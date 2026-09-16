-- =====================================================================
-- TAREA 26 -- EVALUACION: ¿el riesgo de cobranza corta las curvas de STOCK?
-- Solo evaluacion (pedido del usuario 2026-09-15): no toca el motor ni las
-- matrices vigentes. Replica tarea24_v2_matriz_stock.sql solo con la definicion
-- v2 (mora 1-30 el DIA 1; saldo de la foto del ultimo dia del mes anterior;
-- tramo por la mora del dia 1), arrastre fuera, reenganches incluidos (el
-- cierre por reenganche no cuenta como pago), y agrega el modelo de cobranza de
-- la cuota vigente el dia 1 (seg_cob, riesgo_cob; ver tarea26_riesgo_matriz_nuevos.sql).
-- d1 queda como dimension: S2 calibra la curva de stock SIN la cohorte d1.
--
-- Grano: (periodo_meta, tramo, avance_band, d1, seg_cob, riesgo_cob, tipo, dia)
--   tipo = 'base' (dia = -1): saldo y creditos de la poblacion del dia 1
--   tipo = 'act'            : saldo completo el dia del PRIMER pago del mes
--   tipo = 'reb'            : rebaje del dia
-- Ventana: periodo_meta 202501-202608.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, prestamos as (
  select b.id_ihfintech_loan as id_loan, b.amountfinanced
  from dts_okaapi_loans b
  left join loan_chain lc on lc.id_ihfintech_loan = b.id_ihfintech_loan
  where b.status in ('ACTIVE','COMPLETED') and b.amountfinanced > 0
)
, cierre_refin as (
  select _datos_adicionales_loan_accounts_id_ihfintech as id_loan, min(fechaproceso) as f_cierre
  from dts_mambu_loans_hist
  where accountsubstate in ('REFINANCED', 'RESCHEDULED') and fechaproceso >= '20241225'
  group by 1
)
, mambu_dedup as (
  select a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20241225' and '20260901'
)
, fotos as (
  select substr(d.fechaproceso, 1, 6) as periodo, d.fechaproceso
  , cast(substr(d.fechaproceso, 7, 2) as int) as dia
  , d.id_loan, d.saldo, p.amountfinanced
  , lag(d.saldo) over (partition by d.id_loan order by d.fechaproceso) as saldo_ant
  , case when cr.f_cierre is not null and d.fechaproceso >= cr.f_cierre then 1 else 0 end as post_refin
  from mambu_dedup d
  join prestamos p on p.id_loan = d.id_loan
  left join cierre_refin cr on cr.id_loan = d.id_loan
  where d.rn_dedup = 1
)
, dac as (
  select c.id_ihfintech_loan as id_loan, c.fecha_calendario as fecha
  , coalesce(c.dias_atraso_cuota, 0) as mora, c.dni, c.id_loan_nro_cuota as cuota
  from dts_cobranza_creditos_calendario_diario c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  where c.fecha_calendario between date '2025-01-01' and date '2026-08-01'
    and day(c.fecha_calendario) = 1
)
, dni_mora30 as (
  select distinct c.fecha_calendario as fecha, c.dni
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date '2025-01-01' and date '2026-08-01'
    and day(c.fecha_calendario) = 1 and c.dias_atraso_cuota > 30 and c.dni is not null
)
, modelo as (
  select id_loan_nro_cuota as cuota
  , max(segmento_modelo_cobranza) as seg_cob
  , max(prediccion_riesgo_modelo_cobranza) as riesgo_cob
  from dts_cobranza_creditos_cuotas group by 1
)
, stock as (
  select c.fecha as dia1, c.id_loan, c.mora, case when c.mora = 1 then 1 else 0 end as d1, c.dni, c.cuota
  , f.saldo as saldo_inicial, f.amountfinanced
  from dac c
  join fotos f on f.id_loan = c.id_loan
    and f.fechaproceso = date_format(date_add('day', -1, c.fecha), '%Y%m%d')
  where c.mora between 1 and 30 and f.saldo > 0
)
, stock_seg as (
  select date_format(s.dia1, '%Y%m') as periodo_meta, s.id_loan, s.saldo_inicial, s.d1
  , case when s.mora between 1 and 8 then 'a. 1-8' when s.mora between 9 and 15 then 'b. 9-15'
         else 'c. 16-30' end as tramo
  , case when s.saldo_inicial >= 0.9*s.amountfinanced then 'a. avance <10%'
         when s.saldo_inicial >= 0.6*s.amountfinanced then 'b. avance 10-40%'
         when s.saldo_inicial >= 0.3*s.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  , coalesce(mo.seg_cob, 'sin puntaje') as seg_cob
  , coalesce(mo.riesgo_cob, 'sin puntaje') as riesgo_cob
  from stock s
  left join dni_mora30 m on m.fecha = s.dia1 and m.dni = s.dni
  left join modelo mo on mo.cuota = s.cuota
  where m.dni is null
)
, obs as (
  select s.periodo_meta, s.tramo, s.avance_band, s.d1, s.seg_cob, s.riesgo_cob
  , s.id_loan, s.saldo_inicial, f.dia
  , case when f.post_refin = 0 and f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from stock_seg s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
)
, primer_pago as (
  select periodo_meta, tramo, avance_band, d1, seg_cob, riesgo_cob, id_loan, saldo_inicial, min(dia) as dia
  from obs where rebaje > 0
  group by 1, 2, 3, 4, 5, 6, 7, 8
)
select 'base' as tipo, periodo_meta, tramo, avance_band, d1, seg_cob, riesgo_cob, -1 as dia
, round(sum(saldo_inicial), 2) as saldo, count(*) as creditos
from stock_seg group by 1, 2, 3, 4, 5, 6, 7, 8
union all
select 'act', periodo_meta, tramo, avance_band, d1, seg_cob, riesgo_cob, dia
, round(sum(saldo_inicial), 2), count(*)
from primer_pago group by 1, 2, 3, 4, 5, 6, 7, 8
union all
select 'reb', periodo_meta, tramo, avance_band, d1, seg_cob, riesgo_cob, dia
, round(sum(rebaje), 2), count(*)
from obs where rebaje > 0 group by 1, 2, 3, 4, 5, 6, 7, 8
order by 2, 3, 4, 5, 6, 7, 1, 8
;

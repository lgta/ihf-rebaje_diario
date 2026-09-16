-- =====================================================================
-- TAREA 26 -- EVALUACION: ¿el riesgo de cobranza corta las curvas de NUEVOS?
-- Solo evaluacion (pedido del usuario 2026-09-15): no toca el motor ni las
-- matrices vigentes. Replica tarea24_v2_matriz_nuevos.sql filtrada al universo
-- de la curva v2 (st_v2 = 0, entrada distinta del dia 1, arrastre fuera,
-- reenganches incluidos como motor_v2.REENG = True) y agrega el modelo de
-- cobranza de la cuota que entra en mora:
--   seg_cob    = segmento_modelo_cobranza          (MAX_DIASMORA 1-4 / 5-16 / +16)
--   riesgo_cob = prediccion_riesgo_modelo_cobranza (Riesgo Bajo / Medio / Alto)
-- de dts_cobranza_creditos_cuotas, por id_loan_nro_cuota de la cuota vigente el
-- dia de la entrada (calendario_diario). El puntaje se guarda por cuota (varia
-- entre cuotas del mismo credito en ~35% de los creditos) y existe tambien en
-- cuotas pagadas a tiempo: se asigna alrededor del vencimiento, no despues de la
-- mora. No se pudo verificar contra una foto historica que no se re-escriba.
--
-- Grano: (periodo_entrada, avance_band, seg_cob, riesgo_cob, tipo, k)
--   tipo = 'base' (k = -1): saldo de entrada y creditos de la cohorte
--   tipo = 'act'          : saldo de entrada por dia (desde la entrada) del PRIMER pago
--   tipo = 'reb'          : rebaje del dia, max(saldo_ant - saldo, 0)
-- Ventana: entradas 20250102-20260731 (todas con sus 31 dias de fotos al 1-sep).
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
  select d.id_loan, d.fechaproceso, d.saldo, p.amountfinanced
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
  where c.fecha_calendario between date '2024-12-01' and date '2026-07-31'
)
, dac_lag as (
  select id_loan, fecha, mora, dni, cuota
  , lag(mora) over (partition by id_loan order by fecha) as mora_ant
  , row_number() over (partition by id_loan order by fecha) as nro_foto
  from dac
)
, st_v2 as (
  select id_loan, fecha as mes from dac where day(fecha) = 1 and mora between 1 and 30
)
, dni_mora30 as (
  select distinct c.fecha_calendario as fecha, c.dni
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date '2025-01-01' and date '2026-07-31'
    and c.dias_atraso_cuota > 30 and c.dni is not null
)
, modelo as (
  select id_loan_nro_cuota as cuota
  , max(segmento_modelo_cobranza) as seg_cob
  , max(prediccion_riesgo_modelo_cobranza) as riesgo_cob
  from dts_cobranza_creditos_cuotas group by 1
)
, entradas as (
  select id_loan, fecha as fecha_entrada, dni, cuota
  from dac_lag
  where nro_foto > 1 and mora_ant = 0 and mora = 1
    and fecha between date '2025-01-02' and date '2026-07-31' and day(fecha) <> 1
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada
  , coalesce(f.saldo_ant, f.saldo) as saldo_entrada
  , case when coalesce(f.saldo_ant, f.saldo) >= 0.9*f.amountfinanced then 'a. avance <10%'
         when coalesce(f.saldo_ant, f.saldo) >= 0.6*f.amountfinanced then 'b. avance 10-40%'
         when coalesce(f.saldo_ant, f.saldo) >= 0.3*f.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  , coalesce(mo.seg_cob, 'sin puntaje') as seg_cob
  , coalesce(mo.riesgo_cob, 'sin puntaje') as riesgo_cob
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.fechaproceso = date_format(e.fecha_entrada, '%Y%m%d')
  left join st_v2 s2 on s2.id_loan = e.id_loan and s2.mes = date_trunc('month', e.fecha_entrada)
  left join dni_mora30 m on m.fecha = e.fecha_entrada and m.dni = e.dni
  left join modelo mo on mo.cuota = e.cuota
  where coalesce(f.saldo_ant, f.saldo) > 0 and s2.id_loan is null and m.dni is null
)
, obs as (
  select e.id_loan, e.fecha_entrada, e.avance_band, e.seg_cob, e.riesgo_cob, e.saldo_entrada
  , date_diff('day', e.fecha_entrada, date(date_parse(f.fechaproceso, '%Y%m%d'))) as k
  , case when f.post_refin = 0 and f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from entradas_saldo e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso >= date_format(e.fecha_entrada, '%Y%m%d')
    and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada), '%Y%m%d')
)
, primer_pago as (
  select id_loan, fecha_entrada, avance_band, seg_cob, riesgo_cob, saldo_entrada, min(k) as k
  from obs where rebaje > 0
  group by 1, 2, 3, 4, 5, 6
)
select 'base' as tipo, date_format(fecha_entrada, '%Y%m') as periodo, avance_band, seg_cob, riesgo_cob
, -1 as k, round(sum(saldo_entrada), 2) as saldo, count(*) as creditos
from entradas_saldo group by 1, 2, 3, 4, 5, 6
union all
select 'act', date_format(fecha_entrada, '%Y%m'), avance_band, seg_cob, riesgo_cob, k
, round(sum(saldo_entrada), 2), count(*)
from primer_pago group by 1, 2, 3, 4, 5, 6
union all
select 'reb', date_format(fecha_entrada, '%Y%m'), avance_band, seg_cob, riesgo_cob, k
, round(sum(rebaje), 2), count(*)
from obs where rebaje > 0 group by 1, 2, 3, 4, 5, 6
order by 2, 3, 4, 5, 1, 6
;

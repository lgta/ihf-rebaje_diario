-- =====================================================================
-- TAREA 24 -- MATRIZ CRUDA DE STOCK CON LA DEFINICION NUEVA DE ANTIGUO
-- (v2 = en mora 1-30 el DIA 1 del mes), activacion Y rebaje en una corrida.
--
-- Reemplaza, para la recalibracion de tarea 24, a tarea19_curva_cruda_stock.sql
-- (alfa) y tarea19_curva_cruda_stock_rebaje.sql (recupero). Grano minimo:
--
--   (definicion, periodo_meta, tramo, avance_band, d1, arrastre, reeng, dia)
--
--   tipo = 'base' (dia = -1) : saldo y creditos de la poblacion
--   tipo = 'act'             : saldo COMPLETO del credito el dia de su PRIMER
--                              pago del mes (Enfoque alfa)
--   tipo = 'reb'             : suma de max(saldo_ant - saldo, 0) del dia
--                              (Recupero oficial)
--
-- LAS DOS DEFINICIONES EN LA MISMA CORRIDA (columna `definicion`):
--   v1 = dias_atraso_cuota 1-30 en la ULTIMA fila del mes anterior; saldo de
--        esa foto. Tramo por esa mora. Es la de produccion (tarea19_*) y sirve
--        de CONTROL: filtrada a reeng = 0 tiene que reproducir
--        datos_tarea19/curva_cruda_stock*.csv (salvo la re-expresion de Mambu,
--        -0.3% a -0.8%).
--   v2 = dias_atraso_cuota 1-30 el DIA 1 del mes; saldo de la foto del ultimo
--        dia del mes anterior (con el que amanece el dia 1). Tramo por la mora
--        del dia 1 -- la vista usa dias_mora de la fecha de anclaje. Cuadrada
--        contra la vista para septiembre: +0.5% (tarea24_reconcilia_antiguos_sep_v2.sql).
-- Que las dos salgan de la misma foto de Mambu es lo que hace limpia la
-- comparacion v1 vs. v2 del backtest.
--
-- DIMENSIONES NUEVAS:
--   d1       1 = mora exactamente 1 el dia 1: entro en mora ese mismo dia
--            (cuota vencida el ultimo dia del mes anterior). Es la cohorte que
--            "se comporta como nueva" (PENDIENTES tarea 24). Siempre 0 en v1.
--   arrastre 1 = el DNI tiene otro credito con dias_atraso_cuota > 30 el dia 1
--            (flg_arrastre_dni; reconstruccion validada al 99.9% contra
--            max_dias_mora_dni del negocio, tarea24_validacion_arrastre_dni.sql).
--            La vista los saca de TEMPRANA; aca se marcan, no se borran.
--   reeng    1 = coalesce(flg_last_loan_in_chain, 1) = 0 hoy. Produccion los
--            EXCLUYE; aca entran MARCADOS para poder decidir bug 25 sin volver
--            a Athena.
--
-- REENGANCHES: el cierre por refinanciamiento NO cuenta como pago. Se ignora
-- toda caida de saldo desde f_cierre (primer dia con accountsubstate
-- REFINANCED/RESCHEDULED en Mambu) -- ver tarea24_diag_cierre_refin.sql para
-- donde cae ese salto respecto de f_cierre.
--
-- Ventana: periodo_meta 202501-202608. La curva de stock se calibra con
-- ventana FIJA 202504-202606 (CLAUDE.md); 202601-202608 son ademas los meses
-- de test del backtest, asi que de aca salen tambien stock_pob y real_stock
-- (antes eran dos queries aparte con la misma logica).
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, prestamos as (
  select b.id_ihfintech_loan as id_loan, b.amountfinanced
  , case when coalesce(lc.last_in_chain, 1) = 1 then 0 else 1 end as reeng
  from dts_okaapi_loans b
  left join loan_chain lc on lc.id_ihfintech_loan = b.id_ihfintech_loan
  where b.status in ('ACTIVE','COMPLETED') and b.amountfinanced > 0
)
, cierre_refin as (
  select _datos_adicionales_loan_accounts_id_ihfintech as id_loan, min(fechaproceso) as f_cierre
  from dts_mambu_loans_hist
  where accountsubstate in ('REFINANCED', 'RESCHEDULED')
    and fechaproceso >= '20241125'
  group by 1
)
, mambu_dedup as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20241125' and '20260901'
)
, fotos as (
  select
    substr(d.fechaproceso,1,6)                  as periodo
  , d.fechaproceso
  , cast(substr(d.fechaproceso,7,2) as int)     as dia
  , d.id_loan, d.saldo, p.amountfinanced, p.reeng
  , lag(d.saldo) over (partition by d.id_loan order by d.fechaproceso) as saldo_ant
  , case when cr.f_cierre is not null and d.fechaproceso >= cr.f_cierre then 1 else 0 end as post_refin
  from mambu_dedup d
  join prestamos p on p.id_loan = d.id_loan
  left join cierre_refin cr on cr.id_loan = d.id_loan
  where d.rn_dedup = 1
)
, dac as (
  select c.id_ihfintech_loan as id_loan, c.fecha_calendario as fecha
  , coalesce(c.dias_atraso_cuota, 0) as mora, c.dni
  from dts_cobranza_creditos_calendario_diario c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  where c.fecha_calendario between date '2024-12-01' and date '2026-08-01'
)
, dac_cierre as (
  select id_loan, fecha, mora, dni
  , row_number() over (partition by id_loan, date_trunc('month', fecha) order by fecha desc) as rn
  from dac
  where fecha <= date '2026-07-31'
)
, dni_mora30 as (
  select distinct c.fecha_calendario as fecha, c.dni
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date '2025-01-01' and date '2026-08-01'
    and day(c.fecha_calendario) = 1
    and c.dias_atraso_cuota > 30
    and c.dni is not null
)
, stock as (
  select 'v1' as definicion
  , date_add('month', 1, date_trunc('month', c.fecha)) as dia1
  , c.id_loan, c.mora, 0 as d1, c.dni
  , f.saldo as saldo_inicial, f.amountfinanced, f.reeng
  from dac_cierre c
  join fotos f on f.id_loan = c.id_loan and f.fechaproceso = date_format(c.fecha, '%Y%m%d')
  where c.rn = 1 and c.mora between 1 and 30 and f.saldo > 0

  union all

  select 'v2'
  , c.fecha
  , c.id_loan, c.mora, case when c.mora = 1 then 1 else 0 end, c.dni
  , f.saldo, f.amountfinanced, f.reeng
  from dac c
  join fotos f on f.id_loan = c.id_loan
    and f.fechaproceso = date_format(date_add('day', -1, c.fecha), '%Y%m%d')
  where day(c.fecha) = 1 and c.fecha >= date '2025-01-01'
    and c.mora between 1 and 30 and f.saldo > 0
)
, stock_seg as (
  select s.definicion, date_format(s.dia1, '%Y%m') as periodo_meta, s.id_loan, s.saldo_inicial
  , s.d1, s.reeng
  , case when s.mora between 1 and 8  then 'a. 1-8'
         when s.mora between 9 and 15 then 'b. 9-15'
         else                              'c. 16-30' end as tramo
  , case when s.saldo_inicial >= 0.9*s.amountfinanced then 'a. avance <10%'
         when s.saldo_inicial >= 0.6*s.amountfinanced then 'b. avance 10-40%'
         when s.saldo_inicial >= 0.3*s.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  , case when m.dni is not null then 1 else 0 end as arrastre
  from stock s
  left join dni_mora30 m on m.fecha = s.dia1 and m.dni = s.dni
  where s.dia1 between date '2025-01-01' and date '2026-08-01'
)
, obs as (
  select s.definicion, s.periodo_meta, s.tramo, s.avance_band, s.d1, s.arrastre, s.reeng
  , s.id_loan, s.saldo_inicial, f.dia
  , case when f.post_refin = 0 and f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from stock_seg s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
)
, primer_pago as (
  select definicion, periodo_meta, tramo, avance_band, d1, arrastre, reeng, id_loan, saldo_inicial
  , min(dia) as dia
  from obs where rebaje > 0
  group by 1, 2, 3, 4, 5, 6, 7, 8, 9
)
select 'base' as tipo, definicion, periodo_meta, tramo, avance_band, d1, arrastre, reeng, -1 as dia
, round(sum(saldo_inicial), 2) as saldo, count(*) as creditos
from stock_seg
group by 1, 2, 3, 4, 5, 6, 7, 8, 9

union all

select 'act', definicion, periodo_meta, tramo, avance_band, d1, arrastre, reeng, dia
, round(sum(saldo_inicial), 2), count(*)
from primer_pago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9

union all

select 'reb', definicion, periodo_meta, tramo, avance_band, d1, arrastre, reeng, dia
, round(sum(rebaje), 2), count(*)
from obs where rebaje > 0
group by 1, 2, 3, 4, 5, 6, 7, 8, 9

order by 2, 3, 4, 5, 6, 7, 8, 1, 9
;

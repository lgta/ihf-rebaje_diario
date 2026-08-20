-- =====================================================================
-- BACKTEST DEL ENFOQUE ALFA ("CAPITAL ASEGURADO") SOBRE JUNIO 2026
-- v2: recalibrado 2026-07-14 con la definicion corregida antiguos/nuevos
-- (bug 12, ver enfoque_capital_asegurado.sql). Version original ejecutada
-- 2026-07-13, resultado -4.7% de error total (stock +5.6%, nuevos -8.4%).
--
-- YA NO reutiliza bt_stock_junio.csv (fase3_backtest.sql 3G-1) para la
-- poblacion de stock -- ese archivo ancla al cierre de MAYO (31-may), lo
-- que deja afuera (ni stock ni calendario-de-junio) a los creditos cuya
-- cuota vencio el 31-may y no pagaron: no son mora al cierre de mayo
-- (dayslate=0, vence "hoy") y su vencimiento no cae dentro de junio para
-- el calendario prospectivo -- quedaban en un hueco. BT-ASEG-0 (nueva)
-- reconstruye el stock anclado al DIA 1 de junio, que los recupera.
-- bt_calendario_junio.csv SI se sigue reutilizando -- ya esta bien
-- scopeado a vencimientos DENTRO de junio, no tenia el bug.
--
-- Curvas: usar curva_asegurado_stock_seg.csv / curva_asegurado_nuevos_seg.csv
-- YA RECALIBRADAS con la misma definicion (enfoque_capital_asegurado.sql
-- Q1/Q2), no las viejas -- si no, se vuelve a mezclar poblaciones (bug 10).
-- =====================================================================

-- ---------------------------------------------------------------------
-- BT-ASEG-0. STOCK DE JUNIO (poblacion) = stock de siempre (cierre de
-- mayo) UNION los entrantes del dia 1 de junio (mora=0 el 31-may,
-- mora=1 el 1-jun) -- por tramo x avance. NO se re-ancla TODA la
-- poblacion al dia 1 (eso excluye por accidente a cualquier stock que
-- pague justo ese dia, sesgo de supervivencia verificado -- ver
-- enfoque_capital_asegurado.sql). Reemplaza bt_stock_junio.csv para
-- este enfoque. Resultado en datos_backtest_junio/bt_stock_junio_aseg_v2.csv.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , b.amountfinanced
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20260525' and a.fechaproceso <= '20260610'
)
, cierre_mayo as (
  select *, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260531'
)
, dia1_junio as (
  select *, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260601'
)
, stock_previo as (
  select id_loan, saldo,
    case when mora between 1 and 8 then 'a. 1-8'
         when mora between 9 and 15 then 'b. 9-15'
         else 'c. 16-30' end as tramo,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from cierre_mayo
  where rn = 1 and mora between 1 and 30 and saldo > 0 and amountfinanced > 0
)
, dia1_entrantes as (
  select id_loan, saldo,
    'a. 1-8' as tramo,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from dia1_junio
  where rn = 1 and mora = 1 and saldo > 0 and amountfinanced > 0
)
, stock_junio as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
select tramo, avance_band, count(*) as creditos, round(sum(saldo),2) as saldo_total
from stock_junio
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- BT-ASEG-1. STOCK -- capital real activado por dia, junio 2026.
-- Poblacion: la de BT-ASEG-0 (stock de mayo UNION entrantes de dia 1).
-- Resultado en datos_backtest_junio/bt_real_aseg_stock_v2.csv.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20260501' and a.fechaproceso <= '20260630'
)
, cierre_mayo as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260531'
)
, dia1_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260601'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial from cierre_mayo where rn = 1 and mora between 1 and 30 and saldo > 0
)
, dia1_entrantes as (
  select id_loan, saldo as saldo_inicial from dia1_junio where rn = 1 and mora = 1 and saldo > 0
)
, stock_junio as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
, pagos_junio as (
  select s.id_loan, s.saldo_inicial, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock_junio s
  join fotos f on f.id_loan = s.id_loan
  where f.fechaproceso between '20260601' and '20260630'
)
, primer_pago as (
  select id_loan, saldo_inicial, min(fechaproceso) as fecha_primer_pago
  from pagos_junio
  where pago_flag = 1
  group by 1,2
)
select fecha_primer_pago as fechaproceso, round(sum(saldo_inicial),2) as saldo_activado_dia
from primer_pago
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- BT-ASEG-2. NUEVOS -- capital real activado por dia, junio 2026.
-- Poblacion: creditos que entran en mora (dayslate 0->1) DURANTE junio,
-- EXCLUYENDO el dia 1 (bug 12: esos son stock, ver BT-ASEG-0) y
-- excluyendo el stock_junio_ids. Resultado en
-- datos_backtest_junio/bt_real_aseg_nuevos_v2.csv.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , lag(coalesce(a.dayslate,0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20260601' and a.fechaproceso <= '20260630'
)
, dia1_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos
)
, stock_junio_ids as (
  select id_loan from dia1_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_junio as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260602' and '20260630'  -- bug 12: arranca dia 2, dia 1 es stock (BT-ASEG-0)
    and f.id_loan not in (select id_loan from stock_junio_ids)
)
, pagos as (
  select e.id_loan, e.saldo_entrada, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_junio e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada and f.fechaproceso <= '20260630'
)
, primer_pago as (
  select id_loan, saldo_entrada, min(fechaproceso) as fecha_primer_pago
  from pagos
  where pago_flag = 1
  group by 1,2
)
select fecha_primer_pago as fechaproceso, round(sum(saldo_entrada),2) as saldo_activado_dia
from primer_pago
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- BT-ASEG-3. CAPA FANTASMA -- real por dia, junio 2026 (adoptada en
-- produccion 2026-08-20, ver Q3 de enfoque_capital_asegurado.sql y
-- reconciliacion_vw_seguimiento_temprana.md paso 2/3). Creditos con cuota
-- vencida en junio pagada exactamente 1 dia tarde, dayslate nunca la vio,
-- no en stock (BT-ASEG-0) ni en entradas reales (BT-ASEG-2). Saldo =
-- balance del credito el dia de vencimiento (antes del pago), atribuido
-- al dia de pago (vencimiento+1). Resultado en
-- datos_backtest_junio/bt_real_fantasma_nuevos_junio.csv.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260501' and '20260630'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso order by lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    d.fechaproceso, d.id_loan, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, fotos_con_lag as (
  select id_loan, fechaproceso, saldo, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
  where fechaproceso between '20260601' and '20260630'
)
, dia1_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos
  where fechaproceso between '20260601' and '20260630'
)
, stock_junio_ids as (
  select id_loan from dia1_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_reales_junio as (
  select distinct id_loan
  from fotos_con_lag
  where mora_ant = 0 and mora = 1
)
, cuotas_1dia_tarde_junio as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , date_add('day', 1, c.fechavencimiento) as fecha_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2026-06-01') and c.fechavencimiento <= date('2026-06-30')
    and c.installmentstate = 'PAID'
    and c.dias_vencimiento_a_pago = 1
)
, fantasma_junio as (
  select cu.id_loan, cu.fechavencimiento, cu.fecha_pago
  from cuotas_1dia_tarde_junio cu
  where cu.id_loan not in (select id_loan from stock_junio_ids)
    and cu.id_loan not in (select id_loan from entradas_reales_junio)
)
, con_saldo as (
  select f.id_loan, f.fecha_pago, fo.saldo as saldo_al_vencimiento
  from fantasma_junio f
  join fotos fo on fo.id_loan = f.id_loan
   and fo.fechaproceso = replace(cast(f.fechavencimiento as varchar),'-','')
)
select date_format(fecha_pago,'%Y%m%d') as fechaproceso
, round(sum(saldo_al_vencimiento),2) as saldo_activado_dia
, count(*) as creditos
from con_saldo
group by 1
order by 1
;

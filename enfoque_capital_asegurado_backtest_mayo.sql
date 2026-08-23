-- =====================================================================
-- BACKTEST DEL ENFOQUE ALFA ("CAPITAL ASEGURADO") SOBRE MAYO 2026
-- Ejecutado 2026-08-22, tercer mes cerrado del backtest (tarea 9 de
-- PENDIENTES.md -- extender el backtest a mas meses cerrados). Mismo
-- patron EXACTO que enfoque_capital_asegurado_backtest.sql (junio), solo
-- corrido un mes atras (anclado abril->mayo en vez de mayo->junio).
--
-- Resultado (backtest_capital_asegurado_mayo.py, curvas de PRODUCCION
-- actuales sin cambios): Proyectado S/13,579,128 vs. Real S/14,697,936 --
-- error total -7.6% (stock -0.8%, nuevos -14.9%, fantasma -1.5%). Signo
-- OPUESTO y mayor magnitud que junio (+2.65%) y julio (+2.17%) -- ver
-- SEGUIMIENTO.md para la fila completa y BUGS.md para la interpretacion.
--
-- OJO -- las curvas usadas (curva_asegurado_stock_seg.csv/curva_asegurado_
-- nuevos_seg.csv) siguen calibradas sobre periodo_meta '202504'-'202606',
-- que INCLUYE mayo 2026 en su propia calibracion -- no es estrictamente
-- fuera de muestra para este mes. Ver tarea 10 de PENDIENTES.md (recalibrar
-- curvas excluyendo los 3 meses de backtest), pendiente aparte.
-- =====================================================================

-- ---------------------------------------------------------------------
-- BT-ASEG-MAY-CAL. Calendario real de vencimientos de mayo (saldo en
-- riesgo por avance_band), excluyendo el stock de mayo (cierre de abril).
-- Mismo patron que fase3_backtest.sql 3G-2 / bt_calendario_junio.csv.
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos_abr as (
select
  a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, a.balances_principalbalance as saldo
, coalesce(a.dayslate, 0) as mora
, row_number() over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso desc) as rn
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso >= '20260401' and a.fechaproceso <= '20260430'
)
, stock_mayo_ids as (
select id_loan from fotos_abr where rn=1 and mora between 1 and 30 and saldo > 0
)
select
  c.fechavencimiento
, case when f.balances_principalbalance >= 0.9*b.amountfinanced then 'a. avance <10%'
       when f.balances_principalbalance >= 0.6*b.amountfinanced then 'b. avance 10-40%'
       when f.balances_principalbalance >= 0.3*b.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, count(distinct c.id_ihfintech_loan) as creditos
, round(sum(f.balances_principalbalance),0) as saldo_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
join dts_mambu_loans_hist f
  on f._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
 and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
where c.status in ('ACTIVE','COMPLETED')
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento >= date('2026-05-01')
  and c.fechavencimiento <= date('2026-05-31')
  and b.amountfinanced > 0
  and c.id_ihfintech_loan not in (select id_loan from stock_mayo_ids)
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- BT-ASEG-MAY-0. STOCK DE MAYO (poblacion) = stock de siempre (cierre de
-- abril) UNION los entrantes del dia 1 de mayo. Por tramo x avance.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw_mambu as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.dayslate
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso >= '20260425' and a.fechaproceso <= '20260510'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw_mambu
)
, fotos as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.amountfinanced
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_abril as (
  select *, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260430'
)
, dia1_mayo as (
  select *, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260501'
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
  from cierre_abril
  where rn = 1 and mora between 1 and 30 and saldo > 0 and amountfinanced > 0
)
, dia1_entrantes as (
  select id_loan, saldo,
    'a. 1-8' as tramo,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from dia1_mayo
  where rn = 1 and mora = 1 and saldo > 0 and amountfinanced > 0
)
, stock_mayo as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
select tramo, avance_band, count(*) as creditos, round(sum(saldo),2) as saldo_total
from stock_mayo
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- BT-ASEG-MAY-1. STOCK -- capital real activado por dia, mayo 2026.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw_mambu as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.dayslate
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso >= '20260401' and a.fechaproceso <= '20260531'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw_mambu
)
, fotos as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  , lag(d.saldo) over (partition by d.id_loan order by d.fechaproceso) as saldo_ant
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_abril as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260430'
)
, dia1_mayo as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260501'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial from cierre_abril where rn = 1 and mora between 1 and 30 and saldo > 0
)
, dia1_entrantes as (
  select id_loan, saldo as saldo_inicial from dia1_mayo where rn = 1 and mora = 1 and saldo > 0
)
, stock_mayo as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
, pagos_mayo as (
  select s.id_loan, s.saldo_inicial, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock_mayo s
  join fotos f on f.id_loan = s.id_loan
  where f.fechaproceso between '20260501' and '20260531'
)
, primer_pago as (
  select id_loan, saldo_inicial, min(fechaproceso) as fecha_primer_pago
  from pagos_mayo
  where pago_flag = 1
  group by 1,2
)
select fecha_primer_pago as fechaproceso, round(sum(saldo_inicial),2) as saldo_activado_dia
from primer_pago
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- BT-ASEG-MAY-2. NUEVOS -- capital real activado por dia, mayo 2026.
-- Poblacion: dayslate 0->1 durante mayo, EXCLUYENDO el dia 1 (bug 12).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw_mambu as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.dayslate
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso >= '20260501' and a.fechaproceso <= '20260531'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw_mambu
)
, fotos as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  , lag(coalesce(d.dayslate,0)) over (
      partition by d.id_loan order by d.fechaproceso) as mora_ant
  , lag(d.saldo) over (
      partition by d.id_loan order by d.fechaproceso) as saldo_ant
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, dia1_mayo as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos
)
, stock_mayo_ids as (
  select id_loan from dia1_mayo where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_mayo as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260502' and '20260531'
    and f.id_loan not in (select id_loan from stock_mayo_ids)
)
, pagos as (
  select e.id_loan, e.saldo_entrada, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_mayo e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada and f.fechaproceso <= '20260531'
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
-- BT-ASEG-MAY-3. CAPA FANTASMA -- real por dia, mayo 2026. Cuotas vencidas
-- entre 30-abr y 30-may pagadas exactamente 1 dia tarde, fecha_pago dentro
-- de mayo (fix de frontera de mes, bug 14).
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
  where a.fechaproceso between '20260401' and '20260531'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
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
  where fechaproceso between '20260501' and '20260531'
)
, dia1_mayo as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos
  where fechaproceso between '20260501' and '20260531'
)
, stock_mayo_ids as (
  select id_loan from dia1_mayo where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_reales_mayo as (
  select distinct id_loan
  from fotos_con_lag
  where mora_ant = 0 and mora = 1
)
, cuotas_1dia_tarde_mayo as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , date_add('day', 1, c.fechavencimiento) as fecha_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and date_add('day', 1, c.fechavencimiento) >= date('2026-05-01')
    and date_add('day', 1, c.fechavencimiento) <= date('2026-05-31')
    and c.installmentstate = 'PAID'
    and c.dias_vencimiento_a_pago = 1
)
, fantasma_mayo as (
  select cu.id_loan, cu.fechavencimiento, cu.fecha_pago
  from cuotas_1dia_tarde_mayo cu
  where cu.id_loan not in (select id_loan from stock_mayo_ids)
    and cu.id_loan not in (select id_loan from entradas_reales_mayo)
)
, con_saldo as (
  select f.id_loan, f.fecha_pago, fo.saldo as saldo_al_vencimiento
  from fantasma_mayo f
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

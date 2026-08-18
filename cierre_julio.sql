-- =====================================================================
-- CIERRE DE JULIO 2026 -- real final (mes completo, cerrado) vs.
-- proyectado, para los 2 enfoques vigentes. Ejecutado 2026-08-18.
--
-- Julio ya esta completo (hoy es 18-ago) -- a diferencia del tracking en
-- vivo (avance_capital_asegurado_julio_diario.sql / meta_julio.py, que
-- solo llegaban a un corte parcial), esto agrega el mes ENTERO de una
-- sola vez, mismo patron que un backtest (enfoque_capital_asegurado_
-- backtest.sql / fase3_backtest.sql) pero anclado a junio->julio en vez
-- de mayo->junio.
--
-- Los PROYECTADOS ya estaban calculados (no cambian, dependen solo de
-- poblacion+calendario+curvas, todo ya fijo desde el corte 13-jul):
--   Capital asegurado: S/10,306,231 (stock S/3,105,418 + nuevos S/7,200,813)
--   Recupero oficial:  S/1,776,174  (stock S/426,651   + nuevos S/1,349,523)
-- Esta query solo calcula el REAL final para comparar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- J1. CAPITAL ASEGURADO -- STOCK real (mes completo). Poblacion = mora
-- 1-30 al cierre de junio UNION entrantes del dia 1 de julio (bug 12).
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
    and a.fechaproceso between '20260625' and '20260731'
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, dia1_julio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260701'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, dia1_entrantes as (
  select id_loan, saldo as saldo_inicial from dia1_julio where rn = 1 and mora = 1 and saldo > 0
)
, stock_julio as (
  select * from stock_previo union all select * from dia1_entrantes
)
, activacion as (
  select s.id_loan, s.saldo_inicial,
    max(case when f.saldo_ant > f.saldo then 1 else 0 end) as activado
  from stock_julio s
  join fotos f on f.id_loan = s.id_loan and f.fechaproceso between '20260701' and '20260731'
  group by 1,2
)
select
  'ASEG_STOCK' as bloque
, count(*) as creditos_total, round(sum(saldo_inicial),2) as saldo_total
, sum(activado) as creditos_activados, round(sum(saldo_inicial*activado),2) as saldo_asegurado_real
from activacion
;

-- ---------------------------------------------------------------------
-- J2. CAPITAL ASEGURADO -- NUEVOS real (mes completo). Entradas dayslate
-- 0->1 desde el dia 2 de julio (bug 12: dia 1 = stock, ver J1),
-- excluyendo stock.
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
    and a.fechaproceso between '20260601' and '20260731'
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio_ids as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260731'
    and f.id_loan not in (select id_loan from stock_julio_ids)
)
, activacion as (
  select e.id_loan, e.saldo_entrada,
    max(case when f.saldo_ant > f.saldo then 1 else 0 end) as activado
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.fechaproceso > e.fecha_entrada and f.fechaproceso <= '20260731'
  group by 1,2
)
select
  'ASEG_NUEVOS' as bloque
, count(*) as creditos_total, round(sum(saldo_entrada),2) as saldo_total
, sum(activado) as creditos_activados, round(sum(saldo_entrada*activado),2) as saldo_asegurado_real
from activacion
;

-- ---------------------------------------------------------------------
-- J3. RECUPERO OFICIAL -- STOCK, rebaje real (mes completo). Poblacion
-- oficial: mora 1-30 al cierre de junio, SIN el ajuste de bug 12 (no
-- aplica a este enfoque, ver BUGS.md bug 12 "Scope").
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
    and a.fechaproceso between '20260625' and '20260731'
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, rebajes as (
  select s.id_loan,
    sum(case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end) as rebaje_credito
  from stock_previo s
  join fotos f on f.id_loan = s.id_loan and f.fechaproceso between '20260701' and '20260731'
  group by 1
)
select
  'RECUP_STOCK' as bloque
, count(*) as creditos_total, round(sum(saldo_inicial),2) as saldo_total
, round(sum(rebaje_credito),2) as rebaje_real
from stock_previo s
join rebajes r on r.id_loan = s.id_loan
;

-- ---------------------------------------------------------------------
-- J4. RECUPERO OFICIAL -- NUEVOS, rebaje real (mes completo). Entradas
-- dayslate 0->1 durante TODO julio (incluye dia 1, sin ajuste bug 12).
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
    and a.fechaproceso between '20260601' and '20260731'
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio_ids as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas as (
  select f.id_loan, f.fechaproceso as fecha_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260701' and '20260731'
    and f.id_loan not in (select id_loan from stock_julio_ids)
)
, rebajes as (
  select e.id_loan,
    sum(case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end) as rebaje_credito
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.fechaproceso >= e.fecha_entrada and f.fechaproceso <= '20260731'
  group by 1
)
select
  'RECUP_NUEVOS' as bloque
, count(*) as creditos_total
, round(sum(rebaje_credito),2) as rebaje_real
from rebajes
;

-- =====================================================================
-- TAREA 18d -- REAL DIARIO DE AGOSTO 2026, ENFOQUE RECUPERO OFICIAL
-- (rebaje en soles, dayslate -- NO migrado a dias_atraso_cuota, ver
-- decision 18e). Refresca REAL_STOCK_A_HOY/REAL_NUEVOS_A_HOY de
-- meta_agosto.py, que estaban hardcodeados y congelados al 20-ago.
--
-- Mismo patron que fase3_backtest.sql (3G-1/3G-3/3G-4) y
-- fase1_stock.sql/fase2_nuevos.sql: stock = mora 1-30 al cierre de
-- julio, nuevos = mora_ant=0 -> mora=1 durante agosto. Rebaje =
-- max(saldo_ant - saldo, 0), NO activacion binaria (eso es el concepto
-- del Enfoque alfa, no de este).
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    substr(a.fechaproceso,1,6) as periodo
  , a.fechaproceso
  , cast(substr(a.fechaproceso,7,2) as int) as dia
  , a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate, 0) as mora
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  , lag(coalesce(a.dayslate, 0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso between '20260701' and '20260901'
)
, cierre_julio as (
  select *, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where periodo = '202607'
)
, stock_ids as (
  select id_loan, saldo as saldo_inicial
  from cierre_julio
  where rn = 1 and mora between 1 and 30 and saldo > 0
)
, real_stock as (
  select 'stock' as componente, f.dia, sum(case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end) as rebaje_dia
  from fotos f
  join stock_ids s on s.id_loan = f.id_loan
  where f.periodo = '202608'
  group by 1, 2
)
, entradas as (
  select id_loan, fechaproceso as fecha_entrada
  from fotos
  where periodo = '202608' and mora_ant = 0 and mora = 1
    and id_loan not in (select id_loan from stock_ids)
)
, real_nuevos as (
  select 'nuevos' as componente, f.dia, sum(case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end) as rebaje_dia
  from fotos f
  join entradas e on e.id_loan = f.id_loan and f.fechaproceso >= e.fecha_entrada
  where f.periodo = '202608'
  group by 1, 2
)
select componente, dia, round(rebaje_dia, 2) as rebaje_dia
from (select * from real_stock union all select * from real_nuevos)
order by 1, 2
;

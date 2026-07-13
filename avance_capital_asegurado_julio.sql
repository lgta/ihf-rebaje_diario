-- =====================================================================
-- TRACKING EN VIVO DE CAPITAL ASEGURADO -- JULIO 2026 (meta principal
-- desde 2026-07-13). Mismo patron que enfoque_capital_asegurado_backtest.sql
-- (backtest de junio), adaptado a julio: stock anclado al cierre REAL de
-- junio (misma poblacion que meta_julio.py / datos_meta_julio/), capital
-- REAL activado dia a dia desde el 1-jul hasta la ultima fecha disponible
-- en dts_mambu_loans_hist a la corrida. Ver enfoque_capital_asegurado.md,
-- seccion "Tracking en vivo".
--
-- Reutiliza poblacion/calendario YA CACHEADOS de datos_meta_julio/
-- (stock_julio_seg.csv, jul_calendario.csv) y las curvas YA CALIBRADAS de
-- datos_capital_asegurado/. Lo unico nuevo son las dos queries de abajo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- JUL-ASEG-1. STOCK -- capital real activado por dia, julio 2026.
-- Poblacion: stock al cierre de junio (mora 1-30), igual criterio que
-- meta_julio.py / fase1_stock.sql. Ajustar '20260713' a la fecha de
-- corte vigente en cada corrida. Resultado en
-- datos_avance_capital_asegurado_julio/jul_aseg_real_stock.csv.
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
    and a.fechaproceso >= '20260601' and a.fechaproceso <= '20260713'
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio as (
  select id_loan, saldo as saldo_inicial
  from cierre_junio
  where rn = 1 and mora between 1 and 30 and saldo > 0
)
, pagos_julio as (
  select s.id_loan, s.saldo_inicial, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock_julio s
  join fotos f on f.id_loan = s.id_loan
  where f.fechaproceso between '20260701' and '20260713'
)
, primer_pago as (
  select id_loan, saldo_inicial, min(fechaproceso) as fecha_primer_pago
  from pagos_julio
  where pago_flag = 1
  group by 1,2
)
select fecha_primer_pago as fechaproceso, round(sum(saldo_inicial),2) as saldo_activado_dia
from primer_pago
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- JUL-ASEG-2. NUEVOS -- capital real activado por dia, julio 2026.
-- Poblacion: creditos que entran en mora (dayslate 0->1) DURANTE julio,
-- excluyendo el stock_julio_ids. Resultado en
-- datos_avance_capital_asegurado_julio/jul_aseg_real_nuevos.csv.
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
    and a.fechaproceso >= '20260601' and a.fechaproceso <= '20260713'
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio_ids as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_julio as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260701' and '20260713'
    and f.id_loan not in (select id_loan from stock_julio_ids)
)
, pagos as (
  select e.id_loan, e.saldo_entrada, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_julio e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada and f.fechaproceso <= '20260713'
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

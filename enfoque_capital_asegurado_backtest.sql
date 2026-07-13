-- =====================================================================
-- BACKTEST DEL ENFOQUE ALFA ("CAPITAL ASEGURADO") SOBRE JUNIO 2026
-- Ejecutado 2026-07-13. Resultado: -4.7% de error total (stock +5.6%,
-- nuevos -8.4%) -- ver enfoque_capital_asegurado.md, seccion "Backtest".
--
-- Reutiliza poblacion/calendario YA CACHEADOS de datos_backtest_junio/
-- (bt_stock_junio.csv, bt_calendario_junio.csv -- vienen de
-- fase3_backtest.sql 3G-1/3G-2, no dependen de la metrica) y las curvas
-- YA CALIBRADAS de datos_capital_asegurado/ (enfoque_capital_asegurado.sql
-- Q1/Q2). Lo unico nuevo son las dos queries de abajo: capital REAL
-- activado (primer pago) por dia de junio, poblacion stock y nuevos --
-- mismo criterio pago_flag/primer_pago que enfoque_capital_asegurado.sql,
-- pero con fechas de calendario reales en vez de dia relativo de curva.
-- =====================================================================

-- ---------------------------------------------------------------------
-- BT-ASEG-1. STOCK -- capital real activado por dia, junio 2026.
-- Poblacion: mismo stock_junio (mora 1-30 al cierre de mayo) que
-- fase3_backtest.sql 3G-1/bt_stock_junio.csv. Resultado en
-- datos_backtest_junio/bt_real_aseg_stock.csv.
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
, stock_junio as (
  select id_loan, saldo as saldo_inicial
  from cierre_mayo
  where rn = 1 and mora between 1 and 30 and saldo > 0
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
-- excluyendo el stock_junio_ids (mismo criterio que 3G-4). Resultado en
-- datos_backtest_junio/bt_real_aseg_nuevos.csv.
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
    and a.fechaproceso >= '20260501' and a.fechaproceso <= '20260630'
)
, cierre_mayo as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260531'
)
, stock_junio_ids as (
  select id_loan from cierre_mayo where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_junio as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260601' and '20260630'
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

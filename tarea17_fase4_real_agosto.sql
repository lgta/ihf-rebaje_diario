-- =====================================================================
-- TAREA 17 FASE 4 -- Q-I: REAL ACTIVADO POR DIA, AGOSTO 2026 (mes en
-- curso), universo unificado. Columna `componente` = stock | nuevos.
-- Reemplaza las constantes REAL_STOCK_A_HOY / REAL_NUEVOS_A_HOY /
-- REAL_FANTASMA_A_HOY de meta_agosto_capital_asegurado.py: al salir por
-- dia se puede cortar en cualquier fecha sin re-correr la query.
-- Mismas definiciones que Q-F1/Q-F2 (backtest de meses cerrados).
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_dedup as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260725' and '20260825'
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, fotos as (
  select id_loan, fechaproceso, substr(fechaproceso,1,6) as periodo,
    cast(substr(fechaproceso,7,2) as int) as dia, saldo,
    lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  from mambu_dedup where rn_dedup = 1
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-07-01') and date('2026-08-25')
)
, dac as (
  select d.id_loan, d.fechaproceso, d.mora
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, dac_lag as (
  select id_loan, fechaproceso, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant,
    row_number() over (partition by id_loan order by fechaproceso) as nro_foto
  from dac
)
, stock_ids as (
  select id_loan, saldo_inicial from (
    select d.id_loan, f.saldo as saldo_inicial, d.mora,
      row_number() over (partition by d.id_loan order by d.fechaproceso desc) as rn
    from dac d
    join fotos f on f.id_loan = d.id_loan and f.fechaproceso = d.fechaproceso
    where substr(d.fechaproceso,1,6) = '202607'
  )
  where rn = 1 and mora between 1 and 30 and saldo_inicial > 0
)
, real_stock as (
  select 'stock' as componente, s.id_loan, s.saldo_inicial as saldo, min(f.dia) as dia
  from stock_ids s
  join fotos f on f.id_loan = s.id_loan and f.periodo = '202608'
  where f.saldo_ant > f.saldo
  group by 1,2,3
)
, entradas as (
  select l.id_loan, l.fechaproceso as fecha_entrada
  from dac_lag l
  where l.nro_foto > 1 and l.mora_ant = 0 and l.mora = 1
    and substr(l.fechaproceso,1,6) = '202608'
    and not exists (select 1 from stock_ids s where s.id_loan = l.id_loan)
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada, coalesce(f.saldo_ant, f.saldo) as saldo
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.fechaproceso = e.fecha_entrada
  where coalesce(f.saldo_ant, f.saldo) > 0
)
, real_nuevos as (
  select 'nuevos' as componente, e.id_loan, e.saldo, min(f.dia) as dia
  from entradas_saldo e
  join fotos f on f.id_loan = e.id_loan
    and f.periodo = '202608' and f.fechaproceso >= e.fecha_entrada
  where f.saldo_ant > f.saldo
  group by 1,2,3
)
select componente, dia, count(*) as creditos, round(sum(saldo),2) as saldo_activado_dia
from (select * from real_stock union all select * from real_nuevos)
group by 1,2
order by 1,2
;

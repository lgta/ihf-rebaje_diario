-- =====================================================================
-- TAREA 17, FASE 4 -- Q-F1: REAL ACTIVADO POR DIA, componente STOCK,
-- abr/may/jun/jul 2026. Poblacion = la misma de Q-E (dias_atraso_cuota
-- 1-30 al cierre del mes anterior). Capital activado = saldo COMPLETO
-- del credito el primer dia del mes en que su saldo principal cae
-- (deltas de balances_principalbalance -- regla de CLAUDE.md, nunca
-- principalamountpaid). Reemplaza bt_real_aseg_stock.csv de los 4
-- backtests.
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
  , b.amountfinanced
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260325' and '20260731'
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
  where c.fecha_calendario between date('2026-03-01') and date('2026-06-30')
)
, dac as (
  select d.id_loan, d.fechaproceso, d.mora
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, dac_cierre as (
  select substr(fechaproceso,1,6) as periodo, fechaproceso, id_loan, mora,
    row_number() over (partition by id_loan, substr(fechaproceso,1,6)
                       order by fechaproceso desc) as rn
  from dac
)
, stock as (
  select
    date_format(date_add('month',1,date_parse(c.periodo,'%Y%m')), '%Y%m') as periodo_meta
  , c.id_loan, f.saldo as saldo_inicial
  from dac_cierre c
  join fotos f on f.id_loan = c.id_loan and f.fechaproceso = c.fechaproceso
  where c.rn = 1 and c.mora between 1 and 30 and f.saldo > 0
    and c.periodo between '202603' and '202606'
)
, primer_pago as (
  select s.periodo_meta, s.id_loan, s.saldo_inicial, min(f.dia) as dia_primer_pago
  from stock s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
  where f.saldo_ant > f.saldo
  group by 1,2,3
)
select periodo_meta, dia_primer_pago as dia, round(sum(saldo_inicial),2) as saldo_activado_dia
from primer_pago
group by 1,2
order by 1,2
;

-- =====================================================================
-- TAREA 18e -- TASA DE ENTRADA POR SOLES, DESGLOSE MENSUAL AMPLIADO
-- (202501-202606, 18 meses) -- extiende Fase A (tarea18e_fase_a_tasa_
-- soles.sql, que solo cubria ago2025-may2026 para comparar manzana con
-- manzana contra P_NO_PAGA_DIA0) para poder calibrar la tasa con
-- VENTANA RODANTE [M-12,M-1], igual criterio que 18a/18f ya aplico a la
-- curva de nuevos del Enfoque alfa -- sin esto, la tasa quedaria fija
-- mientras la curva rueda, mezclando dos criterios de calibracion.
--
-- Misma definicion exacta que Fase A: dias_atraso_cuota 0->1, calendario
-- elegible = entrada (fechavencimiento+1) dentro del mes, excluye stock,
-- saldo del credito a la fecha exacta de vencimiento (dedup bug 11).
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2024-12-01') and date('2026-07-10')
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
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from dac
)
, cierre as (
  select substr(fechaproceso,1,6) as periodo, id_loan, mora,
    row_number() over (partition by id_loan, substr(fechaproceso,1,6)
                       order by fechaproceso desc) as rn
  from dac
)
, stock_ids as (
  select date_format(date_add('month',1,date_parse(periodo,'%Y%m')), '%Y%m') as periodo_target
       , id_loan
  from cierre
  where rn = 1 and mora between 1 and 30
)
, saldo_venc as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20241231' and '20260701'
)
, calendario_rn as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , date_format(date_add('day',1,c.fechavencimiento), '%Y%m') as periodo
  , f.saldo
  , row_number() over (
      partition by c.id_ihfintech_loan,
                   date_format(date_add('day',1,c.fechavencimiento), '%Y%m')
      order by c.fechavencimiento) as rn
  from dts_cobranza_creditos_cuotas c
  join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
  join saldo_venc f
    on f.id_loan = c.id_ihfintech_loan
   and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
   and f.rn_dedup = 1
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2024-12-31')
    and c.fechavencimiento <= date('2026-06-30')
    and b.amountfinanced > 0
)
, calendario_mes as (
  select cr.periodo, cr.id_loan, cr.fechavencimiento, cr.saldo
  from calendario_rn cr
  where cr.rn = 1
    and cr.periodo between '202501' and '202606'
    and not exists (
      select 1 from stock_ids s
      where s.periodo_target = cr.periodo and s.id_loan = cr.id_loan
    )
)
, entradas as (
  select distinct substr(fechaproceso,1,6) as periodo, id_loan
  from dac_lag
  where mora_ant = 0 and mora = 1
)
select
  cm.periodo
, count(*)                                                                as elegibles_creditos
, round(sum(cm.saldo), 2)                                                 as elegibles_soles
, sum(case when e.id_loan is not null then 1 else 0 end)                  as entran_creditos
, round(sum(case when e.id_loan is not null then cm.saldo else 0 end), 2) as entran_soles
from calendario_mes cm
left join entradas e on e.periodo = cm.periodo and e.id_loan = cm.id_loan
group by 1
order by 1
;

-- =====================================================================
-- TAREA 17, FASE 4 -- Q-E: POBLACION DE STOCK, abr/may/jun/jul 2026.
-- Stock = dias_atraso_cuota 1-30 al cierre del mes anterior (saldo Mambu
-- de ese dia). SIN el union de `dia1_entrantes` (bug 12): esa cohorte
-- ahora entra por el calendario frontier-adjusted como "nuevos".
-- Reemplaza bt_stock_{mes}_aseg.csv de los 4 backtests.
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
, mambu as (
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
  where a.fechaproceso between '20260325' and '20260630'
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
select
  date_format(date_add('month',1,date_parse(c.periodo,'%Y%m')), '%Y%m') as periodo_meta
, case when c.mora between 1 and 8  then 'a. 1-8'
       when c.mora between 9 and 15 then 'b. 9-15'
       else                              'c. 16-30' end as tramo
, case when f.saldo >= 0.9*f.amountfinanced then 'a. avance <10%'
       when f.saldo >= 0.6*f.amountfinanced then 'b. avance 10-40%'
       when f.saldo >= 0.3*f.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, count(*)                as creditos
, round(sum(f.saldo), 2)  as saldo_total
from dac_cierre c
join mambu f on f.id_loan = c.id_loan and f.fechaproceso = c.fechaproceso and f.rn_dedup = 1
where c.rn = 1 and c.mora between 1 and 30 and f.saldo > 0
  and c.periodo between '202603' and '202606'
group by 1,2,3
order by 1,2,3
;

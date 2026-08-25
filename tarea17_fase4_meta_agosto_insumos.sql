-- =====================================================================
-- TAREA 17 FASE 4 -- Q-G/Q-H: INSUMOS DE LA META UNIFICADA DE AGOSTO 2026
-- (una sola corrida, columna `tipo` distingue stock de calendario).
--
-- STOCK: dias_atraso_cuota entre 1 y 30 al CIERRE DE JULIO (31-jul),
--   saldo Mambu de ese dia. Sin el union de `dia1_entrantes` (bug 12) --
--   esa cohorte entra por el calendario con dia_entrada = 1.
--
-- CALENDARIO PROSPECTIVO: cuotas cuya ENTRADA (fechavencimiento + 1 dia)
--   cae dentro de agosto -- indexado por dia_entrada, no por vencimiento.
--   Incluye la cohorte vencida el 31-jul (dia_entrada = 1), que hoy vive
--   como la constante hardcodeada CUOTAS_31JUL_FANTASMA en
--   meta_agosto_capital_asegurado.py; y EXCLUYE la vencida el 31-ago
--   (entrada 1-sep, pertenece a septiembre).
--
--   `status = 'ACTIVE'` SOLAMENTE -- regla de CLAUDE.md para calendario
--   prospectivo (a diferencia de los backtests de meses cerrados, que
--   usan ACTIVE + COMPLETED).
--
--   Saldo anclado al CIERRE DE JULIO (31-jul) para TODAS las cuotas, no
--   al dia del vencimiento: una meta fijada al inicio del mes no puede
--   conocer el saldo futuro. Convencion unica y reproducible -- misma
--   idea con la que se construyo ago_calendario.csv en su momento.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_jul as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , b.amountfinanced
  , b.status
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260701' and '20260731'
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, ancla as (
  -- ultima foto de julio por credito = saldo de referencia de toda la meta
  select id_loan, saldo, amountfinanced, status,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from mambu_jul where rn_dedup = 1
)
, ancla_final as (
  select id_loan, saldo, amountfinanced, status from ancla where rn = 1 and saldo > 0
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-07-01') and date('2026-07-31')
)
, dac_cierre as (
  select d.id_loan, d.mora,
    row_number() over (partition by d.id_loan order by d.fechaproceso desc) as rn
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, stock_agosto as (
  -- status ACTIVE+COMPLETED (no solo ACTIVE): el stock es una poblacion
  -- MEDIDA a una fecha pasada (cierre de julio), no calendario prospectivo
  -- -- misma regla que los 4 backtests. Un credito en mora el 31-jul que
  -- despues termino de pagar figura hoy como COMPLETED y debe contar.
  select c.id_loan, c.mora, a.saldo, a.amountfinanced
  from dac_cierre c
  join ancla_final a on a.id_loan = c.id_loan
  where c.rn = 1 and c.mora between 1 and 30
    and a.status in ('ACTIVE','COMPLETED')
)
select
  'stock' as tipo
, case when s.mora between 1 and 8  then 'a. 1-8'
       when s.mora between 9 and 15 then 'b. 9-15'
       else                              'c. 16-30' end as tramo
, case when s.saldo >= 0.9*s.amountfinanced then 'a. avance <10%'
       when s.saldo >= 0.6*s.amountfinanced then 'b. avance 10-40%'
       when s.saldo >= 0.3*s.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, 0 as dia_entrada
, count(*) as creditos
, round(sum(s.saldo), 2) as saldo
from stock_agosto s
group by 1,2,3,4

union all

select
  'calendario' as tipo
, '' as tramo
, case when a.saldo >= 0.9*a.amountfinanced then 'a. avance <10%'
       when a.saldo >= 0.6*a.amountfinanced then 'b. avance 10-40%'
       when a.saldo >= 0.3*a.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, cast(day(date_add('day',1,c.fechavencimiento)) as int) as dia_entrada
, count(distinct c.id_ihfintech_loan) as creditos
, round(sum(a.saldo), 2) as saldo
from dts_cobranza_creditos_cuotas c
join ancla_final a on a.id_loan = c.id_ihfintech_loan
where c.status = 'ACTIVE'
  and c.flg_last_loan_in_chain = 1
  and a.status = 'ACTIVE'
  and date_add('day',1,c.fechavencimiento) >= date('2026-08-01')
  and date_add('day',1,c.fechavencimiento) <= date('2026-08-31')
  and c.id_ihfintech_loan not in (select id_loan from stock_agosto)
group by 1,2,3,4
order by 1,4,3
;

-- =====================================================================
-- TAREA 18e -- VALIDACION TECNICA A NIVEL DE CASO: el salto de cobertura
-- (real dias_atraso_cuota = 157% del real dayslate en julio) se explica
-- por la poblacion "fantasma" (dayslate=0 todo el dia, dias_atraso_cuota
-- detecta 0->1 igual) pagando casi instantaneo -- ya medido en agregado
-- por bug 16 Fase 3 (activacion dia 0 = 99.60%). Este chequeo mira 10
-- creditos reales concretos de julio para confirmar que el mecanismo es
-- real (rebaje efectivo, no un artefacto de la query): dayslate se queda
-- en 0 el dia que dias_atraso_cuota marca 1, Y el saldo efectivamente
-- bajo ese mismo dia (columnas saldo_ant/saldo lado a lado).
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
  , coalesce(a.dayslate, 0) as dayslate
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260625' and '20260731'
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, fotos as (
  select id_loan, fechaproceso, saldo, dayslate,
    lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  from mambu_dedup where rn_dedup = 1
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-06-25') and date('2026-07-31')
)
, dac as (
  select d.id_loan, d.fechaproceso, d.mora,
    lag(d.mora) over (partition by d.id_loan order by d.fechaproceso) as mora_ant
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
select
  d.id_loan, d.fechaproceso as fecha_entrada_dac
, f.dayslate as dayslate_ese_dia
, round(f.saldo_ant, 2) as saldo_ant
, round(f.saldo, 2) as saldo
, round(f.saldo_ant - f.saldo, 2) as rebaje_ese_dia
from dac d
join fotos f on f.id_loan = d.id_loan and f.fechaproceso = d.fechaproceso
where d.mora_ant = 0 and d.mora = 1
  and d.fechaproceso between '20260701' and '20260731'
  and f.dayslate = 0          -- dayslate NUNCA lo ve en mora ese dia (poblacion "fantasma")
  and f.saldo_ant > f.saldo   -- Y efectivamente hubo un pago ese mismo dia
order by rebaje_ese_dia desc
limit 10
;

-- =====================================================================
-- TAREAS 15/16 -- casos individuales (no agrupados) detras de
-- tarea15_16_sesgo_gestionado_julio.sql. A pedido del usuario: queries
-- que devuelvan id_ihfintech_loan completo por caso, no solo conteos
-- agregados, para poder revisar antes de decidir sobre recalibracion.
-- Ejecutada 2026-08-24, misma sesion.
-- =====================================================================

with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw_mambu as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.dayslate
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260731'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw_mambu
)
, fotos as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, fotos_lag as (
  select id_loan, fechaproceso, saldo, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
)
, cierre_junio as (
  select id_loan, mora, saldo,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_previo as (
  select id_loan, saldo from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, dia1_julio as (
  select id_loan, mora, saldo,
    row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260701'
)
, dia1_entrantes as (
  select id_loan, saldo from dia1_julio where rn = 1 and mora = 1 and saldo > 0
)
, nuevos_julio as (
  select f.id_loan, f.saldo, f.fechaproceso as fecha_entrada
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260731'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
)
, universo as (
  select id_loan, saldo, 'a. stock' as origen, cast(null as varchar) as fecha_entrada from stock_previo
  union all select id_loan, saldo, 'a. stock', cast(null as varchar) from dia1_entrantes
  union all select id_loan, saldo, 'b. nuevos', fecha_entrada from nuevos_julio
)
, asig as (
  select
    aux02 as id_loan
  , max(case when fase_estrategia = 'TEMPRANA' then 1 else 0 end) as temprana
  , max(case when fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as esp_rec
  , max(case when grupo_control = 'CONTROL' then 1 else 0 end) as es_control
  , array_join(array_distinct(array_agg(fase_estrategia)), '|') as fases_vistas
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-07-01' and '2026-07-31' and aux02 is not null
  group by 1
)
, asegurado as (
  select u.id_loan,
    max(case
          when f.mora = 0
           and f.fechaproceso between '20260701' and '20260731'
           and (u.fecha_entrada is null or f.fechaproceso > u.fecha_entrada)
          then 1 else 0
        end) as tuvo_pago
  , min(case
          when f.mora = 0
           and f.fechaproceso between '20260701' and '20260731'
           and (u.fecha_entrada is null or f.fechaproceso > u.fecha_entrada)
          then f.fechaproceso
        end) as fecha_pago
  from universo u
  join fotos f on f.id_loan = u.id_loan
  group by 1
)
select
  u.id_loan as id_ihfintech_loan
, u.origen
, case
    when a.id_loan is null then '4. no aparece en asignaciones'
    when a.temprana = 1 and a.es_control = 1 then '2. TEMPRANA pero grupo control'
    when a.temprana = 1 then '1. TEMPRANA gestionado'
    when a.esp_rec = 1 then '3. escalado ESPECIALIZADA/RECOVERY'
    else '5. aparece, otra situacion'
  end as situacion_ejecucion
, a.fases_vistas
, round(u.saldo, 2) as saldo
, u.fecha_entrada
, coalesce(ase.tuvo_pago, 0) as asegurado
, ase.fecha_pago
from universo u
left join asig a on a.id_loan = u.id_loan
left join asegurado ase on ase.id_loan = u.id_loan
order by 1, 2
;

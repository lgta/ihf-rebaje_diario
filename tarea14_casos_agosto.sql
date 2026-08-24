-- =====================================================================
-- TAREA 14 -- casos individuales (no agrupados) detras de tarea14_no_
-- aparece_asignaciones.sql. A pedido del usuario: id_ihfintech_loan
-- completo por caso, no solo conteos agregados.
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
  where a.fechaproceso between '20260701' and '20260823'
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
, cierre_julio as (
  select id_loan, mora, saldo,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_previo as (
  select id_loan, saldo from cierre_julio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, dia1_agosto as (
  select id_loan, mora, saldo,
    row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260801'
)
, dia1_entrantes as (
  select id_loan, saldo from dia1_agosto where rn = 1 and mora = 1 and saldo > 0
)
, nuevos_agosto as (
  select f.id_loan, f.saldo, f.fechaproceso as fecha_entrada
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260802' and '20260823'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
)
, universo as (
  select id_loan, saldo, 'a. stock' as origen, cast(null as varchar) as fecha_entrada from stock_previo
  union all select id_loan, saldo, 'b. nuevos', fecha_entrada from nuevos_agosto
)
, asig as (
  select aux02 as id_loan
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-08-01' and '2026-08-23' and aux02 is not null
  group by 1
)
-- salida: primer dia posterior a la referencia (fecha_entrada para nuevos,
-- 20260731 para stock) donde mora vuelve a 0.
, salida as (
  select u.id_loan,
    min(case when f.mora = 0 then f.fechaproceso end) as fecha_salida
  from universo u
  join fotos f on f.id_loan = u.id_loan
    and f.fechaproceso > coalesce(u.fecha_entrada, '20260731')
  group by 1
)
select
  u.id_loan as id_ihfintech_loan
, u.origen
, round(u.saldo, 2) as saldo
, u.fecha_entrada
, s.fecha_salida
, case when s.fecha_salida is null then null
       else date_diff('day', date_parse(coalesce(u.fecha_entrada,'20260731'),'%Y%m%d'), date_parse(s.fecha_salida,'%Y%m%d'))
  end as dias_hasta_pago
from universo u
left join asig a on a.id_loan = u.id_loan
left join salida s on s.id_loan = u.id_loan
where a.id_loan is null
order by u.origen, u.fecha_entrada, u.id_loan
;

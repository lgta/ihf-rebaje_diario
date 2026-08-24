-- =====================================================================
-- TAREA 14 (PENDIENTES.md) -- por que 302 creditos del universo propio
-- (agosto, bug 19) nunca aparecen en dts_asignaciones_gestiones_cobranza.
-- Ejecutada 2026-08-24, misma sesion que el fix de bug 18.
--
-- HIPOTESIS DEL USUARIO: son pagos entre las 10pm y 9am -- creditos que
-- resuelven (pagan) antes de que el proceso de asignacion del dia los
-- alcance, y por eso nunca "necesitan" ser asignados.
--
-- RESULTADO (ver BUGS.md bug 19, actualizacion 2026-08-24): la hipotesis
-- es CORRECTA pero solo explica una fraccion. Son DOS mecanismos:
--   - Stock (50 de 51, 98%): TODOS pagaron el 01-ago, el primer dia del
--     mes -- resueltos antes de que el proceso los capture. Confirma la
--     hipotesis, limpio.
--   - Nuevos, 19 de 251 (7.6%): de los que tuvieron salida observada en
--     la ventana, el 100% (19/19) salio de mora en exactamente 1 dia,
--     contra 37.6% de la poblacion que si aparece en asignaciones.
--     Misma firma que la hipotesis.
--   - Nuevos, el grueso: 232 de 251 (92.4%) -- mecanismo DISTINTO, sin
--     relacion con la hipotesis: entraron en mora el 23-ago, el ULTIMO
--     dia de la ventana de asignaciones usada en validacion_universo_
--     ejecucion.sql (fecha_base between 2026-08-01 and 2026-08-23).
--     Es censura por el corte del propio ejercicio -- todavia estan en
--     mora esa fecha, simplemente no tuvieron tiempo de aparecer.
--
-- Reutiliza las mismas CTEs de nuestro universo que validacion_universo_
-- ejecucion.sql V1/V2 (stock_previo, dia1_entrantes, nuevos_agosto).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Nuevos sin asignacion: duracion de mora (dias hasta que mora
-- vuelve a 0), comparado contra los que si aparecen en asignaciones.
-- ---------------------------------------------------------------------
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
, asig as (
  select aux02 as id_loan
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-08-01' and '2026-08-23' and aux02 is not null
  group by 1
)
, salida as (
  select n.id_loan, n.fecha_entrada,
    min(case when f.mora = 0 then f.fechaproceso end) as fecha_salida
  from nuevos_agosto n
  join fotos f on f.id_loan = n.id_loan and f.fechaproceso > n.fecha_entrada
  group by 1, 2
)
select
  case when a.id_loan is null then '3. no aparece en asignaciones' else '1. aparece en asignaciones' end as grupo
, count(*) as creditos
, count(s.fecha_salida) as con_salida_observada
, round(avg(date_diff('day', date_parse(n.fecha_entrada,'%Y%m%d'), date_parse(s.fecha_salida,'%Y%m%d'))), 2) as dias_promedio_en_mora
, sum(case when date_diff('day', date_parse(n.fecha_entrada,'%Y%m%d'), date_parse(s.fecha_salida,'%Y%m%d')) = 1 then 1 else 0 end) as salio_en_1_dia
, sum(case when date_diff('day', date_parse(n.fecha_entrada,'%Y%m%d'), date_parse(s.fecha_salida,'%Y%m%d')) >= 2 then 1 else 0 end) as salio_en_2mas_dias
from nuevos_agosto n
left join asig a on a.id_loan = n.id_loan
left join salida s on s.id_loan = n.id_loan
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- Q2. Nuevos sin asignacion: distribucion de fecha_entrada -- revela que
-- 232/251 (92.4%) entraron el 23-ago, el ultimo dia de la ventana.
-- ---------------------------------------------------------------------
-- (mismas CTEs que Q1 hasta 'asig'; agregar:)
--   , salida as ( ... igual que arriba ... )
--   select n.fecha_entrada, count(*) as creditos_sin_asignacion,
--          sum(case when s.fecha_salida is null then 1 else 0 end) as todavia_en_mora_23ago
--   from nuevos_agosto n
--   left join asig a on a.id_loan = n.id_loan
--   left join salida s on s.id_loan = n.id_loan
--   where a.id_loan is null
--   group by 1 order by 1

-- ---------------------------------------------------------------------
-- Q3. Stock sin asignacion: fecha en que mora volvio a 0 -- revela que
-- 50/51 (98%) pagaron el 01-ago, el primer dia del mes.
-- ---------------------------------------------------------------------
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
, cierre_julio as (
  select id_loan, mora, saldo,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_previo as (
  select id_loan, saldo from cierre_julio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, asig as (
  select aux02 as id_loan
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-08-01' and '2026-08-23' and aux02 is not null
  group by 1
)
, primer_cero as (
  select id_loan, min(fechaproceso) as fecha_pago
  from fotos
  where fechaproceso between '20260801' and '20260823' and mora = 0
  group by 1
)
select p.fecha_pago, count(*) as creditos
from stock_previo s
left join asig a on a.id_loan = s.id_loan
join primer_cero p on p.id_loan = s.id_loan
where a.id_loan is null
group by 1
order by 1
;

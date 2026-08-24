-- =====================================================================
-- TAREAS 15 y 16 (PENDIENTES.md) -- medir el tamano del sesgo de
-- calibrar sobre "todos" vs. solo la poblacion gestionada como TEMPRANA
-- (bug 19). Ejecutada 2026-08-24, misma sesion que tarea 14.
--
-- Por que julio y no agosto: julio es el UNICO mes cerrado con cobertura
-- de asignaciones completa los 31 dias (agosto sigue en curso). Sirve
-- como banco de pruebas: no se puede tocar la ventana real de
-- calibracion de las curvas (abr-2025 a jun-2026, sin datos de
-- asignaciones), pero julio permite medir si "gestionado" y "todos"
-- activan (aseguran capital) a tasas distintas -- esa es la pregunta que
-- las tareas 15/16 necesitan para decidir.
--
-- Mismo patron de CTEs que validacion_universo_ejecucion.sql /
-- tarea14_no_aparece_asignaciones.sql, fechas corridas 1 mes atras
-- (universo de JULIO en vez de agosto) y agregando la metrica de
-- "asegurado" (>=1 dia de pago en el mes, misma definicion de capital
-- asegurado que el resto del proyecto).
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
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-07-01' and '2026-07-31' and aux02 is not null
  group by 1
)
-- asegurado = tuvo >=1 dia de pago en julio: para stock, mora vuelve a 0
-- en cualquier momento del mes; para nuevos, lo mismo pero ESTRICTAMENTE
-- despues de la fecha de entrada (si no, el dia 1-jul con mora=0 ANTES de
-- entrar cuenta como falso positivo -- bug propio, detectado al revisar
-- el resultado: nuevos daba 100% en TODAS las categorias, no creible).
, asegurado as (
  select u.id_loan,
    max(case
          when f.mora = 0
           and f.fechaproceso between '20260701' and '20260731'
           and (u.fecha_entrada is null or f.fechaproceso > u.fecha_entrada)
          then 1 else 0
        end) as tuvo_pago
  from universo u
  join fotos f on f.id_loan = u.id_loan
  group by 1
)
select
  u.origen
, case
    when a.id_loan is null then '4. no aparece en asignaciones'
    when a.temprana = 1 and a.es_control = 1 then '2. TEMPRANA pero grupo control'
    when a.temprana = 1 then '1. TEMPRANA gestionado'
    when a.esp_rec = 1 then '3. escalado ESPECIALIZADA/RECOVERY'
    else '5. aparece, otra situacion'
  end as situacion_ejecucion
, count(*) as creditos
, round(sum(u.saldo), 0) as saldo_total
, sum(coalesce(ase.tuvo_pago, 0)) as creditos_asegurados
, round(100.0 * sum(coalesce(ase.tuvo_pago, 0)) / count(*), 1) as pct_creditos_asegurados
, round(sum(u.saldo * coalesce(ase.tuvo_pago, 0)), 0) as saldo_asegurado
, round(100.0 * sum(u.saldo * coalesce(ase.tuvo_pago, 0)) / nullif(sum(u.saldo), 0), 1) as pct_saldo_asegurado
from universo u
left join asig a on a.id_loan = u.id_loan
left join asegurado ase on ase.id_loan = u.id_loan
group by 1, 2
order by 1, 2
;

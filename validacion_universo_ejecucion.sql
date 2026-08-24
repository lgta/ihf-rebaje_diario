-- =====================================================================
-- VALIDACION DE UNIVERSO CONTRA REGLAS DE EJECUCION (agosto 2026)
-- Ejecutada 2026-08-24, a pedido del usuario.
--
-- PREGUNTA: las curvas del proyecto se calibran sobre universos
-- reconstruidos de meses pasados (stock = mora 1-30 al cierre del mes
-- anterior + entrantes dia 1 (bug 12); nuevos = dayslate 0->1 desde el dia
-- 2). Nunca se valido si ESA regla de construccion coincide con la regla de
-- EJECUCION real del negocio. Agosto lo permite probar: se reconstruye el
-- universo con el metodo historico (SIN mirar la tabla de asignaciones,
-- tratando agosto como si fuera un mes viejo de calibracion) y recien
-- despues se compara contra dts_asignaciones_gestiones_cobranza.
--
-- Corte 2026-08-23 (ambas fuentes llegan a 24-ago; se usa 23 para evitar el
-- dia parcial). Join via aux02 (bug 15). Universo nuestro = el de
-- CALIBRACION DE CURVAS (stock + nuevos via dayslate), SIN capa fantasma --
-- la capa fantasma es aditiva y no participa de la calibracion de curvas,
-- que es lo que se quiere validar.
--
-- RESULTADO (ver ESTADO.md / BUGS.md bug 18 para la lectura completa):
--   V1: nuestro universo 8,385 creditos vs. oficial TEMPRANA 10,035.
--       - Solo oficial: 2,169 (21.6% de la oficial) -- 2,093 punto ciego
--         dayslate (bug 9) + 76 reenganches.
--       - Solo nuestro: 519 (6.2% del nuestro).
--   V2: del universo nuestro, 8.9% NO es gestionado como TEMPRANA por el
--       negocio, y la contaminacion es ASIMETRICA:
--         stock  15.6% no gestionado (7.2% grupo control, 6.5% otra fase)
--         nuevos  5.8% no gestionado (0.6% grupo control, 0.7% otra fase)
-- =====================================================================

-- ---------------------------------------------------------------------
-- V0. Rangos disponibles en ambas fuentes (para fijar el corte).
-- ---------------------------------------------------------------------
-- U0. Rangos disponibles en ambas fuentes, para fijar la fecha de corte del
-- ejercicio de validacion de universo (agosto tratado como mes historico).
select 'mambu_loans_hist' as fuente, min(fechaproceso) as desde, max(fechaproceso) as hasta, count(*) as filas
from dts_mambu_loans_hist
where fechaproceso >= '20260801'
union all
select 'asignaciones_gestiones', min(fecha_base), max(fecha_base), count(*)
from dts_asignaciones_gestiones_cobranza
where fecha_base >= '2026-08-01'
union all
select 'cuotas_calendario_agosto', cast(min(fechavencimiento) as varchar), cast(max(fechavencimiento) as varchar), count(*)
from dts_cobranza_creditos_cuotas
where fechavencimiento >= date('2026-08-01') and fechavencimiento <= date('2026-08-31')
;

-- ---------------------------------------------------------------------
-- V1. Cruce universo reconstruido vs. ejecucion real, con motivos.
-- ---------------------------------------------------------------------
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
, fotos_all as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
)
-- universo NUESTRO: mismos filtros que la calibracion historica
, fotos as (
  select * from fotos_all
  where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
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
  select f.id_loan, f.saldo
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260802' and '20260823'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
)
, nuestro as (
  select id_loan, max(saldo) as saldo, max(origen) as origen from (
    select id_loan, saldo, 'stock' as origen from stock_previo
    union all select id_loan, saldo, 'stock' from dia1_entrantes
    union all select id_loan, saldo, 'nuevos' from nuevos_agosto
  ) group by 1
)
-- universo OFICIAL: lo que el negocio realmente asigno/ejecuto en agosto
, asig as (
  select
    aux02 as id_loan
  , max(case when fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana
  , max(case when fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_esp_rec
  , max(case when grupo_control = 'CONTROL' then 1 else 0 end) as es_control
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-08-01' and '2026-08-23'
    and aux02 is not null
  group by 1
)
, oficial_temprana as (
  select id_loan, es_control, alguna_vez_esp_rec from asig where alguna_vez_temprana = 1
)
-- flags de mambu para clasificar el lado "solo oficial"
, mambu_flags as (
  select id_loan, max(status) as status, max(last_in_chain) as last_in_chain
  from fotos_all group by 1
)
, cruce as (
  select
    coalesce(n.id_loan, o.id_loan) as id_loan
  , n.id_loan is not null as en_nuestro
  , o.id_loan is not null as en_oficial
  , n.saldo, n.origen
  , o.es_control, o.alguna_vez_esp_rec
  , a.alguna_vez_temprana, a.alguna_vez_esp_rec as asig_esp_rec, a.es_control as asig_control
  , m.status as mambu_status, m.last_in_chain as mambu_chain
  from nuestro n
  full outer join oficial_temprana o on o.id_loan = n.id_loan
  left join asig a on a.id_loan = coalesce(n.id_loan, o.id_loan)
  left join mambu_flags m on m.id_loan = coalesce(n.id_loan, o.id_loan)
)
select
  case
    when en_nuestro and en_oficial then '1. EN AMBOS'
    when en_nuestro and not en_oficial then
      case
        when asig_control = 1 then '2a. solo nuestro - grupo control'
        when asig_esp_rec = 1 then '2b. solo nuestro - asignado a ESPECIALIZADA/RECOVERY'
        when alguna_vez_temprana is null then '2c. solo nuestro - no aparece en asignaciones'
        else '2d. solo nuestro - otro'
      end
    else
      case
        when mambu_status is null then '3a. solo oficial - sin match en mambu'
        when mambu_status not in ('ACTIVE','COMPLETED') then '3b. solo oficial - status no activo'
        when mambu_chain <> 1 then '3c. solo oficial - reenganche (excluido por chain)'
        else '3d. solo oficial - punto ciego dayslate (bug 9)'
      end
  end as categoria
, count(*) as creditos
, round(sum(coalesce(saldo,0)),0) as saldo_nuestro
from cruce
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- V2. Desglose de NUESTRO universo por situacion de ejecucion real,
-- separando stock de nuevos (la contaminacion es asimetrica).
-- ---------------------------------------------------------------------
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
  select f.id_loan, f.saldo
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260802' and '20260823'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
)
, nuestro as (
  select id_loan, max(saldo) as saldo, max(origen) as origen from (
    select id_loan, saldo, 'a. stock' as origen from stock_previo
    union all select id_loan, saldo, 'a. stock' from dia1_entrantes
    union all select id_loan, saldo, 'b. nuevos' from nuevos_agosto
  ) group by 1
)
, asig as (
  select
    aux02 as id_loan
  , max(case when fase_estrategia = 'TEMPRANA' then 1 else 0 end) as temprana
  , max(case when grupo_control = 'CONTROL' then 1 else 0 end) as es_control
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-08-01' and '2026-08-23' and aux02 is not null
  group by 1
)
select
  n.origen
, case
    when a.id_loan is null then '3. no aparece en asignaciones'
    when a.temprana = 1 and a.es_control = 1 then '2. TEMPRANA pero GRUPO CONTROL (no gestionado)'
    when a.temprana = 1 then '1. TEMPRANA gestionado'
    else '4. aparece pero nunca en TEMPRANA'
  end as situacion_ejecucion
, count(*) as creditos
, round(sum(n.saldo),0) as saldo
, round(100.0*count(*)/sum(count(*)) over (partition by n.origen), 2) as pct_dentro_origen
from nuestro n
left join asig a on a.id_loan = n.id_loan
group by 1, 2
order by 1, 2
;

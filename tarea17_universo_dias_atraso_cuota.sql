-- =====================================================================
-- TAREA 17, FASE 1 -- Reconstruir el universo de mora 1-30 con
-- dias_atraso_cuota (dts_cobranza_creditos_calendario_diario) en vez de
-- dayslate (dts_mambu_loans_hist), y comparar en CANTIDAD de creditos
-- contra la tabla oficial de asignaciones. Julio y agosto 2026.
--
-- Contexto: revive bug 16 (investigacion 2026-08-22, archivada por
-- resultado mixto en el backtest -- las queries originales, sc_A..sc_AC,
-- se perdieron en el scratchpad de esa sesion y nunca se copiaron al
-- repo). Angulo nuevo del usuario (2026-08-24): el punto ciego de
-- dayslate (bug 9) tiene un mecanismo HORARIO concreto -- el snapshot de
-- Mambu corre ~10pm; un credito que entra en mora (vencimiento+1) y paga
-- ESE MISMO DIA despues de las 9am (ya armada la asignacion) pero antes
-- de las 10pm queda asignado a TEMPRANA mientras dayslate nunca lo ve.
-- dias_atraso_cuota se reconstruye dia a dia desde el pago real, no de
-- un snapshot unico -- deberia capturar esta poblacion.
--
-- MISMO patron de CTEs que validacion_universo_capital_julio_agosto.sql
-- (stock = mora 1-30 al cierre del mes anterior UNION entrantes dia 1,
-- bug 12; nuevos = mora 0->1 desde el dia 2, bug 4 evitado con la CTE de
-- lag separada del filtro de rango) -- unica diferencia: la fuente de
-- "mora" es dias_atraso_cuota (dts_cobranza_creditos_calendario_diario),
-- no dayslate (dts_mambu_loans_hist). dias_atraso_cuota ya resuelve cual
-- es la cuota VIGENTE de cada credito en cada fecha (confirmado NULL
-- cuando esta al dia, igual que dayslate -- ver diagnostico 2026-08-24)
-- -- no se reinventa esa logica desde dts_cobranza_creditos_cuotas
-- directo (correccion 1 del usuario, ver tarea 17 en PENDIENTES.md).
--
-- OBJETIVO: identificar diferencias y sus motivos, NO reducirlas
-- (correccion 2 del usuario) -- el entregable es la tabla de categorias
-- con motivo, no un % unico a minimizar.
-- =====================================================================

-- #######################################################################
-- BLOQUE JULIO (mes cerrado, ventana calendario 20260601-20260731 para
-- poder construir stock_previo desde el cierre de junio)
-- #######################################################################
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, cal_raw as (
  select
    c.id_ihfintech_loan as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d') as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0) as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-06-01') and date('2026-07-31')
)
, fotos_all as (
  select
    d.id_loan, d.fechaproceso, d.mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from cal_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
)
, fotos as (
  select * from fotos_all where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
)
, fotos_lag as (
  select id_loan, fechaproceso, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
)
, cierre_junio as (
  select id_loan, mora,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_previo as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30
)
, dia1_julio as (
  select id_loan, mora,
    row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260701'
)
, dia1_entrantes as (
  select id_loan from dia1_julio where rn = 1 and mora = 1
)
, nuevos_julio as (
  select f.id_loan
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260731'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
)
, nuestro as (
  select id_loan, max(origen) as origen from (
    select id_loan, 'stock' as origen from stock_previo
    union all select id_loan, 'stock' from dia1_entrantes
    union all select id_loan, 'nuevos' from nuevos_julio
  ) group by 1
)
, asig as (
  select
    aux02 as id_loan
  , max(case when fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana
  , max(case when fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_esp_rec
  , max(case when grupo_control = 'CONTROL' then 1 else 0 end) as es_control
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-07-01' and '2026-07-31' and aux02 is not null
  group by 1
)
, oficial_temprana as (
  select id_loan, es_control, alguna_vez_esp_rec from asig where alguna_vez_temprana = 1
)
, mambu_flags as (
  select id_loan, max(status) as status, max(last_in_chain) as last_in_chain
  from fotos_all group by 1
)
, cruce as (
  select
    coalesce(n.id_loan, o.id_loan) as id_loan
  , n.id_loan is not null as en_nuestro
  , o.id_loan is not null as en_oficial
  , n.origen
  , a.alguna_vez_temprana, a.alguna_vez_esp_rec as asig_esp_rec, a.es_control as asig_control
  , m.status as mambu_status, m.last_in_chain as mambu_chain
  from nuestro n
  full outer join oficial_temprana o on o.id_loan = n.id_loan
  left join asig a on a.id_loan = coalesce(n.id_loan, o.id_loan)
  left join mambu_flags m on m.id_loan = coalesce(n.id_loan, o.id_loan)
)
select
  'julio' as mes
, id_loan as id_ihfintech_loan
, case
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
        when mambu_status is null then '3a. solo oficial - sin match en calendario_diario'
        when mambu_status not in ('ACTIVE','COMPLETED') then '3b. solo oficial - status no activo'
        when mambu_chain <> 1 then '3c. solo oficial - reenganche (excluido por chain)'
        else '3d. solo oficial - punto ciego dias_atraso_cuota (a investigar, Fase 1 paso 3)'
      end
  end as categoria
, origen
from cruce
order by 3, 1
;

-- #######################################################################
-- BLOQUE AGOSTO (corte 23-ago, ventana calendario 20260701-20260823 para
-- poder construir stock_previo desde el cierre de julio)
-- #######################################################################
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, cal_raw as (
  select
    c.id_ihfintech_loan as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d') as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0) as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-07-01') and date('2026-08-23')
)
, fotos_all as (
  select
    d.id_loan, d.fechaproceso, d.mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from cal_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
)
, fotos as (
  select * from fotos_all where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
)
, fotos_lag as (
  select id_loan, fechaproceso, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
)
, cierre_julio as (
  select id_loan, mora,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_previo as (
  select id_loan from cierre_julio where rn = 1 and mora between 1 and 30
)
, dia1_agosto as (
  select id_loan, mora,
    row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260801'
)
, dia1_entrantes as (
  select id_loan from dia1_agosto where rn = 1 and mora = 1
)
, nuevos_agosto as (
  select f.id_loan
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260802' and '20260823'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
)
, nuestro as (
  select id_loan, max(origen) as origen from (
    select id_loan, 'stock' as origen from stock_previo
    union all select id_loan, 'stock' from dia1_entrantes
    union all select id_loan, 'nuevos' from nuevos_agosto
  ) group by 1
)
, asig as (
  select
    aux02 as id_loan
  , max(case when fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana
  , max(case when fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_esp_rec
  , max(case when grupo_control = 'CONTROL' then 1 else 0 end) as es_control
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-08-01' and '2026-08-23' and aux02 is not null
  group by 1
)
, oficial_temprana as (
  select id_loan, es_control, alguna_vez_esp_rec from asig where alguna_vez_temprana = 1
)
, mambu_flags as (
  select id_loan, max(status) as status, max(last_in_chain) as last_in_chain
  from fotos_all group by 1
)
, cruce as (
  select
    coalesce(n.id_loan, o.id_loan) as id_loan
  , n.id_loan is not null as en_nuestro
  , o.id_loan is not null as en_oficial
  , n.origen
  , a.alguna_vez_temprana, a.alguna_vez_esp_rec as asig_esp_rec, a.es_control as asig_control
  , m.status as mambu_status, m.last_in_chain as mambu_chain
  from nuestro n
  full outer join oficial_temprana o on o.id_loan = n.id_loan
  left join asig a on a.id_loan = coalesce(n.id_loan, o.id_loan)
  left join mambu_flags m on m.id_loan = coalesce(n.id_loan, o.id_loan)
)
select
  'agosto' as mes
, id_loan as id_ihfintech_loan
, case
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
        when mambu_status is null then '3a. solo oficial - sin match en calendario_diario'
        when mambu_status not in ('ACTIVE','COMPLETED') then '3b. solo oficial - status no activo'
        when mambu_chain <> 1 then '3c. solo oficial - reenganche (excluido por chain)'
        else '3d. solo oficial - punto ciego dias_atraso_cuota (a investigar, Fase 1 paso 3)'
      end
  end as categoria
, origen
from cruce
order by 3, 1
;

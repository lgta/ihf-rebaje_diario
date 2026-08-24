-- =====================================================================
-- VALIDACION DE UNIVERSO EN CAPITAL (soles), no solo en creditos --
-- julio y agosto 2026. A pedido del usuario, 2026-08-24 (continuacion).
--
-- PREGUNTA (distinta de tarea14/15/16): no es calibrar julio ni correr
-- una reconciliacion de recupero. Es verificar si la LOGICA con la que
-- reconstruimos el universo en meses HISTORICOS (stock = mora 1-30 al
-- cierre del mes anterior + entrantes dia 1, bug 12; nuevos = dayslate
-- 0->1 desde el dia 2) devuelve el mismo CAPITAL (soles) que la tabla
-- formal de asignaciones ("la verdad de quien cayo en mora"), en un mes
-- donde SI tenemos esa tabla para comparar. Julio (grupo control grande,
-- mes cerrado) y agosto (grupo control chico, corte 23-ago) son los dos
-- unicos meses donde se puede hacer esta prueba.
--
-- GAP QUE ESTO CORRIGE vs. validacion_universo_ejecucion.sql V1: esa
-- query solo sumaba saldo del lado NUESTRO (n.saldo) -- para la categoria
-- "solo oficial" (creditos que la tabla de asignaciones si tiene y
-- nuestra logica no encuentra), el saldo salia en CERO por construccion,
-- nunca se supo cuantos SOLES representaba lo que falta. Aca se trae el
-- saldo de Mambu para AMBOS lados (saldo_ref, el ultimo saldo visto en
-- la ventana del mes), y se devuelve CASO POR CASO (no agrupado), con
-- id_ihfintech_loan completo.
--
-- Definicion de "oficial": fase_estrategia = 'TEMPRANA' en algun
-- fecha_base del mes (via aux02, bug 15) -- es la poblacion comparable a
-- mora 1-30 gestionada en etapa temprana, misma definicion de bug 19 V1.
-- =====================================================================

-- #######################################################################
-- BLOQUE JULIO (mes cerrado, ventana Mambu 20260601-20260731 para poder
-- construir stock_previo desde el cierre de junio)
-- #######################################################################
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
, fotos as (
  select * from fotos_all where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
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
  select f.id_loan, f.saldo
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260731'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
)
, nuestro as (
  select id_loan, max(saldo) as saldo, max(origen) as origen from (
    select id_loan, saldo, 'stock' as origen from stock_previo
    union all select id_loan, saldo, 'stock' from dia1_entrantes
    union all select id_loan, saldo, 'nuevos' from nuevos_julio
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
-- FIX vs. V1: saldo de referencia para CUALQUIER id_loan (nuestro u
-- oficial), tomado del ultimo fechaproceso visto en la ventana del mes.
, saldo_ref as (
  select id_loan, saldo,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos_all
)
, cruce as (
  select
    coalesce(n.id_loan, o.id_loan) as id_loan
  , n.id_loan is not null as en_nuestro
  , o.id_loan is not null as en_oficial
  , n.origen
  , coalesce(n.saldo, sr.saldo) as saldo
  , a.alguna_vez_temprana, a.alguna_vez_esp_rec as asig_esp_rec, a.es_control as asig_control
  , m.status as mambu_status, m.last_in_chain as mambu_chain
  from nuestro n
  full outer join oficial_temprana o on o.id_loan = n.id_loan
  left join asig a on a.id_loan = coalesce(n.id_loan, o.id_loan)
  left join mambu_flags m on m.id_loan = coalesce(n.id_loan, o.id_loan)
  left join saldo_ref sr on sr.id_loan = coalesce(n.id_loan, o.id_loan) and sr.rn = 1
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
        when mambu_status is null then '3a. solo oficial - sin match en mambu'
        when mambu_status not in ('ACTIVE','COMPLETED') then '3b. solo oficial - status no activo'
        when mambu_chain <> 1 then '3c. solo oficial - reenganche (excluido por chain)'
        else '3d. solo oficial - punto ciego dayslate (bug 9)'
      end
  end as categoria
, origen
, round(coalesce(saldo,0), 2) as saldo
from cruce
order by 3, 1
;

-- #######################################################################
-- BLOQUE AGOSTO (corte 23-ago, ventana Mambu 20260701-20260823 para
-- poder construir stock_previo desde el cierre de julio)
-- #######################################################################
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
, fotos as (
  select * from fotos_all where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
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
, saldo_ref as (
  select id_loan, saldo,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos_all
)
, cruce as (
  select
    coalesce(n.id_loan, o.id_loan) as id_loan
  , n.id_loan is not null as en_nuestro
  , o.id_loan is not null as en_oficial
  , n.origen
  , coalesce(n.saldo, sr.saldo) as saldo
  , a.alguna_vez_temprana, a.alguna_vez_esp_rec as asig_esp_rec, a.es_control as asig_control
  , m.status as mambu_status, m.last_in_chain as mambu_chain
  from nuestro n
  full outer join oficial_temprana o on o.id_loan = n.id_loan
  left join asig a on a.id_loan = coalesce(n.id_loan, o.id_loan)
  left join mambu_flags m on m.id_loan = coalesce(n.id_loan, o.id_loan)
  left join saldo_ref sr on sr.id_loan = coalesce(n.id_loan, o.id_loan) and sr.rn = 1
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
        when mambu_status is null then '3a. solo oficial - sin match en mambu'
        when mambu_status not in ('ACTIVE','COMPLETED') then '3b. solo oficial - status no activo'
        when mambu_chain <> 1 then '3c. solo oficial - reenganche (excluido por chain)'
        else '3d. solo oficial - punto ciego dayslate (bug 9)'
      end
  end as categoria
, origen
, round(coalesce(saldo,0), 2) as saldo
from cruce
order by 3, 1
;

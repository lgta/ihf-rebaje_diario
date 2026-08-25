-- =====================================================================
-- TAREA 17, FASE 2 -- Montos (soles). Misma reconstruccion y misma
-- categorizacion que tarea17_universo_dias_atraso_cuota.sql (Fase 1,
-- cantidad), agregando el saldo capital de Mambu (balances_
-- principalbalance, ultimo visto en la ventana del mes) a cada caso --
-- mismo patron que validacion_universo_capital_julio_agosto.sql.
--
-- Contexto: Fase 1 (cerrada 2026-08-24) encontro que dias_atraso_cuota
-- cierra ~97% del punto ciego de dayslate en CANTIDAD de creditos, a
-- costa de una poblacion nueva ("2c", no aparece en asignaciones) que se
-- explico con el hueco de fin de semana de dts_asignaciones_gestiones_
-- cobranza (bug 16 en BUGS.md). El usuario decidio (2026-08-24): la curva
-- debe representar TODA la mora que ocurre (cualquier dia con
-- vencimientos), no solo la que el negocio gestiona -- dias_atraso_cuota
-- es el universo correcto para calibrar. Fase 2 cuantifica en SOLES el
-- mismo movimiento que Fase 1 midio en creditos.
-- =====================================================================

-- #######################################################################
-- BLOQUE JULIO
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
  select id_loan, mora, fechaproceso,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_previo as (
  select id_loan, fechaproceso as fecha_ancla from cierre_junio where rn = 1 and mora between 1 and 30
)
, dia1_julio as (
  select id_loan, mora, fechaproceso,
    row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260701'
)
, dia1_entrantes as (
  select id_loan, fechaproceso as fecha_ancla from dia1_julio where rn = 1 and mora = 1
)
, nuevos_julio as (
  select f.id_loan, f.fechaproceso as fecha_ancla
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260731'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
)
-- fecha_ancla = fecha en la que dias_atraso_cuota identifica al credito
-- (cierre del mes anterior para stock, dia de entrada para nuevos) --
-- el saldo se toma de Mambu EN ESA FECHA, no el ultimo visto en la
-- ventana (mismo criterio que enfoque_capital_asegurado.sql/
-- validacion_universo_capital_julio_agosto.sql: "cuanto capital entro en
-- mora", no "cuanto queda pendiente al cierre" -- un pago parcial a
-- mitad de mes no debe deflactar el capital que SI entro en mora).
, nuestro as (
  select id_loan, max(origen) as origen, max(fecha_ancla) as fecha_ancla from (
    select id_loan, 'stock' as origen, fecha_ancla from stock_previo
    union all select id_loan, 'stock', fecha_ancla from dia1_entrantes
    union all select id_loan, 'nuevos', fecha_ancla from nuevos_julio
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
, mambu_raw as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260731'
)
, mambu_dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from mambu_raw
)
, mambu_saldo as (
  select id_loan, fechaproceso, saldo from mambu_dedup where rn_dedup = 1
)
, saldo_ref as (
  -- fallback SOLO para "solo oficial" (creditos sin fecha_ancla propia,
  -- nunca identificados como "nuestro"): ultimo saldo visto en la
  -- ventana del mes, mismo criterio que validacion_universo_capital_
  -- julio_agosto.sql.
  select id_loan, saldo,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from mambu_dedup where rn_dedup = 1
)
, cruce as (
  select
    coalesce(n.id_loan, o.id_loan) as id_loan
  , n.id_loan is not null as en_nuestro
  , o.id_loan is not null as en_oficial
  , n.origen
  , coalesce(ms.saldo, sr.saldo, 0) as saldo
  , a.alguna_vez_temprana, a.alguna_vez_esp_rec as asig_esp_rec, a.es_control as asig_control
  , m.status as mambu_status, m.last_in_chain as mambu_chain
  from nuestro n
  full outer join oficial_temprana o on o.id_loan = n.id_loan
  left join asig a on a.id_loan = coalesce(n.id_loan, o.id_loan)
  left join mambu_flags m on m.id_loan = coalesce(n.id_loan, o.id_loan)
  left join mambu_saldo ms on ms.id_loan = n.id_loan and ms.fechaproceso = n.fecha_ancla
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
        when mambu_status is null then '3a. solo oficial - sin match en calendario_diario'
        when mambu_status not in ('ACTIVE','COMPLETED') then '3b. solo oficial - status no activo'
        when mambu_chain <> 1 then '3c. solo oficial - reenganche (excluido por chain)'
        else '3d. solo oficial - punto ciego dias_atraso_cuota (residual)'
      end
  end as categoria
, origen
, round(saldo, 2) as saldo
from cruce
order by 3, 1
;

-- #######################################################################
-- BLOQUE AGOSTO (corte 23-ago)
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
  select id_loan, mora, fechaproceso,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_previo as (
  select id_loan, fechaproceso as fecha_ancla from cierre_julio where rn = 1 and mora between 1 and 30
)
, dia1_agosto as (
  select id_loan, mora, fechaproceso,
    row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260801'
)
, dia1_entrantes as (
  select id_loan, fechaproceso as fecha_ancla from dia1_agosto where rn = 1 and mora = 1
)
, nuevos_agosto as (
  select f.id_loan, f.fechaproceso as fecha_ancla
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260802' and '20260823'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
)
, nuestro as (
  select id_loan, max(origen) as origen, max(fecha_ancla) as fecha_ancla from (
    select id_loan, 'stock' as origen, fecha_ancla from stock_previo
    union all select id_loan, 'stock', fecha_ancla from dia1_entrantes
    union all select id_loan, 'nuevos', fecha_ancla from nuevos_agosto
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
, mambu_raw as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260701' and '20260823'
)
, mambu_dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from mambu_raw
)
, mambu_saldo as (
  select id_loan, fechaproceso, saldo from mambu_dedup where rn_dedup = 1
)
, saldo_ref as (
  select id_loan, saldo,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from mambu_dedup where rn_dedup = 1
)
, cruce as (
  select
    coalesce(n.id_loan, o.id_loan) as id_loan
  , n.id_loan is not null as en_nuestro
  , o.id_loan is not null as en_oficial
  , n.origen
  , coalesce(ms.saldo, sr.saldo, 0) as saldo
  , a.alguna_vez_temprana, a.alguna_vez_esp_rec as asig_esp_rec, a.es_control as asig_control
  , m.status as mambu_status, m.last_in_chain as mambu_chain
  from nuestro n
  full outer join oficial_temprana o on o.id_loan = n.id_loan
  left join asig a on a.id_loan = coalesce(n.id_loan, o.id_loan)
  left join mambu_flags m on m.id_loan = coalesce(n.id_loan, o.id_loan)
  left join mambu_saldo ms on ms.id_loan = n.id_loan and ms.fechaproceso = n.fecha_ancla
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
        when mambu_status is null then '3a. solo oficial - sin match en calendario_diario'
        when mambu_status not in ('ACTIVE','COMPLETED') then '3b. solo oficial - status no activo'
        when mambu_chain <> 1 then '3c. solo oficial - reenganche (excluido por chain)'
        else '3d. solo oficial - punto ciego dias_atraso_cuota (residual)'
      end
  end as categoria
, origen
, round(saldo, 2) as saldo
from cruce
order by 3, 1
;

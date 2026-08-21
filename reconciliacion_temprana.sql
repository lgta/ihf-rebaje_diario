-- =====================================================================
-- RECONCILIACION contra vw_seguimiento_diario_cohorte_tramo (TEMPRANA, julio 2026)
-- Ejecutada 2026-08-20. Ver reconciliacion_vw_seguimiento_temprana.md y bug 14/
-- BUGS.md para el contexto y los resultados. Reemplaza la corrida 2026-08-19
-- (quedo solo en scratchpad, nunca se copio al repo, SQL exacto no recuperable).
--
-- OJO -- bug de no-determinismo propio encontrado y corregido en esta sesion:
-- la primera version de "cierre_junio" ordenaba row_number() por "periodo"
-- (constante dentro del CTE ya filtrado a periodo='202606') en vez de por el
-- dia real -- mismo patron que bug 11 (BUGS.md), Presto no garantiza orden
-- estable con un ORDER BY sobre una columna constante. Fix: dedup determinista
-- de filas duplicadas (id_loan,fechaproceso) via lastmodifieddate desc, id desc
-- ANTES de construir "fotos", y ordenar cierre_junio por "dia" real.
-- Verificado corriendo Q1 dos veces: mismo resultado ambas veces.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Reconciliacion agregada (validacion) -- reproduce bug 14 a la misma
-- escala que la sesion anterior (3,135/S/4,924,248 vs. 3,210/S/5,018,712;
-- 26.8% vs. ~27% de la poblacion oficial TEMPRANA -- mismo hallazgo, la
-- diferencia es reconstruir sin el SQL original de la sesion previa).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260731'
)
, dedup as (
  -- bug 11 (BUGS.md): regla actualizada 2026-08-20 (saldo<>0 antes de lastmodifieddate),
  -- validada contra los 687 casos conflictivos completos de la historia.
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    substr(d.fechaproceso,1,6) as periodo
  , cast(substr(d.fechaproceso,7,2) as int) as dia
  , d.id_loan, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
)
, cierre_junio as (
  select *, row_number() over (partition by id_loan order by dia desc) as rn
  from fotos where periodo = '202606'
)
, stock_previo as (
  select id_loan, saldo from cierre_junio where rn=1 and mora between 1 and 30
)
, primer_dia_julio as (
  select *, row_number() over (partition by id_loan order by dia asc) as rn
  from fotos where periodo='202607'
)
, dia1_entrantes as (
  select id_loan, saldo from primer_dia_julio where rn=1 and mora=1
)
, fotos_julio_lag as (
  select id_loan, dia, saldo, mora,
    lag(mora) over (partition by id_loan order by dia) as mora_ant
  from fotos where periodo='202607'
)
, nuevos_julio as (
  select id_loan, saldo from fotos_julio_lag where mora_ant=0 and mora=1 and dia<>1
)
, nuestro_bruto as (
  select id_loan, saldo from stock_previo
  union all select id_loan, saldo from dia1_entrantes
  union all select id_loan, saldo from nuevos_julio
)
, nuestro as (
  -- dedup 1 fila por credito, saldo max -- evita doble conteo de reentradas dentro del mes
  select id_loan, max(saldo) as saldo from nuestro_bruto group by 1
)
, oficial as (
  select id_ihfintech_loan as id_loan, monto_asignado, fecha_de_vencimiento_cuota
  from vw_seguimiento_diario_cohorte_tramo
  where fase_estrategia='TEMPRANA' and mes_asignacion='202607' and fecha=fecha_ancla
)
, solo_oficial as (
  select o.*
  from oficial o
  left join nuestro n on n.id_loan = o.id_loan
  where n.id_loan is null
)
, mambu_flags as (
  select id_loan, max(status) as status, max(last_in_chain) as last_in_chain
  from fotos
  group by 1
)
, clasificado as (
  select
    so.id_loan, so.monto_asignado, so.fecha_de_vencimiento_cuota,
    case
      when m.id_loan is null then 'sin_match_mambu'
      when m.status not in ('ACTIVE','COMPLETED') then 'status_no_activo'
      when m.last_in_chain <> 1 then 'excluido_chain'
      else 'dayslate_cero_bug9'
    end as motivo
  from solo_oficial so
  left join mambu_flags m on m.id_loan = so.id_loan
)
select 'oficial_total' as chk, count(distinct id_loan) as creditos, round(sum(monto_asignado),0) as monto
from oficial
union all
select 'nuestro_total', count(distinct id_loan), round(sum(saldo),0) from nuestro
union all
select 'solo_oficial_total', count(distinct id_loan), round(sum(monto_asignado),0) from solo_oficial
union all
select motivo, count(*), round(sum(monto_asignado),0) from clasificado group by motivo
;

-- ---------------------------------------------------------------------
-- Q2. PASO 1 DEL PLAN -- mecanismo exacto de los 3,135 creditos "dayslate=0
-- para nosotros, oficial marca mora 1-30". Cruce contra
-- dts_cobranza_creditos_cuotas via fecha_de_vencimiento_cuota (la cuota que
-- la propia vista oficial ya identifico). Resultado: 546 con esa fecha
-- poblada, gap exacto de 1 dia (installmentlastpaiddate - fechavencimiento) ->
-- bug 9 clasico. El resto (fecha nula) se investiga en Q3/Q4.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260731'
)
, dedup as (
  -- bug 11 (BUGS.md): regla actualizada 2026-08-20 (saldo<>0 antes de lastmodifieddate),
  -- validada contra los 687 casos conflictivos completos de la historia.
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    substr(d.fechaproceso,1,6) as periodo
  , cast(substr(d.fechaproceso,7,2) as int) as dia
  , d.id_loan, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
)
, cierre_junio as (
  select *, row_number() over (partition by id_loan order by dia desc) as rn
  from fotos where periodo = '202606'
)
, stock_previo as (
  select id_loan, saldo from cierre_junio where rn=1 and mora between 1 and 30
)
, primer_dia_julio as (
  select *, row_number() over (partition by id_loan order by dia asc) as rn
  from fotos where periodo='202607'
)
, dia1_entrantes as (
  select id_loan, saldo from primer_dia_julio where rn=1 and mora=1
)
, fotos_julio_lag as (
  select id_loan, dia, saldo, mora,
    lag(mora) over (partition by id_loan order by dia) as mora_ant
  from fotos where periodo='202607'
)
, nuevos_julio as (
  select id_loan, saldo from fotos_julio_lag where mora_ant=0 and mora=1 and dia<>1
)
, nuestro_bruto as (
  select id_loan, saldo from stock_previo
  union all select id_loan, saldo from dia1_entrantes
  union all select id_loan, saldo from nuevos_julio
)
, nuestro as (
  select id_loan, max(saldo) as saldo from nuestro_bruto group by 1
)
, oficial as (
  select id_ihfintech_loan as id_loan, monto_asignado, fecha_de_vencimiento_cuota
  from vw_seguimiento_diario_cohorte_tramo
  where fase_estrategia='TEMPRANA' and mes_asignacion='202607' and fecha=fecha_ancla
)
, solo_oficial as (
  select o.*
  from oficial o
  left join nuestro n on n.id_loan = o.id_loan
  where n.id_loan is null
)
, mambu_flags as (
  select id_loan, max(status) as status, max(last_in_chain) as last_in_chain
  from fotos
  group by 1
)
, clasificado as (
  select so.id_loan, so.monto_asignado, so.fecha_de_vencimiento_cuota
  from solo_oficial so
  join mambu_flags m on m.id_loan = so.id_loan
  where m.status in ('ACTIVE','COMPLETED') and m.last_in_chain = 1
)
, con_cuota as (
  select
    cl.id_loan, cl.monto_asignado, cl.fecha_de_vencimiento_cuota
  , c.installmentstate
  , c.dias_vencimiento_a_pago
  , c.installmentlastpaiddate
  , date_diff('day', c.fechavencimiento, c.installmentlastpaiddate) as gap_venc_a_pago_real
  , b."type" as producto
  from clasificado cl
  left join dts_cobranza_creditos_cuotas c
    on c.id_ihfintech_loan = cl.id_loan
   and c.fechavencimiento = cl.fecha_de_vencimiento_cuota
   and c.flg_last_loan_in_chain = 1
  left join dts_okaapi_loans b on b.id_ihfintech_loan = cl.id_loan
)
select
  coalesce(installmentstate, 'sin_match_cuota') as installmentstate
, coalesce(producto,'sin_producto') as producto
, case
    when installmentlastpaiddate is null then 'sin_pago_aun'
    when gap_venc_a_pago_real <= 0 then '0. a_tiempo_o_antes'
    when gap_venc_a_pago_real = 1 then '1. exacto_bug9'
    when gap_venc_a_pago_real between 2 and 5 then '2-5. deberia_detectarse'
    else '6+. deberia_detectarse'
  end as bucket_gap
, count(*) as creditos
, round(sum(monto_asignado),0) as monto
from con_cuota
group by 1,2,3
order by 1,2,3
;

-- ---------------------------------------------------------------------
-- Q3. Diagnostico del resto (fecha_de_vencimiento_cuota NULA, 82% del
-- bucket): confirma que NO es arrastre por DNI (max_dias_mora_dni =
-- dias_mora en casi todos los casos) y que el dayslate propio en la fecha
-- ancla es 0 (consistente, no es un gap de nuestra construccion de poblacion).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260731'
)
, dedup as (
  -- bug 11 (BUGS.md): regla actualizada 2026-08-20 (saldo<>0 antes de lastmodifieddate),
  -- validada contra los 687 casos conflictivos completos de la historia.
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    substr(d.fechaproceso,1,6) as periodo
  , cast(substr(d.fechaproceso,7,2) as int) as dia
  , d.fechaproceso
  , d.id_loan, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
)
, cierre_junio as (
  select *, row_number() over (partition by id_loan order by dia desc) as rn
  from fotos where periodo = '202606'
)
, stock_previo as (
  select id_loan, saldo from cierre_junio where rn=1 and mora between 1 and 30
)
, primer_dia_julio as (
  select *, row_number() over (partition by id_loan order by dia asc) as rn
  from fotos where periodo='202607'
)
, dia1_entrantes as (
  select id_loan, saldo from primer_dia_julio where rn=1 and mora=1
)
, fotos_julio_lag as (
  select id_loan, dia, saldo, mora,
    lag(mora) over (partition by id_loan order by dia) as mora_ant
  from fotos where periodo='202607'
)
, nuevos_julio as (
  select id_loan, saldo from fotos_julio_lag where mora_ant=0 and mora=1 and dia<>1
)
, nuestro_bruto as (
  select id_loan, saldo from stock_previo
  union all select id_loan, saldo from dia1_entrantes
  union all select id_loan, saldo from nuevos_julio
)
, nuestro as (
  select id_loan, max(saldo) as saldo from nuestro_bruto group by 1
)
, oficial as (
  select id_ihfintech_loan as id_loan, monto_asignado, fecha_de_vencimiento_cuota,
    tipo_mora, dias_mora, max_dias_mora_dni, fecha_ancla
  from vw_seguimiento_diario_cohorte_tramo
  where fase_estrategia='TEMPRANA' and mes_asignacion='202607' and fecha=fecha_ancla
)
, solo_oficial as (
  select o.*
  from oficial o
  left join nuestro n on n.id_loan = o.id_loan
  where n.id_loan is null
)
, mambu_flags as (
  select id_loan, max(status) as status, max(last_in_chain) as last_in_chain
  from fotos
  group by 1
)
, clasificado as (
  select so.*
  from solo_oficial so
  join mambu_flags m on m.id_loan = so.id_loan
  where m.status in ('ACTIVE','COMPLETED') and m.last_in_chain = 1
    and so.fecha_de_vencimiento_cuota is null
)
, mambu_en_ancla as (
  select cl.id_loan, cl.dias_mora, cl.max_dias_mora_dni, cl.tipo_mora,
    f.mora as dayslate_propio_en_ancla
  from clasificado cl
  left join fotos f
    on f.id_loan = cl.id_loan
   and f.fechaproceso = replace(cast(cl.fecha_ancla as varchar),'-','')
)
select
  tipo_mora
, case when dias_mora = 0 then '0' when dias_mora between 1 and 30 then '1-30' else '30+/otro' end as dias_mora_bucket
, case when max_dias_mora_dni = 0 then '0' when max_dias_mora_dni between 1 and 30 then '1-30' else '30+/otro' end as max_dias_mora_dni_bucket
, case when dayslate_propio_en_ancla = 0 then '0' when dayslate_propio_en_ancla between 1 and 30 then '1-30' else 'sin_match_o_otro' end as dayslate_propio_bucket
, count(*) as creditos
from mambu_en_ancla
group by 1,2,3,4
order by 1,2,3,4
;

-- ---------------------------------------------------------------------
-- Q4. Para el sub-bucket de Q3 (dias_mora oficial 1-30, sin arrastre por
-- DNI, fecha_de_vencimiento_cuota nula): buscar la cuota vencida mas
-- reciente (fechavencimiento<=fecha_ancla, ya PAID) y medir (a) cuanto se
-- tardo en pagarla vs. su vencimiento, y (b) cuantos dias hay entre esa
-- fecha de pago real y fecha_ancla (el dia que el sistema de asignacion
-- marco mora=1). Resultado: 2,573 de 2,581 con gap=1 dia EXACTO y pago el
-- MISMO dia que fecha_ancla -- el mismo mecanismo de bug 9, sin el campo
-- fecha_de_vencimiento_cuota poblado para cruzarlo directo.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260731'
)
, dedup as (
  -- bug 11 (BUGS.md): regla actualizada 2026-08-20 (saldo<>0 antes de lastmodifieddate),
  -- validada contra los 687 casos conflictivos completos de la historia.
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    substr(d.fechaproceso,1,6) as periodo
  , cast(substr(d.fechaproceso,7,2) as int) as dia
  , d.fechaproceso
  , d.id_loan, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
)
, cierre_junio as (
  select *, row_number() over (partition by id_loan order by dia desc) as rn
  from fotos where periodo = '202606'
)
, stock_previo as (
  select id_loan, saldo from cierre_junio where rn=1 and mora between 1 and 30
)
, primer_dia_julio as (
  select *, row_number() over (partition by id_loan order by dia asc) as rn
  from fotos where periodo='202607'
)
, dia1_entrantes as (
  select id_loan, saldo from primer_dia_julio where rn=1 and mora=1
)
, fotos_julio_lag as (
  select id_loan, dia, saldo, mora,
    lag(mora) over (partition by id_loan order by dia) as mora_ant
  from fotos where periodo='202607'
)
, nuevos_julio as (
  select id_loan, saldo from fotos_julio_lag where mora_ant=0 and mora=1 and dia<>1
)
, nuestro_bruto as (
  select id_loan, saldo from stock_previo
  union all select id_loan, saldo from dia1_entrantes
  union all select id_loan, saldo from nuevos_julio
)
, nuestro as (
  select id_loan, max(saldo) as saldo from nuestro_bruto group by 1
)
, oficial as (
  select id_ihfintech_loan as id_loan, monto_asignado, fecha_de_vencimiento_cuota,
    tipo_mora, dias_mora, max_dias_mora_dni, fecha_ancla
  from vw_seguimiento_diario_cohorte_tramo
  where fase_estrategia='TEMPRANA' and mes_asignacion='202607' and fecha=fecha_ancla
)
, solo_oficial as (
  select o.*
  from oficial o
  left join nuestro n on n.id_loan = o.id_loan
  where n.id_loan is null
)
, mambu_flags as (
  select id_loan, max(status) as status, max(last_in_chain) as last_in_chain
  from fotos
  group by 1
)
, poblacion as (
  select so.id_loan, so.fecha_ancla, so.dias_mora, so.max_dias_mora_dni
  from solo_oficial so
  join mambu_flags m on m.id_loan = so.id_loan
  where m.status in ('ACTIVE','COMPLETED') and m.last_in_chain = 1
    and so.fecha_de_vencimiento_cuota is null
    and so.dias_mora between 1 and 30
    and so.max_dias_mora_dni between 1 and 30
)
, cuota_reciente as (
  select
    p.id_loan, p.fecha_ancla, p.dias_mora as dias_mora_oficial
  , c.fechavencimiento, c.installmentlastpaiddate
  , date_diff('day', c.fechavencimiento, c.installmentlastpaiddate) as dias_tarde_pago
  , date_diff('day', c.installmentlastpaiddate, p.fecha_ancla) as dias_desde_pago_hasta_ancla
  , row_number() over (partition by p.id_loan order by c.fechavencimiento desc) as rn
  from poblacion p
  left join dts_cobranza_creditos_cuotas c
    on c.id_ihfintech_loan = p.id_loan
   and c.flg_last_loan_in_chain = 1
   and c.fechavencimiento <= p.fecha_ancla
   and c.installmentstate = 'PAID'
)
select
  dias_desde_pago_hasta_ancla
, count(*) as creditos
, round(avg(dias_tarde_pago),1) as avg_dias_tarde_pago_original
, round(avg(dias_mora_oficial),1) as avg_dias_mora_oficial
from cuota_reciente
where rn = 1
group by 1
order by 1
;

-- =====================================================================
-- Q5-Q7: sesion 2026-08-20 (continuacion) -- cierre de los pendientes de
-- reconciliacion_vw_seguimiento_temprana.md ("Pendientes para cerrar TEMPRANA
-- por completo"). Dedup de bug 11 (saldo<>0 antes de lastmodifieddate) ya
-- aplicado en todas las CTEs "dedup" de arriba.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q5. Verificacion de la capa fantasma A NIVEL CREDITO (pendiente 1). Cruza
-- los 3,130 creditos del bucket "dayslate_cero_bug9" (Q1) contra la misma
-- logica de deteccion de la capa fantasma de produccion (enfoque_capital_
-- asegurado.sql Q3), para julio. Resultado: 2,839/3,130 (90.7%) cubiertos
-- directo -- NO es 1:1. Ver Q5b para el detalle del gap.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260731'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    substr(d.fechaproceso,1,6) as periodo
  , d.fechaproceso
  , d.id_loan, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
)
, cierre_junio as (
  select *, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where periodo = '202606'
)
, stock_previo as (
  select id_loan, saldo from cierre_junio where rn=1 and mora between 1 and 30
)
, primer_dia_julio as (
  select *, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where periodo='202607'
)
, dia1_entrantes as (
  select id_loan, saldo from primer_dia_julio where rn=1 and mora=1
)
, fotos_julio_lag as (
  select id_loan, fechaproceso, saldo, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos where periodo='202607'
)
, nuevos_julio as (
  select id_loan, saldo from fotos_julio_lag where mora_ant=0 and mora=1 and cast(substr(fechaproceso,7,2) as int)<>1
)
, nuestro_bruto as (
  select id_loan, saldo from stock_previo
  union all select id_loan, saldo from dia1_entrantes
  union all select id_loan, saldo from nuevos_julio
)
, nuestro as (
  select id_loan, max(saldo) as saldo from nuestro_bruto group by 1
)
, oficial as (
  select id_ihfintech_loan as id_loan, monto_asignado, fecha_de_vencimiento_cuota
  from vw_seguimiento_diario_cohorte_tramo
  where fase_estrategia='TEMPRANA' and mes_asignacion='202607' and fecha=fecha_ancla
)
, solo_oficial as (
  select o.* from oficial o
  left join nuestro n on n.id_loan = o.id_loan
  where n.id_loan is null
)
, mambu_flags as (
  select id_loan, max(status) as status, max(last_in_chain) as last_in_chain
  from fotos group by 1
)
, clasificado as (
  select so.id_loan, so.monto_asignado
  from solo_oficial so
  join mambu_flags m on m.id_loan = so.id_loan
  where m.status in ('ACTIVE','COMPLETED') and m.last_in_chain = 1
)
, stock_julio_ids as (
  select id_loan from primer_dia_julio where rn=1 and mora between 1 and 30 and saldo > 0
)
, entradas_reales_julio as (
  select distinct id_loan from fotos_julio_lag where mora_ant=0 and mora=1
)
, cuotas_1dia_tarde_julio as (
  -- FIX 2026-08-20: filtrar por fecha_pago (fechavencimiento+1) cayendo en
  -- julio, no por fechavencimiento -- incluye el 30-jun (fecha_pago=1-jul),
  -- el hueco de frontera de mes que encontro Q5 originalmente.
  select c.id_ihfintech_loan as id_loan, c.fechavencimiento
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and date_add('day', 1, c.fechavencimiento) >= date('2026-07-01')
    and date_add('day', 1, c.fechavencimiento) <= date('2026-07-31')
    and c.installmentstate = 'PAID'
    and c.dias_vencimiento_a_pago = 1
)
, entradas_fantasma_julio as (
  select distinct cu.id_loan
  from cuotas_1dia_tarde_julio cu
  where cu.id_loan not in (select id_loan from stock_julio_ids)
    and cu.id_loan not in (select id_loan from entradas_reales_julio)
)
select
  count(*) as total_bug9_bucket,
  round(sum(monto_asignado),0) as total_bug9_monto,
  sum(case when ef.id_loan is not null then 1 else 0 end) as cubiertos_por_fantasma,
  round(sum(case when ef.id_loan is not null then monto_asignado else 0 end),0) as monto_cubierto,
  sum(case when ef.id_loan is null then 1 else 0 end) as no_cubiertos,
  round(sum(case when ef.id_loan is null then monto_asignado else 0 end),0) as monto_no_cubierto
from clasificado cl
left join entradas_fantasma_julio ef on ef.id_loan = cl.id_loan
;

-- ---------------------------------------------------------------------
-- Q5b. Caracterizacion del gap de Q5 (291 creditos no cubiertos). Cruza cada
-- uno contra su cuota vencida mas reciente <= fecha_ancla. Resultado: 281/291
-- (96.6%) vencieron el 30-jun (ultimo dia del mes ANTERIOR) -- mismo
-- mecanismo de bug 9, pero fuera de la ventana fechavencimiento>=01-jul que
-- usa la capa fantasma -- hueco de frontera de mes, analogo a bug 12.
-- ---------------------------------------------------------------------
-- (mismas CTEs "clasificado"/"entradas_fantasma_julio" de Q5; "no_cubiertos"
-- = clasificado LEFT JOIN entradas_fantasma_julio WHERE ef.id_loan IS NULL,
-- luego cruzar contra dts_cobranza_creditos_cuotas por fechavencimiento<=
-- fecha_ancla, row_number() partition by id_loan order by fechavencimiento
-- desc, rn=1 -- ver query completa en el historial de la sesion 2026-08-20
-- si se necesita reconstruir; el resultado esta documentado en BUGS.md bug 14
-- y reconciliacion_vw_seguimiento_temprana.md, pendiente 1).

-- ---------------------------------------------------------------------
-- Q6. Reconstruccion de "solo nuestro" (creditos que TENEMOS pero la vista
-- oficial no incluye en TEMPRANA/julio) categorizado contra dts_asignaciones_
-- gestiones_cobranza (cruce via dni+producto, no id_ihfintech_loan directo).
-- Pendiente 4: la query exacta de la sesion 2026-08-19 (998/119/186/116=1,419
-- vs. 1,224 reportado) no es reproducible: no quedo en el repo. Esta
-- reconstruccion (categorias mutuamente excluyentes) da 1,246 -- 1.8% del
-- 1,224 original, valida el total de forma razonable aunque el desglose por
-- motivo no calce 1 a 1 contra la sesion perdida.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260731'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    substr(d.fechaproceso,1,6) as periodo
  , cast(substr(d.fechaproceso,7,2) as int) as dia
  , d.id_loan, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
)
, cierre_junio as (
  select *, row_number() over (partition by id_loan order by dia desc) as rn
  from fotos where periodo = '202606'
)
, stock_previo as (
  select id_loan, saldo from cierre_junio where rn=1 and mora between 1 and 30
)
, primer_dia_julio as (
  select *, row_number() over (partition by id_loan order by dia asc) as rn
  from fotos where periodo='202607'
)
, dia1_entrantes as (
  select id_loan, saldo from primer_dia_julio where rn=1 and mora=1
)
, fotos_julio_lag as (
  select id_loan, dia, saldo, mora,
    lag(mora) over (partition by id_loan order by dia) as mora_ant
  from fotos where periodo='202607'
)
, nuevos_julio as (
  select id_loan, saldo from fotos_julio_lag where mora_ant=0 and mora=1 and dia<>1
)
, nuestro_bruto as (
  select id_loan, saldo from stock_previo
  union all select id_loan, saldo from dia1_entrantes
  union all select id_loan, saldo from nuevos_julio
)
, nuestro as (
  select id_loan, max(saldo) as saldo from nuestro_bruto group by 1
)
, oficial as (
  select distinct id_ihfintech_loan as id_loan
  from vw_seguimiento_diario_cohorte_tramo
  where fase_estrategia='TEMPRANA' and mes_asignacion='202607' and fecha=fecha_ancla
)
, solo_nuestro as (
  select n.id_loan, n.saldo
  from nuestro n
  left join oficial o on o.id_loan = n.id_loan
  where o.id_loan is null
)
, dni_producto as (
  select distinct id_ihfintech_loan as id_loan, dni, producto
  from dts_cobranza_creditos_cuotas
  where status='ACTIVE' and flg_last_loan_in_chain=1
)
, asig_julio as (
  select
    dp.id_loan,
    max(case when a.grupo_control = 'CONTROL' then 1 else 0 end) as alguna_vez_control,
    max(case when a.fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana,
    max(case when a.fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_escalado
  from dni_producto dp
  join dts_asignaciones_gestiones_cobranza a
    on a.dni_ce = dp.dni and a.producto = dp.producto
   and a.fecha_base between '2026-07-01' and '2026-07-31'
  group by 1
)
select
  case
    when aj.id_loan is null then 'no_aparece_en_asignaciones'
    when aj.alguna_vez_control = 1 then 'grupo_control'
    when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0 then 'escalado_sin_temprana'
    when aj.alguna_vez_temprana = 1 then 'aparece_temprana_pero_no_en_oficial'
    else 'otro'
  end as motivo
, count(*) as creditos
, round(sum(sn.saldo),0) as saldo
from solo_nuestro sn
left join asig_julio aj on aj.id_loan = sn.id_loan
group by 1
order by 2 desc
;

-- NOTA: se intento la misma descomposicion stock-vs-nuevo (pendiente 2, ver
-- reconciliacion_agosto.sql) para julio, cruzando contra la vista oficial en
-- mes_asignacion='202606' -- la vista no tiene datos de junio para
-- fase_estrategia='TEMPRANA' (query vacia), asi que esta comparacion solo
-- fue posible en agosto (que si tiene julio como referencia).

-- ---------------------------------------------------------------------
-- Q7. SOLO OFICIAL, por credito (no agregado) -- mismas CTEs que Q1, sin el
-- group by final, para exportar un dataset filtrable (2026-08-21, a pedido
-- del usuario). Resultado en datos_reconciliacion_temprana/solo_oficial_
-- motivo_julio.csv (3,265 filas: 3,128 dayslate_cero_bug9 + 137
-- excluido_chain + 0 status_no_activo + 0 sin_match_mambu -- ligeramente
-- distinto a los 3,210/313/1 de la sesion 2026-08-19, misma causa que Q1:
-- reconstruccion sin el SQL original, misma escala).
-- ---------------------------------------------------------------------
-- (mismas CTEs loan_chain/raw/dedup/fotos/cierre_junio/stock_previo/
-- primer_dia_julio/dia1_entrantes/fotos_julio_lag/nuevos_julio/nuestro_
-- bruto/nuestro/oficial/solo_oficial/mambu_flags de Q1 -- ver ese bloque)
-- select
--   so.id_loan, so.monto_asignado
-- , case
--     when m.id_loan is null then 'Sin match en Mambu'
--     when m.status not in ('ACTIVE','COMPLETED') then 'Status no activo'
--     when m.last_in_chain <> 1 then 'Reenganche (excluido por flg_last_loan_in_chain)'
--     else 'Punto ciego dayslate (bug 9)'
--   end as motivo
-- from solo_oficial so
-- left join mambu_flags m on m.id_loan = so.id_loan
-- ;

-- ---------------------------------------------------------------------
-- Q8. SOLO NUESTRO, por credito (no agregado) -- mismas CTEs que Q6, sin el
-- group by final (2026-08-21, a pedido del usuario). Resultado en
-- datos_reconciliacion_temprana/solo_nuestro_motivo_julio.csv (1,246 filas:
-- 779 grupo_control + 94 escalado_sin_temprana + 6 aparece_temprana_pero_no_
-- en_oficial + 367 no_aparece_en_asignaciones -- misma escala que la
-- reconstruccion agregada de Q6, dentro del margen esperado).
--
-- VERIFICADO 2026-08-21 (el usuario pidio confirmar, no asumir): la
-- hipotesis original de "escalado por arrastre de DNI" (otro credito del
-- mismo dni+producto en ESPECIALIZADA/RECOVERY) es FALSA -- se corrio una
-- query de verificacion (ver scratchpad de la sesion) cruzando los 94
-- creditos contra TODOS los id_loan del mismo dni+producto: **94/94 (100%)
-- son el UNICO credito de su dni+producto** -- no hay hermano que arrastre.
-- Lo que si se confirmo con datos: los 94 mantienen la MISMA fase_estrategia
-- (ESPECIALIZADA o RECOVERY) los 31 dias de julio sin cambiar nunca (0 de 94
-- cambia de fase), mientras que 60 de 94 (64%) tienen en algun momento del
-- mes una mora dayslate <=5 dias (promedio mora_min=8.6, mora_max=9.5) --
-- es decir, nuestra medicion ve una mora fresca/baja, pero la asignacion los
-- mantiene fijos en Especializada/Recovery. Lectura: es una fase "pegajosa"
-- (probablemente por historia de mora anterior a julio o un criterio
-- acumulado de riesgo en gestiones_cobranza, no re-evaluado a la baja cada
-- cuota), no un arrastre de otro credito del cliente. Mecanismo exacto de
-- por que la fase no baja: NO investigado a fondo (fuera de lo pedido),
-- queda como hallazgo, no como pendiente bloqueante.
-- ---------------------------------------------------------------------
-- (mismas CTEs de Q6 -- loan_chain/raw/dedup/fotos/.../dni_producto/
-- asig_julio -- ver ese bloque)
-- select
--   sn.id_loan, sn.saldo
-- , case
--     when aj.id_loan is null then 'Sin asignar'
--     when aj.alguna_vez_control = 1 then 'Grupo de control'
--     when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0
--       then 'Escalado a Especializada/Recovery (fase fija, no baja aunque dayslate muestre mora baja)'
--     when aj.alguna_vez_temprana = 1
--       then 'Temprana en asignacion, sin match en vista oficial'
--     else 'Otro / sin clasificar'
--   end as motivo
-- from solo_nuestro sn
-- left join asig_julio aj on aj.id_loan = sn.id_loan
-- ;


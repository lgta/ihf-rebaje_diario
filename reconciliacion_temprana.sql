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
--
-- **SUPERADA 2026-08-21 (continuacion) -- ver bug 15 en BUGS.md.** El cruce
-- dni+producto de abajo (CTE "dni_producto", filtro status='ACTIVE') resulto
-- ser innecesario e impreciso: dts_asignaciones_gestiones_cobranza SI tiene
-- id_ihfintech_loan directo, en la columna "aux02" (99.97% de match real
-- contra dts_okaapi_loans, sin nombre descriptivo, por eso paso desapercibida
-- hasta que el usuario la senalo). Query corregida (mismo resultado que
-- produjo el CSV final commiteado): Q11 mas abajo. Se deja esta version
-- como historial de la investigacion, no usar para nada nuevo.
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
--
-- RE-VERIFICADO 2026-08-21 (continuacion): quedaba solo como comentario/
-- pseudocodigo, nunca se habia corrido como SQL ejecutable real -- pedido
-- explicito del usuario esta sesion (no confiar en el CSV guardado).
-- Re-corrida completa desde cero contra Athena: **reproduce EXACTO** el CSV
-- ya commiteado a nivel credito (id_loan, monto, motivo) -- 3,265/3,265
-- filas identicas, mismos 3,128/137 por motivo. La unica diferencia
-- encontrada al diffear fue CRLF (CSV viejo) vs LF (export nuevo), no datos
-- -- sin no-determinismo de bug 11, sin drift de datos desde el 21-ago.
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
select
  so.id_loan, so.monto_asignado
, case
    when m.id_loan is null then 'Sin match en Mambu'
    when m.status not in ('ACTIVE','COMPLETED') then 'Status no activo'
    when m.last_in_chain <> 1 then 'Reenganche (excluido por flg_last_loan_in_chain)'
    else 'Punto ciego dayslate (bug 9)'
  end as motivo
from solo_oficial so
left join mambu_flags m on m.id_loan = so.id_loan
;

-- ---------------------------------------------------------------------
-- Q8. SOLO NUESTRO, por credito (no agregado) -- mismas CTEs que Q6, sin el
-- group by final (2026-08-21, a pedido del usuario). Resultado FINAL en
-- datos_reconciliacion_temprana/solo_nuestro_motivo_julio.csv (1,246 filas:
-- 779 Grupo de control + 367 Sin asignar + 58 Doble producto en otra fase +
-- 36 Escalado fase fija (sin otro credito) + 6 Revisar).
--
-- VERIFICADO 2026-08-21 (2 rondas -- el usuario pidio confirmar, no asumir,
-- y luego corrigio mi primera verificacion):
-- Ronda 1: la hipotesis de "arrastre de DNI" dentro del MISMO producto es
-- FALSA -- 94/94 (100%) de los "escalado_sin_temprana" son el UNICO credito
-- de su dni+producto, no hay hermano del mismo producto.
-- Ronda 2 (a pedido del usuario, hipotesis "doble producto en otra fase"):
-- SI existe arrastre, pero por OTRO PRODUCTO del mismo dni -- 58/94 (62%)
-- tienen un credito hermano de PRODUCTO DISTINTO que esta en ESPECIALIZADA/
-- RECOVERY (confirma la hipotesis del usuario para esa mayoria). Los 36/94
-- (38%) restantes no tienen NINGUN otro credito (ni mismo ni distinto
-- producto) -- para esos sigue aplicando el hallazgo de la ronda 1: fase
-- fija/pegajosa en el credito mismo (probablemente por historia previa a
-- julio), sin ningun arrastre de por medio. Por eso el motivo quedo
-- DIVIDIDO en 2 categorias, no una sola -- aplicar un solo label a los 94
-- habria sido igual de impreciso que la hipotesis original descartada.
--
-- RE-VERIFICADO 2026-08-21 (continuacion): igual que Q7, quedaba solo como
-- pseudocodigo. Re-corrida completa desde cero: **reproduce EXACTO** el CSV
-- ya commiteado a nivel credito -- 1,246/1,246 filas identicas, mismos
-- 779/367/58/36/6 por motivo. Misma conclusion que Q7: sin no-determinismo,
-- sin drift de datos.
--
-- **SUPERADA 2026-08-21 (continuacion, mismo dia) -- ver bug 15 en BUGS.md.**
-- El crosswalk dni+producto (CTE "dni_producto", filtro status='ACTIVE') que
-- generaba estos 779/367/58/36/6 resulto impreciso -- dts_asignaciones_
-- gestiones_cobranza tiene id_ihfintech_loan directo en "aux02". El CSV
-- solo_nuestro_motivo_julio.csv YA FUE REGENERADO con el metodo corregido
-- (Q12 mas abajo) -- los numeros de este bloque (779/367/58/36/6) ya NO
-- coinciden con el CSV actual del repo (ahora 1017/120/65/36/8). Se deja
-- esta version como historial de la investigacion que llevo al hallazgo de
-- aux02, no usar para nada nuevo.
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
, otros_productos_dni as (
  select distinct dp2.id_loan as id_loan_hermano, dp2.dni, dp2.producto
  from dni_producto dp2
)
, hermano_otro_producto_escalado as (
  select distinct sn.id_loan
  from solo_nuestro sn
  join dni_producto dp on dp.id_loan = sn.id_loan
  join otros_productos_dni op on op.dni = dp.dni and op.producto <> dp.producto
  join dts_asignaciones_gestiones_cobranza a
    on a.dni_ce = op.dni and a.producto = op.producto
   and a.fecha_base between '2026-07-01' and '2026-07-31'
   and a.fase_estrategia in ('ESPECIALIZADA','RECOVERY')
)
select
  sn.id_loan, sn.saldo
, case
    when aj.id_loan is null then 'Sin asignar'
    when aj.alguna_vez_control = 1 then 'Grupo de control'
    when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0 and hop.id_loan is not null
      then 'Doble producto en otra fase'
    when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0
      then 'Escalado, fase fija (sin otro credito del cliente)'
    when aj.alguna_vez_temprana = 1
      then 'Revisar'
    else 'Otro / sin clasificar'
  end as motivo
from solo_nuestro sn
left join asig_julio aj on aj.id_loan = sn.id_loan
left join hermano_otro_producto_escalado hop on hop.id_loan = sn.id_loan
;

-- =====================================================================
-- Q9-Q10: sesion 2026-08-21 (continuacion) -- investigacion de los 2 huecos
-- de "solo nuestro" que quedaban sin explicar (tarea 3 del prompt de
-- continuacion de ESTADO.md). "Doble producto en otra fase"/"Escalado, fase
-- fija" ya se habian investigado antes (ver arriba) -- estos son los 2 que
-- faltaban: "Sin asignar" (367 creditos) y "Revisar" (6 creditos).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q9. "Sin asignar" (367 creditos / S/322,602 en el CSV) -- HALLAZGO: la
-- MAYORIA (228/367, 62.1%) es un bug de matching en el crosswalk de Q6/Q8,
-- no ausencia real de gestion. La CTE "dni_producto" de Q6/Q8 filtra
-- status='ACTIVE' -- un credito que en dts_cobranza_creditos_cuotas hoy
-- muestra status='COMPLETED' (ya termino de pagar, aunque en julio tenia
-- mora) queda FUERA del crosswalk por construccion, sin importar si el
-- negocio si lo asigno ese mes -- el join a asig_julio siempre da null y
-- cae en "Sin asignar" sin importar la realidad.
--
-- Verificado: de los 367, 269 (73.3%) tienen status='COMPLETED' hoy. Al
-- reconstruir el crosswalk SIN el filtro de status (cualquier status,
-- last_in_chain=1) y re-clasificar solo estos 367:
--   - 218 (59.4%, ~S/120,503) en realidad SI tienen match -> son Grupo de
--     control (mismo patron que el 62.9% ya explicado del resto de "solo
--     nuestro").
--   - 7 (1.9%) en realidad estan Escalado.
--   - 3 (0.8%) en realidad aparecen en TEMPRANA julio -> "Revisar" (ver Q10,
--     ese motivo tambien resulta ser un artefacto, no un hueco real).
--   - 106 (28.9%, ~S/160,237) SI son genuinamente "sin gestion en julio" --
--     su dni NO aparece en dts_asignaciones_gestiones_cobranza en NINGUN
--     dia de julio, con NINGUN producto. Esto es el hallazgo real: creditos
--     fuera de la asignacion operativa real del negocio ese mes.
--   - 10 (2.7%, ~S/12,150) tienen su dni SI presente en julio pero con un
--     producto DISTINTO al que muestra dts_cobranza_creditos_cuotas --
--     consistente con el ~3.5% de calidad de cruce dni+producto ya
--     documentado en FUENTES_DATOS.md (match ~96.5%), no un hallazgo nuevo.
--   - 23 (6.3%, ~S/26,481) no tienen NINGUNA fila en dts_cobranza_creditos_
--     cuotas para ese id_loan con flg_last_loan_in_chain=1 -- problema de
--     datos mas profundo, bajo volumen, no investigado a fondo.
--
-- CONCLUSION: "Sin asignar" como motivo unico sobreestima el hueco real --
-- el hueco genuino (creditos fuera de la operacion real de julio) es ~106
-- creditos, no 367. El resto (261) es ruido de la propia query de
-- reconciliacion (filtro de status en el crosswalk demasiado estricto +
-- calidad de cruce dni+producto ya conocida). PENDIENTE si se quiere
-- corregir en produccion: usar el crosswalk sin filtro de status en Q6/Q8 --
-- bajo impacto en el resto de motivos (no se re-corrio el CSV completo con
-- el fix, solo se aislo el sub-bucket "Sin asignar" para esta investigacion).
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
, dni_producto_active_only as (
  select distinct id_ihfintech_loan as id_loan, dni, producto
  from dts_cobranza_creditos_cuotas
  where status='ACTIVE' and flg_last_loan_in_chain=1
)
, asig_julio_original as (
  select
    dp.id_loan,
    max(case when a.grupo_control = 'CONTROL' then 1 else 0 end) as alguna_vez_control,
    max(case when a.fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana,
    max(case when a.fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_escalado
  from dni_producto_active_only dp
  join dts_asignaciones_gestiones_cobranza a
    on a.dni_ce = dp.dni and a.producto = dp.producto
   and a.fecha_base between '2026-07-01' and '2026-07-31'
  group by 1
)
, otros_productos_dni as (
  select distinct dp2.id_loan as id_loan_hermano, dp2.dni, dp2.producto
  from dni_producto_active_only dp2
)
, hermano_otro_producto_escalado as (
  select distinct sn.id_loan
  from solo_nuestro sn
  join dni_producto_active_only dp on dp.id_loan = sn.id_loan
  join otros_productos_dni op on op.dni = dp.dni and op.producto <> dp.producto
  join dts_asignaciones_gestiones_cobranza a
    on a.dni_ce = op.dni and a.producto = op.producto
   and a.fecha_base between '2026-07-01' and '2026-07-31'
   and a.fase_estrategia in ('ESPECIALIZADA','RECOVERY')
)
, clasificado_solo_nuestro as (
  select
    sn.id_loan, sn.saldo
  , case
      when aj.id_loan is null then 'Sin asignar'
      when aj.alguna_vez_control = 1 then 'Grupo de control'
      when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0 and hop.id_loan is not null
        then 'Doble producto en otra fase'
      when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0
        then 'Escalado, fase fija (sin otro credito del cliente)'
      when aj.alguna_vez_temprana = 1
        then 'Revisar'
      else 'Otro / sin clasificar'
    end as motivo
  from solo_nuestro sn
  left join asig_julio_original aj on aj.id_loan = sn.id_loan
  left join hermano_otro_producto_escalado hop on hop.id_loan = sn.id_loan
)
-- crosswalk SIN filtro de status (cualquier status, last_in_chain=1) para
-- probar si el filtro status='ACTIVE' de arriba causa el falso "Sin asignar"
, dni_producto_all_status as (
  select distinct id_ihfintech_loan as id_loan, dni, producto
  from dts_cobranza_creditos_cuotas
  where flg_last_loan_in_chain=1
)
, asig_julio_fix as (
  select
    dp.id_loan,
    max(case when a.grupo_control = 'CONTROL' then 1 else 0 end) as alguna_vez_control,
    max(case when a.fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana,
    max(case when a.fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_escalado
  from dni_producto_all_status dp
  join dts_asignaciones_gestiones_cobranza a
    on a.dni_ce = dp.dni and a.producto = dp.producto
   and a.fecha_base between '2026-07-01' and '2026-07-31'
  group by 1
)
, dni_julio_cualquier_producto as (
  select distinct dni_ce from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-07-01' and '2026-07-31'
)
select
  case
    when ajf.id_loan is not null and ajf.alguna_vez_control = 1 then 'BUG: en realidad es Grupo de control'
    when ajf.id_loan is not null and ajf.alguna_vez_temprana = 1 then 'BUG: en realidad aparece en TEMPRANA julio (ver Q10)'
    when ajf.id_loan is not null and ajf.alguna_vez_escalado = 1 then 'BUG: en realidad esta Escalado'
    when dpas.id_loan is null then 'Sin fila en dts_cobranza_creditos_cuotas (problema de datos, no investigado)'
    when djcp.dni_ce is not null then 'Dni aparece en julio con OTRO producto (calidad de cruce ~96.5%, ya conocido)'
    else 'Real: dni NUNCA aparece en asignaciones de julio (fuera de la operacion real ese mes)'
  end as diagnostico
, count(*) as creditos
, round(sum(csn.saldo),0) as saldo
from clasificado_solo_nuestro csn
left join dni_producto_all_status dpas on dpas.id_loan = csn.id_loan
left join asig_julio_fix ajf on ajf.id_loan = csn.id_loan
left join dni_julio_cualquier_producto djcp on djcp.dni_ce = dpas.dni
where csn.motivo = 'Sin asignar'
group by 1
order by 3 desc
;

-- NOTA 2026-08-21 (mismo dia, continuacion): esta investigacion (Q9) fue la
-- que llevo al usuario a senalar que dts_asignaciones_gestiones_cobranza SI
-- tiene id_ihfintech_loan directo -- columna "aux02", ver bug 15 en BUGS.md.
-- Con aux02, el "Sin asignar" REAL termino siendo 120 creditos (no ~106 como
-- estimaba Q9 con el metodo del filtro de status, ni 367 con el metodo
-- original) -- ver Q11/Q12 mas abajo para la version final corregida. Q9 se
-- deja como historial de la investigacion, no como el numero de referencia.

-- ---------------------------------------------------------------------
-- Q10. "Revisar" (6 creditos / S/6,663) -- caso por caso, factible a mano.
-- HALLAZGO: NO es un hueco real -- es un artefacto de la propia query de
-- reconciliacion. Los 6 tienen fase_estrategia='ESPECIALIZADA' exactamente
-- el 2026-07-01 (su fecha_ancla, el primer dia que aparecen en julio en
-- dts_asignaciones_gestiones_cobranza) -- la vista oficial ANCLA
-- fase_estrategia a fecha_ancla y la deja fija todo el mes, asi que
-- correctamente los reporta como ESPECIALIZADA los 31 dias (verificado:
-- fases_oficial_vistas='ESPECIALIZADA' para los 6, filas_oficial_
-- julio=31). Pero la CTE "asig_julio" de Q6/Q8 usa "alguna_vez_temprana"
-- = maximo sobre TODOS los dias de julio del feed CRUDO (no anclado) -- y
-- el feed crudo SI les muestra fase_estrategia='TEMPRANA' en algun otro dia
-- del mes (la fase fluctua dia a dia en la fuente cruda, a diferencia del
-- anclaje de la vista oficial). Por eso "alguna_vez_temprana=1" dispara el
-- motivo "Revisar", aunque la vista oficial nunca los tuvo en TEMPRANA ese
-- mes. Mismo tipo de hallazgo que bug 13 (fase fija/pegajosa) pero en la
-- direccion contraria: aca el problema es que NUESTRA query no replica el
-- anclaje a fecha_ancla que si usa la vista oficial. CONCLUSION: los 6 no
-- son un hueco -- estan correctamente excluidos de TEMPRANA oficial. Ver
-- reconciliacion_vw_seguimiento_temprana.md para el detalle completo.
-- ---------------------------------------------------------------------
with dni_producto_active_only as (
  select distinct id_ihfintech_loan as id_loan, dni, producto
  from dts_cobranza_creditos_cuotas
  where status='ACTIVE' and flg_last_loan_in_chain=1
)
, ids_revisar as (
  -- los 6 id_loan de motivo='Revisar' en el CSV solo_nuestro_motivo_julio.csv
  select * from (values
    ('981b9371-f3e1-4239-9798-122bca23332d'),
    ('1b5300a3-c75f-4b90-b993-611c035bd314'),
    ('fa6e1966-89bf-497c-b31a-7ce5f1086f3c'),
    ('dba528d0-0560-43d6-a29d-3b448d5ae5dc'),
    ('bf11815b-5eb9-4055-a214-8331caff785e'),
    ('15c17f8c-ba21-48e5-b2e1-56f0d31ba89d')
  ) as t(id_loan)
)
, dp as (
  select ir.id_loan, dp.dni, dp.producto
  from ids_revisar ir
  left join dni_producto_active_only dp on dp.id_loan = ir.id_loan
)
, asignacion_resumen as (
  select
    dp.id_loan
  , min(a.fecha_base) as primera_fecha, max(a.fecha_base) as ultima_fecha
  , array_join(array_agg(distinct a.fase_estrategia), '|') as fases_vistas_feed_crudo
  from dp
  join dts_asignaciones_gestiones_cobranza a
    on a.dni_ce = dp.dni and a.producto = dp.producto
   and a.fecha_base between '2026-07-01' and '2026-07-31'
  group by dp.id_loan
)
, fase_en_ancla as (
  select dp.id_loan, a.fase_estrategia as fase_en_fecha_ancla
  from dp
  join dts_asignaciones_gestiones_cobranza a
    on a.dni_ce = dp.dni and a.producto = dp.producto
   and a.fecha_base = '2026-07-01'
)
, oficial_julio as (
  select
    id_ihfintech_loan as id_loan
  , array_join(array_agg(distinct fase_estrategia), '|') as fases_oficial_vistas
  , count(*) as filas_oficial_julio
  from vw_seguimiento_diario_cohorte_tramo
  where id_ihfintech_loan in (select id_loan from ids_revisar)
    and fecha between date('2026-07-01') and date('2026-07-31')
  group by 1
)
select
  ir.id_loan, ar.fases_vistas_feed_crudo, fea.fase_en_fecha_ancla,
  oc.fases_oficial_vistas, oc.filas_oficial_julio
from ids_revisar ir
left join asignacion_resumen ar on ar.id_loan = ir.id_loan
left join fase_en_ancla fea on fea.id_loan = ir.id_loan
left join oficial_julio oc on oc.id_loan = ir.id_loan
order by ir.id_loan
;

-- NOTA 2026-08-21 (mismo dia, continuacion): con el fix de aux02 (bug 15),
-- "Revisar" paso de 6 a 8 creditos (ver Q11/Q12) -- el mecanismo explicado
-- arriba (anclaje a fecha_ancla que la query propia no replicaba) sigue
-- aplicando igual, es independiente del fix de aux02; no se re-verificaron
-- los 2 creditos nuevos caso por caso, pero misma escala y mismo patron
-- esperado (ambos son fenomenos de anclaje/fase, no de matching).

-- =====================================================================
-- Q11-Q12: sesion 2026-08-21 (continuacion, mismo dia) -- FIX de bug 15:
-- dts_asignaciones_gestiones_cobranza SI tiene id_ihfintech_loan directo
-- (columna "aux02", sin nombre descriptivo, senalada por el usuario -- ver
-- bug 15 en BUGS.md). Reemplaza el crosswalk dni+producto (CTE "dni_producto",
-- filtro status='ACTIVE') usado en Q6/Q8 -- ese filtro excluia por
-- construccion cualquier credito ya COMPLETED del cruce, sin importar si el
-- negocio si lo habia gestionado, y ademas heredaba el ~3.5% de error de
-- cruce dni+producto documentado en FUENTES_DATOS.md. Con aux02 el join es
-- directo id_loan=id_loan, sin crosswalk -- inclusive el chequeo de "hermano
-- de otro producto" (antes via dni_producto contra dts_cobranza_creditos_
-- cuotas) ahora se resuelve con el propio dni_ce/producto que trae la fila
-- de asignacion de ESTE credito (via aux02), sin tocar dts_cobranza_
-- creditos_cuotas para nada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q11. Version CORREGIDA de Q6 (agregado) -- reemplaza el crosswalk
-- dni+producto por aux02. Resultado (verificado contra Athena, coincide con
-- el CSV final regenerado en datos_reconciliacion_temprana/solo_nuestro_
-- motivo_julio.csv): 1,017 Grupo de control (antes 779) + 120 Sin asignar
-- (antes 367) + 65 Doble producto en otra fase (antes 58) + 36 Escalado,
-- fase fija (identico, antes y despues -- consistente, ver nota abajo) + 8
-- Revisar (antes 6) = 1,246 total (identico al total viejo). El total no
-- cambia porque "solo_nuestro" (poblacion base, antes de clasificar motivo)
-- no depende del crosswalk -- solo cambia COMO se reparte entre motivos.
-- "Escalado, fase fija" no se mueve porque, por definicion, esos creditos
-- no tienen ningun otro credito del cliente -- no hay hermano que un
-- crosswalk mejor pudiera encontrar de mas.
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
, mis_asignaciones as (
  select
    a.aux02 as id_loan, a.dni_ce, a.producto, a.fase_estrategia, a.grupo_control
  from dts_asignaciones_gestiones_cobranza a
  where a.fecha_base between '2026-07-01' and '2026-07-31'
)
, asig_julio as (
  select
    id_loan,
    max(dni_ce) as dni_ce,
    max(producto) as producto,
    max(case when grupo_control = 'CONTROL' then 1 else 0 end) as alguna_vez_control,
    max(case when fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana,
    max(case when fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_escalado
  from mis_asignaciones
  group by id_loan
)
, dni_producto_escalados as (
  select distinct dni_ce, producto
  from mis_asignaciones
  where fase_estrategia in ('ESPECIALIZADA','RECOVERY')
)
, hermano_otro_producto_escalado as (
  select distinct aj.id_loan
  from asig_julio aj
  join dni_producto_escalados dpe
    on dpe.dni_ce = aj.dni_ce and dpe.producto <> aj.producto
)
select
  case
    when aj.id_loan is null then 'Sin asignar'
    when aj.alguna_vez_control = 1 then 'Grupo de control'
    when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0 and hop.id_loan is not null
      then 'Doble producto en otra fase'
    when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0
      then 'Escalado, fase fija (sin otro credito del cliente)'
    when aj.alguna_vez_temprana = 1
      then 'Revisar'
    else 'Otro / sin clasificar'
  end as motivo
, count(*) as creditos
, round(sum(sn.saldo),0) as saldo
from solo_nuestro sn
left join asig_julio aj on aj.id_loan = sn.id_loan
left join hermano_otro_producto_escalado hop on hop.id_loan = sn.id_loan
group by 1
order by 2 desc
;

-- ---------------------------------------------------------------------
-- Q12. Version CORREGIDA de Q8 (por credito, export) -- mismas CTEs de Q11,
-- sin el group by final. Esta es la query que efectivamente regenero
-- datos_reconciliacion_temprana/solo_nuestro_motivo_julio.csv (2026-08-21,
-- continuacion) -- reemplaza a Q8 como la version vigente del CSV.
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
, mis_asignaciones as (
  select
    a.aux02 as id_loan, a.dni_ce, a.producto, a.fase_estrategia, a.grupo_control
  from dts_asignaciones_gestiones_cobranza a
  where a.fecha_base between '2026-07-01' and '2026-07-31'
)
, asig_julio as (
  select
    id_loan,
    max(dni_ce) as dni_ce,
    max(producto) as producto,
    max(case when grupo_control = 'CONTROL' then 1 else 0 end) as alguna_vez_control,
    max(case when fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana,
    max(case when fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_escalado
  from mis_asignaciones
  group by id_loan
)
, dni_producto_escalados as (
  select distinct dni_ce, producto
  from mis_asignaciones
  where fase_estrategia in ('ESPECIALIZADA','RECOVERY')
)
, hermano_otro_producto_escalado as (
  select distinct aj.id_loan
  from asig_julio aj
  join dni_producto_escalados dpe
    on dpe.dni_ce = aj.dni_ce and dpe.producto <> aj.producto
)
select
  sn.id_loan, sn.saldo
, case
    when aj.id_loan is null then 'Sin asignar'
    when aj.alguna_vez_control = 1 then 'Grupo de control'
    when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0 and hop.id_loan is not null
      then 'Doble producto en otra fase'
    when aj.alguna_vez_escalado = 1 and aj.alguna_vez_temprana = 0
      then 'Escalado, fase fija (sin otro credito del cliente)'
    when aj.alguna_vez_temprana = 1
      then 'Revisar'
    else 'Otro / sin clasificar'
  end as motivo
from solo_nuestro sn
left join asig_julio aj on aj.id_loan = sn.id_loan
left join hermano_otro_producto_escalado hop on hop.id_loan = sn.id_loan
;


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
  select *, row_number() over (
      partition by id_loan, fechaproceso order by lastmodifieddate desc, id desc) as rn_dedup
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
  select *, row_number() over (
      partition by id_loan, fechaproceso order by lastmodifieddate desc, id desc) as rn_dedup
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
  select *, row_number() over (
      partition by id_loan, fechaproceso order by lastmodifieddate desc, id desc) as rn_dedup
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
  select *, row_number() over (
      partition by id_loan, fechaproceso order by lastmodifieddate desc, id desc) as rn_dedup
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

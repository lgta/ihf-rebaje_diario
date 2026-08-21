-- =====================================================================
-- RECONCILIACION contra vw_seguimiento_diario_cohorte_tramo -- extension a
-- AGOSTO 2026 (parcial, corte 20-ago). Ejecutado 2026-08-20. Pendiente 2 de
-- reconciliacion_vw_seguimiento_temprana.md ("Pendientes para cerrar
-- TEMPRANA por completo"). Dedup de bug 11 ya aplicado (saldo<>0 antes de
-- lastmodifieddate).
--
-- Resultado: el ~27% de punto ciego (bug 9) NO repite igual en el agregado
-- de agosto a mitad de mes (19.1%, 1,772/9,274) -- pero al descomponer por
-- cohorte, "nuevos en agosto" da 30.0% (mayor que julio) y "ya estaba en
-- julio" (analogo a stock) da solo 8.5%. Como agosto esta al dia 20 de 31,
-- "nuevos" (tasa alta, crece dia a dia) todavia no termino de acumularse,
-- mientras "stock" (tamano fijo desde el cierre de julio, tasa baja) ya
-- pesa su proporcion completa -- eso diluye el agregado. Re-medir cuando
-- agosto cierre para una comparacion real mes-completo vs. mes-completo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Reconciliacion agregada de poblacion, agosto 2026 (parcial, corte
-- 20-ago). Mismo patron que reconciliacion_temprana.sql Q1, con periodo
-- 202608 y stock anclado al cierre de julio.
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
  where a.fechaproceso between '20260701' and '20260820'
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
, cierre_julio as (
  select *, row_number() over (partition by id_loan order by dia desc) as rn
  from fotos where periodo = '202607'
)
, stock_previo as (
  select id_loan, saldo from cierre_julio where rn=1 and mora between 1 and 30
)
, primer_dia_agosto as (
  select *, row_number() over (partition by id_loan order by dia asc) as rn
  from fotos where periodo='202608'
)
, dia1_entrantes as (
  select id_loan, saldo from primer_dia_agosto where rn=1 and mora=1
)
, fotos_agosto_lag as (
  select id_loan, dia, saldo, mora,
    lag(mora) over (partition by id_loan order by dia) as mora_ant
  from fotos where periodo='202608'
)
, nuevos_agosto as (
  select id_loan, saldo from fotos_agosto_lag where mora_ant=0 and mora=1 and dia<>1
)
, nuestro_bruto as (
  select id_loan, saldo from stock_previo
  union all select id_loan, saldo from dia1_entrantes
  union all select id_loan, saldo from nuevos_agosto
)
, nuestro as (
  select id_loan, max(saldo) as saldo from nuestro_bruto group by 1
)
, oficial as (
  select id_ihfintech_loan as id_loan, monto_asignado, fecha_de_vencimiento_cuota
  from vw_seguimiento_diario_cohorte_tramo
  where fase_estrategia='TEMPRANA' and mes_asignacion='202608' and fecha=fecha_ancla
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
-- Q2. Descomposicion del bucket bug9 (y de oficial_total) por cohorte:
-- creditos que YA estaban en la vista oficial en julio (analogo a "stock")
-- vs. creditos NUEVOS en la vista en agosto (analogo a "nuevos"). Resultado:
-- nuevos 30.0% (1,374/4,581), stock-like 8.5% (398/4,693) -- explica por
-- que el agregado parcial (19.1%) queda por debajo del ~27% de julio: a
-- mitad de mes, "nuevos" (tasa alta) todavia no acumulo su tamano completo.
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
  where a.fechaproceso between '20260701' and '20260820'
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
, cierre_julio as (
  select *, row_number() over (partition by id_loan order by dia desc) as rn
  from fotos where periodo = '202607'
)
, stock_previo as (
  select id_loan, saldo from cierre_julio where rn=1 and mora between 1 and 30
)
, primer_dia_agosto as (
  select *, row_number() over (partition by id_loan order by dia asc) as rn
  from fotos where periodo='202608'
)
, dia1_entrantes as (
  select id_loan, saldo from primer_dia_agosto where rn=1 and mora=1
)
, fotos_agosto_lag as (
  select id_loan, dia, saldo, mora,
    lag(mora) over (partition by id_loan order by dia) as mora_ant
  from fotos where periodo='202608'
)
, nuevos_agosto as (
  select id_loan, saldo from fotos_agosto_lag where mora_ant=0 and mora=1 and dia<>1
)
, nuestro_bruto as (
  select id_loan, saldo from stock_previo
  union all select id_loan, saldo from dia1_entrantes
  union all select id_loan, saldo from nuevos_agosto
)
, nuestro as (
  select id_loan, max(saldo) as saldo from nuestro_bruto group by 1
)
, oficial as (
  select id_ihfintech_loan as id_loan, monto_asignado
  from vw_seguimiento_diario_cohorte_tramo
  where fase_estrategia='TEMPRANA' and mes_asignacion='202608' and fecha=fecha_ancla
)
, oficial_julio as (
  select distinct id_ihfintech_loan as id_loan
  from vw_seguimiento_diario_cohorte_tramo
  where fase_estrategia='TEMPRANA' and mes_asignacion='202607'
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
, clasificado_bug9 as (
  select so.id_loan, so.monto_asignado
  from solo_oficial so
  join mambu_flags m on m.id_loan = so.id_loan
  where m.status in ('ACTIVE','COMPLETED') and m.last_in_chain = 1
)
select
  case when oj.id_loan is not null then 'ya_estaba_en_julio_like_stock' else 'nuevo_en_agosto' end as categoria,
  'oficial_total' as chk,
  count(distinct o.id_loan) as creditos, round(sum(o.monto_asignado),0) as monto
from oficial o
left join oficial_julio oj on oj.id_loan = o.id_loan
group by 1
union all
select
  case when oj.id_loan is not null then 'ya_estaba_en_julio_like_stock' else 'nuevo_en_agosto' end as categoria,
  'bug9_bucket' as chk,
  count(distinct b.id_loan), round(sum(b.monto_asignado),0)
from clasificado_bug9 b
left join oficial_julio oj on oj.id_loan = b.id_loan
group by 1
order by 2, 1
;

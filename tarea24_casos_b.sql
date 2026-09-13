-- =====================================================================
-- TAREA 24 -- CASOS B, uno por uno: la asignacion los tiene en TEMPRANA
-- como `antiguo` el 1-sep, pero dias_atraso_cuota dice mora 0 el 31-ago,
-- el 1-sep y el 2-sep. Son ~25 creditos (~S/63K). ¿Quien tiene razon?
--
-- Se compara, para cada uno:
--   - la cuota que el NEGOCIO considera vencida (fecha_de_vencimiento_cuota
--     de la asignacion) y su estado/fecha de pago en dts_cobranza_creditos_cuotas
--   - la cuota vigente que ve calendario_diario el 1-sep (fechaporvencer)
--   - dayslate de Mambu el 31-ago y el 1-sep, como tercera opinion
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_ago as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , b.status
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260801' and '20260831'
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, ancla_final as (
  select id_loan, saldo, status from (
    select id_loan, saldo, status,
      row_number() over (partition by id_loan order by fechaproceso desc) as rn
    from mambu_ago where rn_dedup = 1
  ) where rn = 1 and saldo > 0
)
, dac as (
  select c.id_ihfintech_loan as id_loan
  , max(case when c.fecha_calendario = date('2026-08-31') then coalesce(c.dias_atraso_cuota,0) end) as m31
  , max(case when c.fecha_calendario = date('2026-09-01') then coalesce(c.dias_atraso_cuota,0) end) as m01
  , max(case when c.fecha_calendario = date('2026-09-02') then coalesce(c.dias_atraso_cuota,0) end) as m02
  , max(case when c.fecha_calendario = date('2026-09-01') then c.fechaporvencer end) as venc_vigente_01
  , max(case when c.fecha_calendario = date('2026-09-01') then c.fecha_pago end)     as fecha_pago_01
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-08-31') and date('2026-09-02')
  group by 1
)
, base as (
  select aux02 as id_loan, cast(fecha_base as date) as fb, fase_estrategia, tipo_mora,
         dias_mora, max_dias_mora_dni, monto_capital_pendiente, fecha_de_vencimiento_cuota
  from dts_asignaciones_gestiones_cobranza
  where cast(fecha_base as date) between date '2026-09-01' and date '2026-09-30'
)
, primer as (select id_loan, min(fb) as fecha_ancla from base group by 1)
, anc as (
  select p.id_loan, p.fecha_ancla
  , max(b.fase_estrategia) as fase_estrategia, max(b.tipo_mora) as tipo_mora
  , max(b.dias_mora) as mora_negocio, max(b.max_dias_mora_dni) as max_mora_dni
  , max(b.monto_capital_pendiente) as monto_asignado
  , max(b.fecha_de_vencimiento_cuota) as venc_negocio
  from primer p join base b on b.id_loan = p.id_loan and b.fb = p.fecha_ancla
  group by 1, 2
)
, casos as (
  select x.*, d.m31, d.m01, d.m02, d.venc_vigente_01, d.fecha_pago_01
  from anc x
  left join loan_chain lc on lc.id_ihfintech_loan = x.id_loan
  join ancla_final af on af.id_loan = x.id_loan and af.status in ('ACTIVE','COMPLETED')
  join dac d on d.id_loan = x.id_loan
  where x.fase_estrategia = 'TEMPRANA' and x.tipo_mora = 'antiguo'
    and coalesce(lc.last_in_chain, 1) = 1
    and d.m01 = 0 and coalesce(d.m02, 0) = 0
)
-- la cuota que el negocio considera vencida
, cuota_neg as (
  select q.id_ihfintech_loan as id_loan
  , max(q.installmentstate) as estado
  , max(cast(q.installmentlastpaiddate as timestamp)) as pagada
  , count(*) as filas
  from dts_cobranza_creditos_cuotas q
  join casos c on c.id_loan = q.id_ihfintech_loan and q.fechavencimiento = c.venc_negocio
  group by 1
)
, dl as (
  select m._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , max(case when m.fechaproceso = '20260831' then coalesce(m.dayslate, 0) end) as dl31
  , max(case when m.fechaproceso = '20260901' then coalesce(m.dayslate, 0) end) as dl01
  from dts_mambu_loans_hist m
  join casos c on c.id_loan = m._datos_adicionales_loan_accounts_id_ihfintech
  where m.fechaproceso in ('20260831', '20260901')
  group by 1
)
select
  c.id_loan
, c.fecha_ancla
, c.mora_negocio
, c.max_mora_dni
, c.venc_negocio
, round(c.monto_asignado, 2) as monto_asignado
, c.m31, c.m01, c.m02
, c.venc_vigente_01
, c.fecha_pago_01
, q.estado  as estado_cuota_negocio
, q.pagada  as pagada_cuota_negocio
, q.filas   as filas_cuota_negocio
, dl.dl31, dl.dl01
from casos c
left join cuota_neg q on q.id_loan = c.id_loan
left join dl on dl.id_loan = c.id_loan
order by c.monto_asignado desc
;

-- =====================================================================
-- TAREA 18a -- CURVA UNIFICADA DE "NUEVOS" SEGMENTADA POR DIA DE LA
-- SEMANA DEL VENCIMIENTO (habil vs. fin de semana).
--
-- Identica a tarea17_fase4_curva_nuevos.sql (Q-B, la curva de produccion)
-- salvo por UNA cosa: agrega la dimension `tipo_venc`.
--
--   tipo_venc = 'finde' si day_of_week(fechavencimiento) in (6,7)
--                        (6=sabado, 7=domingo en Presto)
--             = 'semana' en otro caso
--
-- fechavencimiento = fecha_entrada - 1 dia (el calendario unificado
-- indexa por dia de ENTRADA = vencimiento + 1; ver
-- tarea17_fase4_calendario.sql). Misma definicion de tipo_venc que
-- tarea17_fase3_curva_fantasma.sql lineas 178/264, para que los numeros
-- sean comparables con lo medido en Fase 3.
--
-- POR QUE: Fase 2 midio que la FORMA de la curva difiere ~2x en el dia 1
-- desde la entrada (finde 30.96% vs. semana 14.84%) y Fase 3 midio que
-- la resolucion mismo-dia tambien difiere (semana 9.08%-9.36% vs. finde
-- 5.67%-6.31%). Con el motor unificado el dia 0 de esta curva ES esa
-- poblacion, asi que el segmentador aplica directo.
--
-- Ventana de calibracion: 20250301-20260531, LA MISMA que Q-B.
-- Se emiten TAMBIEN las columnas de denominador (saldo_entrada_total,
-- entradas) para poder recolapsar la curva exactamente en Python.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_raw as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20250225' and '20260705'
)
, mambu_dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from mambu_raw
)
, mambu_fotos as (
  select d.id_loan, d.fechaproceso, d.saldo, b.amountfinanced
  from mambu_dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, mambu_lag as (
  select id_loan, fechaproceso, saldo, amountfinanced,
    lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  from mambu_fotos
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2025-02-25') and date('2026-05-31')
)
, dac as (
  select d.id_loan, d.fechaproceso, d.mora
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, dac_lag as (
  select id_loan, fechaproceso, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant,
    row_number() over (partition by id_loan order by fechaproceso) as nro_foto
  from dac
)
, entradas as (
  select id_loan, fechaproceso as fecha_entrada,
    date_parse(fechaproceso, '%Y%m%d') as fecha_entrada_d
  from dac_lag
  where nro_foto > 1 and mora_ant = 0 and mora = 1
    and fechaproceso between '20250301' and '20260531'
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada, e.fecha_entrada_d
  , case when day_of_week(date_add('day', -1, e.fecha_entrada_d)) in (6,7)
         then 'finde' else 'semana' end as tipo_venc
  , coalesce(ml.saldo_ant, ml.saldo) as saldo_entrada
  , case when coalesce(ml.saldo_ant, ml.saldo) >= 0.9*ml.amountfinanced then 'a. avance <10%'
         when coalesce(ml.saldo_ant, ml.saldo) >= 0.6*ml.amountfinanced then 'b. avance 10-40%'
         when coalesce(ml.saldo_ant, ml.saldo) >= 0.3*ml.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from entradas e
  join mambu_lag ml on ml.id_loan = e.id_loan and ml.fechaproceso = e.fecha_entrada
  where coalesce(ml.saldo_ant, ml.saldo) > 0
)
, pagos as (
  select e.id_loan, e.avance_band, e.tipo_venc, e.saldo_entrada,
    date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_saldo e
  join mambu_lag f on f.id_loan = e.id_loan
    and f.fechaproceso >= e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, primer_pago as (
  select id_loan, avance_band, tipo_venc, saldo_entrada, min(dia_desde_entrada) as dia_primer_pago
  from pagos where pago_flag = 1
  group by 1,2,3,4
)
, base_total as (
  select avance_band, tipo_venc, sum(saldo_entrada) as saldo_entrada_total, count(*) as entradas
  from entradas_saldo group by 1,2
)
, activado_por_dia as (
  select avance_band, tipo_venc, dia_primer_pago as dia, sum(saldo_entrada) as saldo_activado_dia
  from primer_pago group by 1,2,3
)
select
  a.avance_band, a.tipo_venc, a.dia
, round(sum(a.saldo_activado_dia) over (partition by a.avance_band, a.tipo_venc order by a.dia) / b.saldo_entrada_total * 100, 3) as pct_capital_asegurado_acum
, b.saldo_entrada_total, b.entradas
from activado_por_dia a
join base_total b on b.avance_band = a.avance_band and b.tipo_venc = a.tipo_venc
order by 1, 2, 3
;

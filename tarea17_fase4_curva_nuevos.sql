-- =====================================================================
-- TAREA 17, FASE 4 -- Q-B: CURVA UNIFICADA DE "NUEVOS"
-- Reemplaza curva_asegurado_nuevos_seg.csv (enfoque_capital_asegurado.sql
-- Q2, calibrada con dayslate) + la activacion instantanea de la capa
-- fantasma, por UNA curva sobre UNA definicion de entrada.
--
-- Cambios respecto de Q2 (los 3 son inherentes al swap de universo, NO
-- refinamientos opcionales -- la segmentacion se mantiene identica:
-- 4 buckets de avance_band, a decision del usuario):
--   1. Entrada = dias_atraso_cuota 0->1, no dayslate 0->1.
--   2. La curva arranca en el DIA 0 (el dia de entrada mismo). Con
--      dayslate el dia 0 era vacio por construccion (si pago el mismo
--      dia, dayslate nunca lo vio en mora) -- por eso hacia falta la
--      capa fantasma aparte. Con dias_atraso_cuota esa poblacion ES el
--      dia 0 de esta curva.
--   3. Saldo de referencia = saldo del dia ANTERIOR a la entrada
--      (saldo_ant), no el saldo del dia de entrada -- fix de Fase 3
--      (BUGS.md bug 16): para la poblacion que paga el mismo dia, la
--      foto del dia de entrada ya refleja el pago y subestima el
--      capital realmente en riesgo. Para la poblacion regular (que no
--      pago) saldo_ant == saldo, asi que es seguro aplicarlo a todos.
--   4. YA NO se excluye el dia 1 del mes (bug 12): esas entradas vienen
--      de una cuota vencida el ultimo dia del mes anterior y ahora
--      entran por el calendario frontier-adjusted como "nuevos", no
--      como parche sumado al stock.
--
-- Ventana de calibracion: 20250301-20260531, LA MISMA que Q2 de
-- produccion (comparabilidad manzana con manzana; mismo leak de mayo/
-- junio que tarea 10 midio en ~0.2pp).
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
  -- bug 11: misma regla validada (saldo<>0 antes que lastmodifieddate)
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
  select e.id_loan, e.avance_band, e.saldo_entrada,
    date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_saldo e
  join mambu_lag f on f.id_loan = e.id_loan
    and f.fechaproceso >= e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, primer_pago as (
  select id_loan, avance_band, saldo_entrada, min(dia_desde_entrada) as dia_primer_pago
  from pagos where pago_flag = 1
  group by 1,2,3
)
, base_total as (
  select avance_band, sum(saldo_entrada) as saldo_entrada_total, count(*) as entradas
  from entradas_saldo group by 1
)
, activado_por_dia as (
  select avance_band, dia_primer_pago as dia, sum(saldo_entrada) as saldo_activado_dia
  from primer_pago group by 1,2
)
select
  a.avance_band, a.dia
, round(sum(a.saldo_activado_dia) over (partition by a.avance_band order by a.dia) / b.saldo_entrada_total * 100, 3) as pct_capital_asegurado_acum
, b.saldo_entrada_total, b.entradas
from activado_por_dia a
join base_total b on b.avance_band = a.avance_band
order by 1, 2
;

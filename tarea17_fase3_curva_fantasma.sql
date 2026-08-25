-- =====================================================================
-- TAREA 17, FASE 3 -- Curva real para la capa fantasma (reemplaza la
-- tasa plana P_FANTASMA=8.5524%, activacion instantanea al dia
-- siguiente, tarea 7/bug 14).
--
-- Redefinicion de "fantasma": antes = cuotas pagadas EXACTAMENTE 1 dia
-- tarde (dias_vencimiento_a_pago=1, dts_cobranza_creditos_cuotas), no
-- ya en entradas_reales (dayslate). Ahora = cualquier entrada detectada
-- por dias_atraso_cuota (dts_cobranza_creditos_calendario_diario, mora
-- 0->1) que dayslate NO ve para ese periodo -- mecanismo mas amplio
-- (incluye el hueco de fin de semana de bug 16, no solo pagos 1-dia-
-- tarde). Misma logica de mutua exclusion con entradas_reales que la
-- version anterior (Principio de modelado, CLAUDE.md: tasa y curva
-- sobre la MISMA definicion).
--
-- Segmentadores nuevos (a pedido del usuario, ver BUGS.md bug 16):
--   1. avance_band simplificado a 3 buckets (<10% / 10-40% / 40%+) --
--      40-70% y 70%+ no se separaban bien.
--   2. dia de la semana del VENCIMIENTO (habil vs fin de semana) -- la
--      forma de la curva difiere ~2x en el dia 1 desde la entrada.
--
-- Ventana de calibracion: el usuario pidio 2 versiones para comparar
-- (12 y 6 meses, ambas fuera de muestra de los 4 meses de backtest
-- abr-jul 2026) -- NO se uso la historia completa 2023-10-17+ del plan
-- original: el portafolio en 2023-2024 es ~1000x mas chico que el
-- actual (8 creditos en oct-2023 vs 154,528 en mar-2026, ver BUGS.md),
-- mezclarlo violaria el mismo principio que ya aplica CLAUDE.md/
-- FUENTES_DATOS.md a las demas curvas del proyecto (calibrar con meses
-- recientes, vigilar cambio de mezcla).
--   - 12 meses: periodo_pago 202504-202603 (fechavencimiento 2025-03-31
--     a 2026-03-30).
--   - 6 meses: periodo_pago 202510-202603 (subconjunto de la misma
--     corrida -- los eventos de entrada no cambian, solo el filtro).
--
-- Tasa de referencia (verificada antes de esta query, diagnostico
-- separado): 8.617% (12m) / 8.923% (6m) -- muy cercana al 8.5524%
-- actual pese a la redefinicion mas amplia. El valor de esta Fase 3 no
-- es "una tasa distinta", es una FORMA distinta (activacion no
-- instantanea, con sesgo por dia de semana) -- ver resultado abajo.
-- =====================================================================

with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_raw as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.dayslate
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20250201' and '20260430'
)
, mambu_dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from mambu_raw
)
, mambu_fotos_all as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  , b.amountfinanced
  from mambu_dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
)
, mambu_fotos as (
  select * from mambu_fotos_all where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
    and amountfinanced > 0
)
, mambu_lag as (
  select id_loan, fechaproceso, saldo, mora, amountfinanced,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant,
    lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  from mambu_fotos
)
, entradas_reales as (
  select distinct substr(fechaproceso,1,6) as periodo, id_loan
  from mambu_lag
  where mora_ant = 0 and mora = 1
)
, cierre_mes as (
  select substr(fechaproceso,1,6) as periodo, id_loan, mora,
    row_number() over (partition by id_loan, substr(fechaproceso,1,6) order by fechaproceso desc) as rn
  from mambu_fotos
)
, stock_ids as (
  select
    date_format(date_add('month',1,date_parse(periodo,'%Y%m')), '%Y%m') as periodo_target
  , id_loan
  from cierre_mes
  where rn = 1 and mora between 1 and 30
)
, calendario as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , date_format(date_add('day',1,c.fechavencimiento), '%Y%m') as periodo_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2025-03-31')
    and c.fechavencimiento <= date('2026-03-30')
)
, calendario_mes as (
  select periodo_pago as periodo, id_loan, min(fechavencimiento) as fechavencimiento
  from calendario cal
  where periodo_pago between '202504' and '202603'
    and not exists (
      select 1 from stock_ids s
      where s.periodo_target = cal.periodo_pago and s.id_loan = cal.id_loan
    )
  group by 1, 2
)
, cal_raw as (
  select
    c.id_ihfintech_loan as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d') as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0) as mora_dac
  , c.fechaporvencer
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2025-03-25') and date('2026-04-15')
)
, dac_fotos_all as (
  select
    d.id_loan, d.fechaproceso, d.mora_dac, d.fechaporvencer
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from cal_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
)
, dac_fotos as (
  select * from dac_fotos_all where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
)
, dac_lag as (
  select id_loan, fechaproceso, mora_dac, fechaporvencer,
    lag(mora_dac) over (partition by id_loan order by fechaproceso) as mora_dac_ant
  from dac_fotos
)
, dac_entradas as (
  select
    id_loan, fechaproceso as fecha_entrada, fechaporvencer as fecha_vencimiento
  , substr(fechaproceso,1,6) as periodo
  from dac_lag
  where mora_dac_ant = 0 and mora_dac = 1
)
, entradas_fantasma as (
  select
    cm.periodo, cm.id_loan, de.fecha_entrada, de.fecha_vencimiento
  from calendario_mes cm
  join dac_entradas de on de.id_loan = cm.id_loan and de.periodo = cm.periodo
  where not exists (
    select 1 from entradas_reales er
    where er.periodo = cm.periodo and er.id_loan = cm.id_loan
  )
)
-- saldo y avance a la fecha de entrada: A DIFERENCIA de la curva de
-- "nuevos" (donde el dia de entrada nunca coincide con el dia de pago,
-- por definicion de dayslate), en la poblacion fantasma el mecanismo
-- ES que el sistema ya ve el pago aplicado el mismo dia que detecta la
-- entrada (mismo hallazgo que el caso verificado en bug 16: entrada
-- 2026-07-08, fecha_pago 2026-07-08) -- por eso el saldo de REFERENCIA
-- (cuanto capital estaba en riesgo) es el saldo del dia ANTERIOR
-- (saldo_ant en fecha_entrada, via mambu_lag), y el tracking de pago
-- debe incluir el dia 0 (fecha_entrada mismo), no solo dias posteriores
-- -- de lo contrario se pierde la activacion real y lo que se mide en
-- su lugar es la SIGUIENTE cuota regular del credito (ver nota abajo).
, saldo_entrada as (
  select ef.periodo, ef.id_loan, ef.fecha_entrada, ef.fecha_vencimiento
  , coalesce(ml.saldo_ant, ml.saldo) as saldo_entrada
  , mf.amountfinanced
  , case when day_of_week(date(ef.fecha_vencimiento)) in (6,7) then 'finde' else 'semana' end as tipo_venc
  , case when coalesce(ml.saldo_ant, ml.saldo) >= 0.9*mf.amountfinanced then 'a. avance <10%'
         when coalesce(ml.saldo_ant, ml.saldo) >= 0.6*mf.amountfinanced then 'b. avance 10-40%'
         else 'c. avance 40%+' end as avance_band
  from entradas_fantasma ef
  join mambu_lag ml on ml.id_loan = ef.id_loan and ml.fechaproceso = ef.fecha_entrada
  join mambu_fotos mf on mf.id_loan = ef.id_loan and mf.fechaproceso = ef.fecha_entrada
)
, pagos as (
  select e.id_loan, e.periodo, e.avance_band, e.tipo_venc, e.saldo_entrada,
    date_diff('day', date_parse(e.fecha_entrada,'%Y%m%d'), date_parse(f.fechaproceso,'%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from saldo_entrada e
  join mambu_lag f on f.id_loan = e.id_loan
    and f.fechaproceso >= e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, date_parse(e.fecha_entrada,'%Y%m%d')), '%Y%m%d')
)
, primer_pago as (
  select id_loan, periodo, avance_band, tipo_venc, saldo_entrada, min(dia_desde_entrada) as dia_primer_pago
  from pagos where pago_flag = 1
  group by 1,2,3,4,5
)
-- ======================= SALIDA 1: CURVA 12 MESES (periodo 202504-202603), por avance_band x tipo_venc =======================
, base_total_12m as (
  select avance_band, tipo_venc, sum(saldo_entrada) as saldo_entrada_total, count(*) as entradas
  from saldo_entrada
  where periodo between '202504' and '202603'
  group by 1,2
)
, activado_por_dia_12m as (
  select avance_band, tipo_venc, dia_primer_pago as dia, sum(saldo_entrada) as saldo_activado_dia
  from primer_pago
  where periodo between '202504' and '202603'
  group by 1,2,3
)
select
  '12m' as ventana, a.avance_band, a.tipo_venc, a.dia
, round(sum(a.saldo_activado_dia) over (partition by a.avance_band, a.tipo_venc order by a.dia) / b.saldo_entrada_total * 100, 3) as pct_capital_asegurado_acum
, b.saldo_entrada_total, b.entradas
from activado_por_dia_12m a
join base_total_12m b on b.avance_band = a.avance_band and b.tipo_venc = a.tipo_venc
order by 2, 3, 4
;

-- RESULTADO (2026-08-25): activacion PONDERADA en el dia 0 = 99.60% (sobre
-- S/41.96M de saldo_entrada), con incremento post-dia0 de solo 0.07 a
-- 0.63pp por segmento -- CONFIRMA que la poblacion fantasma (aun con la
-- definicion ampliada via dias_atraso_cuota) sigue activandose casi
-- instantaneamente, igual que asumia P_FANTASMA. NO hace falta una curva
-- multi-dia -- la arquitectura de tasa plana + activacion instantanea de
-- produccion ya era correcta. Ver bug 16 en BUGS.md para el detalle y la
-- interpretacion completa.

-- ======================= SALIDA 2: dia-0 y tasa, VENTANA 6 MESES (periodo 202510-202603), por avance_band x tipo_venc =======================
-- Reemplaza SALIDA 1 (curva completa) por un chequeo mas barato (solo
-- dia 0, no el rango de 31 dias) -- una vez confirmado en la ventana de
-- 12 meses que el incremento post-dia0 es marginal, no hace falta pagar
-- el join completo de nuevo.
, base_total_6m as (
  select avance_band, tipo_venc, sum(saldo_entrada) as saldo_entrada_total, count(*) as entradas
  from saldo_entrada
  where periodo between '202510' and '202603'
  group by 1,2
)
, dia0_6m as (
  select avance_band, tipo_venc, sum(case when pago_flag=1 then saldo_entrada else 0 end) as saldo_dia0
  from pagos
  where periodo between '202510' and '202603' and dia_desde_entrada = 0
  group by 1,2
)
select b.avance_band, b.tipo_venc, b.entradas, b.saldo_entrada_total,
  round(100.0*coalesce(d.saldo_dia0,0)/b.saldo_entrada_total,3) as pct_dia0
from base_total_6m b
left join dia0_6m d on d.avance_band=b.avance_band and d.tipo_venc=b.tipo_venc
order by 1,2
;
-- RESULTADO (2026-08-25): dia-0 entre 99.49% y 100.0% en los 6 segmentos
-- -- misma conclusion que la ventana de 12 meses, activacion casi
-- instantanea sin importar la ventana de calibracion.

-- ======================= SALIDA 3: tasa de entrada (elegibles vs. entradas fantasma) por dia de semana del vencimiento =======================
-- El hallazgo real de utilidad de Fase 3 no es la FORMA de la curva
-- (confirmada instantanea, salida 1/2) sino si la TASA de entrada varia
-- por dia de semana del vencimiento -- se corre para las 2 ventanas.
select
  '12m' as ventana
, case when day_of_week(date(cm.fechavencimiento)) in (6,7) then 'finde' else 'semana' end as tipo_venc
, count(*) as elegibles
, count(ef.id_loan) as entradas_fantasma
, round(100.0*count(ef.id_loan)/count(*),3) as pct_entrada_fantasma
from calendario_mes cm
left join entradas_fantasma ef on ef.periodo = cm.periodo and ef.id_loan = cm.id_loan
where cm.periodo between '202504' and '202603'
group by 2
;
-- RESULTADO 12m (2026-08-25): semana 9.076% (301,559 elegibles / 27,369
-- entradas) vs. finde 5.671% (47,046 / 2,668) -- el vencimiento en fin de
-- semana tiene una tasa de entrada fantasma MENOR, no mayor. Repetir con
-- cm.periodo between '202510' and '202603' para la ventana de 6 meses:
-- semana 9.358% (174,437/16,324), finde 6.310% (29,033/1,832) -- misma
-- direccion y magnitud parecida, estable entre ventanas.
-- Nota de interpretacion: esto NO contradice el hallazgo de Fase 1 (mas
-- creditos "se escapan" a mora el sabado sin llamada preventiva) -- ese
-- hallazgo es sobre la tasa TOTAL de entrada a mora. Esta tasa mide algo
-- mas especifico: de los que entran, cuantos quedan INVISIBLES para
-- dayslate (que corre 7 dias a la semana, a diferencia de la tabla de
-- asignaciones) -- un credito que entra en mora el sabado y NO paga
-- hasta el lunes SI queda visible para dayslate el domingo (dayslate no
-- se salta fines de semana), por lo que cuenta como "entradas_reales",
-- no "fantasma". Solo escapa a dayslate el que paga MUY rapido (mismo
-- dia/antes de la foto de esa noche) -- eso parece ser relativamente
-- menos comun en fin de semana que entre semana, opuesto al mecanismo de
-- "no aparece en asignaciones" que si es mas grande en fin de semana.

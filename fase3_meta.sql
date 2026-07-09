-- =====================================================================
-- FASE 3 - META DE RECUPERO DIARIA (stock + nuevos proyectados)
-- Ejecutada 2026-07-08 en Athena (db dev_datalake_master).
--
-- IMPORTANTE - dos filtros distintos segun si se mira pasado o futuro:
--  * Historico/calibracion (fase0/1/2): status IN ('ACTIVE','COMPLETED')
--    -- queremos el comportamiento completo, incluye los que ya
--    terminaron de pagar bien.
--  * Calendario prospectivo (aqui, 3A): status = 'ACTIVE' solamente
--    -- un credito COMPLETED ya no tiene obligaciones futuras; si
--    apareciera con una cuota PENDING seria dato obsoleto/ruido.
--  * flg_last_loan_in_chain = 1 aplica en AMBOS casos (excluye
--    creditos reemplazados por reenganche, no tiene relacion con
--    pasado/futuro).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3A. CALENDARIO DE VENCIMIENTOS FUTUROS CON SALDO CAPITAL EN RIESGO
-- Insumo para proyectar el flujo de "nuevos" del mes objetivo.
-- Hallazgo: el ultimo dia del mes concentra un salto grande de
-- vencimientos (fin de mes) -- consistente con la aceleracion de
-- fin de mes vista en las curvas de fase1/fase2.
-- ---------------------------------------------------------------------
select
  c.fechavencimiento
, count(distinct c.id_ihfintech_loan) as creditos_vencen
, round(sum(b.balances_principalbalance), 0) as saldo_capital_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b
  on b.id_ihfintech_loan = c.id_ihfintech_loan
where c.status = 'ACTIVE'
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento > date(current_date)
  and c.installmentstate = 'PENDING'
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- 3B. MISMO CALENDARIO, SEGMENTADO POR AVANCE DE AMORTIZACION
-- (saldo capital vigente / monto financiado). Necesario porque la
-- severidad de pago varia mucho por avance (ver fase1_stock.sql /
-- fase2_nuevos.sql): avance<10% ~8-14% vs avance 70%+ ~38-76%.
-- ---------------------------------------------------------------------
select
  c.fechavencimiento
, case when b.balances_principalbalance >= 0.9*b.amountfinanced then 'a. avance <10%'
       when b.balances_principalbalance >= 0.6*b.amountfinanced then 'b. avance 10-40%'
       when b.balances_principalbalance >= 0.3*b.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, count(distinct c.id_ihfintech_loan) as creditos_vencen
, round(sum(b.balances_principalbalance), 0) as saldo_capital_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b
  on b.id_ihfintech_loan = c.id_ihfintech_loan
where c.status = 'ACTIVE'
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento > date(current_date)
  and c.installmentstate = 'PENDING'
  and b.amountfinanced > 0
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- 3C. STOCK VIGENTE HOY, SEGMENTADO POR TRAMO x AVANCE
-- Punto de partida de la proyeccion (parte "stock" de la meta).
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas
group by 1
)
, ultima_foto as (
select
  a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, a.balances_principalbalance as saldo
, coalesce(a.dayslate,0) as mora
, b.amountfinanced
, row_number() over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso desc) as rn
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and coalesce(lc.last_in_chain,1) = 1
)
select
  case when mora between 1 and 8 then 'a. 1-8'
       when mora between 9 and 15 then 'b. 9-15'
       else 'c. 16-30' end as tramo
, case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
       when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
       when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, count(*) as creditos
, round(sum(saldo),0) as saldo_total
from ultima_foto
where rn = 1 and mora between 1 and 30 and saldo > 0
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- 3D/3E. CURVAS DIARIAS SEGMENTADAS POR AVANCE (stock y nuevos)
-- Analogas a 1A y 2C de fase1_stock.sql/fase2_nuevos.sql, pero con
-- la dimension avance_band agregada. Ver esos archivos para las CTEs
-- base (loan_chain, fotos, stock/entradas, rebajes) -- aqui solo se
-- documenta el bloque final que se le agrega:
--
-- 3D (stock, agregar a fase1_stock.sql CTEs base):
--   stock_avance: banda de avance por (periodo_meta, id_loan, tramo)
--   rebaje_dia agrupado por (tramo, avance_band, dia)
--   -> pct_recupero_acum por (tramo, avance_band, dia)
--
-- 3E (nuevos, agregar a fase2_nuevos.sql CTEs base):
--   entradas_avance: banda de avance al momento de entrar en mora
--   rebaje_dia agrupado por (avance_band, dia_desde_entrada)
--   -> pct_recupero_acum por (avance_band, dia_desde_entrada)
--
-- (Query completa ejecutada y validada 2026-07-08; el patron exacto
-- esta en el historial de la sesion -- replicar el patron de 1A/2C
-- añadiendo avance_band al PARTITION BY / GROUP BY donde corresponda.)
-- ---------------------------------------------------------------------

-- =====================================================================
-- 3F. COMBINACION: TRAYECTORIA DIARIA DE LA META (stock + nuevos)
-- =====================================================================
-- La combinacion final (cruzar 3A-3E dia a dia, aplicando el
-- truncamiento de curva por cohorte de entrada) se hace fuera de SQL,
-- en Python, sobre los resultados de 3B/3C/3D/3E ya agregados (son
-- pocas filas: calendario ~30 dias x 4 bandas, stock 3x4, curvas
-- 3x4x31 y 4x31). Ver armar_trayectoria_seg.py (scratchpad de la
-- sesion) para el algoritmo exacto. Formula:
--
--   Meta_cum(d) = Σ(tramo,avance) saldo_stock(tramo,avance) x curva_stock(tramo,avance,d)
--               + Σ(D<=d) Σ(avance) saldo_riesgo(D,avance) x (1-C_ops(0)) x curva_nuevos(avance, d-D)
--
-- P(no paga a tiempo): OJO -- la version original de esta corrida usaba
-- 1-C_ops(0)=27.4% (de la curva de # operaciones a nivel CUOTA,
-- fase2_nuevos.sql 2A). El backtest de junio (fase3_backtest.sql,
-- bloque 3H) encontro que esa cifra NO es la tasa real de entrada a
-- mora a nivel CREDITO -- usarla produjo +79% de error. La tasa
-- correcta, medida directamente (dayslate 0->1) y fuera de muestra,
-- es 13.38%. Ver armar_trayectoria_seg.py y plan_analisis.md.
--
-- CAVEATS de la corrida demo (2026-07-08, ventana rodante desde hoy):
--  1) Usa el stock de HOY como si fuera "dia 1" -- en realidad hoy es
--     dia 8 del mes en curso, asi que el stock ya refleja rebajes de
--     esta semana. Para la meta oficial de un mes calendario, anclar
--     al CIERRE del mes anterior (igual que stock/rebajes en
--     fase1_stock.sql), no al dia de hoy.
--  2) El calendario usado solo trae vencimientos FUTUROS
--     (fechavencimiento > hoy, installmentstate='PENDING') -- sirve
--     para proyectar hacia adelante pero no para reconstruir un mes ya
--     iniciado (los vencimientos ya resueltos de ese mes no
--     aparecerian). Para backtest de meses cerrados, traer las cuotas
--     por fechavencimiento en el rango del mes SIN filtrar por
--     installmentstate (el estado actual no importa, ya sabemos el
--     desenlace via las fotos de dts_mambu_loans_hist).
-- =====================================================================

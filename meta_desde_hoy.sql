-- =====================================================================
-- META DESDE HOY EN ADELANTE ("reinicio del reloj"): en vez de anclar
-- al cierre del mes anterior, se toma la foto de HOY como una nueva
-- linea base, y se proyecta el resto del mes desde ahi.
--
-- Contraste con fase3_backtest.sql / meta_julio.py (que ancla a
-- cierre de junio y usa cohortes por fecha de entrada real): este
-- enfoque es mas simple de calcular pero trata a los creditos del
-- stock original de julio (que ya llevaban 9 dias en mora) como si
-- fueran "dia 1" frescos hoy. Empiricamente ambos enfoques convergen
-- (+1.0% de diferencia el 2026-07-09) pero no son identicos en teoria.
--
-- NOTA sobre fuentes: dts_mambu_loans_hist SI tiene la foto del dia
-- de la consulta (verificado 2026-07-09). vw_mambu_loans_hist NO
-- sirve como sustituto -- solo tiene ~33 fechas puntuales en 2+ anos,
-- no una foto diaria completa.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. STOCK RE-BASELINEADO A HOY: mora 1-30 con la foto del dia de
-- la consulta, segmentado por tramo x avance.
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos_hoy as (
select a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, a.balances_principalbalance as saldo, coalesce(a.dayslate,0) as mora, b.amountfinanced
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso = '20260709'   -- <-- ajustar a la fecha de corte deseada
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
from fotos_hoy
where mora between 1 and 30 and saldo > 0
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- Q2. CALENDARIO DE VENCIMIENTOS DESDE MAÑANA EN ADELANTE, excluyendo
-- el stock de hoy (para no contar dos veces el mismo saldo).
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos_hoy as (
select a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, coalesce(a.dayslate,0) as mora, a.balances_principalbalance as saldo
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso = '20260709'
)
, stock_hoy_ids as (
select id_loan from fotos_hoy where mora between 1 and 30 and saldo > 0
)
select
  c.fechavencimiento
, case when b.balances_principalbalance >= 0.9*b.amountfinanced then 'a. avance <10%'
       when b.balances_principalbalance >= 0.6*b.amountfinanced then 'b. avance 10-40%'
       when b.balances_principalbalance >= 0.3*b.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, count(distinct c.id_ihfintech_loan) as creditos
, round(sum(b.balances_principalbalance),0) as saldo_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
where c.status = 'ACTIVE'
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento >= date('2026-07-10') and c.fechavencimiento <= date('2026-07-31')
  and c.installmentstate = 'PENDING'
  and b.amountfinanced > 0
  and c.id_ihfintech_loan not in (select id_loan from stock_hoy_ids)
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- La combinacion (aplicar curva_stock/curva_nuevos y sumar) se hace
-- en meta_desde_hoy.py, igual que armar_trayectoria_seg.py /
-- meta_julio.py. Formula:
--
--  Stock:  aporte(tramo,avance) = saldo_hoy(tramo,avance) x curva_stock(tramo,avance, dias_restantes)
--  Nuevos: aporte(D,avance) = saldo_en_riesgo(D,avance) x 13.38% x curva_nuevos(avance, dias_para_madurar_hasta_cierre)
--          donde dias_para_madurar_hasta_cierre = (fin_de_mes - fecha_vencimiento).days
-- ---------------------------------------------------------------------

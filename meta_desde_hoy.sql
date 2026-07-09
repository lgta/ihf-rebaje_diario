-- =====================================================================
-- META DESDE HOY EN ADELANTE ("reinicio del reloj"): en vez de anclar
-- al cierre del mes anterior, se toma la foto de HOY como una nueva
-- linea base, y se proyecta el resto del mes desde ahi.
--
-- Contraste con fase3_backtest.sql / meta_julio.py (que ancla a
-- cierre de junio y usa cohortes por fecha de entrada real): este
-- enfoque es mas simple de calcular pero trata a los creditos del
-- stock original de julio (que ya llevaban 9 dias en mora) como si
-- fueran "dia 1" frescos hoy.
--
-- BUG CORREGIDO 2026-07-09 (ver plan_analisis.md "Meta en vivo de
-- julio"): el filtro "where mora between 1 and 30" evaluado con la
-- mora de HOY excluia silenciosamente a los creditos que SI eran
-- parte del stock original de julio (cierre de junio, mora 1-30) pero
-- ya habian cruzado 30 dias de mora para hoy -- violando la regla ya
-- confirmada de que un credito asignado sigue contando aunque cruce
-- 30 dias. Diagnostico: de 1,756 creditos del stock de 1-jul, 244
-- (S/501,307) estaban en esta situacion -- todos originalmente en
-- tramo 16-30 (esperable: solo creditos ya cerca de 30 pueden cruzar
-- en 9 dias). NO se debe simplemente quitar el limite superior del
-- filtro -- eso arrastraria S/9.57M de cartera con mora 90+ dias
-- (76% del universo mora>30 de hoy) que nunca fue parte de la
-- asignacion de julio. La correccion es quirurgica: bloque Q0 abajo
-- identifica solo a los "aged-out survivors" del stock original (via
-- JOIN contra el cierre de junio) y los trata con la logica del
-- enfoque acumulado (su saldo de referencia es el de asignacion, no
-- el de hoy), sumandolos aparte del resto del stock re-baselineado.
--
-- NOTA sobre fuentes: dts_mambu_loans_hist SI tiene la foto del dia
-- de la consulta (verificado 2026-07-09). vw_mambu_loans_hist NO
-- sirve como sustituto -- solo tiene ~33 fechas puntuales en 2+ anos,
-- no una foto diaria completa.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q0. CREDITOS "AGED-OUT": eran parte del stock de julio (mora 1-30 al
-- cierre de junio) pero YA CRUZARON 30 dias de mora para hoy. Se
-- clasifican por su tramo/avance ORIGINALES (30-jun), no los de hoy,
-- y se usa su saldo de esa fecha -- son la cola del enfoque acumulado,
-- no encajan en la logica "hoy = dia 1".
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos_asignacion as (
-- <-- ajustar '20260630' al cierre del mes anterior a la fecha de corte
select a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, coalesce(a.dayslate,0) as mora, a.balances_principalbalance as saldo, b.amountfinanced
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso = '20260630'
)
, stock_asignacion as (
select id_loan, mora, saldo, amountfinanced from fotos_asignacion
where mora between 1 and 30 and saldo > 0
)
, fotos_hoy as (
-- <-- ajustar '20260709' a la fecha de corte deseada
select a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, coalesce(a.dayslate,0) as mora_hoy
from dts_mambu_loans_hist a
where a.fechaproceso = '20260709'
)
select
  case when s.mora between 1 and 8 then 'a. 1-8'
       when s.mora between 9 and 15 then 'b. 9-15'
       else 'c. 16-30' end as tramo_original
, case when s.saldo >= 0.9*s.amountfinanced then 'a. avance <10%'
       when s.saldo >= 0.6*s.amountfinanced then 'b. avance 10-40%'
       when s.saldo >= 0.3*s.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, count(*) as creditos
, round(sum(s.saldo),0) as saldo_asignacion_total
from stock_asignacion s
join fotos_hoy f on f.id_loan = s.id_loan
where f.mora_hoy > 30
group by 1,2
order by 1,2
;
-- Aplicar curva_stock(tramo_original, avance_band, dia31) menos
-- curva_stock(..., dia9) al saldo_asignacion_total -- esa es la
-- logica acumulada, no la de "hoy=dia 1". Ver meta_desde_hoy.py.

-- ---------------------------------------------------------------------
-- Q1. STOCK RE-BASELINEADO A HOY: mora 1-30 con la foto del dia de
-- la consulta, segmentado por tramo x avance. (Ya NO incluye a los
-- aged-out de Q0 -- ver Q1b para el listado a excluir del calendario.)
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
  and a.fechaproceso = '20260709'
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
-- TODO lo que ya es stock (Q1: sigue 1-30 hoy, Q0: aged-out) para no
-- contar dos veces el mismo saldo.
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos_asignacion as (
select a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, coalesce(a.dayslate,0) as mora, a.balances_principalbalance as saldo
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso = '20260630'
)
, stock_asignacion_ids as (
select id_loan from fotos_asignacion where mora between 1 and 30 and saldo > 0
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
, excluir_ids as (
select id_loan from stock_asignacion_ids   -- cubre Q0 (aged-out) + a los que siguen 1-30
union
select id_loan from stock_hoy_ids          -- cubre nuevos que entraron y siguen 1-30 (redundante con la union de arriba, por seguridad)
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
  and c.id_ihfintech_loan not in (select id_loan from excluir_ids)
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- La combinacion (aplicar curva_stock/curva_nuevos y sumar) se hace
-- en meta_desde_hoy.py, igual que armar_trayectoria_seg.py /
-- meta_julio.py. Formula:
--
--  Q1 (stock re-baseline):  aporte(tramo,avance) = saldo_hoy(tramo,avance) x curva_stock(tramo,avance, dias_restantes)
--  Q0 (aged-out survivors): aporte(tramo_original,avance) = saldo_asignacion(tramo_original,avance) x [curva_stock(...,dia31) - curva_stock(...,dia9)]
--  Q2 (nuevos):              aporte(D,avance) = saldo_en_riesgo(D,avance) x 13.38% x curva_nuevos(avance, dias_para_madurar_hasta_cierre)
--          donde dias_para_madurar_hasta_cierre = (fin_de_mes - fecha_vencimiento).days
--
--  Meta desde hoy = Q1 + Q0 + Q2
-- ---------------------------------------------------------------------

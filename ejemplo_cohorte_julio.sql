-- =====================================================================
-- EJEMPLO REPLICABLE: proyeccion de "nuevos" para una sola cohorte,
-- y version completa en un solo query. Corte: 2026-07-09.
-- Ver conversacion / guia_tecnica_recupero.md para la explicacion
-- narrativa paso a paso.
--
-- OJO -- error corregido: en la explicacion original se dijo que
-- "Nuevos_acumulado(dia 9) = S/334,208", pero ese numero es el REAL
-- (recupero efectivo de la poblacion nuevos, ver meta_julio.py /
-- jul_real_a_hoy.csv), NO la suma de cohortes proyectada. El numero
-- PROYECTADO correcto es S/282,689 (este archivo) / S/282,725
-- (meta_julio.py) -- la pequeña diferencia (0.013%) es redondeo de la
-- tasa 13.38% al hardcodearla en SQL vs. usar la fraccion exacta
-- 47966/358580 en Python.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Saldo en riesgo de UNA cohorte: 2 de julio, todas las bandas de
-- avance. Requiere excluir el stock de julio (creditos ya en mora al
-- cierre de junio) para no duplicar saldo ya contado en el motor stock.
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos_junio30 as (
select a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, coalesce(a.dayslate,0) as mora, a.balances_principalbalance as saldo
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso = '20260630'
)
, stock_julio_ids as (
select id_loan from fotos_junio30 where mora between 1 and 30 and saldo > 0
)
select
  c.fechavencimiento
, case when f.balances_principalbalance >= 0.9*b.amountfinanced then 'a. avance <10%'
       when f.balances_principalbalance >= 0.6*b.amountfinanced then 'b. avance 10-40%'
       when f.balances_principalbalance >= 0.3*b.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, count(distinct c.id_ihfintech_loan) as creditos
, round(sum(f.balances_principalbalance),0) as saldo_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
join dts_mambu_loans_hist f
  on f._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
 and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
where c.status in ('ACTIVE','COMPLETED')
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento = date('2026-07-02')
  and b.amountfinanced > 0
  and c.id_ihfintech_loan not in (select id_loan from stock_julio_ids)
group by 1,2
order by 2
;
-- Resultado avance <10%: 277 creditos, S/832,370

-- ---------------------------------------------------------------------
-- Q2. Valor puntual de la curva de "nuevos": avance <10%, dia 7 desde
-- la entrada. Reconstruye la curva completa (fase2_nuevos.sql bloque
-- 2D) y filtra al punto de interes.
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos_hist as (
select
  a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, a.balances_principalbalance as saldo, coalesce(a.dayslate, 0) as mora
, b.amountfinanced
, lag(a.balances_principalbalance) over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
, lag(coalesce(a.dayslate, 0)) over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
, row_number() over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as nro_foto
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain, 1) = 1
  and a.fechaproceso >= '20250201'
)
, entradas as (
select id_loan, fechaproceso as fecha_entrada, date_parse(fechaproceso, '%Y%m%d') as fecha_entrada_d,
  saldo as saldo_entrada,
  case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
       when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
       when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
from fotos_hist
where nro_foto > 1 and mora_ant = 0 and mora = 1
  and fechaproceso between '20250301' and '20260531'
)
, rebajes_hist as (
select e.avance_band, e.saldo_entrada,
  date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
  case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
from entradas e
join fotos_hist f on f.id_loan = e.id_loan
  and f.fechaproceso > e.fecha_entrada
  and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, rebaje_dia as (select avance_band, dia_desde_entrada, sum(rebaje) as rebaje_dia from rebajes_hist group by 1,2)
, base_total as (select avance_band, sum(saldo_entrada) as saldo_entrada_total from entradas group by 1)
, curva as (
select r.avance_band, r.dia_desde_entrada,
  sum(r.rebaje_dia) over (partition by r.avance_band order by r.dia_desde_entrada) / b.saldo_entrada_total * 100 as pct_recupero_acum
from rebaje_dia r join base_total b on b.avance_band = r.avance_band
)
select avance_band, dia_desde_entrada, round(pct_recupero_acum, 3) as pct_recupero_acum
from curva
where avance_band = 'a. avance <10%' and dia_desde_entrada = 7
;
-- Resultado: 7.799%  (aporte de esta cohorte sola: 832,370 x 13.38% x 7.799% = S/8,690 aprox)

-- ---------------------------------------------------------------------
-- Q3. TODO EN UNA QUERY: Nuevos_acumulado(dia 9) completo -- suma las
-- 36 cohortes (9 dias de julio ya vencidos x 4 bandas de avance),
-- cada una multiplicada por P(no paga a tiempo)=13.38% y el valor de
-- su curva en los dias de maduracion correspondientes al 9 de julio.
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos_hist as (
select
  a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, a.balances_principalbalance as saldo, coalesce(a.dayslate, 0) as mora
, b.amountfinanced
, lag(a.balances_principalbalance) over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
, lag(coalesce(a.dayslate, 0)) over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
, row_number() over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as nro_foto
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain, 1) = 1
  and a.fechaproceso >= '20250201'
)
, entradas as (
select id_loan, fechaproceso as fecha_entrada, date_parse(fechaproceso, '%Y%m%d') as fecha_entrada_d,
  saldo as saldo_entrada,
  case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
       when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
       when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
from fotos_hist
where nro_foto > 1 and mora_ant = 0 and mora = 1
  and fechaproceso between '20250301' and '20260531'
)
, rebajes_hist as (
select e.avance_band, e.saldo_entrada,
  date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
  case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
from entradas e
join fotos_hist f on f.id_loan = e.id_loan
  and f.fechaproceso > e.fecha_entrada
  and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, rebaje_dia as (select avance_band, dia_desde_entrada, sum(rebaje) as rebaje_dia from rebajes_hist group by 1,2)
, base_total as (select avance_band, sum(saldo_entrada) as saldo_entrada_total from entradas group by 1)
, curva_nuevos as (
select r.avance_band, r.dia_desde_entrada,
  sum(r.rebaje_dia) over (partition by r.avance_band order by r.dia_desde_entrada) / b.saldo_entrada_total * 100 as pct_recupero_acum
from rebaje_dia r join base_total b on b.avance_band = r.avance_band
)
, fotos_junio30 as (
select a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, coalesce(a.dayslate,0) as mora, a.balances_principalbalance as saldo
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso = '20260630'
)
, stock_julio_ids as (
select id_loan from fotos_junio30 where mora between 1 and 30 and saldo > 0
)
, calendario_julio as (
select
  c.fechavencimiento
, case when f.balances_principalbalance >= 0.9*b.amountfinanced then 'a. avance <10%'
       when f.balances_principalbalance >= 0.6*b.amountfinanced then 'b. avance 10-40%'
       when f.balances_principalbalance >= 0.3*b.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, sum(f.balances_principalbalance) as saldo_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
join dts_mambu_loans_hist f
  on f._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
 and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
where c.status in ('ACTIVE','COMPLETED')
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento >= date('2026-07-01') and c.fechavencimiento <= date('2026-07-09')
  and b.amountfinanced > 0
  and c.id_ihfintech_loan not in (select id_loan from stock_julio_ids)
group by 1,2
)
select
  round(sum(cal.saldo_en_riesgo * 0.1337885 * coalesce(cn.pct_recupero_acum,0) / 100), 0) as nuevos_acumulado_dia9
from calendario_julio cal
left join curva_nuevos cn
  on cn.avance_band = cal.avance_band
 and cn.dia_desde_entrada = date_diff('day', date(cal.fechavencimiento), date('2026-07-09'))
;
-- Resultado: S/282,689 (vs S/282,725 en meta_julio.py -- diferencia de
-- redondeo al hardcodear 0.1337885 en vez de la fraccion exacta)

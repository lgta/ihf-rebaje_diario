-- =====================================================================
-- FASE 3 - BACKTEST SOBRE UN MES REAL Y CERRADO (junio 2026)
-- Ejecutado 2026-07-08. Resultado: +5.4% de error al cierre (ver
-- plan_analisis.md). Reemplaza las limitaciones de la corrida "demo"
-- de fase3_meta.sql (que usaba el stock de HOY como dia 1 y un
-- calendario solo prospectivo).
--
-- HALLAZGO CRITICO: la constante P(no paga a tiempo) usada en la demo
-- (27.4%, de la curva de dias_vencimiento_a_pago a nivel CUOTA) NO
-- corresponde a la tasa real de entrada a mora a nivel CREDITO
-- (dayslate 0->1). Usar esa constante producia un error de +79%.
-- La tasa correcta, medida directamente y fuera de muestra (10 meses
-- previos a junio, sin incluir junio) es 13.38%. Ver bloque 3H.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3G-1. STOCK AL CIERRE DE MAYO 2026 (= stock de junio), por tramo x avance
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
select
  substr(a.fechaproceso, 1, 6) as periodo
, a.fechaproceso
, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, a.balances_principalbalance as saldo
, coalesce(a.dayslate, 0) as mora
, b.amountfinanced
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso >= '20260501' and a.fechaproceso <= '20260531'
)
, cierre_mayo as (
select *, row_number() over (partition by id_loan order by fechaproceso desc) as rn
from fotos
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
from cierre_mayo
where rn = 1 and mora between 1 and 30 and saldo > 0
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- 3G-2. CALENDARIO REAL DE VENCIMIENTOS DE JUNIO (saldo a la fecha de
-- vencimiento, segmentado por avance), EXCLUYENDO el stock de junio.
-- Nota: sin filtro installmentstate -- ya conocemos el desenlace.
-- ---------------------------------------------------------------------
/*
with loan_chain as (...)
, fotos_may as (... rn=1 sobre mayo, igual que 3G-1 ...)
, stock_junio_ids as (
select id_loan from fotos_may where rn=1 and mora between 1 and 30 and saldo > 0
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
  and c.fechavencimiento >= date('2026-06-01')
  and c.fechavencimiento <= date('2026-06-30')
  and b.amountfinanced > 0
  and c.id_ihfintech_loan not in (select id_loan from stock_junio_ids)
group by 1,2
order by 1,2
*/

-- ---------------------------------------------------------------------
-- 3G-3. RECUPERO REAL DIARIO DE JUNIO -- poblacion STOCK
-- (para comparar contra la proyeccion)
-- ---------------------------------------------------------------------
/*
... fotos may+junio con lag, stock_junio_ids igual que 3G-2 ...
select f.fechaproceso, sum(case when f.saldo_ant>f.saldo then f.saldo_ant-f.saldo else 0 end) as rebaje_dia
from fotos f join stock_junio_ids s on s.id_loan=f.id_loan
where f.fechaproceso between '20260601' and '20260630'
group by 1 order by 1
*/

-- ---------------------------------------------------------------------
-- 3G-4. RECUPERO REAL DIARIO DE JUNIO -- poblacion NUEVOS
-- (creditos NO en stock que entran en mora durante junio)
-- ---------------------------------------------------------------------
/*
... entradas_junio: mora_ant=0 y mora=1 en junio, excluyendo stock_junio_ids ...
select f.fechaproceso, sum(case when f.saldo_ant>f.saldo then f.saldo_ant-f.saldo else 0 end) as rebaje_dia
from fotos f
join entradas_junio e on e.id_loan=f.id_loan and f.fechaproceso >= e.fecha_entrada
where f.fechaproceso between '20260601' and '20260630'
group by 1 order by 1
*/

-- ---------------------------------------------------------------------
-- 3H. TASA DE ENTRADA A MORA "P(no paga a tiempo)" -- CALIBRACION
-- FUERA DE MUESTRA (10 meses previos a junio: ago-2025 a may-2026,
-- SIN junio). Denominador = creditos con cuota venciendo ese mes,
-- excluyendo el stock de ese mes (mismo criterio que 3G-2).
-- Resultado: 11.4%-14.6% por mes, promedio ponderado 13.38%
-- (47,966 entradas / 358,580 elegibles). Reemplaza el 27.4% original
-- (que venia de la curva de # operaciones a nivel CUOTA -- poblacion
-- distinta, ver nota al inicio del archivo).
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
select
  substr(a.fechaproceso,1,6) as periodo
, a.fechaproceso
, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, coalesce(a.dayslate, 0) as mora
, lag(coalesce(a.dayslate, 0)) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso >= '20250201'
)
, cierre_mes as (
select periodo, id_loan, mora, row_number() over (partition by id_loan, periodo order by fechaproceso desc) as rn
from fotos
)
, stock_ids as (
select
  date_format(date_add('month',1,date_parse(periodo,'%Y%m')), '%Y%m') as periodo_target
, id_loan
from cierre_mes
where rn = 1 and mora between 1 and 30
)
, entradas as (
select distinct periodo, id_loan
from fotos
where mora_ant = 0 and mora = 1
)
, calendario as (
select
  substr(cast(c.fechavencimiento as varchar),1,7) as periodo_venc
, c.id_ihfintech_loan as id_loan
from dts_cobranza_creditos_cuotas c
where c.status in ('ACTIVE','COMPLETED')
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento >= date('2025-08-01')
  and c.fechavencimiento <= date('2026-05-31')
)
, calendario_mes as (
select replace(periodo_venc,'-','') as periodo, id_loan
from calendario cal
where not exists (
    select 1 from stock_ids s
    where s.periodo_target = replace(cal.periodo_venc,'-','') and s.id_loan = cal.id_loan
  )
group by 1, 2
)
select
  cm.periodo
, count(distinct cm.id_loan) as elegibles
, count(distinct e.id_loan) as entradas
, round(100.0*count(distinct e.id_loan)/count(distinct cm.id_loan), 2) as pct_entra_en_mora
from calendario_mes cm
left join entradas e on e.periodo = cm.periodo and e.id_loan = cm.id_loan
group by 1
order by 1
;

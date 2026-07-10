-- =====================================================================
-- MOTOR ALTERNATIVO "CUOTA-CONSISTENTE" (tasa + curva por vencimiento
-- de cuota, NO por dayslate) - ejecutado 2026-07-10, DESCARTADO.
--
-- Contexto: el usuario propuso usar 25% (complemento simple de "% paga
-- a tiempo") como P(no paga a tiempo). Un sweep contra el backtest de
-- junio (fase3_backtest.sql / backtest_junio.py) con la curva_nuevos
-- SIN cambios mostro que 25-28% sobreestima +66% a +81% (ver BUGS.md).
-- Aqui se construyo la version "propiamente consistente": tasa Y curva
-- ambas redefinidas con el mismo criterio (vencimiento de cuota,
-- deduplicando episodios via LAG, analogo a como dayslate solo cuenta
-- la PRIMERA entrada mora_ant=0/mora=1). Resultado: tasa 8.62% (mucho
-- MAS BAJA que 13.38%, no mas alta), y su backtest en backtest_motor_
-- cuota.py SUBESTIMA junio en -35.7% -- falla en la direccion opuesta.
-- Conclusion: NINGUNA alternativa supera al modelo oficial (dayslate
-- 13.38% + su curva, +5.4% de error). Causa exacta de por que 8.62%
-- difiere tanto de 13.38% queda abierta (ver IDEAS.md).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. TASA DE ENTRADA calibrada fuera de muestra (ago-2025 a may-2026,
-- SIN junio), definiendo "entrada" como: cuota actual NO a tiempo
-- (installmentstate != 'PAID' o pagada tarde) Y la cuota INMEDIATA
-- ANTERIOR del mismo credito (por fechavencimiento) SI estaba a tiempo
-- -- analogo a mora_ant=0/mora=1 de dayslate, pero via LAG sobre
-- dts_cobranza_creditos_cuotas. "elegibles" excluye el mismo stock_ids
-- que usa el motor oficial (fase3_backtest.sql bloque 3H).
-- Resultado: 30,901 entradas / 358,361 elegibles = 8.62% (rango
-- mensual 7.98%-10.53%). Comparar con elegibles=358,580 del calculo
-- por dayslate (fase3_backtest.sql 3H) -- casi identico, confirma que
-- ambas definiciones parten de la misma poblacion base.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select substr(a.fechaproceso,1,6) as periodo, a.fechaproceso,
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan,
    coalesce(a.dayslate,0) as mora
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan=a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan=a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1)=1
    and a.fechaproceso >= '20250201'
)
, cierre_mes as (
  select periodo, id_loan, mora, row_number() over (partition by id_loan, periodo order by fechaproceso desc) as rn
  from fotos
)
, stock_ids as (
  select date_format(date_add('month',1,date_parse(periodo,'%Y%m')), '%Y%m') as periodo_target, id_loan
  from cierre_mes where rn=1 and mora between 1 and 30
)
, cuotas_all as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , case when c.installmentstate='PAID' and coalesce(c.dias_vencimiento_a_pago,0)<=0 then 1 else 0 end as a_tiempo
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED') and c.flg_last_loan_in_chain=1
    and c.fechavencimiento between date('2025-07-01') and date('2026-06-30')
)
, seq as (
  select id_loan, fechavencimiento, a_tiempo,
    lag(a_tiempo) over (partition by id_loan order by fechavencimiento) as a_tiempo_prev
  from cuotas_all
)
, entradas_raw as (
  select id_loan, fechavencimiento,
    replace(substr(cast(fechavencimiento as varchar),1,7),'-','') as periodo
  from seq where a_tiempo=0 and a_tiempo_prev=1
)
, entradas as (
  select er.*
  from entradas_raw er
  where not exists (
    select 1 from stock_ids s where s.periodo_target = er.periodo and s.id_loan = er.id_loan
  )
)
, cuotas_elegibles as (
  select ca.*, replace(substr(cast(ca.fechavencimiento as varchar),1,7),'-','') as periodo
  from cuotas_all ca
  where not exists (
    select 1 from stock_ids s
    where s.periodo_target = replace(substr(cast(ca.fechavencimiento as varchar),1,7),'-','')
      and s.id_loan = ca.id_loan
  )
)
, elegibles_mes as (
  select periodo, count(distinct id_loan) as elegibles
  from cuotas_elegibles
  where periodo between '202508' and '202605'
  group by 1
)
, entradas_mes as (
  select periodo, count(distinct id_loan) as entradas
  from entradas
  where periodo between '202508' and '202605'
  group by 1
)
select el.periodo, el.elegibles, coalesce(en.entradas,0) as entradas,
  round(100.0*coalesce(en.entradas,0)/el.elegibles,2) as pct
from elegibles_mes el
left join entradas_mes en on en.periodo=el.periodo
order by 1
;

-- ---------------------------------------------------------------------
-- Q2. CURVA DE RECUPERO propia para este motor (avance x dias desde
-- entrada, misma logica de "entrada" que Q1, sin exclusion de stock
-- porque por construccion una entrada fresca no puede ser stock).
-- Guardada en datos_motor_cuota/curva_nuevos_cuota.csv.
-- ---------------------------------------------------------------------
with cuotas_all as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , case when c.installmentstate='PAID' and coalesce(c.dias_vencimiento_a_pago,0)<=0 then 1 else 0 end as a_tiempo
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED') and c.flg_last_loan_in_chain=1
    and c.fechavencimiento between date('2025-02-15') and date('2026-05-31')
)
, seq as (
  select id_loan, fechavencimiento, a_tiempo,
    lag(a_tiempo) over (partition by id_loan order by fechavencimiento) as a_tiempo_prev
  from cuotas_all
)
, entradas_raw as (
  select id_loan, date_add('day',1,fechavencimiento) as fecha_entrada_d
  from seq where a_tiempo=0 and a_tiempo_prev=1
    and fechavencimiento between date('2025-03-01') and date('2026-05-31')
)
, entradas as (
  select e.id_loan, e.fecha_entrada_d,
    date_format(e.fecha_entrada_d,'%Y%m%d') as fecha_entrada_s,
    f.balances_principalbalance as saldo_entrada,
    b.amountfinanced,
    case when f.balances_principalbalance >= 0.9*b.amountfinanced then 'a. avance <10%'
         when f.balances_principalbalance >= 0.6*b.amountfinanced then 'b. avance 10-40%'
         when f.balances_principalbalance >= 0.3*b.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from entradas_raw e
  join dts_mambu_loans_hist f
    on f._datos_adicionales_loan_accounts_id_ihfintech = e.id_loan
   and f.fechaproceso = date_format(e.fecha_entrada_d,'%Y%m%d')
  join dts_okaapi_loans b on b.id_ihfintech_loan = e.id_loan
  where b.amountfinanced > 0 and f.balances_principalbalance > 0
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20250301' and '20260630'
)
, rebajes as (
  select e.id_loan, e.avance_band, e.saldo_entrada,
    date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso,'%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from entradas e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada_s
    and f.fechaproceso <= date_format(date_add('day',31,e.fecha_entrada_d),'%Y%m%d')
)
, rebaje_dia as (
  select avance_band, dia_desde_entrada, sum(rebaje) as rebaje_dia
  from rebajes group by 1,2
)
, base_total as (
  select avance_band, sum(saldo_entrada) as saldo_entrada_total, count(*) as entradas
  from entradas group by 1
)
select r.avance_band, r.dia_desde_entrada,
  round(sum(r.rebaje_dia) over (partition by r.avance_band order by r.dia_desde_entrada) / b.saldo_entrada_total*100,3) as pct_recupero_acum,
  b.entradas
from rebaje_dia r join base_total b on b.avance_band=r.avance_band
order by 1,2
;

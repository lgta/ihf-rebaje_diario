-- =====================================================================
-- INVESTIGACION: hueco de frontera de mes en la capa fantasma (bug 14).
-- Ejecutado 2026-08-20 (continuacion). Ver BUGS.md bug 14 ("Actualizacion
-- 2026-08-20 (continuacion, EN PROGRESO...") y reconciliacion_vw_
-- seguimiento_temprana.md (pendiente 1) para el contexto completo.
--
-- Hallazgo: una cuota vencida el ULTIMO DIA de un mes de 30 dias (ej.
-- 30-jun), pagada 1 dia tarde (fecha_pago=1-jul), queda fuera del filtro
-- fechavencimiento de la capa fantasma (que solo mira dentro del mes
-- objetivo). El 31-may (frontera hacia junio) tiene 0 cuotas vencidas --
-- sin impacto ahi. El 30-jun (frontera hacia julio) tiene 9,115 cuotas --
-- impacto real, ya confirmado en el backtest (julio +0.12% -> +1.68%,
-- empeora pero sigue siendo buen numero).
--
-- Fix ADOPTADO en produccion 2026-08-20: filtrar por fecha_pago
-- (fechavencimiento+1) cayendo dentro del mes objetivo, en vez de por
-- fechavencimiento directo. Aplicado en enfoque_capital_asegurado_
-- backtest.sql (BT-ASEG-3), investigacion_capa_fantasma.sql (Q1/Q2/Q3),
-- reconciliacion_temprana.sql (Q5), enfoque_capital_asegurado.sql (Q3,
-- produccion) y meta_agosto_capital_asegurado.py (meta en vivo, v3). Como
-- tasa y calendario deben compartir la misma definicion de "periodo"
-- (CLAUDE.md), P_FANTASMA se recalibro junto con el fix: 8.4534% ->
-- 8.5524%. Backtest final consistente: junio +2.2%->+2.65%, julio
-- +0.12%->+2.17% (ver BUGS.md bug 14 para el detalle completo, incluyendo
-- el hallazgo de que la primera pasada -- tasa vieja + calendario fijo --
-- era inconsistente).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Volumen de cuotas vencidas en cada frontera de mes relevante (para
-- calibrar el impacto esperado antes de decidir si vale la pena el fix en
-- cada caso). Resultado: 31-may=0, 28/29-jun=normal, 30-jun=9,115 (pico),
-- 30-jul=9,211 (pico), 31-jul=101 (casi nada), 1-ago=3,065 (normal). Los
-- creditos parecen concentrarse casi siempre en el dia 30 de cada mes,
-- casi nunca en el 31 (sea el mes de 30 o 31 dias) -- eso explica por que
-- mayo->junio no tiene impacto pero junio->julio si.
-- ---------------------------------------------------------------------
select fechavencimiento, count(*) as n
from dts_cobranza_creditos_cuotas
where fechavencimiento in (date('2026-05-29'), date('2026-05-30'), date('2026-05-31'),
  date('2026-06-28'), date('2026-06-29'), date('2026-06-30'),
  date('2026-07-29'), date('2026-07-30'), date('2026-07-31'), date('2026-08-01'))
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- Q2. Calendario propio de la capa fantasma para junio (con el fix de
-- fecha_pago), para usar en el backtest en vez de reutilizar el calendario
-- compartido con "nuevos" (que no tiene este ajuste). Resultado: da lo
-- mismo que antes en la practica -- ver nota abajo, no fue necesario
-- usarlo porque el loop del backtest_capital_asegurado_junio.py ya excluye
-- estructuralmente el ultimo dia del mes objetivo (dias_desde_entrada<1
-- => continue), asi que el hueco de mayo (vacio) y de junio (excluido
-- aguas abajo de todos modos) no cambian nada para JUNIO especificamente.
-- Solo queda relevante para julio/agosto donde el mes anterior SI tiene
-- volumen en su ultimo dia.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260501' and '20260629'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    d.fechaproceso, d.id_loan, d.saldo, coalesce(d.dayslate,0) as mora
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, fotos_may as (
  select id_loan, saldo, mora,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260531'
)
, stock_junio_ids as (
  select id_loan from fotos_may where rn=1 and mora between 1 and 30 and saldo > 0
)
select
  c.fechavencimiento
, count(distinct c.id_ihfintech_loan) as creditos
, round(sum(f.saldo),0) as saldo_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
join fotos f
  on f.id_loan = c.id_ihfintech_loan
 and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
where c.status in ('ACTIVE','COMPLETED')
  and c.flg_last_loan_in_chain = 1
  and date_add('day',1,c.fechavencimiento) >= date('2026-06-01')
  and date_add('day',1,c.fechavencimiento) <= date('2026-06-30')
  and b.amountfinanced > 0
  and c.id_ihfintech_loan not in (select id_loan from stock_junio_ids)
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- Q3. Caracterizacion del cohorte nuevo de julio (cuotas vencidas 30-jun,
-- agregadas por el fix de frontera de mes): tasa real de "paga 1 dia
-- tarde" de este dia especifico vs. el promedio historico. Resultado:
-- 7,468 elegibles, 600 pagan 1 dia tarde (8.03% -- CASI IGUAL al promedio
-- P_FANTASMA=8.45%, no es una poblacion distinta).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260630'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    d.fechaproceso, d.id_loan, d.saldo, coalesce(d.dayslate,0) as mora
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio_ids as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, cohorte_30jun as (
  select c.id_ihfintech_loan as id_loan, c.installmentstate, c.dias_vencimiento_a_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento = date('2026-06-30')
    and c.id_ihfintech_loan not in (select id_loan from stock_julio_ids)
)
select
  count(*) as elegibles_30jun
, sum(case when installmentstate='PAID' and dias_vencimiento_a_pago=1 then 1 else 0 end) as paga_1dia_tarde
, round(100.0*sum(case when installmentstate='PAID' and dias_vencimiento_a_pago=1 then 1 else 0 end)/count(*), 2) as pct_paga_1dia_tarde
, sum(case when installmentstate='PAID' and coalesce(dias_vencimiento_a_pago,0)<=0 then 1 else 0 end) as paga_a_tiempo
, sum(case when installmentstate='PAID' and dias_vencimiento_a_pago>=2 then 1 else 0 end) as paga_2mas_dias_tarde
, sum(case when installmentstate<>'PAID' then 1 else 0 end) as no_pagada_aun
from cohorte_30jun
;

-- ---------------------------------------------------------------------
-- Q4. De los 600 que pagan 1 dia tarde (Q3), cuantos ya estaban contados
-- por OTRO evento real de mora (dayslate) en julio -- se excluyen de la
-- capa fantasma para no duplicar. Resultado: 150 de 600 (25%) ya
-- contados, neto 450 -- 450/7,468=6.03%, por debajo del promedio. Es
-- dilucion por solapamiento (creditos con OTRO problema de mora ese mes),
-- no un error de calculo.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260601' and '20260731'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    d.fechaproceso, d.id_loan, d.saldo, coalesce(d.dayslate,0) as mora
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio_ids as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, fotos_con_lag as (
  select id_loan, fechaproceso, saldo, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
  where fechaproceso between '20260701' and '20260731'
)
, entradas_reales_julio as (
  select distinct id_loan
  from fotos_con_lag
  where mora_ant = 0 and mora = 1 and fechaproceso between '20260702' and '20260731'
    and id_loan not in (select id_loan from stock_julio_ids)
)
, cohorte_30jun as (
  select c.id_ihfintech_loan as id_loan
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento = date('2026-06-30')
    and c.installmentstate = 'PAID'
    and c.dias_vencimiento_a_pago = 1
    and c.id_ihfintech_loan not in (select id_loan from stock_julio_ids)
)
select
  count(*) as paga_1dia_tarde_30jun,
  sum(case when er.id_loan is not null then 1 else 0 end) as ya_contado_via_dayslate_otro_evento,
  sum(case when er.id_loan is null then 1 else 0 end) as neto_fantasma
from cohorte_30jun c
left join entradas_reales_julio er on er.id_loan = c.id_loan
;

-- ---------------------------------------------------------------------
-- Q5. TASA P_FANTASMA RECALIBRADA con el fix de frontera de mes (periodo
-- por fecha_pago, no por fechavencimiento). Corrida 2026-08-20 al
-- implementar el fix en produccion -- ver enfoque_capital_asegurado.sql
-- Q3 (misma query, ya con el fix aplicado) para el detalle completo.
-- Resultado: 346,396 elegibles / 29,625 entradas fantasma = 8.5524%
-- (antes 353,054/29,845=8.4534%). El cambio viene de los dos extremos de
-- la ventana fuera de muestra (ago-2025 a may-2026): se gana la cohorte
-- del 31-jul-2025 (fecha_pago=1-ago-2025, antes fuera de la ventana) y se
-- pierde la del 31-may-2026 (fecha_pago=1-jun-2026, junio esta excluido
-- de la muestra para evitar leakage con el mes de backtest).
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
, entradas_reales as (
  select distinct periodo, id_loan
  from fotos
  where mora_ant = 0 and mora = 1
)
, calendario as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , date_format(date_add('day',1,c.fechavencimiento), '%Y%m') as periodo_pago
  , c.installmentstate
  , c.dias_vencimiento_a_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2025-07-31')
    and c.fechavencimiento <= date('2026-05-31')
)
, calendario_mes as (
  -- OJO: dedup a 1 fila por (periodo,id_loan) SIN cargar installmentstate/
  -- dias_vencimiento_a_pago en el group by (si un credito tuviera 2 cuotas
  -- en el mismo periodo con esos campos distintos, cargarlos infla
  -- "elegibles" -- verificado contra el baseline conocido 353,054/29,845
  -- con esta misma estructura antes de confiar en el numero nuevo).
  select periodo_pago as periodo, id_loan
  from calendario cal
  where periodo_pago between '202508' and '202605'
    and not exists (
      select 1 from stock_ids s
      where s.periodo_target = cal.periodo_pago and s.id_loan = cal.id_loan
    )
  group by 1, 2
)
, entradas_fantasma as (
  select distinct cal.periodo_pago as periodo, cal.id_loan
  from calendario cal
  where cal.installmentstate = 'PAID' and cal.dias_vencimiento_a_pago = 1
    and cal.periodo_pago between '202508' and '202605'
    and not exists (
      select 1 from entradas_reales er
      where er.periodo = cal.periodo_pago and er.id_loan = cal.id_loan
    )
)
select
  count(*) as elegibles
, count(ef.id_loan) as entradas_fantasma
, round(100.0*count(ef.id_loan)/count(*), 4) as pct_entrada_fantasma
from calendario_mes cm
left join entradas_fantasma ef on ef.periodo = cm.periodo and ef.id_loan = cm.id_loan
;

-- ---------------------------------------------------------------------
-- Q6. HUECO DE AGOSTO -- saldo en riesgo de la cuota vencida 31-jul-2026
-- (fecha_pago=1-ago, fuera de ago_calendario.csv que arranca 1-ago),
-- excluyendo el stock de agosto (mora 1-30 al cierre de julio). Corrida
-- 2026-08-20 para confirmar el impacto con datos antes de asumirlo chico.
-- Resultado: 77 creditos / S/140,194 en riesgo -- chico, como se
-- esperaba por el patron de Q1 (creditos concentrados en dia 30, casi
-- nunca el 31), pero confirmado, no supuesto. Ver meta_agosto_capital_
-- asegurado.py v3 (CUOTAS_31JUL_FANTASMA).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  , b.amountfinanced
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260701' and '20260731'
    and b.status in ('ACTIVE','COMPLETED')
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    d.fechaproceso, d.id_loan, d.saldo, coalesce(d.dayslate,0) as mora, d.amountfinanced
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_julio as (
  select id_loan, mora, saldo, amountfinanced,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_agosto_ids as (
  select id_loan from cierre_julio where rn = 1 and mora between 1 and 30 and saldo > 0
)
select
  case when fo.saldo >= 0.9*fo.amountfinanced then 'a. avance <10%'
       when fo.saldo >= 0.6*fo.amountfinanced then 'b. avance 10-40%'
       when fo.saldo >= 0.3*fo.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, count(distinct c.id_ihfintech_loan) as creditos
, round(sum(fo.saldo),0) as saldo_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
join fotos fo on fo.id_loan = c.id_ihfintech_loan and fo.fechaproceso = '20260731'
where c.status in ('ACTIVE','COMPLETED')
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento = date('2026-07-31')
  and b.amountfinanced > 0
  and c.id_ihfintech_loan not in (select id_loan from stock_agosto_ids)
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- Q7. REAL YA OBSERVADO de la cohorte 31-jul (Q6) al 20-ago -- cuantos de
-- los 77 creditos ya pagaron 1 dia tarde de verdad (el desenlace se
-- conoce el 1-ago, ya esta resuelto y no cambia). Resultado: solo 4
-- creditos / S/3,556.95 -- va a REAL_FANTASMA_A_HOY en meta_agosto_
-- capital_asegurado.py v3, separado del calendario proyectado (Q6, que
-- se multiplica por P_FANTASMA como estimacion, no como realizado).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260701' and '20260820'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    d.fechaproceso, d.id_loan, d.saldo, coalesce(d.dayslate,0) as mora
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, fotos_con_lag as (
  select id_loan, fechaproceso, saldo, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
  where fechaproceso between '20260801' and '20260820'
)
, cierre_julio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_agosto_ids as (
  select id_loan from cierre_julio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_reales_agosto as (
  select distinct id_loan
  from fotos_con_lag
  where mora_ant = 0 and mora = 1
    and id_loan not in (select id_loan from stock_agosto_ids)
)
, cohorte_31jul as (
  select c.id_ihfintech_loan as id_loan, c.installmentstate, c.dias_vencimiento_a_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento = date('2026-07-31')
    and c.id_ihfintech_loan not in (select id_loan from stock_agosto_ids)
)
, fantasma_31jul as (
  select cu.id_loan
  from cohorte_31jul cu
  where cu.installmentstate = 'PAID' and cu.dias_vencimiento_a_pago = 1
    and cu.id_loan not in (select id_loan from entradas_reales_agosto)
)
select
  count(*) as elegibles_31jul
, (select count(*) from fantasma_31jul) as fantasma_real_31jul
, (select round(sum(fo.saldo),2) from fantasma_31jul f
     join fotos fo on fo.id_loan = f.id_loan and fo.fechaproceso = '20260731') as saldo_real_31jul
from cohorte_31jul
;

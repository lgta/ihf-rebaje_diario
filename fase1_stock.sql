-- =====================================================================
-- FASE 1 - MOTOR DEL STOCK (mora 1-30 al inicio de mes)
-- Ejecutada 2026-07-08 en Athena (db dev_datalake_master). Ver
-- plan_analisis.md para resultados e interpretacion.
--
-- Definiciones:
--  * "Inicio de mes" = ultima foto del mes anterior (cierre). Asi un
--    credito que paga el dia 1 no se escapa de la base asignada, y los
--    que entran en mora el dia 1 quedan como "nuevos", no como stock.
--  * El credito mantiene su tramo todo el mes aunque cruce 30 dias.
--  * dayslate es NULL cuando esta al dia -> coalesce(dayslate, 0).
--  * Rebaje diario = max(saldo_ant - saldo, 0); deltas negativos
--    (capitalizaciones, <2% del rebaje) se tratan como 0.
--  * Meses meta: 202504 a 202606 (14 meses completos y estables).
--  * EXCLUSION DE REENGANCHES/REFINANCIAMIENTOS: dts_okaapi_loans no
--    tiene un flag directo de "ultimo credito de la cadena" que sea
--    equivalente a flg_last_loan_in_chain de dts_cobranza_creditos_cuotas
--    (se probo extendedbyloan_id: coincide bien, pero por prolijidad se
--    usa el flag de cuotas, que es la fuente que confirmo el usuario).
--    Se deriva un flag a nivel credito (max(flg_last_loan_in_chain) por
--    id_ihfintech_loan, es constante por credito) y se filtra
--    coalesce(last_in_chain,1)=1 (creditos sin match en cuotas se
--    asumen ultimo de cadena). IMPACTO MEDIDO: pequeno para esta
--    poblacion (mora 1-30) -> ~2% de los credito-mes son reenganches,
--    con severidad ~2x mas alta (27.6% vs 14.7%); el efecto en las
--    curvas finales es de -0.3 a -0.9 puntos porcentuales, no cambia
--    conclusiones. El efecto grande (+7-12 puntos) que se vio al
--    validar contra la curva de # operaciones ocurre porque esa curva
--    se mide sobre TODA la cartera (incluye renovaciones sanas fuera
--    de mora), no sobre el universo acotado de mora 1-30 de aqui.
--
-- CTEs BASE (comunes a todos los bloques; cada bloque final se pega
-- debajo de estas CTEs):
-- =====================================================================
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas
group by 1
)
, fotos as (
select
  substr(a.fechaproceso, 1, 6)                       as periodo
, a.fechaproceso
, cast(substr(a.fechaproceso, 7, 2) as int)          as dia
, a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
, a.balances_principalbalance                        as saldo
, coalesce(a.dayslate, 0)                            as mora
, b."term"                                           as term
, b.amountfinanced
, lag(a.balances_principalbalance) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as saldo_ant
from dts_mambu_loans_hist a
join dts_okaapi_loans b
  on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc
  on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and a.fechaproceso >= '20250301'
  and coalesce(lc.last_in_chain, 1) = 1
)
, cierre_mes as (
select *
, row_number() over (partition by id_loan, periodo order by fechaproceso desc) as rn
from fotos
)
, stock as (
select
  date_format(date_add('month', 1, date_parse(periodo, '%Y%m')), '%Y%m') as periodo_meta
, id_loan
, saldo                                               as saldo_inicial
, mora                                                as mora_inicial
, case when mora between 1 and 8  then 'a. 1-8'
       when mora between 9 and 15 then 'b. 9-15'
       else                            'c. 16-30' end as tramo
, term
, amountfinanced
from cierre_mes
where rn = 1
  and mora between 1 and 30
  and saldo > 0
)
, rebajes as (
select
  s.periodo_meta
, s.tramo
, s.id_loan
, s.saldo_inicial
, f.dia
, case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
from stock s
join fotos f
  on f.id_loan = s.id_loan
 and f.periodo = s.periodo_meta
where s.periodo_meta between '202504' and '202606'
)

-- =====================================================================
-- 1A. CURVA DE RECUPERO ACUMULADO POR TRAMO x DIA DEL MES
--     (esta es la query completa; los demas bloques reemplazan
--      desde aqui hacia abajo)
-- =====================================================================
, rebaje_dia as (
select tramo, dia, sum(rebaje) as rebaje_dia
from rebajes
group by 1, 2
)
, saldo_ini as (
select tramo, sum(saldo_inicial) as saldo_inicial_total
from stock
where periodo_meta between '202504' and '202606'
group by 1
)
select
  r.tramo
, r.dia
, round(sum(r.rebaje_dia) over (partition by r.tramo order by r.dia)
        / s.saldo_inicial_total * 100, 3) as pct_recupero_acum
from rebaje_dia r
join saldo_ini s on s.tramo = r.tramo
order by r.tramo, r.dia
;

-- =====================================================================
-- 1B. ESTABILIDAD MENSUAL POR TRAMO (pegar debajo de CTEs base)
-- =====================================================================
/*
, reb_mes as (
select periodo_meta, tramo, sum(rebaje) as rebaje_mes
from rebajes
group by 1, 2
)
, ini as (
select periodo_meta, tramo, count(*) as creditos, sum(saldo_inicial) as saldo_ini
from stock
where periodo_meta between '202504' and '202606'
group by 1, 2
)
select
  i.periodo_meta
, i.tramo
, i.creditos
, round(i.saldo_ini, 0)                          as saldo_inicial
, round(r.rebaje_mes, 0)                         as rebaje_mes
, round(100.0 * r.rebaje_mes / i.saldo_ini, 2)   as pct_recupero
from ini i
join reb_mes r
  on r.periodo_meta = i.periodo_meta and r.tramo = i.tramo
order by 1, 2
*/

-- =====================================================================
-- 1C. FRECUENCIA x SEVERIDAD POR TRAMO (pegar debajo de CTEs base)
-- =====================================================================
/*
, por_credito as (
select periodo_meta, tramo, id_loan
, max(saldo_inicial) as saldo_inicial
, sum(rebaje)        as rebaje_mes
from rebajes
group by 1, 2, 3
)
select
  tramo
, count(*) as creditos_mes
, round(100.0 * avg(case when rebaje_mes > 0 then 1.0 else 0.0 end), 2)  as pct_creditos_con_pago
, round(100.0 * sum(rebaje_mes) / sum(saldo_inicial), 2)                 as pct_recupero_total
, round(100.0 * sum(case when rebaje_mes > 0 then rebaje_mes else 0 end)
       / sum(case when rebaje_mes > 0 then saldo_inicial else 0 end), 2) as pct_severidad_pagadores
from por_credito
group by 1
order by 1
*/

-- =====================================================================
-- 1D. SEGMENTADORES DE SEVERIDAD: term / saldo / monto / avance
--     Bandas basadas en percentiles del stock (p25/p50/p75):
--     saldo 617/1215/2028 - term 6/10/12 - monto 1244/1844/2803
--     (pegar debajo de CTEs base)
-- =====================================================================
/*
, por_credito as (
select
  r.periodo_meta
, r.tramo
, r.id_loan
, max(r.saldo_inicial) as saldo_inicial
, sum(r.rebaje)        as rebaje_mes
from rebajes r
group by 1, 2, 3
)
, enriquecido as (
select
  p.*
, s.term
, s.amountfinanced
, case when s.term <= 6  then 'a. term 1-6'
       when s.term <= 12 then 'b. term 7-12'
       else                   'c. term 13+' end as term_band
, case when p.saldo_inicial < 600  then 'a. saldo <600'
       when p.saldo_inicial < 1200 then 'b. saldo 600-1200'
       when p.saldo_inicial < 2000 then 'c. saldo 1200-2000'
       else                             'd. saldo 2000+' end as saldo_band
, case when s.amountfinanced < 1250 then 'a. monto <1250'
       when s.amountfinanced < 1850 then 'b. monto 1250-1850'
       when s.amountfinanced < 2800 then 'c. monto 1850-2800'
       else                              'd. monto 2800+' end as monto_band
, case when p.saldo_inicial >= 0.9 * s.amountfinanced then 'a. avance <10%'
       when p.saldo_inicial >= 0.6 * s.amountfinanced then 'b. avance 10-40%'
       when p.saldo_inicial >= 0.3 * s.amountfinanced then 'c. avance 40-70%'
       else                                                'd. avance 70%+' end as avance_band
from por_credito p
join stock s
  on s.id_loan = p.id_loan and s.periodo_meta = p.periodo_meta
)
select * from (
  select 'term' as dimension, tramo, term_band as banda
  , count(*) as creditos
  , round(100.0 * avg(case when rebaje_mes > 0 then 1.0 else 0.0 end), 2) as pct_con_pago
  , round(100.0 * sum(case when rebaje_mes > 0 then rebaje_mes else 0 end)
        / sum(case when rebaje_mes > 0 then saldo_inicial else 0 end), 2) as severidad
  , round(100.0 * sum(rebaje_mes) / sum(saldo_inicial), 2) as recupero_total
  from enriquecido group by 1, 2, 3
  union all
  select 'saldo', tramo, saldo_band
  , count(*)
  , round(100.0 * avg(case when rebaje_mes > 0 then 1.0 else 0.0 end), 2)
  , round(100.0 * sum(case when rebaje_mes > 0 then rebaje_mes else 0 end)
        / sum(case when rebaje_mes > 0 then saldo_inicial else 0 end), 2)
  , round(100.0 * sum(rebaje_mes) / sum(saldo_inicial), 2)
  from enriquecido group by 1, 2, 3
  union all
  select 'monto', tramo, monto_band
  , count(*)
  , round(100.0 * avg(case when rebaje_mes > 0 then 1.0 else 0.0 end), 2)
  , round(100.0 * sum(case when rebaje_mes > 0 then rebaje_mes else 0 end)
        / sum(case when rebaje_mes > 0 then saldo_inicial else 0 end), 2)
  , round(100.0 * sum(rebaje_mes) / sum(saldo_inicial), 2)
  from enriquecido group by 1, 2, 3
  union all
  select 'avance', tramo, avance_band
  , count(*)
  , round(100.0 * avg(case when rebaje_mes > 0 then 1.0 else 0.0 end), 2)
  , round(100.0 * sum(case when rebaje_mes > 0 then rebaje_mes else 0 end)
        / sum(case when rebaje_mes > 0 then saldo_inicial else 0 end), 2)
  , round(100.0 * sum(rebaje_mes) / sum(saldo_inicial), 2)
  from enriquecido group by 1, 2, 3
)
order by dimension, tramo, banda
*/

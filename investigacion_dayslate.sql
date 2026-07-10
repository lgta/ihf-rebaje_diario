-- =====================================================================
-- INVESTIGACION - "PUNTO CIEGO DE 1 DIA" EN dayslate
-- Ejecutada 2026-07-10 en Athena (db dev_datalake_master). Ver
-- BUGS.md y GLOSARIO.md para la explicacion y el hallazgo.
--
-- Pregunta que origino esto: guia_tecnica_recupero.md §2.4 muestra
-- 72.6% "paga a tiempo" (nivel CUOTA, dts_cobranza_creditos_cuotas)
-- vs. 13.38% "no paga a tiempo" (nivel CREDITO, dayslate) que SI usa
-- el modelo. Aqui se mide directamente por que difieren.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. DISTRIBUCION: ¿cuantas cuotas pagadas N dias tarde SI llegan a
-- verse en dayslate (mora_max_ventana >= 1) dentro de una ventana de
-- [vencimiento, vencimiento + dias_tarde + 2]?
-- Resultado (2026-07-10): dias_tarde=1 -> solo 4.3% detectado (458 de
-- 10,533); dias_tarde=2 en adelante -> 100.0% detectado, sin excepcion.
-- Corte binario limpio: la foto diaria practicamente nunca alcanza a
-- capturar una mora que se resuelve en 1 dia.
-- ---------------------------------------------------------------------
with cuotas_late as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , c.dias_vencimiento_a_pago as dias_tarde
  from dts_cobranza_creditos_cuotas c
  where c.fechavencimiento >= date('2026-03-01') and c.fechavencimiento <= date('2026-05-20')
    and c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.installmentstate = 'PAID'
    and c.dias_vencimiento_a_pago between 1 and 20
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , date_parse(a.fechaproceso,'%Y%m%d') as fecha
  , coalesce(a.dayslate,0) as mora
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260301' and '20260610'
)
, cruce as (
  select
    cl.id_loan, cl.fechavencimiento, cl.dias_tarde
  , max(f.mora) as mora_max_ventana
  from cuotas_late cl
  join fotos f
    on f.id_loan = cl.id_loan
   and f.fecha >= cl.fechavencimiento
   and f.fecha <= date_add('day', cast(cl.dias_tarde as integer) + 2, cl.fechavencimiento)
  group by 1,2,3
)
select
  dias_tarde
, count(*) as cuotas_pagadas_tarde
, sum(case when mora_max_ventana >= 1 then 1 else 0 end) as detectadas_por_dayslate
, round(100.0*sum(case when mora_max_ventana>=1 then 1 else 0 end)/count(*),1) as pct_detectada_por_dayslate
from cruce
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- Q2. EJEMPLOS CONCRETOS: creditos pagados 1-3 dias tarde donde
-- dayslate NUNCA registro mora en la ventana. Usar el timeline (Q5)
-- sobre cualquiera de estos id_loan para ver saldo/dayslate dia a dia.
-- ---------------------------------------------------------------------
with cuotas_late as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , c.dias_vencimiento_a_pago as dias_tarde
  from dts_cobranza_creditos_cuotas c
  where c.fechavencimiento >= date('2026-04-01') and c.fechavencimiento <= date('2026-05-10')
    and c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.installmentstate = 'PAID'
    and c.dias_vencimiento_a_pago between 1 and 3
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , date_parse(a.fechaproceso,'%Y%m%d') as fecha
  , coalesce(a.dayslate,0) as mora
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260401' and '20260520'
)
, marcado as (
  select
    cl.id_loan, cl.fechavencimiento, cl.dias_tarde
  , max(f.mora) as mora_max_ventana
  from cuotas_late cl
  join fotos f
    on f.id_loan = cl.id_loan
   and f.fecha >= cl.fechavencimiento
   and f.fecha <= date_add('day', cast(cl.dias_tarde as integer) + 2, cl.fechavencimiento)
  group by 1,2,3
)
select id_loan, fechavencimiento, dias_tarde, mora_max_ventana
from marcado
where mora_max_ventana = 0
order by fechavencimiento
limit 5
;

-- ---------------------------------------------------------------------
-- Q3. HIPOTESIS DE "POBLACION" (exclusion de stock) - DESCARTADA COMO
-- CAUSA DOMINANTE. Solo mueve 72.2% -> 74.0% (2pp), no explica la
-- brecha real frente al 13.38%/86.62% a nivel credito.
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
, cuotas as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , substr(cast(c.fechavencimiento as varchar),1,7) as periodo_venc_txt
  , c.installmentstate
  , c.dias_vencimiento_a_pago
  , c.id_loan_nro_cuota
  from dts_cobranza_creditos_cuotas c
  where c.fechavencimiento >= date('2025-08-01') and c.fechavencimiento <= date('2026-05-31')
    and c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
)
, cuotas_elegibles as (
  select cu.*
  from cuotas cu
  where not exists (
    select 1 from stock_ids s
    where s.periodo_target = replace(cu.periodo_venc_txt,'-','')
      and s.id_loan = cu.id_loan
  )
)
select 'sin_filtro_stock' as universo, count(distinct id_loan_nro_cuota) as cuotas_total,
  count(distinct case when installmentstate='PAID' and coalesce(dias_vencimiento_a_pago,0) <= 0 then id_loan_nro_cuota end) as pagadas_a_tiempo,
  round(100.0*count(distinct case when installmentstate='PAID' and coalesce(dias_vencimiento_a_pago,0)<=0 then id_loan_nro_cuota end)/count(distinct id_loan_nro_cuota),2) as pct_a_tiempo
from cuotas
union all
select 'excluye_stock_elegibles', count(distinct id_loan_nro_cuota),
  count(distinct case when installmentstate='PAID' and coalesce(dias_vencimiento_a_pago,0) <= 0 then id_loan_nro_cuota end),
  round(100.0*count(distinct case when installmentstate='PAID' and coalesce(dias_vencimiento_a_pago,0)<=0 then id_loan_nro_cuota end)/count(distinct id_loan_nro_cuota),2)
from cuotas_elegibles
;

-- ---------------------------------------------------------------------
-- Q4. GAP CALENDARIO -> ENTRADA: para eventos reales de entrada en mora
-- (dayslate 0->1), cuantos dias hay entre el vencimiento de la cuota
-- que la origino y fecha_entrada (primera foto con dayslate=1).
-- Resultado (2026-07-10): 20,069 de 20,069 casos (100%) con gap = 1
-- dia exacto. Descarta un desalineamiento de 2+ dias entre el
-- calendario (fechavencimiento) y el origen de curva_nuevos
-- (fecha_entrada) -- el desfase real es de solo ~1 dia.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , coalesce(a.dayslate,0) as mora
  , lag(coalesce(a.dayslate,0)) over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan=a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan=a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1)=1
    and a.fechaproceso between '20260301' and '20260531'
)
, entradas as (
  select id_loan, date_parse(fechaproceso,'%Y%m%d') as fecha_entrada
  from fotos where mora_ant=0 and mora=1
)
, cuotas as (
  select c.id_ihfintech_loan as id_loan, c.fechavencimiento
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED') and c.flg_last_loan_in_chain=1
    and c.fechavencimiento between date('2026-02-15') and date('2026-05-31')
)
, cruce as (
  select e.id_loan, e.fecha_entrada,
    max(c.fechavencimiento) as vencimiento_relevante
  from entradas e
  join cuotas c on c.id_loan = e.id_loan and c.fechavencimiento <= e.fecha_entrada
  group by 1,2
)
select
  date_diff('day', vencimiento_relevante, fecha_entrada) as dias_gap
, count(*) as creditos
from cruce
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- Q5. TIMELINE de un credito ejemplo (usar cualquier id_loan de Q2).
-- Ejemplo documentado: eb9ef9f2-0326-484d-85b8-164a3e974da9, vencio
-- 2026-04-01, pago 2026-04-02 (saldo 291.90 -> 150.22 ese dia), y
-- dayslate se mantuvo en 0 TODO el tiempo.
-- ---------------------------------------------------------------------
select
  a.fechaproceso
, coalesce(a.dayslate,0) as dayslate
, a.balances_principalbalance as saldo
from dts_mambu_loans_hist a
where a._datos_adicionales_loan_accounts_id_ihfintech = 'eb9ef9f2-0326-484d-85b8-164a3e974da9'
  and a.fechaproceso between '20260328' and '20260405'
order by a.fechaproceso
;

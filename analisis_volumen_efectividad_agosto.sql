-- =====================================================================
-- VOLUMEN vs EFECTIVIDAD -- agosto 2026, corte 21-ago (2026-08-22,
-- continuacion de bug 16 en BUGS.md). Responde 3 preguntas:
--
-- (2) Proyectado-a-la-fecha vs Real-a-la-fecha, MISMO corte (21-ago) --
--     no un mes cerrado. Corte elegido: 21-ago, no 22-ago (hoy), porque
--     dts_asignaciones_gestiones_cobranza (necesaria para K5) solo tiene
--     datos hasta 2026-08-21 -- un solo corte para las 5 queries, evita
--     comparar poblaciones a fechas distintas.
-- (3) Desagregado por segmento: tramo x avance para stock, avance para
--     nuevos (fantasma no se segmenta, el mecanismo no usa curva propia).
-- (4) Volumen (K4: tasa de entrada real vs 13.38% modelado) vs Efectividad
--     (K5: tasa de activacion grupo_control vs gestionado, MISMO corte).
--
-- Ver analisis_volumen_efectividad_agosto.md para la interpretacion
-- completa y las tablas finales. Todas las queries siguen el patron base
-- de FUENTES_DATOS.md: status IN (ACTIVE,COMPLETED), flg_last_loan_in_chain,
-- coalesce(dayslate,0), dedup de bug 11 (saldo<>0 antes de lastmodifieddate).
-- =====================================================================

-- ---------------------------------------------------------------------
-- K1. STOCK real activado, segmentado tramo x avance, agosto 1-21.
-- Poblacion = mora 1-30 cierre de julio UNION entrantes dia 1 agosto
-- (bug 12), igual construccion que enfoque_capital_asegurado.sql Q1 /
-- cierre_julio.sql J1, aplicado a agosto con corte parcial (no mes
-- completo). Resultado: 2,695 creditos / S/4,460,502 poblacion,
-- 1,772 activados / S/2,734,665 real asegurado.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw_mambu as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.dayslate
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260725' and '20260821'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw_mambu
)
, fotos as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.amountfinanced
  , lag(d.saldo) over (partition by d.id_loan order by d.fechaproceso) as saldo_ant
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_julio as (
  select id_loan, mora, saldo, amountfinanced, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, dia1_agosto as (
  select id_loan, mora, saldo, amountfinanced, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260801'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial, amountfinanced,
    case when mora between 1 and 8 then 'a. 1-8' when mora between 9 and 15 then 'b. 9-15' else 'c. 16-30' end as tramo
  from cierre_julio where rn=1 and mora between 1 and 30 and saldo>0 and amountfinanced>0
)
, dia1_entrantes as (
  select id_loan, saldo as saldo_inicial, amountfinanced, 'a. 1-8' as tramo
  from dia1_agosto where rn=1 and mora=1 and saldo>0 and amountfinanced>0
)
, stock_agosto as (
  select *, case when saldo_inicial >= 0.9*amountfinanced then 'a. avance <10%'
                 when saldo_inicial >= 0.6*amountfinanced then 'b. avance 10-40%'
                 when saldo_inicial >= 0.3*amountfinanced then 'c. avance 40-70%'
                 else 'd. avance 70%+' end as avance_band
  from (select * from stock_previo union all select * from dia1_entrantes)
)
, activacion as (
  select s.id_loan, s.tramo, s.avance_band, s.saldo_inicial,
    max(coalesce(case when f.saldo_ant > f.saldo then 1 else 0 end,0)) as activado
  from stock_agosto s
  left join fotos f on f.id_loan = s.id_loan and f.fechaproceso between '20260801' and '20260821'
  group by 1,2,3,4
)
select tramo, avance_band,
  count(*) as creditos_total, round(sum(saldo_inicial),2) as saldo_total,
  sum(activado) as creditos_activados, round(sum(saldo_inicial*activado),2) as saldo_asegurado_real
from activacion
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- K2. NUEVOS real activado, segmentado por avance, agosto dia 2-21.
-- Entradas dayslate 0->1 excluyendo dia 1 (bug 12) y excluyendo stock.
-- Resultado: 5,196 creditos / S/8,226,625 poblacion (coincide EXACTO
-- con entradas_reales de K4 -- valida ambas queries), 3,618 activados /
-- S/5,537,431 real asegurado.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw_mambu as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.dayslate
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260701' and '20260821'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw_mambu
)
, fotos as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  , lag(coalesce(d.dayslate,0)) over (partition by d.id_loan order by d.fechaproceso) as mora_ant
  , lag(d.saldo) over (partition by d.id_loan order by d.fechaproceso) as saldo_ant
  , b.amountfinanced
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_julio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_agosto_ids as (
  select id_loan from cierre_julio where rn=1 and mora between 1 and 30 and saldo>0
)
, entradas as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada,
    case when f.saldo >= 0.9*f.amountfinanced then 'a. avance <10%'
         when f.saldo >= 0.6*f.amountfinanced then 'b. avance 10-40%'
         when f.saldo >= 0.3*f.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260802' and '20260821'
    and f.amountfinanced > 0
    and f.id_loan not in (select id_loan from stock_agosto_ids)
)
, activacion as (
  select e.id_loan, e.avance_band, e.saldo_entrada,
    max(coalesce(case when f.saldo_ant > f.saldo then 1 else 0 end,0)) as activado
  from entradas e
  left join fotos f on f.id_loan = e.id_loan and f.fechaproceso > e.fecha_entrada and f.fechaproceso <= '20260821'
  group by 1,2,3
)
select avance_band,
  count(*) as creditos_total, round(sum(saldo_entrada),2) as saldo_total,
  sum(activado) as creditos_activados, round(sum(saldo_entrada*activado),2) as saldo_asegurado_real
from activacion
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- K3. FANTASMA real (agregado, sin segmentar -- el mecanismo no usa
-- curva propia), agosto 1-21, incluye cohorte 31-jul (fecha_pago=1-ago).
-- Resultado: S/3,348,684 / 2,403 creditos.
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
  where a.fechaproceso between '20260725' and '20260821'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    d.fechaproceso, d.id_loan, d.saldo
  , coalesce(d.dayslate,0) as mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_julio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_julio_ids as (
  select id_loan from cierre_julio where rn=1 and mora between 1 and 30 and saldo>0
)
, entradas_reales_agosto as (
  select distinct id_loan
  from (
    select id_loan, fechaproceso, mora,
      lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
    from fotos where fechaproceso between '20260801' and '20260821'
  ) x
  where mora_ant=0 and mora=1
)
, cuotas_agosto as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , c.installmentstate
  , c.dias_vencimiento_a_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and date_add('day', 1, c.fechavencimiento) >= date('2026-08-01')
    and date_add('day', 1, c.fechavencimiento) <= date('2026-08-21')
    and c.id_ihfintech_loan not in (select id_loan from stock_julio_ids)
)
, fantasma_agosto as (
  select cu.id_loan, cu.fechavencimiento
  from cuotas_agosto cu
  where cu.installmentstate='PAID' and cu.dias_vencimiento_a_pago=1
    and cu.id_loan not in (select id_loan from entradas_reales_agosto)
)
, fantasma_con_saldo as (
  select f.id_loan, fo.saldo
  from fantasma_agosto f
  join fotos fo on fo.id_loan = f.id_loan
   and fo.fechaproceso = replace(cast(f.fechavencimiento as varchar),'-','')
)
select round(sum(saldo),2) as real_fantasma_saldo, count(*) as creditos
from fantasma_con_saldo
;

-- ---------------------------------------------------------------------
-- K4. VOLUMEN -- tasa de entrada real (dayslate 0->1) vs P_NO_PAGA_DIA0
-- modelado (13.38%). "elegibles" = creditos con cuota VENCIENDO 1-20 ago
-- (no 2-21 -- el vencimiento es 1 dia ANTES de la fecha en que dayslate
-- puede mostrar la entrada), excluyendo stock; "entradas_reales" = dayslate
-- 0->1 observado 2-21 ago -- mismo desfase de 1 dia que el resto del
-- modelo (bug 12, "arrancando el dia 2"). Resultado: 35,783 elegibles,
-- 5,196 entradas reales, 14.52% (vs 13.38% modelado, +1.14pp / +8.5%
-- relativo).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw_mambu as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.dayslate
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260701' and '20260821'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw_mambu
)
, fotos as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  , lag(coalesce(d.dayslate,0)) over (partition by d.id_loan order by d.fechaproceso) as mora_ant
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_julio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_agosto_ids as (
  select id_loan from cierre_julio where rn=1 and mora between 1 and 30 and saldo>0
)
, elegibles as (
  select distinct c.id_ihfintech_loan as id_loan
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2026-08-01')
    and c.fechavencimiento <= date('2026-08-20')
    and c.id_ihfintech_loan not in (select id_loan from stock_agosto_ids)
)
, entradas_reales as (
  select distinct id_loan
  from fotos
  where mora_ant = 0 and mora = 1
    and fechaproceso between '20260802' and '20260821'
    and id_loan not in (select id_loan from stock_agosto_ids)
)
select
  (select count(*) from elegibles) as elegibles,
  (select count(*) from entradas_reales) as entradas_reales,
  round(100.0*(select count(*) from entradas_reales)/(select count(*) from elegibles),2) as pct_entrada_real
;

-- ---------------------------------------------------------------------
-- K5. EFECTIVIDAD -- tasa de activacion grupo_control (NO gestionado)
-- vs gestionado, mismo corte (21-ago), separado stock/nuevos. Join via
-- aux02 (bug 15) contra dts_asignaciones_gestiones_cobranza, fecha_base
-- 1-21 ago. Resultado clave (ver .md para detalle e interpretacion):
--   nuevos: gestionado 69.28% (3552/5127) vs control 94.0% (47/50, n chico)
--   stock:  gestionado 65.13% (1550/2380) vs control 64.77% (171/264)
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw_mambu as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo, a.dayslate
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260725' and '20260821'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw_mambu
)
, fotos as (
  select
    d.id_loan, d.fechaproceso, d.saldo
  , coalesce(d.dayslate,0) as mora
  , lag(coalesce(d.dayslate,0)) over (partition by d.id_loan order by d.fechaproceso) as mora_ant
  , lag(d.saldo) over (partition by d.id_loan order by d.fechaproceso) as saldo_ant
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_julio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, dia1_agosto as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260801'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial from cierre_julio where rn=1 and mora between 1 and 30 and saldo>0
)
, dia1_entrantes as (
  select id_loan, saldo as saldo_inicial from dia1_agosto where rn=1 and mora=1 and saldo>0
)
, stock_agosto as (
  select id_loan, saldo_inicial from stock_previo
  union all
  select id_loan, saldo_inicial from dia1_entrantes
)
, entradas_nuevos as (
  select f.id_loan, f.saldo as saldo_inicial, f.fechaproceso as fecha_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260802' and '20260821'
    and f.id_loan not in (select id_loan from stock_agosto)
)
, poblacion as (
  select id_loan, saldo_inicial, 'stock' as segmento, cast(null as varchar) as fecha_entrada from stock_agosto
  union all
  select id_loan, saldo_inicial, 'nuevos' as segmento, fecha_entrada from entradas_nuevos
)
, activacion as (
  select p.id_loan, p.segmento, p.saldo_inicial,
    max(coalesce(case when f.saldo_ant > f.saldo then 1 else 0 end,0)) as activado
  from poblacion p
  left join fotos f on f.id_loan = p.id_loan
    and f.fechaproceso between '20260801' and '20260821'
    and (p.fecha_entrada is null or f.fechaproceso > p.fecha_entrada)
  group by 1,2,3
)
, asig_flag as (
  select aux02 as id_loan,
    max(case when grupo_control = 'CONTROL' then 1 else 0 end) as es_control
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-08-01' and '2026-08-21'
    and aux02 is not null
  group by 1
)
select
  case when af.id_loan is null then 'sin_match_asignacion'
       when af.es_control = 1 then 'grupo_control'
       else 'gestionado' end as grupo,
  a.segmento,
  count(*) as creditos, round(sum(a.saldo_inicial),2) as saldo_total,
  sum(a.activado) as creditos_activados, round(sum(a.saldo_inicial*a.activado),2) as saldo_activado,
  round(100.0*sum(a.activado)/count(*),2) as pct_creditos_activados
from activacion a
left join asig_flag af on af.id_loan = a.id_loan
group by 1,2
order by 2,1
;

-- ---------------------------------------------------------------------
-- K6. Chequeo de timing/right-censoring en el hueco fantasma real<proyectado
-- (mismo diagnostico que reconciliacion_agosto.sql Q4, 2026-08-21):
-- cuotas venciendo cerca del corte (fecha_pago esperada 16-19 ago, dentro
-- de los ultimos ~4 dias antes del corte 21-ago) tienen tasa PAID mas baja
-- (84.9%, 7250/8539) que el resto del periodo (90.0%, 25288/28085) --
-- confirma que parte del hueco es timing, no un hueco real nuevo.
-- ---------------------------------------------------------------------
with cuotas as (
  select
    c.id_ihfintech_loan as id_loan
  , date_add('day',1,c.fechavencimiento) as fecha_pago_esperada
  , c.installmentstate
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and date_add('day',1,c.fechavencimiento) >= date('2026-08-01')
    and date_add('day',1,c.fechavencimiento) <= date('2026-08-21')
)
select
  case when fecha_pago_esperada >= date('2026-08-18') then 'ultimos_4_dias_venc_15-18ago' else 'resto_del_periodo' end as ventana,
  installmentstate,
  count(*) as cuotas
from cuotas
group by 1,2
order by 1,2
;

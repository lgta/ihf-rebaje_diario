-- =====================================================================
-- BACKTEST DEL ENFOQUE ALFA ("CAPITAL ASEGURADO") SOBRE ABRIL 2026
-- Cuarto mes cerrado del backtest (tarea 9 de PENDIENTES.md -- extender el
-- backtest mas alla de 3 meses). Mismo patron EXACTO que
-- enfoque_capital_asegurado_backtest_mayo.sql, anclado marzo->abril en vez
-- de abril->mayo.
--
-- A DIFERENCIA de ese archivo (y del de julio), este SI incluye la query
-- del calendario de fantasma frontier-adjusted (BT-ASEG-ABR-CALFANT) --
-- en mayo/julio esa query se corrio solo en el scratchpad de la sesion y
-- nunca se copio al repo (ver bug 17, BUGS.md, "Pendiente de copiar al
-- repo" en ESTADO.md) -- corregido aca para que el patron completo quede
-- reproducible sin depender del scratchpad.
--
-- Usa las curvas y tasas de PRODUCCION actuales sin cambios
-- (P_NO_PAGA_DIA0=13.38%, P_FANTASMA=8.5524%, curva_asegurado_stock_seg.csv
-- / curva_asegurado_nuevos_seg.csv, calibradas sobre periodo_meta
-- '202504'-'202606' -- eso INCLUYE abril 2026, no es estrictamente fuera de
-- muestra para este mes especifico, mismo caveat que mayo/junio/julio, ver
-- tarea 10 de PENDIENTES.md).
-- =====================================================================

-- ---------------------------------------------------------------------
-- BT-ASEG-ABR-CAL. Calendario real de vencimientos de abril (saldo en
-- riesgo por avance_band, para "nuevos"), excluyendo el stock de abril
-- (cierre de marzo). Mismo patron que BT-ASEG-MAY-CAL.
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas group by 1
)
, fotos_mar as (
select
  a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, a.balances_principalbalance as saldo
, coalesce(a.dayslate, 0) as mora
, row_number() over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso desc) as rn
from dts_mambu_loans_hist a
join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and coalesce(lc.last_in_chain,1) = 1
  and a.fechaproceso >= '20260301' and a.fechaproceso <= '20260331'
)
, stock_abril_ids as (
select id_loan from fotos_mar where rn=1 and mora between 1 and 30 and saldo > 0
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
  and c.fechavencimiento >= date('2026-04-01')
  and c.fechavencimiento <= date('2026-04-30')
  and b.amountfinanced > 0
  and c.id_ihfintech_loan not in (select id_loan from stock_abril_ids)
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- BT-ASEG-ABR-CALFANT. Calendario TOTAL "en riesgo" para fantasma,
-- frontier-adjusted por fecha_pago (fechavencimiento+1) en vez de
-- fechavencimiento directo -- incluye la cuota vencida 31-mar (fecha_pago
-- 1-abr), excluye la vencida 30-abr (fecha_pago 1-may, pertenece al
-- backtest de mayo, ya capturada ahi). Mismo patron que
-- investigacion_capa_fantasma.sql Q3 (CTEs cuotas_julio+calendario_saldo),
-- sin el filtro de installmentstate (esto es el denominador/riesgo total,
-- no el activado real -- ver BT-ASEG-ABR-3 para el activado real). Misma
-- poblacion excluida (stock + entradas reales) que usa BT-ASEG-ABR-3, para
-- que numerador y denominador de P_FANTASMA sean consistentes.
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
  where a.fechaproceso between '20260301' and '20260430'
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
, fotos_con_lag as (
  select id_loan, fechaproceso, saldo, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
  where fechaproceso between '20260401' and '20260430'
)
, cierre_marzo as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260331'
)
, stock_abril_ids as (
  select id_loan from cierre_marzo where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_reales_abril as (
  select distinct id_loan
  from fotos_con_lag
  where mora_ant = 0 and mora = 1 and fechaproceso between '20260402' and '20260430'
    and id_loan not in (select id_loan from stock_abril_ids)
)
, cuotas_abril as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and date_add('day', 1, c.fechavencimiento) >= date('2026-04-01')
    and date_add('day', 1, c.fechavencimiento) <= date('2026-04-30')
    and c.id_ihfintech_loan not in (select id_loan from stock_abril_ids)
    and c.id_ihfintech_loan not in (select id_loan from entradas_reales_abril)
)
select
  cu.fechavencimiento
, round(sum(fo.saldo),2) as saldo_en_riesgo
, count(*) as cuotas
from cuotas_abril cu
join fotos fo on fo.id_loan = cu.id_loan
 and fo.fechaproceso = replace(cast(cu.fechavencimiento as varchar),'-','')
group by cu.fechavencimiento
order by cu.fechavencimiento
;

-- ---------------------------------------------------------------------
-- BT-ASEG-ABR-0. STOCK DE ABRIL (poblacion) = stock de siempre (cierre de
-- marzo) UNION los entrantes del dia 1 de abril. Por tramo x avance.
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
  where a.fechaproceso >= '20260325' and a.fechaproceso <= '20260410'
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
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_marzo as (
  select *, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260331'
)
, dia1_abril as (
  select *, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260401'
)
, stock_previo as (
  select id_loan, saldo,
    case when mora between 1 and 8 then 'a. 1-8'
         when mora between 9 and 15 then 'b. 9-15'
         else 'c. 16-30' end as tramo,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from cierre_marzo
  where rn = 1 and mora between 1 and 30 and saldo > 0 and amountfinanced > 0
)
, dia1_entrantes as (
  select id_loan, saldo,
    'a. 1-8' as tramo,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from dia1_abril
  where rn = 1 and mora = 1 and saldo > 0 and amountfinanced > 0
)
, stock_abril as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
select tramo, avance_band, count(*) as creditos, round(sum(saldo),2) as saldo_total
from stock_abril
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- BT-ASEG-ABR-1. STOCK -- capital real activado por dia, abril 2026.
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
  where a.fechaproceso >= '20260301' and a.fechaproceso <= '20260430'
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
  , lag(d.saldo) over (partition by d.id_loan order by d.fechaproceso) as saldo_ant
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_marzo as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260331'
)
, dia1_abril as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260401'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial from cierre_marzo where rn = 1 and mora between 1 and 30 and saldo > 0
)
, dia1_entrantes as (
  select id_loan, saldo as saldo_inicial from dia1_abril where rn = 1 and mora = 1 and saldo > 0
)
, stock_abril as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
, pagos_abril as (
  select s.id_loan, s.saldo_inicial, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock_abril s
  join fotos f on f.id_loan = s.id_loan
  where f.fechaproceso between '20260401' and '20260430'
)
, primer_pago as (
  select id_loan, saldo_inicial, min(fechaproceso) as fecha_primer_pago
  from pagos_abril
  where pago_flag = 1
  group by 1,2
)
select fecha_primer_pago as fechaproceso, round(sum(saldo_inicial),2) as saldo_activado_dia
from primer_pago
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- BT-ASEG-ABR-2. NUEVOS -- capital real activado por dia, abril 2026.
-- Poblacion: dayslate 0->1 durante abril, EXCLUYENDO el dia 1 (bug 12).
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
  where a.fechaproceso >= '20260401' and a.fechaproceso <= '20260430'
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
  , lag(coalesce(d.dayslate,0)) over (
      partition by d.id_loan order by d.fechaproceso) as mora_ant
  , lag(d.saldo) over (
      partition by d.id_loan order by d.fechaproceso) as saldo_ant
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, dia1_abril as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos
)
, stock_abril_ids as (
  select id_loan from dia1_abril where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_abril as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260402' and '20260430'
    and f.id_loan not in (select id_loan from stock_abril_ids)
)
, pagos as (
  select e.id_loan, e.saldo_entrada, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_abril e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada and f.fechaproceso <= '20260430'
)
, primer_pago as (
  select id_loan, saldo_entrada, min(fechaproceso) as fecha_primer_pago
  from pagos
  where pago_flag = 1
  group by 1,2
)
select fecha_primer_pago as fechaproceso, round(sum(saldo_entrada),2) as saldo_activado_dia
from primer_pago
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- BT-ASEG-ABR-3. CAPA FANTASMA -- real por dia, abril 2026. Cuotas
-- vencidas entre 31-mar y 30-abr pagadas exactamente 1 dia tarde,
-- fecha_pago dentro de abril (fix de frontera de mes, bug 14).
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
  where a.fechaproceso between '20260301' and '20260430'
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
, fotos_con_lag as (
  select id_loan, fechaproceso, saldo, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
  where fechaproceso between '20260401' and '20260430'
)
, dia1_abril as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos
  where fechaproceso between '20260401' and '20260430'
)
, stock_abril_ids as (
  select id_loan from dia1_abril where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_reales_abril as (
  select distinct id_loan
  from fotos_con_lag
  where mora_ant = 0 and mora = 1
)
, cuotas_1dia_tarde_abril as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , date_add('day', 1, c.fechavencimiento) as fecha_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and date_add('day', 1, c.fechavencimiento) >= date('2026-04-01')
    and date_add('day', 1, c.fechavencimiento) <= date('2026-04-30')
    and c.installmentstate = 'PAID'
    and c.dias_vencimiento_a_pago = 1
)
, fantasma_abril as (
  select cu.id_loan, cu.fechavencimiento, cu.fecha_pago
  from cuotas_1dia_tarde_abril cu
  where cu.id_loan not in (select id_loan from stock_abril_ids)
    and cu.id_loan not in (select id_loan from entradas_reales_abril)
)
, con_saldo as (
  select f.id_loan, f.fecha_pago, fo.saldo as saldo_al_vencimiento
  from fantasma_abril f
  join fotos fo on fo.id_loan = f.id_loan
   and fo.fechaproceso = replace(cast(f.fechavencimiento as varchar),'-','')
)
select date_format(fecha_pago,'%Y%m%d') as fechaproceso
, round(sum(saldo_al_vencimiento),2) as saldo_activado_dia
, count(*) as creditos
from con_saldo
group by 1
order by 1
;

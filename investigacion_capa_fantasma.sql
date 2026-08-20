-- =====================================================================
-- CAPA "FANTASMA" -- opcion (a) completa (retro + prospectivo) para el
-- punto ciego de dayslate (bug 9/14). Ejecutado 2026-08-20. Ver
-- reconciliacion_vw_seguimiento_temprana.md paso 2/3 y BUGS.md bug 14.
--
-- Idea: un credito que paga una cuota EXACTAMENTE 1 dia tarde nunca hace
-- que dayslate muestre mora (bug 9) -- la foto nocturna ya ve el pago. Esto
-- afecta tanto la curva de maduracion de "nuevos" (retrospectivo, no tiene
-- bucket dia-0) como la tasa P(no paga a tiempo)=13.38% (prospectivo, mide
-- transiciones dayslate 0->1, tambien ciega a estos casos). Se agrega una
-- CAPA INDEPENDIENTE (no se toca 13.38% ni la curva existente) que se activa
-- 100% el dia siguiente al vencimiento -- por definicion, si detectamos el
-- evento es porque ya se pago.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. TASA "P(entra en mora fantasma)" -- mismo denominador que 3H de
-- fase3_backtest.sql (calendario_mes: creditos elegibles con cuota
-- venciendo ese mes, excluyendo stock ya en mora), fuera de muestra
-- (ago-2025 a may-2026, sin junio, igual que P_NO_PAGA_DIA0=13.38%).
-- Numerador: al menos 1 cuota vencida ese mes pagada EXACTAMENTE 1 dia
-- tarde, Y el credito no esta ya en "entradas_reales" (dayslate) ese mes
-- (mutuamente excluyente, para no duplicar en la proyeccion combinada).
-- Resultado: 29,845 entradas fantasma / 353,054 elegibles = 8.4534%
-- (vs. 47,459/353,054 = 13.44% de entradas reales -- reproduce el 13.38%
-- oficial casi exacto, valida la reconstruccion). Por mes: 7.35%-9.53%.
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
    substr(cast(c.fechavencimiento as varchar),1,7) as periodo_venc
  , c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , c.installmentstate
  , c.dias_vencimiento_a_pago
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
, entradas_fantasma as (
  select distinct replace(cal.periodo_venc,'-','') as periodo, cal.id_loan
  from calendario cal
  where cal.installmentstate = 'PAID' and cal.dias_vencimiento_a_pago = 1
    and not exists (
      select 1 from entradas_reales er
      where er.periodo = replace(cal.periodo_venc,'-','') and er.id_loan = cal.id_loan
    )
)
select
  cm.periodo
, count(distinct cm.id_loan) as elegibles
, count(distinct er.id_loan) as entradas_reales
, count(distinct ef.id_loan) as entradas_fantasma
, round(100.0*count(distinct er.id_loan)/count(distinct cm.id_loan), 2) as pct_entrada_real
, round(100.0*count(distinct ef.id_loan)/count(distinct cm.id_loan), 2) as pct_entrada_fantasma
from calendario_mes cm
left join entradas_reales er on er.periodo = cm.periodo and er.id_loan = cm.id_loan
left join entradas_fantasma ef on ef.periodo = cm.periodo and ef.id_loan = cm.id_loan
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- Q2. BACKTEST JUNIO 2026 -- capa fantasma REAL por dia (para sumar a
-- datos_backtest_junio/bt_real_aseg_nuevos.csv sin modificarlo). Creditos
-- con cuota vencida en junio pagada exactamente 1 dia tarde, dayslate
-- nunca la vio, no en stock ni en entradas reales de BT-ASEG-2. Saldo =
-- balance del credito el dia de vencimiento (antes del pago), atribuido
-- al dia de pago (vencimiento+1).
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
  where a.fechaproceso between '20260501' and '20260630'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso order by lastmodifieddate desc, id desc) as rn_dedup
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
  where fechaproceso between '20260601' and '20260630'
)
, dia1_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos
  where fechaproceso between '20260601' and '20260630'
)
, stock_junio_ids as (
  select id_loan from dia1_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_reales_junio as (
  select distinct id_loan
  from fotos_con_lag
  where mora_ant = 0 and mora = 1
)
, cuotas_1dia_tarde_junio as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , date_add('day', 1, c.fechavencimiento) as fecha_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2026-06-01') and c.fechavencimiento <= date('2026-06-30')
    and c.installmentstate = 'PAID'
    and c.dias_vencimiento_a_pago = 1
)
, fantasma_junio as (
  select cu.id_loan, cu.fechavencimiento, cu.fecha_pago
  from cuotas_1dia_tarde_junio cu
  where cu.id_loan not in (select id_loan from stock_junio_ids)
    and cu.id_loan not in (select id_loan from entradas_reales_junio)
)
, con_saldo as (
  select f.id_loan, f.fecha_pago, fo.saldo as saldo_al_vencimiento
  from fantasma_junio f
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

-- ---------------------------------------------------------------------
-- Q3. VALIDACION JULIO 2026 (segundo mes cerrado, independiente).
-- (a) calendario total "en riesgo" excluyendo stock, vencimientos
-- 1-jul a 30-jul (30 se excluye por consistencia: su "dia siguiente"
-- cae 1-ago, fuera de la ventana de julio, igual que se excluyo el
-- 30-jun en junio); (b) real fantasma con el mismo criterio que Q2.
-- Resultado: calendario S/73,659,266 (53,074 eventos); real fantasma
-- S/5,742,741 (3,774 creditos).
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
      partition by id_loan, fechaproceso order by lastmodifieddate desc, id desc) as rn_dedup
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
  where fechaproceso between '20260701' and '20260731'
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio_ids as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_reales_julio as (
  select distinct id_loan
  from fotos_con_lag
  where mora_ant = 0 and mora = 1 and fechaproceso between '20260702' and '20260731'
    and id_loan not in (select id_loan from stock_julio_ids)
)
, cuotas_julio as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , c.installmentstate
  , c.dias_vencimiento_a_pago
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2026-07-01') and c.fechavencimiento <= date('2026-07-30')
    and c.id_ihfintech_loan not in (select id_loan from stock_julio_ids)
)
, calendario_saldo as (
  select cu.id_loan, cu.fechavencimiento, fo.saldo
  from cuotas_julio cu
  join fotos fo on fo.id_loan = cu.id_loan
   and fo.fechaproceso = replace(cast(cu.fechavencimiento as varchar),'-','')
  group by cu.id_loan, cu.fechavencimiento, fo.saldo
)
, fantasma_julio as (
  select cu.id_loan, cu.fechavencimiento
  from cuotas_julio cu
  where cu.installmentstate = 'PAID' and cu.dias_vencimiento_a_pago = 1
    and cu.id_loan not in (select id_loan from entradas_reales_julio)
)
, fantasma_con_saldo as (
  select f.id_loan, fo.saldo
  from fantasma_julio f
  join fotos fo on fo.id_loan = f.id_loan
   and fo.fechaproceso = replace(cast(f.fechavencimiento as varchar),'-','')
)
select 'calendario_total_saldo_riesgo' as chk, round(sum(saldo),2) as valor, count(*) as n
from calendario_saldo
union all
select 'real_fantasma_total_saldo', round(sum(saldo),2), count(*)
from fantasma_con_saldo
;

-- ---------------------------------------------------------------------
-- Q4. RECOMPUTO DEL REAL DE JULIO (stock+nuevos, sin fantasma) -- mismo
-- patron que cierre_julio.sql J1/J2, recorrido esta sesion para validar
-- de forma independiente. Resultado: stock S/3,137,199 (vs. J1 original,
-- documentado en cierre_julio.sql/SEGUIMIENTO.md), nuevos S/7,633,719.
-- OJO: esto NO calza con el signo del error reportado en SEGUIMIENTO.md
-- para julio (dice "+4.7%/+1.0%/+6.3%", pero recalculando con estos
-- numeros el error sale NEGATIVO, -4.3%/-1.0%/-5.7% -- mismo signo que
-- junio, no "invertido" como dice la nota actual). Ver reconciliacion_
-- vw_seguimiento_temprana.md, paso 3, para el detalle -- no se corrigio
-- SEGUIMIENTO.md todavia, queda para que el usuario lo confirme.
-- ---------------------------------------------------------------------
-- (J1/J2 de cierre_julio.sql, sin cambios -- ver ese archivo)

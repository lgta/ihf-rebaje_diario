-- =====================================================================
-- ENFOQUE ALFA - "CAPITAL ASEGURADO"
-- v2: recalibrado 2026-07-14 con la definicion corregida de antiguos/
-- nuevos (ver mas abajo y BUGS.md bug 12). Version original ejecutada
-- 2026-07-10. Ver enfoque_capital_asegurado.md para la explicacion
-- completa.
--
-- Concepto: no mide cuantos soles se recuperan (eso lo hace la meta
-- oficial de rebaje/recupero) -- mide cuanto del capital ASIGNADO
-- pertenece a creditos que muestran AL MENOS 1 dia de pago en el mes,
-- ponderado por el saldo COMPLETO del credito (no por lo que pago).
-- Ejemplo del usuario: credito A saldo S/12,000 paga S/50 -> aporta
-- S/12,000 completos al capital asegurado (no S/50). Credito B saldo
-- S/8,000 no paga nada -> aporta S/0.
--
-- DEFINICION CORREGIDA DE ANTIGUOS/NUEVOS (bug 12, solo aplica a este
-- enfoque -- fase1_stock.sql/fase2_nuevos.sql del recupero oficial NO
-- se tocan): un credito con dayslate 0->1 exactamente el DIA 1 del mes
-- matematicamente solo puede venir de una cuota que vencio el ULTIMO
-- DIA DEL MES ANTERIOR (vencimiento = dia - dayslate) -- es un antiguo
-- mal clasificado como nuevo, no un caso raro (es TODA la cohorte de
-- entradas de dia 1, todos los meses). Fix: anclar "antiguos" a la foto
-- del DIA 1 del mes meta (no al cierre del mes anterior), y que
-- "nuevos" arranque a detectar entradas desde el dia 2. Asi "nuevo" =
-- vence DENTRO del mes y se atrasa, "antiguo" = ya inicia el mes con
-- mora, sin excepciones.
--
-- Mismas CTEs base y mismos filtros (status, flg_last_loan_in_chain)
-- que fase1_stock.sql / fase2_nuevos.sql -- ver FUENTES_DATOS.md.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. STOCK - curva de capital asegurado, tramo x avance x dia.
-- Resultado en datos_capital_asegurado/curva_asegurado_stock_seg.csv.
-- Dia 31 (final) por segmento, ver enfoque_capital_asegurado.md.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    substr(a.fechaproceso, 1, 6)                       as periodo
  , a.fechaproceso
  , cast(substr(a.fechaproceso, 7, 2) as int)          as dia
  , a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
  , a.balances_principalbalance                        as saldo
  , coalesce(a.dayslate, 0)                            as mora
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
  select *, row_number() over (partition by id_loan, periodo order by fechaproceso desc) as rn
  from fotos
)
, stock_previo as (
  -- stock "de siempre": mora 1-30 al cierre del mes anterior (sin cambios).
  select
    date_format(date_add('month', 1, date_parse(periodo, '%Y%m')), '%Y%m') as periodo_meta
  , id_loan
  , saldo as saldo_inicial
  , case when mora between 1 and 8  then 'a. 1-8'
         when mora between 9 and 15 then 'b. 9-15'
         else                            'c. 16-30' end as tramo
  , case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from cierre_mes
  where rn = 1 and mora between 1 and 30 and saldo > 0 and amountfinanced > 0
)
, primer_dia_mes as (
  select *, row_number() over (partition by id_loan, periodo order by fechaproceso asc) as rn
  from fotos
)
, dia1_entrantes as (
  -- bug 12: creditos con mora=1 el DIA 1 del mes (mora=0 el dia anterior, cierre
  -- del mes previo) -- su cuota vencio el ultimo dia del mes anterior, son
  -- antiguos mal clasificados como nuevos. NO se usa el mismo truco de "anclar
  -- TODA la poblacion al dia 1" (eso excluye por accidente a cualquier stock
  -- que pague justo ese dia, la foto ya reflejaria el pago -> colapsa la curva
  -- de dia 1 a ~0%, verificado). Se suma esta poblacion puntual al stock de
  -- siempre, sin tocar el resto.
  select
    periodo as periodo_meta
  , id_loan
  , saldo as saldo_inicial
  , 'a. 1-8' as tramo  -- mora=1 siempre cae en el tramo mas bajo
  , case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from primer_dia_mes
  where rn = 1 and mora = 1 and saldo > 0 and amountfinanced > 0
)
, stock as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
, rebajes as (
  select s.periodo_meta, s.tramo, s.avance_band, s.id_loan, s.saldo_inicial, f.dia,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
  where s.periodo_meta between '202504' and '202606'
)
, primer_pago as (
  select periodo_meta, tramo, avance_band, id_loan, saldo_inicial, min(dia) as dia_primer_pago
  from rebajes
  where pago_flag = 1
  group by 1,2,3,4,5
)
, saldo_total as (
  select tramo, avance_band, sum(saldo_inicial) as saldo_total, count(*) as creditos_total
  from stock
  where periodo_meta between '202504' and '202606'
  group by 1,2
)
, activado_por_dia as (
  select tramo, avance_band, dia_primer_pago as dia, sum(saldo_inicial) as saldo_activado_dia
  from primer_pago
  group by 1,2,3
)
select
  a.tramo, a.avance_band, a.dia
, round(sum(a.saldo_activado_dia) over (partition by a.tramo, a.avance_band order by a.dia) / t.saldo_total * 100, 3) as pct_capital_asegurado_acum
, t.saldo_total, t.creditos_total
from activado_por_dia a
join saldo_total t on t.tramo = a.tramo and t.avance_band = a.avance_band
order by 1, 2, 3
;

-- ---------------------------------------------------------------------
-- Q2. NUEVOS - curva de capital asegurado, avance x dias desde entrada.
-- Entrada = dayslate 0->1, EXCLUYENDO el dia 1 del mes (bug 12: esas
-- entradas vienen de una cuota vencida el ultimo dia del mes anterior,
-- ya capturadas en Q1/stock). Ya NO es la misma definicion que
-- fase2_nuevos.sql (que si cuenta dia 1) -- la tasa P(no paga)=13.38%,
-- calibrada sobre la definicion vieja, deja de ser consistente con esta
-- curva; ver enfoque_capital_asegurado.md para el tratamiento.
-- Resultado en datos_capital_asegurado/curva_asegurado_nuevos_seg.csv.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
  , a.fechaproceso
  , a.balances_principalbalance                        as saldo
  , coalesce(a.dayslate,0)                              as mora
  , lag(coalesce(a.dayslate,0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as mora_ant
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as saldo_ant
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as nro_foto
  , b.amountfinanced
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b
    on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc
    on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso >= '20250301'
    and coalesce(lc.last_in_chain, 1) = 1
)
, entradas as (
  select id_loan, fechaproceso as fecha_entrada,
    date_parse(fechaproceso, '%Y%m%d') as fecha_entrada_d,
    saldo as saldo_entrada, amountfinanced,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from fotos
  where nro_foto > 1 and mora_ant = 0 and mora = 1
    and fechaproceso between '20250301' and '20260531'
    and amountfinanced > 0
    and cast(substr(fechaproceso, 7, 2) as int) <> 1  -- bug 12: dia 1 = cuota vencio el mes anterior, es stock
)
, pagos as (
  select e.id_loan, e.avance_band, e.saldo_entrada,
    date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, primer_pago as (
  select id_loan, avance_band, saldo_entrada, min(dia_desde_entrada) as dia_primer_pago
  from pagos
  where pago_flag = 1
  group by 1,2,3
)
, base_total as (
  select avance_band, sum(saldo_entrada) as saldo_entrada_total, count(*) as entradas
  from entradas group by 1
)
, activado_por_dia as (
  select avance_band, dia_primer_pago as dia, sum(saldo_entrada) as saldo_activado_dia
  from primer_pago
  group by 1,2
)
select
  a.avance_band, a.dia
, round(sum(a.saldo_activado_dia) over (partition by a.avance_band order by a.dia) / b.saldo_entrada_total * 100, 3) as pct_capital_asegurado_acum
, b.saldo_entrada_total, b.entradas
from activado_por_dia a
join base_total b on b.avance_band = a.avance_band
order by 1, 2
;

-- ---------------------------------------------------------------------
-- Q3. CAPA "FANTASMA" -- tasa P_FANTASMA, adoptada en produccion 2026-08-20
-- (bug 9/14: punto ciego de dayslate, ver reconciliacion_vw_seguimiento_
-- temprana.md paso 2/3 y BUGS.md bug 14). Un credito que paga una cuota
-- EXACTAMENTE 1 dia tarde nunca hace que dayslate muestre mora -- no cuenta
-- ni en Q2 (curva de nuevos, no tiene bucket dia-0) ni en P_NO_PAGA_DIA0=
-- 13.38% (tambien mide transiciones dayslate). Capa INDEPENDIENTE, no
-- mezclada con 13.38% ni con la curva de Q2 (evita bug 10): se activa 100%
-- el dia siguiente al vencimiento, sin curva propia -- por definicion, si
-- se detecta el evento es porque ya se pago. Solo Enfoque alfa (alcance
-- decidido con el usuario 2026-08-20) -- NO se aplica a fase1_stock.sql/
-- fase2_nuevos.sql/fase3_backtest.sql del recupero oficial.
--
-- Mismo denominador que 3H de fase3_backtest.sql (calendario_mes: creditos
-- elegibles con cuota venciendo ese mes, excluyendo stock ya en mora),
-- fuera de muestra (ago-2025 a may-2026, sin junio). Numerador: al menos 1
-- cuota vencida ese mes pagada EXACTAMENTE 1 dia tarde, Y el credito no
-- esta ya en "entradas_reales" (dayslate) ese mes (mutuamente excluyente,
-- para no duplicar en la proyeccion combinada).
--
-- Resultado (2026-08-20): 29,845 entradas fantasma / 353,054 elegibles =
-- P_FANTASMA = 8.4534% (por mes: 7.35%-9.53% -- casi tan grande como el
-- propio 13.38%, no es un ajuste marginal). Validado con backtest en 2
-- meses cerrados (junio: -4.4%->+0.7%; julio: -4.31%->+0.12%), ver
-- backtest_capital_asegurado_junio.py e investigacion_capa_fantasma.sql.
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
, count(distinct ef.id_loan) as entradas_fantasma
, round(100.0*count(distinct ef.id_loan)/count(distinct cm.id_loan), 2) as pct_entrada_fantasma
from calendario_mes cm
left join entradas_fantasma ef on ef.periodo = cm.periodo and ef.id_loan = cm.id_loan
group by 1
order by 1
;

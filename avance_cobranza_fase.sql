-- =====================================================================
-- AVANCE DE JULIO POR FASE DE COBRANZA (Temprana/Especializada/Recovery)
-- Ejecutado 2026-07-13. Ver avance_cobranza_fase.md para la explicacion
-- completa e interpretacion de resultados.
--
-- Fuente: dts_asignaciones_gestiones_cobranza -- asignacion REAL dia a dia
-- del negocio (no la poblacion inferida via dayslate que usa el resto
-- del proyecto). Grano: (dni_ce, producto) por fecha_base.
--
-- CAMBIO 2026-08-18: esta query originalmente usaba dts_asignaciones_
-- cobranza (sin "gestiones"), que quedo congelada el 2026-07-10 -- ver
-- bug 13 en BUGS.md. Se repunto a dts_asignaciones_gestiones_cobranza
-- (mismo grano, tabla viva). OJO: fecha_base ahi es varchar, no date --
-- comparar con literal string ('2026-07-02'), no date('2026-07-02').
--
-- CAMBIO 2026-08-21 (continuacion) -- 3 fixes aplicados en esta re-corrida:
-- (1) bug 15 (BUGS.md): la tabla SI tiene id_ihfintech_loan directo, columna
--     "aux02" (99.97% de match, sin nombre descriptivo) -- reemplaza el
--     crosswalk dni+producto contra dts_cobranza_creditos_cuotas (CTEs
--     "cuotas_activos"/"asignados_dia1" eliminadas, "cohorte" ahora es un
--     select directo con aux02). Cohorte crece de 8,303 a 8,614 creditos
--     (+3.7%), concentrado en TEMPRANA (+249, antes perdidos por el filtro
--     status='ACTIVE' del crosswalk viejo -- mismo mecanismo que bug 13/
--     "Sin asignar" de la reconciliacion TEMPRANA).
-- (2) bug 12 (antiguo/nuevo, dia 1 del mes): un credito con mora=1 el DIA 1
--     de julio (mora=0 el 30-jun) viene de una cuota vencida el ULTIMO DIA
--     DE JUNIO -- es "antiguo"/stock, no "nuevo" (mismo patron que
--     enfoque_capital_asegurado.sql, tramo fijo 'a. 1-8' para estos
--     entrantes). Nunca se habia aplicado a este archivo -- "nuevo" baja de
--     1,397 a 628 creditos (-55%, la mayoria del bucket viejo eran entrantes
--     de dia 1 mal clasificados), "stock" sube de 1,414 a 2,473 (+75%). El
--     impacto es proporcionalmente mucho mayor que en la calibracion de 14
--     meses porque esta cohorte es una ventana de solo 11 dias (dia1=2-jul
--     a dia11=12-jul) -- un solo dia (el 1-jul) pesa mucho mas aqui.
-- (3) bug 11 (dedup, BUGS.md): este archivo nunca tuvo el dedup de filas
--     duplicadas (id_loan, fechaproceso) de dts_mambu_loans_hist -- CLAUDE.md
--     lo exige para cualquier row_number()/lag() nuevo sobre esa tabla.
--     Agregado (regla saldo<>0 antes de lastmodifieddate).
--
-- OJO: la corrida original (12-jul) uso 2-jul como "dia 1" de julio
-- porque dts_asignaciones_cobranza no tenia el 1-jul (decision
-- confirmada con el usuario 2026-07-13, ver avance_cobranza_fase.md).
-- dts_asignaciones_gestiones_cobranza SI tiene 1-jul -- si se re-corre
-- este analisis desde cero, evaluar si conviene usar 1-jul en vez de
-- 2-jul (no cambiado aca para no alterar la corrida historica sin
-- pedido explicito -- esta pasada solo corrige bugs 11/12/15, no cambia
-- el ancla de la cohorte).
--
-- "Rebaje" en este cuadro = capital ASEGURADO (enfoque alfa: saldo
-- COMPLETO del credito si mostro >=1 dia de pago, no soles cobrados) --
-- no el recupero oficial. Confirmado con el usuario porque los % de
-- referencia del formato pedido (96.9%/85.6%) son del orden de magnitud
-- de capital asegurado, no de recupero (~12-20%/mes).
-- =====================================================================

-- ---------------------------------------------------------------------
-- EXTRACCION -- una fila por credito de la cohorte del 2-jul, con:
-- fase de cobranza (fase_estrategia), saldo del dia de asignacion,
-- avance de amortizacion, tramo a cierre de junio (si el credito ya
-- estaba en mora 1-30 entonces = "stock" oficial del proyecto), fecha
-- de entrada a mora en julio (si es "nuevo"), y fecha del primer pago
-- observado entre el 2-jul y el 12-jul (ultima fecha con datos en
-- dts_mambu_loans_hist a la fecha de esta corrida).
-- Resultado usado por avance_cobranza_fase.py (agregacion + curvas).
-- ---------------------------------------------------------------------
with cohorte as (
  -- FIX bug 15: join directo via aux02 (=id_ihfintech_loan), reemplaza el
  -- crosswalk dni+producto contra dts_cobranza_creditos_cuotas.
  select distinct fase_estrategia, subsegmento_fase_estrategia, aux02 as id_ihfintech_loan
  from dts_asignaciones_gestiones_cobranza
  where fecha_base = '2026-07-02' and aux02 is not null
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  , b.amountfinanced
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a._datos_adicionales_loan_accounts_id_ihfintech in (select id_ihfintech_loan from cohorte)
    and a.fechaproceso between '20260601' and '20260712'
)
, dedup as (
  -- FIX bug 11: dedup determinista de filas duplicadas (id_loan, fechaproceso).
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select
    id_loan, fechaproceso, saldo
  , coalesce(dayslate,0) as mora
  , lag(coalesce(dayslate,0)) over (partition by id_loan order by fechaproceso) as mora_ant
  , lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  , amountfinanced
  from dedup
  where rn_dedup = 1
)
, cierre_junio as (
  select id_loan, mora as mora_jun, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, dia1 as (
  select id_loan, saldo as saldo_dia1, mora as mora_dia1, amountfinanced,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from fotos where fechaproceso = '20260702'
)
, entrada_julio as (
  select id_loan, min(fechaproceso) as fecha_entrada
  from fotos
  where mora_ant = 0 and mora = 1 and fechaproceso between '20260701' and '20260712'
  group by 1
)
, pagos as (
  select id_loan, fechaproceso,
    case when saldo_ant > saldo then 1 else 0 end as pago_flag
  from fotos where fechaproceso between '20260702' and '20260712'
)
, primer_pago as (
  select id_loan, min(fechaproceso) as fecha_primer_pago
  from pagos where pago_flag = 1
  group by 1
)
select
  co.fase_estrategia, co.subsegmento_fase_estrategia
, d.id_loan
, d.saldo_dia1, d.avance_band
, cj.mora_jun
, case when coalesce(cj.mora_jun,0) between 1 and 30 then 'stock'
       when coalesce(cj.mora_jun,0) = 0 and e.fecha_entrada = '20260701' then 'stock'  -- FIX bug 12
       when coalesce(cj.mora_jun,0) = 0 then 'nuevo'
       else 'preexistente_31+' end as segmento
, case when cj.mora_jun between 1 and 8 then 'a. 1-8'
       when cj.mora_jun between 9 and 15 then 'b. 9-15'
       when cj.mora_jun between 16 and 30 then 'c. 16-30'
       when coalesce(cj.mora_jun,0) = 0 and e.fecha_entrada = '20260701' then 'a. 1-8'  -- FIX bug 12
       else null end as tramo_jun
, e.fecha_entrada
, pp.fecha_primer_pago
from cohorte co
join dia1 d on d.id_loan = co.id_ihfintech_loan
left join cierre_junio cj on cj.id_loan = co.id_ihfintech_loan and cj.rn = 1
left join entrada_julio e on e.id_loan = co.id_ihfintech_loan
left join primer_pago pp on pp.id_loan = co.id_ihfintech_loan
;

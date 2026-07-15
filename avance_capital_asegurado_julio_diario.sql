-- =====================================================================
-- AVANCE DE JULIO DIA A DIA -- capital asegurado (enfoque alfa), desde la
-- primera asignacion (1-jul, cierre real de junio + primeras entradas en
-- mora) hasta la fecha de corte. Ejecutado 2026-07-13, corte al 13-jul.
-- v2: recalibrado 2026-07-14 con la definicion corregida antiguos/nuevos
-- (bug 12, ver BUGS.md y enfoque_capital_asegurado.sql): un credito que
-- entra en mora (dayslate 0->1) el DIA 1 de julio viene de una cuota
-- vencida el 30-jun -- es antiguo (stock), no nuevo. Stock = stock de
-- siempre (mora 1-30 al cierre de junio) UNION los entrantes del dia 1.
-- Nuevos arranca a detectar entradas desde el dia 2.
--
-- A diferencia de avance_capital_asegurado_julio.sql (que da el REAL
-- ACTIVADO por dia para stock y nuevos, ya usado por avance_capital_
-- asegurado_julio.py), esta consulta agrega la pieza que faltaba: cuanto
-- capital se ASIGNA (entra en mora) cada dia en el motor de "nuevos" --
-- necesaria para explicar dia a dia como crece la poblacion de nuevos,
-- por separado de cuanto de esa poblacion ya "aseguro" (pago >=1 vez).
--
-- Las queries comparten las mismas CTEs base (loan_chain, fotos, exclusion
-- de reenganches) que el resto del proyecto -- ver enfoque_capital_asegurado.md.
-- Resultado combinado (real) en
-- datos_avance_capital_asegurado_julio/tabla_diaria_alfa.csv.
-- =====================================================================

-- ---------------------------------------------------------------------
-- D1. STOCK -- capital ANTIGUO (mora 1-30 al cierre de junio UNION
-- entrantes del dia 1) que se asegura (paga por primera vez en el mes)
-- cada dia. La ASIGNACION del stock es un evento del 1-jul (no cambia
-- dia a dia) -- por eso esta query solo devuelve la fecha de ACTIVACION.
-- Cacheado en datos_avance_capital_asegurado_julio/jul_aseg_real_stock.csv.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20260625' and a.fechaproceso <= '20260713'  -- <- ajustar fecha de corte
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, dia1_julio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260701'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, dia1_entrantes as (
  select id_loan, saldo as saldo_inicial from dia1_julio where rn = 1 and mora = 1 and saldo > 0
)
, stock_julio as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
, pagos_julio as (
  select s.id_loan, s.saldo_inicial, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock_julio s
  join fotos f on f.id_loan = s.id_loan
  where f.fechaproceso between '20260701' and '20260713'  -- <- ajustar fecha de corte
)
, primer_pago as (
  select id_loan, saldo_inicial, min(fechaproceso) as fecha_primer_pago
  from pagos_julio
  where pago_flag = 1
  group by 1,2
)
select fecha_primer_pago as fechaproceso, count(*) as creditos_activados, round(sum(saldo_inicial),2) as saldo_activado_dia
from primer_pago
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- D2. NUEVOS -- cuanto capital se ASIGNA cada dia (creditos que entran en
-- mora, dayslate 0->1, EXCLUYENDO el dia 1 -- bug 12, esos son stock/D1 --
-- y excluyendo el stock). "Calendario real" de entradas, dia a dia, no el
-- proyectado por P(no paga a tiempo) x calendario de vencimientos.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , lag(coalesce(a.dayslate,0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20260601' and a.fechaproceso <= '20260713'  -- <- ajustar fecha de corte
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio_ids as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_julio as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260713'  -- bug 12: arranca dia 2 -- <- ajustar fecha de corte
    and f.id_loan not in (select id_loan from stock_julio_ids)
)
select fecha_entrada as fechaproceso, count(*) as entradas, round(sum(saldo_entrada),2) as saldo_asignado_dia
from entradas_julio
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- D3. NUEVOS -- capital que se ASEGURA (paga por primera vez) cada dia,
-- de la poblacion que ya entro en mora desde el dia 2 (D2). Igual patron
-- que D1 pero anclado a fecha_entrada (no a un unico dia de asignacion).
-- Cacheado en datos_avance_capital_asegurado_julio/jul_aseg_real_nuevos.csv.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , lag(coalesce(a.dayslate,0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20260601' and a.fechaproceso <= '20260713'  -- <- ajustar fecha de corte
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio_ids as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_julio as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260713'  -- bug 12: arranca dia 2 -- <- ajustar fecha de corte
    and f.id_loan not in (select id_loan from stock_julio_ids)
)
, pagos as (
  select e.id_loan, e.saldo_entrada, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_julio e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada and f.fechaproceso <= '20260713'  -- <- ajustar fecha de corte
)
, primer_pago as (
  select id_loan, saldo_entrada, min(fechaproceso) as fecha_primer_pago
  from pagos
  where pago_flag = 1
  group by 1,2
)
select fecha_primer_pago as fechaproceso, count(*) as creditos_activados, round(sum(saldo_entrada),2) as saldo_activado_dia
from primer_pago
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- D4. TABLA COMBINADA -- D1+D2+D3 en un solo query, con acumulados via
-- SUM(...) OVER (ORDER BY fecha) calculados directamente en Athena.
--
-- OJO gotcha Presto (ver CLAUDE.md): el acumulado va en el SELECT final,
-- que NO tiene WHERE sobre fecha -- el filtro de rango ya se aplico antes
-- (en "fotos" y en el calendario), asi que no hay riesgo de que el WHERE
-- se aplique antes que la window function.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , lag(coalesce(a.dayslate,0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20260601' and a.fechaproceso <= '20260713'  -- <- ajustar fecha de corte
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, dia1_julio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260701'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, dia1_entrantes_stock as (
  select id_loan, saldo as saldo_inicial from dia1_julio where rn = 1 and mora = 1 and saldo > 0
)
, stock_julio as (
  select * from stock_previo
  union all
  select * from dia1_entrantes_stock
)
, entradas_julio as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260713'  -- bug 12: arranca dia 2 -- <- ajustar fecha de corte
    and f.id_loan not in (select id_loan from stock_previo)
)
, nuevos_asignado_dia as (
  select fecha_entrada as fecha, count(*) as entradas, sum(saldo_entrada) as saldo_asignado_dia
  from entradas_julio group by 1
)
, pagos_stock as (
  select s.id_loan, s.saldo_inicial, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock_julio s
  join fotos f on f.id_loan = s.id_loan
  where f.fechaproceso between '20260701' and '20260713'  -- <- ajustar fecha de corte
)
, primer_pago_stock as (
  select id_loan, saldo_inicial, min(fechaproceso) as fecha
  from pagos_stock where pago_flag = 1 group by 1,2
)
, stock_asegurado_dia as (
  select fecha, sum(saldo_inicial) as saldo_dia from primer_pago_stock group by 1
)
, pagos_nuevos as (
  select e.id_loan, e.saldo_entrada, f.fechaproceso,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_julio e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada and f.fechaproceso <= '20260713'  -- <- ajustar fecha de corte
)
, primer_pago_nuevos as (
  select id_loan, saldo_entrada, min(fechaproceso) as fecha
  from pagos_nuevos where pago_flag = 1 group by 1,2
)
, nuevos_asegurado_dia as (
  select fecha, sum(saldo_entrada) as saldo_dia from primer_pago_nuevos group by 1
)
, calendario as (
  select date_format(d, '%Y%m%d') as fecha
  from unnest(sequence(date '2026-07-01', date '2026-07-13', interval '1' day)) as t(d)  -- <- ajustar fecha de corte
)
, base as (
  select
    c.fecha
  , coalesce(na.entradas,0) as nuevos_entradas
  , coalesce(na.saldo_asignado_dia,0) as nuevos_asignado_dia
  , coalesce(sd.saldo_dia,0) as stock_asegurado_dia
  , coalesce(nd.saldo_dia,0) as nuevos_asegurado_dia
  from calendario c
  left join nuevos_asignado_dia na on na.fecha = c.fecha
  left join stock_asegurado_dia sd on sd.fecha = c.fecha
  left join nuevos_asegurado_dia nd on nd.fecha = c.fecha
)
select
  fecha
, nuevos_entradas
, round(nuevos_asignado_dia,2) as nuevos_asignado_dia
, round(sum(nuevos_asignado_dia) over (order by fecha),2) as nuevos_asignado_acum
, round(stock_asegurado_dia,2) as stock_asegurado_dia
, round(sum(stock_asegurado_dia) over (order by fecha),2) as stock_asegurado_acum
, round(nuevos_asegurado_dia,2) as nuevos_asegurado_dia
, round(sum(nuevos_asegurado_dia) over (order by fecha),2) as nuevos_asegurado_acum
, round(stock_asegurado_dia + nuevos_asegurado_dia,2) as total_asegurado_dia
, round(sum(stock_asegurado_dia + nuevos_asegurado_dia) over (order by fecha),2) as total_asegurado_acum
from base
order by fecha
;

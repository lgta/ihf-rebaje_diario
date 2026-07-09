-- =====================================================================
-- FASE 2 - MOTOR DE NUEVOS (creditos que caen en mora durante el mes)
-- Ejecutada 2026-07-08 en Athena (db dev_datalake_master).
--
-- Nota metodologica: se investigo dts_cobranza_creditos_cuotas
-- (dias_vencimiento_a_pago, principalamountpaid/due) como fuente
-- cuota-a-cuota. Sirve para la curva en # OPERACIONES (2A, mas abajo,
-- comentada) pero sus campos de capital estan rotos para este uso
-- (principalamountpaid sobre-atribuye pagos anticipados/cancelaciones
-- a cuotas individuales -> el acumulado supera 400% del principal
-- adeudado). Por eso la curva en CAPITAL se construye con el mismo
-- metodo validado en fase1_stock.sql (deltas de dts_mambu_loans_hist),
-- pero indexada por "dias desde entrada en mora" en vez de tramo fijo
-- de inicio de mes.
--
-- Definiciones:
--  * Entrada en mora = transicion mora_ant=0 -> mora=1 (99.7% de las
--    entradas son limpias, ver fase0_diagnostico.sql bloque 0.4).
--  * saldo_entrada = saldo capital el dia que entra en mora (dia 0).
--  * dia_desde_entrada = dias transcurridos desde fecha_entrada.
--  * Ventana de entradas: 2025-03-01 a 2026-05-31 (deja min. 31 dias
--    de fotos posteriores para no censurar la cola de la curva).
--  * Mismas bandas de term/avance que fase1_stock.sql.
--  * Misma exclusion de reenganches/refinanciamientos que fase1_stock.sql
--    (join a dts_cobranza_creditos_cuotas por flg_last_loan_in_chain).
--    IMPACTO MEDIDO en 2C: ~5.4% menos entradas (74,843 -> 70,797) y
--    la curva d31 baja de 23.16% a 22.30% (-0.9pp) -> ajuste menor,
--    no cambia conclusiones.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2A. CURVA EN # OPERACIONES (validacion contra referencia del usuario:
-- ~70% paga al dia 0 de vencimiento, ~85% acumulado al dia 1).
--
-- HISTORIAL DE LA VALIDACION (ver plan_analisis.md pregunta 0):
--  1) Primer intento con status='ACTIVE' (bug: excluye COMPLETED, es
--     decir excluye a los que YA terminaron de pagar bien) -> dia0
--     60.8%, dia1 69.0%. Muy por debajo de la referencia.
--  2) Fix status IN ('ACTIVE','COMPLETED') solo -> dia0 65.3%, dia1
--     72.8%. Mejora parcial.
--  3) + flg_last_loan_in_chain=1 (excluye cuotas de creditos que
--     fueron reenganchados/refinanciados, cuyas cuotas quedan
--     "colgadas" en LATE para siempre) -> dia0 72.6%, dia1 81.2%,
--     plateau d31 93.8%. Muy cerca de la referencia del usuario
--     (70% / 85%). Filtro final adoptado abajo.
-- NOTA: este ajuste de cadena tiene un impacto GRANDE aqui (+7-8pp)
-- porque esta curva se mide sobre TODA la cartera de vencimientos
-- (incluye renovaciones sanas, no solo mora). En fase1_stock.sql y
-- en el bloque 2C/2D de abajo (poblacion acotada a mora 1-30) el
-- mismo filtro tiene un impacto mucho menor (-0.3 a -0.9pp), porque
-- los reenganches "sanos" (sin pasar por mora) no entran a esa
-- poblacion de todos modos.
-- ---------------------------------------------------------------------
with cuotas as (
select
  id_ihfintech_loan
, id_loan_nro_cuota
, fechavencimiento
, installmentstate
, dias_vencimiento_a_pago
, principalamountpaid
, principalamountdue
, cuotavencimiento
, nrocuotas
, amountfinanced
from dts_cobranza_creditos_cuotas
where fechavencimiento >= date('2025-03-01')
  and fechavencimiento <= date('2026-05-31')
  and status in ('ACTIVE','COMPLETED')
  and flg_last_loan_in_chain = 1
)
, dias as (select d as dia from unnest(sequence(0, 31)) as t(d))
select
  d.dia
, count(distinct case when c.installmentstate = 'PAID' and c.dias_vencimiento_a_pago <= d.dia then c.id_loan_nro_cuota end) * 100.0
    / count(distinct c.id_loan_nro_cuota) as pct_operaciones_acum
from cuotas c
cross join dias d
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- CTEs BASE para 2C y 2D (capital, via dts_mambu_loans_hist)
-- ---------------------------------------------------------------------
with loan_chain as (
select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
from dts_cobranza_creditos_cuotas
group by 1
)
, fotos as (
select
  a.fechaproceso
, a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
, a.balances_principalbalance                        as saldo
, coalesce(a.dayslate, 0)                            as mora
, b."term"                                           as term
, b.amountfinanced
, lag(a.balances_principalbalance) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as saldo_ant
, lag(coalesce(a.dayslate, 0)) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as mora_ant
, row_number() over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as nro_foto
from dts_mambu_loans_hist a
join dts_okaapi_loans b
  on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
left join loan_chain lc
  on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and a.fechaproceso >= '20250201'
  and coalesce(lc.last_in_chain, 1) = 1
)
, entradas as (
select
  id_loan
, fechaproceso as fecha_entrada
, date_parse(fechaproceso, '%Y%m%d') as fecha_entrada_d
, saldo         as saldo_entrada
, term
, amountfinanced
, case when term <= 6  then 'a. term 1-6'
       when term <= 12 then 'b. term 7-12'
       else                 'c. term 13+' end as term_band
, case when saldo >= 0.9 * amountfinanced then 'a. avance <10%'
       when saldo >= 0.6 * amountfinanced then 'b. avance 10-40%'
       when saldo >= 0.3 * amountfinanced then 'c. avance 40-70%'
       else                                     'd. avance 70%+' end as avance_band
from fotos
where nro_foto > 1
  and mora_ant = 0
  and mora = 1
  and fechaproceso between '20250301' and '20260531'
)
, rebajes as (
select
  e.id_loan
, e.fecha_entrada
, e.term_band
, e.avance_band
, e.saldo_entrada
, date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada
, case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
from entradas e
join fotos f
  on f.id_loan = e.id_loan
 and f.fechaproceso > e.fecha_entrada
 and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)

-- ---------------------------------------------------------------------
-- 2C. CURVA GLOBAL EN CAPITAL POR DIA DESDE ENTRADA EN MORA
-- (pegar debajo de las CTEs base de arriba)
-- ---------------------------------------------------------------------
, rebaje_dia as (
select dia_desde_entrada, sum(rebaje) as rebaje_dia
from rebajes
group by 1
)
, base_total as (
select sum(saldo_entrada) as saldo_entrada_total, count(*) as entradas
from entradas
)
select
  r.dia_desde_entrada
, round(sum(r.rebaje_dia) over (order by r.dia_desde_entrada)
        / b.saldo_entrada_total * 100, 3) as pct_recupero_acum
, b.entradas
from rebaje_dia r
cross join base_total b
order by r.dia_desde_entrada
;

-- ---------------------------------------------------------------------
-- 2D. CURVA SEGMENTADA POR AVANCE (reemplaza el bloque 2C de arriba,
-- misma logica pero por banda; pegar debajo de CTEs base)
--
-- CORREGIDO 2026-07-08: la version anterior filtraba
-- "where dia_desde_entrada in (...)" en la MISMA query que el
-- acumulado (sum(...) over (order by dia_desde_entrada)). En
-- Presto/Athena el WHERE se aplica ANTES de la window function, asi
-- que el acumulado arrancaba mal (desde el primer dia que sobrevive
-- al filtro, no desde el dia 1 real). Eso invalido los resultados de
-- severidad por avance reportados inicialmente (8.2/11.0/22.5/38.4 a
-- d31) -- los correctos son mas altos (14.4/19.8/40.9/74.2 a d31, ver
-- plan_analisis.md). Esta version ya no filtra dias, devuelve la
-- curva completa 1-31; filtrar dias especificos, si se necesita,
-- DESPUES en una subconsulta externa, nunca en la misma query que la
-- window function. Se quito tambien el segmentador `term` (redundante
-- con avance, ver fase1_stock.sql) para simplificar.
-- ---------------------------------------------------------------------
/*
, rebaje_dia as (
select avance_band, dia_desde_entrada, sum(rebaje) as rebaje_dia
from rebajes
group by 1, 2
)
, base_total as (
select avance_band, sum(saldo_entrada) as saldo_entrada_total, count(*) as entradas
from entradas
group by 1
)
select
  r.avance_band
, r.dia_desde_entrada
, round(sum(r.rebaje_dia) over (partition by r.avance_band order by r.dia_desde_entrada)
        / b.saldo_entrada_total * 100, 3) as pct_recupero_acum
, b.entradas
from rebaje_dia r
join base_total b on b.avance_band = r.avance_band
order by r.avance_band, r.dia_desde_entrada
*/

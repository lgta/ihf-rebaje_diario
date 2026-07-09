-- =====================================================================
-- FASE 0 - DIAGNOSTICO DE DATOS (ver plan_analisis.md)
-- Motor: Athena/Presto. Ejecutar cada bloque por separado.
-- Alcance: historia desde 2025-03-01, creditos ACTIVE/COMPLETED
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0.1 COBERTURA DEL HISTORICO
-- Esperado: dias_con_foto = dias calendario del mes y creditos estables.
-- Si un mes tiene huecos de dias, los deltas acumulan varios dias.
-- ---------------------------------------------------------------------
select
  substr(a.fechaproceso, 1, 6)                                    as periodo
, count(*)                                                        as filas
, count(distinct a._datos_adicionales_loan_accounts_id_ihfintech) as creditos
, count(distinct a.fechaproceso)                                  as dias_con_foto
from dts_mambu_loans_hist a
group by 1
order by 1
;


-- ---------------------------------------------------------------------
-- 0.2 GRUMOSIDAD DEL PAGO (valida el cambio de enfoque)
-- Distribucion del # de dias con rebaje positivo por credito-mes en mora.
-- Esperado: masa concentrada en 0, 1 y 2 dias -> el pago es un evento,
-- no un flujo diario.
-- ---------------------------------------------------------------------
with base as (
select
  substr(a.fechaproceso, 1, 6)                       as periodo
, cast(substr(a.fechaproceso, 7, 2) as int)          as dia
, a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
, a.balances_principalbalance                        as saldo
, a.dayslate
, lag(a.balances_principalbalance) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as saldo_ant
from dts_mambu_loans_hist a
join dts_okaapi_loans b
  on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and a.fechaproceso >= '20250301'
)
, credito_mes as (
select
  periodo
, id_loan
, sum(case when saldo_ant > saldo then 1 else 0 end) as dias_con_rebaje
, max(dayslate)                                      as mora_max
, max(case when dia = 1 then dayslate end)           as mora_dia1
from base
group by 1, 2
)
select
  dias_con_rebaje
, count(*)                                              as creditos_mes
, round(100.0 * count(*) / sum(count(*)) over (), 2)    as pct
from credito_mes
where mora_max >= 1                    -- tuvo mora en el mes
  and coalesce(mora_dia1, 0) <= 30     -- stock 1-30 o entro nuevo en el mes
group by 1
order by 1
;


-- ---------------------------------------------------------------------
-- 0.3 AUMENTOS DE SALDO CAPITAL (ruido)
-- El saldo capital no deberia subir. Si sube (capitalizacion, ajuste),
-- hay que decidir su tratamiento. Este bloque mide cuanto pesa.
-- ---------------------------------------------------------------------
with base as (
select
  substr(a.fechaproceso, 1, 6)                       as periodo
, a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
, a.balances_principalbalance                        as saldo
, lag(a.balances_principalbalance) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as saldo_ant
from dts_mambu_loans_hist a
join dts_okaapi_loans b
  on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and a.fechaproceso >= '20250301'
)
select
  periodo
, sum(case when saldo_ant > saldo then saldo_ant - saldo else 0 end) as rebaje_total
, sum(case when saldo > saldo_ant then saldo - saldo_ant else 0 end) as aumento_total
, sum(case when saldo > saldo_ant then 1 else 0 end)                 as filas_con_aumento
from base
group by 1
order by 1
;


-- ---------------------------------------------------------------------
-- 0.4 MECANICA DE DAYSLATE
-- Valida que la mora avanza +1 por dia y resetea al pagar.
-- HALLAZGO FASE 0: dayslate es NULL cuando el credito esta al dia
-- (no 0), por eso se usa coalesce(dayslate, 0) en todo el analisis.
-- ---------------------------------------------------------------------
with base as (
select
  a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
, coalesce(a.dayslate, 0)                            as mora
, lag(coalesce(a.dayslate, 0)) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as mora_ant
, row_number() over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as nro_foto
from dts_mambu_loans_hist a
join dts_okaapi_loans b
  on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and a.fechaproceso >= '20250301'
)
select
  case
    when nro_foto = 1                         then 'a. primer registro'
    when mora_ant = 0 and mora = 0            then 'b. al dia (sin mora)'
    when mora_ant = 0 and mora = 1            then 'c. entra en mora'
    when mora_ant = 0 and mora > 1            then 'd. entra en mora con salto'
    when mora = mora_ant + 1                  then 'e. mora avanza +1'
    when mora = mora_ant and mora > 0         then 'f. mora congelada'
    when mora_ant > 0 and mora = 0            then 'g. cura (reset a 0)'
    when mora < mora_ant and mora > 0         then 'h. baja parcial'
    else                                           'i. otro'
  end                                                 as transicion
, count(*)                                            as filas
, round(100.0 * count(*) / sum(count(*)) over (), 2)  as pct
from base
group by 1
order by 1
;


-- ---------------------------------------------------------------------
-- 0.5 CANCELACIONES TOTALES ESTANDO EN MORA
-- Saldo capital llega a 0 con mora vigente: recupero del 100%.
-- Mide cuantos son y cuanto capital representan.
-- ---------------------------------------------------------------------
with base as (
select
  substr(a.fechaproceso, 1, 6)                       as periodo
, a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
, a.balances_principalbalance                        as saldo
, lag(a.balances_principalbalance) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as saldo_ant
, lag(a.dayslate) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as mora_ant
from dts_mambu_loans_hist a
join dts_okaapi_loans b
  on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and a.fechaproceso >= '20250301'
)
select
  periodo
, count(distinct id_loan) as creditos_cancelan_en_mora
, sum(saldo_ant)          as capital_recuperado_por_cancelacion
from base
where mora_ant > 0
  and saldo = 0
  and saldo_ant > 0
group by 1
order by 1
;

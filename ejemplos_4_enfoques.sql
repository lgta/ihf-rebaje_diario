-- =====================================================================
-- EJEMPLOS REALES PARA guia_4_enfoques.html
-- Ejecutadas 2026-07-12 en Athena (db dev_datalake_master). Cada bloque
-- trae la trayectoria diaria completa de UN credito real, usada para
-- graficar el ejemplo de cada enfoque en el artifact. No se guardan CSVs
-- (son queries puntuales, no motores) -- correr de nuevo si se necesitan
-- los datos crudos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- EJEMPLO 1 y 3 (acumulado / capital asegurado) -- credito A: activa con
-- un pago chico el dia 17 de junio. Elegido de candidatos del stock de
-- junio 2026 (periodo_meta=202606, anclado a cierre de mayo) filtrando
-- por "pago chico relativo al saldo" (pct_rebaje_sobre_saldo < 2%) y
-- saldo > S/5,000 para que el ejemplo sea legible.
-- id_loan = e79d748e-d8a0-4bb9-a322-47bd4380f848
-- ---------------------------------------------------------------------
select a.fechaproceso, coalesce(a.dayslate,0) as mora, round(a.balances_principalbalance,0) as saldo
from dts_mambu_loans_hist a
where a._datos_adicionales_loan_accounts_id_ihfintech = 'e79d748e-d8a0-4bb9-a322-47bd4380f848'
  and a.fechaproceso between '20260531' and '20260630'
order by a.fechaproceso
;

-- ---------------------------------------------------------------------
-- EJEMPLO 3 -- credito B: nunca paga en todo el mes (contraste con A).
-- id_loan = e1b288ad-8e84-460f-b20a-451915d1c07c
-- ---------------------------------------------------------------------
select a.fechaproceso, coalesce(a.dayslate,0) as mora, round(a.balances_principalbalance,0) as saldo
from dts_mambu_loans_hist a
where a._datos_adicionales_loan_accounts_id_ihfintech = 'e1b288ad-8e84-460f-b20a-451915d1c07c'
  and a.fechaproceso between '20260531' and '20260630'
order by a.fechaproceso
;

-- ---------------------------------------------------------------------
-- EJEMPLO 2 (reinicio del reloj) -- "aged-out survivor": estaba en el
-- stock de julio (mora 1-30 al cierre de junio, tramo 16-30) pero para
-- el 12-jul ya cruzo 30 dias de mora sin pagar nada.
-- id_loan = 1c783c2d-92ce-429d-a496-15c431d0b956
-- ---------------------------------------------------------------------
select a.fechaproceso, coalesce(a.dayslate,0) as mora, round(a.balances_principalbalance,0) as saldo
from dts_mambu_loans_hist a
where a._datos_adicionales_loan_accounts_id_ihfintech = '1c783c2d-92ce-429d-a496-15c431d0b956'
  and a.fechaproceso between '20260630' and '20260712'
order by a.fechaproceso
;

-- ---------------------------------------------------------------------
-- EJEMPLO 4 (salida de mora) -- un episodio cura_real y uno cura_sin_pago,
-- ambos con motivo_apertura poblado y saldo_entrada de tamano similar
-- (~S/11-13K), elegidos de la clasificacion de enfoque_salida_mora.sql Q1.
-- cura_real:     id_loan = 28c55f9c-ff01-42ad-b1c4-c74695a34c89 (01mar-21mar-2025)
-- cura_sin_pago: id_loan = 24f15e0d-69de-4334-99f4-58cd0708a7d6 (07jun-30jun-2025)
-- ---------------------------------------------------------------------
select 'cura_real' as caso, a.fechaproceso, coalesce(a.dayslate,0) as mora, round(a.balances_principalbalance,0) as saldo
from dts_mambu_loans_hist a
where a._datos_adicionales_loan_accounts_id_ihfintech = '28c55f9c-ff01-42ad-b1c4-c74695a34c89'
  and a.fechaproceso between '20250226' and '20250324'
union all
select 'cura_sin_pago' as caso, a.fechaproceso, coalesce(a.dayslate,0) as mora, round(a.balances_principalbalance,0) as saldo
from dts_mambu_loans_hist a
where a._datos_adicionales_loan_accounts_id_ihfintech = '24f15e0d-69de-4334-99f4-58cd0708a7d6'
  and a.fechaproceso between '20250604' and '20250703'
order by 1, 2
;

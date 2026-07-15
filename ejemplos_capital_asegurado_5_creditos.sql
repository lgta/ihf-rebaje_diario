-- =====================================================================
-- 5 CREDITOS REALES PARA EL ARTIFACT "CAPITAL ASEGURADO" (capital_asegurado.html)
-- Ejecutadas 2026-07-13 en Athena (db dev_datalake_master). Todos del
-- stock/nuevos de junio 2026 (periodo_meta=202606, anclado a cierre de
-- mayo), elegidos para mostrar que el TAMAÑO del pago no importa para
-- "activar" el capital asegurado -- solo que haya pago.
--
-- Creditos elegidos (id_loan -> caso):
--   e79d748e-d8a0-4bb9-a322-47bd4380f848 -> paga poco, dia 17 (ya usado en ejemplos_4_enfoques.sql)
--   e1b288ad-8e84-460f-b20a-451915d1c07c -> nunca paga (ya usado en ejemplos_4_enfoques.sql)
--   210ec2b8-ec7d-4275-b7b3-ed853d7df85f -> paga tarde, dia 26 (S/48 de S/11,398)
--   d06e3f04-7f8c-49c6-ac89-60da1ac360e8 -> nuevo, entra dia 3, paga dia 4
--   7a53f103-abdb-4ca7-9f21-f06a197a2b1e -> paga grande, dia 3 (S/2,715 de S/5,146, 52.8%)
-- =====================================================================

-- ---------------------------------------------------------------------
-- BUSQUEDA 1 -- candidato "paga tarde": stock de junio (mora 1-30 al
-- cierre de mayo, saldo S/3,000-15,000), primer pago entre dia 24 y 29.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , cast(substr(a.fechaproceso, 7, 2) as int) as dia
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate, 0) as mora
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso >= '20260525' and a.fechaproceso <= '20260630'
    and coalesce(lc.last_in_chain, 1) = 1
)
, cierre_mayo as (
  select *, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260531'
)
, stock_junio as (
  select id_loan, saldo as saldo_inicial, mora
  from cierre_mayo
  where rn = 1 and mora between 1 and 30 and saldo between 3000 and 15000
)
, pagos as (
  select s.id_loan, s.saldo_inicial, f.dia,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock_junio s
  join fotos f on f.id_loan = s.id_loan
  where f.fechaproceso between '20260601' and '20260630'
)
select id_loan, saldo_inicial, min(dia) as dia_primer_pago
from pagos where pago_flag = 1
group by 1,2
having min(dia) between 24 and 29
order by saldo_inicial desc
limit 3
;

-- ---------------------------------------------------------------------
-- BUSQUEDA 2 -- candidato "nuevo que activa rapido": entra en mora
-- (dayslate 0->1) entre el 2 y el 15 de junio, y paga dentro de los 3
-- dias siguientes a entrar.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , cast(substr(a.fechaproceso, 7, 2) as int) as dia
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate, 0) as mora
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  , lag(coalesce(a.dayslate,0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso >= '20260525' and a.fechaproceso <= '20260630'
    and coalesce(lc.last_in_chain, 1) = 1
)
, entradas as (
  select id_loan, dia as dia_entrada, saldo as saldo_entrada
  from fotos
  where mora_ant = 0 and mora = 1 and fechaproceso between '20260602' and '20260615'
    and saldo between 3000 and 15000
)
, pagos_entrada as (
  select e.id_loan, e.saldo_entrada, e.dia_entrada, f.dia,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.dia > e.dia_entrada and f.dia <= e.dia_entrada + 10
)
select id_loan, saldo_entrada, dia_entrada, min(dia) as dia_primer_pago, min(dia) - dia_entrada as dias_hasta_pago
from pagos_entrada where pago_flag = 1
group by 1,2,3
having min(dia) - dia_entrada <= 3
order by saldo_entrada desc
limit 3
;

-- ---------------------------------------------------------------------
-- BUSQUEDA 3 -- candidato "paga grande" (>50% del saldo en un solo dia,
-- sin llegar a cancelar del todo).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , cast(substr(a.fechaproceso, 7, 2) as int) as dia
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate, 0) as mora
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso >= '20260525' and a.fechaproceso <= '20260630'
    and coalesce(lc.last_in_chain, 1) = 1
)
, cierre_mayo as (
  select *, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260531'
)
, stock_junio as (
  select id_loan, saldo as saldo_inicial, mora
  from cierre_mayo
  where rn = 1 and mora between 1 and 30 and saldo between 5000 and 15000
)
, pagos as (
  select s.id_loan, s.saldo_inicial, f.dia, f.saldo,
    case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from stock_junio s
  join fotos f on f.id_loan = s.id_loan
  where f.fechaproceso between '20260601' and '20260630'
)
select id_loan, saldo_inicial, dia as dia_pago, saldo as saldo_despues, rebaje,
  round(100.0*rebaje/saldo_inicial,1) as pct_pagado
from pagos
where rebaje > 0.5 * saldo_inicial
order by saldo_inicial desc
limit 3
;

-- ---------------------------------------------------------------------
-- TRAYECTORIA COMPLETA de los 5 creditos elegidos (fechaproceso, mora,
-- saldo, 31-may a 30-jun) -- usada para las mini-gráficas del artifact.
-- ---------------------------------------------------------------------
select
  case a._datos_adicionales_loan_accounts_id_ihfintech
    when 'e79d748e-d8a0-4bb9-a322-47bd4380f848' then '1_paga_poco_temprano'
    when 'e1b288ad-8e84-460f-b20a-451915d1c07c' then '2_no_paga'
    when '210ec2b8-ec7d-4275-b7b3-ed853d7df85f' then '3_paga_tarde'
    when 'd06e3f04-7f8c-49c6-ac89-60da1ac360e8' then '4_nuevo_rapido'
    when '7a53f103-abdb-4ca7-9f21-f06a197a2b1e' then '5_paga_grande'
  end as caso
, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
, a.fechaproceso
, coalesce(a.dayslate,0) as mora
, round(a.balances_principalbalance,2) as saldo
from dts_mambu_loans_hist a
where a._datos_adicionales_loan_accounts_id_ihfintech in (
  'e79d748e-d8a0-4bb9-a322-47bd4380f848',
  'e1b288ad-8e84-460f-b20a-451915d1c07c',
  '210ec2b8-ec7d-4275-b7b3-ed853d7df85f',
  'd06e3f04-7f8c-49c6-ac89-60da1ac360e8',
  '7a53f103-abdb-4ca7-9f21-f06a197a2b1e'
)
and a.fechaproceso between '20260531' and '20260630'
order by 1, 3
;

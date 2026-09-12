-- =====================================================================
-- TAREA 21 -- CASOS CONCRETOS DE REENTRADA DENTRO DEL MES (agosto 2026)
--
-- El escenario que describio el usuario, con nombre y apellido: un credito
-- que arranca el mes EN MORA (antiguo), paga y CURA (dias_atraso_cuota
-- vuelve a 0), y despues vuelve a vencer dentro del MISMO mes y REENTRA
-- en mora. Como el atributo antiguo/nuevo se congela al inicio del mes,
-- el negocio lo sigue gestionando como ANTIGUO en esa segunda vuelta.
--
-- Lo que interesa medir:
--   1. CUANTOS son y cuanto capital representan (el `resumen`).
--   2. Como se ven, dia por dia (el `detalle`, una muestra).
--
-- Por que importa para el modelo: si son muchos, la curva de stock tiene
-- que estar absorbiendo esas reentradas -- se calibra sobre esta misma
-- poblacion, midiendo cuanto del capital asignado el dia 1 activa a lo
-- largo del mes, sin importar cuantas veces entre y salga. Si son pocos,
-- el punto es menor. En cualquiera de los dos casos, contarlos ADEMAS en
-- el calendario de nuevos seria doble conteo -- que es justo lo que la
-- exclusion `not in stock_agosto` evita.
--
-- Convencion de mes cerrado: status IN ('ACTIVE','COMPLETED').
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, dac as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , cast(day(c.fecha_calendario) as int)       as dia
  , substr(date_format(c.fecha_calendario, '%Y%m%d'),1,6) as periodo
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
  left join loan_chain lc on lc.id_ihfintech_loan = c.id_ihfintech_loan
  where c.fecha_calendario between date('2026-07-01') and date('2026-08-31')
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, stock_ago as (
  select id_loan, mora as mora_inicial
  from (
    select id_loan, mora,
      row_number() over (partition by id_loan order by fechaproceso desc) as rn
    from dac where periodo = '202607'
  )
  where rn = 1 and mora between 1 and 30
)
, ago as (
  select d.id_loan, d.dia, d.mora
  from dac d join stock_ago s on s.id_loan = d.id_loan
  where d.periodo = '202608'
)
-- para cada credito del stock: el primer dia que curo, y si despues volvio a entrar
, hitos as (
  select
    id_loan
  , min(case when mora = 0 then dia end)                            as dia_cura
  , max(case when mora = 0 then dia end)                            as ult_dia_cero
  , max(dia)                                                        as ult_dia
  , max(case when mora >= 1 then dia end)                           as ult_dia_mora
  from ago group by id_loan
)
, reentradas as (
  select h.id_loan, h.dia_cura, h.ult_dia_mora
  from hitos h
  where h.dia_cura is not null              -- curo en algun momento de agosto
    and h.ult_dia_mora > h.dia_cura         -- y DESPUES volvio a estar en mora
)
, saldo_ini as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn
  from dts_mambu_loans_hist a
  where a.fechaproceso = '20260731'
)
select
  'resumen' as bloque
, cast(count(*) as varchar)                              as id_loan
, cast(round(sum(coalesce(si.saldo,0)), 2) as varchar)   as dato1
, cast(count(distinct r.id_loan) as varchar)             as dato2
, '' as dato3
from reentradas r
left join saldo_ini si on si.id_loan = r.id_loan and si.rn = 1

union all

select
  'resumen_stock' as bloque
, cast(count(*) as varchar)
, cast(round(sum(coalesce(si.saldo,0)), 2) as varchar)
, ''
, ''
from stock_ago s
left join saldo_ini si on si.id_loan = s.id_loan and si.rn = 1

union all

-- detalle dia por dia de una muestra de 12 casos, ordenada por saldo
select
  'detalle' as bloque
, cast(a.id_loan as varchar)
, cast(a.dia as varchar)
, cast(a.mora as varchar)
, cast(round(coalesce(si.saldo,0), 2) as varchar)
from ago a
join (
  select r.id_loan
  from reentradas r
  left join saldo_ini si on si.id_loan = r.id_loan and si.rn = 1
  order by coalesce(si.saldo,0) desc
  limit 12
) m on m.id_loan = a.id_loan
left join saldo_ini si on si.id_loan = a.id_loan and si.rn = 1
order by 1, 2, 3
;

-- =====================================================================
-- TAREA 24 -- ¿EN QUE DIA CAE EL SALDO DE UN CREDITO QUE MAMBU CIERRA POR
-- REFINANCIAMIENTO? Insumo de diseno de las matrices v2.
--
-- Las matrices v2 incluyen los reenganches MARCADOS (bug 25) para poder
-- decidir despues sin volver a Athena. Condicion del plan: el cierre por
-- refinanciamiento NO puede contar como pago. Para eso hay que saber donde
-- cae ese salto de saldo respecto de f_cierre (primer dia con
-- accountsubstate REFINANCED/RESCHEDULED): si cae el mismo dia, alcanza con
-- ignorar las fotos desde f_cierre; si cae antes, hace falta mas margen.
--
-- Salida: caidas de saldo (saldo_ant > saldo) de esos creditos entre 5 dias
-- antes y 3 despues de f_cierre, por dias respecto del cierre, separando
-- las que dejan el saldo en 0. Y cuantos creditos siguen teniendo fotos
-- despues del cierre.
-- =====================================================================
with refin as (
  select _datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , min(fechaproceso) as f_cierre
  from dts_mambu_loans_hist
  where accountsubstate in ('REFINANCED', 'RESCHEDULED')
    and fechaproceso >= '20250101'
  group by 1
)
, fotos as (
  select a._datos_adicionales_loan_accounts_id_ihfintech as id_loan, a.fechaproceso
  , max(a.balances_principalbalance) as saldo          -- dedup de bug 11: el no-cero gana
  from dts_mambu_loans_hist a
  join refin r on r.id_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso >= '20241220'
  group by 1, 2
)
, lagged as (
  select id_loan, fechaproceso, saldo
  , lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  from fotos
)
, rel as (
  select l.*, r.f_cierre
  , date_diff('day', date_parse(r.f_cierre, '%Y%m%d'), date_parse(l.fechaproceso, '%Y%m%d')) as dias_vs_cierre
  from lagged l join refin r on r.id_loan = l.id_loan
)
select 'a. caidas de saldo' as bloque, dias_vs_cierre
, count(*)                                          as caidas
, sum(case when saldo = 0 then 1 else 0 end)        as caidas_a_cero
, round(sum(saldo_ant - saldo), 2)                  as monto
from rel
where saldo_ant > saldo and dias_vs_cierre between -5 and 3
group by 1, 2

union all

select 'b. fotos despues del cierre', least(dias_vs_cierre, 10)
, count(distinct id_loan), sum(case when saldo = 0 then 1 else 0 end), round(sum(saldo), 2)
from rel
where dias_vs_cierre between 0 and 10
group by 1, 2

union all

select 'c. creditos cerrados', 0, count(*), 0, 0 from refin

order by 1, 2
;

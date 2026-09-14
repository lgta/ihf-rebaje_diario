-- =====================================================================
-- TAREA 24 -- ¿QUE SON LOS CREDITOS QUE SACA flg_last_loan_in_chain?
--
-- Aclaracion del usuario 2026-09-13: en OKA un REENGANCHE es un credito
-- ADICIONAL en la misma linea (como aumentar el monto desembolsado), no un
-- refinanciamiento ni una reprogramacion de cobranzas. El proyecto venia
-- llamando "refinanciamiento" al cierre porque Mambu registra el credito
-- anterior con accountsubstate = REFINANCED. Se verifica con datos:
--   - ¿aparece un credito NUEVO del mismo DNI alrededor del cierre (-3 a +1 dias)?
--   - ¿el nuevo arranca con un saldo MAYOR que el que le quedaba al viejo? (top-up)
--   - ¿en que mora estaba el viejo el dia anterior al cierre? Un
--     refinanciamiento de cobranzas vendria con mora; un reenganche, al dia.
--   - extendedbyloan_id de dts_okaapi_loans, como segunda senal del vinculo.
-- Y cuantos creditos con flag 0 NO tienen un cierre REFINANCED/RESCHEDULED.
-- Cierres desde 2025-01.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, cierre as (
  select _datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , min(fechaproceso) as f_cierre
  , min_by(accountsubstate, fechaproceso) as substate
  from dts_mambu_loans_hist
  where accountsubstate in ('REFINANCED', 'RESCHEDULED')
    and fechaproceso >= '20250101'
  group by 1
)
, fotos as (
  -- dedup de bug 11 aproximado: el saldo no-cero gana
  select _datos_adicionales_loan_accounts_id_ihfintech as id_loan, fechaproceso
  , max(balances_principalbalance) as saldo
  from dts_mambu_loans_hist
  where fechaproceso >= '20241201'
  group by 1, 2
)
, alta as (
  -- primera foto de cada credito que nace despues del 1-dic-2024
  select id_loan, min(fechaproceso) as f_alta, min_by(saldo, fechaproceso) as saldo_alta
  from fotos
  group by 1
  having min(fechaproceso) > '20241201'
)
, dni_loan as (
  select id_ihfintech_loan as id_loan, max(dni) as dni
  from dts_cobranza_creditos_calendario_diario
  where fecha_calendario >= date '2024-12-01' and dni is not null
  group by 1
)
, viejo as (
  select c.id_loan, c.substate
  , date(date_parse(c.f_cierre, '%Y%m%d')) as d_cierre
  , coalesce(lc.last_in_chain, 1) as last_in_chain
  , f.saldo as saldo_ant
  , cd.id_ihfintech_loan as fila_cal
  , coalesce(cd.dias_atraso_cuota, 0) as mora_ant
  , dn.dni
  , b.extendedbyloan_id
  from cierre c
  left join loan_chain lc on lc.id_ihfintech_loan = c.id_loan
  left join fotos f on f.id_loan = c.id_loan
    and f.fechaproceso = date_format(date_add('day', -1, date(date_parse(c.f_cierre, '%Y%m%d'))), '%Y%m%d')
  left join dts_cobranza_creditos_calendario_diario cd on cd.id_ihfintech_loan = c.id_loan
    and cd.fecha_calendario = date_add('day', -1, date(date_parse(c.f_cierre, '%Y%m%d')))
  left join dni_loan dn on dn.id_loan = c.id_loan
  left join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_loan
)
, nuevo as (
  select v.id_loan, count(*) as n_nuevos, sum(a.saldo_alta) as saldo_nuevo
  from viejo v
  join dni_loan dn on dn.dni = v.dni and dn.id_loan <> v.id_loan
  join alta a on a.id_loan = dn.id_loan
  where date(date_parse(a.f_alta, '%Y%m%d'))
        between date_add('day', -3, v.d_cierre) and date_add('day', 1, v.d_cierre)
  group by 1
)
select
  v.substate
, case when v.last_in_chain = 0 then 'flag 0' else 'flag 1' end                 as flag_cadena
, case when v.fila_cal is null then 'sin fila en calendario'
       when v.mora_ant = 0 then 'a. al dia'
       when v.mora_ant <= 30 then 'b. mora 1-30'
       else 'c. mora 31+' end                                                   as mora_dia_antes
, case when n.id_loan is not null then 'si' else 'no' end                        as credito_nuevo_mismo_dni
, case when n.id_loan is null then '-'
       when n.saldo_nuevo > coalesce(v.saldo_ant, 0) then 'nuevo > saldo viejo'
       else 'nuevo <= saldo viejo' end                                          as monto
, case when v.extendedbyloan_id is not null then 'si' else 'no' end              as extendedbyloan_id
, count(*)                                                                       as creditos
, round(sum(v.saldo_ant), 2)                                                     as saldo_viejo
, round(sum(n.saldo_nuevo), 2)                                                   as saldo_nuevo
from viejo v
left join nuevo n on n.id_loan = v.id_loan
group by 1, 2, 3, 4, 5, 6

union all

select '(sin cierre REFINANCED/RESCHEDULED)', 'flag 0', '-', '-', '-', '-', count(*)
, cast(null as double), cast(null as double)
from loan_chain lc
where lc.last_in_chain = 0
  and lc.id_ihfintech_loan in (select id_loan from fotos)
  and lc.id_ihfintech_loan not in (select id_loan from cierre)

order by 1, 2, 3, 4, 5, 6
;

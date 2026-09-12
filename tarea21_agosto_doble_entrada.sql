-- =====================================================================
-- TAREA 21 -- EL MISMO DIAGNOSTICO, PERO SOBRE AGOSTO 2026 (mes CERRADO)
--
-- Septiembre dio solo 2 casos de doble vencimiento. La pregunta del
-- usuario es si eso se debe a que el mes recien empieza. NO: el calendario
-- prospectivo es la agenda COMPLETA de vencimientos del mes (los 30 dias
-- ya estan), asi que 2 es un resultado estructural. Esta query lo confirma
-- sobre un mes enteramente observado.
--
-- CONVENCION DE MES CERRADO (CLAUDE.md): `status IN ('ACTIVE','COMPLETED')`
-- y saldo del DIA DEL VENCIMIENTO -- identica a tarea19_calendario_8m.sql,
-- para que los totales sean comparables contra el calendario de agosto ya
-- publicado (S/68,408,838).
--
-- Las tres clases son las mismas que en tarea21_diagnostico_doble_entrada.sql:
--   A  = el credito tambien esta en el stock del 1-ago (YA excluido hoy)
--   B1 = primera entrada del credito en el mes
--   B2 = 2do vencimiento o posterior del MISMO credito (lo que la variante
--        "primera entrada" saca, y que hoy se cuenta dos veces)
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-07-01') and date('2026-08-31')
)
, dac as (
  select d.id_loan, d.fechaproceso, d.mora
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
-- stock de agosto = mora 1-30 en la ULTIMA foto de julio
, stock_ago as (
  select id_loan, mora
  from (
    select id_loan, mora,
      row_number() over (partition by id_loan order by fechaproceso desc) as rn
    from dac
    where substr(fechaproceso,1,6) = '202607'
  )
  where rn = 1 and mora between 1 and 30
)
, saldo_venc as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260731' and '20260830'
)
, cal_todo as (
  select
    c.id_ihfintech_loan as id_loan
  , cast(day(date_add('day',1,c.fechavencimiento)) as int) as dia_entrada
  , f.saldo
  , row_number() over (partition by c.id_ihfintech_loan order by c.fechavencimiento) as nro_venc
  , count(*)      over (partition by c.id_ihfintech_loan)                            as n_vencs
  , case when s.id_loan is not null then 1 else 0 end as es_stock
  from dts_cobranza_creditos_cuotas c
  join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
  join saldo_venc f
    on f.id_loan = c.id_ihfintech_loan
   and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
   and f.rn_dedup = 1
  left join stock_ago s on s.id_loan = c.id_ihfintech_loan
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2026-07-31')
    and c.fechavencimiento <= date('2026-08-30')
    and b.amountfinanced > 0
)
select
  case
    when es_stock = 1 then 'A. tambien esta en el stock (ya excluido hoy)'
    when nro_venc = 1 then 'B1. primera entrada del credito en el mes'
    else                   'B2. vencimiento 2do o posterior del MISMO credito'
  end                                              as clase
, count(*)                                         as cuotas
, count(distinct id_loan)                          as creditos_distintos
, round(sum(saldo), 2)                             as saldo
from cal_todo
group by 1

union all

select 'C. stock del 1-ago (referencia)', count(*), count(distinct id_loan), cast(null as double)
from stock_ago

union all

select 'D. creditos del calendario con N vencimientos: N=' || cast(n_vencs as varchar)
     , count(*), count(distinct id_loan), round(sum(saldo), 2)
from cal_todo
where es_stock = 0
group by n_vencs
order by 1
;

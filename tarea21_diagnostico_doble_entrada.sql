-- =====================================================================
-- TAREA 21 -- DIAGNOSTICO: ¿cuanto capital se cuenta DOS VECES en el
-- calendario prospectivo de septiembre 2026?
--
-- Pregunta del usuario (2026-09-02): la gestion de cobranza congela el
-- atributo antiguo/nuevo al INICIO del mes. Un credito que arranca el mes
-- en mora (antiguo), paga, y vuelve a vencer dentro del mismo mes, entra
-- otra vez -- y su capital podria estar contandose dos veces.
--
-- Son DOS solapamientos distintos y hay que separarlos:
--
--   (A) STOCK x CALENDARIO. Un credito que esta en el stock del 1-sep y
--       ademas tiene un vencimiento en septiembre. YA ESTA EXCLUIDO por
--       `not in (select id_loan from stock_agosto)` en
--       tarea19_meta_septiembre_insumos.sql. Esta query lo MIDE (sin
--       aplicar la exclusion) para saber de que tamano es lo que esa
--       linea esta sacando -- si es grande, la exclusion importa mucho y
--       conviene tenerlo documentado con numero.
--
--   (B) CALENDARIO x CALENDARIO. Un credito con DOS O MAS vencimientos
--       dentro del mismo mes aparece dos veces en el calendario, con su
--       saldo completo cada vez. Esto NO esta excluido: la query de
--       insumos no deduplica por credito-mes. Es el doble conteo que
--       queda vivo, y es el que la variante "primera entrada" corrige.
--
-- OJO -- por que (B) importa mas de lo que parece: `P_ENTRADA` (la tasa
-- por soles, tasa_soles.csv) SI deduplica a un vencimiento por
-- credito-mes (`rn = 1` en tarea19_tasa_soles.sql), pero se aplica sobre
-- un calendario que NO deduplica. Tasa y universo no comparten
-- definicion -- exactamente lo que el "principio de modelado" de
-- CLAUDE.md prohibe. Ver PENDIENTES.md tarea 20.
--
-- Reproduce EXACTO los CTEs de tarea19_meta_septiembre_insumos.sql
-- (mismo ancla al 31-ago, mismo stock, mismos filtros) para que los
-- numeros sean comparables contra la meta vigente al centimo.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_ago as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , b.amountfinanced
  , b.status
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260801' and '20260831'
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, ancla as (
  select id_loan, saldo, amountfinanced, status,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from mambu_ago where rn_dedup = 1
)
, ancla_final as (
  select id_loan, saldo, amountfinanced, status from ancla where rn = 1 and saldo > 0
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-08-01') and date('2026-08-31')
)
, dac_cierre as (
  select d.id_loan, d.mora,
    row_number() over (partition by d.id_loan order by d.fechaproceso desc) as rn
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, stock_agosto as (
  select c.id_loan, c.mora, a.saldo, a.amountfinanced
  from dac_cierre c
  join ancla_final a on a.id_loan = c.id_loan
  where c.rn = 1 and c.mora between 1 and 30
    and a.status in ('ACTIVE','COMPLETED')
)
-- calendario de septiembre SIN NINGUNA exclusion, con el numero de orden
-- del vencimiento dentro del mes para cada credito
, cal_todo as (
  select
    c.id_ihfintech_loan as id_loan
  , cast(day(date_add('day',1,c.fechavencimiento)) as int) as dia_entrada
  , a.saldo
  , a.amountfinanced
  , row_number() over (partition by c.id_ihfintech_loan order by c.fechavencimiento) as nro_venc
  , count(*)      over (partition by c.id_ihfintech_loan)                            as n_vencs
  , case when s.id_loan is not null then 1 else 0 end as es_stock
  from dts_cobranza_creditos_cuotas c
  join ancla_final a on a.id_loan = c.id_ihfintech_loan
  left join stock_agosto s on s.id_loan = c.id_ihfintech_loan
  where c.status = 'ACTIVE'
    and c.flg_last_loan_in_chain = 1
    and a.status = 'ACTIVE'
    and date_add('day',1,c.fechavencimiento) >= date('2026-09-01')
    and date_add('day',1,c.fechavencimiento) <= date('2026-09-30')
)
select
  case
    when es_stock = 1              then 'A. tambien esta en el stock (ya excluido hoy)'
    when nro_venc = 1              then 'B1. primera entrada del credito en el mes'
    else                                'B2. vencimiento 2do o posterior del MISMO credito'
  end                                              as clase
, count(*)                                         as cuotas
, count(distinct id_loan)                          as creditos_distintos
, round(sum(saldo), 2)                             as saldo
from cal_todo
group by 1

union all

select
  'C. stock del 1-sep (referencia)'                as clase
, count(*)                                         as cuotas
, count(distinct id_loan)                          as creditos_distintos
, round(sum(saldo), 2)                             as saldo
from stock_agosto

union all

select
  'D. creditos del calendario con N vencimientos: N=' || cast(n_vencs as varchar) as clase
, count(*)                                         as cuotas
, count(distinct id_loan)                          as creditos_distintos
, round(sum(saldo), 2)                             as saldo
from cal_todo
where es_stock = 0
group by n_vencs
order by 1
;

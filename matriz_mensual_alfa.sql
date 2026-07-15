-- =====================================================================
-- MATRIZ MENSUAL -- capital asegurado (enfoque alfa), asignado vs.
-- asegurado por segmento y mes (mar-2025 a jul-2026, jul en curso).
-- Ejecutado 2026-07-15. Alimenta el artifact curvas_matriz_alfa.html.
--
-- Definicion corregida (bug 12, BUGS.md): antiguo = mora 1-30 al cierre
-- del mes anterior UNION entrantes del dia 1 (cuota vencida el ultimo
-- dia del mes anterior); nuevo = entradas desde el dia 2. Mismo patron
-- que enfoque_capital_asegurado.sql Q1/Q2, pero SIN colapsar periodo_meta
-- (se necesita un total por mes, no la curva agregada de 15 meses).
-- =====================================================================

-- ---------------------------------------------------------------------
-- MATRIZ-STOCK (antiguo) -- por periodo_meta x tramo.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    substr(a.fechaproceso, 1, 6)                       as periodo
  , a.fechaproceso
  , a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
  , a.balances_principalbalance                        as saldo
  , coalesce(a.dayslate, 0)                            as mora
  , b.amountfinanced
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b
    on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc
    on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso >= '20250301'
    and coalesce(lc.last_in_chain, 1) = 1
)
, cierre_mes as (
  select *, row_number() over (partition by id_loan, periodo order by fechaproceso desc) as rn
  from fotos
)
, stock_previo as (
  select
    date_format(date_add('month', 1, date_parse(periodo, '%Y%m')), '%Y%m') as periodo_meta
  , id_loan, saldo as saldo_inicial
  , case when mora between 1 and 8  then 'a. 1-8'
         when mora between 9 and 15 then 'b. 9-15'
         else                            'c. 16-30' end as tramo
  from cierre_mes
  where rn = 1 and mora between 1 and 30 and saldo > 0 and amountfinanced > 0
)
, primer_dia_mes as (
  select *, row_number() over (partition by id_loan, periodo order by fechaproceso asc) as rn
  from fotos
)
, dia1_entrantes as (
  select periodo as periodo_meta, id_loan, saldo as saldo_inicial, 'a. 1-8' as tramo
  from primer_dia_mes
  where rn = 1 and mora = 1 and saldo > 0 and amountfinanced > 0
)
, stock as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
, rebajes as (
  select s.periodo_meta, s.tramo, s.id_loan, s.saldo_inicial,
    max(case when f.saldo_ant > f.saldo then 1 else 0 end) as activado
  from stock s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
  where s.periodo_meta between '202504' and '202607'
  group by 1,2,3,4
)
select
  periodo_meta, tramo
, count(*) as creditos
, round(sum(saldo_inicial),2) as asignado
, round(sum(case when activado=1 then saldo_inicial else 0 end),2) as asegurado
from rebajes
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- MATRIZ-NUEVOS -- por periodo_meta (mes de entrada en mora, excluyendo
-- el dia 1 -- bug 12). Ventana de 31 dias desde la entrada para medir
-- "asegurado" (igual patron que enfoque_capital_asegurado.sql Q2).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
  , a.fechaproceso
  , a.balances_principalbalance                        as saldo
  , coalesce(a.dayslate,0)                              as mora
  , lag(coalesce(a.dayslate,0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as mora_ant
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as saldo_ant
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as nro_foto
  , b.amountfinanced
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b
    on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc
    on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso >= '20250301'
    and coalesce(lc.last_in_chain, 1) = 1
)
, entradas as (
  select
    substr(fechaproceso,1,6) as periodo_meta
  , id_loan, fechaproceso as fecha_entrada, saldo as saldo_entrada
  from fotos
  where nro_foto > 1 and mora_ant = 0 and mora = 1
    and fechaproceso between '20250401' and '20260731'
    and amountfinanced > 0
    and cast(substr(fechaproceso, 7, 2) as int) <> 1  -- bug 12: dia 1 = antiguo, no nuevo
)
, pagos as (
  select e.periodo_meta, e.id_loan, e.saldo_entrada,
    max(case when f.saldo_ant > f.saldo then 1 else 0 end) as activado
  from entradas e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, date_parse(e.fecha_entrada,'%Y%m%d')), '%Y%m%d')
  group by 1,2,3
)
select
  periodo_meta
, count(*) as entradas
, round(sum(saldo_entrada),2) as asignado
, round(sum(case when activado=1 then saldo_entrada else 0 end),2) as asegurado
from pagos
group by 1
order by 1
;

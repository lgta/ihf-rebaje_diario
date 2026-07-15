-- =====================================================================
-- AVANCE DE JULIO SEGMENTADO -- capital asegurado (tramo x avance para
-- stock, avance para nuevos). Ejecutado 2026-07-13, corte al 13-jul.
-- v2: recalibrado 2026-07-14 con la definicion corregida antiguos/nuevos
-- (bug 12, ver BUGS.md): stock = mora 1-30 al cierre de junio UNION los
-- entrantes del dia 1 (su cuota vencio el 30-jun); nuevos arranca a
-- detectar entradas desde el dia 2. Ver enfoque_capital_asegurado.md
-- seccion "Tracking en vivo" y el artifact capital_asegurado.html para la
-- interpretacion. Agregacion + cruce con las curvas (proyectado por
-- segmento): avance_capital_asegurado_julio_segmentado.py
--
-- LISTO PARA POWER BI: cada bloque de abajo es una query autocontenida.
-- Conectar Power BI a Athena (conector nativo "Amazon Athena", DB
-- dev_datalake_master, o via el ODBC driver de Athena) y pegar una de
-- las dos queries como "consulta nativa". Para refrescar con la fecha
-- de hoy, reemplazar '20260713' (la fecha de corte) en ambas queries --
-- no se parametrizo automaticamente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. STOCK -- capital asegurado real vs. asignado, por tramo x avance.
-- Poblacion = mora 1-30 al cierre de junio UNION entrantes del dia 1 de
-- julio (bug 12). Para el "% meta" hay que cruzar el resultado contra
-- datos_capital_asegurado/curva_asegurado_stock_seg.csv (dia = numero de
-- dias desde el 1-jul hasta la fecha de corte) -- eso ya lo hace
-- avance_capital_asegurado_julio_segmentado.py.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  , b.amountfinanced
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20260625' and a.fechaproceso <= '20260713'  -- <- ajustar fecha de corte
)
, cierre_junio as (
  select id_loan, mora, saldo, amountfinanced, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, dia1_julio as (
  select id_loan, mora, saldo, amountfinanced, row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260701'
)
, stock_previo as (
  select id_loan, saldo as saldo_inicial,
    case when mora between 1 and 8  then 'a. 1-8'
         when mora between 9 and 15 then 'b. 9-15'
         else                            'c. 16-30' end as tramo,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from cierre_junio
  where rn = 1 and mora between 1 and 30 and saldo > 0 and amountfinanced > 0
)
, dia1_entrantes as (
  select id_loan, saldo as saldo_inicial,
    'a. 1-8' as tramo,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from dia1_julio
  where rn = 1 and mora = 1 and saldo > 0 and amountfinanced > 0
)
, stock_julio as (
  select * from stock_previo
  union all
  select * from dia1_entrantes
)
, pagos_julio as (
  select s.id_loan, s.saldo_inicial, s.tramo, s.avance_band,
    max(case when f.saldo_ant > f.saldo then 1 else 0 end) as activado
  from stock_julio s
  join fotos f on f.id_loan = s.id_loan
  where f.fechaproceso between '20260701' and '20260713'  -- <- ajustar fecha de corte
  group by 1,2,3,4
)
select
  tramo, avance_band
, count(*) as creditos
, round(sum(saldo_inicial),0) as saldo_total
, sum(activado) as creditos_activados
, round(sum(case when activado=1 then saldo_inicial else 0 end),0) as saldo_asegurado_real
from pagos_julio
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- Q2. NUEVOS -- capital asegurado real, por avance, creditos que
-- entraron en mora (dayslate 0->1) DURANTE julio, EXCLUYENDO el dia 1
-- (bug 12: esos son stock/Q1) y excluyendo el stock.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , lag(coalesce(a.dayslate,0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as saldo_ant
  , b.amountfinanced
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20260601' and a.fechaproceso <= '20260713'  -- <- ajustar fecha de corte
)
, cierre_junio as (
  select id_loan, mora, saldo, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_julio_ids as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30 and saldo > 0
)
, entradas_julio as (
  select f.id_loan, f.fechaproceso as fecha_entrada, f.saldo as saldo_entrada,
    case when f.saldo >= 0.9*f.amountfinanced then 'a. avance <10%'
         when f.saldo >= 0.6*f.amountfinanced then 'b. avance 10-40%'
         when f.saldo >= 0.3*f.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from fotos f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260713'  -- bug 12: arranca dia 2 -- <- ajustar fecha de corte
    and f.amountfinanced > 0
    and f.id_loan not in (select id_loan from stock_julio_ids)
)
, pagos as (
  select e.id_loan, e.saldo_entrada, e.avance_band,
    max(case when f.saldo_ant > f.saldo then 1 else 0 end) as activado
  from entradas_julio e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada and f.fechaproceso <= '20260713'  -- <- ajustar fecha de corte
  group by 1,2,3
)
select
  avance_band
, count(*) as entradas
, round(sum(saldo_entrada),0) as saldo_total
, sum(activado) as creditos_activados
, round(sum(case when activado=1 then saldo_entrada else 0 end),0) as saldo_asegurado_real
from pagos
group by 1
order by 1
;

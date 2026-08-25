-- =====================================================================
-- TAREA 17, FASE 4 -- Q-C: CURVA UNIFICADA DE "STOCK"
-- Reemplaza curva_asegurado_stock_seg.csv (enfoque_capital_asegurado.sql
-- Q1, calibrada con dayslate).
--
-- Cambios respecto de Q1:
--   1. Stock = dias_atraso_cuota entre 1 y 30 al cierre del mes anterior
--      (no dayslate). El tramo tambien sale de dias_atraso_cuota.
--   2. SIN el parche `dia1_entrantes` de bug 12. Con dayslate hacia falta
--      porque un credito con mora=1 el dia 1 del mes venia de una cuota
--      vencida el ultimo dia del mes anterior y quedaba mal clasificado
--      como "nuevo". Con el calendario frontier-adjusted de Fase 4 esa
--      cohorte entra por "nuevos" donde corresponde -- y al cierre del
--      mes anterior tiene atraso 0, asi que NO es stock. Sin solape y
--      sin hueco, verificable por construccion.
--   3. Saldo del stock = saldo Mambu del dia de cierre del mes anterior
--      (igual que Q1 -- aca no aplica el fix de saldo_ant de Fase 3: el
--      stock se ancla a una fecha de corte, no a un evento de entrada).
--
-- Segmentacion identica a produccion (3 tramos x 4 buckets de avance) --
-- decision del usuario: una variable a la vez.
-- Ventana: periodo_meta 202504-202606, LA MISMA que Q1 de produccion.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_raw as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo
  , a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20250325' and '20260630'
)
, mambu_dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from mambu_raw
)
, fotos as (
  select
    substr(d.fechaproceso,1,6)                  as periodo
  , d.fechaproceso
  , cast(substr(d.fechaproceso,7,2) as int)     as dia
  , d.id_loan, d.saldo, b.amountfinanced
  , lag(d.saldo) over (partition by d.id_loan order by d.fechaproceso) as saldo_ant
  from mambu_dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2025-03-25') and date('2026-05-31')
)
, dac as (
  select d.id_loan, d.fechaproceso, d.mora
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, dac_cierre as (
  select substr(fechaproceso,1,6) as periodo, fechaproceso, id_loan, mora,
    row_number() over (partition by id_loan, substr(fechaproceso,1,6)
                       order by fechaproceso desc) as rn
  from dac
)
, stock as (
  select
    date_format(date_add('month',1,date_parse(c.periodo,'%Y%m')), '%Y%m') as periodo_meta
  , c.id_loan
  , f.saldo as saldo_inicial
  , case when c.mora between 1 and 8  then 'a. 1-8'
         when c.mora between 9 and 15 then 'b. 9-15'
         else                              'c. 16-30' end as tramo
  , case when f.saldo >= 0.9*f.amountfinanced then 'a. avance <10%'
         when f.saldo >= 0.6*f.amountfinanced then 'b. avance 10-40%'
         when f.saldo >= 0.3*f.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from dac_cierre c
  join fotos f on f.id_loan = c.id_loan and f.fechaproceso = c.fechaproceso
  where c.rn = 1 and c.mora between 1 and 30 and f.saldo > 0
)
, rebajes as (
  select s.periodo_meta, s.tramo, s.avance_band, s.id_loan, s.saldo_inicial, f.dia,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
  where s.periodo_meta between '202504' and '202606'
)
, primer_pago as (
  select periodo_meta, tramo, avance_band, id_loan, saldo_inicial, min(dia) as dia_primer_pago
  from rebajes where pago_flag = 1
  group by 1,2,3,4,5
)
, saldo_total as (
  select tramo, avance_band, sum(saldo_inicial) as saldo_total, count(*) as creditos_total
  from stock where periodo_meta between '202504' and '202606'
  group by 1,2
)
, activado_por_dia as (
  select tramo, avance_band, dia_primer_pago as dia, sum(saldo_inicial) as saldo_activado_dia
  from primer_pago group by 1,2,3
)
select
  a.tramo, a.avance_band, a.dia
, round(sum(a.saldo_activado_dia) over (partition by a.tramo, a.avance_band order by a.dia) / t.saldo_total * 100, 3) as pct_capital_asegurado_acum
, t.saldo_total, t.creditos_total
from activado_por_dia a
join saldo_total t on t.tramo = a.tramo and t.avance_band = a.avance_band
order by 1, 2, 3
;

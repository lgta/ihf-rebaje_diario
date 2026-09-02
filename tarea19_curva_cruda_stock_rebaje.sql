-- =====================================================================
-- TAREA 18e -- MATRIZ CRUDA DE REBAJE DE "STOCK" (Recupero Oficial), SIN
-- AGREGAR. Analoga a tarea18g_curva_cruda_stock.sql (Enfoque alfa), pero
-- con REBAJE real acumulado (suma de max(saldo_ant-saldo,0) en CADA dia
-- con pago, no solo el dia del PRIMER pago del mes). Grano minimo:
--
--     (periodo_meta, tramo, avance_band, dia) -> rebaje, creditos
--
-- se consume DIRECTO con `curvas_crudas_stock.py` (sin modificar ese
-- modulo -- mismo motivo que la matriz de nuevos: el IPF trata "saldo"
-- de la fila tipo='act' como masa observada, no le importa si es
-- "activo su primer pago" o "bajo tanto de saldo").
--
-- Todo lo demas es IDENTICO a Fase B de esta tarea
-- (tarea18e_fase_b_curva_stock_rebaje.sql): stock = dias_atraso_cuota
-- 1-30 al cierre del mes anterior, mismo saldo de referencia.
--
-- Ventana ampliada respecto de Fase B (202504-202606) para cubrir el
-- walk-forward de 12 meses rodantes x 7 meses de test, igual rango que
-- tarea18g_curva_cruda_stock.sql: periodo_meta 202501-202606.
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
  where a.fechaproceso between '20241125' and '20260801'
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
  where c.fecha_calendario between date('2024-11-25') and date('2026-07-31')
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
    case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from stock s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
  where s.periodo_meta between '202501' and '202607'
)
, rebaje_dia as (
  select periodo_meta, tramo, avance_band, dia
       , sum(rebaje) as rebaje_dia
       , sum(case when rebaje > 0 then 1 else 0 end) as creditos_con_rebaje
  from rebajes
  where rebaje > 0
  group by 1, 2, 3, 4
)
, saldo_total as (
  select periodo_meta, tramo, avance_band, sum(saldo_inicial) as saldo_total, count(*) as creditos_total
  from stock where periodo_meta between '202501' and '202607'
  group by 1, 2, 3
)
select 'base' as tipo, t.periodo_meta, t.tramo, t.avance_band, -1 as dia
     , round(t.saldo_total, 2) as saldo, t.creditos_total as creditos
from saldo_total t
union all
select 'act' as tipo, r.periodo_meta, r.tramo, r.avance_band, r.dia
     , round(r.rebaje_dia, 2) as saldo, r.creditos_con_rebaje as creditos
from rebaje_dia r
order by 2, 3, 4, 5
;

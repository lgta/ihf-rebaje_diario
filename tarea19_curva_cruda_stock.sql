-- =====================================================================
-- TAREA 18g -- MATRIZ CRUDA DE ACTIVACION DE "STOCK", SIN AGREGAR
--
-- Extiende tarea17_fase4_curva_stock.sql (Q-C) para que NO colapse
-- `periodo_meta` en la agregacion final -- el mismo cambio de diseno que
-- tarea18f_curva_cruda.sql ya hizo para "nuevos". Con `periodo_meta`
-- preservado en el grano se puede, en Python y sin volver a Athena:
--
--   - reconstruir la curva de produccion (agrupando todos los periodos)
--   - rodar la ventana de calibracion [M-12, M-1] por mes de test (18c,
--     que hoy sigue con ventana fija 202504-202606)
--   - reagrupar por DIAS-PARA-FIN-DE-MES real en vez de numero de dia
--     fijo (18b/18g: el hallazgo de que el pico de pago es el ULTIMO DIA
--     REAL del mes, no dia calendario 30/31 -- misma fecha_pago = dia_
--     entrada + k que en nuevos, pero aca "dia" ES la fecha directamente
--     porque stock no tiene un dia de entrada dentro del mes, arranca
--     el 1 con mora 1-30 ya acumulada)
--
-- Todo lo demas es IDENTICO a Q-C (misma definicion de stock, mismo
-- saldo de referencia, mismos filtros de universo, mismo criterio de
-- "primer pago" del mes).
--
-- Ventana ampliada respecto de Q-C (202504-202606) para cubrir los 7
-- walk-forward de 12 meses rodantes que 18b/18f ya usan para nuevos:
-- periodo_meta 202501-202606 (calibra [202501..202512] para testear
-- 202601, hasta [202507..202606] para testear 202607).
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
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from stock s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
  where s.periodo_meta between '202501' and '202607'
)
, primer_pago as (
  select periodo_meta, tramo, avance_band, id_loan, saldo_inicial, min(dia) as dia_primer_pago
  from rebajes where pago_flag = 1
  group by 1,2,3,4,5
)
, saldo_total as (
  select periodo_meta, tramo, avance_band, sum(saldo_inicial) as saldo_total, count(*) as creditos_total
  from stock where periodo_meta between '202501' and '202607'
  group by 1,2,3
)
, activado_por_dia as (
  select periodo_meta, tramo, avance_band, dia_primer_pago as dia, sum(saldo_inicial) as saldo_activado_dia
  from primer_pago group by 1,2,3,4
)
select 'base' as tipo, t.periodo_meta, t.tramo, t.avance_band, -1 as dia
     , round(t.saldo_total, 2) as saldo, t.creditos_total as creditos
from saldo_total t
union all
select 'act' as tipo, a.periodo_meta, a.tramo, a.avance_band, a.dia
     , round(a.saldo_activado_dia, 2) as saldo, null as creditos
from activado_por_dia a
order by 2,3,4,5
;

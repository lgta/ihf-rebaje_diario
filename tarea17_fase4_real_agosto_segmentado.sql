-- =====================================================================
-- TAREA 17 FASE 4 -- Real de agosto ABIERTO POR SEGMENTO, universo
-- unificado. Alimenta la seccion 05 del artifact de capital asegurado
-- ("de donde viene la diferencia del mes"), que antes se calculaba sobre
-- la arquitectura de 3 componentes (datos_volumen_efectividad_agosto/).
--
-- stock  -> segmento = (tramo, avance_band) al cierre de julio
-- nuevos -> segmento = avance_band al momento de la entrada (saldo_ant)
-- Sale el acumulado hasta el dia 21 y hasta el 24 (mismos 2 cortes que
-- meta_agosto_capital_asegurado.py).
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_dedup as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , b.amountfinanced
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260725' and '20260825'
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, fotos as (
  select id_loan, fechaproceso, substr(fechaproceso,1,6) as periodo,
    cast(substr(fechaproceso,7,2) as int) as dia, saldo, amountfinanced,
    lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  from mambu_dedup where rn_dedup = 1
)
, dac as (
  select d.id_ihfintech_loan as id_loan
       , date_format(d.fecha_calendario,'%Y%m%d') as fechaproceso
       , coalesce(d.dias_atraso_cuota,0) as mora
  from dts_cobranza_creditos_calendario_diario d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_ihfintech_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_ihfintech_loan
  where d.fecha_calendario between date('2026-07-01') and date('2026-08-25')
    and b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1) = 1
)
, dac_lag as (
  select id_loan, fechaproceso, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant,
    row_number() over (partition by id_loan order by fechaproceso) as nro_foto
  from dac
)
, stock_base as (
  select id_loan, mora, saldo_inicial, amountfinanced from (
    select d.id_loan, d.mora, f.saldo as saldo_inicial, f.amountfinanced,
      row_number() over (partition by d.id_loan order by d.fechaproceso desc) as rn
    from dac d
    join fotos f on f.id_loan = d.id_loan and f.fechaproceso = d.fechaproceso
    where substr(d.fechaproceso,1,6) = '202607'
  )
  where rn = 1 and mora between 1 and 30 and saldo_inicial > 0
)
, stock_seg as (
  select id_loan, saldo_inicial
  , case when mora between 1 and 8 then 'a. 1-8'
         when mora between 9 and 15 then 'b. 9-15'
         else 'c. 16-30' end as tramo
  , case when saldo_inicial >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo_inicial >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo_inicial >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from stock_base
)
, real_stock as (
  select 'stock' as componente, s.tramo, s.avance_band, s.id_loan,
    max(s.saldo_inicial) as saldo, min(f.dia) as dia
  from stock_seg s
  join fotos f on f.id_loan = s.id_loan and f.periodo = '202608'
  where f.saldo_ant > f.saldo
  group by 1,2,3,4
)
, entradas as (
  select l.id_loan, l.fechaproceso as fecha_entrada
  from dac_lag l
  where l.nro_foto > 1 and l.mora_ant = 0 and l.mora = 1
    and substr(l.fechaproceso,1,6) = '202608'
    and not exists (select 1 from stock_base s where s.id_loan = l.id_loan)
)
, entradas_seg as (
  select e.id_loan, e.fecha_entrada, coalesce(f.saldo_ant, f.saldo) as saldo
  , case when coalesce(f.saldo_ant,f.saldo) >= 0.9*f.amountfinanced then 'a. avance <10%'
         when coalesce(f.saldo_ant,f.saldo) >= 0.6*f.amountfinanced then 'b. avance 10-40%'
         when coalesce(f.saldo_ant,f.saldo) >= 0.3*f.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.fechaproceso = e.fecha_entrada
  where coalesce(f.saldo_ant, f.saldo) > 0
)
, real_nuevos as (
  select 'nuevos' as componente, '' as tramo, e.avance_band, e.id_loan,
    max(e.saldo) as saldo, min(f.dia) as dia
  from entradas_seg e
  join fotos f on f.id_loan = e.id_loan
    and f.periodo = '202608' and f.fechaproceso >= e.fecha_entrada
  where f.saldo_ant > f.saldo
  group by 1,2,3,4
)
select componente, tramo, avance_band
, count(*)                                                            as creditos_activados
, round(sum(case when dia <= 21 then saldo else 0 end), 2)            as real_al_21
, round(sum(case when dia <= 24 then saldo else 0 end), 2)            as real_al_24
from (select * from real_stock union all select * from real_nuevos)
group by 1,2,3
order by 1,2,3
;

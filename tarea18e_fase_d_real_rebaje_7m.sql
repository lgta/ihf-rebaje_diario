-- =====================================================================
-- TAREA 18e, FASE D -- REAL DIARIO EN REBAJE (Recupero Oficial), 7
-- MESES (ene-jul 2026), separado stock/nuevos, con dias_atraso_cuota.
--
-- Analoga a tarea18_real_stock_7m.sql / tarea18_real_nuevos_7m.sql
-- (Q-F1/Q-F2 de tarea 17 Fase 4), pero mide REBAJE real acumulado
-- (max(saldo_ant-saldo,0) sumado dia a dia), no activacion binaria --
-- es la medida que necesita Recupero Oficial, no Capital Asegurado.
-- Poblacion identica a Q-E/Q-F1/Q-F2: stock = dias_atraso_cuota 1-30 al
-- cierre del mes anterior; nuevos = dias_atraso_cuota 0->1 dentro del
-- mes, excluyendo el stock del mes. saldo_entrada de nuevos = saldo del
-- dia ANTERIOR a la entrada (fix de Fase 3, bug 16), rango de busqueda
-- de pago incluye el dia 0 -- mismo patron que Fase B/C de esta tarea.
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
  where a.fechaproceso between '20251225' and '20260731'
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, fotos as (
  select id_loan, fechaproceso, substr(fechaproceso,1,6) as periodo,
    cast(substr(fechaproceso,7,2) as int) as dia, saldo,
    lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  from mambu_dedup where rn_dedup = 1
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2025-12-01') and date('2026-07-31')
)
, dac as (
  select d.id_loan, d.fechaproceso, d.mora
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, dac_lag as (
  select id_loan, fechaproceso, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant,
    row_number() over (partition by id_loan order by fechaproceso) as nro_foto
  from dac
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
  from dac_cierre c
  join fotos f on f.id_loan = c.id_loan and f.fechaproceso = c.fechaproceso
  where c.rn = 1 and c.mora between 1 and 30 and f.saldo > 0
    and c.periodo between '202512' and '202606'
)
, real_stock as (
  select 'stock' as componente, s.periodo_meta as periodo, f.dia
       , sum(case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end) as rebaje_dia
  from stock s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
  group by 1, 2, 3
)
, stock_ids as (
  select date_format(date_add('month',1,date_parse(periodo,'%Y%m')), '%Y%m') as periodo_target, id_loan
  from dac_cierre where rn = 1 and mora between 1 and 30
)
, entradas as (
  select l.id_loan, l.fechaproceso as fecha_entrada,
    substr(l.fechaproceso,1,6) as periodo_meta
  from dac_lag l
  where l.nro_foto > 1 and l.mora_ant = 0 and l.mora = 1
    and substr(l.fechaproceso,1,6) between '202601' and '202607'
    and not exists (
      select 1 from stock_ids st
      where st.periodo_target = substr(l.fechaproceso,1,6) and st.id_loan = l.id_loan
    )
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada, e.periodo_meta
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.fechaproceso = e.fecha_entrada
  where coalesce(f.saldo_ant, f.saldo) > 0
)
, real_nuevos as (
  select 'nuevos' as componente, e.periodo_meta as periodo, f.dia
       , sum(case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end) as rebaje_dia
  from entradas_saldo e
  join fotos f on f.id_loan = e.id_loan
    and f.periodo = e.periodo_meta
    and f.fechaproceso >= e.fecha_entrada
  group by 1, 2, 3
)
select componente, periodo, dia, round(rebaje_dia, 2) as rebaje_dia
from (select * from real_stock union all select * from real_nuevos)
order by 1, 2, 3
;

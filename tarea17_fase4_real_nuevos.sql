-- =====================================================================
-- TAREA 17, FASE 4 -- Q-F2: REAL ACTIVADO POR DIA, componente NUEVOS,
-- abr/may/jun/jul 2026. Reemplaza bt_real_aseg_nuevos.csv Y
-- bt_real_fantasma_*.csv (los dos componentes se fusionan en uno).
--
-- Poblacion: entradas detectadas por dias_atraso_cuota (0->1) DENTRO
-- del mes, excluyendo el stock del mes. Incluye el dia 1 (bug 12 ya no
-- aplica: esa cohorte es "nuevos" legitimo bajo el calendario
-- frontier-adjusted) y las entradas que se resuelven el mismo dia (la
-- ex-poblacion fantasma).
--
-- Saldo de referencia = saldo del dia ANTERIOR a la entrada (saldo_ant),
-- consistente con la curva de Q-B -- fix de Fase 3 (bug 16): para la
-- poblacion que paga el mismo dia, la foto del dia de entrada ya
-- refleja el pago.
-- La busqueda de pago incluye el DIA 0 (la fecha de entrada misma), por
-- la misma razon.
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
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260325' and '20260731'
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
  where c.fecha_calendario between date('2026-03-01') and date('2026-07-31')
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
  select substr(fechaproceso,1,6) as periodo, id_loan, mora,
    row_number() over (partition by id_loan, substr(fechaproceso,1,6)
                       order by fechaproceso desc) as rn
  from dac
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
    and substr(l.fechaproceso,1,6) between '202604' and '202607'
    and not exists (
      select 1 from stock_ids s
      where s.periodo_target = substr(l.fechaproceso,1,6) and s.id_loan = l.id_loan
    )
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada, e.periodo_meta,
    coalesce(f.saldo_ant, f.saldo) as saldo_entrada
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.fechaproceso = e.fecha_entrada
  where coalesce(f.saldo_ant, f.saldo) > 0
)
, primer_pago as (
  select e.periodo_meta, e.id_loan, e.saldo_entrada, min(f.dia) as dia_primer_pago
  from entradas_saldo e
  join fotos f on f.id_loan = e.id_loan
    and f.periodo = e.periodo_meta
    and f.fechaproceso >= e.fecha_entrada
  where f.saldo_ant > f.saldo
  group by 1,2,3
)
select periodo_meta, dia_primer_pago as dia, round(sum(saldo_entrada),2) as saldo_activado_dia
from primer_pago
group by 1,2
order by 1,2
;

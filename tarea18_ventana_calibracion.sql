-- =====================================================================
-- TAREA 18 -- ¿CUANTA HISTORIA ES USABLE PARA CALIBRAR, Y DESDE CUANDO?
--
-- Pregunta que responde: el proyecto calibra hoy con
-- `fechaproceso 20250301-20260531` (15 meses) y testea sobre abril-julio
-- 2026, con mayo y junio DENTRO de la ventana de calibracion (leak
-- medido en tarea 10, 0.15-0.2pp). Antes de fijar un protocolo de
-- calibracion/test hay que saber dos cosas que nadie midio todavia:
--
--   1. VOLUMEN: desde que mes el portafolio es lo bastante grande como
--      para que un mes de entradas sea representativo. Fase 3 descarto
--      la historia completa 2023-10+ a ojo ("~1000x mas chico"); aca se
--      mide.
--   2. FORMA: si la curva de nuevos DERIVA mes a mes. Si es estable, la
--      ventana puede ser larga y el leak importa poco; si deriva, hay
--      que acortarla y el leak importa mucho.
--
-- Emite, por MES DE ENTRADA en mora (definicion unificada de Fase 4:
-- dias_atraso_cuota 0->1), el tamano de la cohorte y la curva evaluada
-- en los dias 0, 1, 7 y 30 desde la entrada.
--
-- OJO al leer: la cohorte de un mes necesita 31 dias de seguimiento
-- posterior. Los ultimos ~2 meses de la ventana tienen dia_30
-- incompleto -- la columna `dias_seguimiento_disp` lo marca.
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
  where a.fechaproceso between '20231001' and '20260825'
)
, mambu_dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from mambu_raw
)
, mambu_fotos as (
  select d.id_loan, d.fechaproceso, d.saldo, b.amountfinanced
  from mambu_dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, mambu_lag as (
  select id_loan, fechaproceso, saldo, amountfinanced,
    lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  from mambu_fotos
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2023-10-01') and date('2026-08-25')
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
, entradas as (
  select id_loan, fechaproceso as fecha_entrada,
    date_parse(fechaproceso, '%Y%m%d') as fecha_entrada_d
  from dac_lag
  where nro_foto > 1 and mora_ant = 0 and mora = 1
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada, e.fecha_entrada_d
  , substr(e.fecha_entrada, 1, 6) as mes_entrada
  , coalesce(ml.saldo_ant, ml.saldo) as saldo_entrada
  from entradas e
  join mambu_lag ml on ml.id_loan = e.id_loan and ml.fechaproceso = e.fecha_entrada
  where coalesce(ml.saldo_ant, ml.saldo) > 0
)
, pagos as (
  select e.id_loan, e.mes_entrada, e.saldo_entrada,
    date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_saldo e
  join mambu_lag f on f.id_loan = e.id_loan
    and f.fechaproceso >= e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, primer_pago as (
  select id_loan, mes_entrada, saldo_entrada, min(dia_desde_entrada) as dia_primer_pago
  from pagos where pago_flag = 1
  group by 1,2,3
)
, base as (
  select mes_entrada, sum(saldo_entrada) as saldo_total, count(*) as entradas
  from entradas_saldo group by 1
)
select
  b.mes_entrada
, b.entradas
, round(b.saldo_total, 0)                                        as saldo_entrada_total
, round(100.0 * sum(case when p.dia_primer_pago <= 0  then p.saldo_entrada else 0 end) / b.saldo_total, 3) as dia_0
, round(100.0 * sum(case when p.dia_primer_pago <= 1  then p.saldo_entrada else 0 end) / b.saldo_total, 3) as dia_1
, round(100.0 * sum(case when p.dia_primer_pago <= 7  then p.saldo_entrada else 0 end) / b.saldo_total, 3) as dia_7
, round(100.0 * sum(case when p.dia_primer_pago <= 30 then p.saldo_entrada else 0 end) / b.saldo_total, 3) as dia_30
, date_diff('day', date_parse(b.mes_entrada || '01', '%Y%m%d'), date('2026-08-25'))  as dias_seguimiento_disp
from base b
left join primer_pago p on p.mes_entrada = b.mes_entrada
group by b.mes_entrada, b.entradas, b.saldo_total
order by 1
;

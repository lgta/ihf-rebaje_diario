-- =====================================================================
-- TAREA 18e -- MATRIZ CRUDA DE REBAJE DE "NUEVOS" (Recupero Oficial),
-- SIN AGREGAR. Analoga a tarea18f_curva_cruda.sql (Enfoque alfa), pero
-- con REBAJE real acumulado (suma de max(saldo_ant-saldo,0) en CADA dia
-- con pago, no solo el dia del PRIMER pago) -- es la magnitud que
-- necesita Recupero Oficial. El grano minimo:
--
--     (fecha_entrada, avance_band, dia_desde_entrada) -> rebaje, creditos
--
-- se consume DIRECTO con `curvas_crudas.py` (sin modificar ese modulo:
-- el IPF trata "saldo" de la fila tipo='act' como masa observada en la
-- celda, sea "activo su primer pago" o "bajo tanto de saldo" -- misma
-- mecanica). De ahi, en Python y sin volver a Athena:
--   - la curva por avance_band
--   - la curva por dia de semana del vencimiento
--   - el factor por dia del mes DE PAGO
--   - cualquier VENTANA RODANTE (filtrando fecha_entrada)
--
-- Todo lo demas es IDENTICO a Fase C de esta tarea
-- (tarea18e_fase_c_curva_nuevos_rebaje.sql): entrada = dias_atraso_cuota
-- 0->1, saldo_entrada = saldo del dia ANTERIOR a la entrada (fix Fase 3,
-- bug 16), busqueda de pago incluye el dia 0.
--
-- Ventana ampliada respecto de Fase C (20250301-20260531) para cubrir
-- el walk-forward de 12 meses rodantes x 7 meses de test, igual rango
-- que tarea18f_curva_cruda.sql: entradas 20250101-20260630.
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
  where a.fechaproceso between '20241225' and '20260801'
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
  where c.fecha_calendario between date('2024-12-25') and date('2026-06-30')
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
    and fechaproceso between '20250101' and '20260630'
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada, e.fecha_entrada_d
  , coalesce(ml.saldo_ant, ml.saldo) as saldo_entrada
  , case when coalesce(ml.saldo_ant, ml.saldo) >= 0.9*ml.amountfinanced then 'a. avance <10%'
         when coalesce(ml.saldo_ant, ml.saldo) >= 0.6*ml.amountfinanced then 'b. avance 10-40%'
         when coalesce(ml.saldo_ant, ml.saldo) >= 0.3*ml.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from entradas e
  join mambu_lag ml on ml.id_loan = e.id_loan and ml.fechaproceso = e.fecha_entrada
  where coalesce(ml.saldo_ant, ml.saldo) > 0
)
, rebajes as (
  -- OJO: `fecha_entrada` viaja en el grano (mismo motivo que 18f: un
  -- credito puede entrar en mora varias veces en la ventana).
  select e.id_loan, e.fecha_entrada, e.avance_band, e.saldo_entrada,
    date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from entradas_saldo e
  join mambu_lag f on f.id_loan = e.id_loan
    and f.fechaproceso >= e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, rebaje_dia as (
  select fecha_entrada, avance_band, dia_desde_entrada
       , sum(rebaje) as rebaje_dia
       , sum(case when rebaje > 0 then 1 else 0 end) as creditos_con_rebaje
  from rebajes
  where rebaje > 0
  group by 1, 2, 3
)
select 'base' as tipo, e.fecha_entrada, e.avance_band, -1 as dia
     , round(sum(e.saldo_entrada), 2) as saldo, count(*) as creditos
from entradas_saldo e
group by 1, 2, 3, 4
union all
select 'act' as tipo, r.fecha_entrada, r.avance_band, r.dia_desde_entrada as dia
     , round(r.rebaje_dia, 2) as saldo, r.creditos_con_rebaje as creditos
from rebaje_dia r
order by 2, 3, 4
;

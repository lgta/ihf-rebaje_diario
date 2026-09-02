-- =====================================================================
-- TAREA 18f -- MATRIZ CRUDA DE ACTIVACION DE "NUEVOS", SIN AGREGAR
--
-- Una sola corrida de Athena que reemplaza a TODAS las calibraciones de
-- la curva de nuevos que haga falta de aca en adelante. En vez de emitir
-- una curva ya agregada (como Q-B de produccion o tarea18a_*), emite el
-- grano minimo:
--
--     (fecha_entrada, avance_band, dia_primer_pago) -> saldo, creditos
--
-- De ahi se deriva EN PYTHON, sin volver a consultar:
--   - la curva por avance_band            (agrupando fecha_entrada)
--   - la curva por dia de semana           (dow del vencimiento = fecha_entrada - 1)
--   - el factor por dia del mes DE PAGO    (day(fecha_entrada + dia_primer_pago)) <- 18f
--   - cualquier VENTANA RODANTE de calibracion (filtrando fecha_entrada)
--
-- Eso ultimo es lo que hace barato el walk-forward: calibrar [M-12, M-1]
-- para cada mes de test M no cuesta 7 corridas, cuesta 0 adicionales.
--
-- Filas `tipo='base'` (dia = -1): denominador de cada (fecha_entrada,
-- avance_band). Van aparte y no como columna repetida porque una cohorte
-- que no paga en 31 dias no genera ninguna fila de activacion y aun asi
-- tiene que contar en el denominador.
--
-- Ventana: entradas 20250101-20260630. Cubre calibrar [202501..202512]
-- para testear 202601, hasta [202507..202606] para testear 202607 --
-- los 7 meses de test que la historia permite con piso de 3,000
-- entradas/mes (ver tarea18_ventana_calibracion.sql).
--
-- Todo lo demas es IDENTICO a la Q-B de produccion
-- (tarea17_fase4_curva_nuevos.sql): misma definicion de entrada
-- (dias_atraso_cuota 0->1), mismo saldo de referencia (saldo del dia
-- ANTERIOR a la entrada, fix de Fase 3), mismos filtros de universo.
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
  where a.fechaproceso between '20241225' and '20260901'
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
  where c.fecha_calendario between date('2024-12-25') and date('2026-07-31')
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
    and fechaproceso between '20250101' and '20260731'
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
, pagos as (
  -- OJO: `fecha_entrada` viaja en el grano. Un mismo credito puede entrar
  -- en mora VARIAS veces dentro de la ventana, y cada episodio es una
  -- cohorte distinta con su propio dia 0. Agrupar por id_loan solo
  -- (o cruzar por id_loan solo) mezcla episodios: se vio en la primera
  -- corrida de esta query, con celdas donde los creditos activados
  -- superaban a los de la base.
  select e.id_loan, e.fecha_entrada, e.avance_band, e.saldo_entrada,
    date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas_saldo e
  join mambu_lag f on f.id_loan = e.id_loan
    and f.fechaproceso >= e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, primer_pago as (
  select id_loan, fecha_entrada, avance_band, saldo_entrada,
    min(dia_desde_entrada) as dia_primer_pago
  from pagos where pago_flag = 1
  group by 1,2,3,4
)
select 'base' as tipo, e.fecha_entrada, e.avance_band, -1 as dia
     , round(sum(e.saldo_entrada), 2) as saldo, count(*) as creditos
from entradas_saldo e
group by 1,2,3,4
union all
select 'act' as tipo, e.fecha_entrada, e.avance_band, cast(p.dia_primer_pago as int) as dia
     , round(sum(e.saldo_entrada), 2) as saldo, count(*) as creditos
from entradas_saldo e
join primer_pago p on p.id_loan = e.id_loan and p.fecha_entrada = e.fecha_entrada
group by 1,2,3,4
order by 2,3,4
;

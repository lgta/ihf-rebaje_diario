-- =====================================================================
-- ENFOQUE ALFA - "CAPITAL ASEGURADO"
-- Ejecutado 2026-07-10 en Athena (db dev_datalake_master). Ver
-- enfoque_capital_asegurado.md para la explicacion completa.
--
-- Concepto: no mide cuantos soles se recuperan (eso lo hace la meta
-- oficial de rebaje/recupero) -- mide cuanto del capital ASIGNADO
-- pertenece a creditos que muestran AL MENOS 1 dia de pago en el mes,
-- ponderado por el saldo COMPLETO del credito (no por lo que pago).
-- Ejemplo del usuario: credito A saldo S/12,000 paga S/50 -> aporta
-- S/12,000 completos al capital asegurado (no S/50). Credito B saldo
-- S/8,000 no paga nada -> aporta S/0.
--
-- Mismas CTEs base y mismos filtros (status, flg_last_loan_in_chain)
-- que fase1_stock.sql / fase2_nuevos.sql -- ver FUENTES_DATOS.md.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. STOCK - curva de capital asegurado, tramo x avance x dia.
-- Resultado en datos_capital_asegurado/curva_asegurado_stock_seg.csv.
-- Dia 31 (final) por segmento, ver enfoque_capital_asegurado.md.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    substr(a.fechaproceso, 1, 6)                       as periodo
  , a.fechaproceso
  , cast(substr(a.fechaproceso, 7, 2) as int)          as dia
  , a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
  , a.balances_principalbalance                        as saldo
  , coalesce(a.dayslate, 0)                            as mora
  , b.amountfinanced
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b
    on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc
    on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso >= '20250301'
    and coalesce(lc.last_in_chain, 1) = 1
)
, cierre_mes as (
  select *, row_number() over (partition by id_loan, periodo order by fechaproceso desc) as rn
  from fotos
)
, stock as (
  select
    date_format(date_add('month', 1, date_parse(periodo, '%Y%m')), '%Y%m') as periodo_meta
  , id_loan
  , saldo as saldo_inicial
  , case when mora between 1 and 8  then 'a. 1-8'
         when mora between 9 and 15 then 'b. 9-15'
         else                            'c. 16-30' end as tramo
  , case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from cierre_mes
  where rn = 1 and mora between 1 and 30 and saldo > 0 and amountfinanced > 0
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
  from rebajes
  where pago_flag = 1
  group by 1,2,3,4,5
)
, saldo_total as (
  select tramo, avance_band, sum(saldo_inicial) as saldo_total, count(*) as creditos_total
  from stock
  where periodo_meta between '202504' and '202606'
  group by 1,2
)
, activado_por_dia as (
  select tramo, avance_band, dia_primer_pago as dia, sum(saldo_inicial) as saldo_activado_dia
  from primer_pago
  group by 1,2,3
)
select
  a.tramo, a.avance_band, a.dia
, round(sum(a.saldo_activado_dia) over (partition by a.tramo, a.avance_band order by a.dia) / t.saldo_total * 100, 3) as pct_capital_asegurado_acum
, t.saldo_total, t.creditos_total
from activado_por_dia a
join saldo_total t on t.tramo = a.tramo and t.avance_band = a.avance_band
order by 1, 2, 3
;

-- ---------------------------------------------------------------------
-- Q2. NUEVOS - curva de capital asegurado, avance x dias desde entrada
-- (misma definicion de "entrada" -- dayslate 0->1 -- que fase2_nuevos.sql,
-- por eso la misma tasa P(no paga)=13.38% es consistente con esta curva).
-- Resultado en datos_capital_asegurado/curva_asegurado_nuevos_seg.csv.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
  , a.fechaproceso
  , a.balances_principalbalance                        as saldo
  , coalesce(a.dayslate,0)                              as mora
  , lag(coalesce(a.dayslate,0)) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as mora_ant
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as saldo_ant
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as nro_foto
  , b.amountfinanced
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b
    on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc
    on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso >= '20250301'
    and coalesce(lc.last_in_chain, 1) = 1
)
, entradas as (
  select id_loan, fechaproceso as fecha_entrada,
    date_parse(fechaproceso, '%Y%m%d') as fecha_entrada_d,
    saldo as saldo_entrada, amountfinanced,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from fotos
  where nro_foto > 1 and mora_ant = 0 and mora = 1
    and fechaproceso between '20250301' and '20260531'
    and amountfinanced > 0
)
, pagos as (
  select e.id_loan, e.avance_band, e.saldo_entrada,
    date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then 1 else 0 end as pago_flag
  from entradas e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, primer_pago as (
  select id_loan, avance_band, saldo_entrada, min(dia_desde_entrada) as dia_primer_pago
  from pagos
  where pago_flag = 1
  group by 1,2,3
)
, base_total as (
  select avance_band, sum(saldo_entrada) as saldo_entrada_total, count(*) as entradas
  from entradas group by 1
)
, activado_por_dia as (
  select avance_band, dia_primer_pago as dia, sum(saldo_entrada) as saldo_activado_dia
  from primer_pago
  group by 1,2
)
select
  a.avance_band, a.dia
, round(sum(a.saldo_activado_dia) over (partition by a.avance_band order by a.dia) / b.saldo_entrada_total * 100, 3) as pct_capital_asegurado_acum
, b.saldo_entrada_total, b.entradas
from activado_por_dia a
join base_total b on b.avance_band = a.avance_band
order by 1, 2
;

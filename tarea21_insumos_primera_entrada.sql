-- =====================================================================
-- TAREA 21 -- INSUMOS DE LA VARIANTE "PRIMERA ENTRADA" -- septiembre 2026
--
-- Pedido del usuario (2026-09-02). NO reemplaza a la meta vigente: es una
-- SEGUNDA version, para comparar contra ella.
--
-- LA REGLA DEL UNIVERSO, en una linea: cada credito entra al universo del
-- mes UNA SOLA VEZ, por su PRIMERA entrada en mora.
--
--   - Si ya estaba en mora al cierre del mes anterior -> es ANTIGUO, y no
--     aparece en el calendario aunque tenga vencimientos en el mes. Esto
--     la meta vigente YA lo hace (`not in stock_agosto`), y no es menor:
--     medido en tarea21_diagnostico_doble_entrada.sql son S/3,703,671 de
--     septiembre, el 92% de los creditos del stock.
--   - Si NO estaba en mora, entra por su PRIMER vencimiento del mes. Los
--     vencimientos 2do y posteriores del MISMO credito se descartan.
--     Esto es lo NUEVO de esta variante: `rn_venc = 1`.
--
-- POR QUE IMPORTA aunque en septiembre sea chico (S/6,545.67, 0.007%):
--
--   1. El tamano depende del mes. La ventana del calendario va del ULTIMO
--      dia del mes anterior al PENULTIMO del mes (porque se indexa por
--      entrada = vencimiento + 1). Cuando el mes anterior es corto, esa
--      ventana atrapa DOS vencimientos mensuales del mismo credito: en
--      202603 (despues de un febrero de 28 dias) y en 202607 el calendario
--      corre +12.7% y +12.9% sobre el universo deduplicado. Septiembre se
--      salva por casualidad de calendario, no por diseno.
--
--   2. Cierra la inconsistencia de PENDIENTES.md tarea 20. `P_ENTRADA`
--      (tasa_soles.csv) SI deduplica a un vencimiento por credito-mes
--      (`rn = 1`), pero hoy se aplica sobre un calendario que NO
--      deduplica. Con esta variante la tasa y el universo sobre el que se
--      multiplica comparten definicion, que es lo que exige el "principio
--      de modelado" de CLAUDE.md.
--
-- LO QUE ESTA VARIANTE NO ARREGLA (dicho para no venderla de mas): la
-- CURVA de nuevos sigue calibrada sobre la matriz cruda, que cuenta cada
-- evento de entrada y no deduplica por credito-mes. Para que la variante
-- fuera consistente de punta a punta habria que recalibrar la curva sobre
-- entradas deduplicadas -- una corrida mas de Athena, anotada como
-- pendiente. La curva es una FORMA (% del capital entrado que ya activo),
-- asi que el efecto esperado es de segundo orden, pero no es cero.
--
-- Fuera de `rn_venc = 1`, reproduce EXACTO tarea19_meta_septiembre_insumos.sql
-- -- mismo ancla al 31-ago, mismo stock, mismos filtros -- para que las dos
-- metas sean comparables sin ruido de construccion.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_ago as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , b.amountfinanced
  , b.status
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260801' and '20260831'
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, ancla as (
  select id_loan, saldo, amountfinanced, status,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from mambu_ago where rn_dedup = 1
)
, ancla_final as (
  select id_loan, saldo, amountfinanced, status from ancla where rn = 1 and saldo > 0
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-08-01') and date('2026-08-31')
)
, dac_cierre as (
  select d.id_loan, d.mora,
    row_number() over (partition by d.id_loan order by d.fechaproceso desc) as rn
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, stock_agosto as (
  select c.id_loan, c.mora, a.saldo, a.amountfinanced
  from dac_cierre c
  join ancla_final a on a.id_loan = c.id_loan
  where c.rn = 1 and c.mora between 1 and 30
    and a.status in ('ACTIVE','COMPLETED')
)
-- calendario ya sin los creditos del stock, numerando los vencimientos que
-- le quedan a cada credito dentro del mes
, cal_rn as (
  select
    c.id_ihfintech_loan as id_loan
  , cast(day(date_add('day',1,c.fechavencimiento)) as int) as dia_entrada
  , a.saldo
  , a.amountfinanced
  , row_number() over (partition by c.id_ihfintech_loan order by c.fechavencimiento) as rn_venc
  from dts_cobranza_creditos_cuotas c
  join ancla_final a on a.id_loan = c.id_ihfintech_loan
  where c.status = 'ACTIVE'
    and c.flg_last_loan_in_chain = 1
    and a.status = 'ACTIVE'
    and date_add('day',1,c.fechavencimiento) >= date('2026-09-01')
    and date_add('day',1,c.fechavencimiento) <= date('2026-09-30')
    and c.id_ihfintech_loan not in (select id_loan from stock_agosto)
)
select
  'stock' as tipo
, case when s.mora between 1 and 8  then 'a. 1-8'
       when s.mora between 9 and 15 then 'b. 9-15'
       else                              'c. 16-30' end as tramo
, case when s.saldo >= 0.9*s.amountfinanced then 'a. avance <10%'
       when s.saldo >= 0.6*s.amountfinanced then 'b. avance 10-40%'
       when s.saldo >= 0.3*s.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, 0 as dia_entrada
, count(*) as creditos
, round(sum(s.saldo), 2) as saldo
from stock_agosto s
group by 1,2,3,4

union all

select
  'calendario' as tipo
, '' as tramo
, case when r.saldo >= 0.9*r.amountfinanced then 'a. avance <10%'
       when r.saldo >= 0.6*r.amountfinanced then 'b. avance 10-40%'
       when r.saldo >= 0.3*r.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, r.dia_entrada
, count(*) as creditos
, round(sum(r.saldo), 2) as saldo
from cal_rn r
where r.rn_venc = 1
group by 1,2,3,4

union all

-- Los vencimientos 2do y posteriores, aparte. Sirven para dos cosas:
-- (1) reconstruir el calendario de la meta VIGENTE (= calendario +
--     calendario_extra) desde ESTA MISMA corrida, y asi comparar los dos
--     metodos sobre la misma foto de datos;
-- (2) medir el efecto de la deduplicacion sin que lo contamine la
--     re-expresion de dts_mambu_loans_hist, que mueve los totales -0.3%
--     entre un dia y el siguiente (trampa conocida, ver ESTADO.md).
select
  'calendario_extra' as tipo
, '' as tramo
, case when r.saldo >= 0.9*r.amountfinanced then 'a. avance <10%'
       when r.saldo >= 0.6*r.amountfinanced then 'b. avance 10-40%'
       when r.saldo >= 0.3*r.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, r.dia_entrada
, count(*) as creditos
, round(sum(r.saldo), 2) as saldo
from cal_rn r
where r.rn_venc > 1
group by 1,2,3,4
order by 1,4,3
;

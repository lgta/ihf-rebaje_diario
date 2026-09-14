-- =====================================================================
-- TAREA 24 -- CALENDARIO Y TASA DE ENTRADA EN UNA SOLA POBLACION, v1 y v2.
--
-- Reemplaza, para la recalibracion de tarea 24, a DOS queries que ya median
-- la misma poblacion por separado:
--   tarea19_tasa_soles.sql      -> elegibles/entran por mes (la tasa)
--   tarea19_calendario_8m.sql   -> saldo en riesgo por (mes, dia_entrada,
--                                  banda) para el backtest
-- Salir de la misma query hace que tasa y calendario compartan la definicion
-- por construccion (principio de modelado de CLAUDE.md).
--
-- DOS CUOTAS EN EL MISMO MES (BUGS.md bug 23, tarea 21): la ventana del
-- calendario va del ultimo dia del mes anterior al penultimo del mes, asi que
-- cuando el mes anterior es corto atrapa DOS vencimientos del mismo credito (la
-- cuota del 30 del mes anterior entra el dia 1 y la del 30 del mes entra el 31).
-- La tasa de produccion toma UNA cuota por credito-mes (la primera);
-- calendario_8m sumaba TODAS -- 4-13% del saldo en mar/may/jul/oct/dic. Bug 23
-- lo dejo sin adoptar porque en septiembre no ocurre. Por eso el grano lleva el
-- orden de la cuota:
--   orden    : 1 = primera cuota del credito con entrada en el mes, 2 = las demas
--   orden_d2 : lo mismo contando solo las cuotas con entrada desde el DIA 2
--              (0 = la cuota que entra el dia 1). Con v2 la cuota que entra el
--              dia 1 no es calendario, asi que la primera cuota de v2 es la
--              primera con orden_d2 = 1 -- NO la primera del mes.
--
-- Grano: (periodo, dia_entrada, avance_band, st_v1, st_v2, reeng, orden,
--         orden_d2, entra, arrastre)
--   periodo, dia_entrada : mes y dia de la ENTRADA del calendario
--                          (fechavencimiento + 1)
--   st_v1 / st_v2        : el credito es stock de ese mes en v1 / v2 (mismas
--                          definiciones que tarea24_v2_matriz_nuevos.sql)
--   entra                : tuvo una transicion 0 -> 1 de dias_atraso_cuota en
--                          el mes (misma regla que tarea19_tasa_soles.sql)
--   arrastre             : entro, y su DNI tenia otro credito > 30 dias el
--                          dia de la entrada
--   saldo                : saldo Mambu del dia del vencimiento (dedup bug 11)
--
-- Uso:
--   v1 tasa        : st_v1 = 0, reeng = 0, orden = 1  -> reproduce tasa_soles.csv
--   v1 calendario  : st_v1 = 0, reeng = 0, orden 1 y 2 -> como calendario_8m
--                    (como se publico); con orden = 1 -> consistente con la tasa
--   v2 tasa y cal. : st_v2 = 0, reeng = 0, orden_d2 = 1
--   tasa = sum(saldo | entra = 1 [, arrastre = 0]) / sum(saldo)
--
-- Ventana: periodos 202501-202608.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, prestamos as (
  select b.id_ihfintech_loan as id_loan, b.amountfinanced, b.status
  , case when coalesce(lc.last_in_chain, 1) = 1 then 0 else 1 end as reeng
  from dts_okaapi_loans b
  left join loan_chain lc on lc.id_ihfintech_loan = b.id_ihfintech_loan
  where b.amountfinanced > 0
)
, dac as (
  select c.id_ihfintech_loan as id_loan, c.fecha_calendario as fecha
  , coalesce(c.dias_atraso_cuota, 0) as mora, c.dni
  from dts_cobranza_creditos_calendario_diario c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  where p.status in ('ACTIVE','COMPLETED')
    and c.fecha_calendario between date '2024-12-01' and date '2026-08-31'
)
, dac_lag as (
  select id_loan, fecha, mora, dni
  , lag(mora) over (partition by id_loan order by fecha) as mora_ant
  from dac
)
, st_v1 as (
  select id_loan, date_add('month', 1, date_trunc('month', fecha)) as mes
  from (
    select id_loan, fecha, mora
    , row_number() over (partition by id_loan, date_trunc('month', fecha) order by fecha desc) as rn
    from dac
  )
  where rn = 1 and mora between 1 and 30
)
, st_v2 as (
  select id_loan, fecha as mes
  from dac
  where day(fecha) = 1 and mora between 1 and 30
)
, entradas as (
  select date_trunc('month', fecha) as mes, id_loan
  , min(fecha) as f_ent, min_by(dni, fecha) as dni
  from dac_lag
  where mora_ant = 0 and mora = 1
  group by 1, 2
)
, dni_mora30 as (
  select distinct c.fecha_calendario as fecha, c.dni
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date '2025-01-01' and date '2026-08-31'
    and c.dias_atraso_cuota > 30
    and c.dni is not null
)
, saldo_venc as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20241231' and '20260830'
)
, calendario_rn as (
  select
    c.id_ihfintech_loan as id_loan
  , date_add('day', 1, c.fechavencimiento) as f_entrada_cal
  , date_trunc('month', date_add('day', 1, c.fechavencimiento)) as mes
  , f.saldo, p.amountfinanced, p.reeng
  , row_number() over (
      partition by c.id_ihfintech_loan, date_trunc('month', date_add('day', 1, c.fechavencimiento))
      order by c.fechavencimiento) as rn
  , row_number() over (
      partition by c.id_ihfintech_loan, date_trunc('month', date_add('day', 1, c.fechavencimiento)),
                   case when day(date_add('day', 1, c.fechavencimiento)) >= 2 then 1 else 0 end
      order by c.fechavencimiento) as rn_grupo
  from dts_cobranza_creditos_cuotas c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  join saldo_venc f
    on f.id_loan = c.id_ihfintech_loan
   and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
   and f.rn_dedup = 1
  where c.status in ('ACTIVE','COMPLETED')
    and c.fechavencimiento between date '2024-12-31' and date '2026-08-30'
)
select
  date_format(cr.mes, '%Y%m')                                  as periodo
, day(cr.f_entrada_cal)                                        as dia_entrada
, case when cr.saldo >= 0.9*cr.amountfinanced then 'a. avance <10%'
       when cr.saldo >= 0.6*cr.amountfinanced then 'b. avance 10-40%'
       when cr.saldo >= 0.3*cr.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end                               as avance_band
, case when s1.id_loan is not null then 1 else 0 end           as st_v1
, case when s2.id_loan is not null then 1 else 0 end           as st_v2
, cr.reeng
, least(cr.rn, 2)                                              as orden
, case when day(cr.f_entrada_cal) >= 2 then least(cr.rn_grupo, 2) else 0 end as orden_d2
, case when e.id_loan is not null then 1 else 0 end            as entra
, case when e.id_loan is not null and m.dni is not null then 1 else 0 end as arrastre
, count(*)                                                     as creditos
, round(sum(cr.saldo), 2)                                      as saldo
from calendario_rn cr
left join st_v1 s1    on s1.id_loan = cr.id_loan and s1.mes = cr.mes
left join st_v2 s2    on s2.id_loan = cr.id_loan and s2.mes = cr.mes
left join entradas e  on e.id_loan = cr.id_loan and e.mes = cr.mes
left join dni_mora30 m on m.fecha = e.f_ent and m.dni = e.dni
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
order by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
;

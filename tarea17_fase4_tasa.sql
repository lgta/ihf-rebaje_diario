-- =====================================================================
-- TAREA 17, FASE 4 -- Q-A: TASA UNIFICADA DE ENTRADA A MORA
-- (reemplaza P_NO_PAGA_DIA0=13.38% [dayslate] + P_FANTASMA=8.6163%
-- [dias_atraso_cuota] por UNA sola tasa sobre UNA sola definicion de
-- entrada -- Principio de modelado, CLAUDE.md).
--
-- Definiciones (identicas a las que usaran la curva y el backtest):
--   - Universo de entrada: dias_atraso_cuota 0->1 (reconstruccion
--     diaria), NO dayslate.
--   - Calendario elegible: cuotas cuya ENTRADA (fechavencimiento + 1
--     dia) cae dentro del mes -- NO el vencimiento. Esto absorbe la
--     cohorte de frontera (cuota vencida el ultimo dia del mes
--     anterior) que hoy esta partida entre `dia1_entrantes` del stock
--     (bug 12) y el calendario fantasma frontier-adjusted (bug 14/17).
--   - Excluye el stock del mes (mora 1-30 al cierre del mes anterior,
--     medido tambien con dias_atraso_cuota).
--   - Mismos filtros de siempre: status ACTIVE/COMPLETED,
--     flg_last_loan_in_chain (FUENTES_DATOS.md).
--
-- Ventana: ago-2025 a may-2026, LA MISMA que P_NO_PAGA_DIA0
-- (47966/358580) para que el numero sea comparable manzana con manzana.
-- Incluye abril y mayo 2026 (2 de los 4 meses de backtest) -- mismo
-- leak que ya acepta produccion; tarea 10 lo midio en ~0.2pp.
--
-- Salida en creditos (no soles) -- misma unidad que P_NO_PAGA_DIA0.
-- Desglose mensual ADEMAS del agregado: sirve para ver si la tasa
-- deriva (hipotesis de volumen de analisis_volumen_efectividad_agosto.md,
-- que midio +26.3% de capital entrando en mora sobre lo que asume
-- 13.38%) o si es estable y el gap era definicional.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2025-07-20') and date('2026-06-10')
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
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from dac
)
, cierre as (
  select substr(fechaproceso,1,6) as periodo, id_loan, mora,
    row_number() over (partition by id_loan, substr(fechaproceso,1,6)
                       order by fechaproceso desc) as rn
  from dac
)
, stock_ids as (
  -- stock del mes siguiente = mora 1-30 al cierre de este mes
  select date_format(date_add('month',1,date_parse(periodo,'%Y%m')), '%Y%m') as periodo_target
       , id_loan
  from cierre
  where rn = 1 and mora between 1 and 30
)
, calendario as (
  select
    c.id_ihfintech_loan as id_loan
  , c.fechavencimiento
  , date_format(date_add('day',1,c.fechavencimiento), '%Y%m') as periodo
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2025-07-31')
    and c.fechavencimiento <= date('2026-05-30')
)
, calendario_mes as (
  select cal.periodo, cal.id_loan, min(cal.fechavencimiento) as fechavencimiento
  from calendario cal
  where cal.periodo between '202508' and '202605'
    and not exists (
      select 1 from stock_ids s
      where s.periodo_target = cal.periodo and s.id_loan = cal.id_loan
    )
  group by 1, 2
)
, entradas as (
  select distinct substr(fechaproceso,1,6) as periodo, id_loan
  from dac_lag
  where mora_ant = 0 and mora = 1
)
select
  cm.periodo
, count(*)                                                     as elegibles
, sum(case when e.id_loan is not null then 1 else 0 end)       as entran_mora
, round(100.0 * sum(case when e.id_loan is not null then 1 else 0 end) / count(*), 4) as tasa_pct
from calendario_mes cm
left join entradas e on e.periodo = cm.periodo and e.id_loan = cm.id_loan
group by 1
order by 1
;

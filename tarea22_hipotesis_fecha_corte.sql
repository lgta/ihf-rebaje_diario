-- =====================================================================
-- TAREA 22 -- ¿POR QUE 965 CREDITOS QUE LA VISTA MARCA "ANTIGUO" EN
-- SEPTIEMBRE TIENEN dias_atraso_cuota = 0 PARA NOSOTROS?
--
-- La reconciliacion (tarea22_reconcilia_antiguos_septiembre.sql) dejo el
-- gap explicado en un 99.1% por esa sola causa: S/1,932,530 de 965
-- creditos. Como el motor ya migro a `dias_atraso_cuota` (que cerraba el
-- punto ciego de `dayslate`, bug 9/14), ese resultado NO se explica con lo
-- ya conocido. Hay que averiguar por que antes de tocar nada.
--
-- HIPOTESIS 1 -- FECHA DE CORTE. Nuestro stock se mide al CIERRE DE
--   AGOSTO (ultima foto de agosto). La vista ancla la asignacion en
--   `fecha_ancla` = primer dia que el credito aparece en
--   dts_asignaciones_gestiones_cobranza para el mes, que para los
--   antiguos deberia ser el 1-sep. Un credito que pasa de mora 0 a mora 1
--   ENTRE el 31-ago y el 1-sep seria mora 0 para nosotros y mora >= 1
--   para la vista -- sin que ninguno de los dos este mal.
--   Si es esto, se ve como: mora 0 el 31-ago y mora >= 1 el 1-sep.
--
-- HIPOTESIS 2 -- PUNTO CIEGO QUE SOBREVIVE. El credito esta en mora para
--   el negocio pero `dias_atraso_cuota` no lo ve en NINGUN dia del
--   entorno del corte. Si es esto, se ve como: mora 0 tanto el 31-ago
--   como el 1-sep y el 2-sep.
--
-- HIPOTESIS 3 -- LA FOTO DEL 31-AGO ESTABA INCOMPLETA cuando se corrio la
--   meta (trampa conocida: la foto del dia en curso todavia esta
--   corriendo). Se ve como: sin fila el 31-ago pero con fila el 1-sep.
--
-- Se devuelve la mora de cada uno de esos 965 creditos en 4 fechas
-- (29, 30, 31 de agosto y 1, 2 de septiembre) mas la fecha_ancla y la
-- dias_mora_inicio que reporta la vista, para poder cruzar las tres.
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
, ancla_final as (
  select id_loan, saldo, status from (
    select id_loan, saldo, status,
      row_number() over (partition by id_loan order by fechaproceso desc) as rn
    from mambu_ago where rn_dedup = 1
  ) where rn = 1 and saldo > 0
)
, dac_cierre as (
  select id_loan, mora from (
    select c.id_ihfintech_loan as id_loan, coalesce(c.dias_atraso_cuota,0) as mora,
      row_number() over (partition by c.id_ihfintech_loan order by c.fecha_calendario desc) as rn
    from dts_cobranza_creditos_calendario_diario c
    where c.fecha_calendario between date('2026-08-01') and date('2026-08-31')
  ) where rn = 1
)
, nuestro_stock as (
  select a.id_loan from ancla_final a
  join dac_cierre d on d.id_loan = a.id_loan
  where d.mora between 1 and 30 and a.status in ('ACTIVE','COMPLETED')
)
, vista as (
  select id_ihfintech_loan as id_loan, fecha_ancla, dias_mora_inicio, monto_asignado
  from (
    select v.*, row_number() over (
      partition by v.id_ihfintech_loan order by v.fecha) as rn
    from vw_seguimiento_diario_cohorte_tramo v
    where v.mes_asignacion = '202609' and v.fase_estrategia = 'TEMPRANA'
      and v.tipo_mora = 'antiguo'
  ) where rn = 1
)
-- los 965: estan en la vista, no en nuestro stock, y su mora al cierre es 0
, faltantes as (
  select v.id_loan, v.fecha_ancla, v.dias_mora_inicio, v.monto_asignado
  from vista v
  left join nuestro_stock n on n.id_loan = v.id_loan
  left join dac_cierre d on d.id_loan = v.id_loan
  where n.id_loan is null and d.mora = 0
)
-- mora dia por dia alrededor del corte
, mora_fechas as (
  select
    c.id_ihfintech_loan as id_loan
  , date_format(c.fecha_calendario, '%Y-%m-%d') as f
  , coalesce(c.dias_atraso_cuota, 0) as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario in (date('2026-08-29'), date('2026-08-30'), date('2026-08-31'),
                               date('2026-09-01'), date('2026-09-02'))
)
, pivot as (
  select
    f.id_loan
  , f.monto_asignado
  , f.dias_mora_inicio
  , date_format(f.fecha_ancla, '%Y-%m-%d') as fecha_ancla
  , max(case when m.f = '2026-08-30' then m.mora end) as m30ago
  , max(case when m.f = '2026-08-31' then m.mora end) as m31ago
  , max(case when m.f = '2026-09-01' then m.mora end) as m01sep
  , max(case when m.f = '2026-09-02' then m.mora end) as m02sep
  from faltantes f
  left join mora_fechas m on m.id_loan = f.id_loan
  group by 1,2,3,4
)
select
  case
    when m31ago is null and m01sep is null then 'H3. sin foto ni el 31-ago ni el 1-sep'
    when m31ago is null                    then 'H3. sin foto el 31-ago, con foto el 1-sep'
    when coalesce(m31ago,0) = 0 and coalesce(m01sep,0) >= 1
      then 'H1. mora 0 el 31-ago y >=1 el 1-sep  (cambio de fecha de corte)'
    when coalesce(m31ago,0) = 0 and coalesce(m01sep,0) = 0 and coalesce(m02sep,0) >= 1
      then 'H1b. recien entra el 2-sep'
    when coalesce(m31ago,0) = 0 and coalesce(m01sep,0) = 0 and coalesce(m02sep,0) = 0
      then 'H2. mora 0 en los tres dias  (punto ciego que sobrevive)'
    else 'otro'
  end                                                  as diagnostico
, count(*)                                             as creditos
, round(sum(monto_asignado), 2)                        as saldo
, round(avg(cast(dias_mora_inicio as double)), 2)      as prom_dias_mora_vista
, cast(min(fecha_ancla) as varchar) || ' .. ' || cast(max(fecha_ancla) as varchar) as rango_fecha_ancla
from pivot
group by 1
order by 3 desc
;

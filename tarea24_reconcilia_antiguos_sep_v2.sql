-- =====================================================================
-- TAREA 24 -- ANTIGUO = "EN MORA EL DIA 1" (la definicion de la vista).
-- Reconciliacion de septiembre v2, con 11 dias de asignacion cargados
-- (al 2-sep, cuando se hizo tarea 22, habia solo 2).
--
-- Decision del usuario 2026-09-13: la definicion correcta de antiguo es la
-- de la vista -- el credito que entra en mora el dia 1 es ANTIGUO, no un
-- nuevo con dia_entrada = 1 como lo trata hoy el motor unificado.
--
-- La formula del negocio (FUENTES_DATOS.md, tipo_mora de
-- dts_asignaciones_gestiones_cobranza) es
--     dias_mora >= day(fecha_base)  ->  antiguo
-- y en CUALQUIER dia de asignacion d eso equivale a "entro en mora el dia
-- 1 del mes o antes" (dias_mora = d - dia_entrada + 1 >= d  <=>  dia_entrada <= 1).
-- O sea que la regla va anclada al DIA 1 CALENDARIO, no al primer dia
-- habil, y se puede reproducir sin la tabla de asignaciones -- que es lo
-- que hace falta para recalibrar sobre meses historicos:
--     v2:  dias_atraso_cuota entre 1 y 30 el DIA 1 del mes
-- contra la vigente:
--     v1:  dias_atraso_cuota entre 1 y 30 al CIERRE del mes anterior
--
-- Saldo: ultima foto Mambu de agosto, el saldo con el que el credito
-- amanece el 1-sep (lo que se asigna). Mismos filtros que la meta:
-- status ACTIVE/COMPLETED, sin reenganches, dedup de bug 11.
--
-- Bloques:
--   0.  la vista hoy: TEMPRANA antiguo por fecha_ancla, y la composicion
--       completa de 202609 (al 2-sep: TEMPRANA antiguo 2,789 / S/4,901,917)
--   1.  v1 -> v2: que creditos entran y salen al mover el corte
--   2.  reconciliacion v2 contra la vista, credito a credito, con el
--       motivo de cada lado y la diferencia de MONTO en los que coinciden
--
-- OJO (bug 24): tipo_mora viene en minuscula; la vista expone
-- monto_asignado / dias_mora_inicio / saldo_capital.
-- OJO: en 202609 la vista EXCLUYE todo RECOVERY (fecha_inicio_recovery
-- solo tiene filas para 202607 y 202608), por eso se cruza tambien contra
-- la tabla cruda de asignaciones para ubicar lo que es "solo nuestro".
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
-- v1: mora en la ultima fila de agosto -- identico a la meta vigente
, dac_cierre as (
  select id_loan, mora from (
    select c.id_ihfintech_loan as id_loan, coalesce(c.dias_atraso_cuota,0) as mora,
      row_number() over (partition by c.id_ihfintech_loan order by c.fecha_calendario desc) as rn
    from dts_cobranza_creditos_calendario_diario c
    where c.fecha_calendario between date('2026-08-01') and date('2026-08-31')
  ) where rn = 1
)
-- mora el 1-sep (define v2) y el 2-sep (distingue al que cura el mismo dia 1)
, dac_sep as (
  select c.id_ihfintech_loan as id_loan
  , max(case when c.fecha_calendario = date('2026-09-01') then coalesce(c.dias_atraso_cuota,0) end) as m01
  , max(case when c.fecha_calendario = date('2026-09-02') then coalesce(c.dias_atraso_cuota,0) end) as m02
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-09-01') and date('2026-09-02')
  group by 1
)
, v1 as (
  select a.id_loan, a.saldo from ancla_final a
  join dac_cierre d on d.id_loan = a.id_loan
  where d.mora between 1 and 30 and a.status in ('ACTIVE','COMPLETED')
)
, v2 as (
  select a.id_loan, a.saldo from ancla_final a
  join dac_sep s on s.id_loan = a.id_loan
  where s.m01 between 1 and 30 and a.status in ('ACTIVE','COMPLETED')
)
-- la vista, una fila por credito (la del anclaje), todo 202609
, vista as (
  select id_loan, fecha_ancla, fase_estrategia, tipo_mora, grupo_control,
         dias_mora_inicio, monto_asignado, saldo_capital
  from (
    select v.id_ihfintech_loan as id_loan, v.fecha_ancla, v.fase_estrategia, v.tipo_mora,
           v.grupo_control, v.dias_mora_inicio, v.monto_asignado, v.saldo_capital,
           row_number() over (partition by v.id_ihfintech_loan order by v.fecha) as rn
    from vw_seguimiento_diario_cohorte_tramo v
    where v.mes_asignacion = '202609'
  ) where rn = 1
)
, vista_ta as (
  select * from vista where fase_estrategia = 'TEMPRANA' and tipo_mora = 'antiguo'
)
-- tabla cruda: primera asignacion de septiembre de cada credito, incluye RECOVERY
, asig_raw as (
  select aux02 as id_loan, fase_estrategia, tipo_mora,
    row_number() over (partition by aux02
                       order by cast(fecha_base as date), fase_estrategia desc) as rn
  from dts_asignaciones_gestiones_cobranza
  where cast(fecha_base as date) >= date '2026-09-01'
)
, asig_sep as (select id_loan, fase_estrategia, tipo_mora from asig_raw where rn = 1)
-- =====================================================================
select
  '0. vista TEMPRANA antiguo por fecha_ancla' as bloque
, 'ancla ' || cast(fecha_ancla as varchar)    as k1
, ''                                          as k2
, ''                                          as k3
, count(*)                                    as creditos
, cast(null as double)                        as saldo_nuestro
, round(sum(monto_asignado), 2)               as monto_vista
, round(sum(saldo_capital), 2)                as saldo_mambu_vista
from vista_ta
group by 1,2,3,4

union all

select
  '0b. vista 202609 composicion'
, fase_estrategia
, tipo_mora
, coalesce(grupo_control, '(null)')
, count(*)
, cast(null as double)
, round(sum(monto_asignado), 2)
, round(sum(saldo_capital), 2)
from vista
group by 1,2,3,4

union all

select
  '1. v1 (cierre ago) -> v2 (dia 1)'
, case when v1.id_loan is not null and v2.id_loan is not null then 'a. en v1 y v2'
       when v1.id_loan is not null then 'b. solo v1 (sale)'
       else 'c. solo v2 (entra)' end
, case when v1.id_loan is not null and v2.id_loan is not null then '-'
       when v1.id_loan is not null then
         case when s.id_loan is null or s.m01 is null then 'b1. sin fila en calendario el 1-sep'
              when s.m01 = 0  then 'b2. mora 0 el 1-sep (curo antes del dia 1)'
              when s.m01 > 30 then 'b3. pasa a 31+ el 1-sep'
              else 'b4. otro' end
       else
         case when d.id_loan is null then 'c1. sin fila en calendario en agosto'
              when d.mora = 0    then 'c2. mora 0 al cierre: entra en mora el 1-sep'
              else 'c3. otro' end
  end
, ''
, count(*)
, round(sum(coalesce(v2.saldo, v1.saldo)), 2)
, cast(null as double)
, cast(null as double)
from v1
full outer join v2 on v2.id_loan = v1.id_loan
left join dac_sep s    on s.id_loan = coalesce(v1.id_loan, v2.id_loan)
left join dac_cierre d on d.id_loan = coalesce(v1.id_loan, v2.id_loan)
group by 1,2,3,4

union all

select
  '2. v2 vs vista TEMPRANA antiguo'
, case when t.id_loan is not null and n.id_loan is not null then 'a. en ambos'
       when n.id_loan is not null then 'b. solo nuestro'
       else 'c. solo la vista' end
, case
    when t.id_loan is not null and n.id_loan is not null then
      case when v1.id_loan is not null then 'a1. estaba en v1 (stock al cierre)'
           else 'a2. nuevo en v2 (entro el 1-sep)' end
    when n.id_loan is not null then
      case when vs.id_loan is not null then 'b1. vista: ' || vs.fase_estrategia || ' / ' || vs.tipo_mora
           when ar.id_loan is not null then 'b2. solo tabla cruda: ' || ar.fase_estrategia || ' / ' || ar.tipo_mora
           else 'b3. no aparece en asignaciones de sep' end
    when coalesce(lc.last_in_chain, 1) <> 1 then 'c1. reenganche (flg_last_loan_in_chain)'
    when ok.status is null or ok.status not in ('ACTIVE','COMPLETED')
      then 'c2. status fuera de ACTIVE/COMPLETED'
    when af.id_loan is null then 'c3. sin foto Mambu al cierre de ago con saldo > 0'
    when s.m01 is null then 'c4. sin fila en calendario_diario el 1-sep'
    when s.m01 = 0 and coalesce(s.m02, 0) >= 1 then 'c5. mora 0 el 1-sep, >=1 el 2-sep'
    when s.m01 = 0 then 'c6. mora 0 el 1-sep y el 2-sep'
    when s.m01 > 30 then 'c7. mora > 30 el 1-sep para nosotros'
    else 'c8. SIN MOTIVO IDENTIFICADO' end
, case
    when t.id_loan is not null and n.id_loan is not null then
      case when abs(n.saldo - t.monto_asignado) <= 1 then 'monto igual (+-S/1)'
           else 'monto distinto' end
    when n.id_loan is not null then
      (case when v1.id_loan is not null then 'estaba en v1' else 'nuevo en v2' end)
      || (case when vs.id_loan is null and ar.id_loan is null then
                 (case when coalesce(s.m02, 0) = 0 then ' | mora 0 el 2-sep'
                       else ' | sigue en mora el 2-sep' end)
               else '' end)
    else 'ancla ' || cast(t.fecha_ancla as varchar)
  end
, count(*)
, round(sum(n.saldo), 2)
, round(sum(t.monto_asignado), 2)
, round(sum(t.saldo_capital), 2)
from vista_ta t
full outer join v2 n on n.id_loan = t.id_loan
left join v1                  on v1.id_loan = coalesce(n.id_loan, t.id_loan)
left join vista vs            on vs.id_loan = n.id_loan
left join asig_sep ar         on ar.id_loan = n.id_loan
left join loan_chain lc       on lc.id_ihfintech_loan = t.id_loan
left join dts_okaapi_loans ok on ok.id_ihfintech_loan = t.id_loan
left join ancla_final af      on af.id_loan = t.id_loan
left join dac_sep s           on s.id_loan = coalesce(n.id_loan, t.id_loan)
group by 1,2,3,4

order by 1,2,3,4
;

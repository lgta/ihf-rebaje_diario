-- =====================================================================
-- TAREA 24 -- DIAGNOSTICO, PARTE 1 (nuestro lado): por que quedan las
-- diferencias con la definicion v2 de antiguo ("mora 1-30 el dia 1", la de
-- la vista). Complementa tarea24_reconcilia_antiguos_sep_v2.sql, que dice
-- CUANTO hay en cada bucket; esta y tarea24_diagnostico_vista.sql dicen POR QUE.
--
--   A. Los que SALEN del stock al pasar de v1 a v2 (mora >= 1 al cierre de
--      agosto pero 0 el 1-sep, o 30 -> 31). ¿Donde estan en la asignacion?
--      ¿Cuando pagaron? -- cierra los 487 "no aparecen aun" de tarea 22.
--   E. Nuestros v2 que no aparecen en ninguna asignacion de septiembre.
--   F. Los curados de A: ¿tienen vencimiento en septiembre? Con v2 dejan de
--      estar excluidos del calendario de nuevos.
--
-- La vista NO se usa aca: su CTE mambu_con_fecha hace row_number() sobre
-- TODO dts_mambu_loans_hist y referenciarla varias veces agota recursos
-- (la primera version de esta query fallo asi). Se replica solo el
-- anclaje (primer dia asignado del mes, atributos MAX de ese dia) desde
-- dts_asignaciones_gestiones_cobranza, que es de donde la vista los saca.
--
-- Hora de pago: dts_cobranza_creditos_cuotas.installmentlastpaiddate (la mas
-- reciente entre el 30-ago y el 1-sep). Se asume hora local, igual que el
-- caso de tarea 17 (pago 12:39 dentro de la ventana 9am-10pm).
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
, dac_sep as (
  select c.id_ihfintech_loan as id_loan
  , max(case when c.fecha_calendario = date('2026-09-01') then coalesce(c.dias_atraso_cuota,0) end) as m01
  , max(case when c.fecha_calendario = date('2026-09-02') then coalesce(c.dias_atraso_cuota,0) end) as m02
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-09-01') and date('2026-09-02')
  group by 1
)
-- v1 y v2 juntos, una sola pasada por ancla_final
, univ as (
  select a.id_loan, a.saldo
  , case when d.mora between 1 and 30 then 1 else 0 end as en_v1
  , case when s.m01 between 1 and 30 then 1 else 0 end as en_v2
  , s.m01, s.m02
  from ancla_final a
  left join dac_cierre d on d.id_loan = a.id_loan
  left join dac_sep s on s.id_loan = a.id_loan
  where a.status in ('ACTIVE','COMPLETED')
    and (d.mora between 1 and 30 or s.m01 between 1 and 30)
)
-- anclaje de septiembre replicado desde la tabla cruda (ver cabecera)
, base as (
  select aux02 as id_loan, cast(fecha_base as date) as fb, fase_estrategia, tipo_mora
  from dts_asignaciones_gestiones_cobranza
  where cast(fecha_base as date) between date '2026-09-01' and date '2026-09-30'
)
, primer as (select id_loan, min(fb) as fecha_ancla from base group by 1)
, anc as (
  select p.id_loan, p.fecha_ancla, max(b.fase_estrategia) as fase_estrategia, max(b.tipo_mora) as tipo_mora
  from primer p join base b on b.id_loan = p.id_loan and b.fb = p.fecha_ancla
  group by 1, 2
)
, pago as (
  select id_loan
  , case when date(ts) = date '2026-08-30'                    then 'p1. pago 30-ago'
         when date(ts) = date '2026-08-31' and hour(ts) < 9  then 'p2. pago 31-ago antes de 09h'
         when date(ts) = date '2026-08-31' and hour(ts) < 22 then 'p3. pago 31-ago 09-22h'
         when date(ts) = date '2026-08-31'                    then 'p4. pago 31-ago desde 22h'
         when hour(ts) < 9                                    then 'p5. pago 1-sep antes de 09h'
         else                                                      'p6. pago 1-sep desde 09h' end as bucket
  from (
    select id_ihfintech_loan as id_loan, max(cast(installmentlastpaiddate as timestamp)) as ts
    from dts_cobranza_creditos_cuotas
    where cast(installmentlastpaiddate as timestamp) >= timestamp '2026-08-30 00:00:00'
      and cast(installmentlastpaiddate as timestamp) <  timestamp '2026-09-02 00:00:00'
    group by 1
  )
)
, venc_sep as (
  select distinct id_ihfintech_loan as id_loan
  from dts_cobranza_creditos_cuotas
  where date_add('day', 1, fechavencimiento) between date '2026-09-02' and date '2026-09-30'
)
-- una fila por credito con la condicion y las claves de cada bloque
, prep as (
  select u.saldo
  , (u.en_v1 = 1 and u.en_v2 = 0 and (u.m01 = 0 or u.m01 > 30)) as es_a   -- sale de v1
  , (u.en_v2 = 1 and x.id_loan is null)                          as es_e   -- v2 sin asignacion
  , (u.en_v1 = 1 and u.en_v2 = 0 and u.m01 = 0)                  as es_f   -- curados de A1
  , case when u.m01 = 0 then 'A1. mora 0 el 1-sep' else 'A2. pasa a 31+ el 1-sep' end as a_k1
  , case when x.id_loan is null then 'no aparece en asignaciones de sep'
         else x.fase_estrategia || ' / ' || x.tipo_mora || ' / ancla '
              || (case when x.fecha_ancla = date '2026-09-01' then '1-sep' else 'posterior' end) end as a_k2
  , coalesce(p.bucket, 'p0. sin pago 30-ago..1-sep') as pb
  , case when u.en_v1 = 1 then 'estaba en v1' else 'nuevo en v2' end as e_k1
  , case when coalesce(u.m02, 0) = 0 then 'mora 0 el 2-sep' else 'sigue en mora el 2-sep' end as e_k2
  , case when vz.id_loan is not null then 'tiene vencimiento 2-30 sep' else 'sin vencimiento en sep' end as f_k1
  , case when x.id_loan is null then 'no aparece en asignaciones de sep'
         else x.fase_estrategia || ' / ' || x.tipo_mora end as f_k2
  from univ u
  left join anc x on x.id_loan = u.id_loan
  left join pago p on p.id_loan = u.id_loan
  left join venc_sep vz on vz.id_loan = u.id_loan
)
-- todo en una pasada: cada credito aporta sus filas de bloque via unnest.
-- OJO: Athena NO expande a columnas un unnest sobre array(row(...)) --
-- falla con "Column alias list has 4 entries but 'r' has 1 columns". Por
-- eso van arrays paralelos, que unnest si zipea en columnas.
, filas as (
  select saldo, bloque, k1, k2, k3
  from prep
  cross join unnest(
      array[if(es_a, 'A. salen de v1'),
            if(es_e, 'E. v2 sin asignacion en sep'),
            if(es_f, 'F. curados de A1: vencimiento en sep')]
    , array[a_k1, e_k1, f_k1]
    , array[a_k2, e_k2, f_k2]
    , array[pb, pb, '']
  ) as r(bloque, k1, k2, k3)
  where bloque is not null
)
select bloque, k1, k2, k3, count(*) as creditos, round(sum(saldo), 2) as saldo
from filas
group by 1,2,3,4
order by 1,2,3,4
;

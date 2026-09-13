-- =====================================================================
-- TAREA 24 -- DIAGNOSTICO, PARTE 2 (lado de la vista): por que quedan las
-- diferencias con la definicion v2 de antiguo. Ver
-- tarea24_diagnostico_diferencias.sql para la parte 1 y la razon de no
-- usar la vista directamente (agota recursos si se referencia varias veces).
--
--   0. CONTROL: el anclaje replicado desde la tabla cruda tiene que dar lo
--      mismo que la vista para TEMPRANA/antiguo (2,790 / S/4,904,772.54 en
--      tarea24_reconcilia_antiguos_sep_v2.sql). Si no da, lo de abajo no vale.
--   B. Los que la vista tiene como antiguo pero para nosotros tienen mora 0
--      el 1-sep y el 2-sep. ¿Cuando pagaron?
--   C. Reenganches que la vista gestiona y nuestro filtro excluye. ¿Se
--      refinanciaron DESPUES del 1-sep? Si si, flg_last_loan_in_chain (que
--      se lee con la foto de HOY) esta mirando hacia adelante.
--   D. Nuestros v2 que la asignacion manda a ESPECIALIZADA/RECOVERY.
--      ¿Arrastre por DNI (max_dias_mora_dni > 30)?
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
, dac_sep as (
  select c.id_ihfintech_loan as id_loan
  , max(case when c.fecha_calendario = date('2026-08-31') then coalesce(c.dias_atraso_cuota,0) end) as m31
  , max(case when c.fecha_calendario = date('2026-09-01') then coalesce(c.dias_atraso_cuota,0) end) as m01
  , max(case when c.fecha_calendario = date('2026-09-02') then coalesce(c.dias_atraso_cuota,0) end) as m02
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-08-31') and date('2026-09-02')
  group by 1
)
, base as (
  select aux02 as id_loan, cast(fecha_base as date) as fb, fase_estrategia, tipo_mora,
         dias_mora, max_dias_mora_dni, monto_capital_pendiente
  from dts_asignaciones_gestiones_cobranza
  where cast(fecha_base as date) between date '2026-09-01' and date '2026-09-30'
)
, primer as (select id_loan, min(fb) as fecha_ancla from base group by 1)
, anc as (
  select p.id_loan, p.fecha_ancla
  , max(b.fase_estrategia) as fase_estrategia, max(b.tipo_mora) as tipo_mora
  , coalesce(max(b.dias_mora), 0) as dias_mora_inicio
  , max(b.max_dias_mora_dni) as max_dias_mora_dni
  , max(b.monto_capital_pendiente) as monto_asignado
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
-- una fila por credito con todo lo que usan los bloques
, cred as (
  select x.id_loan, x.fase_estrategia, x.tipo_mora, x.dias_mora_inicio, x.max_dias_mora_dni,
         x.monto_asignado
  , coalesce(lc.last_in_chain, 1) as last_in_chain
  , af.id_loan is not null and af.status in ('ACTIVE','COMPLETED') as con_foto
  , af.saldo
  , s.m31, s.m01, s.m02
  , p.bucket
  from anc x
  left join loan_chain lc  on lc.id_ihfintech_loan = x.id_loan
  left join ancla_final af on af.id_loan = x.id_loan
  left join dac_sep s      on s.id_loan = x.id_loan
  left join pago p         on p.id_loan = x.id_loan
)
-- C necesita el estado Mambu de sep: solo para los reenganches TEMPRANA/antiguo
, reeng as (
  select c.id_loan, c.monto_asignado
  , min(case when m.accountstate not in ('ACTIVE','ACTIVE_IN_ARREARS') then m.fechaproceso end) as f_sale_active
  , max_by(m.accountstate || '/' || coalesce(m.accountsubstate, '-'), m.fechaproceso) as estado_ult
  from cred c
  left join dts_mambu_loans_hist m
    on m._datos_adicionales_loan_accounts_id_ihfintech = c.id_loan
   and m.fechaproceso between '20260825' and '20260912'
  where c.fase_estrategia = 'TEMPRANA' and c.tipo_mora = 'antiguo' and c.last_in_chain <> 1
  group by 1, 2
)
, prep as (
  select c.monto_asignado as monto, c.saldo
  , (c.fase_estrategia = 'TEMPRANA' and c.tipo_mora = 'antiguo') as es_0
  , (c.fase_estrategia = 'TEMPRANA' and c.tipo_mora = 'antiguo'
     and c.last_in_chain = 1 and c.con_foto and c.m01 = 0 and coalesce(c.m02, 0) = 0) as es_b
  , (c.fase_estrategia in ('ESPECIALIZADA','RECOVERY')
     and c.last_in_chain = 1 and c.con_foto and c.m01 between 1 and 30) as es_d
  , case when c.m31 is null then 'sin fila el 31-ago'
         when c.m31 = 0 then 'mora 0 el 31-ago'
         else 'mora >=1 el 31-ago (estaba en v1)' end as b_k1
  , 'mora asignacion ' || case when c.dias_mora_inicio <= 1 then '1'
                               when c.dias_mora_inicio <= 8 then '2-8'
                               when c.dias_mora_inicio <= 15 then '9-15'
                               else '16-30' end as b_k2
  , coalesce(c.bucket, 'p0. sin pago 30-ago..1-sep') as b_k3
  , c.fase_estrategia as d_k1
  , case when c.max_dias_mora_dni is null then 'max_dias_mora_dni null'
         when c.max_dias_mora_dni > 30 then 'max_dias_mora_dni > 30 (arrastre por DNI)'
         else 'max_dias_mora_dni <= 30' end as d_k2
  , case when c.m01 <= 8 then 'nuestra mora 1-8'
         when c.m01 <= 15 then 'nuestra mora 9-15'
         else 'nuestra mora 16-30' end as d_k3
  from cred c
)
-- OJO: Athena NO expande a columnas un unnest sobre array(row(...)); van
-- arrays paralelos (ver tarea24_diagnostico_diferencias.sql).
, filas as (
  select monto, saldo, bloque, k1, k2, k3
  from prep
  cross join unnest(
      array[if(es_0, '0. control: TEMPRANA antiguo replicado'),
            if(es_b, 'B. vista antiguo, mora 0 nuestra el 1-sep'),
            if(es_d, 'D. v2 asignado a ESPECIALIZADA/RECOVERY')]
    , array['total', b_k1, d_k1]
    , array['', b_k2, d_k2]
    , array['', b_k3, d_k3]
  ) as r(bloque, k1, k2, k3)
  where bloque is not null
)
select bloque, k1, k2, k3, count(*) as creditos
, round(sum(monto), 2) as monto_asignado
, round(sum(saldo), 2) as saldo_nuestro
from filas
group by 1,2,3,4

union all

select 'C. reenganches que gestiona la vista'
, coalesce('deja ACTIVE el ' || f_sale_active, 'sigue ACTIVE al 12-sep')
, coalesce(estado_ult, '(sin foto Mambu)')
, ''
, count(*)
, round(sum(monto_asignado), 2)
, cast(null as double)
from reeng
group by 1,2,3,4

order by 1,2,3,4
;

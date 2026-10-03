-- =====================================================================
-- TAREA 25 -- STOCK DE OCTUBRE (v2, en mora 1-30 el dia 1) CONTRA LA ASIGNACION
-- REAL DEL 1-OCT (dts_asignaciones_gestiones_cobranza, fecha_base '2026-10-01').
-- Pregunta del usuario 2026-10-01: la asignacion del dia 1 ya esta cargada al
-- inicio del dia; ¿no es esa el stock? Cruce credito a credito por aux02.
-- Nuestro lado: el CTE stock de tarea25_insumos_octubre.sql, sin cambios.
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
, cierre_refin as (
  select _datos_adicionales_loan_accounts_id_ihfintech as id_loan, min(fechaproceso) as f_cierre
  from dts_mambu_loans_hist
  where accountsubstate in ('REFINANCED', 'RESCHEDULED')
    and fechaproceso >= '20260901'
  group by 1
)
, mambu_dedup as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso, a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260901' and '20260930'
)
, ancla_final as (
  select id_loan, saldo, amountfinanced, status, reeng, refin_post from (
    select d.id_loan, d.saldo, p.amountfinanced, p.status, p.reeng
    , case when cr.f_cierre >= '20261001' then 1 else 0 end as refin_post
    , row_number() over (partition by d.id_loan order by d.fechaproceso desc) as rn
    from mambu_dedup d
    join prestamos p on p.id_loan = d.id_loan
    left join cierre_refin cr on cr.id_loan = d.id_loan
    where d.rn_dedup = 1
  ) where rn = 1 and saldo > 0
)
, dac as (
  select c.id_ihfintech_loan as id_loan, c.fecha_calendario as fecha
  , coalesce(c.dias_atraso_cuota, 0) as mora, c.dni
  from dts_cobranza_creditos_calendario_diario c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  where p.status in ('ACTIVE','COMPLETED')
    and c.fecha_calendario between date '2026-09-01' and date '2026-10-01'
)
, dac_cierre as (
  select id_loan, mora, dni from (
    select id_loan, mora, dni, row_number() over (partition by id_loan order by fecha desc) as rn
    from dac where fecha <= date '2026-09-30'
  ) where rn = 1
)
, dac_d1 as (
  select id_loan, mora, dni from dac where fecha = date '2026-10-01'
)
, dni_mora30 as (
  select distinct c.dni
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario = date '2026-10-01'
    and c.dias_atraso_cuota > 30
    and c.dni is not null
)
, stock as (
  select 'v1' as definicion, a.id_loan, c.mora, 0 as d1, c.dni, a.saldo, a.amountfinanced
  , a.reeng, a.refin_post
  from ancla_final a join dac_cierre c on c.id_loan = a.id_loan
  where c.mora between 1 and 30 and a.status in ('ACTIVE','COMPLETED')

  union all

  select 'v2', a.id_loan, c.mora, case when c.mora = 1 then 1 else 0 end, c.dni
  , a.saldo, a.amountfinanced, a.reeng, a.refin_post
  from ancla_final a join dac_d1 c on c.id_loan = a.id_loan
  where c.mora between 1 and 30 and a.status in ('ACTIVE','COMPLETED')
)
, asig as (
  select cast(aux02 as varchar) as id_loan
  , max(fase_estrategia) as fase, max(tipo_mora) as tipo_mora
  , max(dias_mora) as dias_mora, max(grupo_control) as grupo_control
  , max(monto_capital_pendiente) as monto
  from dts_asignaciones_gestiones_cobranza
  where fecha_base = '2026-10-01'
  group by 1
)
, nuestro as (
  select s.id_loan, s.saldo, s.mora, s.d1
  , case when m.dni is not null then 1 else 0 end as arrastre
  from stock s left join dni_mora30 m on m.dni = s.dni
  where s.definicion = 'v2'
)
select 'resumen_asig' as bloque, fase, tipo_mora, cast(null as varchar) as lado
, cast(null as integer) as d1, cast(null as integer) as arrastre
, count(*) as creditos, round(sum(monto),2) as monto_asig, cast(null as double) as saldo_nuestro
from asig group by 2, 3
union all
select 'cruce', coalesce(a.fase, a2.fase, '(sin asig)'), coalesce(a.tipo_mora, a2.tipo_mora, '(sin asig)')
, case when n.id_loan is not null and a.id_loan is not null then 'ambos'
       when n.id_loan is not null then 'solo_nuestro' else 'solo_asig' end
, n.d1, n.arrastre
, count(*), round(sum(a.monto),2), round(sum(n.saldo),2)
from nuestro n
full outer join (select * from asig where fase = 'TEMPRANA' and lower(tipo_mora) = 'antiguo') a
  on a.id_loan = cast(n.id_loan as varchar)
left join asig a2 on a2.id_loan = cast(n.id_loan as varchar)
group by 2, 3, 4, 5, 6
order by 1, 2, 3, 4, 5, 6

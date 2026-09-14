-- =====================================================================
-- TAREA 24 -- SEPTIEMBRE 2026 CON LA DEFINICION v2, EN PARALELO A LA META
-- PUBLICADA (que NO se toca). Dos bloques:
--
--   insumo : los insumos de la meta de septiembre con las dos definiciones,
--            de la misma foto de hoy -- v1 reproduce
--            tarea19_meta_septiembre_insumos.sql (lo que se uso el 1-sep, salvo
--            re-expresion); v2 es lo que usaria la meta con la definicion nueva.
--              stock      v1: dias_atraso_cuota 1-30 en la ultima fila de agosto
--                         v2: dias_atraso_cuota 1-30 el 1-sep (tramo por esa mora)
--                         saldo: ultima foto de agosto (> 0), status ACTIVE/COMPLETED
--              calendario cuotas ACTIVE con entrada (venc + 1) en septiembre,
--                         saldo anclado al cierre de agosto, sin el stock de su
--                         definicion. v2: desde el dia 2 (la cohorte del dia 1 es
--                         stock). `saldo` suma todas las cuotas (como v1);
--                         `saldo_rn1` solo la primera de cada credito (como la
--                         tasa de tarea24_v2_calendario_tasa.sql).
--   real   : el real de septiembre por dia con la definicion v2 (activacion y
--            rebaje). El de v1 esta en tarea19_real_septiembre.sql.
--
-- Dimensiones: d1 (entro en mora el 1-sep), arrastre (DNI con otro credito
-- > 30 dias: el 1-sep para stock y calendario, el dia de entrada para el real
-- de nuevos), reeng (flg_last_loan_in_chain = 0 hoy; la meta v1 los excluia).
-- Reenganches: el cierre por refinanciamiento no cuenta como pago.
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
    and fechaproceso >= '20260801'
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
  where a.fechaproceso between '20260801' and '20260930'
)
, fotos as (
  select d.id_loan, d.fechaproceso, substr(d.fechaproceso,1,6) as periodo
  , cast(substr(d.fechaproceso,7,2) as int) as dia
  , d.saldo, p.amountfinanced, p.status, p.reeng
  , lag(d.saldo) over (partition by d.id_loan order by d.fechaproceso) as saldo_ant
  , case when cr.f_cierre is not null and d.fechaproceso >= cr.f_cierre then 1 else 0 end as post_refin
  from mambu_dedup d
  join prestamos p on p.id_loan = d.id_loan
  left join cierre_refin cr on cr.id_loan = d.id_loan
  where d.rn_dedup = 1
)
, ancla_final as (
  select id_loan, saldo, amountfinanced, status, reeng from (
    select id_loan, saldo, amountfinanced, status, reeng
    , row_number() over (partition by id_loan order by fechaproceso desc) as rn
    from fotos where periodo = '202608'
  ) where rn = 1 and saldo > 0
)
, dac as (
  select c.id_ihfintech_loan as id_loan, c.fecha_calendario as fecha
  , coalesce(c.dias_atraso_cuota, 0) as mora, c.dni
  from dts_cobranza_creditos_calendario_diario c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  where p.status in ('ACTIVE','COMPLETED')
    and c.fecha_calendario between date '2026-08-01' and date '2026-09-30'
)
, dac_cierre as (
  select id_loan, mora, dni from (
    select id_loan, mora, dni, row_number() over (partition by id_loan order by fecha desc) as rn
    from dac where fecha <= date '2026-08-31'
  ) where rn = 1
)
, dac_d1 as (
  select id_loan, mora, dni from dac where fecha = date '2026-09-01'
)
, dni_mora30 as (
  select distinct c.fecha_calendario as fecha, c.dni
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date '2026-09-01' and date '2026-09-30'
    and c.dias_atraso_cuota > 30
    and c.dni is not null
)
, stock as (
  select 'v1' as definicion, a.id_loan, c.mora, 0 as d1, c.dni, a.saldo, a.amountfinanced, a.reeng
  from ancla_final a join dac_cierre c on c.id_loan = a.id_loan
  where c.mora between 1 and 30 and a.status in ('ACTIVE','COMPLETED')

  union all

  select 'v2', a.id_loan, c.mora, case when c.mora = 1 then 1 else 0 end, c.dni
  , a.saldo, a.amountfinanced, a.reeng
  from ancla_final a join dac_d1 c on c.id_loan = a.id_loan
  where c.mora between 1 and 30 and a.status in ('ACTIVE','COMPLETED')
)
, stock_seg as (
  select s.definicion, s.id_loan, s.saldo, s.d1, s.reeng
  , case when s.mora between 1 and 8  then 'a. 1-8'
         when s.mora between 9 and 15 then 'b. 9-15'
         else                              'c. 16-30' end as tramo
  , case when s.saldo >= 0.9*s.amountfinanced then 'a. avance <10%'
         when s.saldo >= 0.6*s.amountfinanced then 'b. avance 10-40%'
         when s.saldo >= 0.3*s.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  , case when m.dni is not null then 1 else 0 end as arrastre
  from stock s
  left join dni_mora30 m on m.fecha = date '2026-09-01' and m.dni = s.dni
)
, cal as (
  select c.id_ihfintech_loan as id_loan
  , cast(day(date_add('day', 1, c.fechavencimiento)) as int) as dia_entrada
  , a.saldo, a.amountfinanced, a.reeng
  , row_number() over (partition by c.id_ihfintech_loan order by c.fechavencimiento) as rn
  from dts_cobranza_creditos_cuotas c
  join ancla_final a on a.id_loan = c.id_ihfintech_loan
  where c.status = 'ACTIVE' and a.status = 'ACTIVE'
    and date_add('day', 1, c.fechavencimiento) between date '2026-09-01' and date '2026-09-30'
)
, cal_def as (
  select 'v1' as definicion, cal.* from cal
  where not exists (select 1 from stock s where s.definicion = 'v1' and s.id_loan = cal.id_loan)
  union all
  select 'v2', cal.* from cal
  where cal.dia_entrada >= 2
    and not exists (select 1 from stock s where s.definicion = 'v2' and s.id_loan = cal.id_loan)
)
-- real v2 de septiembre
, dac_lag as (
  select id_loan, fecha, mora, dni
  , lag(mora) over (partition by id_loan order by fecha) as mora_ant
  , row_number() over (partition by id_loan order by fecha) as nro_foto
  from dac
)
-- todas las entradas de septiembre, marcadas con el stock de cada definicion:
-- v1 = sin stock v1 (incluye el dia 1); v2 = sin stock v2 y desde el dia 2
, entradas as (
  select l.id_loan, l.fecha as fecha_entrada, l.dni
  , case when s1.id_loan is not null then 1 else 0 end as st_v1
  , case when s2.id_loan is not null then 1 else 0 end as st_v2
  from dac_lag l
  left join stock s1 on s1.definicion = 'v1' and s1.id_loan = l.id_loan
  left join stock s2 on s2.definicion = 'v2' and s2.id_loan = l.id_loan
  where l.nro_foto > 1 and l.mora_ant = 0 and l.mora = 1
    and l.fecha between date '2026-09-01' and date '2026-09-30'
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada, day(e.fecha_entrada) as dia_entrada, e.st_v1, e.st_v2
  , f.reeng, coalesce(f.saldo_ant, f.saldo) as saldo
  , case when m.dni is not null then 1 else 0 end as arrastre
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.fechaproceso = date_format(e.fecha_entrada, '%Y%m%d')
  left join dni_mora30 m on m.fecha = e.fecha_entrada and m.dni = e.dni
  where coalesce(f.saldo_ant, f.saldo) > 0 and f.status in ('ACTIVE','COMPLETED')
)
, obs as (
  select 'stock' as componente, s.id_loan, '-' as fecha_entrada, s.saldo as saldo_ref
  , s.d1, s.arrastre, s.reeng, f.dia
  , case when f.post_refin = 0 and f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from stock_seg s
  join fotos f on f.id_loan = s.id_loan and f.periodo = '202609'
  where s.definicion = 'v2'

  union all

  select 'nuevos', e.id_loan, date_format(e.fecha_entrada, '%Y%m%d'), e.saldo, 0, e.arrastre, e.reeng, f.dia
  , case when f.post_refin = 0 and f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end
  from entradas_saldo e
  join fotos f on f.id_loan = e.id_loan
    and f.periodo = '202609' and f.fechaproceso >= date_format(e.fecha_entrada, '%Y%m%d')
  where e.st_v2 = 0 and e.dia_entrada >= 2
)
, primer_pago as (
  select componente, id_loan, fecha_entrada, saldo_ref, d1, arrastre, reeng, min(dia) as dia
  from obs where rebaje > 0
  group by 1, 2, 3, 4, 5, 6, 7
)
, act as (
  select componente, d1, arrastre, reeng, dia, count(*) as creditos, sum(saldo_ref) as saldo
  from primer_pago group by 1, 2, 3, 4, 5
)
, reb as (
  select componente, d1, arrastre, reeng, dia, sum(rebaje) as rebaje
  from obs where rebaje > 0 group by 1, 2, 3, 4, 5
)
-- =====================================================================
select 'insumo' as bloque, definicion, 'stock' as componente, tramo, avance_band, d1, arrastre, reeng
, 0 as dia, count(*) as creditos, round(sum(saldo), 2) as saldo
, round(sum(saldo), 2) as saldo_rn1, cast(null as double) as rebaje
from stock_seg
group by 1, 2, 3, 4, 5, 6, 7, 8, 9

union all

select 'insumo', definicion, 'calendario', ''
, case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
       when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
       when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end
, 0, 0, reeng, dia_entrada, count(distinct id_loan), round(sum(saldo), 2)
, round(sum(case when rn = 1 then saldo else 0 end), 2), cast(null as double)
from cal_def
group by 1, 2, 3, 4, 5, 6, 7, 8, 9

union all

select 'real', 'v2', coalesce(a.componente, r.componente), '', ''
, coalesce(a.d1, r.d1), coalesce(a.arrastre, r.arrastre), coalesce(a.reeng, r.reeng)
, coalesce(a.dia, r.dia), coalesce(a.creditos, 0), round(coalesce(a.saldo, 0), 2)
, cast(null as double), round(coalesce(r.rebaje, 0), 2)
from act a
full outer join reb r
  on r.componente = a.componente and r.d1 = a.d1 and r.arrastre = a.arrastre
 and r.reeng = a.reeng and r.dia = a.dia

union all

-- entradas por dia con cada definicion: separa VOLUMEN de entrada de ACTIVACION
select 'real_pob', 'v1', 'nuevos', '', '', 0, arrastre, reeng, dia_entrada, count(*), round(sum(saldo), 2)
, cast(null as double), cast(null as double)
from entradas_saldo
where st_v1 = 0
group by 1, 2, 3, 4, 5, 6, 7, 8, 9

union all

select 'real_pob', 'v2', 'nuevos', '', '', 0, arrastre, reeng, dia_entrada, count(*), round(sum(saldo), 2)
, cast(null as double), cast(null as double)
from entradas_saldo
where st_v2 = 0 and dia_entrada >= 2
group by 1, 2, 3, 4, 5, 6, 7, 8, 9

order by 1, 2, 3, 4, 5, 6, 7, 8, 9
;

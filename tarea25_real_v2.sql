-- =====================================================================
-- TAREA 25 -- REAL v2 POR DIA DE UN MES EN CURSO, para seguir la meta v2 (los
-- dos enfoques). Armada para OCTUBRE 2026. Salida para
--   python seguimiento_v2.py 202610 datos_tarea25/insumos_octubre.csv \
--          datos_tarea25/real_v2_octubre.csv <ultimo dia completo>
--
-- Copia de los bloques 'real' y 'real_pob' de tarea24_v2_septiembre.sql, sin los
-- insumos (salen de tarea25_insumos_octubre.sql) y solo con la definicion v2.
-- Mismo universo que la meta:
--   stock  = dias_atraso_cuota 1-30 el DIA 1 del mes, saldo de la ultima foto del
--            mes anterior > 0, status ACTIVE/COMPLETED. d1 = entro en mora ese
--            mismo dia 1 (la meta la proyecta con la curva de nuevos, pero su
--            real va en el stock, igual que en la meta).
--   nuevos = transicion dias_atraso_cuota 0 -> 1 desde el DIA 2, sin el stock v2;
--            saldo de entrada = el del dia anterior.
-- Marcados, no filtrados: arrastre (DNI con otro credito > 30 dias: el dia 1 para
-- el stock, el dia de entrada para nuevos) y reeng (flg_last_loan_in_chain = 0
-- hoy). La meta de octubre INCLUYE los reenganches (motor_v2.REENG): el
-- seguimiento los suma. El salto de saldo del reenganche (desde f_cierre, primer
-- dia REFINANCED) no cuenta como pago.
--
-- Esquema de salida = el de tarea24_v2_septiembre.sql:
--   real     : por (componente, d1, arrastre, reeng, dia) -- creditos y saldo
--              activados ese dia (alfa, primer pago del mes) y rebaje (recupero)
--   real_pob : entradas v2 por (arrastre, reeng, dia) -- el VOLUMEN que entro
-- Trae todos los dias con foto; el corte al ultimo dia completo (el penultimo:
-- la foto del dia en curso esta incompleta) lo hace seguimiento_v2.py.
--
-- PARA OTRO MES: correr un mes todas las fechas -- '20260901' y '20261031'
-- (fotos), '202609' (mes del ancla) y '202610' (mes en curso), y las date
-- '2026-09-01', '2026-10-01' y '2026-10-31'.
-- VALIDADA 2026-09-13 corriendola con las fechas de SEPTIEMBRE contra los bloques
-- 'real' y 'real_pob' v2 de datos_tarea24/v2_septiembre.csv.
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
  where a.fechaproceso between '20260901' and '20261031'
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
    from fotos where periodo = '202609'
  ) where rn = 1 and saldo > 0
)
, dac as (
  select c.id_ihfintech_loan as id_loan, c.fecha_calendario as fecha
  , coalesce(c.dias_atraso_cuota, 0) as mora, c.dni
  from dts_cobranza_creditos_calendario_diario c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  where p.status in ('ACTIVE','COMPLETED')
    and c.fecha_calendario between date '2026-09-01' and date '2026-10-31'
)
, dac_d1 as (
  select id_loan, mora, dni from dac where fecha = date '2026-10-01'
)
, dni_mora30 as (
  select distinct c.fecha_calendario as fecha, c.dni
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date '2026-10-01' and date '2026-10-31'
    and c.dias_atraso_cuota > 30
    and c.dni is not null
)
, stock_seg as (
  select a.id_loan, a.saldo, a.reeng
  , case when c.mora = 1 then 1 else 0 end as d1
  , case when m.dni is not null then 1 else 0 end as arrastre
  from ancla_final a
  join dac_d1 c on c.id_loan = a.id_loan
  left join dni_mora30 m on m.fecha = date '2026-10-01' and m.dni = c.dni
  where c.mora between 1 and 30 and a.status in ('ACTIVE','COMPLETED')
)
, dac_lag as (
  select id_loan, fecha, mora, dni
  , lag(mora) over (partition by id_loan order by fecha) as mora_ant
  , row_number() over (partition by id_loan order by fecha) as nro_foto
  from dac
)
, entradas as (
  select l.id_loan, l.fecha as fecha_entrada, l.dni
  from dac_lag l
  where l.nro_foto > 1 and l.mora_ant = 0 and l.mora = 1
    and l.fecha between date '2026-10-01' and date '2026-10-31'
    and day(l.fecha) >= 2
    and not exists (select 1 from stock_seg s where s.id_loan = l.id_loan)
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada, day(e.fecha_entrada) as dia_entrada
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
  join fotos f on f.id_loan = s.id_loan and f.periodo = '202610'

  union all

  select 'nuevos', e.id_loan, date_format(e.fecha_entrada, '%Y%m%d'), e.saldo, 0, e.arrastre, e.reeng, f.dia
  , case when f.post_refin = 0 and f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end
  from entradas_saldo e
  join fotos f on f.id_loan = e.id_loan
    and f.periodo = '202610' and f.fechaproceso >= date_format(e.fecha_entrada, '%Y%m%d')
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
select 'real' as bloque, 'v2' as definicion, coalesce(a.componente, r.componente) as componente
, '' as tramo, '' as avance_band
, coalesce(a.d1, r.d1) as d1, coalesce(a.arrastre, r.arrastre) as arrastre, coalesce(a.reeng, r.reeng) as reeng
, coalesce(a.dia, r.dia) as dia, coalesce(a.creditos, 0) as creditos, round(coalesce(a.saldo, 0), 2) as saldo
, cast(null as double) as saldo_rn1, round(coalesce(r.rebaje, 0), 2) as rebaje
from act a
full outer join reb r
  on r.componente = a.componente and r.d1 = a.d1 and r.arrastre = a.arrastre
 and r.reeng = a.reeng and r.dia = a.dia

union all

select 'real_pob', 'v2', 'nuevos', '', '', 0, arrastre, reeng, dia_entrada, count(*), round(sum(saldo), 2)
, cast(null as double), cast(null as double)
from entradas_saldo
group by 1, 2, 3, 4, 5, 6, 7, 8, 9

order by 1, 2, 3, 4, 5, 6, 7, 8, 9
;

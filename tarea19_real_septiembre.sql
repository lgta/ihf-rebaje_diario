-- =====================================================================
-- SEGUIMIENTO DE SEPTIEMBRE 2026 CONTRA LA META PUBLICADA -- real por dia,
-- los DOS enfoques en una sola corrida.
--
-- Copia de tarea19_real_agosto_cierre.sql con las fechas corridas un mes.
-- El real se mide con la MISMA definicion que la meta publicada el 1-sep
-- (motor unificado v3, definicion v1 de antiguo):
--   stock  = dias_atraso_cuota 1-30 en la ultima fila de AGOSTO, saldo Mambu
--            de esa fecha > 0
--   nuevos = transicion dias_atraso_cuota 0 -> 1 dentro de septiembre,
--            excluyendo el stock; saldo = el del dia anterior a la entrada
-- NO se mide con la definicion v2 (en mora el dia 1): esa es la de la
-- recalibracion de tarea 24 y va aparte (tarea24_v2_septiembre.sql).
--
-- Dos medidas por (componente, dia):
--   saldo_activado_dia : Enfoque alfa -- saldo COMPLETO del credito el dia de
--                        su primer pago del mes (activacion)
--   rebaje_dia         : Recupero oficial -- suma de max(saldo_ant - saldo, 0)
--                        de cada dia. La meta de recupero de septiembre es la
--                        primera con el motor migrado a dias_atraso_cuota
--                        (18e), asi que su real va con esta MISMA poblacion,
--                        no con dayslate como el de agosto.
--
-- La query trae todos los dias que haya; el corte al PENULTIMO dia (la foto
-- del dia en curso todavia esta corriendo) se hace en seguimiento_septiembre.py.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, mambu_dedup as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.fechaproceso between '20260825' and '20260930'
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, fotos as (
  select id_loan, fechaproceso, substr(fechaproceso,1,6) as periodo,
    cast(substr(fechaproceso,7,2) as int) as dia, saldo,
    lag(saldo) over (partition by id_loan order by fechaproceso) as saldo_ant
  from mambu_dedup where rn_dedup = 1
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-08-01') and date('2026-09-30')
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
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant,
    row_number() over (partition by id_loan order by fechaproceso) as nro_foto
  from dac
)
, stock_ids as (
  select id_loan, saldo_inicial from (
    select d.id_loan, f.saldo as saldo_inicial, d.mora,
      row_number() over (partition by d.id_loan order by d.fechaproceso desc) as rn
    from dac d
    join fotos f on f.id_loan = d.id_loan and f.fechaproceso = d.fechaproceso
    where substr(d.fechaproceso,1,6) = '202608'
  )
  where rn = 1 and mora between 1 and 30 and saldo_inicial > 0
)
, entradas as (
  select l.id_loan, l.fechaproceso as fecha_entrada
  from dac_lag l
  where l.nro_foto > 1 and l.mora_ant = 0 and l.mora = 1
    and substr(l.fechaproceso,1,6) = '202609'
    and not exists (select 1 from stock_ids s where s.id_loan = l.id_loan)
)
, entradas_saldo as (
  select e.id_loan, e.fecha_entrada, coalesce(f.saldo_ant, f.saldo) as saldo
  from entradas e
  join fotos f on f.id_loan = e.id_loan and f.fechaproceso = e.fecha_entrada
  where coalesce(f.saldo_ant, f.saldo) > 0
)
-- una fila por (componente, credito, episodio) y dia de septiembre con foto
, obs as (
  select 'stock' as componente, s.id_loan, '-' as fecha_entrada, s.saldo_inicial as saldo_ref,
         f.dia, f.saldo_ant, f.saldo
  from stock_ids s
  join fotos f on f.id_loan = s.id_loan and f.periodo = '202609'

  union all

  select 'nuevos', e.id_loan, e.fecha_entrada, e.saldo, f.dia, f.saldo_ant, f.saldo
  from entradas_saldo e
  join fotos f on f.id_loan = e.id_loan
    and f.periodo = '202609' and f.fechaproceso >= e.fecha_entrada
)
, primer_pago as (
  select componente, id_loan, fecha_entrada, saldo_ref, min(dia) as dia
  from obs where saldo_ant > saldo
  group by 1, 2, 3, 4
)
, act as (
  select componente, dia, count(*) as creditos_activados, sum(saldo_ref) as saldo_activado_dia
  from primer_pago group by 1, 2
)
, reb as (
  select componente, dia, sum(saldo_ant - saldo) as rebaje_dia
  from obs where saldo_ant > saldo
  group by 1, 2
)
, pob as (
  select 'stock' as componente, count(*) as creditos_pob, sum(saldo_inicial) as saldo_pob from stock_ids
  union all
  select 'nuevos', count(*), sum(saldo) from entradas_saldo
)
select coalesce(a.componente, r.componente) as componente
, coalesce(a.dia, r.dia)                    as dia
, coalesce(a.creditos_activados, 0)         as creditos_activados
, round(coalesce(a.saldo_activado_dia, 0), 2) as saldo_activado_dia
, round(coalesce(r.rebaje_dia, 0), 2)       as rebaje_dia
, p.creditos_pob
, round(p.saldo_pob, 2)                     as saldo_pob
from act a
full outer join reb r on r.componente = a.componente and r.dia = a.dia
join pob p on p.componente = coalesce(a.componente, r.componente)
order by 1, 2
;

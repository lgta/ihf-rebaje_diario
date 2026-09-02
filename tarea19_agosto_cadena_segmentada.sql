-- =====================================================================
-- TAREA 19 -- AGOSTO 2026 CERRADO, LA CADENA COMPLETA POR SEGMENTO.
--
-- Alimenta la explicacion "de capital asignado a capital asegurado" del
-- artifact. Las queries que ya existian daban solo el REAL activado; esta
-- da los DENOMINADORES tambien, que es lo que faltaba para poder mostrar
-- cada paso de la cadena como una division con sus dos terminos.
--
-- ANTIGUOS (stock) -- se asigna TODO al inicio del mes, de una sola vez:
--   stock_base : poblacion en mora 1-30 al cierre de julio (31-jul), por
--                (tramo, avance_band). Esto es el capital ASIGNADO.
--   stock_act  : de esa poblacion, la que hizo >=1 pago durante agosto.
--                Esto es el capital ASEGURADO.
--   -> ratio de activacion de antiguos = stock_act / stock_base
--
-- NUEVOS -- no se asignan de golpe: van entrando dia a dia segun vence
-- cada cuota, y la entrada en mora es vencimiento + 1 dia.
--   nuevos_cal : capital de las cuotas que VENCEN (indexado por dia de
--                entrada = vencimiento+1). Es el universo elegible, NO
--                capital asignado todavia -- la mayoria paga a tiempo.
--   nuevos_ent : de ese calendario, el que efectivamente ENTRO en mora
--                (dias_atraso_cuota 0->1). Esto es el capital ASIGNADO.
--   nuevos_act : de los que entraron, los que hicieron >=1 pago en el mes.
--                Esto es el capital ASEGURADO.
--   -> tasa de entrada        = nuevos_ent / nuevos_cal
--   -> ratio de activacion    = nuevos_act / nuevos_ent
--
-- Los dos ratios son DISTINTOS y se aplican en momentos distintos de la
-- cadena -- confundirlos es el error que 18b diagnostico (bug 10 es el
-- caso donde salio caro). Antiguos NO tiene tasa de entrada: ya estan
-- todos en mora al empezar el mes.
--
-- Grano de salida: tipo, tramo, avance_band, dia_entrada, creditos, saldo.
-- `dia_entrada` solo aplica a nuevos (0 en stock). El dia de semana del
-- vencimiento se deriva en Python desde dia_entrada, no hace falta acá.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , substr(a.fechaproceso,1,6) as periodo
  , cast(substr(a.fechaproceso,7,2) as int) as dia
  , a.balances_principalbalance as saldo
  , b.amountfinanced
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso) as saldo_ant
  from (
    select *, row_number() over (
        partition by _datos_adicionales_loan_accounts_id_ihfintech, fechaproceso
        order by (case when balances_principalbalance <> 0 then 0 else 1 end),
                 lastmodifieddate desc, id desc) as rn_dedup
    from dts_mambu_loans_hist
    where fechaproceso between '20260725' and '20260901'
  ) a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where a.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
    and b.amountfinanced > 0
)
, dac as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-07-01') and date('2026-08-31')
)
, dac_lag as (
  select id_loan, fechaproceso, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant,
    row_number() over (partition by id_loan order by fechaproceso) as nro_foto
  from dac
)
-- ---------- ANTIGUOS: asignado al 1-ago ----------
, stock_base as (
  select id_loan, saldo_inicial, amountfinanced, mora from (
    select d.id_loan, f.saldo as saldo_inicial, f.amountfinanced, d.mora,
      row_number() over (partition by d.id_loan order by d.fechaproceso desc) as rn
    from dac d
    join fotos f on f.id_loan = d.id_loan and f.fechaproceso = d.fechaproceso
    where substr(d.fechaproceso,1,6) = '202607'
  )
  where rn = 1 and mora between 1 and 30 and saldo_inicial > 0
)
, stock_seg as (
  select id_loan, saldo_inicial
  , case when mora between 1 and 8 then 'a. 1-8'
         when mora between 9 and 15 then 'b. 9-15'
         else 'c. 16-30' end as tramo
  , case when saldo_inicial >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo_inicial >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo_inicial >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from stock_base
)
-- ---------- NUEVOS: calendario, entradas, activaciones ----------
, calendario as (
  select
    c.id_ihfintech_loan as id_loan
  , cast(day(date_add('day',1,c.fechavencimiento)) as int) as dia_entrada
  , f.saldo
  , case when f.saldo >= 0.9*f.amountfinanced then 'a. avance <10%'
         when f.saldo >= 0.6*f.amountfinanced then 'b. avance 10-40%'
         when f.saldo >= 0.3*f.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  , row_number() over (partition by c.id_ihfintech_loan order by c.fechavencimiento) as rn
  from dts_cobranza_creditos_cuotas c
  join fotos f on f.id_loan = c.id_ihfintech_loan
              and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
  where c.status in ('ACTIVE','COMPLETED')
    and c.flg_last_loan_in_chain = 1
    and date_add('day',1,c.fechavencimiento) >= date('2026-08-01')
    and date_add('day',1,c.fechavencimiento) <= date('2026-08-31')
    and f.saldo > 0
)
, calendario_final as (
  select * from calendario c
  where c.rn = 1
    and not exists (select 1 from stock_base s where s.id_loan = c.id_loan)
)
, entradas as (
  select l.id_loan, cast(substr(l.fechaproceso,7,2) as int) as dia_entrada
  from dac_lag l
  where l.nro_foto > 1 and l.mora_ant = 0 and l.mora = 1
    and substr(l.fechaproceso,1,6) = '202608'
    and not exists (select 1 from stock_base s where s.id_loan = l.id_loan)
)
-- ---------- salida ----------
select 'stock_base' as tipo, tramo, avance_band, 0 as dia_entrada
     , count(*) as creditos, round(sum(saldo_inicial),2) as saldo
from stock_seg group by 1,2,3,4
union all
select 'stock_act', s.tramo, s.avance_band, 0
     , count(distinct s.id_loan), round(sum(distinct_saldo),2)
from (
  select s.id_loan, s.tramo, s.avance_band, max(s.saldo_inicial) as distinct_saldo
  from stock_seg s
  join fotos f on f.id_loan = s.id_loan and f.periodo = '202608'
  where f.saldo_ant > f.saldo
  group by 1,2,3
) s group by 1,2,3,4
union all
select 'nuevos_cal', '', c.avance_band, c.dia_entrada
     , count(*), round(sum(c.saldo),2)
from calendario_final c group by 1,2,3,4
union all
select 'nuevos_ent', '', c.avance_band, c.dia_entrada
     , count(*), round(sum(c.saldo),2)
from calendario_final c
join entradas e on e.id_loan = c.id_loan and e.dia_entrada = c.dia_entrada
group by 1,2,3,4
union all
select 'nuevos_act', '', a.avance_band, a.dia_entrada
     , count(*), round(sum(a.saldo),2)
from (
  select c.id_loan, c.avance_band, c.dia_entrada, max(c.saldo) as saldo
  from calendario_final c
  join entradas e on e.id_loan = c.id_loan and e.dia_entrada = c.dia_entrada
  join fotos f on f.id_loan = c.id_loan and f.periodo = '202608'
                and cast(substr(f.fechaproceso,7,2) as int) >= c.dia_entrada
  where f.saldo_ant > f.saldo
  group by 1,2,3
) a group by 1,2,3,4
order by 1,2,3,4
;

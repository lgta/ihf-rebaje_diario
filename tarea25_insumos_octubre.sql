-- =====================================================================
-- TAREA 25 -- INSUMOS DE LA META DE OCTUBRE 2026, la primera con el motor v2
-- (antiguo = en mora 1-30 el dia 1; adoptado 2026-09-13). Salida para
-- `python meta_v2.py 202610 datos_tarea25/insumos_octubre.csv`.
--
-- CORRER EL 2-OCT O DESPUES: la foto del dia en curso esta incompleta, y el
-- stock v2 se lee de la fila del 1-oct de calendario_diario. Leido mas tarde
-- no mira adelante: como en tarea24_v2_septiembre_al_1.sql (de la que es copia
-- con las fechas corridas un mes), el calendario acepta ACTIVE o COMPLETED
-- para todo credito con saldo > 0 al 30-sep, y refin_post devuelve al universo
-- a quien tuvo su reenganche desde el 1-oct.
--
-- v2 = la meta. v1 = referencia de lo que habria dado el motor anterior.
-- En v2 el calendario toma UNA cuota por credito: la primera con entrada desde
-- el dia 2 (misma base que la tasa, orden_d2 = 1 en
-- tarea24_v2_calendario_tasa.sql). Octubre sigue a un mes de 30 dias, asi que
-- es de los que traen dos cuotas del mismo credito (bug 23): la del 30-sep
-- entra el 1-oct (stock si entro) y la del 30-oct entra el 31.
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
, stock_seg as (
  select s.definicion, s.id_loan, s.saldo, s.d1, s.reeng, s.refin_post
  , case when s.mora between 1 and 8  then 'a. 1-8'
         when s.mora between 9 and 15 then 'b. 9-15'
         else                              'c. 16-30' end as tramo
  , case when s.saldo >= 0.9*s.amountfinanced then 'a. avance <10%'
         when s.saldo >= 0.6*s.amountfinanced then 'b. avance 10-40%'
         when s.saldo >= 0.3*s.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  , case when m.dni is not null then 1 else 0 end as arrastre
  from stock s
  left join dni_mora30 m on m.dni = s.dni
)
, cal as (
  select c.id_ihfintech_loan as id_loan
  , cast(day(date_add('day', 1, c.fechavencimiento)) as int) as dia_entrada
  , a.saldo, a.amountfinanced, a.reeng, a.refin_post
  , case when c.status = 'ACTIVE' and a.status = 'ACTIVE' then 1 else 0 end as activo_hoy
  , row_number() over (partition by c.id_ihfintech_loan order by c.fechavencimiento) as rn
  , row_number() over (
      partition by c.id_ihfintech_loan,
                   case when day(date_add('day', 1, c.fechavencimiento)) >= 2 then 1 else 0 end
      order by c.fechavencimiento) as rn_grupo
  from dts_cobranza_creditos_cuotas c
  join ancla_final a on a.id_loan = c.id_ihfintech_loan
  where c.status in ('ACTIVE','COMPLETED') and a.status in ('ACTIVE','COMPLETED')
    and date_add('day', 1, c.fechavencimiento) between date '2026-10-01' and date '2026-10-31'
)
, cal_def as (
  select 'v1' as definicion, cal.* from cal
  where not exists (select 1 from stock s where s.definicion = 'v1' and s.id_loan = cal.id_loan)
  union all
  select 'v2', cal.* from cal
  where cal.dia_entrada >= 2 and cal.rn_grupo = 1
    and not exists (select 1 from stock s where s.definicion = 'v2' and s.id_loan = cal.id_loan)
)
select 'insumo' as bloque, definicion, 'stock' as componente, tramo, avance_band, d1, arrastre
, reeng, refin_post, 1 as activo_hoy, 0 as dia
, count(*) as creditos, round(sum(saldo), 2) as saldo, round(sum(saldo), 2) as saldo_rn1
from stock_seg
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11

union all

select 'insumo', definicion, 'calendario', ''
, case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
       when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
       when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end
, 0, 0, reeng, refin_post, activo_hoy, dia_entrada
, count(distinct id_loan), round(sum(saldo), 2), round(sum(case when rn = 1 then saldo else 0 end), 2)
from cal_def
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11

order by 2, 3, 11, 4, 5
;

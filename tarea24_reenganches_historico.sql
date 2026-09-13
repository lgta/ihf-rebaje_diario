-- =====================================================================
-- TAREA 24 -- ¿CUANTO PESA EL FILTRO DE REENGANCHES QUE MIRA HACIA ADELANTE?
--
-- Pedido del usuario 2026-09-13: medirlo para ir viendo; la DECISION queda
-- pendiente (anotada en PENDIENTES.md tarea 24).
--
-- El hallazgo: flg_last_loan_in_chain es constante por credito y se lee con
-- la foto de HOY. Un credito que el dia 1 del mes M estaba vigente y en mora,
-- y que se refinancio DESPUES, hoy tiene flag 0 -- y la calibracion lo borra
-- de la historia de M. En la reconciliacion de septiembre fueron 13 creditos
-- (S/18,575), todos refinanciados entre el 2 y el 11-sep.
--
-- Se mide, mes a mes (202504-202609), sobre las poblaciones de la
-- definicion v2 (la que va a usar la recalibracion):
--   stock  = dias_atraso_cuota 1-30 el DIA 1 del mes
--   nuevos = entrada en mora (dias_atraso_cuota = 1) del dia 2 en adelante,
--            excluyendo el stock del mes, una por credito-mes
-- cuanto de cada una tiene flag 0, y CUANDO Mambu cerro esos creditos por
-- refinanciamiento/reprogramacion: antes, dentro o despues del mes.
--   - "dentro del mes": si se incluyeran, el saldo cae a 0 por el
--     refinanciamiento y se contaria como pago -- activacion falsa.
--   - "despues del mes": el mes se calibro sin ellos, pero al proyectar no
--     se puede saber quien se va a refinanciar -- es el sesgo de mirar adelante.
--
-- Saldo: foto Mambu del ultimo dia del mes anterior (la misma convencion con
-- la que la meta ancla el calendario). Status ACTIVE/COMPLETED: verificado
-- que no mira adelante -- los 30,184 creditos con flag 0 estan todos en
-- COMPLETED; el filtro solo saca DELETED/REQUESTED.
-- Septiembre 2026 es parcial (entradas al 12-sep).
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, prestamos as (
  select b.id_ihfintech_loan as id_loan, coalesce(lc.last_in_chain, 1) as last_in_chain
  from dts_okaapi_loans b
  left join loan_chain lc on lc.id_ihfintech_loan = b.id_ihfintech_loan
  where b.status in ('ACTIVE','COMPLETED') and b.amountfinanced > 0
)
-- primer dia en que Mambu muestra el credito cerrado por refinanciamiento/reprogramacion
, cierre_refin as (
  select _datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , min(date(date_parse(cast(fechaproceso as varchar), '%Y%m%d'))) as f_cierre
  , min_by(accountsubstate, fechaproceso) as substate
  from dts_mambu_loans_hist
  where accountsubstate in ('REFINANCED', 'RESCHEDULED')
  group by 1
)
-- saldo Mambu al ultimo dia del mes anterior (dedup de bug 11: el no-cero gana)
, saldo_cierre as (
  select _datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , date_add('day', 1, date(date_parse(cast(fechaproceso as varchar), '%Y%m%d'))) as d1
  , max(balances_principalbalance) as saldo
  from dts_mambu_loans_hist
  where fechaproceso in ('20250331','20250430','20250531','20250630','20250731','20250831',
                         '20250930','20251031','20251130','20251231','20260131','20260228',
                         '20260331','20260430','20260531','20260630','20260731','20260831')
  group by 1, 2
)
-- mora el dia 1 de cada mes (define el stock v2)
, mora_d1 as (
  select id_ihfintech_loan as id_loan, fecha_calendario as d1,
         max(coalesce(dias_atraso_cuota, 0)) as m
  from dts_cobranza_creditos_calendario_diario
  where fecha_calendario between date '2025-04-01' and date '2026-09-01'
    and day(fecha_calendario) = 1
  group by 1, 2
)
-- entradas en mora del dia 2 en adelante, una por credito-mes
, entradas as (
  select id_ihfintech_loan as id_loan, date_trunc('month', fecha_calendario) as d1
  from dts_cobranza_creditos_calendario_diario
  where fecha_calendario between date '2025-04-02' and date '2026-09-12'
    and day(fecha_calendario) >= 2
    and dias_atraso_cuota = 1
  group by 1, 2
)
, pobl as (
  select 'stock' as pob, m.d1, m.id_loan, s.saldo
  from mora_d1 m
  join saldo_cierre s on s.id_loan = m.id_loan and s.d1 = m.d1
  where m.m between 1 and 30 and s.saldo > 0

  union all

  select 'nuevos', e.d1, e.id_loan, s.saldo
  from entradas e
  join saldo_cierre s on s.id_loan = e.id_loan and s.d1 = e.d1
  left join mora_d1 m on m.id_loan = e.id_loan and m.d1 = e.d1 and m.m between 1 and 30
  where m.id_loan is null and s.saldo > 0
)
select
  date_format(p.d1, '%Y%m') as mes
, p.pob
, case when pr.last_in_chain = 1 then 'a. ultimo de su cadena (queda)'
       when cr.f_cierre is null then 'b. flag 0, sin cierre REFINANCED/RESCHEDULED'
       when cr.f_cierre < p.d1 then 'c. flag 0, cerrado antes del dia 1'
       when cr.f_cierre <= last_day_of_month(p.d1)
         then 'd. flag 0, ' || lower(cr.substate) || ' DENTRO del mes'
       else 'e. flag 0, ' || lower(cr.substate) || ' DESPUES del mes' end as bucket
, count(*)             as creditos
, round(sum(p.saldo), 2) as saldo
from pobl p
join prestamos pr on pr.id_loan = p.id_loan
left join cierre_refin cr on cr.id_loan = p.id_loan
group by 1, 2, 3
order by 1, 2, 3
;

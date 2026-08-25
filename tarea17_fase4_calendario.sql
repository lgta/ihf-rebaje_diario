-- =====================================================================
-- TAREA 17, FASE 4 -- Q-D: CALENDARIO UNIFICADO (frontier-adjusted)
-- abril, mayo, junio y julio 2026 en una sola corrida.
--
-- Reemplaza los DOS calendarios de hoy (el de "nuevos", indexado por
-- fechavencimiento dentro del mes, y el de fantasma, frontier-adjusted
-- con date_add('day',1,...)) por UNO solo, indexado por el DIA DE
-- ENTRADA (= fechavencimiento + 1 dia) dentro del mes.
--
-- Por que indexar por dia de entrada y no por vencimiento: la curva se
-- calibra desde la entrada, asi que el proyector queda
-- dias_desde_entrada = d - dia_entrada, sin correcciones. El indice
-- corrido de bug 18 (d - dd - 1) se vuelve estructuralmente imposible,
-- y el hueco de frontera de bug 14/17 (cuota vencida el ultimo dia del
-- mes anterior) queda incluido por construccion en dia_entrada = 1.
--
-- Excluye el stock del mes (dias_atraso_cuota 1-30 al cierre del mes
-- anterior) -- misma regla que el resto de Fase 4.
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, dac_raw as (
  select
    c.id_ihfintech_loan                        as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d')  as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0)           as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-03-01') and date('2026-06-30')
)
, dac as (
  select d.id_loan, d.fechaproceso, d.mora
  from dac_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain, 1) = 1
)
, stock_ids as (
  select
    date_format(date_add('month',1,date_parse(periodo,'%Y%m')), '%Y%m') as periodo_target
  , id_loan
  from (
    select substr(fechaproceso,1,6) as periodo, id_loan, mora,
      row_number() over (partition by id_loan, substr(fechaproceso,1,6)
                         order by fechaproceso desc) as rn
    from dac
  )
  where rn = 1 and mora between 1 and 30
)
select
  date_format(date_add('day',1,c.fechavencimiento), '%Y%m')  as periodo
, cast(day(date_add('day',1,c.fechavencimiento)) as int)     as dia_entrada
, case when f.saldo >= 0.9*b.amountfinanced then 'a. avance <10%'
       when f.saldo >= 0.6*b.amountfinanced then 'b. avance 10-40%'
       when f.saldo >= 0.3*b.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end                             as avance_band
, count(distinct c.id_ihfintech_loan)                        as creditos
, round(sum(f.saldo), 2)                                     as saldo_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
join (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260331' and '20260730'
) f
  on f.id_loan = c.id_ihfintech_loan
 and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
 and f.rn_dedup = 1
where c.status in ('ACTIVE','COMPLETED')
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento >= date('2026-03-31')
  and c.fechavencimiento <= date('2026-07-30')
  and b.amountfinanced > 0
  and not exists (
    select 1 from stock_ids s
    where s.periodo_target = date_format(date_add('day',1,c.fechavencimiento), '%Y%m')
      and s.id_loan = c.id_ihfintech_loan
  )
group by 1,2,3
order by 1,2,3
;

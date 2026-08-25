-- =====================================================================
-- TAREA 17 FASE 4 (hallazgo lateral) -- Calendario fantasma de ABRIL
-- reconstruido SIN excluir `entradas_reales`, igual que mayo y julio.
--
-- bt_calendario_fantasma_abril.csv (BT-ASEG-ABR-CALFANT) excluye
-- `entradas_reales_abril` del denominador. Ningun otro mes lo hace, y
-- P_FANTASMA se calibra (enfoque_capital_asegurado.sql Q3 /
-- tarea17_fase3_curva_fantasma.sql, CTE `calendario_mes`) sobre un
-- denominador que excluye SOLO el stock. Tasa y denominador quedan de
-- distinta definicion -> proy_fantasma de abril subestimado.
--
-- Esta query replica el denominador correcto (frontier-adjusted,
-- excluye solo el stock de abril medido con dayslate -- misma regla que
-- el resto del backtest de produccion, NO dias_atraso_cuota, para que el
-- numero de abril siga siendo comparable con mayo/junio/julio).
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, raw as (
  select
    a.fechaproceso, a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.balances_principalbalance as saldo, a.dayslate, a.lastmodifieddate, a.id
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20260301' and '20260430'
)
, dedup as (
  select *, row_number() over (
      partition by id_loan, fechaproceso
      order by (case when saldo <> 0 then 0 else 1 end), lastmodifieddate desc, id desc) as rn_dedup
  from raw
)
, fotos as (
  select d.fechaproceso, d.id_loan, d.saldo, coalesce(d.dayslate,0) as mora
  from dedup d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
  where d.rn_dedup = 1
    and b.status in ('ACTIVE','COMPLETED')
    and coalesce(lc.last_in_chain,1) = 1
)
, cierre_marzo as (
  select id_loan, mora, saldo,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260331'
)
, stock_abril_ids as (
  select id_loan from cierre_marzo where rn = 1 and mora between 1 and 30 and saldo > 0
)
select
  date_format(c.fechavencimiento, '%Y-%m-%d') as fechavencimiento
, round(sum(f.saldo), 2)                      as saldo_en_riesgo
, count(distinct c.id_ihfintech_loan)         as cuotas
from dts_cobranza_creditos_cuotas c
join fotos f on f.id_loan = c.id_ihfintech_loan
            and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
where c.status in ('ACTIVE','COMPLETED')
  and c.flg_last_loan_in_chain = 1
  and date_add('day', 1, c.fechavencimiento) >= date('2026-04-01')
  and date_add('day', 1, c.fechavencimiento) <= date('2026-04-30')
  and c.id_ihfintech_loan not in (select id_loan from stock_abril_ids)
group by 1
order by 1
;

-- =====================================================================
-- TAREA 22 -- LA OTRA PUNTA: ¿donde estan los 592 creditos (S/810,573)
-- que NOSOTROS tenemos como stock del 1-sep y la vista NO marca en
-- TEMPRANA/antiguo?
--
-- La reconciliacion ya explico el lado "solo la vista" (99.7% son la
-- cohorte que vencio el 31-ago y entro en mora el 1-sep, que para
-- nosotros son NUEVOS del dia 1, no stock). Falta el lado espejo, para
-- que el cuadre quede completo y sin residuo sin nombre.
--
-- Hipotesis a distinguir, sin asumir ninguna:
--   - estan en la vista pero en OTRA fase (ESPECIALIZADA / RECOVERY), por
--     escalamiento -- en la reconciliacion de julio (bug 14) el arrastre
--     de mora por DNI mandaba creditos a fases mas duras;
--   - estan en la vista, en TEMPRANA, pero clasificados 'nuevo' o 'sin mora';
--   - estan en grupo de CONTROL (deliberadamente no gestionados) -- en
--     julio eso explico el 82% de "solo nuestro";
--   - no aparecen en la vista para 202609 en absoluto.
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
, dac_cierre as (
  select id_loan, mora from (
    select c.id_ihfintech_loan as id_loan, coalesce(c.dias_atraso_cuota,0) as mora,
      row_number() over (partition by c.id_ihfintech_loan order by c.fecha_calendario desc) as rn
    from dts_cobranza_creditos_calendario_diario c
    where c.fecha_calendario between date('2026-08-01') and date('2026-08-31')
  ) where rn = 1
)
, nuestro_stock as (
  select a.id_loan, a.saldo, d.mora
  from ancla_final a
  join dac_cierre d on d.id_loan = a.id_loan
  where d.mora between 1 and 30 and a.status in ('ACTIVE','COMPLETED')
)
-- toda la vista de 202609, sin filtrar fase ni tipo_mora
, vista_sep as (
  select id_ihfintech_loan as id_loan, fase_estrategia, tipo_mora, grupo_control,
         dias_mora_inicio, monto_asignado
  from (
    select v.*, row_number() over (
      partition by v.id_ihfintech_loan order by v.fecha) as rn
    from vw_seguimiento_diario_cohorte_tramo v
    where v.mes_asignacion = '202609'
  ) where rn = 1
)
select
  coalesce(vs.fase_estrategia, '(no aparece en la vista para 202609)') as fase
, coalesce(vs.tipo_mora, '-')                                         as tipo_mora
, coalesce(vs.grupo_control, '(null)')                                as grupo_control
, count(*)                                                            as creditos
, round(sum(n.saldo), 2)                                              as saldo_nuestro
, round(avg(cast(n.mora as double)), 1)                               as prom_mora_nuestra
from nuestro_stock n
left join vista_sep vs on vs.id_loan = n.id_loan
where not (vs.fase_estrategia = 'TEMPRANA' and vs.tipo_mora = 'antiguo')
   or vs.id_loan is null
group by 1,2,3
order by 5 desc
;

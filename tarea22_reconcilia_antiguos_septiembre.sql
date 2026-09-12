-- =====================================================================
-- TAREA 22 -- ¿POR QUE NUESTROS "ANTIGUOS" DE SEPTIEMBRE (S/3.76M) SON
-- MENORES QUE TEMPRANA DE vw_seguimiento_diario_cohorte_tramo (~S/4.9M)?
--
-- Pregunta del usuario, 2026-09-02. Es el "principio de universo" de
-- CLAUDE.md: la diferencia se EXPLICA con datos, no se asume.
--
-- Bloque 1 -- COMO SE COMPONE LA VISTA. Una fila por credito (la del
--   anclaje) para mes_asignacion 202609 y 202608, abierta por
--   fase_estrategia x tipo_mora x grupo_control. Sirve para saber, antes
--   que nada, si los S/4.9M que ve el usuario son ANTIGUO solo o
--   ANTIGUO + NUEVO, y si incluyen el grupo de CONTROL (que en la
--   reconciliacion de julio explico el 82% de "solo nuestro", bug 14).
--
-- Bloque 2 -- RANGO DE MORA DE LA VISTA. Nuestro stock es estrictamente
--   `dias_atraso_cuota` entre 1 y 30 al cierre del mes anterior. Si
--   TEMPRANA incluye dias_mora fuera de 1-30, esa sola diferencia de
--   definicion podria explicar todo el gap. Se abre `dias_mora_inicio` en
--   tramos para verlo (columna `dias_mora_inicio`).
--
-- OJO con `monto_asignado`: FUENTES_DATOS.md advierte no usarlo como
-- sustituto del saldo Mambu para NUESTRO calculo (es el mismo campo
-- monto_capital_pendiente que bug 5 desaconseja). Aca se usa a proposito,
-- porque es EL numero que reporta la tabla oficial y contra el que el
-- usuario esta comparando -- reconciliar, no adoptar.
--
-- Bloque 3 -- RECONCILIACION CREDITO A CREDITO contra NUESTRO stock del
--   1-sep (el mismo `stock_agosto` de tarea19_meta_septiembre_insumos.sql,
--   copiado tal cual). Clasifica en: en ambos / solo la vista / solo
--   nuestro, y para "solo la vista" identifica el MOTIVO -- que es lo que
--   hay que poder nombrar:
--     - lo excluye nuestro filtro flg_last_loan_in_chain (reenganches)
--     - status del credito fuera de ACTIVE/COMPLETED
--     - no tiene foto Mambu al 31-ago con saldo > 0
--     - dias_atraso_cuota fuera de 1-30 para nosotros al cierre de agosto
--       (incluye el caso mora=0, el punto ciego que bug 14 cuantifico en
--       ~27% de TEMPRANA cuando el motor usaba `dayslate` -- desde
--       2026-08-25 el motor usa dias_atraso_cuota y deberia haberse
--       cerrado casi todo; esta query lo verifica)
--     - ningun motivo identificado  <- si esto es grande, hay algo nuevo
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
-- ---------- NUESTRO stock del 1-sep, identico a la meta vigente ----------
, mambu_ago as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , b.amountfinanced
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
, ancla as (
  select id_loan, saldo, amountfinanced, status,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from mambu_ago where rn_dedup = 1
)
, ancla_final as (
  select id_loan, saldo, amountfinanced, status from ancla where rn = 1 and saldo > 0
)
, dac_cierre as (
  select id_loan, mora, rn from (
    select
      c.id_ihfintech_loan as id_loan
    , coalesce(c.dias_atraso_cuota, 0) as mora
    , row_number() over (partition by c.id_ihfintech_loan
                         order by c.fecha_calendario desc) as rn
    from dts_cobranza_creditos_calendario_diario c
    where c.fecha_calendario between date('2026-08-01') and date('2026-08-31')
  ) where rn = 1
)
, nuestro_stock as (
  select a.id_loan, a.saldo, d.mora
  from ancla_final a
  join dac_cierre d on d.id_loan = a.id_loan
  where d.mora between 1 and 30
    and a.status in ('ACTIVE','COMPLETED')
)
-- ---------- LA VISTA, una fila por credito (el anclaje) ----------
, vista as (
  select id_ihfintech_loan as id_loan, mes_asignacion, fase_estrategia, tipo_mora,
         grupo_control, dias_mora_inicio, monto_asignado
  from (
    select v.*, row_number() over (
      partition by v.id_ihfintech_loan, v.mes_asignacion order by v.fecha) as rn
    from vw_seguimiento_diario_cohorte_tramo v
    where v.mes_asignacion in ('202608','202609')
  ) where rn = 1
)
-- =====================================================================
select
  '1. composicion de la vista' as bloque
, mes_asignacion               as k1
, fase_estrategia              as k2
, coalesce(tipo_mora,'(null)') as k3
, coalesce(grupo_control,'(null)') as k4
, count(*)                     as creditos
, round(sum(monto_asignado), 2) as saldo
from vista
group by 1,2,3,4,5

union all

select
  '2. rango de mora en TEMPRANA'
, mes_asignacion
, coalesce(tipo_mora,'(null)')
, case when dias_mora_inicio is null then 'z. null'
       when dias_mora_inicio < 1     then 'a. 0 o menos'
       when dias_mora_inicio <= 8    then 'b. 1-8'
       when dias_mora_inicio <= 15   then 'c. 9-15'
       when dias_mora_inicio <= 30   then 'd. 16-30'
       else                              'e. 31+' end
, ''
, count(*)
, round(sum(monto_asignado), 2)
from vista
where fase_estrategia = 'TEMPRANA'
group by 1,2,3,4,5

union all

-- ---------- bloque 3: reconciliacion credito a credito ----------
select
  '3. reconciliacion (202609, TEMPRANA, ANTIGUO)'
, case when v.id_loan is not null and n.id_loan is not null then 'a. en ambos'
       when n.id_loan is not null                           then 'b. solo nuestro'
       else                                                      'c. solo la vista' end
, case
    when v.id_loan is not null and n.id_loan is not null then '-'
    when n.id_loan is not null then '-'
    when coalesce(lc.last_in_chain, 1) <> 1 then 'c1. lo excluye flg_last_loan_in_chain'
    when ok.status is null or ok.status not in ('ACTIVE','COMPLETED')
      then 'c2. status fuera de ACTIVE/COMPLETED'
    when af.id_loan is null then 'c3. sin foto Mambu al cierre de ago con saldo > 0'
    when dc.mora is null then 'c4. sin fila en calendario_diario'
    when dc.mora = 0 then 'c5. dias_atraso_cuota = 0 para nosotros'
    when dc.mora > 30 then 'c6. dias_atraso_cuota > 30 para nosotros'
    else 'c7. SIN MOTIVO IDENTIFICADO' end
, ''
, ''
, count(*)
, round(sum(coalesce(v.monto_asignado, n.saldo)), 2)
from (select * from vista
      where mes_asignacion = '202609' and fase_estrategia = 'TEMPRANA'
        and tipo_mora = 'antiguo') v   -- OJO: la vista trae tipo_mora en MINUSCULA
full outer join nuestro_stock n on n.id_loan = v.id_loan
left join loan_chain lc  on lc.id_ihfintech_loan = v.id_loan
left join dts_okaapi_loans ok on ok.id_ihfintech_loan = v.id_loan
left join ancla_final af on af.id_loan = v.id_loan
left join dac_cierre dc on dc.id_loan = v.id_loan
group by 1,2,3

order by 1,2,3,4
;

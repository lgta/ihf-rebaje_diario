-- =====================================================================
-- TAREA 24 -- VALIDACION DEL FIX CON SEPTIEMBRE: COMO DIMENSIONA v2 EL STOCK Y
-- LOS NUEVOS, CONTRA LO QUE PASO (al 12-sep, ultimo dia completo).
--
-- Pedido del usuario 2026-09-13: correr el backtest de septiembre sobre la logica
-- que dimensiona nuevos y stock, y con eso validar el fix.
--
-- STOCK: con v2 no se estima cuanto hay: se OBSERVA el dia 1. Su validacion es el
-- cuadre credito a credito contra la vista (tarea24_reconcilia_antiguos_sep_v2.sql:
-- 2,751 en ambos, +0.5%). Lo que se proyecta es cuanto ACTIVA, y eso lo mide
-- backtest_septiembre_v2.py contra el real.
-- NUEVOS: la meta dimensiona el flujo como calendario x tasa. Bloques:
--   B.  nuestras entradas v2 (dias 2-12) contra los NUEVOS de TEMPRANA que asigno el
--       negocio, credito a credito, con el motivo de cada diferencia. El anclaje de la
--       vista se replica desde dts_asignaciones_gestiones_cobranza (bug 27: la vista
--       referenciada varias veces agota recursos).
--   B2. lo mismo por dia: nuestras entradas del dia d y las asignaciones del dia d.
--   C.  tasa de entrada REALIZADA en los dias 2-12 de cada mes (202601-202609), misma
--       definicion que tarea24_v2_calendario_tasa.sql (v2: sin stock v2, una cuota por
--       credito -- la primera con entrada desde el dia 2 --, sin reenganches, saldo al
--       vencimiento): ¿septiembre se sale de lo historico?
--   D.  entradas reales v2 de septiembre por (dia, banda, arrastre|reeng): el volumen
--       REAL, para proyectar la activacion con la curva sin el error de volumen.
--   E.  calendario MEDIDO de septiembre por (dia, banda), con el saldo al vencimiento
--       en vez del cierre de agosto: separa el efecto del ancla del de la tasa.
-- Columnas: bloque, k1, k2, k3, creditos, saldo_1, saldo_2.
--   B/B2: saldo_1 = saldo de entrada nuestro, saldo_2 = monto asignado en la vista
--   C/E:  saldo_1 = elegibles, saldo_2 = los que entraron
--   D:    saldo_1 = saldo de entrada
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
, dac as (
  select c.id_ihfintech_loan as id_loan, c.fecha_calendario as fecha
  , coalesce(c.dias_atraso_cuota, 0) as mora, c.dni
  from dts_cobranza_creditos_calendario_diario c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  where p.status in ('ACTIVE','COMPLETED')
    and c.fecha_calendario between date '2025-12-31' and date '2026-09-12'
)
, dac_lag as (
  select id_loan, fecha, mora, dni
  , lag(mora) over (partition by id_loan order by fecha) as mora_ant
  from dac
)
, st_v2 as (
  select id_loan, fecha as mes from dac where day(fecha) = 1 and mora between 1 and 30
)
, entradas as (
  -- primera entrada 0 -> 1 entre el dia 2 y el 12 de cada mes
  select date_trunc('month', fecha) as mes, id_loan, min(fecha) as f_ent, min_by(dni, fecha) as dni
  from dac_lag
  where mora_ant = 0 and mora = 1 and day(fecha) between 2 and 12
    and fecha >= date '2026-01-02'
  group by 1, 2
)
, saldo_dia as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20251231' and '20260912'
)
, cal as (
  select c.id_ihfintech_loan as id_loan
  , date_trunc('month', date_add('day', 1, c.fechavencimiento)) as mes
  , day(date_add('day', 1, c.fechavencimiento)) as dia_entrada
  , f.saldo, p.amountfinanced, p.reeng
  , row_number() over (
      partition by c.id_ihfintech_loan, date_trunc('month', date_add('day', 1, c.fechavencimiento)),
                   case when day(date_add('day', 1, c.fechavencimiento)) >= 2 then 1 else 0 end
      order by c.fechavencimiento) as rn_grupo
  from dts_cobranza_creditos_cuotas c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  join saldo_dia f on f.id_loan = c.id_ihfintech_loan
    and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d') and f.rn_dedup = 1
  where c.status in ('ACTIVE','COMPLETED')
    and c.fechavencimiento between date '2026-01-01' and date '2026-09-11'
)
, cal_v2 as (
  -- calendario v2 de los dias 2-12, con si el credito entro en mora en esos dias
  select cal.*
  , case when e.id_loan is not null then 1 else 0 end as entra
  , case when cal.saldo >= 0.9*cal.amountfinanced then 'a. avance <10%'
         when cal.saldo >= 0.6*cal.amountfinanced then 'b. avance 10-40%'
         when cal.saldo >= 0.3*cal.amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from cal
  left join st_v2 s    on s.id_loan = cal.id_loan and s.mes = cal.mes
  left join entradas e on e.id_loan = cal.id_loan and e.mes = cal.mes
  where cal.rn_grupo = 1 and cal.dia_entrada between 2 and 12 and s.id_loan is null
)
, dni_mora30 as (
  select distinct c.fecha_calendario as fecha, c.dni
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date '2026-09-02' and date '2026-09-12'
    and c.dias_atraso_cuota > 30
    and c.dni is not null
)
, nuevos_sep as (
  -- nuestras entradas v2 de septiembre: dias 2-12, sin el stock v2
  select e.id_loan, e.f_ent, p.reeng, p.amountfinanced
  , f.saldo as saldo_entrada
  , case when m.dni is not null then 1 else 0 end as arrastre
  from entradas e
  join prestamos p on p.id_loan = e.id_loan
  left join st_v2 s on s.id_loan = e.id_loan and s.mes = e.mes
  left join saldo_dia f on f.id_loan = e.id_loan and f.rn_dedup = 1
    and f.fechaproceso = date_format(date_add('day', -1, e.f_ent), '%Y%m%d')
  left join dni_mora30 m on m.fecha = e.f_ent and m.dni = e.dni
  where e.mes = date '2026-09-01' and s.id_loan is null
)
, cura as (
  select n.id_loan, max(case when d.mora = 0 then 1 else 0 end) as curo_48h
  from nuevos_sep n
  join dac d on d.id_loan = n.id_loan
   and d.fecha between date_add('day', 1, n.f_ent) and date_add('day', 2, n.f_ent)
  group by 1
)
, mora_sep as (
  select id_loan, max(mora) as max_mora
  from dac where fecha between date '2026-09-01' and date '2026-09-12'
  group by 1
)
-- anclaje de la vista, replicado (bug 27)
, base_gestion as (
  select a.aux02 as id_loan, cast(a.fecha_base as date) as fecha_base
  , a.fase_estrategia, a.tipo_mora, a.monto_capital_pendiente
  from dts_asignaciones_gestiones_cobranza a
  where cast(a.fecha_base as date) between date '2026-09-01' and date '2026-09-12'
    and (a.fase_estrategia <> 'RECOVERY' or cast(a.fecha_base as date) = date '2026-09-01')
)
, ancla as (
  select id_loan, min(fecha_base) as fecha_ancla from base_gestion group by 1
)
, vista as (
  select a.id_loan, a.fecha_ancla
  , max(b.fase_estrategia) as fase, max(b.tipo_mora) as tipo_mora
  , max(b.monto_capital_pendiente) as monto
  from ancla a
  join base_gestion b on b.id_loan = a.id_loan and b.fecha_base = a.fecha_ancla
  group by 1, 2
)
, vista_tn as (
  select * from vista where fase = 'TEMPRANA' and tipo_mora = 'nuevo'
)
, comp as (
  select coalesce(n.id_loan, v.id_loan) as id_loan
  , n.id_loan as n_id, v.id_loan as v_id
  , n.f_ent, n.saldo_entrada, n.arrastre, n.reeng
  , v.fecha_ancla, v.monto
  from nuevos_sep n
  full outer join vista_tn v on v.id_loan = n.id_loan
)
-- =====================================================================
select
  'B. nuevos v2 vs vista TEMPRANA nuevo' as bloque
, case when c.n_id is not null and c.v_id is not null then 'a. en ambos'
       when c.n_id is not null then 'b. solo nuestro'
       else 'c. solo la vista' end as k1
, case
    when c.n_id is not null and c.v_id is not null then
      case when date_diff('day', c.f_ent, c.fecha_ancla) < 0 then 'asignado antes de entrar'
           when date_diff('day', c.f_ent, c.fecha_ancla) = 0 then 'asignado el dia de entrada'
           when date_diff('day', c.f_ent, c.fecha_ancla) = 1 then 'asignado 1 dia despues'
           when date_diff('day', c.f_ent, c.fecha_ancla) = 2 then 'asignado 2 dias despues'
           else 'asignado 3+ dias despues' end
    when c.n_id is not null then
      case when c.arrastre = 1 then 'arrastre por DNI'
           when va.id_loan is not null then 'vista: ' || va.fase || ' / ' || va.tipo_mora
           when c.f_ent >= date '2026-09-11' then 'entro el 11-12: su asignacion puede no haber llegado'
           when coalesce(cu.curo_48h, 0) = 1 then 'curo en 48h sin ser asignado'
           else 'no asignado y siguio en mora' end
    else
      case when s.id_loan is not null then 'en nuestro stock v2 (antiguo para nosotros)'
           when p.id_loan is null or p.status not in ('ACTIVE','COMPLETED') then 'status fuera de ACTIVE/COMPLETED'
           when ms.id_loan is null then 'sin fila en calendario_diario del 1 al 12-sep'
           when ms.max_mora = 0 then 'mora 0 en calendario_diario del 1 al 12-sep'
           else 'con mora pero sin transicion 0->1 del 2 al 12-sep' end
  end as k2
, case when c.n_id is not null and c.v_id is null
       then 'entrada ' || date_format(c.f_ent, '%a')
       else '' end as k3
, count(*) as creditos
, round(sum(c.saldo_entrada), 2) as saldo_1
, round(sum(c.monto), 2) as saldo_2
from comp c
left join vista va     on va.id_loan = c.id_loan and c.v_id is null
left join cura cu      on cu.id_loan = c.id_loan
left join st_v2 s      on s.id_loan = c.id_loan and s.mes = date '2026-09-01'
left join prestamos p  on p.id_loan = c.id_loan
left join mora_sep ms  on ms.id_loan = c.id_loan
group by 1, 2, 3, 4

union all

select 'B2. nuestras entradas por dia', cast(day(f_ent) as varchar)
, case when arrastre = 1 then 'arrastre' else 'temprana' end, ''
, count(*), round(sum(saldo_entrada), 2), cast(null as double)
from nuevos_sep
group by 1, 2, 3, 4

union all

select 'B2. vista nuevos TEMPRANA por dia', cast(day(fecha_ancla) as varchar), '', ''
, count(*), cast(null as double), round(sum(monto), 2)
from vista_tn
group by 1, 2, 3, 4

union all

select 'C. tasa realizada dias 2-12', date_format(mes, '%Y%m'), '', ''
, count(*), round(sum(saldo), 2), round(sum(case when entra = 1 then saldo else 0 end), 2)
from cal_v2
where reeng = 0
group by 1, 2, 3, 4

union all

select 'D. entradas reales v2 sep', cast(day(f_ent) as varchar)
, case when saldo_entrada >= 0.9*amountfinanced then 'a. avance <10%'
       when saldo_entrada >= 0.6*amountfinanced then 'b. avance 10-40%'
       when saldo_entrada >= 0.3*amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end
, cast(arrastre as varchar) || '|' || cast(reeng as varchar)
, count(*), round(sum(saldo_entrada), 2), cast(null as double)
from nuevos_sep
where coalesce(saldo_entrada, 0) > 0
group by 1, 2, 3, 4

union all

select 'E. calendario medido sep', cast(dia_entrada as varchar), avance_band, ''
, count(*), round(sum(saldo), 2), round(sum(case when entra = 1 then saldo else 0 end), 2)
from cal_v2
where reeng = 0 and mes = date '2026-09-01'
group by 1, 2, 3, 4

order by 1, 2, 3, 4
;

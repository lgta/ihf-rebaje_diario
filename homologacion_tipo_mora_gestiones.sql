-- =====================================================================
-- HOMOLOGACION: tipo_mora (dts_asignaciones_gestiones_cobranza, proyecto
-- gestiones_cobranzas) vs. antiguo/nuevo (dayslate + fix bug 12, este
-- proyecto). Ejecutado 2026-08-18, a raiz de
-- prompt_handoff_reconciliacion_gestiones_cobranzas.txt.
--
-- Contexto: gestiones_cobranzas calcula tipo_mora a nivel CUOTA con
-- `CASE WHEN dias_mora >= day(current_date) THEN 'antiguo' ELSE 'nuevo' END`
-- (dias_mora = date_diff(dia, fecha_vencimiento_cuota, current_date)).
-- Es una formula distinta a la nuestra (deteccion de transicion dayslate
-- 0->1 a nivel CREDITO) pero responde la misma pregunta de fondo.
--
-- Tabla usada: dts_asignaciones_gestiones_cobranza -- NO dts_asignaciones_cobranza
-- (esa quedo congelada el 2026-07-10, ver FUENTES_DATOS.md). Grano
-- confirmado (dni_ce, producto) por fecha_base, ~1:1 (verificado
-- 2026-08-18: filas == combinaciones dni_ce+producto distintas).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1 -- cruce en dia 1 de mes (2026-08-01). NO es representativo: la
-- formula de gestiones_cobranza hace day(current_date)=1, o sea el
-- umbral "dias_mora >= 1" -- CUALQUIER mora existente sale "antiguo" por
-- construccion (nada puede ser "nuevo" el dia 1). Se deja como referencia
-- de por que no sirve como test, no como evidencia de acuerdo/desacuerdo.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, dni, producto, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas
  group by id_ihfintech_loan, dni, producto
)
, creditos as (
  select lc.id_ihfintech_loan, lc.dni, lc.producto
  from loan_chain lc
  join dts_okaapi_loans o on o.id_ihfintech_loan = lc.id_ihfintech_loan
  where o.status = 'ACTIVE'
    and coalesce(lc.last_in_chain,1) = 1
)
, hoy as (
  select c.id_ihfintech_loan, c.dni, c.producto, coalesce(m.dayslate,0) as mora_hoy
  from creditos c
  join dts_mambu_loans_hist m
    on m._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
   and m.fechaproceso = '20260801'
)
, ayer as (
  select c.id_ihfintech_loan, coalesce(m.dayslate,0) as mora_ayer
  from creditos c
  join dts_mambu_loans_hist m
    on m._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
   and m.fechaproceso = '20260731'
)
, propio as (
  select h.id_ihfintech_loan, h.dni, h.producto, h.mora_hoy, coalesce(a.mora_ayer,0) as mora_ayer,
    case
      when h.mora_hoy = 0 then 'sin mora'
      when coalesce(a.mora_ayer,0) between 1 and 30 then 'antiguo'
      when coalesce(a.mora_ayer,0) >= 31 then 'fuera_de_alcance_mora_previa'
      when coalesce(a.mora_ayer,0) = 0 then 'antiguo'  -- entra el dia 1 => bug12: antiguo
      else 'nuevo'
    end as tipo_mora_propio
  from hoy h
  left join ayer a on a.id_ihfintech_loan = h.id_ihfintech_loan
)
, gestiones as (
  select dni_ce, producto, tipo_mora
  from dts_asignaciones_gestiones_cobranza
  where fecha_base = '2026-08-01'
)
select p.tipo_mora_propio, g.tipo_mora as tipo_mora_gestiones, count(*) as n
from propio p
join gestiones g on g.dni_ce = p.dni and g.producto = p.producto
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- Q2 -- cruce en un dia de mitad de mes (2026-08-10), representativo:
-- ambos motores pueden producir "nuevo". Poblacion de referencia = mora
-- 1-30 (la que cubre este proyecto).
--
-- Resultado real (2026-08-18): 917 antiguo/antiguo, 947 nuevo/nuevo,
-- 28 antiguo(propio)/nuevo(gestiones), 0 nuevo(propio)/antiguo(gestiones).
-- 98.5% de acuerdo (1864/1892) en la poblacion mora 1-30 compartida.
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, dni, producto, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas
  group by id_ihfintech_loan, dni, producto
)
, creditos as (
  select lc.id_ihfintech_loan, lc.dni, lc.producto
  from loan_chain lc
  join dts_okaapi_loans o on o.id_ihfintech_loan = lc.id_ihfintech_loan
  where o.status = 'ACTIVE'
    and coalesce(lc.last_in_chain,1) = 1
)
, dia10 as (
  select c.id_ihfintech_loan, c.dni, c.producto, coalesce(m.dayslate,0) as mora_dia10
  from creditos c
  join dts_mambu_loans_hist m
    on m._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
   and m.fechaproceso = '20260810'
)
, jul31 as (
  select c.id_ihfintech_loan, coalesce(m.dayslate,0) as mora_jul31
  from creditos c
  join dts_mambu_loans_hist m
    on m._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
   and m.fechaproceso = '20260731'
)
, ago1 as (
  select c.id_ihfintech_loan, coalesce(m.dayslate,0) as mora_ago1
  from creditos c
  join dts_mambu_loans_hist m
    on m._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
   and m.fechaproceso = '20260801'
)
, propio as (
  select d.id_ihfintech_loan, d.dni, d.producto, d.mora_dia10,
    coalesce(j.mora_jul31,0) as mora_jul31,
    coalesce(a.mora_ago1,0) as mora_ago1,
    case
      when d.mora_dia10 = 0 then 'sin mora'
      when d.mora_dia10 > 30 then 'fuera_de_alcance_mora_actual'
      when coalesce(j.mora_jul31,0) between 1 and 30 then 'antiguo'
      when coalesce(j.mora_jul31,0) >= 31 then 'fuera_de_alcance_mora_previa'
      when coalesce(a.mora_ago1,0) = 1 then 'antiguo'   -- entro el dia 1 (bug12)
      else 'nuevo'
    end as tipo_mora_propio
  from dia10 d
  left join jul31 j on j.id_ihfintech_loan = d.id_ihfintech_loan
  left join ago1 a on a.id_ihfintech_loan = d.id_ihfintech_loan
)
, gestiones as (
  select dni_ce, producto, tipo_mora
  from dts_asignaciones_gestiones_cobranza
  where fecha_base = '2026-08-10'
)
select p.tipo_mora_propio, g.tipo_mora as tipo_mora_gestiones, count(*) as n
from propio p
join gestiones g on g.dni_ce = p.dni and g.producto = p.producto
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- Q3 -- detalle de los 28 casos antiguo(propio)/nuevo(gestiones) de Q2,
-- con las cuotas en mora del credito para diagnosticar la causa.
--
-- Hallazgo (2026-08-18): en los 28 casos, mora_jul31 esta entre 23 y 30
-- (creditos cerca del limite de 30 dias al cierre de julio) Y hubo una
-- CURA seguida de una RECAIDA con una cuota nueva dentro de agosto
-- (mora_dia10 bajo a 2-9 dias, sobre una cuota vencida en agosto). No es
-- un bug de join/datos: es que este proyecto fija la membresia "stock"
-- para todo el mes por diseno (DECISIONES.md, "tramo fijo aunque cruce
-- 30 dias"), mientras que tipo_mora de gestiones_cobranza se recalcula
-- a diario desde la cuota vigente -- si el credito cura y cae de nuevo,
-- ellos lo reclasifican a "nuevo" y nosotros no. Conecta con el hallazgo
-- de reincidencia del enfoque beta descontinuado (80.8% de "cura sin
-- pago" recae, bug 11 en BUGS.md).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, dni, producto, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas
  group by id_ihfintech_loan, dni, producto
)
, creditos as (
  select lc.id_ihfintech_loan, lc.dni, lc.producto
  from loan_chain lc
  join dts_okaapi_loans o on o.id_ihfintech_loan = lc.id_ihfintech_loan
  where o.status = 'ACTIVE'
    and coalesce(lc.last_in_chain,1) = 1
)
, dia10 as (
  select c.id_ihfintech_loan, c.dni, c.producto, coalesce(m.dayslate,0) as mora_dia10
  from creditos c
  join dts_mambu_loans_hist m
    on m._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
   and m.fechaproceso = '20260810'
)
, jul31 as (
  select c.id_ihfintech_loan, coalesce(m.dayslate,0) as mora_jul31
  from creditos c
  join dts_mambu_loans_hist m
    on m._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
   and m.fechaproceso = '20260731'
)
, ago1 as (
  select c.id_ihfintech_loan, coalesce(m.dayslate,0) as mora_ago1
  from creditos c
  join dts_mambu_loans_hist m
    on m._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan
   and m.fechaproceso = '20260801'
)
, propio as (
  select d.id_ihfintech_loan, d.dni, d.producto, d.mora_dia10,
    coalesce(j.mora_jul31,0) as mora_jul31,
    coalesce(a.mora_ago1,0) as mora_ago1,
    case
      when d.mora_dia10 = 0 then 'sin mora'
      when d.mora_dia10 > 30 then 'fuera_de_alcance_mora_actual'
      when coalesce(j.mora_jul31,0) between 1 and 30 then 'antiguo'
      when coalesce(j.mora_jul31,0) >= 31 then 'fuera_de_alcance_mora_previa'
      when coalesce(a.mora_ago1,0) = 1 then 'antiguo'
      else 'nuevo'
    end as tipo_mora_propio
  from dia10 d
  left join jul31 j on j.id_ihfintech_loan = d.id_ihfintech_loan
  left join ago1 a on a.id_ihfintech_loan = d.id_ihfintech_loan
)
, gestiones as (
  select dni_ce, producto, tipo_mora, dias_mora, max_dias_mora_dni, nro_de_cuota, fase_estrategia
  from dts_asignaciones_gestiones_cobranza
  where fecha_base = '2026-08-10'
)
, casos as (
  select p.*, g.tipo_mora as tipo_mora_gestiones, g.dias_mora, g.max_dias_mora_dni, g.nro_de_cuota
  from propio p
  join gestiones g on g.dni_ce = p.dni and g.producto = p.producto
  where p.tipo_mora_propio = 'antiguo' and g.tipo_mora = 'nuevo'
)
, cuotas_credito as (
  select id_ihfintech_loan,
         count(*) as n_cuotas_en_mora,
         array_join(array_agg(cast(fechavencimiento as varchar) order by fechavencimiento), ',') as vencimientos,
         array_join(array_agg(installmentstate order by fechavencimiento), ',') as estados
  from dts_cobranza_creditos_cuotas
  where installmentstate in ('LATE','PENDING')
  group by id_ihfintech_loan
)
select c.id_ihfintech_loan, c.dni, c.producto, c.mora_dia10, c.mora_jul31, c.mora_ago1,
       c.dias_mora as dias_mora_gestiones, c.max_dias_mora_dni, c.nro_de_cuota,
       cc.n_cuotas_en_mora, cc.vencimientos, cc.estados
from casos c
left join cuotas_credito cc on cc.id_ihfintech_loan = c.id_ihfintech_loan
order by c.id_ihfintech_loan
;

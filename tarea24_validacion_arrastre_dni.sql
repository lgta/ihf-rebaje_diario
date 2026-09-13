-- =====================================================================
-- TAREA 24 -- VALIDAR EL FLAG DE ARRASTRE POR DNI antes de usarlo en la
-- historia.
--
-- Decision del usuario 2026-09-13: el arrastre se trata como en la vista
-- (el credito en mora 1-30 cuyo DNI tiene otro credito con mas de 30 dias
-- no es TEMPRANA), pero con un FLAG, para poder separarlo en reporte y
-- analisis. La tabla de asignaciones (max_dias_mora_dni) existe solo desde
-- julio 2026; para calibrar hay que reconstruirlo desde
-- dts_cobranza_creditos_calendario_diario.dni.
--
-- Se prueban dos variantes contra lo que asigno el negocio el primer dia
-- de asignacion de julio, agosto y septiembre, sobre los creditos que para
-- nosotros estan en mora 1-30 ese dia:
--   flag_todos  = max dias_atraso_cuota de TODOS los creditos del DNI > 30
--   flag_cadena = igual, pero solo con creditos ultimos de su cadena
-- La variante buena es la que reproduce la fase del negocio
-- (TEMPRANA vs. ESPECIALIZADA/RECOVERY).
-- =====================================================================
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, cal as (
  select c.fecha_calendario as d, c.id_ihfintech_loan as id_loan, max(c.dni) as dni,
         max(coalesce(c.dias_atraso_cuota, 0)) as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario in (date '2026-07-01', date '2026-08-03', date '2026-09-01')
  group by 1, 2
)
, dni_max as (
  select cal.d, cal.dni
  , max(cal.mora) as max_todos
  , max(case when coalesce(lc.last_in_chain, 1) = 1 then cal.mora end) as max_cadena
  from cal
  left join loan_chain lc on lc.id_ihfintech_loan = cal.id_loan
  where cal.dni is not null
  group by 1, 2
)
, asig as (
  select cast(fecha_base as date) as d, aux02 as id_loan
  , max(fase_estrategia) as fase
  , max(max_dias_mora_dni) as max_dni_negocio
  from dts_asignaciones_gestiones_cobranza
  where cast(fecha_base as date) in (date '2026-07-01', date '2026-08-03', date '2026-09-01')
  group by 1, 2
)
select
  cast(a.d as varchar) as dia
, case when a.fase = 'TEMPRANA' then 'negocio: TEMPRANA' else 'negocio: ESP/REC' end as fase_negocio
, case when m.max_todos > 30 then 'todos: >30' else 'todos: <=30' end   as flag_todos
, case when m.max_cadena > 30 then 'cadena: >30' else 'cadena: <=30' end as flag_cadena
, case when a.max_dni_negocio > 30 then 'max_dni negocio >30' else 'max_dni negocio <=30' end as flag_negocio
, count(*) as creditos
from asig a
join cal c on c.id_loan = a.id_loan and c.d = a.d
left join dni_max m on m.d = c.d and m.dni = c.dni
where c.mora between 1 and 30
group by 1, 2, 3, 4, 5
order by 1, 2, 3, 4, 5
;

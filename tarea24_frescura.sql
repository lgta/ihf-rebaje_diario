-- =====================================================================
-- TAREA 24 -- FRESCURA DE LAS DOS FUENTES al 13-sep: filas por dia desde
-- el 1-sep. La foto del dia en curso todavia esta corriendo (trampa vieja
-- del handoff): el ultimo dia COMPLETO es el que tiene un conteo de filas
-- en linea con los anteriores.
-- =====================================================================
select 'mambu' as fuente, fechaproceso as fecha, count(*) as filas
from dts_mambu_loans_hist
where fechaproceso >= '20260828'
group by 1, 2

union all

select 'calendario', date_format(fecha_calendario, '%Y%m%d'), count(*)
from dts_cobranza_creditos_calendario_diario
where fecha_calendario >= date '2026-08-28'
group by 1, 2

order by 1, 2
;

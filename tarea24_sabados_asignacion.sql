-- =====================================================================
-- TAREA 24 -- ¿HAY ASIGNACION LOS FINES DE SEMANA?
--
-- FUENTES_DATOS.md decia (verificado en julio 2026) que
-- dts_asignaciones_gestiones_cobranza no tiene filas sabado/domingo.
-- Al revisar la frescura de septiembre aparecieron filas el sabado 5-sep.
-- Resultado (2026-09-13): hay asignacion TODOS los sabados desde el
-- 2026-07-25, los domingos nunca. Aclaracion del usuario: la de sabado es
-- solo para canales complementarios, NO se genera para call ni IVR.
-- Relevante para tarea 23 (cortar por canal_asignado).
-- =====================================================================
select cast(fecha_base as date)                                          as f
, day_of_week(cast(fecha_base as date))                                  as dow
, count(distinct aux02)                                                  as creditos
, count(distinct case when tipo_mora = 'nuevo' then aux02 end)           as nuevos
from dts_asignaciones_gestiones_cobranza
where cast(fecha_base as date) >= date '2026-07-01'
  and day_of_week(cast(fecha_base as date)) in (6, 7)
group by 1, 2
order by 1
;

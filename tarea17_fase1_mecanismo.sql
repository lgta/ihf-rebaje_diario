-- =====================================================================
-- TAREA 17, FASE 1, PASO 3 -- Investigar sistematicamente las 2 brechas
-- que deja tarea17_universo_dias_atraso_cuota.sql (no reducirlas,
-- EXPLICARLAS -- correccion 2 del usuario, ver PENDIENTES.md tarea 17).
--
-- Resultado de la reconstruccion principal (tarea17_universo_dias_atraso_
-- cuota.sql), julio y agosto 2026:
--   - categoria "3d. solo oficial - punto ciego dias_atraso_cuota" baja
--     de 3,130 (dayslate) a 87 (julio) y de 2,093 a 63 (agosto) -- ~97%
--     de reduccion, CONFIRMA el mecanismo horario propuesto por el
--     usuario (ver bug 16 en BUGS.md, actualizacion 2026-08-24).
--   - PERO aparece una brecha nueva y mas grande: "2c. solo nuestro - no
--     aparece en asignaciones" SUBE de 117 a 851 (julio) y de 302 a 1,708
--     (agosto). Esto se investiga aca.
--
-- HALLAZGO (verificado con las 3 queries de abajo):
-- dts_asignaciones_gestiones_cobranza NO TIENE FILAS LOS FINES DE SEMANA
-- -- el proceso de asignacion del negocio corre de lunes a viernes
-- solamente. dias_atraso_cuota, al reconstruir dia por dia (incluidos
-- sabado y domingo), detecta episodios de mora reales pero breves que
-- se originan y se resuelven (paga) DENTRO de un fin de semana -- para
-- cuando corre la siguiente asignacion (el proximo dia habil), el
-- credito ya no esta en mora y nunca recibe una fila TEMPRANA en TODO
-- el mes. Confirmado en 4 subpoblaciones distintas:
--   - julio, origen "nuevos" (680 creditos): 91.0% entran en mora un
--     sabado o domingo (Q2 de abajo).
--   - agosto, origen "nuevos" (727 creditos): 96.0% entran en mora un
--     sabado o domingo (Q2).
--   - julio, origen "stock" (171 creditos): 82.9% salen de mora
--     exactamente el 1-jul (miercoles, dia habil -- variante de bug 19/
--     tarea 14, ventana de solo 1 dia porque 1-jul SI es dia habil), el
--     resto (17.1%) el 2-jul (Q3).
--   - agosto, origen "stock" (981 creditos): 100.0% salen de mora el
--     01-ago o 02-ago (sabado y domingo -- el mecanismo se COMPONE con
--     el de tarea 14: 1-ago siendo fin de semana da 2 dias de gracia en
--     vez de 1, por eso este bucket es 5.7x mas grande que julio) (Q3).
--
-- El residual que SI sigue siendo "3d" (87 julio + 63 agosto, <1% del
-- universo oficial) tiene un patron MIXTO, no el mismo mecanismo: 56/87
-- (julio) nunca muestran NINGUN dia de atraso en dias_atraso_cuota
-- durante toda la ventana jun-jul, pero SI fueron asignados TEMPRANA por
-- el negocio dentro de julio (Q4) -- posible arrastre a nivel cliente
-- (mismo mecanismo ya documentado para ESPECIALIZADA/RECOVERY en
-- FUENTES_DATOS.md) o una definicion de mora del negocio distinta a la
-- cuota vigente -- NO CONFIRMADO, queda como diferencia sin explicar
-- (correccion 2 del usuario: documentar, no forzar una explicacion).
-- =====================================================================

-- #######################################################################
-- Q1 -- dts_asignaciones_gestiones_cobranza no tiene fecha_base los
-- fines de semana (julio 2026). Confirma el mecanismo de raiz: el
-- proceso de asignacion es de lunes a viernes.
-- #######################################################################
select
  fecha_base
, day_of_week(date(fecha_base)) as dow_iso  -- 1=lunes .. 7=domingo
, count(distinct aux02) as creditos
from dts_asignaciones_gestiones_cobranza
where fecha_base between '2026-07-01' and '2026-07-31'
group by 1, 2
order by 1
;
-- Resultado ya verificado 2026-08-24: filas para 07-01 a 07-31 EXCEPTO
-- 07-04, 07-05, 07-11, 07-12, 07-18, 07-19, 07-25, 07-26 (los 4 fines de
-- semana completos de julio) -- 0 filas esos 8 dias.

-- #######################################################################
-- Q2 -- dia de la semana de ENTRADA en mora (dias_atraso_cuota) para los
-- creditos "2c. solo nuestro - no aparece en asignaciones", origen
-- "nuevos", julio. Cambiar el rango de fechas/ventana para agosto (ver
-- nota al final).
-- #######################################################################
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, cal_raw as (
  select
    c.id_ihfintech_loan as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d') as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0) as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-06-01') and date('2026-07-31')
)
, fotos_all as (
  select
    d.id_loan, d.fechaproceso, d.mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from cal_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
)
, fotos as (
  select * from fotos_all where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
)
, fotos_lag as (
  select id_loan, fechaproceso, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
)
, cierre_junio as (
  select id_loan, mora,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260630'
)
, stock_previo as (
  select id_loan from cierre_junio where rn = 1 and mora between 1 and 30
)
, dia1_julio as (
  select id_loan, mora,
    row_number() over (partition by id_loan order by fechaproceso asc) as rn
  from fotos where fechaproceso >= '20260701'
)
, dia1_entrantes as (
  select id_loan from dia1_julio where rn = 1 and mora = 1
)
, nuevos_julio as (
  select f.id_loan, min(f.fechaproceso) as fecha_entrada
  from fotos_lag f
  where f.mora_ant = 0 and f.mora = 1
    and f.fechaproceso between '20260702' and '20260731'
    and f.id_loan not in (select id_loan from stock_previo)
    and f.id_loan not in (select id_loan from dia1_entrantes)
  group by f.id_loan
)
, asig as (
  select
    aux02 as id_loan
  , max(case when fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana
  , max(case when fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_esp_rec
  , max(case when grupo_control = 'CONTROL' then 1 else 0 end) as es_control
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-07-01' and '2026-07-31' and aux02 is not null
  group by 1
)
select
  day_of_week(date_parse(n.fecha_entrada, '%Y%m%d')) as dow_iso  -- 1=lunes .. 6=sabado, 7=domingo
, count(*) as creditos
from nuevos_julio n
left join asig a on a.id_loan = n.id_loan
where coalesce(a.alguna_vez_temprana, 0) = 0     -- no aparece como TEMPRANA
  and coalesce(a.alguna_vez_esp_rec, 0) = 0        -- ni ESP/REC (2b)
  and coalesce(a.es_control, 0) = 0                -- ni grupo control (2a)
  -- nota: a.id_loan is null (sin ninguna fila en asig) o matcheado pero
  -- sin ninguna fase relevante caen ambos aca, que es exactamente "2c"
group by 1
order by 1
;
-- Resultado verificado 2026-08-24: 680 creditos total, dow 6(sabado)=353,
-- dow 7(domingo)=266 -> 619/680 = 91.0% en fin de semana.
-- Repetir con ventana '2026-07-01' a '2026-08-23' (cal_raw), stock_previo
-- desde cierre '20260731', dia1_agosto >= '20260801', nuevos_agosto entre
-- '20260802' y '20260823', asig entre '2026-08-01' y '2026-08-23' para
-- agosto -> 727 creditos, 96.0% fin de semana (698/727).

-- #######################################################################
-- Q3 -- dia de SALIDA de mora (dias_atraso_cuota) para los creditos
-- "2c", origen "stock", agosto (el bucket mas grande, 981 creditos).
-- Cambiar rango de fechas para julio (ver nota al final).
-- #######################################################################
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, cal_raw as (
  select
    c.id_ihfintech_loan as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d') as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0) as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-07-01') and date('2026-08-23')
)
, fotos_all as (
  select
    d.id_loan, d.fechaproceso, d.mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from cal_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
)
, fotos as (
  select * from fotos_all where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
)
, fotos_lag as (
  select id_loan, fechaproceso, mora,
    lag(mora) over (partition by id_loan order by fechaproceso) as mora_ant
  from fotos
)
, cierre_julio as (
  select id_loan, mora,
    row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260731'
)
, stock_previo as (
  select id_loan from cierre_julio where rn = 1 and mora between 1 and 30
)
, salida as (
  select id_loan, min(fechaproceso) as fecha_salida
  from fotos_lag
  where mora_ant > 0 and mora = 0 and fechaproceso >= '20260801'
  group by 1
)
, asig as (
  select
    aux02 as id_loan
  , max(case when fase_estrategia = 'TEMPRANA' then 1 else 0 end) as alguna_vez_temprana
  , max(case when fase_estrategia in ('ESPECIALIZADA','RECOVERY') then 1 else 0 end) as alguna_vez_esp_rec
  , max(case when grupo_control = 'CONTROL' then 1 else 0 end) as es_control
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-08-01' and '2026-08-23' and aux02 is not null
  group by 1
)
select
  s.fecha_salida
, day_of_week(date_parse(s.fecha_salida, '%Y%m%d')) as dow_iso
, count(*) as creditos
from stock_previo p
join salida s on s.id_loan = p.id_loan
left join asig a on a.id_loan = p.id_loan
where coalesce(a.alguna_vez_temprana, 0) = 0
  and coalesce(a.alguna_vez_esp_rec, 0) = 0
  and coalesce(a.es_control, 0) = 0
group by 1, 2
order by 1
;
-- Resultado verificado 2026-08-24: 981 creditos, 99.9% (980) salen de
-- mora exactamente el 01-ago o 02-ago (sabado/domingo, los 2 dias
-- inmediatos al cierre de julio). Para julio (cambiar ventana a
-- 20260601-20260731, cierre_junio <= 20260630, salida >= 20260701):
-- 171 creditos, 82.9% (141) salen exacto el 01-jul (miercoles, dia
-- habil -- por eso la ventana de gracia es de 1 dia no 2), 17.1% (29)
-- el 02-jul.

-- #######################################################################
-- Q4 -- El residual "3d" que SI sigue sin explicar (87 julio + 63
-- agosto, <1% del universo oficial): 56/87 en julio nunca muestran
-- ningun dia de atraso en dias_atraso_cuota durante jun-jul, pero SI
-- tienen fase_estrategia='TEMPRANA' en dts_asignaciones_gestiones_
-- cobranza dentro de julio. Ver cuando fueron asignados TEMPRANA -- si
-- fuera un flag "pegajoso" de antes de la ventana se veria clave (case
-- de bug 13, fase "pegajosa"), pero NO es el caso: la primera fecha de
-- TEMPRANA cae DENTRO de julio para los 15 casos revisados a mano
-- (2026-08-24) -- no resuelto, ver nota en BUGS.md bug 16.
-- #######################################################################
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, cal_raw as (
  select
    c.id_ihfintech_loan as id_loan
  , date_format(c.fecha_calendario, '%Y%m%d') as fechaproceso
  , coalesce(c.dias_atraso_cuota, 0) as mora
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date('2026-06-01') and date('2026-07-31')
)
, fotos_all as (
  select
    d.id_loan, d.fechaproceso, d.mora
  , b.status
  , coalesce(lc.last_in_chain,1) as last_in_chain
  from cal_raw d
  join dts_okaapi_loans b on b.id_ihfintech_loan = d.id_loan
  left join loan_chain lc on lc.id_ihfintech_loan = d.id_loan
)
, fotos as (
  select * from fotos_all where status in ('ACTIVE','COMPLETED') and last_in_chain = 1
)
, cobertura as (
  select id_loan,
    count(*) as filas,
    sum(case when mora is not null and mora > 0 then 1 else 0 end) as filas_con_atraso,
    max(mora) as max_atraso
  from fotos
  group by 1
)
, asig_temprana as (
  select aux02 as id_loan, min(fecha_base) as primer_temprana, max(fecha_base) as ultimo_temprana
  from dts_asignaciones_gestiones_cobranza
  where fecha_base between '2026-07-01' and '2026-07-31'
    and fase_estrategia = 'TEMPRANA' and aux02 is not null
  group by 1
)
select c.id_loan, c.filas, c.filas_con_atraso, c.max_atraso, t.primer_temprana, t.ultimo_temprana
from cobertura c
join asig_temprana t on t.id_loan = c.id_loan
where c.filas_con_atraso = 0   -- nunca muestran atraso en dias_atraso_cuota
order by t.primer_temprana
;
-- Nota: esta query reproduce el universo "3d, nunca atraso" desde cero
-- (sin depender de la lista de ids del scratchpad de la sesion) -- pero
-- NO filtra por "solo oficial" (mambu_status/last_in_chain/last_in_chain
-- del cruce completo) porque aca ya se sabe que son ACTIVE/COMPLETED y
-- last_in_chain=1 (estan en `fotos`, que ya aplica ese filtro). El
-- resultado esperado es ~56 filas para julio.

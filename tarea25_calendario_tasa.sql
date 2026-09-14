-- =====================================================================
-- TAREA 25 / BUG 28 -- CALENDARIO Y TASA DE ENTRADA CON EL SALDO ANCLADO.
--
-- Copia de tarea24_v2_calendario_tasa.sql (misma poblacion, mismo grano, mismas
-- definiciones v1/v2) con el saldo de cada cuota en la ULTIMA FOTO DEL MES
-- ANTERIOR, que es el unico saldo que la meta conoce el dia 1 (BUGS.md bug 28).
-- La tasa de tarea 24 divide por el saldo AL VENCIMIENTO; la meta la multiplica
-- por el saldo ANCLADO, que en septiembre (dias 2-12) es 10.5% mayor: toda meta
-- fijada el dia 1 salia alta en nuevos. La correccion (aprobada por el usuario
-- 2026-09-13) calibra la tasa sobre el denominador que la meta si conoce:
--
--   tasa anclada = entran (saldo de entrada) / elegibles (saldo anclado)
--
-- El numerador no cambia: `saldo` es el del dia del vencimiento, que para quien
-- entra en mora es su saldo de entrada (la foto del dia anterior a la entrada,
-- la base de la curva de nuevos en tarea24_v2_matriz_nuevos.sql).
--
-- Columnas nuevas respecto de tarea24_v2_calendario_tasa.sql:
--   tiene_ancla     : 1 = el credito tiene foto en el mes anterior con saldo > 0,
--                     el universo del calendario de la meta (ancla_final de
--                     tarea25_insumos_octubre.sql). 0 = la meta no lo ve el dia 1.
--   avance_band_anc : banda con el saldo anclado -- la que usa la meta para elegir
--                     la curva ('-' si tiene_ancla = 0).
--   saldo_ancla     : saldo Mambu de la ultima foto del mes anterior (dedup bug 11),
--                     solo con tiene_ancla = 1.
--
-- Uso (v2, arrastre fuera; los reenganches se incluyen desde el 2026-09-13):
--   filtro v2      : st_v2 = 0, orden_d2 = 1
--   tasa medida    : sum(saldo | entra = 1, arrastre = 0) / sum(saldo)
--   tasa anclada   : sum(saldo | entra = 1, arrastre = 0, tiene_ancla = 1)
--                    / sum(saldo_ancla | tiene_ancla = 1)
--   cal. anclado   : saldo_ancla por (dia_entrada, avance_band_anc), tiene_ancla = 1
--   CONTROL: sumando sobre las columnas nuevas, reproduce tarea24_v2_calendario_tasa
--   (salvo re-expresion de Mambu).
--
-- Ventana: periodos 202501-202608 COMPLETOS -- octubre calibra [202509, 202608] --
-- y 202609 PARCIAL: solo cuotas con entrada hasta el 12-sep, el ultimo dia completo
-- al correrla (13-sep). 202609 sirve para rehacer las tres capas de septiembre con
-- los reenganches (el bloque E de tarea24_v2_dimensionamiento_sep.sql los excluye);
-- curvas_v2.CALENDARIO_HASTA impide calibrar con el.
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
    and c.fecha_calendario between date '2024-12-01' and date '2026-09-12'
)
, dac_lag as (
  select id_loan, fecha, mora, dni
  , lag(mora) over (partition by id_loan order by fecha) as mora_ant
  from dac
)
, st_v1 as (
  select id_loan, date_add('month', 1, date_trunc('month', fecha)) as mes
  from (
    select id_loan, fecha, mora
    , row_number() over (partition by id_loan, date_trunc('month', fecha) order by fecha desc) as rn
    from dac
  )
  where rn = 1 and mora between 1 and 30
)
, st_v2 as (
  select id_loan, fecha as mes
  from dac
  where day(fecha) = 1 and mora between 1 and 30
)
, entradas as (
  select date_trunc('month', fecha) as mes, id_loan
  , min(fecha) as f_ent, min_by(dni, fecha) as dni
  from dac_lag
  where mora_ant = 0 and mora = 1
  group by 1, 2
)
, dni_mora30 as (
  select distinct c.fecha_calendario as fecha, c.dni
  from dts_cobranza_creditos_calendario_diario c
  where c.fecha_calendario between date '2025-01-01' and date '2026-09-12'
    and c.dias_atraso_cuota > 30
    and c.dni is not null
)
, mambu_dedup as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , row_number() over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech, a.fechaproceso
      order by (case when a.balances_principalbalance <> 0 then 0 else 1 end),
               a.lastmodifieddate desc, a.id desc) as rn_dedup
  from dts_mambu_loans_hist a
  where a.fechaproceso between '20241201' and '20260911'
)
, saldo_venc as (
  select id_loan, fechaproceso, saldo
  from mambu_dedup
  where rn_dedup = 1 and fechaproceso >= '20241231'
)
, ancla as (
  -- ultima foto de cada mes: el saldo que la meta del mes siguiente conoce el dia 1
  select id_loan, substr(fechaproceso, 1, 6) as mes_foto
  , max_by(saldo, fechaproceso) as saldo_ancla
  from mambu_dedup
  where rn_dedup = 1 and fechaproceso <= '20260831'
  group by 1, 2
)
, calendario_rn as (
  select
    c.id_ihfintech_loan as id_loan
  , date_add('day', 1, c.fechavencimiento) as f_entrada_cal
  , date_trunc('month', date_add('day', 1, c.fechavencimiento)) as mes
  , f.saldo, p.amountfinanced, p.reeng
  , row_number() over (
      partition by c.id_ihfintech_loan, date_trunc('month', date_add('day', 1, c.fechavencimiento))
      order by c.fechavencimiento) as rn
  , row_number() over (
      partition by c.id_ihfintech_loan, date_trunc('month', date_add('day', 1, c.fechavencimiento)),
                   case when day(date_add('day', 1, c.fechavencimiento)) >= 2 then 1 else 0 end
      order by c.fechavencimiento) as rn_grupo
  from dts_cobranza_creditos_cuotas c
  join prestamos p on p.id_loan = c.id_ihfintech_loan
  join saldo_venc f
    on f.id_loan = c.id_ihfintech_loan
   and f.fechaproceso = date_format(c.fechavencimiento, '%Y%m%d')
  where c.status in ('ACTIVE','COMPLETED')
    and c.fechavencimiento between date '2024-12-31' and date '2026-09-11'
)
, calendario_anc as (
  select cr.*, an.saldo_ancla
  , case when an.saldo_ancla > 0 then 1 else 0 end as tiene_ancla
  from calendario_rn cr
  left join ancla an
    on an.id_loan = cr.id_loan
   and an.mes_foto = date_format(date_add('month', -1, cr.mes), '%Y%m')
)
select
  date_format(cr.mes, '%Y%m')                                  as periodo
, day(cr.f_entrada_cal)                                        as dia_entrada
, case when cr.saldo >= 0.9*cr.amountfinanced then 'a. avance <10%'
       when cr.saldo >= 0.6*cr.amountfinanced then 'b. avance 10-40%'
       when cr.saldo >= 0.3*cr.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end                               as avance_band
, case when cr.tiene_ancla = 0 then '-'
       when cr.saldo_ancla >= 0.9*cr.amountfinanced then 'a. avance <10%'
       when cr.saldo_ancla >= 0.6*cr.amountfinanced then 'b. avance 10-40%'
       when cr.saldo_ancla >= 0.3*cr.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end                               as avance_band_anc
, case when s1.id_loan is not null then 1 else 0 end           as st_v1
, case when s2.id_loan is not null then 1 else 0 end           as st_v2
, cr.reeng
, least(cr.rn, 2)                                              as orden
, case when day(cr.f_entrada_cal) >= 2 then least(cr.rn_grupo, 2) else 0 end as orden_d2
, case when e.id_loan is not null then 1 else 0 end            as entra
, case when e.id_loan is not null and m.dni is not null then 1 else 0 end as arrastre
, cr.tiene_ancla
, count(*)                                                     as creditos
, round(sum(cr.saldo), 2)                                      as saldo
, round(sum(case when cr.tiene_ancla = 1 then cr.saldo_ancla else 0 end), 2) as saldo_ancla
from calendario_anc cr
left join st_v1 s1    on s1.id_loan = cr.id_loan and s1.mes = cr.mes
left join st_v2 s2    on s2.id_loan = cr.id_loan and s2.mes = cr.mes
left join entradas e  on e.id_loan = cr.id_loan and e.mes = cr.mes
left join dni_mora30 m on m.fecha = e.f_ent and m.dni = e.dni
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
order by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
;

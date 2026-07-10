-- =====================================================================
-- ENFOQUE BETA - "SALIDA DE MORA": cura real vs. cura sin pago
-- (candidata a reestructuracion). Ejecutado 2026-07-10 en Athena
-- (db dev_datalake_master). Ver enfoque_salida_mora.md para la
-- explicacion completa e interpretacion de resultados.
--
-- Concepto: no basta con que el sistema deje de marcar mora (dayslate
-- vuelve a 0) para contar como "salida real" -- el saldo capital
-- tambien debe haber bajado durante el episodio. Los casos donde sale
-- de mora SIN que el saldo baje son candidatos a reestructuracion
-- (facilidad de pago que resetea el estado sin cobro real).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. DETECCION DE EPISODIOS DE MORA completos (entrada -> salida) y
-- clasificacion. Usa el patron "gaps and islands" (rn - row_number()
-- particionado por estado) para agrupar corridas consecutivas de
-- mora>0 por credito, y compara saldo_entrada (dia que entra en mora)
-- vs saldo_salida (primer dia que vuelve a mora=0).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , row_number() over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as rn
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso between '20250301' and '20260630'
    and coalesce(lc.last_in_chain,1) = 1
)
, mora_flag as (
  select *, case when mora > 0 then 1 else 0 end as en_mora
  from fotos
)
, episodios_marca as (
  select *,
    rn - row_number() over (partition by id_loan, en_mora order by fechaproceso) as grp
  from mora_flag
)
, episodios as (
  select id_loan, grp,
    min(fechaproceso) as fecha_inicio, min(rn) as rn_inicio,
    max(fechaproceso) as fecha_fin, max(rn) as rn_fin,
    count(*) as dias_en_mora
  from episodios_marca
  where en_mora = 1
  group by 1,2
)
, con_saldos as (
  select e.id_loan, e.fecha_inicio, e.fecha_fin, e.dias_en_mora,
    f_in.saldo as saldo_entrada,
    f_out.fechaproceso as fecha_salida,
    f_out.saldo as saldo_salida,
    f_out.mora as mora_salida
  from episodios e
  join fotos f_in on f_in.id_loan = e.id_loan and f_in.rn = e.rn_inicio
  left join fotos f_out on f_out.id_loan = e.id_loan and f_out.rn = e.rn_fin + 1
)
, con_motivo as (
  select distinct id_ihfintech_loan, "_motivo_apertura__motivo_apertura" as motivo_apertura
  from dts_cobranza_creditos_cuotas
  where "_motivo_apertura__motivo_apertura" is not null
)
select
  case when cs.saldo_salida is null then 'sin_salida_observada (censurado)'
       when cs.saldo_entrada - cs.saldo_salida > 0.01 * cs.saldo_entrada then 'cura_real (baja >1%)'
       when cs.saldo_entrada - cs.saldo_salida > 0 then 'cura_parcial (baja <=1%)'
       else 'cura_sin_pago (no baja)' end as clasificacion
, count(*) as episodios
, count(distinct cs.id_loan) as creditos
, round(sum(cs.saldo_entrada),0) as saldo_entrada_total
, count(distinct m.id_ihfintech_loan) as con_motivo_apertura
from con_saldos cs
left join con_motivo m on m.id_ihfintech_loan = cs.id_loan
group by 1
order by 1
;

-- ---------------------------------------------------------------------
-- Q2. DESGLOSE por valor especifico de motivo_apertura (1-4), dentro de
-- cura_real vs cura_sin_pago. Mismas CTEs base que Q1 (repetidas aqui
-- para que la query sea autocontenida y copiable).
-- ---------------------------------------------------------------------
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan
  , a.fechaproceso
  , a.balances_principalbalance as saldo
  , coalesce(a.dayslate,0) as mora
  , row_number() over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as rn
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')
    and a.fechaproceso between '20250301' and '20260630'
    and coalesce(lc.last_in_chain,1) = 1
)
, mora_flag as (
  select *, case when mora > 0 then 1 else 0 end as en_mora
  from fotos
)
, episodios_marca as (
  select *,
    rn - row_number() over (partition by id_loan, en_mora order by fechaproceso) as grp
  from mora_flag
)
, episodios as (
  select id_loan, grp,
    min(fechaproceso) as fecha_inicio, min(rn) as rn_inicio,
    max(fechaproceso) as fecha_fin, max(rn) as rn_fin,
    count(*) as dias_en_mora
  from episodios_marca
  where en_mora = 1
  group by 1,2
)
, con_saldos as (
  select e.id_loan, e.fecha_inicio, e.fecha_fin, e.dias_en_mora,
    f_in.saldo as saldo_entrada,
    f_out.fechaproceso as fecha_salida,
    f_out.saldo as saldo_salida,
    f_out.mora as mora_salida
  from episodios e
  join fotos f_in on f_in.id_loan = e.id_loan and f_in.rn = e.rn_inicio
  left join fotos f_out on f_out.id_loan = e.id_loan and f_out.rn = e.rn_fin + 1
)
, con_motivo as (
  select distinct id_ihfintech_loan, "_motivo_apertura__motivo_apertura" as motivo_apertura
  from dts_cobranza_creditos_cuotas
  where "_motivo_apertura__motivo_apertura" is not null
)
, clasificado as (
  select cs.*,
    case when cs.saldo_salida is null then 'sin_salida_observada'
         when cs.saldo_entrada - cs.saldo_salida > 0.01 * cs.saldo_entrada then 'cura_real'
         when cs.saldo_entrada - cs.saldo_salida > 0 then 'cura_parcial'
         else 'cura_sin_pago' end as clasificacion
  from con_saldos cs
)
select
  c.clasificacion
, m.motivo_apertura
, count(distinct c.id_loan) as creditos
, round(avg(c.dias_en_mora),1) as dias_en_mora_prom
, round(sum(c.saldo_entrada),0) as saldo_entrada_total
from clasificado c
join con_motivo m on m.id_ihfintech_loan = c.id_loan
where c.clasificacion in ('cura_sin_pago','cura_real')
group by 1,2
order by 1,2
;

-- ---------------------------------------------------------------------
-- Q3. UBICACION Y VALORES de la columna motivo_apertura (referencia).
-- Vive en dts_cobranza_creditos_cuotas (nivel cuota, aunque el valor es
-- constante por credito), campo "_motivo_apertura__motivo_apertura"
-- (nombre duplicado por venir de un custom field anidado de Mambu).
-- Poblada en solo 721 de ~198,000 creditos (0.4%). NO hay diccionario
-- de datos confirmado para 1/2/3/4 -- pendiente preguntar a negocio.
-- ---------------------------------------------------------------------
select
  "_motivo_apertura__motivo_apertura" as motivo_apertura
, count(*) as filas
, count(distinct id_ihfintech_loan) as creditos
from dts_cobranza_creditos_cuotas
group by 1
order by 1
;

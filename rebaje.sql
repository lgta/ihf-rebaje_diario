-- SELECT COUNT(1) FROM   -- 	2294959 
with 
base_diaria as 
(

SELECT 
substr(a.fechaproceso, 1,6) as periodo
, a.fechaproceso
, cast(substr(a.fechaproceso, 7,2) as int) as dia 
, b."type" as producto 
, b.subproducto
, a._datos_adicionales_loan_accounts_id_ihfintech as id_ihfintech_loan
, a.balances_principalbalance as saldo_capital_total
, b.amountfinanced as monto_financiado
, a.dayslate

, c.dias_atraso_cuota
, c.cuotaporvencer
, c.fechaporvencer
FROM dts_mambu_loans_hist a
left join dts_okaapi_loans b
on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
LEFT JOIN dts_cobranza_creditos_calendario_diario C
ON date_format(c.fecha_calendario, '%Y%m%d')  = A.fechaproceso
AND B.id_ihfintech_loan = C.id_ihfintech_loan
where B.status in ('ACTIVE','COMPLETED')

)
, base_diaria_saldo as 
(
select  
*
,  LAG(saldo_capital_total) OVER (
   PARTITION BY id_ihfintech_loan
   ORDER BY fechaproceso ASC
   ) AS saldo_capital_total_dia_anterior
, case when dayslate is not null then 
        case when dayslate>dia then 'a. Antiguo'
        when dayslate<=dia then 'b. Nuevo'else null end 
        else null end as tipo_mora
from base_diaria

)
,
base_diaria_rebaje
as 
(
SELECT 
* 
, coalesce(saldo_capital_total_dia_anterior,0) - coalesce(saldo_capital_total,0) as delta_diario_saldo_capital_total
FROM base_diaria_saldo
-- WHERE id_ihfintech_loan = '031b4ee8-de02-4923-a51f-ef27ef585bdc'
)
, creditos_cobranza 
as 
(
select 
distinct 
id_ihfintech_loan
, periodo
, tipo_mora
from base_diaria_rebaje
where dayslate> 0
)
,
base_cobranza_alimentada
as 
(
select 
a.*
, b.tipo_mora
from base_diaria_rebaje a
join creditos_cobranza b
on a.id_ihfintech_loan = b.id_ihfintech_loan
and a.periodo = b.periodo
)

select * from base_cobranza_alimentada

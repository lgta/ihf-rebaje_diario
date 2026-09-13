-- =====================================================================
-- TAREA 24 -- CASOS B: ¿son pagos regularizados/revertidos?
--
-- Los 25 creditos que la asignacion tiene como TEMPRANA/antiguo el 1-sep y
-- que para dias_atraso_cuota estan al dia (mora 0 el 31-ago, 1-sep y 2-sep).
-- Mambu (dayslate) le da la razon al negocio en 24 de 25, y la tabla de
-- cuotas marca la cuota vencida como pagada (17) o no la tiene (8).
-- Hipotesis del usuario (2026-09-13): pagos regularizados. Se listan las
-- transacciones de pago de Mambu de cada uno desde el 20-jul, marcando las
-- revertidas (adjustmenttransactionkey no nulo -- misma logica que usa la
-- vista en Pagos_ajustados) y las que tienen fecha valor distinta al registro.
-- IDs fijos, salidos de datos_tarea24/casos_b.csv.
-- =====================================================================
with casos (id_loan, venc_negocio, mora_negocio, monto_asignado) as (
  values
    ('db79efdf-0560-429f-b405-76842275699f', date '2026-08-31',  1, 16080.00),
    ('489eb2a0-6e4f-46e5-a787-56c2086c58c4', date '2026-08-13', 19,  8563.60),
    ('242d303a-2803-400d-9759-b8ce966db540', date '2026-08-05', 27,  6524.55),
    ('fad17a21-4ed6-49f3-b179-a6c324fb6f3b', date '2026-08-31',  1,  4058.19),
    ('bbc8c411-25a8-4ae1-a390-6466239764e5', date '2026-08-24',  8,  4039.76),
    ('cbfb56dc-1a03-410c-a86e-0fdc569b17d6', date '2026-08-12', 20,  3706.92),
    ('b7cce032-1101-44d9-8495-7ffd07dc0210', date '2026-08-31',  1,  3666.95),
    ('9516ddbd-446d-4f78-9516-5c975d5cfc86', date '2026-08-18', 14,  2805.98),
    ('a1d89df4-4b9b-42c8-a361-0c0cb0d65ca6', date '2026-08-31',  1,  1927.60),
    ('6b082a86-fc2c-4d6f-8c85-d5314496fdcd', date '2026-08-26',  6,  1841.27),
    ('f9d36f7b-7f35-4894-9581-e377e3b1c887', date '2026-08-28',  4,  1647.17),
    ('a726e0ae-87c9-4b99-a9f3-906bb219243b', date '2026-08-24',  8,  1635.39),
    ('5c804ea5-0068-4812-bbef-f899832df594', date '2026-08-25',  7,  1565.97),
    ('fc963644-0268-4622-868e-8cc49c9853b4', date '2026-08-24',  8,  1267.77),
    ('66c9302f-6215-4532-b96d-927075b60514', date '2026-08-18', 14,  1010.24),
    ('49008a2e-bd33-4d49-a61d-9c0cd371970b', date '2026-08-18', 14,   656.79),
    ('0ad05e41-9ee9-4ccd-a38a-870562af930a', date '2026-08-31',  1,   453.34),
    ('7fd7d9e7-74a7-4039-a7d2-f1bb79014463', date '2026-08-26',  6,   431.31),
    ('279ee4b8-8d1c-4b3c-9757-2d6157e283c8', date '2026-08-25',  7,   400.50),
    ('8f8cb20b-337f-4d28-972a-92da66371505', date '2026-08-28',  4,   341.57),
    ('07800b32-edb7-4724-a909-87c948f71a67', date '2026-08-18', 14,   302.90),
    ('6de29114-ce26-4230-8fc6-7c3830416d5e', date '2026-08-31',  1,   284.69),
    ('a923fae2-aa3a-4df6-8d78-8f90d55118e6', date '2026-08-29',  3,   121.38),
    ('e73c5b58-7391-4fcd-944b-28d10020d0b0', date '2026-08-24',  8,   116.21),
    ('b16639f3-c156-4f8d-a7f1-854d620da1d3', date '2026-08-15', 17,     5.56)
)
, cuentas as (
  select distinct l._datos_adicionales_loan_accounts_id_ihfintech as id_loan, l.encodedkey
  from dts_mambu_loans l
  join casos c on c.id_loan = l._datos_adicionales_loan_accounts_id_ihfintech
)
, tx as (
  select distinct cu.id_loan, t.encodedkey, t.type, t.creationdate, t.valuedate, t.amount,
         t.affectedamounts_principalamount as capital, t.adjustmenttransactionkey
  from dts_mambu_loanstransactions t
  join cuentas cu on cu.encodedkey = t.parentaccountkey
  where t.creationdate >= timestamp '2026-07-20 00:00:00'
    and (t.type like '%REPAYMENT%' or t.type like '%ADJUSTMENT%')
)
select
  c.id_loan
, c.venc_negocio
, c.mora_negocio
, c.monto_asignado
, tx.type
, tx.creationdate                                        as registrada
, tx.valuedate                                           as fecha_valor
, round(tx.amount, 2)                                    as monto
, round(tx.capital, 2)                                   as capital
, case when tx.adjustmenttransactionkey is not null then 'REVERTIDA' else '' end as revertida
, date_diff('day', date(tx.valuedate), date(tx.creationdate)) as dias_valor_antes_de_registro
from casos c
left join tx on tx.id_loan = c.id_loan
order by c.monto_asignado desc, tx.creationdate
;

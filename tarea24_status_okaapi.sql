-- =====================================================================
-- TAREA 24 -- ¿EL FILTRO DE STATUS TAMBIEN MIRA HACIA ADELANTE?
--
-- Pregunta hermana de bug 25 (flg_last_loan_in_chain se lee con la foto de
-- hoy). Si un credito que se refinancia o castiga despues pasara a un
-- status fuera de ACTIVE/COMPLETED, el filtro de status tambien lo borraria
-- de la historia. Resultado (2026-09-13): NO -- los creditos con flag 0
-- (no ultimos de su cadena) estan TODOS en COMPLETED, y el filtro solo saca
-- DELETED y REQUESTED. El unico filtro que mira adelante es el de cadena.
-- =====================================================================
select b.status
, count(*)                                              as creditos
, count(case when lc.last_in_chain = 0 then 1 end)      as flag0
from dts_okaapi_loans b
left join (select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
           from dts_cobranza_creditos_cuotas group by 1) lc
  on lc.id_ihfintech_loan = b.id_ihfintech_loan
group by 1
order by 2 desc
;

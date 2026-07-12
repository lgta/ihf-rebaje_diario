# Bugs y gotchas

Un registro por bug: síntoma, causa raíz, fix, impacto medido. Orden cronológico. Antes de
escribir una query nueva sobre estas tablas, vale la pena escanear esta lista — varios de
estos ya mordieron más de una vez.

---

### 1. Filtro de prueba hardcodeado en `rebaje.sql`
**Síntoma:** el análisis original solo consideraba un crédito (`WHERE id_ihfintech_loan =
'031b4ee8-...'`). **Fix:** comentar la línea. Trivial, pero fue el primer bug de la sesión.

### 2. `status='ACTIVE'` excluye `COMPLETED` (sesga curvas hacia abajo)
**Síntoma:** la curva de # operaciones daba 60.8%/69.0% (día0/día1), muy por debajo de la
referencia de negocio (~70%/~85%). **Causa:** `COMPLETED` son los créditos que ya
terminaron de pagar bien — excluirlos deja solo a los que siguen con problemas, sesgando
cualquier ratio hacia abajo. **Fix:** `status IN ('ACTIVE','COMPLETED')` para todo análisis
histórico/de calibración (no para calendarios prospectivos, ver `DECISIONES.md`).
**Impacto:** +4-5pp en la curva de operaciones.

### 3. Reenganches/refinanciamientos sin excluir
**Síntoma:** mismo síntoma que el bug 2 (curva por debajo de la referencia). **Causa:** un
crédito refinanciado deja cuotas "colgadas" en `LATE` para siempre — nunca se marcan
`PAID`, arrastran cualquier promedio hacia abajo. `dts_okaapi_loans` no tiene un flag
confiable para esto. **Fix:** derivar un flag a nivel crédito desde
`dts_cobranza_creditos_cuotas.flg_last_loan_in_chain` (`max(...)` agrupado por
`id_ihfintech_loan`, es constante por crédito) y filtrar `coalesce(last_in_chain,1)=1`.
**Impacto:** +7-8pp sobre TODA la cartera; solo -0.3 a -0.9pp sobre poblaciones ya acotadas
a mora 1-30 (los reenganches sanos no entraban ahí de todos modos — no asumir que un
impacto grande en un universo se traslada 1:1 a un universo más chico).

### 4. Window function evaluada antes del `WHERE` (Presto/Athena)
**Síntoma:** un acumulado (`SUM(...) OVER (ORDER BY dia)`) arrancaba mal cuando la misma
query tenía `WHERE dia IN (...)`. **Causa:** Presto/Athena aplica el `WHERE` ANTES de
evaluar la window function — el acumulado arranca desde el primer valor que sobrevive al
filtro, no desde el día 1 real. **Fix:** calcular el acumulado completo en una CTE, filtrar
los días de interés en una consulta externa. **Mordió 2+ veces:** la curva de operaciones
(2A) y, más seriamente, la severidad de "nuevos" segmentada por avance (2D) — los números
reportados inicialmente (8.2/11.0/22.5/38.4 a día 31) eran incorrectos; corregidos a
14.4/19.8/40.9/74.2.

### 5. `principalamountpaid`/`principalamountdue` rotos para capital
**Síntoma:** el acumulado de recupero superaba 400%. **Causa:** estos campos de
`dts_cobranza_creditos_cuotas` sobre-atribuyen pagos anticipados/cancelaciones totales a
cuotas individuales (doble conteo). **Fix:** no usarlos para capital — usar deltas de
`balances_principalbalance` en `dts_mambu_loans_hist` (ya validado). Sirven solo para la
curva de validación en # de operaciones.

### 6. P(no paga a tiempo) = 27.4% mal aplicado — el bug más caro (+79% de error)
**Síntoma:** el primer backtest contra junio 2026 sobreestimó +79%. **Causa:** se usó 27.4%
(complemento de la curva de operaciones a nivel CUOTA, día 0) como si fuera la tasa de
entrada a mora a nivel CRÉDITO — son poblaciones distintas (ver bug 9, el punto ciego de 1
día explica gran parte de por qué). **Fix:** medir la tasa directamente a nivel crédito
(`dayslate` 0→1), fuera de muestra (10 meses previos a junio, sin junio, para evitar data
leakage): **13.38%** (47,966/358,580). **Impacto:** error bajó de +79% a +5.4%.

### 7. Exclusión silenciosa de "aged-out survivors" en `meta_desde_hoy.sql`
**Síntoma:** el enfoque "reinicio del reloj" excluía créditos que deberían contar.
**Causa:** el filtro `mora between 1 and 30` se evaluaba con la mora de HOY, no la de
asignación — un crédito que era parte del stock original de julio pero ya cruzó 30 días
para el corte quedaba fuera, violando la regla confirmada de que un crédito asignado sigue
contando aunque cruce 30 días. **Fix:** bloque Q0 que reincorpora a estos créditos vía JOIN
contra la foto de asignación (30-jun), aplicando `curva[día31]-curva[día9]` sobre su saldo
original. **Impacto:** 244 créditos / S/501,307 estaban siendo excluidos; su aporte real al
resto del mes es solo S/22,510 (mora profunda → baja frecuencia de pago). Nota: NO se debe
simplemente quitar el límite superior del filtro — eso arrastraría S/9.57M de cartera 90+
días que nunca fue parte de la asignación de julio.

### 8. Doble conteo menor en el calendario de nuevos (Q2 de `meta_desde_hoy.sql`)
**Síntoma:** 3 créditos / S/6,843 contados dos veces (como "aged-out" y como "en riesgo" en
el calendario). **Fix:** la exclusión del calendario ahora usa TODO el stock de asignación,
no solo el que sigue 1-30 hoy.

### 9. `dayslate` tiene un punto ciego de ~1 día (no es un bug, es un comportamiento del sistema fuente)
**Síntoma:** una cuota pagada exactamente 1 día tarde casi nunca hace que `dayslate` llegue
a mostrar 1 (solo 4.3% de 10,533 casos de muestra). Pagos 2+ días tarde sí se detectan al
100%, sin excepción — corte binario limpio. **Causa probable:** la foto diaria captura el
estado DESPUÉS de que el pago ya se aplicó, si el pago se resolvió el mismo/siguiente día.
No es un "bug" en el sentido de diseño incorrecto — es una limitación de granularidad
(snapshot 1 vez al día) frente a una cuota que se resuelve casi de inmediato. Ejemplo
verificado: crédito `eb9ef9f2-0326-484d-85b8-164a3e974da9`
(`investigacion_dayslate.sql` Q5). **Implicación:** no mezclar tasas/curvas calibradas por
`dayslate` con estadísticas de cuota tipo `dias_vencimiento_a_pago>=1` — ver bug 10.

### 10. Swap de tasa sin recalibrar la curva (25% plano) — sobreestima +66% a +81%
**Síntoma:** al proponer usar 25% (complemento de "% paga a tiempo" a nivel cuota) como
reemplazo de 13.38%, manteniendo la curva de recupero actual sin cambios, el backtest de
junio dio +66.5% de error (25%), +71.7% (26%), +79.1% (27.4%, coincide exacto con el bug
6), +81.2% (27.8%). **Causa:** la tasa y la curva deben describir la misma población — ver
`feedback-tasa-curva-consistente` en memoria y `DECISIONES.md`. **Se probó también** la
versión "propiamente consistente" (tasa Y curva ambas redefinidas por vencimiento de
cuota): tasa 8.62%, pero el backtest **subestima** -35.7% — falla en la dirección opuesta.
Ninguna alternativa supera al modelo oficial. Ver `motor_cuota_vencimiento.sql`,
`backtest_motor_cuota.py`, y el artifact
[⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8).

**SQL del motor "cuota-consistente" (`motor_cuota_vencimiento.sql`):** detecta "entrada"
por vencimiento de cuota, no por `dayslate`, deduplicando episodios con
`lag(a_tiempo) over (partition by id_loan order by fechavencimiento) as a_tiempo_prev` —
solo cuenta como entrada si la cuota actual NO está a tiempo Y la cuota INMEDIATA anterior
del mismo crédito SÍ lo estaba (análogo al `mora_ant=0 and mora=1` de `dayslate`, pero
sobre la secuencia de cuotas en vez de la foto diaria). La tasa (8.62%) y la curva de
recupero propia se calibran sobre esta misma definición — por eso el experimento es un
buen ejemplo de "hacerlo bien" (tasa y curva consistentes) que aun así no supera al
modelo oficial en el backtest.

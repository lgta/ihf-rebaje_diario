# Bugs y gotchas

Un registro por bug: síntoma, causa raíz, fix, impacto medido. Orden cronológico. Antes de
escribir una query nueva sobre estas tablas, vale la pena escanear esta lista — varios de
estos ya mordieron más de una vez.

> **Nota (2026-07-15):** los bugs 7 y 11 documentan archivos de los enfoques "reinicio del
> reloj" y "salida de mora", descontinuados y eliminados del repo ese día (ver
> `DECISIONES.md`) — el registro se conserva como historial, pero `meta_desde_hoy.sql` y
> `enfoque_salida_mora.sql` ya no existen.

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

### 11. Filas duplicadas por (crédito, día) en `dts_mambu_loans_hist` rompen el patrón "gaps and islands" (no reproducible)
**Síntoma:** al investigar reincidencia de "cura sin pago" (`enfoque_salida_mora.sql`
Q4), la misma query devolvía conteos distintos en corridas sucesivas (420 vs. 415
episodios elegibles) — algo nunca visto antes en este proyecto. **Causa:** 1,316
combinaciones `(id_loan, fechaproceso)` de 46.7M (0.003%) tienen filas duplicadas (hasta
10 en un mismo día), 691 de ellas con `saldo`/`dayslate` **conflictivos** entre sí (no son
duplicados exactos). El `row_number() over (partition by id_loan order by fechaproceso)`
usado en el patrón de islas (`enfoque_salida_mora.sql`, también documentado en
`enfoque_capital_asegurado.md`) no tenía desempate — con `fechaproceso` empatado, Presto
no garantiza un orden estable, así que `rn` (y por lo tanto `grp`, los límites de
episodio, y crucialmente `rn_fin + 1` para ubicar `saldo_salida`) cambiaba entre
corridas. Una foto duplicada en medio de una racha de mora podía fragmentar un episodio
real en 2+ episodios falsos. **Fix:** dedup determinista por `(id_loan, fechaproceso)`
antes de calcular `rn`, vía `row_number() over (partition by id_loan, fechaproceso order
by lastmodifieddate desc, id desc)` (`id` es la clave nativa de Mambu, siempre única —
garantiza desempate total; `fechaactualizaciontabla`, el timestamp de carga ETL, NO sirve
porque es idéntico entre duplicados en 1,314 de 1,316 casos — vienen del mismo batch).
**Impacto medido** (reclasificación completa de `enfoque_salida_mora.sql` Q1): episodios
`cura_sin_pago` 513→376 (-27%, eran fragmentos falsos del MISMO crédito — créditos
afectados 364→363, casi sin cambio); `dias_en_mora_prom` de motivo=1 dentro de
`cura_sin_pago` subió de 34.5 a 48.8 días (el fragmento se veía más corto de lo real).
`cura_real` casi no se movió (70,314→70,208 episodios, -0.15%) porque son episodios más
largos, menos sensibles a una foto de más. **Las proporciones agrupadas por
`motivo_apertura` (~97x reprogramación, ~15x adelanto/producto) no cambiaron de forma
material** — el hallazgo cualitativo se mantiene, solo se corrigieron los conteos.
**Un hallazgo inicial SÍ se revirtió:** la primera corrida (sin el fix) sugería que
"cura sin pago" recae más RÁPIDO que "cura real" (mediana 20.3 vs. 28.1 días) — con el
fix, es al revés: recae con más frecuencia (80.8% vs. 63.8%) pero en un plazo similar o
algo más lento (mediana 31.0 vs. 28.1 días). **Implicación:** cualquier query nueva sobre
`dts_mambu_loans_hist` que use `row_number() over (partition by id_loan order by
fechaproceso)` debe agregar el dedup de arriba primero. `enfoque_salida_mora.sql` (Q1,
Q2, Q4, Q5) ya lo tiene. **Pendiente:** el resto de queries de este proyecto
(`fase1_stock.sql`, `fase2_nuevos.sql`, `fase3_backtest.sql`,
`enfoque_capital_asegurado.sql`, etc.) usan el mismo patrón sin este desempate — no se
re-corrieron porque el impacto ahí es sobre agregados de saldo/curvas (mucho menos
sensibles a un desempate de un día que un contador de episodios discretos), pero si algún
resultado de esos archivos se ve raro o no reproducible, este es el primer sospechoso.

**Actualización 2026-08-20 — el desempate `lastmodifieddate desc` elige mal en ~1 de cada
3 casos conflictivos, hay una regla mejor:** ejemplo real encontrado (crédito
`5a2e85db-199d-45ca-97e2-761f0c5af13c`, 17 al 21 de junio 2026): dos filas por día, una de
una cuenta Mambu vieja cerrándose a S/0 (`id` `028...`) y otra de la cuenta nueva del
reenganche con saldo S/1,662.18 (`id` `029...`) — confirmado por 10 días de saldo estable
después (17-jun a 26-jun) y porque `dts_cobranza_creditos_cuotas` solo tiene el cronograma
de la cuenta nueva. La regla `lastmodifieddate desc` elige la fila de S/0 (LATER
timestamp, pero el estado STALE) — equivocada en este caso.

Perfil rápido (muestra may-jul 2026, no la historia completa, para no escanear 46.7M
filas): **16 grupos duplicados con saldo conflictivo, 100% del mismo patrón "cero vs.
no-cero"** (reenganche) — ningún otro patrón de conflicto apareció en la muestra. La
regla actual elige el candidato en S/0 en **5 de 16 (31%)**.

**Regla propuesta (no aplicada todavía):** preferir el candidato con saldo≠0 antes que
`lastmodifieddate`; usar `lastmodifieddate desc, id desc` solo como desempate final si
ambos son cero o ambos son no-cero. Resuelve 16/16 de la muestra. **Cruce con bug 14:**
verificado que esto NO afecta la reconciliación de la capa fantasma — de los 3,130
créditos "fantasma" de julio, solo 1 tiene alguna fila duplicada en julio y ninguno tiene
`dayslate` conflictivo (bug 11 y bug 14 son independientes, no se solapan).

**Actualización 2026-08-20 (continuación) — regla validada contra la historia completa y
aplicada a Enfoque alfa (Tarea 3 de `PENDIENTES.md`):** se reprodujo el universo exacto de
bug 11 (`status IN ('ACTIVE','COMPLETED')`, `last_in_chain=1`, `fechaproceso BETWEEN
'20250301' AND '20260630'` — el mismo filtro que usaba `enfoque_salida_mora.sql`) y dio
**1,312 grupos duplicados / 687 conflictivos** (vs. 1,316/691 originales — diferencia de
~4 casos, esperable por datos que llegaron tarde desde la sesión original, no un error de
reconstrucción). **100% de los 687 casos conflictivos son el patrón "cero vs. no-cero"**
(no solo el 16/16 de la muestra acotada) — no aparece ningún otro patrón de conflicto en
la historia completa.

Aplicando la regla propuesta (saldo≠0 antes de `lastmodifieddate`) contra la regla vieja:
**145 de 687 (21.1%) cambian de pick** — la regla vieja elegía el candidato en S/0 en esos
145 casos (cifra en la misma escala que el 31% de la muestra de 16, dentro del margen de
una muestra tan chica). Validación contra evidencia independiente (saldo del mismo crédito
en días adyacentes sin ambigüedad propia, ventana ±10 días): de los 145 casos, **116
tienen alguna referencia no-ambigua disponible — 100% de esas 116 confirman el saldo
no-cero** (46 con match exacto, 70 más cercanas al no-cero que al cero) y **0 confirman el
cero**. Sin contradicciones. Detalle de las queries de validación: sesión 2026-08-20,
scratchpad (no copiado al repo — ver "Pendiente de copiar" en `ESTADO.md` si se necesita
reconstruir).

**Aplicado a producción:** dedup con la regla validada agregado a `enfoque_capital_
asegurado.sql` (Q1, Q2, Q3 — Q3 ya tenía dedup pero con la regla vieja, actualizada),
`enfoque_capital_asegurado_backtest.sql` (BT-ASEG-0 a BT-ASEG-3, mismo caso que Q3 para
BT-ASEG-3), `cierre_julio.sql` (J1/J2) e `investigacion_capa_fantasma.sql` (Q3, validación
de julio) — estos 2 últimos no estaban en el pedido original pero alimentan el backtest de
julio con la misma regla, para no comparar una proyección corregida contra un real sin
corregir. `fase1_stock.sql`/`fase2_nuevos.sql`/`fase3_backtest.sql` (recupero oficial,
Tarea 6) **no se tocaron** — fuera de alcance de esta pasada, igual que bug 12/14 (afecta
únicamente Enfoque alfa).

**Impacto medido (re-corrida completa, junio y julio, principio de modelado de
`CLAUDE.md`):**
- **Curvas de calibración (14 meses, `enfoque_capital_asegurado.sql` Q1/Q2):** bajo
  impacto confirmado — el segmento más afectado (tramo 1-8 / avance <10%) pasó de
  9,806,903 a 9,726,381 de saldo total (-0.8%), 3,673→3,648 créditos (-0.7%); el resto de
  segmentos con cambios de magnitud similar o menor. `pct_capital_asegurado_acum` día 31
  se movió <0.2pp en todos los segmentos.
- **`P_FANTASMA` (Q3, tasa prospectiva):** sin cambio de fondo — 29,845/353,054 antes,
  29,845/353,053 después (diferencia de redondeo de 1 unidad en el denominador, no en el
  numerador).
- **Backtest de junio (mes de calibración):** el error total **sube de +0.7% a +2.2%**
  (stock +7.2%→+7.3%, fantasma +11.1% sin cambio, **nuevos -8.6%→-5.8%** — el componente
  que más se mueve, porque el fix elimina "pagos" espurios que el patrón viejo detectaba
  al comparar el saldo real de un crédito contra la fila duplicada en S/0 de un reenganche
  del mismo día). Diff día a día de `bt_real_aseg_nuevos.csv` confirma que el efecto es
  sistemático y pequeño (cada día de junio baja consistentemente 2-5%, no un salto puntual
  en 1-2 días) — consistente con una corrección real, no un artefacto de la query.
- **Backtest de julio (segundo mes cerrado, validación independiente): sin cambio, ni un
  centavo.** `cierre_julio.sql` J1/J2 e `investigacion_capa_fantasma.sql` Q3 dieron
  exactamente los mismos números antes y después del fix (S/3,137,199.21 / S/7,633,719.13
  / S/73,659,266.44 / S/5,742,740.84) — no hay filas conflictivas relevantes en la
  ventana de julio para esta población. El error de julio se mantiene en **+0.1%**.

**Conclusión:** el fix es real y de bajo impacto en el agregado (como se esperaba para un
enfoque basado en saldos/curvas, no en conteo de episodios discretos como
`enfoque_salida_mora.sql`), pero no despreciable — mueve el backtest de junio 1.5pp. Se
documenta en `SEGUIMIENTO.md`/`ESTADO.md`/`enfoque_capital_asegurado.md`. Las curvas
Q1/Q2 y `meta_agosto_capital_asegurado.py` no se recalcularon con este fix (impacto <1pp
en las curvas, no se justifica rehacer la meta de agosto por esto) — **pendiente** si en
el futuro se quiere una meta 100% consistente con el fix.

### 12. Antiguos/nuevos mal cortados en el límite de mes — el día 1 de cada mes se clasificaba como "nuevo" siendo "antiguo" (solo Enfoque alfa)
**Síntoma:** ninguno visible en los agregados (el error total del backtest no se movía
mucho), lo encontró el usuario con un ejemplo conceptual, no un número raro. **Causa:**
`dayslate` cuenta días desde el vencimiento de la cuota — un crédito que muestra
`dayslate=1` exactamente el DÍA 1 de un mes matemáticamente solo puede venir de una cuota
que venció el ÚLTIMO DÍA DEL MES ANTERIOR (vencimiento = día − dayslate). La detección de
"nuevos" vía `mora_ant=0 and mora=1` (sin excluir el día 1) contaba a TODA esa cohorte
como "nuevo" cuando en realidad es "antiguo" (ya inicia el mes con mora, la cuota es de
antes) — no es un caso raro, es sistemático, todos los meses. **Fix:** en
`enfoque_capital_asegurado.sql` (Q1/Q2) y `enfoque_capital_asegurado_backtest.sql`
(BT-ASEG-0/1/2): "nuevos" excluye entradas del día 1 del mes; "antiguos" (stock) = stock de
siempre (mora 1-30 al cierre del mes anterior) **UNION** los entrantes del día 1. **OJO —
intento fallido primero:** la primera versión del fix re-ancló TODA la población de stock
al snapshot del día 1 (en vez de sumar solo los entrantes) — eso excluye por accidente a
cualquier crédito de stock que pague justo ese día (la foto del día 1 ya refleja el pago,
así que no aparece como "en mora" y desaparece sin ser contado en ningún lado). Sesgo de
supervivencia: la curva de stock día 1 colapsó de 16.2% a 0.263% de activación acumulada —
señal inequívoca de que algo estaba mal. El fix correcto es la UNIÓN (no tocar la población
existente, solo agregar la puntual de día 1), verificado porque tramos 9-15/16-30
(no afectados por el bug) dieron números IDÉNTICOS antes/después del fix. **Scope:** solo
Enfoque alfa (`enfoque_capital_asegurado*.sql`) — `fase1_stock.sql`/`fase2_nuevos.sql` del
recupero oficial NO se tocaron (no fue parte del pedido). **Impacto medido:**
- Calibración 14 meses: stock +2.9M→+... la población de stock creció ~16% (S/34.1M→S/39.7M,
  19,172→22,418 créditos-mes), toda concentrada en tramo 1-8 (los otros tramos no cambiaron
  — confirma que el fix no tiene efectos secundarios). Forma de las curvas casi no cambió
  (día 31 stock 1-8/avance<10%: 69.7%→71.8%; nuevos día 31 por avance: cambios <0.2pp).
- Backtest de junio 2026: error total **-4.7% → -4.4%** (prácticamente igual, incluso algo
  mejor) — stock +5.6%→+7.2%, nuevos -8.4%→-8.6%. La tasa `P(no paga a tiempo)=13.38%`
  sigue siendo válida sin recalibrar (mide si la entrada ocurre, no en qué día del mes cae).
- Julio en vivo: pendiente de re-correr `avance_capital_asegurado_julio_diario.sql` /
  `_segmentado.sql` / `avance_cobranza_fase.sql` con la definición corregida.

### 13. `dts_asignaciones_cobranza` quedó congelada el 2026-07-10; homologación de `tipo_mora` contra `gestiones_cobranzas` confirma el fix de bug 12
**Contexto:** el 2026-08-18, una sesión del proyecto hermano `gestiones_cobranzas` entregó
un handoff (`prompt_handoff_reconciliacion_gestiones_cobranzas.txt`) para homologar la
clasificación antiguo/nuevo de ambos proyectos. Investigado con
`homologacion_tipo_mora_gestiones.sql`.

**Hallazgo 1 — tabla muerta:** `dts_asignaciones_cobranza` (la que documentaba
`FUENTES_DATOS.md` y usa `avance_cobranza_fase.sql`) dejó de recibir datos el 2026-07-10
(solo 7 días de historia, `min=2026-07-02`, `max=2026-07-10`). La tabla viva equivalente es
**`dts_asignaciones_gestiones_cobranza`** (datos continuos hasta hoy, mismo grano
`(dni_ce, producto)` por `fecha_base`, superset de columnas — incluye `tipo_mora`, que
`dts_asignaciones_cobranza` también tenía pero congelado). **Fix:** cualquier desarrollo
nuevo debe apuntar a `dts_asignaciones_gestiones_cobranza`, no a `dts_asignaciones_cobranza`
— ya aplicado en `avance_cobranza_fase.sql`. Ojo: `fecha_base` es `varchar` en la tabla
nueva (no `date` como en la vieja) — comparar con literal string, no `date('...')`. También
existen `dts_asignaciones_gestiones_cobranza_recon`/`_v2`/`_v3`/`_v4` (backfill estático de
julio completo, 2026-07-01 a 2026-07-31) — no confirmado si son reprocesos puntuales o
snapshots vivos, no usar sin verificar antes.

**Hallazgo 2 — `tipo_mora` (gestiones_cobranzas, fórmula `dias_mora >= day(current_date)`
→ antiguo, a nivel CUOTA) valida el fix de bug 12 (dayslate, a nivel CRÉDITO):** cruce en
día de mitad de mes (2026-08-10, representativo — el día 1 no sirve como test porque la
fórmula de gestiones fuerza TODO a "antiguo" ese día por construcción) sobre la población
mora 1-30 compartida: **98.5% de acuerdo** (1,864/1,892 créditos: 917 antiguo/antiguo + 947
nuevo/nuevo). Cero casos "nuevo(propio)/antiguo(gestiones)" — el desacuerdo va en una sola
dirección.

**Los 28 casos "antiguo(propio)/nuevo(gestiones)" tienen una causa común, no es ruido:** en
los 28, `mora_jul31` (dayslate al cierre de julio) está entre 23-30 días — créditos cerca
del límite de 30 — y entre el 1-ago y el 10-ago el crédito **curó y volvió a caer en mora
con una cuota distinta** (mora al 10-ago bajó a 2-9 días, sobre una cuota recién vencida en
agosto). No es un bug de join ni de datos: es que este proyecto fija la membresía "stock"
para todo el mes por diseño (`DECISIONES.md`, "tramo fijo aunque cruce 30 días"), mientras
que `tipo_mora` se recalcula a diario desde la cuota vigente — si el crédito cura y recae,
gestiones_cobranzas lo reclasifica a "nuevo" y este proyecto no. Conecta directo con la
reincidencia medida en el enfoque beta descontinuado (80.8% de "cura sin pago" recae, bug
11). **No amerita cambiar la regla** (1.5% de la población, comportamiento intencional y ya
documentado) — se deja como diferencia conocida entre ambos proyectos, no como pendiente.

**Nota aparte (no es bug 12, es un hallazgo distinto):** 324 de ~8,800 créditos cruzados
(3.7%) que este proyecto ve "sin mora" (`dayslate`=0/NULL) muestran mora según
`tipo_mora`/`dias_mora` de gestiones_cobranzas — posible punto ciego adicional de `dayslate`
(ver bug 9) a nivel cuota vs. crédito. No investigado a fondo (fuera del alcance pedido por
el usuario, que priorizó solo la homologación antiguo/nuevo) — candidato para
`installmentlastpaiddate` (pendiente #7 de `PENDIENTES.md`) si se retoma.

**Actualización 2026-08-21 (continuación) — cobertura de agosto CERRADA, hipótesis de
timing confirmada con datos:** verificación a nivel crédito de la capa fantasma para
agosto (corte 20-ago, `reconciliacion_agosto.sql` Q3): **81.8% de cobertura**
(1,850/2,262 créditos), vs. 99.7% en julio. Se desagregaron los 412 no cubiertos por
`installmentstate` de su cuota vencida más reciente (Q4): **405/412 (98.3%) todavía no
pagan esa cuota** — timing de mitad de mes, no un hueco del mecanismo (julio ya tiene
todos los desenlaces resueltos, agosto al corte 20-ago no). Solo **7/412 (1.7%,
S/6,704) ya están `PAID` con `dias_vencimiento_a_pago<>1`** — un hueco real pero de
volumen despreciable (0.2% del bucket bug9 total de agosto). **No hay evidencia de que
la capa fantasma tenga un hueco nuevo distinto al ya conocido y corregido** (frontera de
mes). Pendiente: re-medir cuando agosto cierre (día 31) para comparar apples-to-apples
contra el 99.7% de julio — la expectativa es que suba a un nivel similar. Ver
`reconciliacion_vw_seguimiento_temprana.md` pendiente 2 para el detalle.

**Actualización 2026-08-21 — "escalado" a Especializada/Recovery NO es arrastre de DNI,
es fase pegajosa (hallazgo de la reconciliación bug 14, categoría `escalado_sin_temprana`
de `reconciliacion_temprana.sql` Q6/Q8):** al desglosar "solo nuestro" en un dataset
filtrable por crédito (`datos_reconciliacion_temprana/solo_nuestro_motivo_julio.csv`), la
hipótesis inicial para esos 94 créditos era que **otro crédito del mismo DNI** ya estaba
en `ESPECIALIZADA`/`RECOVERY` y arrastraba la clasificación. **Verificado y descartado:**
94/94 (100%) son el ÚNICO crédito de su combinación `dni`+`producto` — no hay ningún
hermano. Lo que sí se confirmó con datos: los 94 mantienen la **misma `fase_estrategia`
fija los 31 días de julio** (0/94 cambia de fase en el mes) mientras que 60/94 (64%)
tienen en algún momento una mora `dayslate` baja (≤5 días, promedio mora_min=8.6). Es
decir, `gestiones_cobranza` no vuelve a bajar de fase a un crédito ya escalado (por
historia previa a julio, probablemente) aunque `dayslate` muestre mora fresca ese mes —
"fase pegajosa", no arrastre. Mecanismo exacto de por qué no baja: no investigado (bajo
volumen, S/199,604). Ver `reconciliacion_vw_seguimiento_temprana.md` para el detalle.

### 14. El punto ciego de `dayslate` (bug 9) es ~27% de la población real de mora 1-30, no un caso de borde — reconciliación contra `vw_seguimiento_diario_cohorte_tramo`
**Contexto (2026-08-19):** el usuario compartió una vista externa "oficial" con detalle a
nivel crédito (`vw_seguimiento_diario_cohorte_tramo.txt`, definición en la raíz del repo,
mantenida fuera de este proyecto) y pidió reconciliar nuestro `capital_asignado` (mora
1-30, Enfoque alfa) contra ella para la fase `TEMPRANA`, identificando motivos si no
cuadraba. Plan de cierre completo, con las queries y el desglose, en
`reconciliacion_vw_seguimiento_temprana.md` — **este bug es el resumen corto, no
repetir el diagnóstico ahí ya hecho.**

**Resultado:** para los 8,269 créditos que ambas fuentes coinciden en incluir (julio
2026), el saldo cuadra casi exacto (nuestro S/13,301,944 vs. oficial `monto_asignado`
S/13,321,309 — 0.15% de diferencia). El mecanismo de fondo (saldo Mambu, `dayslate`
1-30) está bien — el problema es de **cobertura de población**, no de cálculo.

**La diferencia restante (oficial S/18,736,321 vs. nuestro S/15,376,876, ambos ya
deduplicados a 1 fila por crédito) se explica así:**
- **Solo nuestro (S/2.07M) — no requiere acción:** 998 de 1,224 créditos (82%) son
  `grupo_control='CONTROL'` en `dts_asignaciones_gestiones_cobranza` (grupo de control,
  deliberadamente no gestionado — confirmado con el usuario). El resto (119 escalados a
  Especializada/Recovery por arrastre de DNI + 186 sin fase clara + 116 sin match) es
  menor y ya está explicado.
- **Solo oficial (S/5.4M) — sí hay que resolverlo:** **3,210 de 3,449 créditos (93%,
  S/5.02M) tienen `dayslate`=0 para nosotros pero la vista oficial sí los marca en mora
  1-30.** Esto es el **27% de TODA la población TEMPRANA oficial** — mucho más grande que
  el ~3.7% que sugería la muestra genérica de la homologación de `tipo_mora` (bug 13,
  arriba). El punto ciego de `dayslate` (bug 9) no es un caso de borde, es sistemático y
  material. El resto (313 créditos excluidos por nuestro filtro `flg_last_loan_in_chain`,
  que la vista oficial no aplica) es una diferencia de alcance deliberada, no un bug.

**Impacto:** nuestro `capital_asignado` subestima la cartera real de mora 1-30 en ~18%
(15.38M vs. 18.74M) principalmente por este punto ciego, no por un error en las queries.
**Pendiente, con plan de trabajo detallado en `reconciliacion_vw_seguimiento_temprana.md`:**
investigar el mecanismo exacto vía `installmentlastpaiddate` (tarea 7 de `PENDIENTES.md`),
decidir una corrección (con backtest obligatorio antes de adoptarla — no repetir el error
de bug 10, tasa y curva deben calibrarse sobre la misma definición).

**Actualización 2026-08-20 — paso 1 del plan resuelto, no es un patrón nuevo:** al
reconstruir la reconciliación (los archivos de la sesión 2026-08-19 solo quedaron en
scratchpad, nunca se copiaron al repo — ver nota de no-determinismo abajo) y cruzar los
créditos "dayslate=0/oficial mora 1-30" contra `installmentlastpaiddate`
(`dts_cobranza_creditos_cuotas`), **99.5% de los 3,135 créditos de esta muestra
resultó ser exactamente el mismo mecanismo de bug 9** (cuota pagada 1 día tarde, la foto
diaria captura el estado ya resuelto): 546 con `fecha_de_vencimiento_cuota` poblada en
la vista oficial y match directo (gap=1 día exacto); 2,573 más con ese campo NULO
(gap de instrumentación de `dts_asignaciones_gestiones_cobranza`, no causa distinta) pero
con el mismo patrón al buscar la cuota vencida más reciente directamente — pagada 1 día
tarde, el pago cae el MISMO día que `fecha_ancla`. Sin arrastre por DNI (`max_dias_mora_
dni`=`dias_mora` en 2,581/2,588 casos) ni sesgo de producto (BNPL/LD proporcional al mix
general). Detalle completo y query en `reconciliacion_vw_seguimiento_temprana.md` /
`reconciliacion_temprana.sql`. **Bug propio encontrado en el camino:** la primera
reconstrucción de esta sesión tenía el mismo patrón de no-determinismo que bug 11
(`row_number() order by` una columna constante) — corregido con el mismo dedup de bug 11
antes de sacar conclusiones; los dos números (con/sin fix) diferían ~15% en el bucket
final, así que el fix importó. **Sigue pendiente:** paso 2 (decidir corrección, con el
usuario — no elegida de antemano) y paso 3 (backtest obligatorio antes de adoptar nada).

**Actualización 2026-08-20 (continuación, mismo día) — paso 2/3 resueltos, backtest en
2 meses cerrados confirma mejora:** con el usuario, se eligió opción (a) completa
(retrospectivo + prospectivo, solo Enfoque alfa) — diseño "capa fantasma": detecta pago
1 día tarde no visto por `dayslate`, se activa 100% al día siguiente del vencimiento (sin
curva propia), con una tasa nueva e independiente `P_FANTASMA=8.4534%` (no se tocó
`13.38%` ni la curva existente — evita repetir bug 10). **Backtest (sin tocar producción,
`backtest_capital_asegurado_junio_con_fantasma.py` corre en paralelo):** error total baja
de -4.4% a **+0.7% en junio** y de -4.31% a **+0.12% en julio** (segundo mes cerrado,
verificado independientemente) — mejora consistente en los 2 meses disponibles, no un mes
con suerte. Detalle completo, tablas, y el hallazgo colateral de que `SEGUIMIENTO.md`
tenía el signo de julio invertido (decía +4.7%, correcto es -4.31% — mismo signo que
junio) en `reconciliacion_vw_seguimiento_temprana.md`, sección "Paso 2/3 — resultado".

**Adoptado en producción el mismo día, a pedido explícito del usuario:**
`enfoque_capital_asegurado.sql` (Q3, tasa `P_FANTASMA`), `enfoque_capital_asegurado_
backtest.sql` (BT-ASEG-3), `backtest_capital_asegurado_junio.py` (v3, fusionado — ya no
hay script paralelo), `meta_agosto_capital_asegurado.py` (v2) y `SEGUIMIENTO.md` (signo
de julio corregido, filas de junio/julio/agosto actualizadas con la capa fantasma). La
meta de agosto sube de S/10,245,695 a S/16,351,397 y el avance al 18-ago pasa de "+8.7%
adelantado" a "-1.8%" (prácticamente en línea) — ver `ESTADO.md` "La meta vigente" para
el detalle y la nota de que esto es un cambio de metodología, no una señal de deterioro
(el backtest mejora, no empeora, con la capa fantasma).

**Actualización 2026-08-20 (continuación) — hueco de frontera de mes encontrado y
CORREGIDO en producción:** al verificar la capa fantasma a nivel crédito (ver bloque más
abajo, "verificación a nivel crédito") se encontró un hueco de frontera de mes: una cuota
vencida el ÚLTIMO DÍA de un mes de 30 días (ej. 30-jun), pagada 1 día tarde
(fecha_pago=1-jul), queda fuera del filtro `fechavencimiento` de la capa fantasma (que
solo mira dentro del mes objetivo). Confirmado con datos: el 31 de mayo (frontera hacia
junio) tiene **0 cuotas vencidas** — sin impacto ahí — pero el 30 de junio (frontera hacia
julio) tiene **9,115 cuotas** — impacto real. **Fix:** filtrar por `fecha_pago`
(`fechavencimiento+1`) cayendo dentro del mes objetivo, en vez de por `fechavencimiento`
directo — simétrico, sin doble conteo. Aplicado en `enfoque_capital_asegurado_
backtest.sql` (BT-ASEG-3), `investigacion_capa_fantasma.sql` (Q1/Q2/Q3) y
`reconciliacion_temprana.sql` (Q5). **Backtest re-corrido (primera pasada, con la tasa
`P_FANTASMA` VIEJA sin recalibrar):**
- **Junio: sin cambio** (+2.2%, idéntico) — el 31-may no tiene cuotas, no hay nada que
  agregar. Verificado re-corriendo BT-ASEG-3 y comparando: el único diff es que el output
  ya no incluye la fila `20260701` (créditos del 30-jun, que ahora correctamente se
  atribuyen a julio) — esa fila nunca se leía en la suma de junio de todos modos.
- **Julio: el error EMPEORA, de +0.12% a +1.68%** (fantasma +8.4%→+11.7%). Calendario
  fantasma proyectado sube de S/73,659,266 a S/85,280,364 (+7,468 elegibles); real sube de
  S/5,742,741 a S/6,454,260 (+450 créditos netos). Sigue siendo un buen backtest (mucho
  mejor que el -4.31% sin capa fantasma), pero NO es una mejora — a diferencia de todos
  los demás fixes de esta sesión.

**Hallazgo adicional al implementar (mismo día) — la primera pasada de arriba era
INCONSISTENTE, no se debía adoptar tal cual:** el +1.68% de julio se calculó aplicando el
calendario YA corregido (fecha_pago) contra la tasa `P_FANTASMA` VIEJA (8.4534%, calibrada
SIN el fix — es decir, sobre una definición de "periodo" distinta a la que ahora usa el
calendario). Es exactamente el tipo de mezcla que `CLAUDE.md` prohíbe de forma no
negociable (tasa y curva deben calibrarse sobre la misma definición de entrada/cohorte —
ver bug 10). Se recalibró `P_FANTASMA` con el mismo fix de frontera aplicado a su propio
cálculo (`enfoque_capital_asegurado.sql` Q3 / `investigacion_capa_fantasma.sql` Q1):
**8.4534% → 8.5524%** (346,396 elegibles / 29,625 entradas fantasma fuera de muestra,
ago-2025 a may-2026, verificado contra Athena). **Backtest re-corrido con la tasa
consistente (números finales, adoptados):**
- **Junio: +2.2% → +2.65%** (fantasma +11.1%→+12.4%). Como el 31-may no tiene cuotas, el
  movimiento es 100% por el cambio de tasa, no por el calendario.
- **Julio: +1.68% → +2.17%** (fantasma +11.7%→+13.0%). Calendario fantasma proyectado
  S/85,280,364 × 8.5524% = S/7,293,476 (antes S/7,209,074 con la tasa vieja); real sin
  cambio (S/6,454,260, 4,224 créditos — la tasa no afecta lo observado).

Ambos números finales siguen siendo buenos (lejos de bug 10), y el motivo de por qué julio
sube más que junio (dilución por solapamiento con otros eventos de mora del mismo mes, ver
más abajo) sigue aplicando igual — es una propiedad del hueco de cobertura que se cerró,
no un error nuevo introducido por la recalibración de la tasa.

**Adoptado en producción (2026-08-20, con el usuario, ver `SEGUIMIENTO.md` para las filas
finales de junio/julio/agosto):** `enfoque_capital_asegurado.sql` Q3, `investigacion_
capa_fantasma.sql` Q1, `backtest_capital_asegurado_junio.py` v4 (tasa 8.5524%) y
`meta_agosto_capital_asegurado.py` v3 (tasa 8.5524% + cohorte 31-jul: 77 créditos /
S/140,194 en riesgo, confirmado con Athena, no supuesto — real observado a la fecha: solo
4 créditos / S/3,556.95 ya pagaron 1 día tarde). Meta de agosto sube de S/16,351,397 a
**S/16,410,194** (+0.4%).

**Investigación del motivo (por qué julio empeora) — no es un bug, es dilución por
solapamiento:** de los 7,468 elegibles nuevos (cuotas del 30-jun), **600 (8.03%) pagan
exactamente 1 día tarde** — tasa CASI IDÉNTICA al promedio histórico `P_FANTASMA`=8.45%,
no es una población distinta ni un problema de composición de cartera. Pero de esos 600,
**150 (25%) ya estaban contados** como entrada real de mora vía `dayslate` por OTRO
evento en julio (mutuamente excluyente con la capa fantasma, para no duplicar) — dejando
un neto de **450/7,468 = 6.03%**, por debajo del promedio. Es decir: el mecanismo de
"paga 1 día tarde" ocurre a la tasa esperada, pero este cohorte específico tiene una
proporción más alta de créditos que ADEMÁS tienen otro problema de mora ese mes (así que
ya se cuentan por el canal normal) — dilución mecánica, no una señal de que el mecanismo
esté mal. Con solo este mes de evidencia no se puede saber si esto es específico del
30-jun o varianza normal de un cohorte grande y puntual.

**RESUELTO 2026-08-20 — el usuario confirmó adoptar el fix** (con la explicación del
motivo del empeoramiento de julio, ver abajo) y, al implementarlo, se encontró y corrigió
también la inconsistencia tasa/calendario descrita arriba (recalibración de
`P_FANTASMA`). Los números finales adoptados son +2.65%/junio y +2.17%/julio (no
+2.2%/+1.68% como se había estimado antes de recalibrar la tasa) — ver bloque de arriba y
`SEGUIMIENTO.md`. El hueco real del 31-jul en `meta_agosto_capital_asegurado.py` resultó
ser 77 créditos / S/140,194 (no ~101 cuotas como se estimaba antes de confirmarlo con
Athena) — chico, como se esperaba, pero confirmado con datos, no supuesto.

**Actualización 2026-08-20 (continuación) — verificación a nivel crédito: la capa
fantasma NO cubre 1:1 el bucket bug9, encuentra un hueco de frontera de mes nuevo (no
bloqueante):** al cruzar crédito-por-crédito (no solo el agregado monetario) los 3,130
créditos del bucket "solo oficial, `dayslate`=0" contra la capa fantasma de producción,
solo **2,839 (90.7%)** están cubiertos directamente. De los 291 restantes, **281 (96.6%
del gap)** son el mismo mecanismo de bug 9 pero con la cuota disparadora vencida el
**último día del mes ANTERIOR** (ej. 30-jun, pagada 1-jul) — la capa fantasma filtra
`fechavencimiento` dentro del calendario del mes (`>= '2026-07-01'`), así que esta cohorte
queda fuera de la ventana de julio (y tampoco cae en la de junio, porque el evento de pago
es el 1-jul). Es el mismo tipo de problema que bug 12 (frontera de mes en antiguos/nuevos)
pero aplicado a la capa fantasma, que no lo tenía resuelto desde su diseño original.
Sumando ambos, **99.7% del bucket se explica por el mecanismo de bug 9** (consistente con
el 99.5% del paso 1) — el diagnóstico se sostiene, y la implementación de la capa fantasma
tenía un hueco real (~9% de sub-cobertura, ~S/400K/mes estimado). **Corregido 2026-08-20**
(extendiendo la ventana por `fecha_pago` en vez de `fechavencimiento`, mismo patrón de fix
que bug 12) — ver el bloque de arriba para el backtest final y la tasa recalibrada. Ver
`reconciliacion_vw_seguimiento_temprana.md`, tarea 1 de "Pendientes para cerrar TEMPRANA".

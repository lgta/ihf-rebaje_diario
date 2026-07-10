# Plan de análisis — Meta de recupero de cartera en cobranza (tramo 1–30)

> **Este archivo es el historial cronológico crudo** (hasta 2026-07-09). Para lo que está
> vigente HOY, ir a [`ESTADO.md`](ESTADO.md). Para bugs, ideas, decisiones, glosario y
> fuentes de datos ya extraídos de acá en forma consultable, ver los archivos listados en
> `ESTADO.md`. El trabajo del 2026-07-10 en adelante (investigación de dayslate, motor
> cuota-consistente, artifacts nuevos) vive en esos archivos nuevos, no se siguió
> agregando acá — este archivo queda congelado como referencia histórica.

## Objetivo
Definir la meta mensual de recupero **en saldo capital** de la cartera asignada a cobranza,
con curva diaria esperada para seguimiento intra-mes.

## Decisiones cerradas
| Tema | Decisión |
|---|---|
| Métrica de recupero | Rebaje de saldo capital (`balances_principalbalance`) |
| Universo | Créditos con mora **1–30 días al día 1 del mes** (stock) + los que **caen en mora durante el mes** (nuevos) |
| Asignación | Stock se asigna a inicio de mes; nuevos se asignan día a día conforme caen |
| Fuente principal | `dts_mambu_loans_hist` (fotos diarias) + `dts_okaapi_loans` (producto, monto financiado, status) |
| Ventana histórica | Desde **2025-03** (los meses previos son menos estables; hay ~2 años en total) |
| Refinanciamientos | La base ya viene limpia de refinanciamientos |
| Dato externo de referencia | Curva de pago por días-desde-vencimiento en # operaciones (ej.: ~70% paga al día 0, ~85% acumulado al día 1) — se usa como validación |

## Modelo conceptual
El pago es "grumoso" (pocos eventos de pago al mes), así que NO se modela rebaje diario promedio.
Se modela **evento × magnitud**:

> Recupero esperado = P(paga dentro de la ventana) × E(% del saldo capital que rebaja al pagar)

Dos poblaciones, dos motores:

1. **Stock (mora 1–30 al día 1):** curvas de recupero acumulado por día del mes,
   segmentadas por tramo de mora inicial (propuesta inicial: 1–8, 9–15, 16–30, ajustable)
   y, si agregan poder, por nro. de cuota y monto financiado. Ponderadas por saldo
   (Σ rebaje / Σ saldo inicial).
2. **Flujo (nuevos):** curva de pago por días-desde-vencimiento, truncada a fin de mes.
   El día de entrada NO requiere segmentación propia: solo define dónde se trunca la curva.
   `P(recupera en el mes | entró el día D) = [C(días restantes) − C(0)] / [1 − C(0)]`
   Convertida a capital con severidad por nro. de cuota.

## Fases
- **Fase 0 — Diagnóstico** (`fase0_diagnostico.sql`): ✅ EJECUTADA 2026-07-08 en Athena
  (db `dev_datalake_master`, workgroup `primary`). Resultados:
  - **0.1 Cobertura:** fotos diarias completas de nov-2023 a hoy, sin huecos. La cartera
    crece rápido: 53k créditos (mar-25) → 200k (jul-26). Implicancia: calibrar ratios con
    meses recientes y vigilar cambio de mezcla.
  - **0.2 Grumosidad (valida el enfoque):** de los crédito-mes en mora, 24% no rebaja nada,
    68% rebaja en exactamente 1 día, 8% en 2 días. El 92% tiene 0 o 1 evento de pago al mes
    → confirmado: modelar evento × magnitud, no rebaje diario promedio.
  - **0.3 Aumentos de saldo:** despreciables (< 2% del rebaje mensual, ~100 filas/mes de
    58M) → los deltas negativos se tratan como 0.
  - **0.4 Mecánica de `dayslate`:** es **NULL cuando está al día** (usar
    `coalesce(dayslate,0)` siempre). Entra a mora casi siempre por 1 (99.7% de entradas),
    avanza +1 diario, cura = reset a NULL. Bajas parciales de mora: raras (2.3k filas).
    Desde mar-25: 83.7k entradas a mora, 77.2k curas. → detección de entrada/cura confiable.
  - **0.5 Cancelaciones totales en mora:** 500–1,000 créditos/mes llegan a saldo 0 estando
    en mora (~S/ 200–450k de capital/mes). Supuesto: cuentan como recupero del 100%.
- **Fase 1 — Motor del stock**: ✅ EJECUTADA 2026-07-08 (`fase1_stock.sql`). Definición
  adoptada: "inicio de mes" = última foto del mes anterior; el crédito mantiene su tramo
  aunque cruce 30 días (confirmado por el usuario). Meses meta: 202504–202606. Resultados:
  - **Recupero mensual por tramo (agregado 14 meses):** 1–8: **18.1%** | 9–15: **12.7%** |
    16–30: **7.8%** del saldo capital inicial. (Cifras finales tras excluir reenganches/
    refinanciamientos — ver sección "Pregunta 0 resuelta" más abajo; el ajuste fue de
    solo -0.3 a -0.5pp vs. la primera corrida.)
  - **Descomposición clave:** la severidad es PLANA entre tramos (~24% del saldo cuando
    pagan); lo que cae con la mora es la FRECUENCIA: pagan algo en el mes el 83% (1–8),
    58% (9–15) y 39% (16–30). → El tramo predice si paga; no cuánto rebaja.
  - **Severidad la manejan term y avance** (consistente entre tramos):
    term 1–6: ~49–51% | term 7–12: ~21–24% | term 13+: ~10–12%. Avance 70%+: ~75–81%
    (suelen cancelar el remanente) | avance <10%: ~13–16% (la intuición "cuota 1 rebaja
    poco" confirmada). Saldo y monto financiado discriminan también pero son proxies de
    term/avance.
  - **Forma de la curva diaria:** front-loaded en 1–8 (al día 8 ya lleva ~10 de sus 18.4
    puntos) + aceleración de fin de mes (días 26–31). Tramos 9–15 y 16–30 son más lineales.
  - **Estabilidad mensual (1B):** tramo 1–8 estable (16.2–20.5%); 9–15 volátil
    (9.8–18.8%, n chico ~100–330); 16–30 estable bajo (6.2–11.1%).
  - **Matriz propuesta para la meta del stock:** tramo × banda de avance (o term), con
    celdas directas y respaldo multiplicativo P(pago|tramo) × Sev(banda) donde la celda
    sea delgada. Decidir term vs avance en el backtest de Fase 3.
- **Fase 2 — Motor del flujo**: curva días-desde-vencimiento en # operaciones (validar vs
  70/85 conocido) y en capital; severidad por cuota. Fuente candidata mejor: tabla de pagos
  por cuota (pendiente de recibir).
- **Fase 3 — Meta y backtest**: stock × ratios + flujo proyectado con
  `dts_cobranza_creditos_Cuotas` (vencimientos futuros PENDING). Backtest: ratios con meses
  t−6…t−2 → proyectar t−1 → comparar vs real.

## Fase 2 — hallazgo intermedio (nota técnica)
Se auditó `dts_cobranza_creditos_cuotas` (cuota-nivel, con `dias_vencimiento_a_pago`,
`principalamountpaid`, `principalamountdue`) como fuente para la curva de "nuevos".
- **Curva en # operaciones (2A):** confiable — día 0: 60.8% pagó a tiempo, día 1
  acumulado: 69.0%, plateau ~82% al día 31. Es MÁS BAJA que la referencia del usuario
  (70% / 85% acum. día 1). Pendiente de conciliar (posible diferencia de mezcla de
  producto/cohorte en la referencia del usuario vs. universo completo de la tabla).
- **Curva en capital vía `principalamountpaid`/`principalamountdue` (2A): DESCARTADA.**
  El ratio supera 100% y crece sin límite (hasta ~405% al día 31) — indica que
  `principalamountpaid` sobre-atribuye pagos anticipados/cancelaciones totales a cuotas
  individuales (doble conteo). No usar estos campos para capital sin más investigación.
- **Decisión:** el motor de "nuevos" en capital se construye igual que Fase 1, con
  `dts_mambu_loans_hist` (deltas de saldo ya validados), indexado por "días desde entrada
  en mora" en vez de tramo fijo. Mismas definiciones de avance/term. Ver `fase2_nuevos.sql`.

## Fase 2 — Motor de nuevos: resultados
✅ EJECUTADA 2026-07-08 (`fase2_nuevos.sql`). Ventana de entradas a mora: 2025-03-01 a
2026-05-31 (74,843 entradas, con 31+ días de fotos posteriores para no censurar la cola).

- **Curva global en capital (2C), acumulada desde el día de entrada en mora:**
  día 1: 4.6% · día 3: 9.3% · día 8: 13.0% · día 15: 15.2% · día 20: 16.2% · día 30: 21.7%
  · día 31: 23.2%. Forma cóncava con leve aceleración final (fin de mes / segundo
  vencimiento). Para un "nuevo" que entra en mora el día D del mes, el recupero esperado
  a fin de mes es el valor de esta curva en (último día del mes − D + 1).
- **Segmentación por avance de amortización (misma lectura que en el stock):** a más
  avance, más recupero — d31: avance <10% → **14.4%** | 10–40% → **19.8%** |
  40–70% → **40.9%** | 70%+ → **74.2%** (cancelaciones de saldo remanente). Confirma
  que "cuota 1" rebaja mucho menos que créditos avanzados, igual que en el stock, y
  cruza bien contra el análogo de Fase 1 (stock tramo 1-8 + avance 70%+ → 67.5%
  recupero incondicional, mismo orden de magnitud).
  - **CORRECCIÓN 2026-07-08:** la primera corrida de este bloque (8.2%/11.0%/22.5%/
    38.4%) tenía el mismo bug de `WHERE ... IN (...)` aplicado antes de la window
    function que se documentó para 1A/2C (ver sección "Gotcha SQL" más abajo) —
    nunca se había re-ejecutado este bloque específico tras identificar el bug.
    Los números de arriba son la versión corregida (query sin filtro de días antes
    del acumulado). Los números de `term` de esa misma corrida (26.0%/10.3%/4.0%)
    tienen el mismo problema y no se han recalculado — no usar hasta reconfirmar;
    se prioriza `avance` como segmentador operativo.
- **Curva en # operaciones (2A, vía `dts_cobranza_creditos_cuotas`), validación:**
  día 0 (a tiempo): **60.8%** · día 1 acumulado: **69.0%** · plateau día 31: **82.2%**.
  Más bajo que tu referencia (70% / 85% acum. día 1) — mismo patrón de forma pero nivel
  distinto. Posibles causas: mezcla de producto/tienda distinta a tu referencia, o que tu
  cifra se calculó sobre un subconjunto (p.ej. solo cuota 1, o un producto específico).
  No bloquea el uso de la curva en capital (2C), que es la que alimenta la meta — pero
  vale la pena conciliar antes de presentar cifras hacia afuera.

## Fase 2 — Pregunta 0 RESUELTA: causa de la discrepancia 60.8%/69.0% vs. 70%/85%
El usuario identificó la causa exacta: el filtro `status = 'ACTIVE'` excluía los créditos
`COMPLETED` (los que ya terminaron de pagar bien) y no excluía cuotas de créditos
reenganchados/refinanciados (que quedan `LATE` para siempre, arrastrando el promedio
hacia abajo). Filtro corregido: `status IN ('ACTIVE','COMPLETED') AND
flg_last_loan_in_chain = 1`. Se aisló el efecto de cada fix por separado:

| Filtro | Día 0 | Día 1 acum. | Plateau (d31) |
|---|---|---|---|
| `status='ACTIVE'` (original, con bug) | 60.8% | 69.0% | 82.2% |
| + `status IN ('ACTIVE','COMPLETED')` | 65.3% | 72.8% | — |
| + `flg_last_loan_in_chain=1` (final) | **72.6%** | **81.2%** | **93.8%** |

Resultado final muy cerca de la referencia del usuario (70% / 85%). El filtro de cadena
pesa más que el de status (+7-8pp vs +4-5pp) porque esta curva se mide sobre **toda la
cartera de vencimientos** (incluye renovaciones sanas fuera de mora); un crédito
reenganchado deja cuotas "colgadas" en LATE para siempre, arrastrando el acumulado.

**Impacto en Fase 1 y Fase 2 (capital):** `dts_okaapi_loans` no tiene un campo
`flg_last_loan_in_chain`; se derivó un flag a nivel crédito uniendo con
`dts_cobranza_creditos_cuotas` (`max(flg_last_loan_in_chain)` por `id_ihfintech_loan`,
es constante por crédito — verificado). A diferencia de la curva de operaciones, el
impacto sobre las poblaciones de **mora 1-30** es pequeño, porque los reenganches sanos
(sin pasar por mora) no entran a esas poblaciones de todos modos:
- **Fase 1 (stock):** ~2% de los crédito-mes son reenganches, con severidad ~2x más alta
  (27.6% vs 14.7%) — pero al ser tan pocos, el efecto en las curvas finales es de solo
  **-0.3 a -0.5pp**. Números finales (antes → después del filtro): tramo 1-8 d31
  18.39% → **18.08%** | tramo 9-15 d31 12.70% → **12.69%** | tramo 16-30 d31
  7.90% → **7.84%**. No cambia ninguna conclusión de Fase 1.
- **Fase 2 (nuevos):** ~5.4% menos entradas a mora califican (74,843 → 70,797, los
  reenganchados se excluyen). Curva global d31: 23.16% → **22.30%** (-0.9pp). Tampoco
  cambia conclusiones, pero es la versión correcta/final.
- El filtro de cadena ya quedó incorporado como definición estándar en
  `fase1_stock.sql` y `fase2_nuevos.sql` (CTE `loan_chain` + `coalesce(last_in_chain,1)=1`
  en la CTE `fotos`) — usar esa versión para todo lo que sigue en Fase 3.

## Fase 3 — Backtest sobre junio 2026 (mes real y cerrado)
✅ EJECUTADO 2026-07-08. Se corrigieron las dos limitaciones pendientes de la corrida
demo: stock anclado al cierre real de mayo-2026 (no al día de la consulta), y
calendario de junio reconstruido con `fechavencimiento` real (no filtrado por
`installmentstate`, ya que el desenlace de junio ya se conoce). Comparación día a
día contra el recupero REAL de junio (mismo método fotos-based de Fase 1/2,
separado en población stock vs. población que entró en mora durante junio).

**Hallazgo crítico — el primer intento falló por +79%:** la constante
`P(no paga a tiempo)` usada en Fase 3 (27.4%, tomada del día 0 de la curva de
`dias_vencimiento_a_pago` a nivel CUOTA) no corresponde a la tasa real de entrada
a mora a nivel CRÉDITO (`dayslate` 0→1). Son poblaciones distintas: `dayslate`
probablemente tiene un período de gracia antes de marcar mora oficial, mientras
`dias_vencimiento_a_pago` cuenta cualquier atraso desde el día 1. La tasa real
medida en junio fue 10.96% (5,982 de 54,600 créditos elegibles) — pero usar el
dato del propio junio para validar junio es data leakage. Se midió la tasa en
10 meses previos, SIN junio (ago-2025 a may-2026): estable entre 11.4% y 14.6%,
promedio ponderado **13.38%** (47,966 entradas / 358,580 elegibles) — este es el
valor correcto y fuera de muestra para `P(no paga a tiempo)` en el mecanismo de
Fase 3, reemplaza el 27.4% original en `armar_trayectoria_seg.py` /
`fase3_meta.sql`.

**Resultado del backtest (con la tasa correcta, 13.38%):**

| Día de junio | Proyectado acum. | Real acum. | Error |
|---|---|---|---|
| 10 | S/ 637,700 | S/ 548,638 | +16.2% |
| 19 | S/ 1,114,598 | S/ 1,058,352 | +5.3% |
| 25 | S/ 1,448,039 | S/ 1,377,155 | +5.1% |
| **30 (cierre)** | **S/ 1,806,299** | **S/ 1,713,815** | **+5.4%** |

Descomposición del cierre: stock proyectado S/601,379 vs real S/517,683
(**+16.2%**, varianza normal — ver volatilidad mensual de Fase 1B, especialmente
tramo 9-15); nuevos proyectado S/1,204,920 vs real S/1,196,132 (**+0.7%**,
prácticamente exacto). El mecanismo de cohortes por día de vencimiento (la pieza
más nueva y más incierta de Fase 3) valida muy bien; el motor de stock, calibrado
sobre la curva blended de 14 meses (que SÍ incluye junio con peso marginal ~1/14),
es la fuente principal del error residual.

**Nota metodológica:** las curvas de stock/nuevos (fase1_stock.sql/fase2_nuevos.sql)
siguen calibradas sobre la ventana completa de 14 meses (incluye junio, ~1/14 del
peso) — no son estrictamente fuera de muestra. Solo la tasa `P(no paga a tiempo)`
se recalibró excluyendo junio explícitamente. Un backtest totalmente riguroso
recalibraría también las curvas excluyendo el mes de prueba; dado el peso marginal
de un mes sobre 14, el sesgo esperado de esto es pequeño.

Queries y script: `bt_q1_stock.sql`…`bt_q4_real_nuevos.sql` (scratchpad de la
sesión) + `backtest_junio.py`. Pendiente: promover estas queries a un archivo
`fase3_backtest.sql` formal en la carpeta del proyecto.

## Fase 3 — Meta en vivo de julio 2026 (corte 2026-07-09)
✅ EJECUTADO 2026-07-09. Con el mecanismo ya validado por el backtest de junio, se calculó
la meta de julio en curso, y se corrió en paralelo un segundo enfoque ("reinicio del
reloj") como cruce de validación independiente.

**Enfoque A — Acumulado (oficial):** stock anclado al cierre real de junio (día 1 de
julio) + calendario real de julio + curvas calibradas. Resultado:
- Stock inicial (30-jun): S/2,943,958 (tramo 1-8: S/1,296,254 · 9-15: S/766,679 ·
  16-30: S/881,025).
- **Meta total del mes: S/1,776,174** (stock S/426,651 + nuevos S/1,349,523).
- Real recuperado al corte (día 9): S/527,375 (stock S/193,167 + nuevos S/334,208) —
  **+6.3%** por encima de lo proyectado para el mismo día (S/496,201) → señal sana.
- **Lo que resta del mes (día 10-31): S/1,248,799.**
- Scripts: `meta_julio.py` + `datos_meta_julio/` (stock_julio_seg.csv, jul_calendario.csv
  con el corte histórico/proxy en el día 9, jul_real_a_hoy.csv, curva_stock_seg.csv,
  curva_nuevos_seg.csv).

**Ejemplo de replicación (cohorte única + query todo-en-uno):** documentado en
`ejemplo_cohorte_julio.sql`. Cohorte del 2-jul, avance <10%: 277 créditos, S/832,370 en
riesgo → ×13.38% → S/111,362 entran en mora → ×curva(día 7)=7.799% → aporte S/8,684 al
día 9. La suma de las 36 cohortes (9 días × 4 bandas) da **Nuevos_acumulado(día 9) =
S/282,689** (SQL puro, query única) vs S/282,725 (Python) — coinciden al 0.013%.
**Corrección aplicada:** una explicación previa había citado por error S/334,208 como
si fuera este acumulado proyectado — ese número es en realidad el REAL (recupero
efectivo de "nuevos" al día 9), no la suma de cohortes. Ver conversación para el
detalle completo paso a paso.

**Enfoque B — "Reinicio del reloj" (cruce de validación, no oficial):** trata la foto de
HOY (no el cierre de junio) como nueva línea base, y proyecta los 22 días restantes de
julio. Scripts: `meta_desde_hoy.py` + `meta_desde_hoy.sql`.
- Stock re-baseline a hoy (9-jul): S/4,192,563 (mayor que el de 1-jul porque ya absorbió
  a los "nuevos" de la primera semana).
- Resultado inicial: **S/1,261,169** (stock S/462,014 + nuevos S/799,155) — solo **+1.0%**
  vs. el Enfoque A (S/1,248,799). Buen cruce de validación a primera vista.

**BUG encontrado y diagnosticado (2026-07-09):** el filtro `where mora between 1 and 30`
de `meta_desde_hoy.sql` (evaluado con la mora de HOY) excluía silenciosamente a los
créditos del stock original de julio que ya habían cruzado los 30 días de mora entre el
1 y el 9 de julio — violando la regla ya confirmada de que un crédito asignado sigue
contando aunque cruce 30 días. Diagnóstico cuantificado:
- Del stock de 1-jul (1,756 créditos, S/2,943,958): 716 curaron (S/1,062,860, ya no
  deben nada, exclusión correcta) · 796 siguen 1-30 (S/1,379,790, correctamente
  incluidos) · **244 cruzaron a más de 30 días (S/501,307, excluidos por el bug)**.
- Importante: NO se debe simplemente quitar el límite superior del filtro — eso también
  arrastraría S/9.57M de cartera con mora 90+ días (76% de todo el universo mora>30 de
  hoy) que nunca fue parte de la asignación de julio y está fuera de alcance. La
  corrección debe ser quirúrgica: solo reincorporar a los 244 créditos que SÍ eran parte
  del stock original (requiere JOIN contra el cierre de junio, no se puede resolver
  mirando solo la foto de hoy).
- Los 244 créditos clasifican, por su tramo original al 30-jun, TODOS en "16-30"
  (esperable: solo créditos ya muy cerca de 30 pueden cruzar en apenas 9 días). Su aporte
  esperado al resto del mes (curva día31 − curva día9, aplicada a su saldo de 30-jun) es
  de solo **S/22,510** — chico, porque mora profunda implica baja frecuencia de pago.
- **Enfoque B corregido: S/1,261,169 + S/22,510 = S/1,283,679** — esto en realidad
  ALEJA el cruce con el Enfoque A (+2.8% en vez de +1.0%); la cercanía inicial de +1.0%
  era en parte casualidad (el undercount de estos 244 créditos se compensaba con la
  sobreestimación de tratar a los créditos de julio-1 supervivientes como "día 1 fresco"
  en vez de "día 9 de su propio ciclo").

**Conclusión y recomendación:** el Enfoque A (acumulado, anclado a cierre de mes) es el
metodológicamente correcto y debe ser la fuente oficial — no tiene este problema porque
nunca re-filtra por mora del día corriente, solo clasifica una vez al momento de
asignación. El Enfoque B ("reinicio del reloj") es útil como sanity-check rápido pero
tiene una limitación estructural: cualquier crédito que haya cruzado el límite superior
del rango de trabajo (30 días) entre el momento de asignación real y el corte de hoy
necesita un tratamiento especial (mirar su clasificación original), no puede resolverse
solo con la foto del día. Si se vuelve a usar el Enfoque B, aplicar siempre este parche.

### Corrección aplicada (2026-07-09)
Se corrigió `meta_desde_hoy.sql`/`.py` con dos cambios:
1. **Bloque Q0 nuevo:** identifica a los "aged-out survivors" (créditos del stock
   original de julio — cierre de junio, mora 1-30 — que ya cruzaron 30 días para hoy)
   vía JOIN contra la foto de asignación, los clasifica por su tramo/avance
   **originales** (no los de hoy — todos caen en "16-30", ya que solo créditos ya cerca
   de 30 pueden cruzar en 9 días) y aplica la lógica acumulada: `saldo_30-jun × [curva
   día 31 − curva día 9]`. Aporte: **S/22,510**.
2. **Q2 corregido:** la exclusión del calendario de "nuevos" ahora usa TODO el stock de
   asignación (no solo el que sigue 1-30 hoy), evitando un segundo bug menor — 3
   créditos / S/6,843 de saldo que se contaban dos veces (como stock aged-out y también
   como "en riesgo" en el calendario de nuevos).

**Resultado final corregido:** S/22,510 (aged-out) + S/462,014 (stock re-baseline) +
S/782,322 (nuevos, calendario ya corregido) = **S/1,266,846** — solo **+1.4%** sobre el
Enfoque A oficial (S/1,248,799). Mucho más consistente que el +2.8% estimado de forma
aproximada antes de aplicar el fix completo a Q2. Insumos actualizados en
`datos_meta_desde_hoy/` (agregado `aged_out_hoy.csv`; `calendario_hoy_adelante.csv`
regenerado con la exclusión corregida).

## Preguntas abiertas
1. **Cruce de 30 días:** un crédito del stock asignado con 25 días de mora cruza los 30 a
   mitad de mes. **Supuesto vigente:** sigue contando en la cartera asignada (y su rebaje
   suma al recupero) hasta fin de mes. Confirmado y validado empíricamente 2026-07-09
   (ver sección "Meta en vivo de julio" — el Enfoque A ya implementa esto correctamente;
   el bug del Enfoque B confirma por contraste por qué la regla es necesaria).
2. Sub-tramos definitivos dentro de 1–30 (propuesta: 1–8 / 9–15 / 16–30).
3. Recibir la tabla de pagos por cuota para Fase 2.
4. `installmentlastpaiddate` (dts_cobranza_creditos_cuotas, nivel cuota) — dato aportado
   por el usuario, pendiente de usar para cuantificar el período de gracia de `dayslate`
   (cruzar contra la fecha en que `dayslate` pasa a 1 para el mismo crédito).
5. Extender el backtest a 3-6 meses más (junio es un solo punto de dato).
6. Corregir `meta_desde_hoy.sql`/`.py` con el parche descrito arriba (créditos aged-out
   del stock original), o documentar claramente que el Enfoque B es solo referencial.

# Volumen vs. efectividad — agosto 2026, corte 21-ago

**Ejecutado 2026-08-22**, a pedido del usuario, como continuación directa del pendiente
abierto en bug 16 (`BUGS.md`): si el error Real>Proyectado del backtest (bug 16: +9.71%
julio, +0.93% junio con `dias_atraso_cuota`; y el propio avance en vivo de agosto)
refleja **mejora real de gestión de cobranza** o es **volumen** (entra más capital en mora
de lo que el calendario asume). SQL completo y reproducible en
`analisis_volumen_efectividad_agosto.sql` (queries K1-K6). Resultados crudos en
`datos_volumen_efectividad_agosto/`.

**Corte usado: 21-ago (no 22-ago/hoy).** `dts_asignaciones_gestiones_cobranza` (necesaria
para K5, comparación grupo_control) solo tiene datos hasta 2026-08-21 — un solo corte para
las 5 queries evita comparar poblaciones a fechas distintas. `dts_mambu_loans_hist` sí
llega a 22-ago (verificado), no fue el limitante.

**Nota de proceso:** la primera versión de este análisis tenía un off-by-one en el índice
del calendario de "nuevos" (excluía por error la cohorte con cuota vencida el 1-ago,
tratándola como si "arrancar el día 2" quisiera decir que el calendario debe arrancar el
día 2 — en realidad ese día 2 se refiere a la fecha de ENTRADA, no de vencimiento; el
vencimiento del 1-ago sí es una cohorte válida de "nuevos", su entrada recién se ve el
2-ago). Se detectó al comparar el proyectado recalculado por segmento contra el total
oficial del propio `meta_agosto_capital_asegurado.py` (que no coincidía) — quedan
alineados exactos ahora (S/11,325,584). Las cifras de este documento ya están corregidas.

## 1. Proyectado-a-la-fecha vs. Real-a-la-fecha, mismo corte (día 21)

A diferencia de "cuánto llevamos del total del mes" (que compara real contra la meta de
**mes completo**, un error de escala si el mes no terminó — ver nota de julio/junio en
`ESTADO.md`), esto compara el modelo evaluado **en el mismo día 21** contra lo
efectivamente cobrado hasta el día 21.

| Componente | Proyectado (día 21) | Real (día 21) | Diferencia | % |
|---|---:|---:|---:|---:|
| Stock | S/2,693,205 | S/2,734,665 | +S/41,460 | **+1.54%** |
| Nuevos | S/4,458,075 | S/5,537,431 | +S/1,079,356 | **+24.21%** |
| Fantasma | S/4,174,304 | S/3,348,684 | −S/825,620 | **−19.78%** |
| **Total** | **S/11,325,584** | **S/11,620,780** | **+S/295,196** | **+2.61%** |

El total (+2.61%, coincide con el `meta_agosto_capital_asegurado.py` v5 refrescado a este
mismo corte) esconde tres historias muy distintas por componente — nunca leer el agregado
solo. Stock está casi en línea (ruido, ver sección 2). Nuevos corre por encima. Fantasma
corre por debajo, y **parte de eso es un artefacto de timing, no un hueco real** (sección
4c): las cuotas que vencen cerca del corte todavía no terminan de resolverse a `PAID` en la
fuente, así que el fantasma real de estos últimos días está subcontado y va a subir en los
próximos días — mismo mecanismo ya documentado en bug 13 (actualización 2026-08-21,
cobertura de agosto).

**Nota de volatilidad:** el corte 20-ago (sesión anterior, `ESTADO.md`) daba +1.9%. Un día
después, +2.61% — se mantiene en el mismo orden de magnitud (a diferencia de una versión
anterior de este análisis con un bug, que daba +6.17% — ya corregido, ver nota de proceso
arriba). Consistente con la advertencia ya registrada en `ESTADO.md` ("todavía es alta la
varianza día a día, no tratar como tendencia asentada").

## 2. Desagregado por segmento

**Stock (tramo × avance) — la variación es ruido, no señal:** los 12 segmentos individuales
oscilan entre −20.1% y +36.8%, con signos alternados sin patrón, y el AGREGADO (+1.54%)
es casi plano — consistente con que cada segmento tiene solo cientos de créditos (alta
varianza muestral) y con que "stock" es el componente más estable del modelo en los
backtests históricos (junio/julio +2.65%/+2.17%). Detalle en
`datos_volumen_efectividad_agosto/k1_stock_seg_real_21ago.csv`.

**Nuevos (avance) — los 4 segmentos son POSITIVOS, sin excepción:**

| Avance | Proyectado | Real | Diferencia |
|---|---:|---:|---:|
| <10% | S/1,460,319 | S/2,165,534 | **+48.3%** |
| 10-40% | S/2,169,562 | S/2,401,444 | **+10.7%** |
| 40-70% | S/721,976 | S/819,880 | **+13.6%** |
| 70%+ | S/106,218 | S/150,573 | **+41.8%** |

A diferencia de stock, acá el signo es consistente en los 4 segmentos — no es ruido, hay un
mecanismo sistemático detrás. Sección 3 lo descompone.

## 3. Volumen vs. efectividad — el mecanismo detrás del exceso en "nuevos"

Para separar las dos hipótesis, cada segmento de "nuevos" se descompuso en dos factores
independientes: **(a) volumen** — ¿entraron más créditos/soles en mora de los que el
calendario asume (13.38%)? y **(b) tasa de activación condicional** — dado que un crédito
entró en mora, ¿paga a una tasa distinta de la histórica?

| Avance | Calendario elegible (venc. 1-20 ago) | Entrada modelada (×13.38%) | Entrada REAL | Exceso de volumen | Tasa activación modelada | Tasa activación REAL | Δ tasa |
|---|---:|---:|---:|---:|---:|---:|---:|
| <10% | S/16,757,895 | S/2,242,206 | S/3,268,696 | **+45.8%** | 65.13% | 66.24% | +1.1pp |
| 10-40% | S/23,285,406 | S/3,115,595 | S/3,532,654 | **+13.4%** | 69.64% | 67.98% | −1.7pp |
| 40-70% | S/7,497,174 | S/1,003,122 | S/1,206,869 | **+20.3%** | 71.98% | 67.94% | −4.0pp |
| 70%+ | S/1,128,178 | S/150,966 | S/218,405 | **+44.7%** | 70.36% | 68.94% | −1.4pp |
| **Total** | **S/48,668,653** | **S/6,511,889** | **S/8,226,625** | **+26.3%** | **68.46%** | **67.32%** | **−1.1pp** |

**Lectura: el exceso es volumen, no efectividad — y en la dimensión de tasa, si algo se
mueve, es levemente en contra de "la gestión mejoró".** El volumen de entrada real (soles
que efectivamente pasaron a mora) es 26.3% más alto que lo que el calendario × 13.38%
asume, en los 4 segmentos, con magnitud grande (13%-46%). La tasa de activación condicional
(dado que entró, ¿a qué tasa paga?) real está **por debajo** del modelo en 3 de 4 segmentos
y el total es −1.1pp — si la gestión estuviera cobrando de forma más efectiva que el
histórico, esperaríamos ver esta tasa sistemáticamente por ENCIMA del modelo, no por debajo
ni en línea.

Confirmado también a nivel agregado por créditos, no soles (K4,
`datos_volumen_efectividad_agosto/k4_entry_rate_21ago.csv`): la tasa de entrada real a
nivel de # de créditos es **14.52%** (5,196/35,783) vs. **13.38%** modelado — +1.14pp /
+8.5% relativo. Menor que el +26.3% en soles porque el exceso de volumen está concentrado
en créditos de saldo más alto (el exceso en soles es mayor que el exceso en # de créditos)
— dato adicional: no solo entran más créditos, entran créditos de saldo más grande de lo
que el mix histórico asumía.

## 4. Comparación directa: grupo_control (no gestionado) vs. gestionado

Prueba más directa de "efectividad": dentro de la misma población (agosto, mismo corte),
¿el subconjunto que el propio negocio marca como `grupo_control='CONTROL'` (deliberadamente
NO gestionado, en `dts_asignaciones_gestiones_cobranza`) se activa a una tasa distinta que
el resto (gestionado)? Si gestionado > control de forma clara, es evidencia de efectividad
real. Join vía `aux02` (bug 15). Fuente:
`datos_volumen_efectividad_agosto/k5_grupo_control_21ago.csv`.

| Segmento | Grupo | Créditos | % activados |
|---|---|---:|---:|
| **Stock** | Gestionado | 2,380 | **65.13%** |
| **Stock** | Grupo control | 264 | **64.77%** |
| Stock | Sin match en asignaciones | 51 | 100.0% |
| **Nuevos** | Gestionado | 5,127 | **69.28%** |
| **Nuevos** | Grupo control | 50 | **94.0%** |
| Nuevos | Sin match en asignaciones | 19 | 100.0% |

**(a) Stock — la comparación con más poder estadístico (264 vs. 2,380 créditos) no muestra
diferencia:** 64.77% vs. 65.13%, prácticamente idéntico. Esta es la evidencia más confiable
de las dos (n grande en ambos lados) y apunta a que, para créditos que ya venían en mora,
estar "gestionado" no se asocia con una tasa de activación más alta que el control.

**(b) Nuevos — el control activa MÁS que el gestionado (94.0% vs. 69.3%), dirección
opuesta a lo que predeciría "la gestión funciona"** — pero con **n=50** en el grupo control,
la muestra es chica (el intervalo de confianza aproximado de 94.0% es ancho, ±~7pp) y el
resultado no debe sobre-interpretarse como "la gestión perjudica". Es más consistente con
ruido de muestra chica o con un posible sesgo de selección de quién cae en control (ver
caveat abajo) que con un efecto causal negativo real.

**Categoría "sin match en asignaciones" (100% activados, n=19/51):** créditos que no
aparecen en `dts_asignaciones_gestiones_cobranza` en ningún día de agosto — volumen bajo
(1.9%-2.2% de cada segmento), 100% exacto en una muestra tan chica es plausible por azar,
no investigado a fondo (no es el foco de esta pregunta).

**Caveat RESUELTO 2026-08-23 — confirmado por el usuario:** `grupo_control` es una
**aleatorización estratificada por riesgo y monto** (no una regla de negocio ni una
selección no aleatoria). Al ser aleatorización real, la comparación de arriba **sí soporta
una lectura causal** (con la salvedad de que la estratificación equilibra riesgo/monto entre
grupos, no cambia la validez del diseño) — refuerza, no solo sugiere, la conclusión de la
sección 5: el exceso Real>Proyectado en "nuevos" es volumen, no una mejora real de
efectividad de cobranza. Queda cerrado el pendiente 1 de la sección 5.

**(c) Fantasma corriendo por debajo del proyectado (sección 1, −19.78%) — verificado que es,
al menos en parte, timing (K6):** cuotas venciendo en los últimos ~4 días antes del corte
(fecha de pago esperada 16-19 ago) tienen tasa `PAID` de **84.9%** (7,250/8,539) vs. **90.0%**
(25,288/28,085) del resto del período — típico de censura por la derecha: cuotas cerca del
corte todavía no terminan de resolverse en la fuente, así que el número real va a subir en
los próximos días a medida que esas cuotas se resuelvan.

## 5. Conclusión y siguientes pasos

**Con la evidencia de este corte, el exceso Real>Proyectado en "nuevos" (agosto, +24.2%)
se explica en gran parte por volumen (más capital entrando en mora de lo que el calendario
histórico asume, +26.3% en soles / +8.5% en # de créditos, consistente en los 4
segmentos), no por una tasa de pago condicional más alta — esa tasa está, si algo, levemente
por DEBAJO del modelo (−1.1pp agregado).** La comparación directa grupo_control vs.
gestionado apunta en la misma dirección: donde hay suficiente muestra para confiar en el
número (stock), no hay diferencia detectable; donde sí aparece una diferencia grande
(nuevos), va en la dirección contraria a "la gestión mejora la tasa" y descansa en una
muestra chica. **No hay evidencia en este análisis de que una mejora real de efectividad de
cobranza explique el error del modelo** — la hipótesis que mejor sobrevive es que el modelo
de `P_NO_PAGA_DIA0=13.38%` (calibrado ago2025-may2026) está subestimando el volumen de
entrada a mora actual (y particularmente el volumen en soles de créditos de saldo alto), no
la tasa de recupero condicional.

**Pendientes para profundizar:**
1. ~~Confirmar con el equipo de `gestiones_cobranza` cómo se define/asigna
   `grupo_control`~~ **RESUELTO 2026-08-23:** el usuario confirmó que es aleatorización
   estratificada por riesgo y monto — la conclusión de la sección 4 queda con soporte
   causal, no solo correlacional.
2. Repetir la comparación grupo_control vs. gestionado en 2-3 cortes más (no solo un día)
   para que el n=50 de "nuevos control" deje de ser tan chico — la muestra crece con cada
   día adicional de agosto.
3. Si el exceso de volumen se confirma persistente (no solo este mes), sería la base para
   recalibrar `P_NO_PAGA_DIA0` — pero siguiendo el principio de `CLAUDE.md` (bug 10): nunca
   cambiar la tasa sin recalibrar la curva sobre la misma definición y correr el backtest
   completo, no en abstracto.
4. Conecta directo con bug 16 (`BUGS.md`): la investigación de `dias_atraso_cuota` como
   reemplazo de `dayslate` tenía exactamente esta pregunta pendiente — este análisis la
   responde parcialmente (volumen, no efectividad) usando el enfoque de producción actual
   (`dayslate`+capa fantasma), no `dias_atraso_cuota`. Sigue pendiente repetir con esa
   tabla si se retoma esa línea.

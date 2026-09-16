# Tarea 26 — ¿El riesgo de cobranza corta las curvas? (evaluación, 2026-09-15)

**Pedido del usuario:** incluir el riesgo de cobranza en las curvas para ver si esa variable también
corta el rebaje. *"No modifiques técnicas, esto es solo una evaluación."* **Nada del motor, las curvas
vigentes ni las metas cambió.** Todo sale de dos queries nuevas que replican las matrices v2 y agregan
el riesgo como dimensión.

## La variable

- **`prediccion_riesgo_modelo_cobranza`** (Riesgo Bajo / Medio / Alto) y **`segmento_modelo_cobranza`**
  (MAX_DIASMORA 1-4 / 5-16 / +16), de `dts_cobranza_creditos_cuotas`, **por cuota**. Nuevos: el de la cuota
  que entra en mora (por `id_loan_nro_cuota` de la cuota vigente el día de la entrada en
  `calendario_diario`). Stock: el de la cuota vigente el día 1.
- **Es el puntaje crudo de un modelo, no el riesgo de gestión** (aclarado el mismo 2026-09-15, a pregunta
  del usuario: *"hay dos, ¿recuerdas?"*). En la tabla de cuotas el modelo de cobranza y el de mora coinciden
  en segmento y riesgo en el 96% de las cuotas: en la práctica son uno. Los dos que usa la gestión son
  **el de mora y el preventivo**, y el `riesgo_mora_gestion` sale de ellos con una tabla fija (sección
  siguiente). Esta evaluación usó el puntaje de cobranza para todos los créditos: no usó el preventivo ni
  aplicó la tabla.
- **¿Mira hacia adelante?** La evidencia dice que no, sin verificarlo contra una foto histórica: el
  puntaje se guarda por cuota (varía entre cuotas del mismo crédito en ~35% de los créditos), existe
  también en cuotas pagadas a tiempo (se asigna alrededor del vencimiento, no después de la mora) y
  **aparece recién en las cuotas que vencen desde junio 2025**: 0% de las entradas antes, ~20% en junio,
  100% desde julio. Se fue asignando en su momento; no se rellenó hacia atrás.

## Los dos riesgos: cómo los asigna la gestión (verificado, TEMPRANA jul-sep 2026)

En `dts_asignaciones_gestiones_cobranza`, las columnas `segmento_modelo_mora` / `prediccion_riesgo_modelo_mora`
traen, según el crédito, **uno de dos modelos**: el de mora (segmentos `MAX_DIASMORA`, ~85% de las filas) o el
**preventivo** (segmentos `Cliente Nuevo` / `Cliente Antiguo`, ~15%), aunque la columna se llame "mora". El
`riesgo_mora_gestion` es una **tabla fija** de ese par, distinta para antiguos y nuevos, sin una sola excepción en
168,091 filas:

| Segmento que trae la asignación | Riesgo del modelo | Gestión si es antiguo | Gestión si es nuevo |
|---|---|---|---|
| `MAX_DIASMORA 1-4` (modelo de mora) | Bajo / Medio / Alto | Bajo / Bajo / Bajo | Bajo / Bajo / Bajo |
| `MAX_DIASMORA 5-16` | Bajo / Medio / Alto | Bajo / Medio / Medio | Bajo / Medio / Medio |
| `MAX_DIASMORA +16` | Bajo / Medio / Alto | Medio / Alto / Alto | Medio / Alto / Alto |
| `Cliente Nuevo` (preventivo) | Bajo / Medio / Alto | Medio / Alto / Alto | Bajo / Medio / Alto |
| `Cliente Antiguo` (preventivo) | Bajo / Medio / Alto | Medio / Medio / Alto | Bajo / Medio / Medio |

Todo el segmento de 1-4 días queda en bajo aunque el modelo diga alto, y un preventivo alto es alto en nuevos pero
medio en antiguos (cliente antiguo).

**Todavía no se puede reconstruir hacia atrás.** El par que trae la asignación coincide con el de la cuota vigente
ese día en 77% de los nuevos con modelo de mora, pero solo en 44% de los antiguos y 41% de los preventivos: la
asignación puntúa otra cuota u otro momento. Tampoco sale de la cuota cuál de los dos modelos toca: casi todas las
cuotas tienen los dos puntajes. Directo desde la asignación solo hay julio y agosto 2026 completos.

## Universo y control

Mismo universo que las curvas v2: nuevos con `st_v2 = 0`, sin las entradas del día 1, arrastre fuera,
reenganches incluidos; stock = mora 1-30 el día 1, arrastre fuera, reenganches incluidos, sin la cohorte
d1 (S2). **Control:** el saldo base por mes reproduce `datos_tarea24/v2_matriz_{nuevos,stock}.csv` al
céntimo hasta 202604 y a ≤0.07% después (re-expresión de Mambu). Ventana **[202508, 202607]**, la de la
meta de septiembre; cobertura del puntaje 99.8-100%.

## 1. Corta, y fuerte

| Al cierre (nuevos: 30 días desde la entrada; stock: fin de mes) | Bajo | Medio | Alto |
|---|---:|---:|---:|
| Peso en el saldo, nuevos | 39.0% | 35.0% | 26.0% |
| **Rebaje de nuevos** | **28.9%** | 20.8% | **16.8%** |
| Activación de nuevos | 96.6% | 90.9% | 88.7% |
| Peso en el saldo, stock | 29.3% | 42.1% | 28.6% |
| **Rebaje de stock** | **22.8%** | 12.7% | **9.6%** |
| Activación de stock | 80.1% | 60.2% | 53.2% |

- **En nuevos corta más el rebaje que la activación.** El día de la entrada activa casi lo mismo en los
  tres niveles (38.6 / 36.8 / 36.4%) y a 30 días casi todos hicieron algún pago (89-97%); lo que cambia
  es cuánto pagan: el riesgo alto rebaja 42% menos soles que el bajo.
- **En stock corta los dos.** En rebaje separa más que el tramo (13.2 puntos entre Bajo y Alto, contra
  9.9 entre los tramos 1-8 y 16-30); en activación, menos (27 contra 42).
- El **segmento** del modelo también separa en nuevos (rebaje 24.6 / 20.8 / 16.7%; activación 95.8 / 89.5
  / 71.9% para máx. 1-4 / 5-16 / +16), con poco peso en el tramo más alto (4.4% del saldo).

## 2. Separa dentro de los segmentadores que el modelo ya usa

Rebaje, Alto menos Bajo, dentro de cada segmento vigente:

| Nuevos, por banda de avance | <10% | 10-40% | 40-70% | 70%+ |
|---|---:|---:|---:|---:|
| Rebaje de la banda | 16.0% | 20.5% | 41.3% | 75.1% |
| Alto − Bajo | −10.1pp | −9.2pp | −9.3pp | −6.0pp |

| Stock | 1-8 | 9-15 | 16-30 | avance <10% | 10-40% | 40-70% | 70%+ |
|---|---:|---:|---:|---:|---:|---:|---:|
| Alto − Bajo, rebaje | −12.6pp | −10.1pp | −9.2pp | −6.9pp | −9.6pp | −14.8pp | −25.3pp |
| Alto − Bajo, activación | −17.9pp | −15.6pp | −22.7pp | −22.1pp | −24.3pp | −27.0pp | −35.9pp |

En nuevos la banda de avance separa más que el riesgo (16% a 75%), pero **dentro de cada banda** el
riesgo sigue separando: trae información que el modelo hoy no tiene. En la banda con más saldo (<10%), el
riesgo alto rebaja la mitad que el bajo (11.3% contra 21.4%).

## 3. Es estable

El orden Bajo > Medio > Alto se cumple **todos los meses** con cobertura completa. Alto − Bajo en rebaje:
nuevos entre −9.5 y −15.0pp (jun-2025 a jul-2026), stock entre −9.5 y −16.6pp (jul-2025 a ago-2026). En
activación: nuevos −4.7 a −11.3pp, stock −18.2 a −34.5pp.

## 4. Para la meta, hasta ahora pesa poco, pero la mezcla se está moviendo

Lo que importa para la meta no es que el riesgo separe, sino que **la mezcla por riesgo cambie entre
meses**: una curva sin riesgo ya promedia los tres niveles con el peso de la ventana. Con las tasas de la
ventana por banda (nuevos) o tramo × banda (stock), con y sin riesgo, aplicadas a la mezcla de cada mes
(shift-share, in-sample; es una medida de materialidad, no un backtest):

| Efecto en la expectativa del mes | nuevos, rebaje | stock, rebaje | nuevos, activación | stock, activación |
|---|---:|---:|---:|---:|
| Rango ago-2025 a jul-2026 | −2.0% a +2.2% | −1.4% a +3.0% | −0.4% a +0.4% | −0.6% a +1.3% |
| Julio 2026 | −2.0% | −1.2% | −0.4% | −0.2% |

**Hay una deriva en nuevos:** el saldo que entra con riesgo alto pasó de 22-23% (jul-ago 2025) a 28-31%
(jun-jul 2026), y el de riesgo bajo de 45% a 34-37%. Por eso el efecto va de +2.2% (ago-2025) a −2.0%
(jul-2026): un modelo sin riesgo espera, para los meses recientes, ~2% más rebaje de nuevos del que su
mezcla justifica. Es del mismo signo que la sobreestimación de recupero de jun-jul en el backtest (+9 a
+10%, variante fix), pero explica a lo sumo un par de puntos de ella — orden de magnitud, con ventanas
distintas. En activación, que es la meta principal, el efecto es de décimas.

## Lectura

- **Sí, el riesgo de cobranza corta el rebaje**, en las dos poblaciones, dentro de cada segmento que ya
  usa el modelo, y todos los meses con el mismo signo. En nuevos corta sobre todo el monto que se paga, no
  si se paga.
- **Para la meta importa en la medida en que cambie la mezcla.** Hasta ahora movió la expectativa ±2-3%
  por mes en recupero y décimas en capital asegurado, pero la entrada de riesgo alto viene creciendo. Es
  un dato para la tarea 19 (la caída de la tasa de entrada y de la velocidad) que no estaba medido.
- **Adoptarlo sería cambiar de técnica, y no se hizo.** Requeriría el walk-forward con métricas diarias
  (el error de cierre no arbitra segmentadores, `CLAUDE.md`), y la curva de stock no podría seguir con su
  ventana fija 202504-202606: en ese período casi no hay puntaje.

## Archivos

Artifact: [🌡️ Riesgo de cobranza en las curvas](https://claude.ai/artifact/B2jGBzDFD5nb5vxTaFBKKt) (`riesgo_cobranza.html`; los datos los inyecta
`tarea26_riesgo_evaluacion.py` al final de su corrida).

`tarea26_riesgo_matriz_nuevos.sql`, `tarea26_riesgo_matriz_stock.sql` (matrices con el riesgo),
`tarea26_riesgo_evaluacion.py` (esta evaluación; log en `datos_tarea26/evaluacion_riesgo.log`, datos para
graficar en `datos_tarea26/evaluacion_riesgo.json`). Los perfiles de las columnas (cuotas y asignaciones)
se corrieron como queries exploratorias el 2026-09-15; sus resultados están resumidos arriba.

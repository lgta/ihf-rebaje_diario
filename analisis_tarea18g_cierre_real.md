# Tarea 18g — reindexar "fin de mes" por el cierre real, walk-forward de 7 meses

**Ejecutado 2026-08-26**, continuación directa de la corrección de 18b (el pico de pago vive
en el **último día real** de cada mes, no en el día calendario fijo 30/31 — ver
`analisis_sesgo_nuevos_18b.md` sección 2). Query nueva: `tarea18g_curva_cruda_stock.sql`
(matriz cruda de stock, grano `periodo_meta × tramo × avance_band × día`, 202501-202606 —
validada contra la curva de producción: día 15 exacto, día 30 dentro de 1pp). Código:
`curvas_crudas_stock.py`, `backtest_tarea18g.py`. **Diagnóstico — nada de esto está en
producción.**

## Qué se probó

| Variante | nuevos | stock |
|---|---|---|
| Y0 | estructural (=W3, producción) | fija, sin factor (=producción) |
| Y1 | **cierre real** | fija, sin factor |
| Y2 | estructural | fija **+ factor de cierre real** |
| Y3 | cierre real | fija + factor de cierre real |
| Y4 | cierre real | **rodando 12m** + factor de cierre real (además cierra 18c) |

Arbitrado con las mismas métricas diarias que 18a/18f (correlación de incrementos, MAE) —
el error de fin de mes se reporta como contexto, no decide (`CLAUDE.md`).

## Resultado: mejora real pero chica en stock, marginal en nuevos, y rodar la ventana de
stock por sí solo EMPEORA las métricas diarias

| | Y0 (prod) | Y1 (nuevos) | Y2 (stock) | Y3 (ambos) | Y4 (+ rodar stock) |
|---|---:|---:|---:|---:|---:|
| corr. diaria TOTAL | 0.831 | 0.835 | 0.838 | 0.838 | **0.827** |
| corr. diaria stock | 0.841 | 0.841 | **0.848** | 0.848 | 0.820 |
| corr. diaria nuevos | 0.886 | 0.888 | 0.886 | 0.888 | 0.888 |
| MAE stock (S/miles) | 27.3 | 27.3 | **26.7** | 26.7 | 29.3 |
| MAE nuevos (S/miles) | 72.5 | 72.1 | 72.5 | 72.1 | 72.1 |
| error cierre (media \|err\|) | 10.55% | 10.51% | 10.26% | 10.22% | 10.05% |

**Febrero, el caso que motivó esto — mejora clara y específica:** err. de stock **-11.0% →
-8.3%** (Y2) y correlación diaria de stock **0.818 → 0.856**. El factor de cierre está
capturando parte real del mecanismo — pero **no lo resuelve del todo**: -8.3% sigue siendo,
por lejos, el peor mes de stock (el resto va de -4.5% a +5.3%). Rodar además la ventana (Y4)
**empeora** febrero de nuevo (-9.0%).

**Nuevos apenas se mueve** (corr. 0.886→0.888, MAE 72.5K→72.1K) — mucho más chico que el
salto que dio el día de semana en 18a (+0.264) o incluso el factor de quincena/fin-de-mes
original en 18f (+0.011 sí, pero éste da +0.002). Es coherente con lo medido en la sección 2
de 18b: el factor `f` de producción, aunque diluido, ya capturaba la mayor parte de la señal
porque el grupo `{30,31}` incluye el verdadero pico (día 31 en meses de 31 días) — la dilución
existe pero pesa poco en el agregado de 7 meses.

**Rodar la ventana de stock (18c), aislado de la pregunta del cierre real, empeora las
métricas diarias en promedio** (corr. total 0.831→0.827 comparando Y0 vs. una versión Y4 sin
el factor — el efecto negativo es de la ventana rodante, no del factor: corr. stock cae de
0.848 a 0.820 al pasar de Y3 a Y4, manteniendo el factor de cierre en ambas). Stock es el
componente con menos masa por mes (`BUGS.md`: "el componente errático del backtest") — una
ventana rodante de 12 meses le da, a los meses de test más tempranos (enero), una historia de
calibración con cartera bastante más chica que la ventana fija actual, y eso parece pesar más
que el beneficio de no tener leak. **Esto es un hallazgo en sí mismo:** "sin leak" no
garantiza "mejor" cuando el componente tiene alta varianza muestral — 18c necesitaría su
propia evaluación específica, no asumir que rodar es automáticamente correcto solo porque es
consistente con nuevos.

## Lectura, no ajuste

- **El mecanismo es real y está bien identificado** (dpf=0 concentra el pico de pago, no el
  día calendario 30/31) — pero su impacto agregado en las métricas de decisión es chico
  para nuevos y modesto-pero-real para stock, concentrado sobre todo en meses cortos como
  febrero.
- **Candidato razonable para adoptar, por el criterio de `CLAUDE.md`** (mide más fiel, no
  "mejora el error"): el factor de cierre real de STOCK (Y2) — mecanismo verificado, mejora
  medible y dirigida exactamente al caso que lo motivó, sin la complicación de rodar la
  ventana. El de NUEVOS (Y1) es defendible pero de impacto marginal — no cambia mucho adoptarlo
  o no.
- **Rodar la ventana de stock (18c) NO sale gratis como en nuevos** — acá hay una tensión real
  entre "más consistente" y "más ruidoso", que 18c va a necesitar resolver por separado
  (quizás con una ventana rodante más larga que 12 meses para stock, dado que es el componente
  de mayor varianza — no probado todavía).
- Nada de esto se llevó a producción. Es material de decisión, en el mismo formato que 18a/18f.

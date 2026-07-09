# Meta de recupero diaria — cartera de cobranza (mora 1–30)

Metodología y herramientas para estimar, **día a día**, cuánto saldo capital debería
recuperarse de la cartera de cobranza en mora 1–30 días — calibrada con 14 meses de
historia real (dts_mambu_loans_hist, dts_okaapi_loans, dts_cobranza_creditos_cuotas en
Athena, `dev_datalake_master`) y validada contra un mes real cerrado (backtest de junio
2026: +5.4% de error).

## Documentos publicados

| Documento | Público | Contenido |
|---|---|---|
| [Metodología ejecutiva](https://claude.ai/code/artifact/909de8df-443f-4440-b85a-e39af636c8e7) — `metodologia_recupero.html` | Negocio | Modelo conceptual, curvas, backtest de junio |
| [Guía técnica](https://claude.ai/code/artifact/9df13c20-7758-4174-8346-ed6563d25c5d) — `guia_tecnica_recupero.md` | Técnico | Mismo contenido + SQL copiable para Athena |
| [Meta en vivo — julio](https://claude.ai/code/artifact/52d8badf-bb51-4b92-a3c1-f4f2017aaa27) — `meta_julio_en_vivo.html` | Operativo | Caso de uso real: cálculo de la meta del mes en curso |
| [Deck completo](https://claude.ai/code/artifact/ae2f5e71-ff14-48bd-af00-909b0aa634cf) — `deck_meta_recupero.html` | Presentación | De la asignación (antiguos/nuevos) a la meta, en 11 slides |

*(Los artifacts son privados hasta que se compartan explícitamente desde su menú de
compartir en claude.ai.)*

## El modelo, en una frase

El pago es un evento (92% de los créditos en mora paga 0 o 1 vez al mes), no un flujo
diario — por eso el recupero se modela como **P(paga) × E(% del saldo que rebaja al
pagar)**, para dos poblaciones con motores distintos:

- **Stock (antiguos):** créditos con mora 1–30 al cierre del mes anterior. Curva de
  recupero por **tramo de mora × día del mes**.
- **Nuevos:** créditos que caen en mora durante el mes, uno por cada día del calendario
  de vencimientos que no se paga a tiempo. Curva de recupero por **avance de
  amortización × días desde la entrada en mora**.

Ver [`guia_tecnica_recupero.md`](guia_tecnica_recupero.md) para la explicación completa
con SQL replicable, o [`plan_analisis.md`](plan_analisis.md) para la bitácora técnica
completa (todas las decisiones, corridas y correcciones, en orden cronológico).

## Estructura del repositorio

```
fase0_diagnostico.sql      Auditoría de datos: grumosidad del pago, mecánica de dayslate
fase1_stock.sql            Motor del stock — curva por tramo × avance × día
fase2_nuevos.sql           Motor de nuevos — curva por avance × días desde entrada
fase3_meta.sql             Calendario de vencimientos + mecanismo de combinación
fase3_backtest.sql         Backtest sobre un mes real y cerrado (junio 2026)
ejemplo_cohorte_julio.sql  Ejemplo replicable de una sola cohorte, paso a paso

armar_trayectoria_seg.py   Combina curvas + calendario en una trayectoria diaria (rolling)
backtest_junio.py          Compara proyección vs. recupero real de junio (backtest)
meta_julio.py              Meta del mes en curso, anclada al cierre del mes anterior
meta_desde_hoy.py          Meta recalculada desde hoy ("reinicio del reloj", cruce de validación)

datos_backtest_junio/      Insumos (CSV) del backtest de junio
datos_meta_julio/          Insumos (CSV) de la meta de julio (enfoque acumulado)
datos_meta_desde_hoy/      Insumos (CSV) del enfoque "reinicio del reloj"

plan_analisis.md           Bitácora técnica completa — fuente de verdad
guia_tecnica_recupero.md   Guía técnica con SQL replicable (copia del artifact)
metodologia_recupero.html  Documento ejecutivo (copia del artifact)
meta_julio_en_vivo.html    Caso de uso en vivo (copia del artifact)
deck_meta_recupero.html    Deck de presentación (copia del artifact)
```

## Resultados clave (al 2026-07-09)

- **Recupero mensual del stock por tramo:** 1–8 días: 18.1% · 9–15: 12.7% · 16–30: 7.8%
  del saldo capital.
- **Severidad determinada por avance de amortización, no por tramo de mora** — de 14.9%
  (avance <10%) a 74.8% (avance 70%+), consistente en stock y en nuevos.
- **Backtest sobre junio 2026 (mes real y cerrado):** +5.4% de error al cierre
  (stock +16.2%, nuevos +0.7% — casi exacto).
- **Meta de julio 2026:** S/1,776,174 (stock S/426,651 + nuevos S/1,349,523). Al corte
  del día 9: recuperado real S/527,375 (+6.3% sobre lo proyectado); resta S/1,248,799.

## Pendientes

- Extender el backtest a 3–6 meses más (junio es un solo punto de dato).
- Corregir el enfoque "reinicio del reloj" (`meta_desde_hoy.*`) para no excluir
  silenciosamente a los créditos del stock original que cruzan 30 días de mora entre la
  asignación y el corte — ver detalle en `plan_analisis.md`, sección "Meta en vivo de
  julio". El enfoque acumulado (`meta_julio.*`) no tiene este problema y es la fuente
  oficial.
- Recalibrar las curvas excluyendo cada mes de prueba (hoy incluyen los 14 meses
  completos, con peso marginal ~1/14 del mes evaluado).
- Usar `installmentlastpaiddate` (dts_cobranza_creditos_cuotas) para cuantificar el
  período de gracia de `dayslate` frente a la fecha de vencimiento.

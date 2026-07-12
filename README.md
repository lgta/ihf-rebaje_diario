# Meta de recupero diaria — cartera de cobranza (mora 1–30)

Metodología y herramientas para estimar, **día a día**, cuánto saldo capital debería
recuperarse de la cartera de cobranza en mora 1–30 días — calibrada con 14 meses de
historia real (dts_mambu_loans_hist, dts_okaapi_loans, dts_cobranza_creditos_cuotas en
Athena, `dev_datalake_master`) y validada contra un mes real cerrado (backtest de junio
2026: +5.4% de error).

## Empezar por acá

**[`ESTADO.md`](ESTADO.md)** — foto del momento: meta vigente, artifacts actualizados,
qué está validado vs. experimental, pendientes. Es el archivo que se mantiene al día; todo
lo demás es o bien historial (`plan_analisis.md`) o referencia estable (glosario, fuentes
de datos, decisiones).

## Documentos publicados

| Documento | Público | Contenido |
|---|---|---|
| [Metodología ejecutiva](https://claude.ai/code/artifact/909de8df-443f-4440-b85a-e39af636c8e7) — `metodologia_recupero.html` | Negocio | Modelo conceptual, curvas, backtest de junio |
| [Guía técnica](https://claude.ai/code/artifact/9df13c20-7758-4174-8346-ed6563d25c5d) — `guia_tecnica_recupero.md` | Técnico | Mismo contenido + SQL copiable para Athena |
| [Detalle con curvas interactivas](https://claude.ai/code/artifact/71e5d69d-7586-4ba1-aedc-de7397eea425) — `meta_recupero_detalle.html` | Equipo | El más completo: composición, calendario, curvas por avance, cohortes, trayectoria — todo interactivo |
| [⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8) — `julio_25pct_no_recomendado.html` | Referencia | Registro de por qué la tasa oficial es 13.38%, no el complemento simple de "paga a tiempo" |
| [🔒 Capital asegurado](https://claude.ai/code/artifact/3a6b8cb9-0b2a-4dac-9569-473327a84b0a) — `capital_asegurado.html` | 🧪 Experimental | Enfoque alfa: % del capital asignado con actividad de pago, no soles recuperados. Ver `enfoque_capital_asegurado.md` |
| [🔓 Salida de mora](https://claude.ai/code/artifact/f1b0c577-4044-40a3-bebd-e01f5141ed98) — `salida_mora.html` | 🔬 Exploratorio | Enfoque beta: cura real vs. reestructuración al salir de mora. Ver `enfoque_salida_mora.md` |
| [Meta en vivo — julio](https://claude.ai/code/artifact/52d8badf-bb51-4b92-a3c1-f4f2017aaa27) — `meta_julio_en_vivo.html` | Operativo, ⚠ desactualizado | Caso de uso real: cálculo de la meta del mes en curso |
| [Deck completo](https://claude.ai/code/artifact/ae2f5e71-ff14-48bd-af00-909b0aa634cf) — `deck_meta_recupero.html` | Presentación, ⚠ desactualizado | De la asignación (antiguos/nuevos) a la meta, en 11 slides |

*(Los artifacts son privados hasta que se compartan explícitamente desde su menú de
compartir en claude.ai. Los marcados ⚠ no tienen error, solo no incorporan el fix de
aged-out ni la investigación de dayslate — ver `ESTADO.md`.)*

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
con SQL replicable, [`plan_analisis.md`](plan_analisis.md) para la bitácora técnica
completa (todas las decisiones, corridas y correcciones, en orden cronológico), o los
archivos de referencia de abajo para consultas puntuales.

## Documentos de referencia (no cronológicos)

| Archivo | Para qué |
|---|---|
| [`ESTADO.md`](ESTADO.md) | Foto del momento — empezar por acá |
| [`BUGS.md`](BUGS.md) | Bugs y gotchas encontrados, con causa y fix |
| [`IDEAS.md`](IDEAS.md) | Pendientes activos + ideas ya probadas y descartadas |
| [`DECISIONES.md`](DECISIONES.md) | Por qué se eligió cada pieza de la metodología |
| [`GLOSARIO.md`](GLOSARIO.md) | Definición corta de cada término |
| [`FUENTES_DATOS.md`](FUENTES_DATOS.md) | Las 3 tablas de Athena, su grano y sus quirks |
| [`SEGUIMIENTO.md`](SEGUIMIENTO.md) | Tabla mes a mes de proyectado vs. real |
| [`CLAUDE.md`](CLAUDE.md) | Instrucciones para cualquier sesión de Claude Code en este repo |
| [`enfoque_acumulado.md`](enfoque_acumulado.md) | Enfoque oficial (validado): resumen corto, apunta a `guia_tecnica_recupero.md` |
| [`enfoque_reinicio_reloj.md`](enfoque_reinicio_reloj.md) | Enfoque B (deprioritizado): recalcular desde "hoy" en vez del cierre |
| [`enfoque_capital_asegurado.md`](enfoque_capital_asegurado.md) | Enfoque alfa (experimental): % de capital con actividad de pago |
| [`enfoque_salida_mora.md`](enfoque_salida_mora.md) | Enfoque beta (exploratorio): cura real vs. reestructuración al salir de mora |

## Estructura del repositorio

```
fase0_diagnostico.sql        Auditoría de datos: grumosidad del pago, mecánica de dayslate
fase1_stock.sql              Motor del stock — curva por tramo × avance × día
fase2_nuevos.sql             Motor de nuevos — curva por avance × días desde entrada
fase3_meta.sql               Calendario de vencimientos + mecanismo de combinación
fase3_backtest.sql           Backtest sobre un mes real y cerrado (junio 2026)
ejemplo_cohorte_julio.sql    Ejemplo replicable de una sola cohorte, paso a paso
investigacion_dayslate.sql   Investigación del punto ciego de 1 día en dayslate
motor_cuota_vencimiento.sql  Motor alternativo por vencimiento de cuota (descartado, ver BUGS.md)
enfoque_capital_asegurado.sql  Enfoque alfa: curvas de capital asegurado (experimental)
enfoque_salida_mora.sql      Enfoque beta: cura real vs. reestructuración (exploratorio)

armar_trayectoria_seg.py     Combina curvas + calendario en una trayectoria diaria (rolling)
backtest_junio.py            Compara proyección vs. recupero real de junio (backtest)
backtest_motor_cuota.py      Backtest del motor alternativo (descartado)
meta_julio.py                Meta del mes en curso, anclada al cierre del mes anterior
meta_julio_25pct.py          Meta de julio bajo el escenario 25% plano (no recomendado)
meta_julio_capital_asegurado.py  Proyección de julio bajo el enfoque alfa (experimental)
meta_desde_hoy.py            Meta recalculada desde hoy ("reinicio del reloj", deprioritizado)

datos_backtest_junio/        Insumos (CSV) del backtest de junio
datos_meta_julio/            Insumos (CSV) de la meta de julio (enfoque acumulado)
datos_meta_desde_hoy/        Insumos (CSV) del enfoque "reinicio del reloj"
datos_motor_cuota/           Insumos (CSV) del motor alternativo por vencimiento
datos_capital_asegurado/     Insumos (CSV) del enfoque alfa (capital asegurado)
scripts/run_athena.sh        Helper para correr un .sql contra Athena y bajar el CSV

plan_analisis.md             Bitácora técnica completa — historial cronológico
guia_tecnica_recupero.md     Guía técnica con SQL replicable (copia del artifact)
metodologia_recupero.html    Documento ejecutivo (copia del artifact)
meta_julio_en_vivo.html      Caso de uso en vivo (copia del artifact, desactualizado)
deck_meta_recupero.html      Deck de presentación (copia del artifact, desactualizado)
meta_recupero_detalle.html   Detalle con curvas interactivas (copia del artifact)
julio_25pct_no_recomendado.html  Por qué NO usar 25% (copia del artifact)
capital_asegurado.html       Enfoque alfa: capital asegurado (copia del artifact, experimental)
salida_mora.html             Enfoque beta: hallazgos de salida de mora (copia del artifact, exploratorio)
enfoque_capital_asegurado.md Doc dedicado del enfoque alfa: concepto, metodología, resultados
enfoque_salida_mora.md       Doc dedicado del enfoque beta: cura real vs. reestructuración
```

## Resultados clave

Ver [`ESTADO.md`](ESTADO.md) para la cifra vigente (se actualiza ahí, no acá) y
[`SEGUIMIENTO.md`](SEGUIMIENTO.md) para el histórico mes a mes de proyectado vs. real.
Resumen al 2026-07-10:

- **Recupero mensual del stock por tramo:** 1–8 días: 18.1% · 9–15: 12.7% · 16–30: 7.8%
  del saldo capital.
- **Severidad determinada por avance de amortización, no por tramo de mora** — de 14.9%
  (avance <10%) a 74.8% (avance 70%+), consistente en stock y en nuevos.
- **Backtest sobre junio 2026 (mes real y cerrado):** +5.4% de error al cierre
  (stock +16.2%, nuevos +0.7% — casi exacto). Es el único enfoque validado — dos
  alternativas de tasa de entrada a mora (25% plano, motor "cuota-consistente" 8.62%)
  se probaron y fallaron el backtest, en direcciones opuestas (ver `BUGS.md` bug 10).
- **Meta de julio 2026:** S/1,776,174 (stock S/426,651 + nuevos S/1,349,523). Al corte
  del día 9: recuperado real S/527,375 (29.7% de avance); resta S/1,248,799.
- El enfoque "reinicio del reloj" (`meta_desde_hoy.*`) quedó **deprioritizado** — la meta
  oficial es siempre la del mes completo. Ver `ESTADO.md`.

## Pendientes

Ver [`IDEAS.md`](IDEAS.md) para la lista completa (activos + ya descartados, para no
repetir). Los más relevantes: extender el backtest a 3–6 meses más, recalibrar las curvas
excluyendo cada mes de prueba, usar `installmentlastpaiddate` para precisar el punto ciego
de `dayslate`, y entender por qué la tasa "cuota-consistente" (8.62%) difiere tanto de la
oficial (13.38%).

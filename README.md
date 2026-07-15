# Meta de recupero diaria — cartera de cobranza (mora 1–30)

Metodología y herramientas para estimar, **día a día**, la cartera de cobranza en mora
1–30 días — calibrada con 14 meses de historia real (dts_mambu_loans_hist,
dts_okaapi_loans, dts_cobranza_creditos_cuotas en Athena, `dev_datalake_master`) y
validada contra un mes real cerrado. **Desde 2026-07-13 la meta principal es capital
asegurado** (Enfoque alfa: % de capital con actividad de pago, backtest -4.7% de error);
el recupero oficial en soles (backtest +5.4% de error) se sigue trackeando en paralelo.
Ver [`ESTADO.md`](ESTADO.md) para el detalle.

> **Desde 2026-07-15 el proyecto mantiene solo estos 2 enfoques.** "Reinicio del reloj" y
> el enfoque beta "salida de mora" se descontinuaron a pedido explícito del usuario — ver
> `DECISIONES.md`. Sus archivos se eliminaron del repo (recuperables vía git history).

## Empezar por acá

**[`ESTADO.md`](ESTADO.md)** — foto del momento: meta vigente, artifacts actualizados,
qué está validado vs. experimental, pendientes. Es el archivo que se mantiene al día; todo
lo demás es o bien historial (`plan_analisis.md`) o referencia estable (glosario, fuentes
de datos, decisiones).

**[`PENDIENTES.md`](PENDIENTES.md)** — plan de continuación accionable para los 2
enfoques vigentes (alfa y acumulado), pensado para que alguien que recién llega complete
lo que falta sin releer todo el historial.

## Documentos publicados

| Documento | Público | Contenido |
|---|---|---|
| [Metodología ejecutiva](https://claude.ai/code/artifact/909de8df-443f-4440-b85a-e39af636c8e7) — `metodologia_recupero.html` | Negocio | Modelo conceptual, curvas, backtest de junio |
| [Guía técnica](https://claude.ai/code/artifact/9df13c20-7758-4174-8346-ed6563d25c5d) — `guia_tecnica_recupero.md` | Técnico | Mismo contenido + SQL copiable para Athena |
| [Detalle con curvas interactivas](https://claude.ai/code/artifact/71e5d69d-7586-4ba1-aedc-de7397eea425) — `meta_recupero_detalle.html` | Equipo | El más completo: composición, calendario, curvas por avance, cohortes, trayectoria — todo interactivo |
| [⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8) — `julio_25pct_no_recomendado.html` | Referencia | Registro de por qué la tasa oficial es 13.38%, no el complemento simple de "paga a tiempo" |
| [🔒 Capital asegurado](https://claude.ai/code/artifact/3a6b8cb9-0b2a-4dac-9569-473327a84b0a) — `capital_asegurado.html` | Meta principal, ⚠ desactualizado (números pre-bug 12) | Enfoque alfa: % del capital asignado con actividad de pago, no soles recuperados. 5 créditos reales, curvas por segmento, backtest de junio (-4.4%) y avance en vivo de julio. Ver `enfoque_capital_asegurado.md`. Pendiente en `PENDIENTES.md` |
| [🔒 Curvas + matriz mensual](https://claude.ai/code/artifact/c8d733d5-f008-4f33-b4e6-e7712f1c4ece) — `curvas_matriz_alfa.html` | Equipo | Enfoque alfa: curvas de maduración interactivas (antiguo por tramo, nuevos) + matriz mes a mes de asignado/asegurado/%, ya con la definición corregida (bug 12). Ver `matriz_mensual_alfa.sql` |
| [Meta en vivo — julio](https://claude.ai/code/artifact/52d8badf-bb51-4b92-a3c1-f4f2017aaa27) — `meta_julio_en_vivo.html` | Operativo, ⚠ desactualizado | Caso de uso real: cálculo de la meta del mes en curso |
| [Deck completo](https://claude.ai/code/artifact/ae2f5e71-ff14-48bd-af00-909b0aa634cf) — `deck_meta_recupero.html` | Presentación, ⚠ desactualizado | De la asignación (antiguos/nuevos) a la meta, en 11 slides |

*(Los artifacts son privados hasta que se compartan explícitamente desde su menú de
compartir en claude.ai. Los marcados ⚠ no tienen error, solo no incorporan el fix de
aged-out ni la investigación de dayslate — ver `ESTADO.md`. Los artifacts de "Salida de
mora" y "Los 4 enfoques explicados" se quitaron de esta tabla al descontinuarse esos
enfoques el 2026-07-15 — ver `DECISIONES.md`; siguen existiendo en claude.ai, solo
dejaron de mantenerse.)*

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
| [`PENDIENTES.md`](PENDIENTES.md) | Plan de continuación accionable para los 2 enfoques vigentes |
| [`BUGS.md`](BUGS.md) | Bugs y gotchas encontrados, con causa y fix |
| [`IDEAS.md`](IDEAS.md) | Pendientes de investigación de fondo + ideas ya probadas y descartadas |
| [`DECISIONES.md`](DECISIONES.md) | Por qué se eligió cada pieza de la metodología |
| [`GLOSARIO.md`](GLOSARIO.md) | Definición corta de cada término |
| [`FUENTES_DATOS.md`](FUENTES_DATOS.md) | Las 4 tablas de Athena del proyecto, su grano y sus quirks |
| [`LINAJE.md`](LINAJE.md) | De qué sistema viene cada columna (Mambu, OkaAPI, o calculada internamente) |
| [`SEGUIMIENTO.md`](SEGUIMIENTO.md) | Tabla mes a mes de proyectado vs. real |
| [`CLAUDE.md`](CLAUDE.md) | Instrucciones para cualquier sesión de Claude Code en este repo |
| [`enfoque_acumulado.md`](enfoque_acumulado.md) | Enfoque oficial (validado): resumen corto, apunta a `guia_tecnica_recupero.md` |
| [`enfoque_capital_asegurado.md`](enfoque_capital_asegurado.md) | Enfoque alfa (validado, backtest -4.7%): % de capital con actividad de pago |
| [`avance_cobranza_fase.md`](avance_cobranza_fase.md) | Análisis puntual: avance de julio por fase de cobranza (Temprana/Especializada/Recovery), usando la asignación real del negocio |

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
enfoque_capital_asegurado.sql  Enfoque alfa: curvas de capital asegurado (validado, backtest -4.7%)
enfoque_capital_asegurado_backtest.sql  Backtest de junio del enfoque alfa
avance_cobranza_fase.sql     Análisis puntual: avance por fase de cobranza (Temprana/Especializada/Recovery)

armar_trayectoria_seg.py     Combina curvas + calendario en una trayectoria diaria (rolling)
backtest_junio.py            Compara proyección vs. recupero real de junio (backtest)
backtest_capital_asegurado_junio.py  Backtest de junio del enfoque alfa (capital asegurado)
backtest_motor_cuota.py      Backtest del motor alternativo (descartado)
meta_julio.py                Meta del mes en curso, anclada al cierre del mes anterior
meta_julio_25pct.py          Meta de julio bajo el escenario 25% plano (no recomendado)
meta_julio_capital_asegurado.py  Proyección de julio bajo el enfoque alfa
avance_cobranza_fase.py      Agregación + cruce con curvas del análisis por fase de cobranza

datos_backtest_junio/        Insumos (CSV) del backtest de junio (recupero + capital asegurado)
datos_meta_julio/            Insumos (CSV) de la meta de julio (enfoque acumulado)
datos_motor_cuota/           Insumos (CSV) del motor alternativo por vencimiento
datos_capital_asegurado/     Insumos (CSV) del enfoque alfa (capital asegurado)
datos_avance_fase/           Insumos (CSV) del análisis de avance por fase de cobranza
scripts/run_athena.sh        Helper para correr un .sql contra Athena y bajar el CSV

plan_analisis.md             Bitácora técnica completa — historial cronológico (incluye lo
                              descontinuado: reinicio del reloj, salida de mora)
guia_tecnica_recupero.md     Guía técnica con SQL replicable (copia del artifact)
metodologia_recupero.html    Documento ejecutivo (copia del artifact)
meta_julio_en_vivo.html      Caso de uso en vivo (copia del artifact, desactualizado)
deck_meta_recupero.html      Deck de presentación (copia del artifact, desactualizado)
meta_recupero_detalle.html   Detalle con curvas interactivas (copia del artifact)
julio_25pct_no_recomendado.html  Por qué NO usar 25% (copia del artifact)
capital_asegurado.html       Enfoque alfa: capital asegurado (copia del artifact, pendiente de refresco)
enfoque_capital_asegurado.md Doc dedicado del enfoque alfa: concepto, metodología, resultados
PENDIENTES.md                Plan de continuación accionable para los 2 enfoques vigentes
```

**Nota (2026-07-15):** `enfoque_reinicio_reloj.md`, `meta_desde_hoy.py`/`.sql`,
`datos_meta_desde_hoy/`, `enfoque_salida_mora.md`/`.sql`, `salida_mora.html`,
`datos_salida_mora/`, `guia_4_enfoques.html` y `ejemplos_4_enfoques.sql` se eliminaron del
repo al descontinuarse esos 2 enfoques — ver `DECISIONES.md`. Recuperables vía git history.

## Resultados clave

Ver [`ESTADO.md`](ESTADO.md) para la cifra vigente (se actualiza ahí, no acá) y
[`SEGUIMIENTO.md`](SEGUIMIENTO.md) para el histórico mes a mes de proyectado vs. real.
Resumen al 2026-07-14:

- **Desde 2026-07-13, la meta principal reportada es capital asegurado** (Enfoque alfa,
  `enfoque_capital_asegurado.md`), a pedido explícito del usuario — no el recupero en
  soles. El recupero oficial se sigue calculando y trackeando en paralelo.
- **2026-07-14 — corrección de definición antiguos/nuevos** (bug 12, ver `BUGS.md`): un
  crédito que entra en mora el día 1 de un mes viene de una cuota vencida el último día del
  mes anterior — es antiguo, no nuevo. Los números de abajo ya reflejan el fix.
- **Meta de julio 2026 — capital asegurado:** S/10,306,231 proyectado (stock S/3,105,418 +
  nuevos S/7,200,813). Al corte del día 13: real S/4,971,669 (48.2% de avance del mes,
  +4.1% por encima de lo proyectado para el mismo día). Lectura de un solo mes a mitad de
  camino — no sacar conclusiones todavía, ver `ESTADO.md`.
- **Backtest de capital asegurado sobre junio 2026:** -4.4% de error al cierre (stock
  +7.2%, nuevos -8.6%) — mismo orden de magnitud que el backtest del recupero oficial.
- **Recupero oficial — backtest sobre junio 2026 (mes real y cerrado):** +5.4% de error al
  cierre (stock +16.2%, nuevos +0.7% — casi exacto). Dos alternativas de tasa de entrada a
  mora (25% plano, motor "cuota-consistente" 8.62%) se probaron y fallaron el backtest, en
  direcciones opuestas (ver `BUGS.md` bug 10).
- **Meta de julio 2026 — recupero oficial:** S/1,776,174 (stock S/426,651 + nuevos
  S/1,349,523). Al corte del día 9: recuperado real S/527,375 (29.7% de avance); resta
  S/1,248,799.
- **Recupero mensual del stock por tramo:** 1–8 días: 18.1% · 9–15: 12.7% · 16–30: 7.8%
  del saldo capital.
- **Severidad determinada por avance de amortización, no por tramo de mora** — de 14.9%
  (avance <10%) a 74.8% (avance 70%+), consistente en stock y en nuevos.
- **2026-07-15 — recorte de alcance:** el enfoque "reinicio del reloj" y el enfoque beta
  "salida de mora" se descontinuaron formalmente y sus archivos se eliminaron del repo —
  el proyecto ahora mantiene solo el enfoque acumulado y el alfa. Ver `DECISIONES.md`.

## Pendientes

**Ver [`PENDIENTES.md`](PENDIENTES.md)** para la lista accionable de los 2 enfoques
vigentes (qué falta re-correr, qué artifact refrescar, qué queda para cerrar julio). Ver
[`IDEAS.md`](IDEAS.md) para pendientes de investigación de fondo (extender el backtest a
3–6 meses más, recalibrar curvas excluyendo cada mes de prueba, `installmentlastpaiddate`)
e ideas ya descartadas (para no repetirlas).

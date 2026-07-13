# Estado actual

> Este archivo se **reescribe**, no crece. Si algo de acá cambia (una meta se recalcula,
> un artifact se actualiza, un pendiente se resuelve), se edita esta misma sección — no
> se agrega una entrada nueva al final. Para el historial cronológico completo, ver
> `plan_analisis.md`. Para saber por qué se decidió algo, ver `DECISIONES.md`.

Última actualización: 2026-07-13.

## La meta vigente

**Julio 2026, corte 9-jul:** meta total **S/1,776,174** (stock S/426,651 + nuevos
S/1,349,523). Real recuperado a la fecha: S/527,375 (29.7% de avance). Resta:
**S/1,248,799** (días 10-31). Fuente: `meta_julio.py` + `datos_meta_julio/`.

Metodología: modelo evento × magnitud, dos motores (stock anclado al cierre del mes
anterior, nuevos vía calendario de vencimientos × P(no paga a tiempo)=13.38% × curva de
maduración). Detalle completo en `guia_tecnica_recupero.md` y en el artifact interactivo
de abajo.

## Artifacts publicados

| Artifact | Estado | Contenido |
|---|---|---|
| [Metodología ejecutiva](https://claude.ai/code/artifact/909de8df-443f-4440-b85a-e39af636c8e7) | ✓ vigente | Modelo conceptual, curvas, backtest de junio |
| [Guía técnica](https://claude.ai/code/artifact/9df13c20-7758-4174-8346-ed6563d25c5d) | ✓ vigente | SQL replicable para Athena |
| [Meta en vivo — julio](https://claude.ai/code/artifact/52d8badf-bb51-4b92-a3c1-f4f2017aaa27) | ⚠ desactualizado | No refleja el fix de aged-out ni la investigación de dayslate |
| [Deck (11 slides)](https://claude.ai/code/artifact/ae2f5e71-ff14-48bd-af00-909b0aa634cf) | ⚠ desactualizado | Mismo motivo |
| [**Detalle con curvas interactivas**](https://claude.ai/code/artifact/71e5d69d-7586-4ba1-aedc-de7397eea425) | ✓ vigente, el más completo | Composición stock, calendario nuevos, curvas por avance, cohortes, trayectoria — todo con gráficos hover |
| [⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8) | ✓ vigente, es una advertencia | Registro de por qué la tasa oficial es 13.38% y no el complemento simple de "paga a tiempo" |
| [🔒 Capital asegurado](https://claude.ai/code/artifact/3a6b8cb9-0b2a-4dac-9569-473327a84b0a) | ⚠ desactualizado | Enfoque alfa — no refleja el backtest de junio (-4.7%, ver `enfoque_capital_asegurado.md`), que ya pasó y promovió la métrica a KPI complementario en `SEGUIMIENTO.md` |
| [🔓 Salida de mora — hallazgos](https://claude.ai/code/artifact/f1b0c577-4044-40a3-bebd-e01f5141ed98) | ⚠ desactualizado | Enfoque beta — tiene los números de ANTES del fix de dedup (bug 11, `BUGS.md`: 513/364 → 376/363) y no incluye el hallazgo de reincidencia (80.8% recae). Ver `enfoque_salida_mora.md` |
| [🧭 Los 4 enfoques explicados](https://claude.ai/code/artifact/a75f705d-9522-4843-af77-d79ce90b047f) | ✓ vigente | Concepto + SQL explicado + un crédito real de Athena por cada uno de los 4 enfoques (acumulado, reinicio, capital asegurado, salida de mora). Ver `guia_4_enfoques.html` |

Los dos primeros más el de "Detalle" son los recomendados para compartir con el equipo.
Los "⚠ desactualizado" no tienen error, solo no incorporan los hallazgos más recientes —
no republicar sin actualizarlos primero.

## Índice de enfoques

> Todos los enfoques construidos hasta ahora, en un solo lugar — pensado para que una
> sesión futura pueda armar un markdown integral sin tener que releer todo el historial.
> Cada uno tiene su propio archivo `enfoque_*.md` con el detalle completo.

| Enfoque | Archivo | Qué mide | Estado |
|---|---|---|---|
| **Acumulado** (oficial) | `enfoque_acumulado.md` | Soles recuperados, mes completo anclado al cierre anterior | ✅ Validado, backtest +5.4% |
| Reinicio del reloj | `enfoque_reinicio_reloj.md` | Lo mismo, pero re-anclado a "hoy" | 🕓 Deprioritizado, no oficial |
| Alfa — Capital asegurado | `enfoque_capital_asegurado.md` | % de capital con ≥1 pago en el mes (no soles recuperados) | ✅ Backtest -4.7% (jun-2026), promovido a KPI complementario en `SEGUIMIENTO.md` |
| Beta — Salida de mora | `enfoque_salida_mora.md` | Cura real vs. reestructuración al salir de mora; reincidencia | 🔬 Exploratorio — reincidencia confirmada (80.8% recae), falta curva/proyección (opción a) |
| Tasa 25% plano / motor cuota-consistente | ver `BUGS.md` bug 10 | Alternativas de `P(no paga a tiempo)` | ❌ Descartados por backtest (+66% a +81% / -35.7%) |

Detalle de los dos últimos:
- ⚠️ **Descartado por backtest:** tasa plana 25-28% (sobreestima +66% a +81%); motor
  "cuota-consistente" con tasa 8.62% + curva propia (subestima -35.7%). Ver `BUGS.md` y
  `motor_cuota_vencimiento.sql`. No son un "enfoque" completo (solo tocan la constante
  `P(no paga a tiempo)` del enfoque acumulado), por eso no tienen `enfoque_*.md` propio.

## Análisis puntuales (snapshots, no enfoques con curva propia)

- **Avance de julio por fase de cobranza** (`avance_cobranza_fase.md`, 2026-07-13): cruza
  la asignación REAL del negocio (tabla nueva `dts_asignaciones_cobranza`, ver
  `FUENTES_DATOS.md`) contra capital asegurado (Enfoque alfa) por fase TEMPRANA /
  ESPECIALIZADA / RECOVERY × nuevo/stock. Corte 2-jul a 12-jul. Hallazgo: Temprana va
  ligeramente atrasada (-4 a -13pp según tramo, salvo 16-30 que va +2.7pp adelantado);
  Especializada/Recovery no tienen curva calibrada (el modelo nunca cubrió mora 31+).

## Pendiente de copiar al repo desde scratchpad

Nada por ahora — todo lo generado hasta el 2026-07-13 (backtest de capital asegurado,
investigación de reincidencia, avance por fase de cobranza) ya está en el repo.

**Cuando termines una sesión con hallazgos nuevos, revisa esta sección antes de cerrar** —
si algo quedó solo en el scratchpad de Claude Code, anótalo aquí para no perderlo.

## Pendiente de git

Nada — todo commiteado y pusheado al cierre de la sesión del 2026-07-13.

## Índice de los demás documentos

- `BUGS.md` — bugs y gotchas encontrados, con causa y fix.
- `IDEAS.md` — pendientes activos + ideas ya probadas y descartadas (no las repitas).
- `DECISIONES.md` — por qué se eligió cada pieza de la metodología.
- `GLOSARIO.md` — definición corta de cada término (tramo, avance, dayslate, etc.).
- `FUENTES_DATOS.md` — las 4 tablas de Athena del proyecto (3 base + la nueva de
  asignaciones), su grano y sus quirks.
- `LINAJE.md` — de qué sistema viene cada columna (Mambu, OkaAPI, o calculada internamente).
- `SEGUIMIENTO.md` — tabla mes a mes de proyectado vs. real (empieza con junio 2026).
- `plan_analisis.md` — bitácora cronológica completa (el historial crudo).
- `guia_tecnica_recupero.md` — guía técnica externa con SQL replicable.
- `enfoque_acumulado.md`, `enfoque_reinicio_reloj.md`, `enfoque_capital_asegurado.md`,
  `enfoque_salida_mora.md` — un archivo por enfoque, ver "Índice de enfoques" arriba.
- `avance_cobranza_fase.md` — análisis puntual por fase de cobranza, ver sección arriba.

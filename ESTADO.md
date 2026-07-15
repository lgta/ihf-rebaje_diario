# Estado actual

> Este archivo se **reescribe**, no crece. Si algo de acá cambia (una meta se recalcula,
> un artifact se actualiza, un pendiente se resuelve), se edita esta misma sección — no
> se agrega una entrada nueva al final. Para el historial cronológico completo, ver
> `plan_analisis.md`. Para saber por qué se decidió algo, ver `DECISIONES.md`.

Última actualización: 2026-07-14.

## La meta vigente

> **Desde 2026-07-13, la meta principal reportada es capital asegurado (Enfoque alfa)**,
> a pedido explícito del usuario — no el recupero en soles. El recupero oficial se sigue
> calculando y trackeando (sigue siendo válido, con su propio backtest +5.4%), pero ya no
> es el número que lidera esta sección. Ver `enfoque_capital_asegurado.md`.

> **2026-07-14 — corrección de definición antiguos/nuevos (bug 12, ver `BUGS.md`):** un
> crédito que entra en mora el DÍA 1 de un mes viene siempre de una cuota vencida el
> ÚLTIMO DÍA DEL MES ANTERIOR — es antiguo, no nuevo. Se corrigió en curvas, backtest y el
> tracking de julio de abajo (`avance_cobranza_fase.md`, el análisis por fase, **todavía
> no** se re-corrió con la definición nueva — pendiente). Efecto: el backtest de junio casi
> no se mueve (-4.7%→-4.4%), pero el **avance de julio sí cambia bastante** — el "adelanto"
> reportado antes (+36.8%) bajaba en gran parte de que el stock proyectado estaba
> subestimado (no incluía a los entrantes de día 1). Números corregidos abajo.

**Julio 2026, corte 13-jul — Capital asegurado:** meta proyectada **S/10,306,231** (stock
S/3,105,418 + nuevos S/7,200,813). Real asegurado a la fecha: **S/4,971,669** (48.2% de
avance del total del mes) — **+4.1% por encima de lo proyectado para el mismo día**
(proyección al día 13: S/4,776,792). Resta: S/5,334,562 (días 14-31). Fuente:
`avance_capital_asegurado_julio.py` + `datos_avance_capital_asegurado_julio/`. Curvas
calibradas y ya validadas con backtest de junio (-4.4% de error), ver
`enfoque_capital_asegurado.md`.

(Antes de la corrección: meta S/8,919,611, real S/4,969,508, 55.7% de avance, **+36.8%** de
adelanto — el real casi no cambió, lo que cambió fue la meta proyectada, que creció 15.5%
al corregir la población de stock.)

**Nuevo — tabla día a día (nuevos vs. antiguos), desde el 1-jul:** ver
`avance_capital_asegurado_julio_diario.sql` (queries D1-D4, incluye una consolidada D4 con
acumulados calculados en Athena) y `datos_avance_capital_asegurado_julio/tabla_diaria_alfa.csv`.
Nota: el capital asegurado de "hoy" (el día de corte) puede recalcularse y subir horas
después — es dato intradía de `dts_mambu_loans_hist` que sigue llegando durante el día, no
un error; los días ya cerrados no cambian.

**Nota de cautela:** el +4.1% de adelanto (ya con la definición corregida) es la lectura de
un solo mes a mitad de camino (día 13 de 31) — el backtest de junio (mes completo, cerrado)
dio -4.4%. Con datos tan parciales, la lectura puede diluirse o revertirse antes del
cierre; no hay base todavía para saber si es señal real o solo el patrón normal de que
julio arranca con más actividad de la típica. Seguir el avance semana a semana antes de
sacar conclusiones.

Metodología: modelo evento × magnitud, dos motores (stock anclado al cierre del mes
anterior UNION entrantes del día 1, nuevos vía calendario de vencimientos × P(no paga a
tiempo)=13.38% × curva de maduración, arrancando el día 2) — igual mecanismo que el
recupero oficial, solo que la curva mide "% de saldo con ≥1 pago" (capital asegurado) en
vez de "% recuperado". Detalle completo en `enfoque_capital_asegurado.md`.

### Recupero oficial (soles cobrados, se sigue trackeando en paralelo)

**Julio 2026, corte 9-jul:** meta total **S/1,776,174** (stock S/426,651 + nuevos
S/1,349,523). Real recuperado a la fecha: S/527,375 (29.7% de avance). Resta:
**S/1,248,799** (días 10-31). Fuente: `meta_julio.py` + `datos_meta_julio/`. Detalle
completo en `guia_tecnica_recupero.md` y en el artifact interactivo de abajo.

## Artifacts publicados

| Artifact | Estado | Contenido |
|---|---|---|
| [Metodología ejecutiva](https://claude.ai/code/artifact/909de8df-443f-4440-b85a-e39af636c8e7) | ✓ vigente | Modelo conceptual, curvas, backtest de junio |
| [Guía técnica](https://claude.ai/code/artifact/9df13c20-7758-4174-8346-ed6563d25c5d) | ✓ vigente | SQL replicable para Athena |
| [Meta en vivo — julio](https://claude.ai/code/artifact/52d8badf-bb51-4b92-a3c1-f4f2017aaa27) | ⚠ desactualizado | No refleja el fix de aged-out ni la investigación de dayslate |
| [Deck (11 slides)](https://claude.ai/code/artifact/ae2f5e71-ff14-48bd-af00-909b0aa634cf) | ⚠ desactualizado | Mismo motivo |
| [**Detalle con curvas interactivas**](https://claude.ai/code/artifact/71e5d69d-7586-4ba1-aedc-de7397eea425) | ✓ vigente, el más completo | Composición stock, calendario nuevos, curvas por avance, cohortes, trayectoria — todo con gráficos hover |
| [⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8) | ✓ vigente, es una advertencia | Registro de por qué la tasa oficial es 13.38% y no el complemento simple de "paga a tiempo" |
| [🔒 Capital asegurado](https://claude.ai/code/artifact/3a6b8cb9-0b2a-4dac-9569-473327a84b0a) | ⚠ desactualizado (números pre-bug 12) | Enfoque alfa, **meta principal de julio** — explicado con 5 créditos reales, curvas por segmento, backtest de junio y avance en vivo de julio. Números vigentes en `enfoque_capital_asegurado.md`/`ESTADO.md`, el artifact todavía tiene los de antes del fix del 2026-07-14 (bug 12) |
| [🔓 Salida de mora — hallazgos](https://claude.ai/code/artifact/f1b0c577-4044-40a3-bebd-e01f5141ed98) | ⚠ desactualizado | Enfoque beta — tiene los números de ANTES del fix de dedup (bug 11, `BUGS.md`: 513/364 → 376/363) y no incluye el hallazgo de reincidencia (80.8% recae). Ver `enfoque_salida_mora.md` |
| [🧭 Los 4 enfoques explicados](https://claude.ai/code/artifact/a75f705d-9522-4843-af77-d79ce90b047f) | ✓ vigente | Concepto + SQL explicado + un crédito real de Athena por cada uno de los 4 enfoques (acumulado, reinicio, capital asegurado, salida de mora). Ver `guia_4_enfoques.html` |
| [🔒 Curvas + matriz mensual](https://claude.ai/code/artifact/c8d733d5-f008-4f33-b4e6-e7712f1c4ece) | ✓ vigente (2026-07-15) | Enfoque alfa — curvas de maduración interactivas (antiguo por tramo, nuevos) + matriz mes a mes (mar-2025 a jul-2026) de asignado/asegurado/% por segmento, ya con la definición corregida (bug 12). Fuente: `curvas_matriz_alfa.html` + `matriz_mensual_alfa.sql` |

Los dos primeros más el de "Detalle" son los recomendados para compartir con el equipo.
Los "⚠ desactualizado" no tienen error, solo no incorporan los hallazgos más recientes —
no republicar sin actualizarlos primero.

## Índice de enfoques

> Todos los enfoques construidos hasta ahora, en un solo lugar — pensado para que una
> sesión futura pueda armar un markdown integral sin tener que releer todo el historial.
> Cada uno tiene su propio archivo `enfoque_*.md` con el detalle completo.

| Enfoque | Archivo | Qué mide | Estado |
|---|---|---|---|
| **Alfa — Capital asegurado** (meta principal desde 2026-07-13) | `enfoque_capital_asegurado.md` | % de capital con ≥1 pago en el mes (no soles recuperados) | ✅ Backtest -4.4% (jun-2026, definición corregida — bug 12), tracking en vivo de julio |
| Acumulado (recupero oficial, en paralelo) | `enfoque_acumulado.md` | Soles recuperados, mes completo anclado al cierre anterior | ✅ Validado, backtest +5.4% |
| Reinicio del reloj | `enfoque_reinicio_reloj.md` | Lo mismo, pero re-anclado a "hoy" | 🕓 Deprioritizado, no oficial |
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
  **⚠ Pendiente:** todavía usa la definición vieja de nuevo/stock (día 1 = nuevo, bug 12) —
  no se re-corrió, los números de este análisis puntual pueden cambiar.

## Pendiente de copiar al repo desde scratchpad

Nada por ahora — todo lo generado hasta el 2026-07-13 (backtest de capital asegurado,
investigación de reincidencia, avance por fase de cobranza) ya está en el repo.

**Cuando termines una sesión con hallazgos nuevos, revisa esta sección antes de cerrar** —
si algo quedó solo en el scratchpad de Claude Code, anótalo aquí para no perderlo.

## Pendiente de git

Sin commitear: actualización del artifact de capital asegurado (`capital_asegurado.html`
reescrito con 5 créditos reales + curvas + backtest + avance en vivo — ⚠ con números
pre-bug 12, falta re-generarlo), `ejemplos_capital_asegurado_5_creditos.sql`,
`datos_avance_capital_asegurado_julio/artifact_data.json`, las notas en
`ESTADO.md`/`README.md`, y lo nuevo de la tabla día a día: `avance_capital_
asegurado_julio_segmentado.py`/`.sql`, `avance_capital_asegurado_julio_diario.sql`.

**2026-07-14 — fix bug 12 (antiguos/nuevos, ver arriba y `BUGS.md`):** modificados
`enfoque_capital_asegurado.sql`, `enfoque_capital_asegurado_backtest.sql`,
`avance_capital_asegurado_julio.py`, `avance_capital_asegurado_julio_diario.sql`,
`avance_capital_asegurado_julio_segmentado.sql`, `backtest_capital_asegurado_junio.py`,
`GLOSARIO.md`, `enfoque_capital_asegurado.md`, `BUGS.md` (bug 12 nuevo); CSV
recalibrados/regenerados: `datos_capital_asegurado/curva_asegurado_stock_seg.csv`,
`curva_asegurado_nuevos_seg.csv`, `datos_backtest_junio/bt_stock_junio_aseg.csv` (nuevo),
`bt_real_aseg_stock.csv`, `bt_real_aseg_nuevos.csv`, y en
`datos_avance_capital_asegurado_julio/`: `tabla_diaria_alfa.csv`, `jul_aseg_real_stock.csv`,
`jul_aseg_real_nuevos.csv`, `jul_aseg_real_stock_seg.csv`, `jul_aseg_real_nuevos_seg.csv`,
`stock_julio_aseg_seg.csv` (nuevo). **Pendiente:** `avance_cobranza_fase.sql`/`.py` todavía
NO se re-corrieron con la definición corregida (ver nota arriba); el artifact
`capital_asegurado.html` tampoco se re-generó.

**2026-07-15 — artifact nuevo (curvas + matriz mensual):** `curvas_matriz_alfa.html`
(fuente del artifact publicado, ver tabla de arriba) y `matriz_mensual_alfa.sql` (las dos
queries que arman la matriz mes a mes, ya con la definición corregida). Pendiente de que
el usuario pida commitear.

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

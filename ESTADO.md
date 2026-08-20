# Estado actual

> Este archivo se **reescribe**, no crece. Si algo de acá cambia (una meta se recalcula,
> un artifact se actualiza, un pendiente se resuelve), se edita esta misma sección — no
> se agrega una entrada nueva al final. Para el historial cronológico completo, ver
> `plan_analisis.md`. Para saber por qué se decidió algo, ver `DECISIONES.md`.

Última actualización: 2026-08-20.

> **2026-08-20 — "capa fantasma" diseñada, validada con backtest en 2 meses cerrados, y
> ADOPTADA en producción (a pedido explícito del usuario):** el punto ciego de `dayslate`
> (bug 9) es 99.5% el mecanismo ya conocido, no uno nuevo (paso 1). Se diseñó una
> corrección quirúrgica (opción (a) completa, solo Enfoque alfa, no toca `13.38%` ni la
> curva existente — tasa nueva e independiente `P_FANTASMA=8.4534%`) y el backtest mostró
> mejora consistente en los 2 meses cerrados disponibles: **error total -4.4%→+0.7% en
> junio, -4.31%→+0.12% en julio** (esto último con un signo que estaba mal en
> `SEGUIMIENTO.md`, ya corregido). Aplicado a `enfoque_capital_asegurado.sql`/
> `_backtest.sql`, `backtest_capital_asegurado_junio.py`, `meta_agosto_capital_asegurado.py`
> y `SEGUIMIENTO.md` — ver bug 14 en `BUGS.md` y `reconciliacion_vw_seguimiento_
> temprana.md` ("Paso 2/3 — resultado") para el detalle completo. La meta de agosto
> cambia de forma material — ver "La meta vigente" abajo.

> **2026-08-19 — reconciliación contra vista oficial externa, punto ciego de `dayslate`
> cuantificado en ~27%:** ver bug 14 en `BUGS.md` y el plan de trabajo en
> `reconciliacion_vw_seguimiento_temprana.md`. Nuestra población de mora 1-30 cuadra casi
> exacto con la oficial (`vw_seguimiento_diario_cohorte_tramo`) donde ambas coinciden — el
> gap es de cobertura, no de cálculo.

> **2026-08-18 — homologación con `gestiones_cobranzas` + julio cerrado + meta de agosto:**
> ver bug 13 en `BUGS.md` (homologación de `tipo_mora`) y `SEGUIMIENTO.md` (cierre de julio,
> ambos enfoques). `dts_asignaciones_cobranza` quedó congelada desde 2026-07-10 — repuntado
> a `dts_asignaciones_gestiones_cobranza` en `avance_cobranza_fase.sql`/`FUENTES_DATOS.md`.
> El repo había estado ~1 mes sin actividad (último commit antes de hoy: `b0b5f73`,
> 2026-07-15) — ya resuelto: julio cerrado y agosto con meta + tracking en vivo (ver "La
> meta vigente" abajo). **Sigue pendiente:** re-correr `avance_cobranza_fase.md` con la
> definición corregida (bug 12, tarea 1 de `PENDIENTES.md`) — no se tocó en este cierre.

> **2026-07-15 — recorte de alcance a 2 enfoques:** a pedido explícito del usuario, el
> proyecto ahora solo mantiene el enfoque acumulado/oficial (rebaje, capital reducido) y
> el enfoque alfa (capital asegurado). "Reinicio del reloj" y "salida de mora" (beta) se
> descontinuaron y sus archivos se eliminaron del repo — ver `DECISIONES.md`. **Para
> completar lo pendiente de los 2 enfoques vigentes, ver [`PENDIENTES.md`](PENDIENTES.md)
> — es el documento de handoff, pensado para retomar sin releer todo este archivo.**

## La meta vigente

> **Desde 2026-07-13, la meta principal reportada es capital asegurado (Enfoque alfa)**,
> a pedido explícito del usuario — no el recupero en soles. El recupero oficial se sigue
> calculando y trackeando (sigue siendo válido, con su propio backtest +5.4%), pero ya no
> es el número que lidera esta sección. Ver `enfoque_capital_asegurado.md`.

> **2026-07-14 — corrección de definición antiguos/nuevos (bug 12, ver `BUGS.md`):** un
> crédito que entra en mora el DÍA 1 de un mes viene siempre de una cuota vencida el
> ÚLTIMO DÍA DEL MES ANTERIOR — es antiguo, no nuevo. Se corrigió en curvas y backtest.
> `avance_cobranza_fase.md` (el análisis por fase) **todavía no** se re-corrió con la
> definición nueva — pendiente (tarea 1, `PENDIENTES.md`).

> **2026-08-18 — julio cerrado, meta vigente pasa a agosto:** ver `SEGUIMIENTO.md` para el
> detalle de ambos cierres. Julio quedó con **+4.7% de error** en capital asegurado (stock
> +1.0%, nuevos +6.3%) y **+17.6%** en recupero oficial (stock +2.0%, nuevos +22.5% — el
> error más alto medido hasta ahora en este enfoque, ver nota de cautela abajo). Fuente:
> `cierre_julio.sql`.

**Agosto 2026, corte 18-ago — Capital asegurado (con capa fantasma, ver bug 14 en
`BUGS.md`):** meta proyectada **S/16,351,397** (stock S/2,956,828 + nuevos S/7,288,868 +
fantasma S/6,105,701). Real asegurado a la fecha: **S/9,622,765** (58.8% de avance del
total del mes) — **-1.8% por debajo de lo proyectado para el mismo día** (proyección al
día 18: S/9,795,613). Resta: S/6,728,632 (días 19-31). Fuente:
`meta_agosto_capital_asegurado.py` (v2) + `datos_avance_capital_asegurado_agosto/`. Curvas
calibradas y validadas con backtest de junio (**+0.7%** con capa fantasma, antes -4.4%) y
del cierre real de julio (**+0.1%** con capa fantasma, antes -4.3% — signo corregido, ver
`SEGUIMIENTO.md`), ver `enfoque_capital_asegurado.md`.

**2026-08-20 — cambio de metodología, no un cambio de tendencia:** la lectura de "+8.7%
adelantado" que se reportaba hasta hoy no incluía la capa fantasma (créditos que pagan 1
día tarde sin que `dayslate` los vea — bug 9/14). Al agregarla, tanto la meta como el real
crecen, pero la meta crece más (el calendario de vencimientos completo de agosto es mayor
que lo ya observado a la fecha) — el avance pasa a **-1.8%**, prácticamente en línea con lo
proyectado. Esto no es una señal nueva de deterioro: junio y julio (backtest en 2 meses
cerrados) muestran que con la capa fantasma el error total baja a ±1% en vez de ±4.4%, así
que la meta corregida es más confiable, no menos. Con solo 2 meses de cierre real (ambos
ahora con la misma metodología), todavía no hay base para saber si un futuro error tiende a
crecer o es varianza normal (ver tarea 9, `PENDIENTES.md`, extender el backtest a más
meses). Seguir el avance semana a semana antes de sacar conclusiones.

Metodología: modelo evento × magnitud, dos motores (stock anclado al cierre del mes
anterior UNION entrantes del día 1, nuevos vía calendario de vencimientos × P(no paga a
tiempo)=13.38% × curva de maduración, arrancando el día 2) — igual mecanismo que el
recupero oficial, solo que la curva mide "% de saldo con ≥1 pago" (capital asegurado) en
vez de "% recuperado". Detalle completo en `enfoque_capital_asegurado.md`.

### Recupero oficial (soles cobrados, se sigue trackeando en paralelo)

**Agosto 2026, corte 18-ago:** meta total **S/2,108,435** (stock S/711,160 + nuevos
S/1,397,275). Real recuperado a la fecha: S/1,147,110 (54.4% de avance) — **-1.5% respecto
a lo proyectado para el mismo día** (proyección al día 18: S/1,164,716). Resta:
**S/961,325** (días 19-31). Fuente: `meta_agosto.py` + `datos_meta_agosto/`. Julio cerró
con +17.6% de error (ver `SEGUIMIENTO.md`) — el error más alto medido hasta ahora en este
enfoque, concentrado en "nuevos" (+22.5%); agosto a mitad de mes va casi exacto (-1.5%), sin
señal todavía de que se repita. Detalle completo en `guia_tecnica_recupero.md` y en el
artifact interactivo de abajo.

## Artifacts publicados

| Artifact | Estado | Contenido |
|---|---|---|
| [Metodología ejecutiva](https://claude.ai/code/artifact/909de8df-443f-4440-b85a-e39af636c8e7) | ✓ vigente | Modelo conceptual, curvas, backtest de junio |
| [Guía técnica](https://claude.ai/code/artifact/9df13c20-7758-4174-8346-ed6563d25c5d) | ✓ vigente | SQL replicable para Athena |
| [Meta en vivo — julio](https://claude.ai/code/artifact/52d8badf-bb51-4b92-a3c1-f4f2017aaa27) | ⚠ desactualizado | No refleja el fix de aged-out ni la investigación de dayslate |
| [Deck (11 slides)](https://claude.ai/code/artifact/ae2f5e71-ff14-48bd-af00-909b0aa634cf) | ⚠ desactualizado | Mismo motivo |
| [**Detalle con curvas interactivas**](https://claude.ai/code/artifact/71e5d69d-7586-4ba1-aedc-de7397eea425) | ✓ vigente, el más completo | Composición stock, calendario nuevos, curvas por avance, cohortes, trayectoria — todo con gráficos hover |
| [⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8) | ✓ vigente, es una advertencia | Registro de por qué la tasa oficial es 13.38% y no el complemento simple de "paga a tiempo" |
| [🔒 Capital asegurado](https://claude.ai/code/artifact/3a6b8cb9-0b2a-4dac-9569-473327a84b0a) | ⚠ desactualizado (números pre-bug 12) | Enfoque alfa, **meta principal de julio** — explicado con 5 créditos reales, curvas por segmento, backtest de junio y avance en vivo de julio. Números vigentes en `enfoque_capital_asegurado.md`/`ESTADO.md`, el artifact todavía tiene los de antes del fix del 2026-07-14 (bug 12). **Pendiente en `PENDIENTES.md` tarea 2.** |
| [🔒 Curvas + matriz mensual](https://claude.ai/code/artifact/c8d733d5-f008-4f33-b4e6-e7712f1c4ece) | ✓ vigente (2026-07-15) | Enfoque alfa — curvas de maduración interactivas (antiguo por tramo, nuevos) + matriz mes a mes (mar-2025 a jul-2026) de asignado/asegurado/% por segmento, ya con la definición corregida (bug 12). Fuente: `curvas_matriz_alfa.html` + `matriz_mensual_alfa.sql` |
| De julio a agosto — cómo se arma la meta | ⚠ solo local, sin publicar | Guía paso a paso (curvas, asignación de julio, walkthrough completo de la meta de agosto), ambos enfoques con toggle. **Actualizado 2026-08-20** con la capa fantasma (bug 14) — julio ahora +0.1% de error (antes +4.7% con signo mal), agosto sube a meta S/16,351,397 y avance -1.8% al 18-ago. **Sin URL de claude.ai** — esta sesión tampoco tuvo la herramienta Artifact disponible para publicarlo; abrir directo `resumen_julio_agosto.html` en un navegador, o publicarlo desde una sesión que sí tenga esa herramienta. Fuente: `resumen_julio_agosto.html` + `armar_artifact_julio_agosto.py` + `datos_artifact_julio_agosto.json` |

Los dos primeros más el de "Detalle" son los recomendados para compartir con el equipo.
Los "⚠ desactualizado" no tienen error, solo no incorporan los hallazgos más recientes —
no republicar sin actualizarlos primero.

*(Los artifacts de "Salida de mora" y "Los 4 enfoques explicados" ya no están en esta
tabla — sus enfoques se descontinuaron 2026-07-15, ver `DECISIONES.md`. Los artifacts
siguen existiendo en claude.ai, solo dejaron de mantenerse.)*

## Índice de enfoques

> Todos los enfoques construidos hasta ahora, en un solo lugar — pensado para que una
> sesión futura pueda armar un markdown integral sin tener que releer todo el historial.
> Cada uno tiene su propio archivo `enfoque_*.md` con el detalle completo.

> **Solo estos 2 enfoques se mantienen desde 2026-07-15** (ver `DECISIONES.md`). "Reinicio
> del reloj" y "Beta — Salida de mora" se descontinuaron y sus archivos se eliminaron del
> repo (recuperables vía git history).

| Enfoque | Archivo | Qué mide | Estado |
|---|---|---|---|
| **Alfa — Capital asegurado** (meta principal desde 2026-07-13) | `enfoque_capital_asegurado.md` | % de capital con ≥1 pago en el mes (no soles recuperados) | ✅ Backtest +0.7% (jun) / +0.1% (jul) con capa fantasma (bug 14, 2026-08-20). Pendientes en `PENDIENTES.md` |
| Acumulado (recupero oficial, en paralelo) | `enfoque_acumulado.md` | Soles recuperados, mes completo anclado al cierre anterior | ✅ Validado, backtest +5.4%. Pendientes en `PENDIENTES.md` |
| Tasa 25% plano / motor cuota-consistente | ver `BUGS.md` bug 10 | Alternativas de `P(no paga a tiempo)` (respaldo de una decisión del enfoque acumulado, no es un enfoque propio) | ❌ Descartados por backtest (+66% a +81% / -35.7%) |

Detalle del último:
- ⚠️ **Descartado por backtest:** tasa plana 25-28% (sobreestima +66% a +81%); motor
  "cuota-consistente" con tasa 8.62% + curva propia (subestima -35.7%). Ver `BUGS.md` y
  `motor_cuota_vencimiento.sql`. No es un "enfoque" completo (solo toca la constante
  `P(no paga a tiempo)` del enfoque acumulado), por eso no tiene `enfoque_*.md` propio.

## Análisis puntuales (snapshots, no enfoques con curva propia)

- **Avance de julio por fase de cobranza** (`avance_cobranza_fase.md`, 2026-07-13): cruza
  la asignación REAL del negocio (tabla `dts_asignaciones_gestiones_cobranza` desde
  2026-08-18 — la original, `dts_asignaciones_cobranza`, quedó congelada el 2026-07-10, ver
  bug 13 en `BUGS.md` — contra capital asegurado (Enfoque alfa) por fase TEMPRANA /
  ESPECIALIZADA / RECOVERY × nuevo/stock. Corte 2-jul a 12-jul. Hallazgo: Temprana va
  ligeramente atrasada (-4 a -13pp según tramo, salvo 16-30 que va +2.7pp adelantado);
  Especializada/Recovery no tienen curva calibrada (el modelo nunca cubrió mora 31+).
  **⚠ Pendiente:** todavía usa la definición vieja de nuevo/stock (día 1 = nuevo, bug 12) —
  no se re-corrió, los números de este análisis puntual pueden cambiar.
- **Homologación con `gestiones_cobranzas`** (2026-08-18, `homologacion_tipo_mora_gestiones.sql`,
  bug 13 en `BUGS.md`): el `tipo_mora` de ese proyecto hermano valida el fix de bug 12 —
  98.5% de acuerdo con nuestra clasificación antiguo/nuevo en la población mora 1-30
  (muestra 10-ago). El 1.5% de diferencia es un comportamiento esperado (créditos que curan
  y recaen dentro del mes; este proyecto fija "stock" todo el mes por diseño). No requiere
  cambios al modelo.
- **Reconciliación contra `vw_seguimiento_diario_cohorte_tramo`** (2026-08-19/20, vista
  externa "oficial" aportada por el usuario, bug 14 en `BUGS.md`): nuestra población de
  mora 1-30 cuadra casi exacto (0.15%) con la oficial en los créditos que ambas comparten,
  pero el punto ciego de `dayslate` (bug 9) explica ~27% de TODA la población TEMPRANA
  oficial que no estábamos capturando. **✅ Resuelto 2026-08-20:** 99.5% es el mismo
  mecanismo de bug 9 (no un patrón nuevo) — corrección ("capa fantasma") diseñada,
  validada con backtest en 2 meses cerrados (+0.7%/+0.1%) y adoptada en producción. Ver
  `reconciliacion_vw_seguimiento_temprana.md` y "La meta vigente" arriba. Pendiente menor:
  extender la reconciliación de población a agosto, y decidir si aplica también al
  Enfoque acumulado (fuera de alcance por ahora).

## Pendiente de copiar al repo desde scratchpad

Nada por ahora — todo lo generado hasta el 2026-07-13 (backtest de capital asegurado,
investigación de reincidencia, avance por fase de cobranza) ya está en el repo.

**Cuando termines una sesión con hallazgos nuevos, revisa esta sección antes de cerrar** —
si algo quedó solo en el scratchpad de Claude Code, anótalo aquí para no perderlo.

## Pendiente de git

**2026-08-20:** cierre completo de la reconciliación (pasos 1/2/3), adopción en
producción de la capa fantasma, y refresco del artifact local julio-agosto. Archivos
nuevos: `reconciliacion_temprana.sql`, `investigacion_capa_fantasma.sql`,
`datos_backtest_junio/bt_real_fantasma_nuevos_junio.csv`. Archivos modificados:
`enfoque_capital_asegurado.sql` (Q3), `enfoque_capital_asegurado_backtest.sql`
(BT-ASEG-3), `backtest_capital_asegurado_junio.py` (v3), `meta_agosto_capital_
asegurado.py` (v2), `armar_artifact_julio_agosto.py`, `datos_artifact_julio_agosto.json`,
`resumen_julio_agosto.html`, `SEGUIMIENTO.md`, `enfoque_capital_asegurado.md`,
`reconciliacion_vw_seguimiento_temprana.md`, `BUGS.md`, `PENDIENTES.md`, este archivo.
Pendiente de que el usuario pida commitear (junto con lo del 2026-08-19, todavía sin
commitear: actualizaciones en `FUENTES_DATOS.md`/`README.md`).

## Índice de los demás documentos

- `BUGS.md` — bugs y gotchas encontrados, con causa y fix.
- `IDEAS.md` — pendientes activos + ideas ya probadas y descartadas (no las repitas).
- `DECISIONES.md` — por qué se eligió cada pieza de la metodología.
- `GLOSARIO.md` — definición corta de cada término (tramo, avance, dayslate, etc.).
- `FUENTES_DATOS.md` — las 4 tablas de Athena del proyecto (3 base + la nueva de
  asignaciones), su grano y sus quirks.
- `LINAJE.md` — de qué sistema viene cada columna (Mambu, OkaAPI, o calculada internamente).
- `SEGUIMIENTO.md` — tabla mes a mes de proyectado vs. real (empieza con junio 2026).
- `plan_analisis.md` — bitácora cronológica completa (el historial crudo, incluye el
  historial de los enfoques descontinuados).
- `guia_tecnica_recupero.md` — guía técnica externa con SQL replicable.
- `enfoque_acumulado.md`, `enfoque_capital_asegurado.md` — un archivo por enfoque (los
  únicos 2 vigentes), ver "Índice de enfoques" arriba.
- `avance_cobranza_fase.md` — análisis puntual por fase de cobranza, ver sección arriba.
- `reconciliacion_vw_seguimiento_temprana.md` — pendiente activo: reconciliación contra
  vista externa oficial, plan de trabajo para cerrar el punto ciego de `dayslate` (bug 14).
- `PENDIENTES.md` — plan de continuación accionable para los 2 enfoques vigentes.

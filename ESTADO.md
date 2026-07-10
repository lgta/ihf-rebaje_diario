# Estado actual

> Este archivo se **reescribe**, no crece. Si algo de acá cambia (una meta se recalcula,
> un artifact se actualiza, un pendiente se resuelve), se edita esta misma sección — no
> se agrega una entrada nueva al final. Para el historial cronológico completo, ver
> `plan_analisis.md`. Para saber por qué se decidió algo, ver `DECISIONES.md`.

Última actualización: 2026-07-10.

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
| [🔒 Capital asegurado](https://claude.ai/code/artifact/3a6b8cb9-0b2a-4dac-9569-473327a84b0a) | 🧪 experimental, sin backtest | Enfoque alfa — % del capital asignado con actividad de pago, no soles recuperados. Ver `enfoque_capital_asegurado.md` |

Los dos primeros más el de "Detalle" son los recomendados para compartir con el equipo.
Los "⚠ desactualizado" no tienen error, solo no incorporan los hallazgos más recientes —
no republicar sin actualizarlos primero.

## Qué está validado vs. qué es experimental

- ✅ **Validado por backtest** (junio 2026 real, +5.4% de error): el modelo oficial completo
  — stock por tramo×avance, nuevos por calendario×13.38%×avance.
- ⚠️ **Descartado por backtest, mantener como referencia:** tasa plana 25-28% (sobreestima
  +66% a +81%); motor "cuota-consistente" con tasa 8.62% + curva propia (subestima -35.7%).
  Ver `BUGS.md` y `motor_cuota_vencimiento.sql`.
- 🕓 **Deprioritizado, no oficial:** enfoque "reinicio del reloj" (`meta_desde_hoy.*`). El
  usuario aclaró (2026-07-10) que la meta oficial es siempre la del mes completo
  (`meta_julio.py`). No invertir tiempo ahí salvo pedido explícito.
- 🧪 **Experimental, construido pero sin backtest:** "capital asegurado" (enfoque alfa,
  `enfoque_capital_asegurado.md`) — % del capital asignado que muestra actividad de pago,
  no soles recuperados. Proyección de julio: S/8,919,611. No reportar hacia el negocio
  como KPI oficial hasta correrle un backtest (ver pendientes en su propio archivo).
- 🔬 **Exploratorio, patrón validado pero sin curva/proyección:** "salida de mora" (enfoque
  beta, `enfoque_salida_mora.md`) — distingue curas reales de curas sin pago (candidatas a
  reestructuración). Hallazgo: 364 créditos (S/1.2M) salen de mora sin bajar su saldo, y
  esos créditos tienen 75x más probabilidad de tener `motivo_apertura` registrado que una
  cura real (67.9% vs 0.9%) — confirma la hipótesis. Pendiente decidir siguiente paso.

## Pendiente de copiar al repo desde scratchpad

Nada por ahora — los archivos generados en la sesión del 2026-07-10 (motor cuota-consistente,
los dos artifacts nuevos) ya se copiaron: `meta_recupero_detalle.html`,
`julio_25pct_no_recomendado.html`, `motor_cuota_vencimiento.sql`, `investigacion_dayslate.sql`,
`backtest_motor_cuota.py`, `meta_julio_25pct.py`, `datos_motor_cuota/`, `scripts/run_athena.sh`.

**Cuando termines una sesión con hallazgos nuevos, revisa esta sección antes de cerrar** —
si algo quedó solo en el scratchpad de Claude Code, anótalo aquí para no perderlo.

## Pendiente de git

Todo el trabajo hasta el commit `6dc0296` (fix del bug aged-out) está pusheado y verificado.
**Todo lo de esta sesión (2026-07-10) — los 8 markdown nuevos, los archivos recién copiados,
las correcciones a `plan_analisis.md`/`README.md` — no está commiteado.** El usuario controla
el push (ver `CLAUDE.md`).

## Índice de los demás documentos

- `BUGS.md` — bugs y gotchas encontrados, con causa y fix.
- `IDEAS.md` — pendientes activos + ideas ya probadas y descartadas (no las repitas).
- `DECISIONES.md` — por qué se eligió cada pieza de la metodología.
- `GLOSARIO.md` — definición corta de cada término (tramo, avance, dayslate, etc.).
- `FUENTES_DATOS.md` — las 3 tablas de Athena que se usan siempre, su grano y sus quirks.
- `SEGUIMIENTO.md` — tabla mes a mes de proyectado vs. real (empieza con junio 2026).
- `plan_analisis.md` — bitácora cronológica completa (el historial crudo).
- `guia_tecnica_recupero.md` — guía técnica externa con SQL replicable.

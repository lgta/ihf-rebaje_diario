# Estado actual

> Este archivo se **reescribe**, no crece. Si algo de acá cambia (una meta se recalcula,
> un artifact se actualiza, un pendiente se resuelve), se edita esta misma sección — no
> se agrega una entrada nueva al final. Para el historial cronológico completo, ver
> `plan_analisis.md`. Para saber por qué se decidió algo, ver `DECISIONES.md`.

Última actualización: 2026-08-21.

> **2026-08-21 (continuación, 4ta vuelta) — `homologacion_tipo_mora_gestiones.sql` (bug
> 13) re-verificado con `aux02`, bajo impacto CONFIRMADO (no solo esperado). Los 3 archivos
> del proyecto que cruzan contra `dts_asignaciones_gestiones_cobranza` quedan corregidos —
> no queda ningún uso del crosswalk `dni`+`producto` viejo en el repo.** Re-corrido Q1/Q2/Q3
> con `aux02`: el acuerdo del día representativo (10-ago) pasa de 98.52% a **98.49%**
> (897+929=1,826/1,854 vs. 917+947=1,864/1,892 antes) — prácticamente idéntico, y **los
> mismos 28 casos exactos** de desacuerdo (0 en la dirección opuesta, igual que antes). La
> población matcheada baja levemente (-2%) — `aux02` a veces referencia un eslabón anterior
> de una cadena de reenganche en vez del vigente, diferencia menor que no cambia ninguna
> conclusión de bug 13. Ver bug 15 en `BUGS.md` para el detalle completo.

> **2026-08-21 (continuación, 3ra vuelta) — desplegado el fix de `aux02` (bug 15) a
> `avance_cobranza_fase.sql`, tarea 1 de `PENDIENTES.md` CERRADA.** A pedido del usuario,
> se re-corrió `avance_cobranza_fase.sql` con 3 fixes juntos: bug 15 (`aux02` en vez del
> crosswalk `dni`+`producto` — cohorte crece de 8,303 a 8,614 créditos, +3.7%, concentrado
> en TEMPRANA), bug 12 (día 1 de julio = antiguo/stock, no nuevo — nunca se había aplicado
> a este archivo; "nuevo" baja de 1,258 a 571 créditos, la mayoría del bucket viejo eran
> entrantes de día 1 mal clasificados) y bug 11 (dedup, exigido por `CLAUDE.md` para
> cualquier `row_number()`/`lag()` nuevo sobre `dts_mambu_loans_hist`, este archivo tampoco
> lo tenía). Verificado: la tasa `13.38%`/`P_FANTASMA` y las curvas de maduración **no se
> ven afectadas** por ninguno de estos hallazgos — se calibran exclusivamente contra
> `dts_mambu_loans_hist`/`dts_cobranza_creditos_cuotas`, sin ninguna dependencia de
> `dts_asignaciones_gestiones_cobranza` (confirmado con grep en los archivos de
> calibración/backtest/meta, 0 referencias). Con los 3 fixes, la lectura de avance de
> Temprana cambia de "atrasada" a "adelantada" en el segmento nuevo (+6.6pp vs. -4.3pp
> antes) — es un cambio de clasificación, no una señal nueva de que el ritmo de pago real
> cambió. Especializada/Recovery casi no se movieron (tienen poco saldo dentro de mora
> 1-30, donde pegan estos fixes). Sin impacto en la meta vigente de agosto. Ver
> `avance_cobranza_fase.md` para el detalle completo y la tabla de resultados actualizada.
> **Queda pendiente, menor prioridad:** revisar `homologacion_tipo_mora_gestiones.sql`
> (bug 13) con el mismo fix — impacto esperado bajo (ya daba 98.5% de acuerdo).

> **2026-08-21 (continuación, 2da vuelta) — Q7/Q8 de la reconciliación TEMPRANA
> verificadas como SQL ejecutable real, los 2 huecos de "solo nuestro" investigados, y
> hallazgo mayor de metodología: `dts_asignaciones_gestiones_cobranza` SÍ tiene
> `id_ihfintech_loan` directo (columna `aux02`) — corregido y aplicado.** A pedido
> explícito del usuario, se relanzó el cálculo desde cero contra Athena (sin confiar en el
> CSV guardado): Q7/Q8 nunca habían quedado como SQL real en el repo (solo pseudocódigo) —
> re-corridas, dan **3,265/3,265 y 1,246/1,246 filas idénticas** al CSV ya commiteado a
> nivel crédito — sin no-determinismo de bug 11, sin drift de datos. Al investigar "Sin
> asignar" (367 créditos), se encontró primero un bug de matching (crosswalk
> `dni`+`producto` con filtro `status='ACTIVE'` demasiado estricto) y luego, señalado por
> el usuario, algo más grande: la tabla **SÍ tiene el ID de crédito directo** en una
> columna sin nombre descriptivo (`aux02`) — verificado con Athena (99.97% de match real,
> mejor que el ~96.5% del crosswalk que el proyecto venía usando desde bug 13). **Corregido
> y aplicado en el mismo día:** `FUENTES_DATOS.md`, `reconciliacion_temprana.sql` (Q11/Q12
> reemplazan a Q6/Q8) y el CSV `solo_nuestro_motivo_julio.csv` regenerado — números
> finales: Grupo de control 1,017 (antes 779), Sin asignar 120 (antes 367), Doble producto
> en otra fase 65 (antes 58), Escalado fase fija 36 (igual), Revisar 8 (antes 6, ese motivo
> resultó ser además un artefacto de anclaje de fecha, no un hueco real — no relacionado al
> fix de `aux02`). Con esto, **TEMPRANA queda completamente cerrada**. **Pendiente, fuera
> de esta pasada:** aplicar el mismo fix de `aux02` en `avance_cobranza_fase.sql` (ya
> pendiente por bug 12) y revisar `homologacion_tipo_mora_gestiones.sql` (bug 13, bajo
> impacto esperado). Sin cambios a producción de la meta vigente de agosto. Ver bug 15 en
> `BUGS.md` y `reconciliacion_vw_seguimiento_temprana.md` pendiente 4 para el detalle
> completo, y `reconciliacion_temprana.sql` Q7-Q12 para las queries reales.

> **2026-08-21 (continuación) — cobertura de agosto de la capa fantasma: hipótesis de
> timing confirmada, no hay hueco nuevo.** El 81.8% de cobertura (vs. 99.7% julio,
> `reconciliacion_agosto.sql` Q3) se desagregó por `installmentstate` (Q4): **98.3% de
> los 412 no cubiertos todavía no pagan su cuota** (timing de mitad de mes, julio ya
> tiene todos los desenlaces resueltos y agosto no) — solo 1.7% (7 créditos, S/6,704) es
> un hueco real, volumen despreciable. Sin cambios a producción (no bloqueante). Ver bug
> 14 en `BUGS.md` y `reconciliacion_vw_seguimiento_temprana.md` pendiente 2.

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

> **2026-08-20 (mismo día) — bug 11 (filas duplicadas) validado y aplicado a Enfoque
> alfa:** la regla mejorada de dedup (saldo≠0 antes de `lastmodifieddate`) se validó
> contra los 687 casos conflictivos completos de la historia (no solo la muestra de 16) —
> 100% de las referencias no-ambiguas disponibles confirman el saldo no-cero. Aplicada a
> `enfoque_capital_asegurado.sql`/`_backtest.sql`/`cierre_julio.sql`. Backtest re-corrido:
> junio sube de +0.7% a **+2.2%** (nuevos -8.6%→-5.8%); julio no se movió (0 filas
> duplicadas relevantes en su ventana). Ver bug 11 en `BUGS.md` y `SEGUIMIENTO.md`. La meta
> de agosto (curvas Q1/Q2) se movió <1pp — no se recalculó (bajo impacto confirmado).

> **2026-08-20 (mismo día) — reconciliación TEMPRANA CERRADA, los 5 pendientes
> resueltos:** los pendientes 2-5 de `reconciliacion_vw_seguimiento_temprana.md` quedaron
> resueltos: (b) el ~27% de punto ciego no repite igual en el agregado de agosto a mitad de
> mes (19.1% al corte 20-ago) pero sí por cohorte (nuevos: 30.0%, mayor que julio) — hay
> que re-medir cuando agosto cierre. Reenganches (313 créditos) quedan documentados como
> diferencia de alcance deliberada (decidido con el usuario). El pendiente 1 (capa fantasma
> a nivel crédito) encontró que solo cubría 90.7% directo (no 100%) por un hueco de
> frontera de mes — **fix adoptado en producción**: cobertura 90.7%→99.7%, y la tasa
> `P_FANTASMA` se recalibró junto con el fix (8.4534%→8.5524%, misma definición de
> "periodo" en tasa y calendario). Backtest final: junio +2.2%→+2.65%, julio
> +0.12%→+2.17% (ambos buenos números, motivo del alza: dilución por solapamiento con
> otros eventos de mora, no un error) — ver bug 14 en `BUGS.md` para el detalle completo.

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

**Agosto 2026, corte 18-ago — Capital asegurado (con capa fantasma, tasa recalibrada y fix
de frontera de mes, ver bug 14 en `BUGS.md`):** meta proyectada **S/16,410,194** (stock
S/2,951,390 + nuevos S/7,269,629 + fantasma S/6,189,175, incluye 77 créditos/S/140,194 del
31-jul). Real asegurado a la fecha: **S/9,626,322** (58.7% de avance del total del mes) —
**-2.1% por debajo de lo proyectado para el mismo día**. Resta: S/6,783,872 (días 19-31).
Fuente: `meta_agosto_capital_asegurado.py` (v3) + `datos_avance_capital_asegurado_agosto/`.
Curvas calibradas y validadas con backtest de junio (**+2.65%** con capa fantasma + dedup
de bug 11 + tasa `P_FANTASMA` recalibrada, antes +2.2% con la tasa vieja, +0.7% sin el
dedup, -4.4% sin ninguna corrección) y del cierre real de julio (**+2.17%**, antes +0.12%
con la tasa vieja — ver `SEGUIMIENTO.md` para el detalle completo del porqué sube). Las
curvas de este archivo (Q1/Q2) no se recalcularon con el dedup de bug 11 — el impacto
medido en las curvas fue <1pp, bajo impacto confirmado (ver bug 11 en `BUGS.md`), no se
justificó rehacer la meta de agosto por esto.

**2026-08-20 — cambio de metodología, no un cambio de tendencia:** la lectura de "+8.7%
adelantado" que se reportaba antes de esta sesión no incluía la capa fantasma (créditos
que pagan 1 día tarde sin que `dayslate` los vea — bug 9/14). Al agregarla (con su fix de
frontera de mes y tasa recalibrada), tanto la meta como el real crecen, pero la meta crece
más (el calendario de vencimientos completo de agosto es mayor que lo ya observado a la
fecha) — el avance pasa a **-2.1%**, prácticamente en línea con lo proyectado. Esto no es
una señal nueva de deterioro: junio y julio (backtest en 2 meses cerrados) muestran que con
la capa fantasma completa el error total baja a ±2.65% en vez de ±4.4%, así que la meta
corregida es más confiable, no menos. Con solo 2 meses de cierre real (ambos ahora con la
misma metodología), todavía no hay base para saber si un futuro error tiende a crecer o es
varianza normal (ver tarea 9, `PENDIENTES.md`, extender el backtest a más meses). Seguir el
avance semana a semana antes de sacar conclusiones.

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
| De julio a agosto — cómo se arma la meta | ✓ vigente (2026-08-21), sin publicar | Guía paso a paso (curvas, asignación de julio, walkthrough completo de la meta de agosto), ambos enfoques con toggle. **Actualizado 2026-08-21** con el fix de frontera de mes + tasa `P_FANTASMA` recalibrada (bug 14): julio +2.17%/meta agosto S/16,410,194/avance -2.1%. Agregada **sección 4 "Diferencias con la reconciliación"** — explica el punto ciego de `dayslate`, la capa fantasma, el fix de frontera y por qué julio sube más que junio (dilución por solapamiento). **Sin URL de claude.ai** — no hay herramienta Artifact disponible en esta sesión; abrir directo `resumen_julio_agosto.html` en un navegador, o publicarlo desde una sesión con esa herramienta. Fuente: `resumen_julio_agosto.html` + `armar_artifact_julio_agosto.py` + `datos_artifact_julio_agosto.json` |

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
| **Alfa — Capital asegurado** (meta principal desde 2026-07-13) | `enfoque_capital_asegurado.md` | % de capital con ≥1 pago en el mes (no soles recuperados) | ✅ Backtest +2.65% (jun) / +2.17% (jul) con capa fantasma completa (bug 14: tasa recalibrada + fix de frontera de mes) + dedup bug 11, todos 2026-08-20. Pendientes en `PENDIENTES.md` |
| Acumulado (recupero oficial, en paralelo) | `enfoque_acumulado.md` | Soles recuperados, mes completo anclado al cierre anterior | ✅ Validado, backtest +5.4%. Pendientes en `PENDIENTES.md` |
| Tasa 25% plano / motor cuota-consistente | ver `BUGS.md` bug 10 | Alternativas de `P(no paga a tiempo)` (respaldo de una decisión del enfoque acumulado, no es un enfoque propio) | ❌ Descartados por backtest (+66% a +81% / -35.7%) |

Detalle del último:
- ⚠️ **Descartado por backtest:** tasa plana 25-28% (sobreestima +66% a +81%); motor
  "cuota-consistente" con tasa 8.62% + curva propia (subestima -35.7%). Ver `BUGS.md` y
  `motor_cuota_vencimiento.sql`. No es un "enfoque" completo (solo toca la constante
  `P(no paga a tiempo)` del enfoque acumulado), por eso no tiene `enfoque_*.md` propio.

## Análisis puntuales (snapshots, no enfoques con curva propia)

- **Avance de julio por fase de cobranza** (`avance_cobranza_fase.md`, ejecutado
  2026-07-13, **re-corrido 2026-08-21**): cruza la asignación REAL del negocio (tabla
  `dts_asignaciones_gestiones_cobranza`) contra capital asegurado (Enfoque alfa) por fase
  TEMPRANA / ESPECIALIZADA / RECOVERY × nuevo/stock. Corte 2-jul a 12-jul (misma ventana en
  ambas corridas). **✅ Tarea 1 de `PENDIENTES.md` CERRADA** — re-corrido con 3 fixes: bug
  12 (día 1 = antiguo/stock, no nuevo — nunca se había aplicado a este archivo, cohorte
  "nuevo" bajó de 1,258 a 571 créditos), bug 15 (`aux02` en vez del crosswalk
  `dni`+`producto`, cohorte total creció de 8,303 a 8,614 créditos) y bug 11 (dedup, este
  archivo tampoco lo tenía). Con los fixes, Temprana pasa de verse uniformemente atrasada a
  mostrar "nuevo" +6.6pp adelantado (antes -4.3pp) — la lectura cambió porque se redefinió
  qué créditos caen en cada categoría, no porque el ritmo de pago real haya cambiado.
  Especializada/Recovery siguen sin curva calibrada (el modelo nunca cubrió mora 31+), sin
  cambio material ahí. Ver bug 15 en `BUGS.md` y `avance_cobranza_fase.md` para el detalle
  completo.
- **Homologación con `gestiones_cobranzas`** (2026-08-18, `homologacion_tipo_mora_gestiones.sql`,
  bug 13 en `BUGS.md`): el `tipo_mora` de ese proyecto hermano valida el fix de bug 12 —
  98.5% de acuerdo con nuestra clasificación antiguo/nuevo en la población mora 1-30
  (muestra 10-ago). El 1.5% de diferencia es un comportamiento esperado (créditos que curan
  y recaen dentro del mes; este proyecto fija "stock" todo el mes por diseño). No requiere
  cambios al modelo. **Re-verificado 2026-08-21 con el fix de `aux02` (bug 15):** 98.49% de
  acuerdo (prácticamente idéntico) y los mismos 28 casos exactos de desacuerdo — bajo
  impacto confirmado, no solo esperado.
- **Reconciliación contra `vw_seguimiento_diario_cohorte_tramo`** (2026-08-19/20, vista
  externa "oficial" aportada por el usuario, bug 14 en `BUGS.md`): nuestra población de
  mora 1-30 cuadra casi exacto (0.15%) con la oficial en los créditos que ambas comparten,
  pero el punto ciego de `dayslate` (bug 9) explica ~27% de TODA la población TEMPRANA
  oficial que no estábamos capturando. **✅ Resuelto 2026-08-20:** 99.5% es el mismo
  mecanismo de bug 9 (no un patrón nuevo) — corrección ("capa fantasma") diseñada,
  validada con backtest en 2 meses cerrados y adoptada en producción, incluyendo un
  segundo fix (frontera de mes + tasa `P_FANTASMA` recalibrada) encontrado al verificar a
  nivel crédito. Números finales: **+2.65%/junio, +2.17%/julio**. **TEMPRANA cerrada
  2026-08-20** (los 5 pendientes de cierre resueltos, ver `reconciliacion_vw_seguimiento_
  temprana.md`): (a) la verificación a nivel crédito encontró que la capa fantasma
  original cubría solo 90.7% directo del bucket bug9 — el 9.3% restante era el mismo
  mecanismo pero con un hueco de frontera de mes (cuota vencida el último día del mes
  anterior), análogo a bug 12 — **corregido, cobertura ahora 99.7%**; (b) el ~27% no
  repite igual en agosto a mitad de mes (19.1% agregado al 20-ago) pero sí por cohorte
  (nuevos: 30.0%, más alto que julio) — hay que re-medir cuando agosto cierre. Reenganches
  (313 créditos) quedan documentados como diferencia de alcance deliberada, decidido con
  el usuario. Aplicar la capa fantasma al Enfoque acumulado sigue fuera de alcance.

  **2026-08-21 — dataset filtrable por crédito + corrección verificada:** se generaron
  `datos_reconciliacion_temprana/solo_oficial_motivo_julio.csv` y
  `solo_nuestro_motivo_julio.csv` (1 fila por crédito, columna `motivo`, vía Q7/Q8 de
  `reconciliacion_temprana.sql`) para poder filtrar los motivos de diferencia en vez de
  solo ver el agregado. Al verificar el motivo "escalado a Especializada/Recovery" se
  encontró que la hipótesis de "arrastre de DNI" era **falsa** (94/94 son el único
  crédito de su `dni`+`producto`, sin hermano) — el motivo real es una **fase fija/
  "pegajosa"** en `gestiones_cobranza` que no baja aunque `dayslate` muestre mora fresca.
  Ver bug 13 en `BUGS.md` para el detalle.

  **2026-08-21 (continuación) — Q7/Q8 verificadas como SQL real, los 2 huecos restantes
  cerrados, y hallazgo mayor de metodología (`aux02`) corregido — TEMPRANA completamente
  cerrada:** Q7/Q8 nunca habían quedado como SQL ejecutable en el repo — re-corridas
  contra Athena, reproducen exacto los 2 CSV ya commiteados a nivel crédito. Al investigar
  "Sin asignar" (367 créditos) se encontró primero un bug de matching (crosswalk
  `dni`+`producto` con filtro `status='ACTIVE'` demasiado estricto) y luego, señalado por
  el usuario, que `dts_asignaciones_gestiones_cobranza` **sí tiene `id_ihfintech_loan`
  directo** en una columna sin nombre descriptivo (`aux02`, 99.97% de match verificado) —
  mejor que el crosswalk `dni`+`producto` que el proyecto venía usando desde bug 13.
  **Corregido y aplicado:** Q11/Q12 reemplazan a Q6/Q8, CSV regenerado — Grupo de control
  1,017 (antes 779), Sin asignar 120 (antes 367), Doble producto en otra fase 65 (antes
  58), Escalado fase fija 36 (igual), Revisar 8 (antes 6, artefacto de anclaje de fecha,
  no relacionado al fix). Ver bug 15 en `BUGS.md` para el detalle completo y
  `reconciliacion_temprana.sql` Q9-Q12 para las queries. **Pendiente:** aplicar el mismo
  fix en `avance_cobranza_fase.sql` y revisar `homologacion_tipo_mora_gestiones.sql`.

## Pendiente de copiar al repo desde scratchpad

Nada por ahora — todo lo generado hasta el 2026-07-13 (backtest de capital asegurado,
investigación de reincidencia, avance por fase de cobranza) ya está en el repo.

**Cuando termines una sesión con hallazgos nuevos, revisa esta sección antes de cerrar** —
si algo quedó solo en el scratchpad de Claude Code, anótalo aquí para no perderlo.

## Prompt de continuación

> La reconciliación TEMPRANA (bug 14), la tarea 1 de `PENDIENTES.md`
> (`avance_cobranza_fase.sql`, bugs 11/12/15) y la re-verificación de
> `homologacion_tipo_mora_gestiones.sql` (bug 13/15) quedan **completamente cerradas** con
> esta continuación — el hallazgo de `aux02` (bug 15) ya está desplegado en los 3 archivos
> del proyecto que lo necesitaban, no queda ningún pendiente de este tema. No hay un prompt
> de retoma específico. Para el resto, ver `PENDIENTES.md` y la nota de re-medir la
> cobertura de agosto de la capa fantasma cuando el mes cierre (día 31), ya anotada arriba
> en "La meta vigente".

## Pendiente de git

**Sí hay pendiente:** esta continuación (4ta vuelta, 2026-08-21) agregó:
`homologacion_tipo_mora_gestiones.sql` (Q1/Q2/Q3) corregido con `aux02` (bug 15), cerrando
el último de los 3 archivos que usaban el crosswalk `dni`+`producto` viejo — re-verificado
que el 98.5% de acuerdo con `gestiones_cobranzas` (bug 13) se mantiene prácticamente
idéntico (98.49%, mismos 28 casos de desacuerdo); y las actualizaciones de `BUGS.md`
(bug 15) / `ESTADO.md` que cierran ese hallazgo. **Todo lo de la vuelta anterior de esta
misma sesión (Q7-Q12 de `reconciliacion_temprana.sql`, fix de `avance_cobranza_fase.sql`,
`FUENTES_DATOS.md`, `PENDIENTES.md` tarea 1) ya está commiteado y pusheado**
(commit `ef5f717`).

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
- `reconciliacion_vw_seguimiento_temprana.md` — reconciliación contra vista externa
  oficial, punto ciego de `dayslate` (bug 14) — **5/5 pendientes cerrados 2026-08-20**. SQL
  en `reconciliacion_temprana.sql` (julio), `reconciliacion_agosto.sql` (agosto) e
  `investigacion_frontera_mes_fantasma.sql` (hueco de frontera de mes, fix adoptado).
- `PENDIENTES.md` — plan de continuación accionable para los 2 enfoques vigentes.

# Pendientes — plan de continuación

> Este archivo es para que alguien que recién llega al proyecto sepa **exactamente qué
> hacer**, sin releer todo el historial. Léelo junto con `ESTADO.md` (foto del momento
> vigente) y `BUGS.md` (gotchas ya encontrados — varios de estos pueden hacerte perder
> horas si los repites). `DECISIONES.md` explica el *por qué* de cada pieza de la
> metodología si algo no se explica acá.

## Qué pasó el 2026-07-15

El proyecto tenía 4 líneas de análisis. A pedido explícito del usuario se acotó a **2**:

- **Enfoque acumulado** (a veces referido como "rebaje" o "capital reducido") — el
  recupero oficial en soles. Ver `enfoque_acumulado.md`.
- **Enfoque alfa** (capital asegurado) — **meta principal** desde 2026-07-13. Ver
  `enfoque_capital_asegurado.md`.

Se descontinuaron "reinicio del reloj" y el enfoque beta "salida de mora" — sus archivos
se eliminaron del repo (recuperables vía `git log`/`git show` de cualquier commit anterior
a esta limpieza). Ver `DECISIONES.md` para el detalle de esa decisión. **No hay tareas
pendientes de esos 2 enfoques en este documento** — si algo de abajo te hace pensar en
"reinicio del reloj" o "salida de mora", no es parte del alcance actual.

---

## Enfoque Alfa — Capital asegurado (meta principal)

### Tarea 1 — Re-correr `avance_cobranza_fase` con la definición corregida (bug 12)
**Archivos:** `avance_cobranza_fase.sql`, `avance_cobranza_fase.py`, `avance_cobranza_fase.md`.

**Contexto:** el 2026-07-14 se corrigió un bug (bug 12 en `BUGS.md`) en la clasificación
antiguos/nuevos del Enfoque alfa: un crédito que entra en mora el día 1 de un mes es
"antiguo" (su cuota venció el último día del mes anterior), no "nuevo". El fix ya se
aplicó a `enfoque_capital_asegurado.sql` (Q1/Q2) y a `enfoque_capital_asegurado_backtest.sql`
(BT-ASEG-0/1/2), pero **`avance_cobranza_fase.sql` todavía usa la definición vieja**.

**Qué hacer:** aplicar el mismo patrón (UNION de los entrantes de día 1 al stock, en vez
de re-anclar toda la población — ¡ojo con el "intento fallido" documentado en bug 12,
re-anclar toda la población causa sesgo de supervivencia!) a este archivo, re-correr
contra Athena (`scripts/run_athena.sh`), actualizar la agregación en `.py` y los números
en `avance_cobranza_fase.md`. **Ya aplicado (2026-08-18):** el SQL se repuntó a
`dts_asignaciones_gestiones_cobranza` (la tabla vieja, `dts_asignaciones_cobranza`, quedó
congelada el 2026-07-10 — ver bug 13 en `BUGS.md`); falta todavía el fix de bug 12 en sí y
re-correr/actualizar `.py`/`.md`.

**Criterio de terminado:** los números de avance por fase (Temprana/Especializada/
Recovery × nuevo/stock) en `avance_cobranza_fase.md` reflejan la definición corregida;
la nota "⚠ Pendiente" de `ESTADO.md` sección "Análisis puntuales" se puede quitar.

### Tarea 2 — Refrescar el artifact `capital_asegurado.html`
**Archivo:** `capital_asegurado.html` (ya reescrito con 5 créditos reales + curvas +
backtest + avance en vivo, pero con **números pre-bug-12**).

**Qué hacer:** actualizar los números del artifact con los vigentes en
`enfoque_capital_asegurado.md`/`ESTADO.md`: backtest de junio -4.4% (stock +7.2%, nuevos
-8.6%), avance de julio +4.1% al corte del día 13 (meta S/10,306,231, real S/4,971,669).
Republicar vía la herramienta Artifact usando la misma URL
(`https://claude.ai/code/artifact/3a6b8cb9-0b2a-4dac-9569-473327a84b0a`). Copiar el
archivo fuente actualizado al repo (ya está ahí, solo hay que sobreescribirlo — es la
convención del proyecto, ver `CLAUDE.md`). Actualizar su estado de "⚠ desactualizado" a
"✓ vigente" en las tablas de `README.md` y `ESTADO.md`.

**Criterio de terminado:** el artifact muestra los mismos números que `ESTADO.md`; ambas
tablas (README/ESTADO) dicen "✓ vigente".

### Tarea 3 — Aplicar el fix de bug 11 (filas duplicadas) a `enfoque_capital_asegurado.sql`
**Contexto:** bug 11 (`BUGS.md`) encontró 1,316 combinaciones (crédito, día) con filas
duplicadas en `dts_mambu_loans_hist` que rompen el patrón `row_number() over (partition by
id_loan order by fechaproceso)` si no hay desempate. Ya se corrigió en
`enfoque_salida_mora.sql` (eliminado junto con ese enfoque) pero **nunca se aplicó a
`enfoque_capital_asegurado.sql`**, que usa el mismo patrón sin desempate.

**Qué hacer:** agregar el dedup determinista (`row_number() over (partition by id_loan,
fechaproceso order by lastmodifieddate desc, id desc)` antes de calcular `rn`/`grp`) y
re-correr el backtest de junio para confirmar que el error no cambia materialmente
(se espera bajo impacto — es sobre agregados de saldo, no conteo de episodios discretos,
a diferencia de `enfoque_salida_mora.sql` donde sí cambió 513→376 episodios).

**Criterio de terminado:** backtest re-corrido, diferencia documentada en `BUGS.md` (aunque
sea "no cambió", para cerrar el pendiente del punto 11 de `IDEAS.md`).

### Tarea 4 — ~~Seguir el tracking en vivo de julio y cerrar la fila de `SEGUIMIENTO.md`~~ hecho 2026-08-18
Julio cerró con **+4.7% de error** (stock +1.0%, nuevos +6.3%) — ver `SEGUIMIENTO.md` y
`cierre_julio.sql`. Meta de agosto ya armada y en tracking (`meta_agosto_capital_
asegurado.py`, `datos_avance_capital_asegurado_agosto/`) — nueva tarea abajo (Tarea 4b).

### Tarea 4b — Cerrar la fila de agosto en `SEGUIMIENTO.md` cuando termine el mes
Meta proyectada S/10,245,695 (stock S/2,956,828 + nuevos S/7,288,868) vs. real final.
Fuente: `meta_agosto_capital_asegurado.py` + `datos_avance_capital_asegurado_agosto/`.

---

## Enfoque Acumulado — Recupero oficial (rebaje / capital reducido)

### Tarea 5 — Decidir destino de los artifacts desactualizados
**Artifacts:** "Meta en vivo — julio" (`meta_julio_en_vivo.html`) y "Deck completo"
(`deck_meta_recupero.html`).

**Contexto:** están desactualizados desde ANTES del bug 12 — les falta el fix de
"aged-out survivors" (bug 7) y los hallazgos de la investigación de `dayslate` (bug 9).
El bug 12 (antiguos/nuevos en el corte de mes) **no aplica a este enfoque** — su scope
fue explícitamente solo `enfoque_capital_asegurado*.sql` (ver bug 12 en `BUGS.md`,
sección "Scope"), así que no hace falta re-correr nada por eso acá.

**Qué hacer:** refrescarlos con los fixes de bug 7/9, o retirarlos de circulación si ya no
tienen uso operativo (eran para un caso de uso puntual). Es una decisión de producto, no
solo técnica — confirmar con el usuario si todavía se usan antes de invertir tiempo en
refrescarlos.

### Tarea 6 — Aplicar el fix de bug 11 a los 3 archivos del motor oficial
**Archivos:** `fase1_stock.sql`, `fase2_nuevos.sql`, `fase3_backtest.sql`.

Mismo dedup que la Tarea 3, aplicado al motor de recupero oficial. Re-correr el backtest
de junio (+5.4% de error hoy) y confirmar que no cambia materialmente.

### Tarea 7 — Investigar `installmentlastpaiddate`
**Tabla:** `dts_cobranza_creditos_cuotas` (nivel cuota), campo aportado por el usuario,
todavía sin explotar.

Podría precisar el punto ciego de ~1 día de `dayslate` (bug 9 en `BUGS.md`: una cuota
pagada 1 día tarde casi nunca hace que `dayslate` llegue a mostrar 1) cruzándolo contra la
fecha exacta en que `dayslate` pasa a 1 para el mismo crédito.

**Prioridad elevada 2026-08-19 (bug 14 en `BUGS.md`):** la reconciliación contra
`vw_seguimiento_diario_cohorte_tramo` (vista oficial externa) cuantificó este punto ciego
en **~27% de la población real de mora 1-30/TEMPRANA** (3,210 de 3,449 créditos "solo
oficiales"), no el ~4% que sugería la muestra anterior — ya no es un caso de borde. Plan
de trabajo completo (qué investigar, opciones de corrección, backtest obligatorio antes
de adoptar cualquiera) en `reconciliacion_vw_seguimiento_temprana.md` — **empezar ahí,
no repetir el diagnóstico.**

### Tarea 8 — ~~Cerrar la fila de julio en `SEGUIMIENTO.md` (recupero oficial)~~ hecho 2026-08-18
Julio cerró con **+17.6% de error** (stock +2.0%, nuevos +22.5%) — el más alto medido hasta
ahora en este enfoque. Ver `SEGUIMIENTO.md` y `cierre_julio.sql`. Meta de agosto ya armada
(`meta_agosto.py`, `datos_meta_agosto/`) — nueva tarea abajo (Tarea 8b).

### Tarea 8b — Cerrar la fila de agosto en `SEGUIMIENTO.md` (recupero oficial) cuando termine el mes
Meta proyectada S/2,108,435 (stock S/711,160 + nuevos S/1,397,275) vs. real final. Fuente:
`meta_agosto.py` + `datos_meta_agosto/`.

---

## Compartidas entre ambos enfoques

### Tarea 9 — Extender el backtest a 3-6 meses cerrados más
**Avance 2026-08-18:** julio ya se cerró como segundo punto de dato para ambos enfoques
(`cierre_julio.sql`, ver `SEGUIMIENTO.md`) — capital asegurado +4.7% (vs. -4.7% en junio,
signo invertido), recupero oficial +17.6% (vs. +5.4% en junio, mismo signo pero mucho más
grande, concentrado en "nuevos"). Con 2 meses todavía no alcanza para saber si ±5-22% es el
error típico o si julio fue una anomalía — faltan 2-4 meses más (replicar `cierre_julio.sql`
ajustando fechas para meses previos ya cerrados: mayo, abril, etc., y anotar cada uno en
`SEGUIMIENTO.md`).

### Tarea 10 — Recalibrar las curvas excluyendo el mes de prueba
Hoy `curva_stock`/`curva_nuevos` (ambos enfoques) se calibran sobre los 14 meses completos
de historia (incluyen junio, peso marginal ~1/14) — solo la tasa `P(no paga a tiempo)` se
recalibró estrictamente fuera de muestra. Un backtest riguroso recalcularía también las
curvas excluyendo cada mes de prueba.

### Tarea 11 — Investigar la sobreestimación de stock en junio
El stock sobreestimó +16.2% (recupero oficial) / +7.2% (capital asegurado tras bug 12) en
junio, mientras "nuevos" acertó casi exacto en ambos casos. Podría ser varianza normal (el
tramo 9-15 osciló 9.8%-18.8% entre meses en los 14 de historia) o un segmentador que falta
— investigar antes de asumir que es un problema del modelo.

### Tarea 12 (baja prioridad) — Reorganizar en carpetas
Considerar `sql/`, `python/`, `docs/` si el root sigue creciendo. No bloquea nada; con la
limpieza del 2026-07-15 el root ya bajó en 8 archivos + 2 carpetas de datos.

---

## Ya resuelto en la limpieza del 2026-07-15

- Descontinuación formal de "reinicio del reloj" y "salida de mora" (archivos eliminados,
  documentación actualizada en `DECISIONES.md`, `GLOSARIO.md`, `LINAJE.md`, `BUGS.md`,
  `IDEAS.md`, `ESTADO.md`, `README.md`).
- `SEGUIMIENTO.md` sincronizado con los números de julio ya corregidos por bug 12
  (S/4,971,669 real, +4.1% vs. proyectado — antes decía S/4,800,372 / +32.1%, un residuo
  de antes del fix).
- Pendientes activos de `IDEAS.md` consolidados en este archivo, organizados por enfoque.

## Ya resuelto 2026-08-18 (homologación con `gestiones_cobranzas`)

- Confirmado que `dts_asignaciones_cobranza` quedó congelada el 2026-07-10 — repuntado
  `avance_cobranza_fase.sql`/`FUENTES_DATOS.md` a `dts_asignaciones_gestiones_cobranza`
  (tabla viva). Ver bug 13 en `BUGS.md`.
- Homologado `tipo_mora` (gestiones_cobranzas) contra antiguo/nuevo (`dayslate`+bug12, este
  proyecto): 98.5% de acuerdo en población mora 1-30 (muestra 10-ago). El 1.5% restante
  tiene causa identificada (créditos que curan y recaen dentro del mes) y no amerita cambio
  de metodología. Query fuente: `homologacion_tipo_mora_gestiones.sql`.
- **No incluido en este cierre** (fuera del pedido explícito del usuario, que priorizó solo
  la homologación antiguo/nuevo): el 3.7% de créditos "sin mora" para este proyecto que sí
  aparecen con mora en `gestiones_cobranza` (ver nota en bug 13).
- **Cerrado julio y armada la meta de agosto (mismo día, a pedido del usuario):** ver
  tareas 4/4b y 8/8b arriba, `SEGUIMIENTO.md` y `cierre_julio.sql`/`meta_agosto.py`/
  `meta_agosto_capital_asegurado.py`. Julio: capital asegurado +4.7%, recupero oficial
  +17.6% (el error más alto medido hasta ahora, en "nuevos"). Agosto: metas proyectadas y
  tracking en vivo al corte 18-ago, ambos enfoques.

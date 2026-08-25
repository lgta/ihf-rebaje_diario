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

### Tarea 1 — ~~Re-correr `avance_cobranza_fase` con la definición corregida (bug 12)~~ CERRADA 2026-08-21
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

**Agregado 2026-08-21 — aplicar TAMBIÉN el fix de bug 15 (`aux02`) en esta misma pasada:**
`avance_cobranza_fase.sql` cruza `dts_asignaciones_gestiones_cobranza` contra
`dts_cobranza_creditos_cuotas` vía `dni`+`producto` (CTE `cuotas_activos`, filtro
`status='ACTIVE'`) — el mismo patrón que resultó impreciso en la reconciliación TEMPRANA
(ver bug 15 en `BUGS.md`): la tabla SÍ tiene `id_ihfintech_loan` directo en la columna
`aux02` (99.97% de match verificado, vs. ~96.5% del crosswalk, y sin el problema de
excluir créditos ya `COMPLETED`). Reemplazar el join `c.dni = a.dni_ce and c.producto =
a.producto` por un join directo `c.id_ihfintech_loan = a.aux02` (o usar `a.aux02`
directamente como `id_ihfintech_loan`, sin pasar por `dts_cobranza_creditos_cuotas` en
absoluto, salvo que se necesite algún otro campo de esa tabla).

**Criterio de terminado:** los números de avance por fase (Temprana/Especializada/
Recovery × nuevo/stock) en `avance_cobranza_fase.md` reflejan la definición corregida;
la nota "⚠ Pendiente" de `ESTADO.md` sección "Análisis puntuales" se puede quitar.

**CERRADA 2026-08-21 — los 3 fixes aplicados (bug 12 + bug 15 + bug 11, este último
agregado en el camino por ser exigido por `CLAUDE.md` para cualquier `row_number()`/`lag()`
nuevo sobre `dts_mambu_loans_hist`, y este archivo nunca lo había tenido):**
- La cohorte creció de 8,303 a 8,614 créditos (bug 15, +3.7%, concentrado en TEMPRANA).
- "nuevo" bajó de 1,258 a 571 créditos, "stock" subió correspondientemente (bug 12 — el
  1-jul solo representaba 60-70% del bucket "nuevo" viejo, un impacto mucho mayor que en
  la calibración de 14 meses porque esta cohorte es una ventana de solo 11 días).
- Query verificada tal como quedó en el repo (re-ejecutada, reproduce los mismos números).
- `avance_cobranza_fase.py` no necesitó cambios de código — ya estaba preparado para
  consumir la clasificación correcta directo del SQL.
- Resultados actualizados en `avance_cobranza_fase.md` (tabla + lectura de resultados). La
  nota "⚠ Pendiente" en `ESTADO.md` "Análisis puntuales" — quitada.

### Tarea 2 — ~~Refrescar el artifact `capital_asegurado.html`~~ CERRADA 2026-08-23
**Reconstrucción completa** (no un simple refresco de cifras — el archivo tenía números
previos a bug 12 Y a la capa fantasma de bug 14, un motor de 2 componentes en vez de 3).
Se rehizo con: curvas actuales (bug 12), backtest de 3 meses cerrados con capa fantasma
(mayo -4.4%, junio +2.65%, julio -0.2% — este último el número reconstruido en bug 17,
`BUGS.md`), avance en vivo de agosto (corte 21-ago, +2.7% vs. proyectado mismo día) y
segmentado de agosto, más 5 créditos de ejemplo nuevos (agosto real). Mismo motor visual/JS
del archivo original, solo se reemplazaron los datos y el texto que los describe.

**URL vieja (`3a6b8cb9...`) ya no existía** (mismo patrón que pasó con
`curvas_matriz_alfa.html` — los artifacts pueden expirar/desaparecer con el tiempo) —
republicado en una URL nueva:
`https://claude.ai/code/artifact/d4140b13-4017-4313-b140-7d8f6356d5d7`. `README.md` y
`ESTADO.md` actualizados a "✓ vigente" con la URL nueva.

### Tarea 3 — ~~Aplicar el fix de bug 11 (filas duplicadas) a `enfoque_capital_asegurado.sql`~~ hecho 2026-08-20
**Contexto:** bug 11 (`BUGS.md`) encontró 1,316 combinaciones (crédito, día) con filas
duplicadas en `dts_mambu_loans_hist` que rompen el patrón `row_number() over (partition by
id_loan order by fechaproceso)` si no hay desempate. Ya se corrigió en
`enfoque_salida_mora.sql` (eliminado junto con ese enfoque) pero **nunca se aplicó a
`enfoque_capital_asegurado.sql`**, que usa el mismo patrón sin desempate.

**Hecho 2026-08-20:** la regla mejorada (saldo≠0 antes de `lastmodifieddate`) se validó
contra los 687 casos conflictivos completos de la historia (no solo la muestra de 16) —
100% del mismo patrón "cero vs. no-cero", y 100% de las referencias no-ambiguas
disponibles (116/145 casos donde la regla cambia el pick) confirman el saldo no-cero, 0
confirman el cero. Aplicada a `enfoque_capital_asegurado.sql` (Q1/Q2/Q3), `_backtest.sql`
(BT-ASEG-0 a 3), `cierre_julio.sql` (J1/J2) e `investigacion_capa_fantasma.sql` (Q3).
Backtest re-corrido: junio sube de +0.7% a **+2.2%** (nuevos -8.6%→-5.8%, el resto casi sin
cambio); julio **no se movió** (0 filas duplicadas relevantes en su ventana). Ver bug 11 en
`BUGS.md` para el detalle completo y `SEGUIMIENTO.md`/`ESTADO.md`/`enfoque_capital_
asegurado.md` para los números actualizados. Las curvas Q1/Q2 y `meta_agosto_capital_
asegurado.py` no se recalcularon (impacto <1pp en curvas, no se justificó rehacer agosto).

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

Mismo dedup ya validado y aplicado a Enfoque alfa en la Tarea 3 (saldo≠0 antes de
`lastmodifieddate`, validado contra los 687 casos conflictivos completos de la historia —
ver bug 11 en `BUGS.md`), pendiente de aplicar al motor de recupero oficial. Re-correr el
backtest de junio (+5.4% de error hoy) y confirmar el impacto — en Enfoque alfa movió el
backtest de junio +0.7%→+2.2% pero julio no se movió nada, así que no asumir que el
impacto acá será igual de chico o grande sin correrlo.

### Tarea 7 — ~~Investigar `installmentlastpaiddate`~~ hecho 2026-08-20, capa fantasma adoptada
**Tabla:** `dts_cobranza_creditos_cuotas` (nivel cuota), campo aportado por el usuario.

Se cruzó contra los créditos específicos que la reconciliación de bug 14 marcaba como
punto ciego: **99.5% resultó ser el mismo mecanismo de bug 9** (pago exactamente 1 día
tarde, `dayslate` nunca lo ve). Se diseñó y adoptó en producción una "capa fantasma"
(tasa nueva e independiente `P_FANTASMA`, no mezclada con `13.38%` ni la curva
existente) — backtest en 2 meses cerrados: junio -4.4%→+0.7%, julio -4.31%→+0.12%. Ver
`reconciliacion_vw_seguimiento_temprana.md` (pasos 1/2/3), `BUGS.md` bug 14,
`enfoque_capital_asegurado.md` sección "Capa fantasma".

**Continuación 2026-08-20, mismo día, también cerrada:** la verificación a nivel crédito
encontró un hueco de frontera de mes (cobertura 90.7%, no 100%) — corregido, junto con la
tasa recalibrada de forma consistente (`P_FANTASMA=8.4534%→8.5524%`). Backtest final:
junio +2.2%→+2.65%, julio +0.12%→+2.17%. Ver bug 14 en `BUGS.md` para el detalle completo.

**Nuevos pendientes que deja esto:**
- Extender el backtest de la capa fantasma a más meses cerrados (solo junio/julio
  disponibles hasta ahora) antes de tratar ±2-3% como error típico.
- Refrescar `capital_asegurado.html` (tarea 2 abajo) también incluye ahora la capa
  fantasma completa (tasa recalibrada + fix de frontera), no solo el fix de bug 12.
- Decidir si en algún momento se extiende la capa fantasma al Enfoque acumulado
  (recupero oficial) — deliberadamente fuera de alcance en esta pasada (13.38% de ese
  enfoque no se tocó).

### Tarea 8 — ~~Cerrar la fila de julio en `SEGUIMIENTO.md` (recupero oficial)~~ hecho 2026-08-18
Julio cerró con **+17.6% de error** (stock +2.0%, nuevos +22.5%) — el más alto medido hasta
ahora en este enfoque. Ver `SEGUIMIENTO.md` y `cierre_julio.sql`. Meta de agosto ya armada
(`meta_agosto.py`, `datos_meta_agosto/`) — nueva tarea abajo (Tarea 8b).

### Tarea 8b — Cerrar la fila de agosto en `SEGUIMIENTO.md` (recupero oficial) cuando termine el mes
Meta proyectada S/2,108,435 (stock S/711,160 + nuevos S/1,397,275) vs. real final. Fuente:
`meta_agosto.py` + `datos_meta_agosto/`.

---

## Compartidas entre ambos enfoques

### Tarea 9 — Extender el backtest a 3-6 meses cerrados más — PARCIAL, 2026-08-22/23
**Avance 2026-08-22:** mayo agregado como tercer mes cerrado del backtest de capital
asegurado (`backtest_capital_asegurado_mayo.py`) — error -4.4% (stock -0.8%, nuevos -14.9%,
fantasma +7.4%). Al reconstruir julio con el mismo rigor (dedup + calendario de fantasma
frontier-adjusted, `backtest_capital_asegurado_julio_diario.py`) se encontró que el número
oficial anterior (+2.17%) estaba calculado con `jul_calendario.csv`, un archivo huérfano que
corría 7.9% alto — **el número correcto es -0.2%** (stock -1.9%, nuevos -12.2%, fantasma
+15.4%), adoptado y confirmado con el usuario 2026-08-23 (ver bug 17 en `BUGS.md`,
`SEGUIMIENTO.md` ya actualizado).

**Avance 2026-08-23:** abril agregado como cuarto mes cerrado (`backtest_capital_
asegurado_abril.py`, `enfoque_capital_asegurado_backtest_abril.sql`) — error **-17.6%**
(stock +7.9%, nuevos -24.1%, fantasma -18.9%), el error más grande de los 4 meses. Con los
4 meses (abril -17.6%, mayo -4.4%, junio +2.65%, julio -0.2%): **"nuevos" subestima en los
4, sin excepción** (-24.1% / -14.9% / -5.8% / -12.2%) — señal cada vez más consistente con
sesgo real en `P_NO_PAGA_DIA0=13.38%` (subestima volumen de entrada), no solo varianza, ver
`analisis_volumen_efectividad_agosto.md` (mismo patrón en el tracking en vivo de agosto, y
el caveat de causalidad de esa lectura ya se resolvió — `grupo_control` es aleatorización
estratificada por riesgo y monto, confirmado por el usuario). **Esta vez la query del
calendario de fantasma frontier-adjusted SÍ quedó copiada al repo** (bug 17 pedía
explícitamente evitar que se perdiera en el scratchpad otra vez) —
`enfoque_capital_asegurado_backtest_abril.sql` query BT-ASEG-ABR-CALFANT. El artifact
[📈 Proyectado vs. Real](https://claude.ai/code/artifact/f80d3761-732c-483b-99ad-d85c95c896aa)
explica el mecanismo completo con julio y mayo como ejemplos — **todavía no incluye abril**,
pendiente de refrescar.

**Sigue pendiente:** 4 puntos de dato es una base más firme pero todavía vale extender a
marzo 2026 (o más atrás si hay datos limpios) para confirmar el patrón, usando
`enfoque_capital_asegurado_backtest_abril.sql` como plantilla esta vez (ya incluye el fix
completo del calendario de fantasma, a diferencia de la plantilla de mayo). Dado que abril
tiene el error más grande de los 4 (y en dirección distinta en fantasma/stock respecto a
mayo/junio/julio), vale la pena investigar si marzo confirma esa magnitud o si abril es un
outlier puntual antes de sacar conclusiones sobre tendencia. También pendiente (menor
prioridad): confirmar la causa exacta de por qué `jul_calendario.csv` corría alto — no se
investigó a fondo, la pista es saldo promedio ~11% más alto por crédito con MENOS créditos,
no una firma de fila duplicada. Y actualizar el artifact "Proyectado vs. Real" con la tabla
ampliada a 4 meses.

### Tarea 10 — Recalibrar las curvas excluyendo el mes de prueba — CERRADA 2026-08-22
Se recalibraron `curva_asegurado_stock_seg.csv`/`curva_asegurado_nuevos_seg.csv` excluyendo
por completo mayo, junio Y julio (antes solo julio quedaba fuera por casualidad de rango) y
se re-corrieron los 3 backtests con las curvas nuevas — movimiento de ~0.15-0.2pp en los 3
meses, mismo patrón que la prueba de ventana de `P_NO_PAGA_DIA0` (bug 11 en `BUGS.md`): el
modelo es robusto a la exclusión estricta. **No se adopta en producción** (impacto no lo
justifica). Ver bug 11 (actualización 2026-08-22) en `BUGS.md` para el detalle completo y
la tabla comparativa.

### Tarea 11 — Investigar la sobreestimación de stock en junio
El stock sobreestimó +16.2% (recupero oficial) / +7.2% (capital asegurado tras bug 12) en
junio, mientras "nuevos" acertó casi exacto en ambos casos. Podría ser varianza normal (el
tramo 9-15 osciló 9.8%-18.8% entre meses en los 14 de historia) o un segmentador que falta
— investigar antes de asumir que es un problema del modelo.

**Pista nueva 2026-08-24 (bug 19):** con 4 meses de backtest el stock es el componente
errático (+7.9% abr, -0.8% may, +7.3% jun, -1.9% jul) mientras "nuevos" es consistente en
signo. Y la validación de universo encontró que **la contaminación del stock (15.6% no
gestionado como TEMPRANA) es casi 3× la de nuevos (5.8%)** — si esa proporción varía mes a
mes, la curva de stock (calibrada con un mix promedio) erraría de forma variable. Es
hipótesis, no verificada, y **no se puede verificar antes de julio 2026** (la tabla de
asignaciones no existe antes). Ver bug 19 en `BUGS.md`.

### Tarea 13 — Corregir el índice de la curva de nuevos (bug 18) — ✅ CERRADA 2026-08-24
**Resuelta.** Índice cambiado a `dias_desde_entrada = d - dd - 1` en los 4 backtests y en
`meta_agosto_capital_asegurado.py`; en `_junio.py` y `meta_agosto_*` hubo que desacoplar el
guard compartido con la capa fantasma para dejarla intacta (ver bug 18 en `BUGS.md`).
Resultados: abril **-19.2%**, mayo **-6.8%**, junio **+1.6%**, julio **-3.3%** — exactamente
los números pre-medidos. Meta de agosto S/16,410,194 → **S/16,211,015**. `SEGUIMIENTO.md`,
`ESTADO.md` y los 2 artifacts actualizados. **Lo que queda abierto es explicar el sesgo de
"nuevos" ya sin el bug compensándolo** (-27.3% abr / -20.1% may / -8.0% jun / -19.2% jul) —
eso es tarea 9 + el análisis de volumen/mix/gestión, no un ajuste de constante.

<details><summary>Enunciado original</summary>

**Prioridad: la más alta.** Es un error puro, verificado con datos, y afecta la meta vigente
de agosto además de los 4 backtests. Acordado con el usuario 2026-08-24 como el primer paso
de la sesión siguiente.

**Qué está mal:** la curva de nuevos se calibra indexada desde `fecha_entrada` (día que
`dayslate`=1 = vencimiento+1, verificado 99.99%), con el join `f.fechaproceso >
e.fecha_entrada` — o sea el día 1 de la curva es vencimiento+2. Pero los proyectores indexan
`dias_desde_entrada = d - dd` donde `dd` es el día de VENCIMIENTO, o sea
`fechaproceso − vencimiento`. Aplica `curva[k]` donde corresponde `curva[k−1]`.

**Qué hacer:**
1. Cambiar el índice a `dias_desde_entrada = d - dd - 1` en los 4 scripts de backtest
   (`backtest_capital_asegurado_abril.py`, `_mayo.py`, `_junio.py`, `_julio_diario.py`) y en
   `meta_agosto_capital_asegurado.py`. **No tocar el loop de fantasma** — ese no usa curva y
   su índice actual es correcto.
2. Re-correr los 4 backtests y actualizar `SEGUIMIENTO.md` (las 4 filas), `ESTADO.md`
   ("La meta vigente" + índice de enfoques) y la meta de agosto.
3. Republicar los artifacts afectados con los números nuevos:
   [📈 Proyectado vs. Real](https://claude.ai/code/artifact/f80d3761-732c-483b-99ad-d85c95c896aa)
   y [🔒 Capital asegurado](https://claude.ai/code/artifact/d4140b13-4017-4313-b140-7d8f6356d5d7)
   (pasar `url=` para no crear artifacts nuevos).

**Impacto ya medido — el error EMPEORA y aun así se corrige** (ver el principio nuevo de
`CLAUDE.md`, "El error se explica, no se optimiza"): abril -17.6%→-19.2%, mayo -4.4%→-6.8%,
junio +2.65%→+1.6%, julio -0.2%→-3.3%. El bug estaba compensando parcialmente el sesgo de
"nuevos" (que subestima en los 4 meses). Al corregirlo, ese sesgo queda expuesto — **eso es
lo correcto**, hay que explicarlo (volumen/mix/gestión), no taparlo.

Ver bug 18 en `BUGS.md` para el detalle completo, la verificación empírica y la hipótesis
que se descartó en el camino (la tasa 13.38% NO tiene el mismo problema — recalibrada por
fecha exacta da 13.57%, solo +0.9% relativo).

</details>

### Tarea 14 — Investigar los 302 créditos que no aparecen en asignaciones (bug 19) — ✅ CERRADA 2026-08-24
**Resuelta.** Son dos mecanismos distintos, no uno (detalle completo en bug 19,
`BUGS.md`, actualización 2026-08-24; queries en `tarea14_no_aparece_asignaciones.sql`):
- **~69 créditos (50 stock + 19 nuevos, 22.8%)** confirman la hipótesis original (pagos que
  resuelven el crédito antes de que el proceso de asignación del día los alcance) — el
  stock pagó el 01-ago (día 1 del mes), los nuevos salieron de mora en 1 día exacto (100%
  vs. 37.6% de baseline).
- **232 créditos (77.2%, todo el resto de "nuevos")** es censura por el corte de fecha del
  propio ejercicio de validación — entraron en mora el 23-ago, el último día de la ventana
  de asignaciones usada, y simplemente no tuvieron tiempo de aparecer. No es un hallazgo de
  negocio.

No cambia la lectura de bug 19 (el hueco del 21.6% y la contaminación asimétrica 15.6%/5.8%
siguen de pie) — solo cierra la pregunta puntual de por qué estos 302 no aparecían.

### Tareas 15 y 16 — Población gestionada vs. total, y escalados ESPECIALIZADA/RECOVERY (bug 19) — MEDIDAS 2026-08-24, DECISIÓN SIGUE ABIERTA
**El trabajo técnico (medir el sesgo) está hecho — lo que falta es la decisión del usuario,
que sigue siendo suya.** Julio 2026 (único mes cerrado con asignaciones completas) muestra
que ESPECIALIZADA/RECOVERY activa capital muchísimo menos que TEMPRANA gestionado — gap real
y grande por componente:

| | TEMPRANA gestionado | ESPECIALIZADA/RECOVERY | Gap |
|---|---:|---:|---:|
| Stock (% saldo asegurado) | 64.7% | 9.6% | **-55.1pp** |
| Nuevos (% saldo asegurado) | 73.0% | 11.6% | **-61.4pp** |

**Pero en el AGREGADO (curva completa) el efecto es chico** — "todos" vs. "solo TEMPRANA":
stock 64.6% vs 64.7% (-0.1pp), nuevos 71.5% vs 73.0% (-1.5pp). ESPECIALIZADA/RECOVERY es
poco volumen (6.5% stock, 0.7% nuevos) y su arrastre se compensa casi del todo con otros
buckets. Detalle completo, incluyendo el bucket residual sin explicar ("otra situación") y
la nota sobre grupo control, en bug 19 (`BUGS.md`) y `tarea15_16_sesgo_gestionado_julio.sql`.
**Casos individuales (no solo agregados) en `tarea15_16_casos_julio.sql` /
`datos_tareas14_15_16/` — el usuario los pidió 2026-08-24 para revisar antes de decidir.**

**Recomendación (no decisión):** dado el efecto agregado chico, mismo criterio que tarea 10
(fuga de datos, 0.15-0.2pp, no adoptado) — no tocar la calibración de producción por esto
ahora, solo documentar el gap real por componente para cuando la pregunta vuelva (ej. si el
volumen de escalados crece). **Si el usuario prefiere excluir ESPECIALIZADA/RECOVERY de
todos modos por coherencia conceptual** (la curva debería representar lo que TEMPRANA hace,
no una fase de gestión distinta) aunque el impacto agregado sea chico, esa sigue siendo su
llamada — avisar para implementarlo.

**Limitación dura que sigue de pie:** `dts_asignaciones_gestiones_cobranza` solo existe
desde 2026-07-01 y las curvas se calibran sobre 14 meses previos — el universo histórico no
se puede limpiar retroactivamente. Esta medición es de UN mes (julio) — no se sabe si es
representativo de otros meses ni si la proporción de escalados varía con el tiempo (conecta
con la hipótesis no verificada de la tarea 11, ver bug 19).

La motivación original de la tarea 15 (el punto ciego de ~21% de `dayslate`, población fuera
de nuestro universo que paga 1 día tarde) es una pregunta DISTINTA, ya parcialmente resuelta
por la capa fantasma (bug 9/14) — no remedida en esta sesión.

### Tarea 17 — Validar el universo a nivel de CUOTA (`dias_atraso_cuota`) contra asignaciones, y construir una curva real para la capa fantasma — FASE 1 (cantidad) CERRADA 2026-08-24, Fase 2 pendiente
**Prioridad: la más alta de las pendientes — precede y puede cambiar cómo se resuelven las
tareas 15/16.** Revive y extiende bug 16 (`dias_atraso_cuota`, investigación de 2026-08-22
archivada por resultado "mixto" en el backtest) con un ángulo nuevo del usuario: el mecanismo
HORARIO por el que `dayslate` es ciego a pagos de 1 día de mora.

**✅ FASE 1 (cantidad) EJECUTADA Y CERRADA 2026-08-24 — resultado más rico de lo planificado:
el mecanismo horario se confirma (~97% de reducción del punto ciego), pero aparece un
mecanismo HERMANO no anticipado (fin de semana sin asignación) que es MÁS GRANDE que el
original. Detalle completo, las 4 queries de diagnóstico verificadas, y la tabla de
categorías con motivo en bug 16 (`BUGS.md`, actualización 2026-08-24). Resumen:**
- El universo oficial TEMPRANA es idéntico entre métodos (11,736 julio / 10,035 agosto) —
  cambia cuánto capturamos. `dias_atraso_cuota` sube la cobertura de 70.4%→**96.3%** (julio)
  y 78.4%→**98.6%** (agosto).
- El "punto ciego" específico baja de 3,130→**87** (julio) y 2,093→**63** (agosto), ~97% de
  reducción — confirma el mecanismo horario del usuario.
- Pero aparece "no aparece en asignaciones" (117→**851** julio, 302→**1,708** agosto) — NO
  es ruido: `dts_asignaciones_gestiones_cobranza` no tiene NINGUNA fila los fines de semana
  (verificado), y `dias_atraso_cuota` detecta episodios de mora reales pero breves que nacen
  y se resuelven DENTRO de un fin de semana, invisibles para la asignación semanal-hábil.
  91-100% de las 4 subpoblaciones revisadas (nuevos/stock × julio/agosto) caen exactas en
  este patrón.
- Residual sin explicar: 87+63=150 créditos (<1% del universo oficial), patrón mixto, no
  forzado a una explicación — documentado en bug 16.
- **Archivos nuevos en el repo (a diferencia de bug 16 original, que se perdió en
  scratchpad):** `tarea17_universo_dias_atraso_cuota.sql` (reconstrucción + categorización,
  julio y agosto), `tarea17_fase1_mecanismo.sql` (Q1-Q4, diagnóstico del mecanismo, todas
  auto-contenidas, sin depender de listas de IDs de sesión), `datos_tarea17_universo/`
  (CSVs caso por caso, `id_ihfintech_loan` completo).

**✅ Pregunta conceptual RESUELTA por el usuario 2026-08-24: la curva debe representar TODA
la mora que ocurre (cualquier día con vencimientos), no solo la que el negocio gestiona.**
"dias_atraso_cuota" es el universo correcto para calibrar de acá en adelante. Verificado con
2 chequeos antes de aceptar la decisión (detalle en bug 16, `BUGS.md`):
1. Un crédito que vence sábado y sigue sin pagar entra oficialmente como "nuevo" el lunes —
   confirmado 100% con 259 casos reales.
2. La forma de la curva SÍ difiere por día de la semana del vencimiento (fin de semana paga
   ~2x más rápido en el día 1 desde la entrada que entre semana) — hipótesis del usuario
   (sin gestión activa el sábado, más créditos "se escapan" a mora, pero pagan rápido apenas
   los llaman el lunes) adoptada sobre la mía (rezago de procesamiento de pago, descartada
   por el usuario). **Implicación para Fase 3: el día de la semana del vencimiento debe
   tratarse como segmentador de la curva**, no solo como parte de la tasa de entrada.
   De paso, se corrigió el wording: lo que se llamaba "días de gestión" (el índice que elige
   el % de la curva al proyectar un vencimiento hasta fin de mes) son en realidad **días
   calendario** desde el vencimiento — el modelo está bien así, solo estaba mal nombrado.

**Observación adicional del usuario sobre el segmentador `avance_band` existente (4 buckets:
<10% / 10-40% / 40-70% / 70%+): 40-70% y 70%+ no se separan bien, candidato a simplificar a
3 buckets (<10% / 10-40% / 40%+) en Fase 3.**

**✅ FASE 2 (montos, soles) EJECUTADA Y CERRADA 2026-08-24 — mismo patrón que Fase 1, en
soles.** Archivo `tarea17_fase2_montos.sql`, CSVs en `datos_tarea17_universo/`. Detección y
corrección de un bug propio en el camino (saldo de fin de mes en vez de saldo al momento de
entrada — corregido y verificado 99.94% de coincidencia contra el método `dayslate` en
créditos "EN AMBOS"). Resultado:

| | Julio — cobertura | Julio — hueco | Agosto — cobertura | Agosto — hueco |
|---|---:|---:|---:|---:|
| `dayslate` | 75.9% (S/13.29M) | S/4.22M (24.1%) | 84.2% (S/12.64M) | S/2.37M (15.8%) |
| `dias_atraso_cuota` | **97.8% (S/17.23M)** | **S/390K (2.2%)** | **99.3% (S/14.92M)** | **S/101K (0.7%)** |

Detalle completo, incluyendo el desglose del "solo nuestro - no aparece en asignaciones" en
soles, en bug 16 (`BUGS.md`).

**✅ FASE 3 EJECUTADA 2026-08-25 — resultado inesperado: la activación instantánea de
`P_FANTASMA` YA ERA CORRECTA, no hace falta una curva multi-día.** Calibrado con 2 ventanas
a pedido del usuario (12 y 6 meses, no la historia completa 2023-10-17+ del plan original —
el portafolio de esa época es ~1000x más chico, mezclarlo violaría el mismo principio que ya
aplica a las demás curvas del proyecto). Archivo `tarea17_fase3_curva_fantasma.sql`, datos en
`datos_tarea17_fase3/`. Resumen (detalle completo en bug 16, `BUGS.md`):
- Tasa agregada casi idéntica a la actual pese a la redefinición más amplia (dias_atraso_cuota
  en vez de `dias_vencimiento_a_pago=1`): **8.617% (12m) / 8.923% (6m)** vs. 8.5524% actual.
- Activación ponderada en el **día 0 = 99.60%** (12m), 99.49%-100% por segmento (6m) — el día
  de semana del vencimiento y `avance_band` NO cambian la forma, todos los segmentos llegan
  a ~99-100% casi de inmediato. Un bug propio (saldo de referencia mal anclado) se encontró y
  corrigió en el camino — ver bug 16.
- Lo que SÍ varía por día de semana es la TASA de entrada, no la forma: semana 9.08%/9.36%
  vs. fin de semana 5.67%/6.31% (12m/6m) — dirección opuesta al hallazgo de "no aparece en
  asignaciones" de Fase 1, con una explicación distinta (`dayslate` corre 7 días a la semana,
  a diferencia de asignaciones, y sí alcanza a ver la mayoría de la mora de fin de semana que
  no se resuelve el mismo día).
- **Recomendación, pendiente de decisión del usuario:** actualizar `P_FANTASMA` a la tasa
  recalibrada (con o sin segmentar por día de semana), sin tocar la arquitectura de
  activación instantánea (confirmada correcta) — verificar con backtest antes de adoptar.

**Siguiente paso: Fase 4 — evaluar si conviene recalibrar TODAS las curvas de producción
(stock, nuevos) con `dias_atraso_cuota` en vez de `dayslate`.** No ejecutado todavía.

**El punto de partida (usuario, 2026-08-24):** el snapshot diario de `dts_mambu_loans_hist`
se toma cerca de las 10pm. Un crédito que entra en mora (vencimiento+1) y paga ese mismo día
DESPUÉS de las 9am (cuando ya se armó la asignación de cobranza del día) pero ANTES de las
10pm (cuando corre el snapshot de Mambu) **queda asignado a TEMPRANA en la tabla oficial,
pero `dayslate` nunca lo ve en mora** — Mambu ya lo ve pagado en su única foto del día. Esto
explicaría por qué las curvas calibradas con `dayslate` (todos los meses históricos,
2025-04 a 2026-06) sistemáticamente excluyen a esta población, y por qué `dts_cobranza_
creditos_cuotas`/`dias_atraso_cuota` (que reconstruye día por día desde el pago real, no de
un snapshot único) SÍ la captura.

**Verificado a nivel de caso, ejemplo real (2026-08-24):** crédito `1f49097f-3bb7-4886-8a22-
7ca10a5f5704` (categorizado "solo oficial - punto ciego dayslate" en julio) — su cuota
vigente venció **2026-07-07**, se pagó **2026-07-08 12:39:41** (vencimiento+1, dentro de la
ventana 9am-10pm). Confirma el mecanismo a nivel de caso individual, no solo en agregado.

**3 correcciones del usuario al plan original de esta sesión — tenerlas presentes:**
1. **Al revisar casos de `dts_cobranza_creditos_cuotas`, mirar SOLO la cuota vigente** (la
   que efectivamente cayó en mora y coincide con lo que dice la tabla de asignaciones para
   ese crédito) — no otras cuotas del mismo crédito (pasadas ya pagadas, futuras no
   vencidas). Usar `dts_cobranza_creditos_calendario_diario.dias_atraso_cuota` (bug 16) como
   la reconstrucción diaria ya resuelve cuál es la cuota vigente en cada fecha — no
   reinventar esa lógica desde `dts_cobranza_creditos_cuotas` directo.
2. **El objetivo de cuadrar el universo es IDENTIFICAR diferencias y sus motivos, NO
   reducirlas.** Si al final queda un % sin explicar, se documenta como tal — no se busca
   minimizarlo. Aplica el mismo "Principio de interpretación del error" de `CLAUDE.md` a
   este ejercicio específico de reconciliación de universo, no solo al backtest de recupero.
3. **El propósito real no es solo julio/agosto — es VALIDAR si el método usado para calibrar
   curvas en TODOS los meses históricos (`dayslate`) es ciego a esta población,** y si
   `dias_atraso_cuota` (con datos desde 2023-10-17, mucho más profundo que los 14 meses
   actuales) la ve. Julio/agosto son el banco de pruebas (única ventana con tabla formal de
   asignaciones) para confirmar el mecanismo antes de aplicarlo a la historia completa.

**Plan en fases (ejecutar en este orden, ninguna fase saltada):**

**Fase 1 — Cuadrar CANTIDAD (créditos), julio primero, agosto después.**
1. Reconstruir el universo de julio con `dias_atraso_cuota` en vez de `dayslate` (mismo
   patrón que bug 16, pero **copiado al repo esta vez** — las queries originales de bug 16,
   `sc_A` a `sc_AC`, quedaron solo en el scratchpad de esa sesión y nunca se recuperaron).
   A nivel de CASO (`id_ihfintech_loan` completo), no agregado — mismo estándar que
   `tarea15_16_casos_julio.sql`/`tarea14_casos_agosto.sql` de esta sesión.
2. Comparar contra `dts_asignaciones_gestiones_cobranza` en cantidad de créditos, con el
   mismo esquema de categorías de `validacion_universo_ejecucion.sql`/
   `validacion_universo_capital_julio_agosto.sql` (en ambos / solo nuestro -grupo control,
   ESP-REC, no aparece- / solo oficial -sin match, status, reenganche, resto-).
3. Para lo que quede "solo oficial" sin explicar, usar `installmentlastpaiddate` (tiene
   timestamp completo, ya confirmado) para verificar si cae en la ventana 9am-10pm —
   sistemáticamente, no solo el ejemplo de arriba.
4. Repetir para agosto (corte 23-ago, grupo control mucho más chico que julio).
5. **Entregable: tabla de categorías con motivo para cada una, no un número único de "%
   cuadrado".**

**Fase 2 — Recién con la Fase 1 completa: montos (soles), misma metodología.**

**Fase 3 — Si el mecanismo horario se confirma sistemáticamente: construir una curva real
(no una tasa plana) para la población "paga 1 día tarde"**, calibrada sobre la historia
completa de `dias_atraso_cuota`/`installmentlastpaiddate` (2023-10-17 en adelante) —
reemplazando el supuesto de tasa plana `P_FANTASMA=8.5524%` (tarea 7, bug 14) que el usuario
señaló como inadecuado. Misma metodología ya usada para calibrar la curva de "nuevos".

**Fase 4 (pendiente de la Fase 3) — evaluar si conviene recalibrar TODAS las curvas de
producción (stock, nuevos) usando `dias_atraso_cuota` en vez de `dayslate`** — es la pregunta
que bug 16 dejó abierta con resultado "mixto" (junio mejoró, julio empeoró en su momento, con
el número de julio ya desactualizado) y que este trabajo podría finalmente explicar.

**No ejecutar sin releer:** bug 16 completo (`BUGS.md`) — tiene la reconciliación previa
(83%→99.8% de cierre en soles) y el backtest mixto ya corrido, no repetir esas 2 corridas de
junio/julio sin releer primero qué se probó y qué falta.

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

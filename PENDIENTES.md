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

### Tarea 4b — ~~Cerrar la fila de agosto en `SEGUIMIENTO.md`~~ ✅ CERRADA 2026-09-01
Meta S/17,117,628 vs. real **S/17,322,872 = -1.2%** (stock -1.3%, nuevos -1.1%). **El mes más
ajustado del proyecto**, y rompe la racha de 7 meses en que "nuevos" subestimaba sin excepción.
Real de `tarea19_real_agosto_cierre.sql` (ventana extendida al 31-ago; la vieja cortaba el 26).

Dos caveats que quedaron anotados en la fila y no hay que perder:
- **No es un test prospectivo limpio.** Las curvas nunca vieron agosto, pero la ADOPCIÓN de W3
  se decidió el 26-ago con 25 días del mes visibles. Septiembre sí lo es.
- **Los cortes ya publicados se movieron al re-medir** (21-ago S/11,595,123→S/11,547,707, -0.4%;
  25-ago S/13,484,959→S/13,398,433, -0.6%): `dts_mambu_loans_hist` se re-expresa para días
  pasados. No es un bug del modelo; conviene tenerlo presente al comparar cortes viejos.

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

### Tarea 6 — ~~Aplicar el fix de bug 11 a los 3 archivos del motor oficial~~ OBSOLETA 2026-09-14
**Obsoleta:** esos tres archivos quedaron como referencia histórica cuando el recupero oficial migró a
`dias_atraso_cuota` (18e, 2026-08-26), y desde octubre el recupero sale de `motor_v2.py`. Las queries
v2 (`tarea24_v2_*.sql`, `tarea25_*.sql`) ya traen el dedup de bug 11 (`mambu_dedup`: saldo ≠ 0
primero, después `lastmodifieddate`). Lo de abajo queda como registro.

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

### Tarea 8b — ~~Cerrar la fila de agosto en `SEGUIMIENTO.md` (recupero oficial)~~ ✅ CERRADA 2026-09-01
Meta S/2,108,435 vs. real **S/2,178,078 = -3.2%** (stock +7.7%, nuevos -7.9%).

**Decisión metodológica del cierre, que no era obvia:** la meta se fijó con el motor viejo
(`dayslate`), así que el real se midió **también con `dayslate`** — `tarea19_real_agosto_
recupero_cierre.sql`. Medirlo con `dias_atraso_cuota` habría dado S/3,174,012 (**146%** del
anterior, en línea con el 148-157% que 18e midió en junio/julio) y un error de +3.2% en vez de
-3.2%: esa diferencia es **cambio de universo, no de ejecución**, y mezclarla haría ilegible la
fila. El número con `dias_atraso_cuota` queda como referencia en la misma fila.

La limitación vieja del script (calendario con el saldo del 18-ago repetido como proxy para los
días 19-31) **muere con esta fila**: `meta_septiembre_recupero.py` ancla el saldo de todas las
cuotas al cierre de agosto, convención única y reproducible.

---

## Compartidas entre ambos enfoques

### Tarea 9 — ~~Extender el backtest a 3-6 meses cerrados más~~ ✅ SUPERADA por 18a/18f/19
**Ya son 8 meses cerrados (ene-ago 2026) en los dos enfoques**, con calibración rodante de 12
meses sin fuga, desde una matriz cruda que hace que agregar un mes cueste 0 queries nuevas de
calibración. Lo de abajo es el historial de cómo se llegó ahí (4 meses, arquitectura con capa
fantasma) — se conserva porque explica de dónde salen números viejos que todavía se citan.

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

### Tarea 11 — Investigar la sobreestimación de stock en junio — DIAGNÓSTICO DESPLAZADO
**2026-09-01:** con 8 meses de test el mes problemático del stock **no es junio, es febrero**, y
18b/18g ya lo explicaron (único mes de 28 días; el modelo indexaba "fin de mes" por día
calendario 30/31 y su cierre real nunca caía ahí — el 28-feb explica el 79.3% del gap). El factor
de cierre real ya está adoptado. Lo que queda vivo de esta tarea es la hipótesis de contaminación
variable del stock, abajo — pero el motivo original (junio) ya no se sostiene.

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

### Tarea 17 — Validar el universo a nivel de CUOTA (`dias_atraso_cuota`) contra asignaciones y evaluar reemplazar `dayslate` en producción — FASES 1-4 EJECUTADAS; Fase 4 ADOPTADA EN PRODUCCIÓN (2026-08-25)
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
**✅ ADOPTADO EN PRODUCCIÓN 2026-08-25 (a pedido del usuario):** `P_FANTASMA` actualizado a
**8.6163%** (ventana 12m, sin segmentar por día de semana todavía) en los 4 scripts de
backtest y en `meta_agosto_capital_asegurado.py` (v6). Backtest re-corrido — movimiento chico
en los 4 meses (afecta solo el componente fantasma): abril -19.2%→**-19.0%**, mayo
-6.8%→**-6.5%**, junio +1.6%→**+1.9%**, julio -3.3%→**-3.0%**. Meta de agosto:
S/16,211,015→**S/16,257,325** (+0.3%). `SEGUIMIENTO.md` y `ESTADO.md` ya actualizados. **Los 2 artifacts afectados
([📈 Proyectado vs. Real](https://claude.ai/code/artifact/f80d3761-732c-483b-99ad-d85c95c896aa)
y [🔒 Capital asegurado](https://claude.ai/code/artifact/d4140b13-4017-4313-b140-7d8f6356d5d7))
ya fueron republicados 2026-08-25** con los números nuevos, pasando `url=` (URLs
conservadas) — incluye las series diarias de julio (ambos) y agosto (Capital asegurado)
regeneradas desde los scripts, no solo los totales.
Tampoco se segmentó la tasa por día de semana (semana 9.08%-9.36% vs. fin de semana
5.67%-6.31%, estable entre ventanas) — queda como refinamiento futuro si se justifica.

**✅ FASE 4 EJECUTADA 2026-08-25 — modelo UNIFICADO (stock + nuevos con `dias_atraso_cuota`,
SIN capa fantasma) construido y backtesteado en los 4 meses. DECISIÓN DEL USUARIO PENDIENTE.**
Alcance acordado antes de correr: solo Enfoque alfa, segmentación idéntica a producción (una
variable a la vez). Archivos: `tarea17_fase4_*.sql` (7 queries), `backtest_fase4_unificado.py`,
`datos_tarea17_fase4/`. Detalle completo en bug 16 (`BUGS.md`). Resumen:

| Mes | Error unificado | Error producción | Error prod. corregido (bug 20) |
|---|---:|---:|---:|
| Abril 2026 | -12.6% | -19.0% | -13.4% |
| Mayo 2026 | -8.7% | -6.5% | -6.5% |
| Junio 2026 | -2.6% | +1.9% | +1.9% |
| Julio 2026 | -5.0% | -3.0% | -3.0% |
| media \|error\| | 7.22% | 7.59% | **6.20%** |

- **La masa cuadra exacto:** `P_ENTRADA` unificada = 21.9918% vs. `13.38% + 8.6163%` =
  21.9963% de producción (0.005pp de diferencia). Sin deriva mensual.
- **Lo que la tasa plana tenía mal es la forma:** `P_FANTASMA` es ciega a `avance_band`; la
  activación real del día 0 va de 8.13% (banda a) a 6.73% (banda d). Efecto neto: -2.0% a
  -2.6% de proyección, **uniforme en los 4 meses**.
- **Toda la varianza mes a mes viene del cambio de insumos, no de la curva** — y el +11.6%
  de abril resultó ser un bug propio (**bug 20**, nuevo).
- **Por qué empeora el error:** el parche plano enmascaraba el sesgo de "nuevos" por ser
  sistemáticamente generoso (fantasma +8.2%/+13.2%/+16.3% contra nuevos -20.1%/-8.0%/-19.2%).
  El unificado deja un solo componente con sesgo de **signo constante en los 4 meses**
  (-16.4/-9.8/-3.9/-5.1), aprox. la mitad de la magnitud, sin compensación accidental.
- **El mecanismo de fin de semana NO explica el resultado** (mix medido por mes: mayo 36.5%,
  abril 30.1%, junio 27.0%, julio 23.3%, baseline 28.9% — no ordena con el error).
- **Ganancia estructural:** bug 12, bug 14/17, bug 18 y bug 20 se vuelven imposibles por
  construcción (un solo calendario indexado por día de entrada, un solo universo).

**✅ ADOPTADO EN PRODUCCIÓN 2026-08-25 (decisión del usuario).** El Enfoque alfa corre con
el motor unificado; la capa fantasma ya no existe. Entregado:
- `motor_unificado.py` (proyector compartido: tasa, curvas, calendario por día de entrada).
- `backtest_capital_asegurado_unificado.py` — los 4 meses en una corrida, con series diarias
  en `datos_backtest_unificado/`. Reemplaza a `backtest_capital_asegurado_{abril,mayo,junio}.py`
  y `_julio_diario.py`, que quedan como referencia histórica.
- `meta_agosto_capital_asegurado.py` **v7** — meta S/16,257,325 → **S/17,274,766** (+6.3%),
  avance al 21-ago **-0.3%** (antes +4.8%). Insumos nuevos:
  `tarea17_fase4_meta_agosto_insumos.sql`, `tarea17_fase4_real_agosto.sql`,
  `tarea17_fase4_real_agosto_segmentado.sql`.
- Curvas de producción en `datos_capital_asegurado/curva_unificada_{stock,nuevos}_seg.csv`.
- Los 2 artifacts republicados (URLs conservadas) y `SEGUIMIENTO.md`, `ESTADO.md`,
  `README.md`, `CLAUDE.md` actualizados.
- **bug 20** resuelto por construcción (ver `BUGS.md`).

**Si se adopta, lo que falta hacer (no hecho todavía):**
1. Reescribir los 4 scripts de backtest sobre el motor unificado (o reemplazarlos por
   `backtest_fase4_unificado.py`, que ya corre los 4 en una pasada).
2. Rehacer `meta_agosto_capital_asegurado.py` (v7) con el calendario prospectivo unificado —
   requiere una query nueva de calendario para agosto (status = 'ACTIVE' solamente, ver
   `CLAUDE.md`), no incluida en Fase 4.
3. Recalcular la meta vigente de agosto y el avance al corte, y republicar los 2 artifacts
   pasando `url=` (conservar URLs).
4. Actualizar `SEGUIMIENTO.md`, `ESTADO.md`, `README.md` y `FUENTES_DATOS.md`.
5. Decidir aparte qué hacer con **bug 20** (fix del calendario de abril) — si se adopta Fase 4
   queda resuelto por construcción; si NO se adopta, hay que aplicarlo igual.

**Refinamiento posterior (deliberadamente fuera de esta fase):** segmentar la curva por día de
semana del vencimiento y simplificar `avance_band` a 3 buckets — ambos medidos en Fase 2/3,
ninguno probado contra el backtest.

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

### Tarea 18 — Lo que deja abierto el motor unificado (tarea 17 Fase 4, adoptada 2026-08-25; 18a/18f adoptadas 2026-08-26)

**Contexto:** el Enfoque alfa ya corre con `dias_atraso_cuota` y sin capa fantasma (ver tarea
17 y `BUGS.md` bug 16 Fase 4). Estos son los frentes que quedaron deliberadamente fuera de
esa adopción, en orden de prioridad.

**18a — Segmentar la curva por día de la semana del vencimiento, y simplificar `avance_band`
a 3 buckets — MEDIDA 2026-08-25, DECISIÓN PENDIENTE DEL USUARIO.** Los dos refinamientos estaban medidos pero
nunca probados contra el backtest; se dejaron fuera a propósito para aislar una variable a la
vez (decisión del usuario al aprobar Fase 4).
- **Día de semana:** Fase 2 midió que la forma de la curva difiere ~2x en el día 1 desde la
  entrada (fin de semana 30.96% vs. entre semana 14.84%); Fase 3 midió que la tasa de
  resolución mismo-día también difiere (semana 9.08%-9.36% vs. fin de semana 5.67%-6.31%).
  Con el motor unificado el día 0 de la curva ES esa población, así que el segmentador aplica
  directo. **Ojo:** el diagnóstico de Fase 4 mostró que el mix de fin de semana por mes
  (mayo 36.5%, abril 30.1%, junio 27.0%, julio 23.3%, baseline 28.9%) **no ordena** con el
  error — así que esto no es una explicación del sesgo residual, es un refinamiento de forma.
- **3 buckets de avance** (`<10%` / `10-40%` / `40%+`): observación del usuario de que 40-70%
  y 70%+ no se separan bien. **Pero** el día 0 de la curva unificada sí los separa
  (31.635% vs. 30.61%) y el segmento 70%+ es el que más se desvía en agosto (+89.0% real vs.
  meta al 21-ago) — revisar con ese dato antes de colapsarlos.
- Correr con `backtest_capital_asegurado_unificado.py` y comparar contra el baseline actual
  (abril -12.6%, mayo -8.7%, junio -2.6%, julio -5.0%, media 7.22%). **No adoptar por mejora
  de error** — adoptar si el universo/medición queda más fiel, per `CLAUDE.md`.

**✅ 18a EJECUTADA 2026-08-25 — los dos refinamientos se separan limpio: el día de semana SÍ
(pero con otro corte que el propuesto), los 3 buckets NO. Sin cambios a producción —
recomendación pendiente de decisión del usuario.** Código:
`backtest_tarea18a.py` (7 variantes en una corrida, reusa `motor_unificado.proyectar` sin
tocarlo), `tarea18a_curva_nuevos_dow.sql` (corte binario) y `tarea18a_curva_nuevos_dow7.sql`
(día de semana abierto), datos en `datos_tarea18a/`. La variante V0 reproduce el baseline
publicado al centésimo en los 4 meses, así que la comparación es manzana con manzana.

| Variante | abril | mayo | junio | julio | media \|err\| | corr. incrementos diarios |
|---|---:|---:|---:|---:|---:|---:|
| V0 4 bandas, sin dow (**producción**) | -12.6% | -8.7% | -2.6% | -5.0% | **7.22%** | 0.577 |
| V1 4 bandas × dow binario | -12.4% | -10.1% | -2.7% | -4.4% | 7.40% | 0.781 |
| V2 **3 bandas**, sin dow | -12.6% | -8.7% | -2.6% | -5.0% | **7.22%** | 0.576 |
| V3 3 bandas × dow binario | -12.4% | -10.1% | -2.7% | -4.5% | 7.40% | 0.781 |
| **V4 4 bandas × dow abierto** | -11.9% | -10.8% | -2.9% | -3.8% | 7.35% | **0.878** |
| V5 3 bandas × dow abierto | -11.9% | -10.8% | -2.9% | -3.8% | 7.35% | 0.878 |
| V6 4 bandas × tipo de día de entrada (3 regímenes) | -12.1% | -10.4% | -2.8% | -4.0% | 7.31% | 0.849 |

**(1) El corte binario `finde`/`semana` de Fase 2/3 está mal puesto — ver bug 21.** Ninguna
cuota vence domingo (0.00% del calendario Y de la calibración), así que `finde = {sáb,dom}`
es en la práctica solo "venc. sábado", y manda "venc. viernes" —que entra **sábado**, día no
hábil— al bucket `semana`. Los regímenes reales son entrada hábil (día 0: 37-42%), entrada
sábado (27.4%) y entrada domingo (18.7%). Abierto a los 6 días que existen, el segmentador
captura **0.878** de correlación contra 0.781 del binario.

**(2) El error de fin de mes es la medida MENOS sensible a este refinamiento, y por eso casi
no se mueve (7.22% → 7.35%).** Casi todo lo que el segmentador distingue se gasta en los
primeros días: la dispersión entre días de semana (max-min de la curva ponderada) es
**23.3pp en el día 0, 6.8pp en el día 3 y 2.0pp en el día 30** — o sea las curvas convergen
~92% antes del día 3. Una cohorte que entra a principio de mes recorre la curva entera y
termina casi donde habría terminado sin segmentar; el efecto sobre el total del mes entra
**sobre todo por las cohortes del final del mes**, que alcanzan a recorrer nada más que los
días 0-3 — justo donde la diferencia vive. Eso
explica el signo mes a mes sin ninguna apelación al azar: en los últimos 5 días del mes el
saldo con venc. de fin de semana es 45.8% en mayo (proyección baja, error empeora a -10.8%),
32.4% en abril, 21.9% en junio y **0.0% en julio** (proyección sube, error mejora a -3.8%).

**(3) Lo que el segmentador sí arregla es la TRAYECTORIA diaria — que es para lo que existe
el proyecto (meta *diaria*).** La correlación entre incrementos diarios proyectados y reales
sube en los **4 meses sin excepción**: 0.647→0.901 (abr), 0.318→0.875 (may), 0.620→0.887
(jun), 0.720→0.849 (jul). En mayo —el peor mes de V0— el error absoluto medio del incremento
diario cae de **S/132K a S/68K (-48%)**. V0 falla con patrón semanal reconocible: sobreproyecta
los días de entrada domingo (+146/+173/+180/+153/+243 mil) y subproyecta los lunes
(-331/-139/-219/-191 mil), que no tienen cohorte nueva pero concentran el repago rezagado del
fin de semana. V4 corrige los dos, porque al segmentar por día de entrada la curva sabe que
el "día 6" de una cohorte que entró martes cae lunes.

**(4) Los 3 buckets de avance NO se adoptan.** El colapso c+d es numéricamente **nulo**: el
efecto máximo sobre el total de un mes es **0.008%** (julio), y sobre el error, 0.007pp. No
cuesta nada pero tampoco aporta nada, y **cuesta resolución de diagnóstico justo donde hay
señal**: en agosto al 21-ago la banda 70%+ corre **+89.0%** sobre lo proyectado y la 40-70%
**+22.3%** — colapsadas dan +28.6%, que esconde que el bucket chico va al doble. Per el
criterio de `CLAUDE.md`, el colapso no hace la medición más fiel, la hace más gruesa. La
observación original (que las dos bandas no se separan) es **correcta como enunciado sobre la
forma de la curva** —difieren ≤3.9% en relativo y se cruzan en el día 14— pero `avance_band`
no es solo segmentador de curva: también es el eje por el que se lee la desviación.

**RECOMENDACIÓN (no decisión — es del usuario): adoptar V4** (4 bandas × día de semana del
vencimiento abierto), y **no** colapsar `avance_band`. El razonamiento es el criterio de
`CLAUDE.md` aplicado literal: cambia **cómo se mide** —cada día del calendario tiene un día de
semana único, así que hoy el proyector le aplica a *todos* los días una curva mezclada que no
corresponde a *ninguno*— y la trayectoria diaria queda medida más fiel en los 4 meses. El
+0.13pp de error de fin de mes no es información perdida: es el mismo sesgo de "nuevos" de
18b, redistribuido. **Riesgo a mirar antes de adoptar:** V4 abre 24 celdas de calibración y la
más chica queda en 1,241 entradas (banda 70%+ × venc. jueves). Si eso preocupa, V6 (3
regímenes de día de entrada: hábil / sábado / domingo, 12 celdas) conserva **0.849** de los
0.878 — pero **compra menos robustez de lo que parece**: solo engrosa el lado hábil (4 días
en 1), que ya era el más gordo, y deja intactas las celdas realmente flacas, que son las de
sábado y domingo. La celda mínima pasa de **1,241 a 1,519 entradas (+22%)**, no al doble.
Como el 0.03 de correlación que se cede sí es real, V6 solo vale la pena si además se decide
engrosar de otra forma la banda 70%+ (ej. no segmentarla por día de semana).

**✅ 18a + 18f CERRADAS 2026-08-25 con un walk-forward de 7 meses sin leak
(`backtest_tarea18f.py`).** Protocolo acordado con el usuario: **calibración de 12 meses
rodantes** (`[M-12, M-1]`, la curva de nuevos nunca ve el mes que proyecta) y **7 meses de
test** (202601-202607), que es lo que da la historia con piso de 3,000 entradas/mes — antes
de 202501 la cartera es <20% de la actual y la dispersión de la curva se duplica (ver
`tarea18_ventana_calibracion.sql`). Sale gratis en corridas de Athena porque las curvas se
arman desde una **matriz cruda** al grano `(fecha_entrada, banda, día_primer_pago)`
(`tarea18f_curva_cruda.sql` + `curvas_crudas.py`): recalibrar 7 ventanas × 4 variantes cuesta
0 queries adicionales.

| Variante | ene | feb | mar | abr | may | jun | jul | media \|err\| | corr. diaria | MAE inc. diario |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| W0 banda (**producción**) | -11.4% | -18.7% | -14.3% | -12.5% | -8.5% | -2.6% | -5.1% | 10.43% | 0.611 | S/124K |
| **W1 banda × dow** | -11.8% | -18.6% | -14.3% | -11.8% | -10.7% | -2.9% | -3.8% | 10.54% | **0.875** | **S/75K** |
| W2 banda + f | -10.7% | -19.6% | -14.3% | -12.7% | -8.0% | -3.1% | -4.7% | 10.44% | 0.622 | S/123K |
| **W3 banda × dow + f** | -11.2% | -19.6% | -14.1% | -11.9% | -10.9% | -3.2% | -3.0% | 10.55% | **0.886** | **S/73K** |

- **El día de semana (18a) se confirma en los 7 meses sin excepción**, ahora sin leak: la
  correlación de incrementos diarios va de 0.611 a **0.875** y el error absoluto medio del
  incremento diario cae **-39%** (S/124K → S/75K). Mejora los 7 meses, uno por uno.
- **El factor por día del mes (18f) es real pero chico.** Encima del día de semana suma
  +0.011 de correlación y -3% de MAE (mejora 5-6 de 7 meses). Solo, sin día de semana, casi
  no hace nada (+0.011).
- El error de fin de mes se mueve ±0.12pp entre las 4 variantes — sigue sin poder arbitrar
  esta decisión (ver el cálculo de poder abajo, en 18c).

**El factor `f` de 18f: 2 parámetros, no 31.** Calibrado con un parámetro por día del mes,
`f` **sobreajusta**: entre dos mitades disjuntas de la ventana la correlación es solo +0.51.
Lo que SÍ se reproduce son los días de pago de planilla — día 15 (1.140 / 1.195 en cada
mitad) y días 30-31 (1.18-1.20 en ambas). El día 29 sale **bajo** en las dos (0.959 / 0.953),
así que el efecto es de **fecha de pago**, no de "últimos días del mes". Con la agrupación
estructural `{15,16} / {30,31} / resto` los parámetros son estables en 4 ventanas distintas:

| ventana | quincena | fin de mes | resto |
|---|---:|---:|---:|
| 202501-202509 | 1.0746 | 1.1843 | 0.9829 |
| 202510-202606 | 1.0856 | 1.1947 | 0.9809 |
| 202503-202605 (producción) | 1.0938 | 1.1778 | 0.9812 |
| 202507-202606 (12m) | 1.0855 | 1.1848 | 0.9812 |

**Confirmación independiente del mecanismo:** la curva de **stock**, que ya está indexada por
día del mes y por lo tanto SÍ puede ver el efecto, tiene la quincena **+12%** sobre su propia
tendencia local (anomalía 1.119 en días 14-16 vs. 0.900 del resto, con el hazard detrendado
contra una media móvil de 7 días). O sea el efecto no es un artefacto del ajuste: existe, y
el componente de nuevos era el único ciego a él.

`f` multiplica el **incremento diario**, no el acumulado, y se normaliza a media ponderada 1
— **redistribuye** masa dentro del mes en vez de agregarla. Se calibró **solo sobre la
ventana histórica**; los residuos del backtest se usaron para detectar el fenómeno, nunca
para ajustar el factor (`CLAUDE.md`).

**✅ ADOPTADO W3 EN PRODUCCIÓN 2026-08-26 (decisión del usuario), y la meta de agosto
recalculada (también decisión del usuario).** Propagado a `motor_unificado.py` **v2** (el
proyector aplica `f` sobre incrementos y acepta claves `(banda, dow)`),
`generar_curvas_produccion.py` → `datos_capital_asegurado/curva_unificada_nuevos_dow_seg.csv` +
`factor_dia_mes.csv`, `meta_agosto_capital_asegurado.py` **v8**,
`backtest_capital_asegurado_unificado.py` reescrito a 7 meses con calibración rodante, y los
**2 artifacts republicados** (URLs conservadas) vía `armar_proyectado_vs_real.py` y
`armar_capital_asegurado.py`. **Meta de agosto: S/17,274,766 → S/17,117,628 (-0.9%)**; curvas
calibradas `[202507, 202606]` — los 12 meses completamente observados al 1-ago, con julio
afuera a propósito porque al fijar la meta sus cohortes no tenían los 31 días de seguimiento.
Backtest oficial nuevo en `SEGUIMIENTO.md`.

**RECOMENDACIÓN ORIGINAL (que el usuario adoptó): W3** (4 bandas × día de semana del
vencimiento + factor de quincena/fin de mes), y **no** colapsar `avance_band` a 3 buckets.
Criterio de `CLAUDE.md`: cambia **cómo se mide** —hoy el proyector aplica a cada día una curva
mezclada que no corresponde a ninguno, y es ciego a la quincena— y la trayectoria diaria queda
más fiel en los 7 meses. **Si se prefiere mínima complejidad, W1 captura ~96% de la ganancia
con 0 parámetros nuevos** y es una decisión perfectamente defendible; `f` agrega 2 parámetros
por un +0.011 de correlación.

**Lo que la adopción implica** (no ejecutado — producción sigue intacta): propagar a
`motor_unificado.py` (el proyector tiene que aplicar `f` sobre incrementos y aceptar claves
`(banda, dow)`), regenerar `datos_capital_asegurado/curva_unificada_nuevos_seg.csv`,
re-correr `backtest_capital_asegurado_unificado.py` y `meta_agosto_capital_asegurado.py`, y
republicar los 2 artifacts.

**18b — Explicar el sesgo de "nuevos", que ahora está expuesto entero.** Con el parche plano
fuera, los 4 meses subestiman con **signo constante**: -16.4% (abr), -9.8% (may), -3.9%
(jun), -5.1% (jul). Es aprox. la mitad de la magnitud que tenía con 3 componentes, pero ya
sin la sobreestimación compensatoria del fantasma. Lo que ya se sabe y no hay que repetir:
la tasa de entrada NO deriva (Fase 4 la midió mes a mes, rango 20.39%-23.82% sin tendencia),
y en agosto el exceso es volumen y no efectividad condicional
(`analisis_volumen_efectividad_agosto.md`). Conecta con tarea 9 y con el hallazgo de mix de
agosto (avance 70%+ activando +89% sobre la curva). **Explicarlo, no ajustarlo.**

**✅ 18b MEDIDA 2026-08-26, con los 7 meses del backtest oficial (W3) y sin Athena** (toda la
evidencia sale de `datos_tarea18a/` + la matriz cruda). Detalle completo, con tablas y
correlaciones, en `analisis_sesgo_nuevos_18b.md` (reproducible con
`analisis_sesgo_nuevos_18b.py`). Dos hallazgos, cada uno con mecanismo propio — **diagnóstico,
no ajuste de producción**:

1. **`P_ENTRADA` (21.9918%) se calibró contando CRÉDITOS (`tarea17_fase4_tasa.sql`, el propio
   comentario del archivo lo dice: "Salida en creditos, no soles") pero se aplica multiplicando
   SALDO EN SOLES del calendario** (`motor_unificado.proyectar`, y también en producción vía
   `meta_agosto_capital_asegurado.py`). Como el exceso de entrada a mora está concentrado en
   créditos de saldo alto (ya medido en agosto: +8.5% por conteo vs. +26.3% en soles), la tasa
   por conteo subestima estructuralmente la tasa que el modelo necesitaría. Medido mes a mes
   con la misma matriz cruda que arma la curva: la tasa real ponderada por soles corre
   **24.34%-27.22%**, siempre 11%-24% por encima de la fija, en los 6 meses medibles (jul queda
   fuera del rango de la matriz cruda, 20250101-20260630). Sustituir solo la tasa (dejando todo
   lo demás intacto) cierra **~78% de la magnitud del error de "nuevos" en 5 de 6 meses**
   (71%-84%), de errores de dos dígitos a residuos de ±3-6%; correlación error-vs-tasa real
   **r=-0.93**. Junio es la excepción (el residuo de forma pesa más ahí, ver el .md). **No
   contradice** el "sin deriva mensual" de Fase 4 — esa medición es por conteo, ésta por
   soles; son coherentes entre sí y con `analisis_volumen_efectividad_agosto.md`.
2. **Febrero (el único mes de 28 días del test) es también el único mes donde STOCK falla
   fuerte (-11.0%) porque el modelo indexa "fin de mes" por NÚMERO de día calendario (30/31,
   ver `GRUPOS_DIA_MES`), no por cercanía real al cierre.** Un mes de 28 días nunca llega a
   esos días, así que su cierre real (día 28) siempre cae en el grupo "resto" (factor 0.9812,
   por debajo del promedio). El 28 de febrero, solo, explica **79.3%** del gap de stock del mes
   entero — ningún otro mes concentra así su gap en el último día. **Corrección tras repregunta
   del usuario:** el efecto real, medido reagrupando por días-para-fin-de-mes (0=último día real,
   sea 28/30/31) sobre la muestra grande de "nuevos", es un **pico angosto en el último día**
   (+63% sobre el baseline, `dpf=0`: 4.536% vs. baseline 2.786%) — el penúltimo día NO se
   despega del baseline (`dpf=1`: 2.827%). No es "último o penúltimo", es solo el cierre real.
   Esto también implica que el grupo `{30,31}` actual diluye el factor `f`: en un mes de 31
   días el 31 es el pico y el 30 es casi-baseline, agruparlos junto sub-estima el verdadero pico
   — afecta a TODOS los meses de 31 días, no solo a febrero.
3. **Hipótesis del handoff descartada:** el tamaño del calendario del mes (en soles o en días)
   correlaciona débil con el error (r=+0.48 / +0.47) — mucho más débil que la tasa de entrada
   real (r=-0.93) y es sobre todo un proxy ruidoso de la tendencia temporal (la cartera crece
   con el tiempo).

**Ninguno de los dos hallazgos se llevó a producción.** Si el usuario decide actuar: el de
`P_ENTRADA` requiere recalibrar con definición consistente (soles) y correr el backtest
completo (patrón del bug 10, no parchar la constante); el de febrero requeriría re-indexar la
curva de stock (y el factor `f`) por "días hasta fin de mes" en vez de número de día
calendario — un cambio de forma que se arbitraría con métricas diarias, no con el error de
cierre (mismo criterio que 18a/18f).

**✅ 18g EJECUTADA Y PARCIALMENTE ADOPTADA 2026-08-26 — formalizó y probó el reindex por cierre
real de 18b contra el walk-forward de 7 meses, para nuevos y stock.** Query nueva
(`tarea18g_curva_cruda_stock.sql`, matriz cruda de stock 202501-202606, valida contra
producción), código (`curvas_crudas_stock.py`, `backtest_tarea18g.py`), detalle completo en
`analisis_tarea18g_cierre_real.md`. **Resultado — mejora real pero chica en stock, marginal en
nuevos, y rodar la ventana de stock por separado EMPEORA las métricas diarias:**
- **Stock + factor de cierre real (Y2): ✅ ADOPTADO EN `motor_unificado.py` v3** (decisión del
  usuario). Corr. diaria stock 0.841→0.848, MAE 27.3K→26.7K. En **febrero específicamente** (el
  caso que motivó esto): err. stock -11.0%→**-8.3%**, corr. 0.818→0.856 — mejora real y
  dirigida, pero **no lo resuelve del todo** (sigue siendo el peor mes de stock por lejos).
  `proyectar()` acepta ahora `f_dm_stock` (opcional, `None`=comportamiento idéntico a v2 —
  verificado con regresión antes de tocar nada más). Curva nueva en
  `datos_capital_asegurado/curva_unificada_stock_seg_v3.csv` + `factor_dia_mes_stock.csv`
  (quincena=1.0068, cierre=1.8698, resto=0.9717), ventana FIJA 202504-202606 (igual que
  siempre). Backtest oficial re-corrido (`backtest_capital_asegurado_unificado.py`) — media de
  error 10.55%→**10.26%**, ver `SEGUIMIENTO.md`.
- **Nuevos reindexado (Y1): documentado, NO adoptado.** Corr. 0.886→0.888, MAE 72.5K→72.1K —
  casi sin efecto; el grupo `{30,31}` de producción, aunque diluido, ya capturaba la mayor
  parte de la señal. Adoptarlo requeriría cambiar el esquema de agrupación compartido de
  `grupo_dia_mes`, que también usa la meta de agosto ya publicada — no se justifica el riesgo
  por un beneficio marginal. Queda para una pasada separada y deliberada, sin un mes en curso
  que proteger.
- **Rodar además la ventana de stock (Y4, bonus que también cerraría 18c): EMPEORA, NO
  adoptado.** Corr. stock 0.848→0.820, MAE 26.7K→29.3K, y vuelve a empeorar febrero
  (-8.3%→-9.0%). Stock es el componente de mayor varianza muestral (`BUGS.md`) — una ventana
  rodante de 12 meses le da a los meses de test tempranos una historia de calibración
  demasiado chica. **18c no sale gratis para stock como salió para nuevos** — sigue abierta,
  necesita su propia evaluación (quizás ventana más larga que 12 meses).
- **La meta de agosto (S/17,117,628, `meta_agosto_capital_asegurado.py`) NO se tocó** —
  verificado con regresión (mismo `+1.0%` al 25-ago antes y después de este cambio). Sigue
  leyendo los archivos originales (`curva_unificada_stock_seg.csv`, sin sufijo `_v3`). El
  factor de cierre queda listo para la meta de **septiembre** — que además todavía no se puede
  calibrar en su ventana propia [202508,202607] hasta que julio complete sus 31 días de
  seguimiento (recién el 31-ago).

**✅ 18c RESUELTA PARCIALMENTE 2026-08-25 (queda solo el stock).** El walk-forward de 18a/18f
mide el leak directamente: calibrando rodante sin leak contra la ventana fija de producción,
los 4 meses comparables se mueven **0.11 / 0.17 / 0.01 / -0.09 pp, media 0.10pp** — consistente
con (y algo por debajo de) los 0.15-0.2pp que tarea 10 midió sobre la arquitectura de 3
componentes. El mecanismo se sostiene en el motor unificado.

**Lo que falta:** la curva de **stock** no rueda — sigue calibrada en 202504-202606, así que 6
de los 7 meses de test están dentro de su ventana. Eso hace **optimista el nivel absoluto de
error de ene-jun**, pero no afecta la comparación entre variantes (el componente de stock es
idéntico en las 4 y se cancela). Para cerrar 18c del todo hay que emitir la matriz cruda
equivalente para stock y rodar también esa curva.

**Cálculo de poder, para no volver a discutirlo:** la diferencia pareada W1-W0 del error de
fin de mes tiene media -0.13pp y **desvío 1.49pp** — el ruido es 10x el efecto, porque el
signo lo fija la composición de fin de mes de cada mes. Detectar 0.13pp sobre el error de
cierre necesitaría **~1,050 meses**. El error de fin de mes es el número de negocio y el
insumo de 18b; **no es el árbitro de los refinamientos de forma** — eso se decide con métricas
diarias, que aportan ~30 puntos por mes en vez de 1.

**18c (original) — Repetir la prueba de robustez fuera de muestra sobre el motor unificado.** La que
existe (tarea 10, movimiento de 0.15-0.2pp) se corrió sobre la arquitectura de 3 componentes
con curvas `dayslate`; el artifact `proyectado_vs_real.html` ya lo aclara en su sección 05.
Las curvas unificadas calibran con `periodo_meta 202504-202606` (stock) y
`fechaproceso 20250301-20260531` (nuevos), o sea siguen dejando entrar mayo y junio. El
mecanismo es el mismo y la conclusión debería sostenerse, pero no está medido.

**18d — `resumen_julio_agosto.html` y `armar_artifact_julio_agosto.py` quedaron
desactualizados.** Describen el Enfoque alfa con capa fantasma y `P_FANTASMA=8.5524%` — dos
versiones atrás, ya estaban desactualizados antes de Fase 4. El builder mezcla los dos
enfoques (recupero oficial + alfa); solo el lado alfa necesita rehacerse sobre
`motor_unificado.py`. Ver tarea 5 (destino de artifacts desactualizados).

**✅ 18d EJECUTADA 2026-08-26 — REHECHO, no retirado.** `armar_artifact_julio_agosto.py`
reescrito de punta a punta sobre el motor unificado v3: julio usa el backtest oficial (stock
con factor de cierre), agosto usa la meta v2/W3 ya fijada (no se retoca a mitad de mes — ver
tarea 18g), y el recupero oficial usa `meta_agosto.py` v3 con el real refrescado (ya no
hardcodeado, ver `tarea18d_real_agosto_recupero.sql` — nueva query, mismo patrón día-por-día
que ya tenía capital asegurado). La sección 4 vieja ("Diferencias con la reconciliación —
de dónde sale la capa fantasma") se reemplazó por "Cómo se afina la curva": día de semana +
factor de quincena/cierre (18a/18f/18g), con la nota explícita de que el error de fin de mes
no arbitra esa decisión. La trayectoria de agosto ahora grafica el REAL día a día (antes era
una recta aproximada entre 0 y el corte — la única serie real que existía era un total
único). Republicado en la misma URL (`949ab3c2-...`). `README.md` y `ESTADO.md`
actualizados.

**18e — Decidir si el motor de recupero oficial se migra a `dias_atraso_cuota`.** Sigue con
`dayslate` (`fase1_stock.sql`, `fase2_nuevos.sql`, `fase3_backtest.sql`) y nunca tuvo capa
fantasma, así que el punto ciego de bug 9 está ahí **sin compensar de ninguna forma**. No se
decidió nada; el alcance de Fase 4 fue solo Enfoque alfa, a pedido del usuario. Si se hace,
el patrón ya está probado — `motor_unificado.py` + las 9 queries `tarea17_fase4_*.sql`.

**✅ 18e DECIDIDA 2026-08-26 (recomendación, NO ejecutada todavía) — SÍ migrar, pero como
sesión dedicada aparte, no como agregado del mismo día.** Razonamiento:
- **Por qué sí, en principio:** el mecanismo es idéntico al que justificó Fase 4 — bug 9 (el
  punto ciego de ~1 día de `dayslate`, 95.7% de los pagos exactamente 1 día tarde no se
  detectan) aplica igual acá, sin ninguna compensación. Es el mismo argumento de "universo
  debe cuadrar contra una fuente fiel" de `CLAUDE.md`, no una mejora de error buscada.
- **Por qué NO ahora mismo, en la misma pasada:** a diferencia de repetir un patrón ya armado,
  esto necesita **queries nuevas desde cero** — Recupero Oficial mide **rebaje real en soles**
  (`saldo_ant - saldo`, cuánto capital efectivamente bajó), no activación binaria como Capital
  Asegurado (si hubo o no cualquier pago). Los scripts de hoy (`curvas_crudas.py`,
  `curvas_crudas_stock.py`, `motor_unificado.py`) están armados para el concepto de
  "activación", no de "monto pagado" — no se pueden reusar directo. El tamaño real es
  comparable a la Fase 4 completa (curva de stock + curva de nuevos + tasa de entrada + 2-3
  backtests de validación), no a una tarea chica.
- **Contexto que baja la urgencia:** Recupero Oficial dejó de ser la meta principal reportada
  desde 2026-07-13 (`ESTADO.md`) — se sigue trackeando en paralelo como "modelo validado", no
  como el número que se comunica. Migrarlo mejora la fidelidad de un tracking secundario, no
  de la meta vigente.
**PLAN DE EJECUCIÓN (armado 2026-08-26, para una sesión dedicada — no ejecutado)**, en 4 fases,
espejo de tarea 17 Fase 4 pero para rebaje en soles en vez de activación binaria:

- **Fase A — Tasa de entrada unificada, en la MISMA definición que necesita 18b.** Reusar el
  patrón de `tarea17_fase4_tasa.sql` (`dias_atraso_cuota` 0→1, calendario elegible = entrada
  dentro del mes, excluye stock) pero — a diferencia de esa query original — calibrar **por
  SOLES, no por conteo de créditos**. La tarea 18b (`analisis_sesgo_nuevos_18b.md`) ya mostró
  que P_ENTRADA calibrada por conteo subestima la tasa real cuando se aplica a un calendario en
  soles, porque el exceso de entrada se concentra en créditos de saldo alto — el mismo error no
  se debe repetir acá. Salida esperada: una tasa (o su desglose mensual) directamente
  comparable, en la misma unidad, con el calendario de soles que arma Recupero Oficial.
- **Fase B — Curva de stock en REBAJE, indexada por `dias_atraso_cuota`.** `fase1_stock.sql`
  YA calcula rebaje (`max(saldo_ant - saldo, 0)`) — el cambio es puntual: reemplazar
  `coalesce(dayslate,0)` por `dias_atraso_cuota` de
  `dts_cobranza_creditos_calendario_diario` (mismo join que ya usa
  `tarea17_fase4_curva_stock.sql`) como fuente de `mora`/tramo. El resto del query (rebaje,
  tramo × avance, ventana de calibración) no cambia de forma.
- **Fase C — Curva de nuevos en REBAJE, indexada por `dias_atraso_cuota`.** Mismo cambio
  puntual sobre `fase2_nuevos.sql`: la entrada (`mora_ant=0 → mora=1`) se redefine sobre
  `dias_atraso_cuota` en vez de `dayslate`, arrastrando el punto ciego de bug 9 a la
  reconstrucción en vez de dejarlo sin compensar. El "saldo_entrada" (fix de Fase 3, saldo del
  día ANTERIOR a la entrada) se mantiene igual.
- **Fase D — Backtest de al menos 2-3 meses cerrados, motor nuevo vs. motor vigente, antes de
  decidir.** No se adopta por mejora de error (`CLAUDE.md`) — se adopta si el universo/medición
  queda más fiel (cierra el punto ciego de bug 9), aunque el error suba, igual que se hizo con
  Fase 4 y con W3 en Enfoque alfa.

Nada de esto está bloqueado por otra tarea — se puede arrancar en cualquier momento. Queda
anotado, no bloqueante para nada de lo demás.

**✅ 18e FASES A-D EJECUTADAS 2026-08-26 (continuación 2) — motor completo de Recupero
Oficial migrado a `dias_atraso_cuota` y respaldado con backtest de 7 meses. RECOMENDACIÓN
armada, NO adoptado en producción — decisión pendiente del usuario.**

**Fase A — tasa de entrada por SOLES, mismo mecanismo que 18b confirmado fuera del Enfoque
alfa.** Query `tarea18e_fase_a_tasa_soles.sql` (reusa el patrón de `tarea17_fase4_tasa.sql` +
`tarea18_calendario_7m.sql` para el saldo en la fecha exacta de vencimiento con dedup de bug
11), datos en `datos_tarea18e/tasa_soles.csv`. Misma ventana que `P_NO_PAGA_DIA0` y
`P_ENTRADA` (ago2025-may2026) para que las tres tasas sean comparables.

- **Tasa por conteo: 21.9941%** (75,613/343,788) — prácticamente idéntica a `P_ENTRADA`
  (21.9918%, 75,621/343,860) del Enfoque alfa. La diferencia mínima es el join a
  `dts_mambu_loans_hist` en la fecha exacta de vencimiento (unos pocos créditos sin foto esa
  fecha exacta quedan fuera). Confirma que el salto grande (13.38%→~22%) es casi todo el
  cambio `dayslate`→`dias_atraso_cuota` (cierra el punto ciego de bug 9, ya medido en Fase 1
  de tarea 17: cobertura 70.4%→96.3%), no la unidad de medida.
- **Tasa por soles: 25.1924%** (S/112.8M / S/447.9M) — **+14.5% relativo** sobre la de conteo,
  mismo signo y mecanismo que 18b (el exceso de entrada se concentra en créditos de saldo
  alto). Por mes corre **23.4%-27.2%**, sin tendencia — mismo rango de dispersión que el
  22.99%-27.22% que 18b midió para Enfoque alfa.

**Fase B — curva de stock en REBAJE, indexada por `dias_atraso_cuota`.** Query
`tarea18e_fase_b_curva_stock_rebaje.sql` (mismo cambio puntual que ya probó
`tarea17_fase4_curva_stock.sql` para Enfoque alfa: `dias_atraso_cuota` en vez de `dayslate`
para el tramo/stock, el rebaje sigue siendo deltas de `dts_mambu_loans_hist`), datos en
`datos_tarea18e/curva_stock_rebaje_dac.csv`. Ventana idéntica a la vigente (`periodo_meta`
202504-202606), 3 tramos × 4 bandas de avance.

**Fase C — curva de nuevos en REBAJE, indexada por `dias_atraso_cuota`.** Query
`tarea18e_fase_c_curva_nuevos_rebaje.sql` (mismo patrón que
`tarea17_fase4_curva_nuevos.sql`: entrada = `dias_atraso_cuota` 0→1, curva arranca en el DÍA
0, `saldo_entrada` = saldo del día ANTERIOR a la entrada — fix de Fase 3/bug 16, necesario
porque la población que paga el mismo día que entra tiene su foto de "día de entrada" ya
reflejando el pago), datos en `datos_tarea18e/curva_nuevos_rebaje_dac.csv`. Ventana idéntica
a la vigente (20250301-20260531), 4 bandas de avance.

**Fase D — backtest de 7 meses (202601-202607), motor nuevo vs. motor vigente.**
`backtest_tarea18e_recupero_oficial_dac.py` reusa `motor_unificado.proyectar()` tal cual (es
genérico — solo hace `stock×curva` y `saldo_riesgo×tasa×curva`, sin ningún supuesto de
"activación" vs. "rebaje") con los insumos de Fases A-C, más `datos_tarea18a/stock_pob_7m.csv`
/`calendario_7m.csv` (población idéntica, no depende del enfoque) y una query nueva de real en
rebaje (`tarea18e_fase_d_real_rebaje_7m.sql` → `datos_tarea18e/real_rebaje_7m.csv`, análoga a
Q-F1/Q-F2 de tarea 17 pero sumando rebaje diario en vez de activación). Log completo en
`datos_tarea18e/backtest_recupero_oficial_dac.log`.

| Mes | Proyectado | Real (dac) | error | err stock | err nuevos | corr. diaria | vigente (dayslate) |
|---|---:|---:|---:|---:|---:|---:|---|
| Enero | S/2,302,148 | S/2,290,411 | +0.5% | +0.6% | +0.5% | 0.610 | sin backtest previo |
| Febrero | S/2,091,201 | S/2,227,338 | -6.1% | -9.0% | -5.4% | 0.567 | sin backtest previo |
| Marzo | S/2,938,022 | S/3,061,707 | -4.0% | -6.2% | -3.8% | 0.716 | sin backtest previo |
| Abril | S/2,649,481 | S/2,614,085 | +1.4% | +10.6% | -1.0% | 0.562 | sin backtest previo |
| Mayo | S/3,141,698 | S/2,893,212 | +8.6% | -2.4% | +10.6% | 0.389 | sin backtest previo |
| Junio | S/2,965,487 | S/2,538,947 | +16.8% | +9.1% | +18.9% | 0.367 | err +5.4% (real S/1,713,815) |
| Julio | S/3,888,900 | S/3,280,551 | +18.5% | -2.9% | +22.1% | 0.711 | err +17.6% (real S/2,088,911) |

- **Magnitud media de error de fin de mes: 7.99%** — sin ningún refinamiento de forma (día de
  semana, factor de quincena, ventana rodante: el equivalente a "W0", no a "W3"). Comparable
  en orden de magnitud a los dos únicos puntos del motor vigente disponibles (5.4%/17.6%,
  media 11.5% sobre solo 2 meses) — no concluyente con tan pocos puntos del lado vigente, pero
  no es una regresión visible.
- **Hallazgo principal — cobertura de universo, no error de cierre:** el real capturado con
  `dias_atraso_cuota` es **148.1% (junio) y 157.0% (julio) del real capturado con `dayslate`**
  (S/2.54M vs. S/1.71M; S/3.28M vs. S/2.09M) — **+48-57% de rebaje real que el motor vigente
  nunca ve**, no +26-30% como la cobertura en CRÉDITOS que Fase 1 de tarea 17 ya midió
  (70.4%→96.3%). Mecanismo coherente con lo ya conocido, no nuevo: la razón
  `P_ENTRADA/P_NO_PAGA_DIA0 = 21.99%/13.38% = 1.643×` ya anticipaba un salto grande en
  *entradas*, y bug 16 Fase 3 ya midió que la población que `dayslate` no ve (ex-"fantasma")
  se activa **99.60% el mismo día** — population de pago casi instantáneo que aporta rebaje
  ~1:1 de su saldo apenas se detecta. Un universo de entradas +64% más grande, concentrado en
  población de altísima velocidad de pago, explica por qué el REBAJE capturado crece más que
  proporcionalmente (+48-57%) respecto al conteo de créditos (+26-30%). **Punto ciego de bug 9
  sin compensar** — exactamente el argumento por el que 18e recomendó migrar en principio.
- **Nada de esto tocó producción.** Recupero Oficial sigue con `P_NO_PAGA_DIA0=13.38%` y
  `dayslate` (`fase1_stock.sql`/`fase2_nuevos.sql`/`fase3_backtest.sql`, `meta_agosto.py`).

**RECOMENDACIÓN (no decisión — es del usuario), mismo criterio de `CLAUDE.md` que ya se aplicó
a Fase 4/18a: no se adopta por mejora de error — se adopta si el universo/medición queda más
fiel, aunque el error de cierre suba.** El hallazgo de cobertura (+48-57% de rebaje real
invisible hoy) es un argumento de universo, no de ajuste fino. **Antes de adoptar, conviene**:
(1) decidir si se calibra la tasa/curvas con ventana rodante (mismo refinamiento que 18a/18f
ya validó para Enfoque alfa — esta primera pasada usa ventana fija, igual que la vigente, así
que la comparación de error es pareja pero deja mejora sobre la mesa); (2) decidir si
corresponde recalcular `SEGUIMIENTO.md`/`meta_agosto.py` con el motor nuevo, lo que cambiaría
el número de Recupero Oficial reportado (aunque ya no es la meta principal desde 2026-07-13).

**✅ VALIDACIÓN TÉCNICA A NIVEL DE CASO 2026-08-26 (continuación 2), a pedido del usuario
("¿hay que validar algo antes de implementar?") — el salto de cobertura (+48-57%) es un
mecanismo real, no un artefacto de la query.** `tarea18e_validacion_casos_fantasma.sql` /
`datos_tarea18e/validacion_casos_fantasma.csv`: 10 créditos reales de julio donde
`dias_atraso_cuota` detecta la entrada en mora (`mora_ant=0→mora=1`) pero `dayslate` ese mismo
día vale **0** (población "fantasma", invisible al motor vigente) — en los 10 casos el saldo
efectivamente bajó ese mismo día (rebaje real de S/2,711 a S/7,749), y varios **cancelan el
saldo completo del crédito** el mismo día que técnicamente entran en mora
(ej. `dc69f32d-...`: S/7,749.55→S/0). Confirma a nivel de caso lo que bug 16 Fase 3 ya midió
en agregado (activación día 0 = 99.60%): la población que `dayslate` no ve no es marginal ni
rara, paga casi instantáneo y a veces con el saldo completo — coherente con que el REBAJE
capturado crezca más que proporcionalmente al crecimiento en conteo de créditos.

**Con esto, el hallazgo de Fase D queda validado técnicamente (no es un bug de query).** Lo
que sigue pendiente antes de adoptar en producción sigue siendo lo de arriba: ventana rodante
+ forma (día de semana, quincena — refinamiento, no bloqueante para la validez del hallazgo) y
la decisión de si/cuándo tocar `SEGUIMIENTO.md`/`meta_agosto.py`. Una validación adicional
posible pero NO ejecutada (más cara, cruza contra `vw_seguimiento_diario_cohorte_tramo`/
`dts_asignaciones_gestiones_cobranza`, mismo patrón que tarea 14/15/16/bug 19): confirmar que
la población fantasma también aparece en la asignación real de negocio (TEMPRANA), no solo en
Mambu — quedaría para si el usuario quiere blindar el número antes de publicarlo en
`SEGUIMIENTO.md`.

**✅ REFINAMIENTO DE FORMA (v2) EJECUTADO 2026-08-26 (continuación 2), a pedido del usuario
("hagamos ambos") — mismo tratamiento que 18a/18f/18g ya validaron para el Enfoque alfa,
aplicado al motor de Recupero Oficial.** `backtest_tarea18e_recupero_oficial_v2.py`, log en
`datos_tarea18e/backtest_recupero_oficial_v2.log`.

**Insumos nuevos — matrices CRUDAS de rebaje, reusando `curvas_crudas.py`/
`curvas_crudas_stock.py` SIN TOCAR NINGUNA LÍNEA de esos módulos** (el IPF que calibran trata
la columna `saldo` de cada celda como masa observada — no le importa si semánticamente es
"activación del primer pago" o "rebaje sumado día a día", así que calibra igual de bien sobre
cualquiera de las dos):
- `tarea18e_matriz_cruda_nuevos_rebaje.sql` → `datos_tarea18e/curva_cruda_nuevos_rebaje.csv`
  (grano `fecha_entrada × avance_band × dia_desde_entrada`, rango 20250101-20260630 — análoga
  a `tarea18f_curva_cruda.sql` pero sumando TODO el rebaje diario, no solo el día del primer
  pago).
- `tarea18e_matriz_cruda_stock_rebaje.sql` → `datos_tarea18e/curva_cruda_stock_rebaje.csv`
  (análoga a `tarea18g_curva_cruda_stock.sql`, rango 202501-202606).
- `tarea18e_tasa_soles_18m.sql` → `datos_tarea18e/tasa_soles_18m.csv`: Fase A extendida a
  desglose mensual 202501-202606 (18 meses) — permite rodar la tasa junto con la curva de
  nuevos, sin leak, en vez de fijarla como hace `P_ENTRADA` en Enfoque alfa.

**Decisiones de diseño (para no re-medir mecanismos ya resueltos):** NUEVOS rueda `[M-12,M-1]`
(curva y tasa) — mismo leak ~0.10pp ya medido en 18a/18f. STOCK **NO** rueda — ventana FIJA
202504-202606 igual que producción; rodar stock ya se probó en 18c/18g para Enfoque alfa y
**empeora** (corr. 0.848→0.820, stock es el componente de mayor varianza muestral) — se aplica
la misma decisión en vez de re-probar el mismo mecanismo. STOCK sí lleva el factor de cierre
real (modo "real", como v3) — refinamiento independiente de rodar la ventana. NUEVOS con día
de semana + factor de quincena, modo "estructural" (como W3).

| Mes | Proyectado | Real (dac) | error | err stock | err nuevos | corr. diaria | p_entrada | v1 sin refinar | vigente |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Enero | S/2,394,155 | S/2,290,411 | +4.5% | +3.1% | +4.9% | 0.862 | 25.26% | +0.5% | — |
| Febrero | S/2,133,336 | S/2,227,338 | -4.2% | -5.6% | -3.8% | 0.773 | 25.00% | -6.1% | — |
| Marzo | S/2,998,996 | S/3,061,707 | -2.0% | -4.2% | -1.8% | 0.933 | 25.08% | -4.0% | — |
| Abril | S/2,715,849 | S/2,614,085 | +3.9% | +14.4% | +1.2% | 0.831 | 25.28% | +1.4% | — |
| Mayo | S/3,067,507 | S/2,893,212 | +6.0% | -0.3% | +7.2% | 0.822 | 25.31% | +8.6% | — |
| Junio | S/2,939,249 | S/2,538,947 | +15.8% | +12.6% | +16.6% | 0.801 | 25.26% | +16.8% | +5.4% |
| Julio | S/3,882,039 | S/3,280,551 | +18.3% | -0.9% | +21.5% | 0.836 | 25.07% | +18.5% | +17.6% |

- **Correlación media de incrementos diarios: 0.560 → 0.837** — mismo salto de calidad que el
  refinamiento análogo logró en Enfoque alfa (0.611→0.886), mejora en los 7 meses.
- **Magnitud media de error de cierre: 7.99% → 7.83%** — casi no se mueve, y es a propósito
  (mismo principio de "qué métrica arbitra qué" de `CLAUDE.md`): el error de fin de mes no es
  el árbitro de un refinamiento de forma.
- **Tasa rodante estable: 25.00%-25.31%**, sin deriva — consistente con lo que 18b ya había
  encontrado para la tasa por soles (23.4%-27.2%).

**✅ 18e ADOPTADA 2026-08-26 (continuación 2), decisión explícita del usuario.**
`SEGUIMIENTO.md` reemplazó la fila vigente de Recupero Oficial por el motor v2
(`dias_atraso_cuota`, 7 meses enero-julio) — los números viejos (`dayslate`, junio +5.4%/julio
+17.6%) quedan como referencia histórica en el mismo archivo, no borrados. **`meta_agosto.py`
NO se tocó** — mismo criterio que Capital Asegurado (18g): no se cambia el motor de un mes EN
CURSO a mitad de mes; agosto sigue con `dayslate`/13.38% hasta que cierre. **Queda pendiente,
no bloqueante, para cuando agosto cierre (31-ago):** calibrar la meta de **septiembre** de
Recupero Oficial con este motor, ventana `[202508,202607]` (mismo patrón que la meta de
septiembre de Capital Asegurado, que tampoco se puede fijar todavía) — requiere un
`meta_septiembre.py` nuevo, análogo a `meta_agosto_capital_asegurado.py` pero con los insumos
de 18e (`backtest_tarea18e_recupero_oficial_v2.py` tiene toda la maquinaria de calibración
lista para reusar). Ver "LO QUE SIGUE" en `ESTADO.md`.

**18f — Efecto "día del mes" en la curva de nuevos (quincena y fin de mes) — ✅ MEDIDA Y
ADOPTADA 2026-08-26 como parte de W3. Abierta 2026-08-25 a partir de una pregunta del
usuario; no estaba anotada.** El resultado y los parámetros están arriba, en el bloque de
18a/18f; lo de abajo es el diagnóstico original que la abrió. El calendario ya está
indexado por día del mes (el volumen que entra cada día se mide, no se estima) y la curva de
stock también, así que ese eje está cubierto para esos dos componentes. Lo que queda ciego es
la **curva de nuevos**, indexada por `dias_desde_entrada`: una cohorte que entró el 12 y otra
que entró el 27 recorren la misma curva aunque solo la primera cruce la quincena temprano.

Medido sobre el residuo de V4 (o sea ya descontado el día de semana), como % del real del mes
y por día de la ventana:

| ventana | abril | mayo | junio | julio | media |
|---|---:|---:|---:|---:|---:|
| quincena (14-16) | -0.95% | -0.71% | -0.43% | -1.44% | **-0.88%/día** |
| fin de mes (últ. 3) | -0.75% | -0.39% | -0.18% | -0.57% | **-0.47%/día** |
| resto del mes | -0.44% | -0.36% | -0.10% | +0.09% | -0.20%/día |

Subproyecta la quincena en los **4 meses sin excepción**, a ~4x la tasa del resto (fin de mes,
~2x). El nivel negativo general es el sesgo de 18b — lo que importa es la diferencia **entre
ventanas**. No es el día de semana disfrazado: la ventana 14-16 cae en días distintos en cada
mes (abril M-X-J, mayo J-V-S, junio D-L-M, julio M-X-J) y el efecto aparece igual en los 4.

**Cómo modelarlo — y cómo NO.** No segmentar la curva por día del mes de entrada: la quincena
le pega a *todas* las cohortes vivas ese día, hayan entrado el 2 o el 14. Es un efecto del
**día en que llega la plata**, no del día de entrada de la cohorte; segmentarlo como cohorte
daría ~30 curvas, con las tardías truncadas por el fin de mes, y no resolvería el mecanismo.
La forma correcta es un **factor multiplicativo por día del mes aplicado al día de pago** —
una dimensión, no 30. **Advertencia de `CLAUDE.md`:** ese factor se calibra sobre la ventana
histórica como cualquier otra curva; ajustarlo contra el residuo del backtest de arriba lo
convierte en un ajuste ex-post y destruye lo que hace útil al modelo como meta fijada al
inicio del mes.

**Menores que siguen abiertos:** el residual de 150 créditos sin explicar de Fase 1 (<1% del
universo, patrón mixto) y el pendiente de bug 17 (por qué `jul_calendario.csv` tenía saldo
promedio 11% más alto por crédito) — ninguno bloquea nada.

### Tarea 19 — Ciclo de septiembre: cierre de agosto, tasa por soles adoptada, y la caída de activación — 2026-09-01

**HECHO Y CERRADO en esta sesión:**
- Agosto cerrado en los dos enfoques (tareas 4b y 8b).
- **`P_ENTRADA` del Enfoque alfa migrada a SOLES** (24.9081%, rodante `[202508,202607]`) —
  decisión del usuario, cierra lo que 18b diagnosticó. Verificado antes de correr nada: los dos
  motores comparten la definición de entrada, y la query de 18e reproduce el `P_ENTRADA` del
  alfa en créditos (21.9941% vs. 21.9918%) — **no hacía falta query nueva de tasa**.
- **Metas de septiembre fijadas:** alfa **S/20,477,271**, recupero **S/3,928,776**.
- **Protocolo de 12 meses reconfirmado**: 6m empeora las métricas diarias (0.886→0.876), 9m≈12m.

**EL FRENTE ABIERTO PRINCIPAL — la activación real está cayendo y no sabemos por qué.**
Medido: **-0.46pp/mes** (20.99% ene-mar → 18.50% jun-ago, r=-0.77) como % del calendario,
mientras la tasa de entrada por soles no tiene tendencia y el calendario creció **+90%** en 9
meses. **Está medido, no explicado.** Lo que hay que averiguar, en orden:
1. **¿Es capacidad de gestión?** El volumen asignado por gestor, la cobertura de la cartera y
   el ratio de contacto son medibles vía `dts_asignaciones_gestiones_cobranza` (existe desde
   julio 2026, así que solo cubre los 2 últimos puntos — limitación real).
2. **¿Es composición?** Si la cartera nueva entra con `avance_band` distinto, la caída podría
   ser mix y no eficiencia. Se mide sin Athena nueva, desde la matriz cruda.
3. **¿Es un artefacto del universo?** Descartado parcialmente: el mismo patrón aparece en los
   dos enfoques y con las dos tasas, así que no es de la definición de entrada.
   **Candidato (2026-09-13, bug 25) — MEDIDO, explica una parte:** el filtro `flg_last_loan_in_chain` mira
   hacia adelante y saca de cada mes a los que se refinanciaron después — 8-11% del saldo de nuevos
   en los meses viejos, solo 2-5% en los recientes porque sus refinanciamientos todavía no
   ocurrieron. Si esos créditos activan menos, los meses viejos quedan "limpiados" y los recientes
   no: una caída aparente. Se prueba midiendo su activación contra el resto (tarea 24).
   **→ Medido el mismo 13-sep:** incluir los reenganches explica ~1.5-2pp de los ~9pp de jun-jul, no
   toda la deriva (tarea 24, sensibilidades). Desde octubre la calibración los incluye (`motor_v2.REENG`).
   Ojo con el nombre: son reenganches (crédito adicional en la misma línea), no refinanciamientos.
**→ 2026-09-14, PREGUNTA 2 (composición) — MEDIDA: la mezcla no explica la caída, y con v2 la caída es
sobre todo de ENTRADA, no de conversión** (`tarea19_composicion_activacion.py`; addendum en
`analisis_tarea19_activacion_decreciente.md`). Por banda, día de semana y tercio del mes, la mezcla explica
≈0 de la caída de la conversión a 30 días (−1.08pp, ene-mar → may-jul); la de reenganches es etiqueta (bug
25). Activado/calendario cae 6.2% (ene-mar → jun-ago) = tasa de entrada −5.0% + conversión −1.3%. La
conversión a 30 días no tiene tendencia en 19 meses (−0.02pp/mes); ene-mar 2026 fue un pico de velocidad
(45.9% activa el mismo día de la entrada, contra 35-43% en 2025). Septiembre: la brecha al día 12 es de
arranque (0.649 contra 0.731), dentro del rango histórico (0.596-0.771); si el patrón se sostiene, se achica
después de la quincena — **verificarlo el 16-17 de septiembre**. La pregunta 1 (capacidad de gestión) pierde
fuerza: la conversión no cae. Lo abierto: qué pasó en ene-mar 2026 y por qué bajó la tasa de entrada en
jun-jul (cartera u originación, no cobranza).

**No ajustar nada mientras tanto** (`CLAUDE.md`) — la meta de septiembre lleva el caveat
explícito de que corre ~10% alta si la tendencia sigue.

**✅ ARTIFACT PUBLICADO 2026-09-02 — "De asignado a asegurado"**, en la URL **949ab3c2**
(reemplaza a la guía julio→agosto que vivía ahí; `resumen_julio_agosto.html` queda en el repo
como la versión anterior). Fuente: `asignado_a_asegurado.html` +
`armar_asignado_a_asegurado.py` + `tarea19_agosto_cadena_segmentada.sql` +
`datos_asignado_a_asegurado.json`.

Está escrito para que lo entienda alguien que no siguió el proyecto, y su eje es la **cadena
de capital asignado → capital asegurado** con los tres ratios nombrados y con su denominador
explícito (ratio de activación de antiguos 66.7%, tasa de entrada en mora 22.8%, ratio de
activación de nuevos 86.2%), todo abierto por tramo de atraso, banda de avance y día de semana
del vencimiento. Cubre agosto cerrado (−1.2% vs. la meta publicada, **+9.8% vs. el enfoque
actual**), septiembre proyectado (S/20,477,271) con la misma cadena, y la caída de activación.

~~**Siguen pendientes de republicar, sin escribir todavía:** **Capital asegurado** (d4140b13) y
**Proyectado vs. Real** (f80d3761) — los dos citan la meta de agosto ya superada.~~ **Republicados el
2026-09-02** (tabla de artifacts de `ESTADO.md`). Con la meta de octubre vuelven a quedar atrás: tarea 25,
paso 7.

**~~PENDIENTE MENSUAL~~ REEMPLAZADO POR LA TAREA 25 (motor v2, 2026-09-13).** Lo que sigue era el ciclo
con el motor v1 y ya no se usa: el de octubre en adelante está en la tarea 25. Texto original: fijar la meta de octubre es correr las 9
queries `tarea19_*.sql` con las ventanas movidas un mes, `generar_curvas_septiembre.py` con
`VENTANA_NUEVOS = ("202509","202608")`, y los dos `meta_septiembre_*.py`. Los archivos
`tarea18*` quedan congelados como el registro de lo que produjo la meta de agosto; los
`tarea19*` son la plantilla que se mueve.

**LO QUE SIGUE SIN RESOLVER de antes:** 18c (rodar la curva de stock — probado, empeora, necesita
su propio enfoque), el re-índice de nuevos por "días hasta fin de mes" (medido, no adoptado),
tarea 5 (2 artifacts desactualizados, decisión de producto), tarea 12 (carpetas).

Detalle completo en `analisis_tarea19_activacion_decreciente.md`.

### Tarea 12 (baja prioridad) — Reorganizar en carpetas
Considerar `sql/`, `python/`, `docs/` si el root sigue creciendo. No bloquea nada; con la
limpieza del 2026-07-15 el root ya bajó en 8 archivos + 2 carpetas de datos.

**2026-09-01 — subió de prioridad, aunque sigue sin bloquear.** El root pasó de ~40 a ~110
archivos entre las tareas 17/18/19, hay **~80 sin commitear**, y ya conviven 3 generaciones de
scripts (backtests por mes de la arquitectura con capa fantasma, `tarea18*` congelados,
`tarea19*` vigentes). El criterio de corte natural sería `sql/`, `python/`, `datos/` y un
`historico/` para lo que quedó como referencia, pero **hacerlo rompe todas las rutas relativas
hardcodeadas** en los scripts — no es un `git mv`, hay que tocar cada `DIR_*`. Conviene hacerlo
justo después de fijar una meta, no antes.

**2026-09-14:** la raíz ya tiene 196 archivos (109 `.sql`, 45 `.py`, 23 `.md`, 11 `.html`) y 28
carpetas `datos_*`. Ya no queda nada sin commitear y los CSV no se versionan, así que el costo real es
solo el de las rutas. El momento natural es justo después de fijar la meta de octubre (2-oct).

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

### Tarea 20 — La tasa de entrada se mueve por banda de avance y el modelo la aplica plana — 2026-09-02

**MEDIDO, NO ADOPTADO.** Salió al armar la sección «Qué mueve cada corte» del artifact 949ab3c2.
Fuente: `calendario_8m.csv` (denominador) + `curva_cruda_nuevos.csv` filas `tipo='base'` (numerador),
que son las dos caras de la MISMA matriz cruda con la que se calibra la curva — numerador y
denominador comparten definición, que es lo que pide el principio de modelado de `CLAUDE.md`.
Ventana **202601-202607** (la intersección real de las dos fuentes; ver la trampa abajo).

| Corte | Rango de la tasa de entrada | Índice | ¿El modelo lo usa para repartir entradas? |
|---|---|---|---|
| **Banda de avance** | 22.75% – 30.81% | **0.874 – 1.184 (±18%)** | **no** — tasa plana |
| Día de semana del venc. | 24.63% – 27.60% | 0.947 – 1.061 (±6%) | **no** — tasa plana |
| Cercanía al pago | 25.43% – 26.40% | 0.977 – 1.015 (±2%) | no, y no hace falta |

**Lo que esto dice:** el corte más grande de los tres es el que el modelo ignora. La banda de avance
sí segmenta la curva (techo 86.8%→96.4%), pero la tasa de entrada se aplica plana. En cambio la
cercanía al pago **no mueve quién cae en mora** (±2%) y sí mueve **cuándo paga el que ya cayó**
(factores ×1.087 quincena, ×1.225 fin de mes) — o sea que el factor de día del mes está del lado
correcto del modelo. El corte por día de semana es chico pero **estable**: miércoles por encima del
promedio los 7 meses, lunes por debajo los 7.

**NO SE TOCÓ NADA** — `CLAUDE.md`, principio de modelado: un cambio de constante se decide corriendo
el backtest, no en abstracto (precedente: bug 10). Si se quiere probar, es `p_entrada` por banda en
`motor_unificado.proyectar()`, que ya recibe el calendario segmentado por banda: el cambio es de una
línea, lo que cuesta es el walk-forward de 8 meses. **Ojo con el criterio de arbitraje:** cambiar la
tasa por banda es un cambio de NIVEL por segmento, no de forma, así que acá el error de cierre sí es
pertinente (mismo razonamiento que en tarea 19 con la tasa por soles).

**TRAMPA YA PISADA, no repetir:** `curva_cruda_nuevos.csv` cubre entradas hasta **202607**, mientras
`calendario_8m.csv` llega a **202608**. Cruzarlas sobre 202601-202608 resta las entradas de agosto sin
restar su calendario y hunde la tasa a 22.3% (contra 26.0% real). La ventana correcta es 202601-202607.

**DIFERENCIA DE CONVENCIÓN, pendiente de decidir si importa:** sobre la misma ventana, el par crudo da
**26.02%** y `tasa_soles.csv` (la fuente oficial de `P_ENTRADA`) da **24.85%**. La oficial deduplica a
un vencimiento por crédito-mes en el denominador y una entrada por crédito-mes en el numerador; la
matriz cruda cuenta cada evento. **La curva está calibrada sobre la convención cruda** y la tasa sobre
la deduplicada — que es exactamente el tipo de mezcla que el principio de modelado prohíbe. El efecto
medido es acotado (+1.16pp sobre la ventana, con dispersión mensual de +0.07 a +2.86pp) y **no se
tocó**; queda anotado acá para decidirlo con datos, no por argumento.

**→ 2026-09-13 (tarea 25, bug 28): buena parte de este corte era el denominador.** Con el calendario
ANCLADO como denominador (el saldo de la última foto del mes anterior, el que usa la meta), en [202509,
202608] la tasa por banda queda en 19.0% / 21.1% / 23.5% / 23.9% (bandas a-d), contra 29.4% / 19.9% /
22.2% / 22.4% con el saldo al vencimiento: el rango se achica y la banda "a" pasa de ser la más alta a
la más baja. En la foto del vencimiento, quien paga la cuota ese día ya bajó de saldo y saltó de banda
(sobre todo de "a" a "b"): el medido tiene 32.5% del saldo en la banda "a", contra 40.8% de los que
entran, y eso inflaba la tasa de esa banda. El calendario anclado queda a 3.3pp de la mezcla de bandas
de quien entra (el medido, a 8.3pp). Si se retoma esta tarea, medir el corte con la tasa anclada
(`curvas_v2.tasa_mensual(..., ancla=True)`), no con la vieja.

### Tarea 21 — Variante "primera entrada": el doble conteo antiguo/nuevo — 2026-09-02

**PEDIDO DEL USUARIO.** La gestión de cobranza congela el atributo antiguo/nuevo al inicio del mes.
Un crédito que arranca en mora (antiguo), paga, cura y vuelve a vencer dentro del mismo mes reentra
— y su capital podría contarse dos veces: una en el stock y otra en el calendario de nuevos.

**SON DOS SOLAPAMIENTOS DISTINTOS, y solo uno estaba vivo.**

| | Agosto 2026 (cerrado) | Septiembre 2026 (prospectivo) | ¿Estaba resuelto? |
|---|---|---|---|
| **A.** El crédito está en el stock **y** tiene vencimiento en el mes | 2,204 créd. · **S/3,311,800** | 2,205 créd. · **S/3,703,671** | **Sí**, `not in stock_agosto` |
| **B2.** 2.º vencimiento del **mismo** crédito en el mes | 2 créd. · S/1,913 | 2 créd. · S/6,546 | **No** — lo agrega esta variante |

(A) ya estaba excluido y **no es cosmético**: en septiembre el **92%** de los créditos del stock
tiene además un vencimiento en el mes. Coincide con el atributo congelado — el crédito es antiguo
todo el mes, y su reentrada ya vive dentro de la curva de stock, que se calibra sobre esa misma
población. Fuentes: `tarea21_diagnostico_doble_entrada.sql`, `tarea21_agosto_doble_entrada.sql`.

**LAS REENTRADAS SON FRECUENTES, y por eso (A) importa tanto.** En agosto, **1,035 de los 3,608
créditos del stock (28.7%) curan y vuelven a entrar en mora dentro del mismo mes** — S/1,659,914,
el 28.8% del capital del stock. Trayectorias día a día de 8 casos reales en
`datos_tarea21/casos_reentrada_trayectorias.txt` (`tarea21_casos_reentrada.sql`).

**LA VARIANTE, entregada y NO adoptada:** `meta_septiembre_primera_entrada.py` +
`tarea21_insumos_primera_entrada.sql`. Regla: cada crédito entra al universo del mes **una sola
vez, por su primera entrada en mora**. Resultado sobre una sola foto de datos:

    vigente (todo vencimiento)   S/20,412,734
    primera entrada              S/20,411,584   (-0.0056%)

**Para septiembre no mueve la meta, y ese es el resultado** — no un fracaso. La meta publicada
sigue siendo **S/20,477,271** (la diferencia contra los S/20.41M de arriba es re-expresión de
`dts_mambu_loans_hist` entre el 1-sep y el 2-sep, ~-0.3%, no el método).

**POR QUÉ IGUAL VALE TENERLA, dos razones independientes del tamaño:**
1. **Depende del mes.** El calendario se indexa por entrada (= vencimiento+1), así que su ventana
   va del último día del mes anterior al penúltimo del mes. Cuando el mes anterior es corto, atrapa
   dos vencimientos mensuales del mismo crédito: **202603 +12.7%** y **202607 +12.9%** contra el
   universo deduplicado, vs. **+0.0%** en 202609. Septiembre se salva por casualidad de calendario.
2. **Cierra media tarea 20.** `P_ENTRADA` (`tasa_soles.csv`) **sí** deduplica a un vencimiento por
   crédito-mes, pero hoy se aplica sobre un calendario que **no** deduplica. Con la variante, tasa y
   universo comparten definición — lo que exige el principio de modelado de `CLAUDE.md`.

**LO QUE LA VARIANTE NO ARREGLA (pendiente real):** la **curva** de nuevos sigue calibrada sobre
`curva_cruda_nuevos.csv`, que cuenta cada evento de entrada sin deduplicar por crédito-mes. Para
consistencia de punta a punta hay que recalibrarla sobre entradas deduplicadas — **una corrida más
de Athena**, editando `tarea19_curva_cruda_nuevos.sql` con un `row_number()` sobre
(crédito, mes de entrada) y `rn=1`. La curva es una forma, así que el efecto esperado es de segundo
orden, pero mientras no se mida **no se puede afirmar que sea chico**.

**→ 2026-09-14, medido el peso en la base:** con v2, la base de la matriz de nuevos (cada entrada) y el
numerador de la tasa (una cuota por crédito) coinciden a 0.00-0.04% por mes, salvo 202512 (+3.7%)
(`tarea19_composicion_activacion.py`, sección 5). El doble conteo es despreciable en el nivel; la forma de
la curva no se midió.


### Tarea 23 — Versión de proyección "lo que realmente entra a gestión" — pedido 2026-09-02, NO empezada

**PEDIDO TEXTUAL DEL USUARIO**, anotado para trabajarlo después:

> "Quiero proyectar cuánto entrará en gestión de cobranza. Para ello debemos excluir aquellos
> que entran en mora sábado y pagan ese mismo día y domingo, ya que esos días no tenemos
> asignación, y solo considerar el saldo al lunes, ya que eso se asignará."

**QUÉ ES:** una **tercera versión** de la proyección (no reemplaza la vigente ni la de tarea 21).
Hoy el modelo proyecta *capital asegurado sobre todo el que entra en mora*. Esta versión
proyectaría *capital que efectivamente llega a la mesa de gestión*, que es menos: el que entra
sábado y se resuelve solo antes del lunes **nunca se asigna**, así que no debería estar en el
universo de una meta de gestión.

**POR QUÉ ENCAJA CON LO YA MEDIDO** (no es una idea suelta):
- Ninguna cuota vence domingo, así que **nadie entra en mora un lunes** (bug 21). Las entradas
  de fin de semana son las de **vencimiento viernes → entra sábado** y **vencimiento sábado →
  entra domingo**.
- La curva de nuevos ya muestra que ese grupo es el más distinto de todos: el **día 0** de
  "vence sábado" es **19.1%** contra **42.0%** de "vence martes" (artifact 949ab3c2, sección de
  curvas). Ese 19.1% que activa el día 0 sin gestión es, casi por definición, la población que
  esta versión quiere excluir.
- Y la tasa de entrada por día de semana del vencimiento ya está medida: viernes 27.3% y
  sábado 27.1%, ambos **por encima** del promedio (tarea 20).

**CÓMO SE CONSTRUIRÍA** (borrador, a validar con el usuario antes de correr nada):
1. Definir el universo de gestión: capital en mora **al lunes** (o al primer día hábil), no al
   día de entrada. Para las cohortes de sábado y domingo, eso significa medir el saldo
   remanente después de los pagos de fin de semana, no el saldo de entrada.
2. Eso cambia **el universo, no la curva**: hay que recalibrar la tasa de entrada y la curva
   sobre esa misma definición (`CLAUDE.md`, principio de modelado) — no basta con descontar
   del resultado.
3. Cuidado con el corte: `in (6,7)` sobre el día de vencimiento es en la práctica **solo
   sábado**, y deja "vence viernes" (que entra **sábado**) del lado de los días hábiles
   (bug 21). El corte correcto es sobre el **día de ENTRADA**, no el de vencimiento.

**PREGUNTA ABIERTA para el usuario antes de construirlo:** ¿los feriados también son días sin
asignación? Si sí, el universo depende de un calendario de feriados que hoy el proyecto no tiene.

**ACTUALIZACIÓN 2026-09-13:** desde el **25-jul** `dts_asignaciones_gestiones_cobranza` SÍ tiene
filas los sábados (~8,300-9,400 créditos cada uno; los domingos nunca). Aclaración del usuario: **la
asignación de sábado es solo para canales complementarios — no se genera para call ni IVR.** La
premisa de esta tarea sigue valiendo para los canales principales, pero al construirla hay que
cortar por canal (`canal_asignado`): "el sábado no hay asignación" es cierto para call/IVR, no para
toda la tabla.


### Tarea 24 — Antiguo = "en mora el día 1" (la definición de la vista): reconciliación, decisiones y recalibración — 2026-09-13

**DECISIÓN DEL USUARIO (2026-09-13):** la definición correcta de antiguo es la de
`vw_seguimiento_diario_cohorte_tramo` — el crédito que entra en mora el día 1 es **antiguo**, no un
nuevo con `dia_entrada = 1`. *"Si esto implica recalibrar, hagámoslo."* Revierte a propósito lo que
hacía el motor unificado desde tarea 17 Fase 4. Decisión en `DECISIONES.md`.

**La regla es reproducible en toda la historia.** El negocio calcula `tipo_mora` con
`dias_mora >= day(fecha_base)`; en cualquier día de asignación eso equivale a "entró en mora el día 1
del mes o antes". Va anclada al **día 1 calendario**, no al primer día hábil:

    v2 (nueva):   dias_atraso_cuota entre 1 y 30 el DÍA 1 del mes; saldo al cierre del mes anterior
    v1 (vigente): dias_atraso_cuota entre 1 y 30 al CIERRE del mes anterior

Quién está en mora el día 1 se sabe al cierre del último día del mes anterior: la meta se sigue
pudiendo fijar el día 1.

**Reconciliación de septiembre con v2** (`tarea24_reconcilia_antiguos_sep_v2.sql`, vista con 11 días
de asignación cargados):

| | Créditos | Saldo | vs. vista |
|---|---:|---:|---:|
| Vista, TEMPRANA `antiguo` | 2,790 | S/4,904,773 | |
| v1 (cierre de agosto) | 2,384 | S/3,734,730 | −23.9% |
| **v2 (en mora el 1-sep)** | 2,837 | S/4,930,217 | **+0.5%** |

En ambos: 2,751 créditos, con el monto idéntico al céntimo en 2,749. (v1 daba S/3,763,294 el 2-sep:
re-expresión de Mambu y del calendario.)

**Qué mueve v1 → v2** (`tarea24_diagnostico_diferencias.sql`):
- **+965 (S/1,915,671)** entraron en mora el 1-sep; +12 (S/14,279) tenían >30 al cierre y 1-30 el 1-sep.
- **−478 (S/656,621)** estaban en mora al cierre pero **pagaron el 31-ago** (475 de 478): el 1-sep ya
  estaban al día y el negocio no los asignó. **Son los 487 "no aparecen aún" de tarea 22 — no era
  rezago.** 459 no aparecen en ninguna asignación del mes, 17 reentraron como `nuevo`, 2 fueron
  asignados `antiguo` igual. 475 tienen otro vencimiento en septiembre: con v2, si vuelven a caer,
  entran por el calendario de nuevos (hoy el motor los deja fijos en el stock todo el mes).
- **−46 (S/77,843)** pasaron de 30 a 31 días el 1-sep: el negocio los asignó a ESPECIALIZADA (45) y
  RECOVERY (1).

**Lo que queda, y qué se decidió** (`tarea24_diagnostico_vista.sql`, `tarea24_casos_b*.sql`):

| Diferencia | Créditos | Saldo | Decisión |
|---|---:|---:|---|
| Arrastre por DNI (solo nuestro) | 68 | S/85,999 | **Como la vista, con flag** |
| Punto ciego de `dias_atraso_cuota` (solo vista) | 25 | S/63,456 | Documentar; el usuario valida con IDs |
| Reenganches refinanciados después del corte (solo vista) | 13 | S/18,575 | **Incluidos** (decidido el 13-sep a la noche, abajo) |
| Sin asignación en sep (solo nuestro) | 18 | S/22,383 | Se quedan (pocos; decisión del 24-ago) |
| Sin foto Mambu al cierre (solo vista) | 1 | S/814 | — |

1. **Arrastre por DNI.** Los 68 tienen `max_dias_mora_dni > 30` (100%). Se tratan como la vista
   (fuera de TEMPRANA) **mediante un flag** `flg_arrastre_dni`, para poder separarlos en reporte y
   análisis. **Validado** (`tarea24_validacion_arrastre_dni.sql`): la mora máxima por DNI
   reconstruida desde `calendario_diario.dni` coincide con el `max_dias_mora_dni` del negocio en
   99.9% (jul 3,282/3,286; ago 2,484/2,485; sep 2,830/2,831), y en septiembre el flag separa la fase
   exacto: 67 de 68 ESP/REC marcados, 0 de 2,763 TEMPRANA. Contar todos los créditos del DNI o solo
   los últimos de su cadena da lo mismo. En julio y agosto hay además 328 y 263 ESP/REC con
   `max_dias_mora_dni <= 30` ("fase pegajosa", bug 14) que el flag no captura; en septiembre, 0.
2. **Punto ciego de `dias_atraso_cuota`** (bug 26). El negocio los tiene en mora el 1-sep y Mambu
   (`dayslate`) le da la razón en 24 de 25. Dos mecanismos (`tarea24_casos_b_transacciones.sql`):
   **17 (S/21,190) pagos regularizados** — registrados después del corte (casi todos el 3-sep, en
   lote) con fecha valor en agosto; la tabla de cuotas y `calendario_diario` se re-expresan con la
   fecha valor (hipótesis del usuario, confirmada en los 17). **8 (S/42,266) sin la cuota vencida en
   `dts_cobranza_creditos_cuotas`** y sin pagos entre el 20-jul y el corte; causa no verificada. Se
   documenta, no se cambia de fuente (1.3% contra el ~20% del punto ciego de `dayslate`). IDs en
   `datos_tarea24/casos_b.csv`.
3. **Sin asignación:** 15 pagaron el 1-sep y el negocio nunca los asignó (mecanismo de tarea 14);
   3 (S/2,719) siguen en mora sin asignación, sin explicar. Se quedan.

**REENGANCHES — MEDIDO, Y DECIDIDO EL 13-SEP A LA NOCHE: SE INCLUYEN** (`motor_v2.REENG = True`; ver
tarea 25 y `DECISIONES.md`). Lo que sigue es cómo se midió (el usuario pidió anotarlo y medirlo
para decidir después; `tarea24_reenganches_historico.sql`, bug 25). `flg_last_loan_in_chain` se lee
con la foto de HOY: un crédito vigente y en mora el día 1 que se refinanció después tiene hoy flag 0,
y la calibración lo borra de ese mes. Peso en saldo, sobre las poblaciones v2:

| | Meses completos 202504-202605 | 202606 | 202607 | 202608 |
|---|---|---:|---:|---:|
| Nuevos | 7.8% – 11.3% | 7.6% | 4.8% | 2.2% |
| Stock | 1.2% – 5.9% | 2.0% | 2.6% | 1.1% |

- Todos cierran en Mambu como `CLOSED/REFINANCED` (RESCHEDULED no aparece). Casi todo es
  refinanciamiento **después** del mes; **dentro** del mes es 0.7-1.6% en nuevos y 0.0-1.3% en stock
  — esos, si se incluyeran, bajan el saldo a 0 y contarían como pago.
- **El peso cae hacia el presente** porque los refinanciamientos futuros todavía no ocurrieron: la
  población de calibración está más "limpiada" en los meses viejos que en los recientes.
- **Hipótesis → medida (13-sep):** si quienes después tienen un reenganche activan distinto, excluirlos
  produce una caída aparente de la activación en los meses recientes — conecta con los −0.46pp/mes de
  tarea 19. Incluirlos explica ~1.5-2pp de los ~9pp de jun-jul, no toda la deriva (sensibilidades de la
  recalibración, abajo).
- **No bloqueó la recalibración:** las matrices nuevas llevan el flag de reenganche como dimensión
  (sin contar el cierre por reenganche como pago). Desde el 13-sep a la noche producción los incluye
  (`motor_v2.REENG = True`).

**~~ABIERTO~~ RESUELTO 2026-09-13 — la pregunta que se le hizo al usuario antes de recalibrar:** ¿los créditos con
arrastre por DNI quedan **fuera de la meta de TEMPRANA con su real reportado aparte**
(recomendado: son ~1.7% del stock y una curva propia saldría con muy poca muestra), o se quiere
también una **proyección propia** para esa línea? Defaults anunciados si no dice otra cosa: el flag
se aplica también a nuevos (medido el día de entrada); los dos enfoques; la meta de septiembre
publicada no se toca; octubre es la primera meta v2; backtest de 8 meses con las dos métricas.
**Respuesta:** fuera de la meta de TEMPRANA, como en la vista, y marcados con `flg_arrastre_dni` (ver
«Decisiones del usuario» en la tarea 25). No se armó una proyección propia para esa línea.

**Ojo de diseño para el stock v2:** la cohorte que entra el día 1 se comporta como nueva (activa
fuerte el día 0) y su peso dentro del tramo 1-8 varía por mes — cuando el último día del mes
anterior es domingo **no hay** cohorte del día 1 (ninguna cuota vence domingo). Probar un segmento
propio ("entra el día 1") dentro del stock y decidirlo con métricas diarias (`CLAUDE.md`).

**Plan de recalibración:**
1. Matrices crudas nuevas (stock, nuevos, calendario, tasa; activación y rebaje) con v2 y con
   `flg_arrastre_dni` y el flag de reenganche como dimensiones.
2. Curva de stock v2 (ventana fija 202504-202606). Nuevos sin la cohorte del día 1 y con los que
   pagaron el último día de vuelta al calendario. `P_ENTRADA` sobre la misma definición.
3. Los dos enfoques — comparten la definición de entrada.
4. Backtest de 8 meses v1 vs. v2, con error de cierre y correlación diaria.
5. Septiembre: la meta publicada no se toca; v2 en paralelo para comparar. Octubre: primera meta v2.
   *(Cambiado el 14-sep: el usuario re-fijó septiembre con v2.)*

**De paso:** (a) la asignación de sábado es solo para canales complementarios (ver tarea 23,
`tarea24_sabados_asignacion.sql`); (b) la vista cambió — incluye RECOVERY en 202609 y columnas
nuevas (`call`, `monto_cuota_a_pagar`, `ultima_actualizacion`, `fecha_pago`); el `.txt` del repo se
actualizó con `SHOW CREATE VIEW`; (c) referenciar la vista varias veces por query agota recursos de
Athena (bug 27); (d) el filtro de `status` no mira adelante (`tarea24_status_okaapi.sql`).

#### RECALIBRACIÓN v2 — EJECUTADA 2026-09-13 (tarde). La adopción la decide el usuario.

**La respuesta sobre el arrastre no llegó:** el mensaje de arranque de la sesión trajo el
placeholder sin completar. Se corrió con el default recomendado (**fuera de la meta, con flag**) y se
midió la alternativa: **no cambia nada material** (alfa 4.09% → 4.10% de error medio, correlación
idéntica). Con eso la pregunta queda como decisión de reporte, no de modelo.

**Queries.** Las cuatro llevan las dos definiciones en la misma foto de Mambu (`definicion`, o
`st_v1`/`st_v2`), más `d1` (entró en mora el día 1), `arrastre` y `reeng`:
- `tarea24_v2_matriz_stock.sql`: stock, activación y rebaje, `periodo_meta` 202501-202608.
- `tarea24_v2_matriz_nuevos.sql`: nuevos, activación y rebaje, entradas 20250101-20260831. Las de
  **agosto tienen el seguimiento truncado al 1-sep: no calibrar con ellas.**
- `tarea24_v2_calendario_tasa.sql`: calendario y tasa en **una sola población**, con el orden de
  la cuota en el grano (bug 23).
- `tarea24_v2_septiembre.sql`: insumos de septiembre v1 y v2, real v2 y entradas por día.
- `tarea24_diag_cierre_refin.sql`: el salto del cierre por refinanciamiento cae **exactamente** el
  día de `f_cierre` (27,106 de 27,124 caídas de ese día llegan a 0, S/30.7M; los días previos son
  pagos normales). Alcanza con ignorar las fotos desde `f_cierre`.
- Código: `curvas_v2.py` (lectura con filtros, no toca `curvas_crudas*.py`),
  `backtest_tarea24_v1_v2.py`, `meta_septiembre_v2.py`.

**Control.** Filtradas como v1, las matrices reproducen las de `datos_tarea19/` a ≤1.2%
(re-expresión). La tasa v1 da 24.9412% en [202508, 202607] contra 24.9081% de producción. El
backtest v1 reconstruido reproduce el publicado mes a mes: media 4.55% contra 4.54%, correlación de
nuevos 0.889 idéntica.

**La cohorte del día 1 pesa de 0% a 53% del stock v2 según el mes.** Sigue a las cuotas que vencen
el día 30: es grande en los meses que siguen a uno de 30 días o a febrero (marzo 52%, mayo 34%,
julio 47%, octubre 37%) y casi nula en el resto. Por eso el stock v2 va de 0.72x a 1.87x del v1
según el mes, y esa cohorte necesita tratamiento propio.

**Tasa v2 = 24.36%** en [202508, 202607] con el arrastre fuera (24.40% con el arrastre dentro),
contra 24.94% de v1.

**Backtest, 8 meses (202601-202608), las dos métricas** (`python backtest_tarea24_v1_v2.py sens`):

| Enfoque alfa | Error medio de cierre | Corr. total | Corr. stock | Corr. nuevos | MAE total |
|---|---:|---:|---:|---:|---:|
| v1 publicada | 4.55% | 0.826 | 0.842 | 0.889 | S/75.3K |
| v2 S0 — d1 dentro del tramo 1-8 | 3.99% | 0.808 | 0.896 | 0.897 | S/77.1K |
| v2 S1 — d1 como tramo propio | 4.04% | 0.815 | 0.900 | 0.897 | S/76.7K |
| **v2 S2 — d1 con la curva de nuevos** | 4.09% | **0.826** | **0.912** | 0.897 | **S/72.4K** |

| Recupero oficial | Error medio de cierre | Corr. total | Corr. stock | Corr. nuevos | MAE total |
|---|---:|---:|---:|---:|---:|
| v1 publicada | 8.26% | 0.826 | 0.811 | 0.881 | S/16.1K |
| v2 S0 | 8.33% | 0.810 | 0.857 | 0.887 | S/16.1K |
| v2 S1 | 8.15% | 0.810 | 0.862 | 0.887 | S/16.1K |
| **v2 S2** | 8.94% | 0.811 | **0.876** | 0.887 | **S/15.9K** |

- **Entre variantes v2 (el real es el mismo), S2 gana en las métricas diarias en los dos enfoques**,
  más claro en alfa. Se nota en los meses con cohorte d1 grande: marzo, correlación de stock 0.995
  (S2) contra 0.931/0.939; julio, 0.989 contra 0.961/0.953. La curva de nuevos por día de semana
  captura que el día 0 de esa cohorte depende del día en que cayó el vencimiento. S2 usa el saldo
  real de la cohorte, sin tasa: el día 1 ya se sabe quién entró. **Recomendación: S2 en los dos
  enfoques.**
- **v1 → v2:** en alfa baja el error de cierre (4.55% → 4.09%) con la misma correlación total y un
  MAE 4% menor; en recupero sube (8.26% → 8.94%) y la correlación total baja (0.826 → 0.811). Las
  correlaciones por componente no son comparables entre definiciones (la cohorte d1 cambia de
  lado): la comparable es la total. Criterio de `CLAUDE.md`: v2 corrige quién entra al universo
  (cuadra la vista al +0.5%), así que se adopta aunque el error de recupero suba. La adopción la
  decide el usuario.
- **Bug 23 queda resuelto por construcción en v2**: la cuota que entra el día 1 ya no es calendario
  (quien entró es stock, conocido), así que queda una cuota por crédito en la misma base que la
  tasa. De paso se midió la corrección que tarea 21 había dejado sin adoptar para v1 (`v1c1`, una
  cuota por crédito): **empeora el seguimiento diario** (marzo corr. total 0.912 → 0.736, julio
  0.886 → 0.680), porque quedarse con la primera cuota saca la del día 31, que sí genera entradas.
  No sirve como arreglo de v1.

**Sensibilidades, sobre v2 S2:**
- **Arrastre dentro:** igual (alfa 4.10%, corr. 0.826; recupero 8.93%).
- **Reenganches incluidos (bug 25):** alfa 4.09% → **3.74%**; jun/jul/ago pasan de +9.0/+8.4/+2.5%
  a +7.1/+6.9/+1.1%; correlación igual (0.828). Recupero 8.94% → 7.75%. La tasa baja a ~23.8%
  porque los reenganches entran en mora bastante menos (su tasa propia es 15-19% en soles, contra
  ~25%), lo que sugiere que son mayormente reenganches de buenos pagadores. **Inferencia, no
  verificada caso a caso.** Primera evidencia medida de que el filtro que mira adelante explica una
  parte de la deriva de tarea 19 (~1.5-2pp de los ~9pp de jun-jul), no toda. Se decide por
  universo (no mirar adelante), no por el error.

**Septiembre en paralelo** (`python meta_septiembre_v2.py S2 12`), la meta publicada no se toca:

| | Alfa | Recupero | Real/proy. al 12-sep (alfa) |
|---|---:|---:|---:|
| v1 publicada (1-sep) | S/20,477,271 | S/3,928,776 | 0.826 |
| v1 re-medida hoy | S/19,932,405 (−2.7%) | S/3,794,996 (−3.4%) | 0.852 |
| **v2 S2** | **S/19,283,694** (−3.3% contra v1 hoy) | **S/3,713,811** (−2.1%) | 0.871 |

La re-medición es el calendario prospectivo re-leído hoy: los créditos que terminaron de pagar en
septiembre ya figuran `COMPLETED` (S/87.1M contra S/89.6M), más la re-expresión de Mambu. El stock
v2 reproduce la reconciliación (2,837 / S/4,930,217); la cohorte d1 son S/1,920,753 que v2 conoce
el día 1 en vez de proyectarlos con la tasa. La definición explica una parte chica de la brecha de
septiembre: el resto es volumen y ejecución (ver `SEGUIMIENTO.md`).

**Septiembre v2 "como habría salido el 1-sep"** (pedido del usuario: cuánto hay que cerrar según la
proyección del día 1; `tarea24_v2_septiembre_al_1.sql` + `meta_septiembre_v2_dia1.py`). La tabla de
arriba usa insumos leídos HOY, que miran adelante: el calendario pierde a los que terminaron de
pagar después del 1-sep (S/2.8M, hoy `COMPLETED`) y el flag borra a los reenganches refinanciados
después. Reconstruido el universo del 1-sep (ACTIVE o COMPLETED con saldo al 31-ago; reenganches
refinanciados desde el 1-sep adentro), **v1 reproduce la publicada**: S/20,496,232 contra
S/20,477,271 (+0.09%; calendario +0.14%, ±0.6% día a día). Con v2:

| Septiembre, fijada el 1-sep | Alfa | Recupero | Real/proy. al 12-sep (alfa) |
|---|---:|---:|---:|
| v1 publicada | S/20,477,271 | S/3,928,776 | 0.826 |
| **v2, S2, arrastre fuera** | **S/19,814,433** (−3.2%) | **S/3,856,429** (−1.8%) | 0.849 |
| v2, arrastre dentro | S/19,845,582 | S/3,863,733 | 0.849 |
| v2, reenganches incluidos | S/19,468,590 | S/3,692,374 | 0.853 |

Trayectoria de la meta v2 en alfa: 15-sep S/9.84M, 20-sep S/13.07M, 25-sep S/16.32M, 30-sep
S/19.81M. Al 12-sep el real v2 lleva S/7,116,182 (35.9% del mes, contra 42.3% esperado): faltan
S/12.7M. El 0.871 de la tabla anterior sale de insumos re-medidos y **no** es el comparable.

#### VALIDACIÓN DEL FIX CON SEPTIEMBRE, al 12-sep (`tarea24_v2_dimensionamiento_sep.sql` + `backtest_septiembre_v2.py`)

Pedido del usuario: correr el backtest de septiembre sobre la lógica que dimensiona stock y nuevos, y
con eso validar el fix. **El fix de definición queda validado por los dos lados:**
- **Stock:** con v2 se observa el día 1 (no se estima), y cuadra con la vista crédito a crédito
  (+0.5%). La curva que proyecta cuánto activa va en **0.998** del real al 12-sep (corr. diaria
  0.993), con la cohorte del día 1 proyectada con la curva de nuevos (S2).
- **Nuevos:** nuestras entradas v2 del 2 al 12-sep son los nuevos que el negocio asigna a TEMPRANA:
  **3,973 créditos en ambos, con el monto idéntico al céntimo (S/6,251,983)**. 96.8% de nuestras
  entradas asignables están en la vista y 99.6% de la vista está en lo nuestro; 3,612 se asignan el
  mismo día de la entrada y 361 al día siguiente. Las diferencias están explicadas: 127 (S/240K)
  curaron en 48 horas sin llegar a asignarse — 107 de ellos entraron un DOMINGO y pagaron antes de
  la asignación del lunes, la población de la tarea 23 —, 8 son arrastre por DNI y 6 fueron a
  ESPECIALIZADA/RECOVERY. Del lado de la vista hay 17 (S/30K) que `dias_atraso_cuota` no ve (fecha
  valor, bug 26).

**La brecha de la meta NO viene del fix.** Backtest en tres capas al 12-sep, con la misma curva y la
misma tasa:

| Capital asegurado, real/proyectado al 12-sep | Nuevos | Total |
|---|---:|---:|
| a. Meta al 1-sep (calendario anclado al 31-ago) | 0.767 | 0.847 |
| b. Calendario medido al vencimiento | 0.844 | 0.901 |
| c. Entradas reales, curva sin tasa | 0.909 | 0.944 |
| Stock (igual en las tres capas) | | 0.998 |

- **a → b, el ancla (+5.4pp del total):** en los días 2-12 el calendario anclado al 31-ago tiene
  **10.5% más saldo** que el mismo calendario medido al vencimiento (S/31.3M contra S/28.3M). La tasa
  se calibra sobre el saldo al vencimiento, pero la meta la aplica sobre el saldo anclado: tasa y
  calendario con definiciones distintas. **Es el bug 28, con una corrección propuesta.**
- **b → c, la tasa (+4.3pp):** entró 6.3% menos de lo que esperaba la tasa calibrada (24.36%). La
  tasa realizada de los días 2-12 de septiembre es **22.90%**, en línea con jun-ago (22.9-23.5%) y
  por debajo de ene-may (24.2-26.3%): no es un mes raro, es el nivel reciente. Una parte puede ser el
  filtro de reenganches que mira adelante (bug 25), que saca más buenos pagadores de los meses viejos.
- **c, la conversión (0.909 en nuevos):** quien entra activa 9% menos que la curva hasta el día 12.
  Es la señal de ejecución, la caída de activación de la tarea 19.
- Recupero: 0.719 → 0.744 → 0.789. Ahí además el stock va en 0.763: activa como se esperaba (0.998 en
  alfa) pero rebaja menos, o sea pagos más chicos que los de la curva (lectura, no verificada
  crédito a crédito).

### Tarea 25 — Ciclo de octubre: la primera meta con el motor v2 — LISTA el 2026-09-13; lo que falta necesita datos de octubre

Motor v2 adoptado (tarea 24) con las dos decisiones del 13-sep a la noche: **reenganches incluidos**
(`motor_v2.REENG = True`) y **tasa anclada** (`motor_v2.TASA_ANCLADA = True`, bug 28 corregido).

0. ~~**Antes del 1-oct, resolver el bug 28.**~~ **HECHO 2026-09-13 (noche).** `tarea25_calendario_tasa.sql`
   → `datos_tarea25/v2_calendario_tasa.csv`, vigente en `curvas_v2.CT`: completa hasta
   `CALENDARIO_HASTA = "202608"`, más 202609 PARCIAL (entradas hasta el 12-sep) para validar
   septiembre; `curvas_v2.tasa` se niega a calibrar con un periodo posterior. Backtest de 8 meses
   (`backtest_tarea25_ancla.py`): la meta con la tasa vieja da +10.9% de sesgo; corregida, 3.83% / corr.
   0.827, el nivel del backtest de siempre (3.74% / 0.828). Detalle en `BUGS.md` bug 28. **Tasa anclada
   de la ventana de octubre [202509, 202608]: 20.52%** (medida: 23.38%).

**Septiembre, re-fijada con v2 el 14-sep** (decisión del usuario): meta S/17,504,932 / S/3,338,715
(`datos_tarea24/meta_v2_202609.csv`). Cada día: `bash scripts/run_athena.sh tarea25_real_v2_septiembre.sql >
datos_tarea25/real_v2_septiembre.csv` y `python seguimiento_v2.py 202609 datos_tarea24/v2_septiembre_al_1.csv
datos_tarea25/real_v2_septiembre.csv <último día completo>`; después `python armar_meta_septiembre.py <día>` y
republicar `meta_septiembre.html` (artifact 📍 Meta de septiembre, https://claude.ai/artifact/NsXqSFvWyeugGi9q95kvGU, desde el 15-sep). El 16-17 sep, mirar si la brecha de nuevos se
achica tras la quincena (tarea 19). Al cierre, la fila de septiembre en `SEGUIMIENTO.md` va contra la v2,
con la v1 al lado. Referencia contra la publicada v1: `bash scripts/run_athena.sh tarea19_real_septiembre.sql >
datos_tarea19/real_septiembre.csv` y `python seguimiento_septiembre.py <último día completo>` (el día va como
argumento; sin él corta en el 12). Al 14-sep, medido el 15: contra la v2, alfa 0.929 (−7.1%) y recupero 0.821; contra la v1, alfa 0.823
(−17.7%) y recupero 0.720 (−28.0%).

**Desde el 2-oct** (la foto del día en curso está incompleta, y el stock v2 se lee de la fila del 1-oct):
1. **Matriz de nuevos:** `bash scripts/run_athena.sh tarea25_matriz_nuevos.sql > datos_tarea25/v2_matriz_nuevos.csv`
   (ya escrita: fotos hasta el 1-oct, entradas hasta el 30-sep; las de septiembre quedan truncadas y no
   se calibra con ellas). Después, en `curvas_v2.py`: `MN = "datos_tarea25/v2_matriz_nuevos.csv"` y
   `FOTOS_NUEVOS_HASTA = "20261001"`. Sin esto, `motor_v2.curvas` se niega a calibrar [202509, 202608].
2. **Matriz de stock:** no hace falta (ventana fija 202504-202606).
3. **Calendario y tasa:** ya está: `datos_tarea25/v2_calendario_tasa.csv` llega a 202608, lo que pide la
   ventana de octubre. Para noviembre hay que extenderla un periodo (fechas corridas un mes y
   `CALENDARIO_HASTA = "202609"`).
4. **Insumos:** `bash scripts/run_athena.sh tarea25_insumos_octubre.sql > datos_tarea25/insumos_octubre.csv`
   (ya escrita; con REENG = True se usa todo el universo del 1-oct, reenganches incluidos).
5. **Meta:** `python meta_v2.py 202610 datos_tarea25/insumos_octubre.csv`, los dos enfoques; deja la serie
   diaria en `datos_tarea25/meta_v2_202610.csv`. Control ya pasado: `python meta_v2.py 202609
   datos_tarea24/v2_septiembre_al_1.csv` da S/17,504,932 y S/3,338,715 (septiembre con el motor adoptado).
6. ~~**Seguimiento de octubre:** falta la query y el script.~~ **HECHO 2026-09-13.** `tarea25_real_v2.sql`
   (real v2 por día de un mes en curso; validada con las fechas de septiembre: stock y nuevos de los días
   1-12 idénticos al céntimo a `datos_tarea24/v2_septiembre.csv`) + `seguimiento_v2.py` (avance,
   correlación y MAE diarios, y la brecha de nuevos partida en volumen y conversión; control: reproduce el
   0.927 de septiembre). Cada día: `bash scripts/run_athena.sh tarea25_real_v2.sql >
   datos_tarea25/real_v2_octubre.csv` y `python seguimiento_v2.py 202610 datos_tarea25/insumos_octubre.csv
   datos_tarea25/real_v2_octubre.csv <último día completo>`.
7. **Artifacts:** `armar_asignado_a_asegurado.py` está armado sobre los insumos v1 de tarea 19; rehacerlo
   sobre v2 antes de republicar 949ab3c2. **2026-09-14, corrección intermedia (versión 7), a pedido del
   usuario:** la meta de septiembre re-fijada (KPI + puente) y la última sección medida con v2. Se editó el
   HTML a mano (el armador solo inyecta los datos): al rehacerlo, conservar esas dos piezas. Siguen con v1 y
   se rehacen el 2-oct: las tablas y gráficos de septiembre, «Qué mueve cada corte» (tasa por banda con el
   saldo al vencimiento; con el anclado cambia, tarea 20) y los ratios de agosto. d4140b13 y f80d3761 todavía
   muestran la meta de septiembre v1. **El link compartido de 949ab3c2 muestra una versión anclada: la mueve
   el usuario.** **El usuario dará su feedback de la versión 7 en otra sesión** (aplicarlo sobre el HTML y
   republicar con `url=`).

**Salvedad de lectura para el seguimiento de octubre:** la tasa anclada es plana y el ancla pesa menos al
principio del mes (tasa anclada por tercio en la ventana de octubre: 21.2% / 21.5% / 19.1%), así que la
trayectoria de nuevos corre algo baja en el primer tercio y alta en el último. La tasa por tercio se
probó y no mejora las métricas diarias (no adoptada); `seguimiento_v2.py` muestra la tasa histórica de
los mismos días para poder leerlo.

**Decisiones del usuario (2026-09-13):**
1. **v2 ADOPTADO** desde la meta de octubre, con S2 en los dos enfoques (`motor_v2.py`, `meta_v2.py`;
   el ciclo está en la tarea 25). Septiembre quedaba con su meta publicada; **el 14-sep el usuario la
   re-fijó con v2** (S/17,504,932 / S/3,338,715).
2. **Arrastre por DNI FUERA** de TEMPRANA, como en la vista, porque se cobra en ESPECIALIZADA.
3. **Reenganches: INCLUIDOS** (decisión de la noche, `motor_v2.REENG = True`; `DECISIONES.md`). Lo que
   sigue es el registro de cómo se llegó. El usuario aclaró que un reenganche es un
   crédito ADICIONAL en la misma línea (como aumentar el monto desembolsado), no un refinanciamiento
   ni una reprogramación de cobranzas. Verificado con `tarea24_reenganches_que_son.sql` (30,237
   cierres `REFINANCED`/`RESCHEDULED` desde 2025-01):
   - 99.8% tienen flag 0 y `extendedbyloan_id`.
   - En 73.2% aparece un crédito nuevo del mismo DNI entre 3 días antes y 1 después del cierre, y en
     72.3% ese crédito arranca con más saldo que el que le quedaba al viejo.
   - El día anterior, 98.6% de los que tienen fila en el calendario estaban al día (1.1% en mora
     1-30, ninguno en 31+).
   - `RESCHEDULED` son 26 créditos, todos con flag 1: las reprogramaciones no pasan por este flag.

   **El "refinanciamiento" de esta tarea era el nombre técnico de Mambu (`REFINANCED`), no el del
   negocio.** Con eso la pregunta queda así: el flag saca de cada mes histórico a créditos que
   DESPUÉS recibieron un reenganche — buenos pagadores que el día 1 de ese mes eran créditos como
   cualquier otro, y que al fijar la meta no se sabe quiénes van a ser. Incluirlos (sin contar como
   pago el salto de saldo del día del reenganche) baja el error de alfa de 4.09% a 3.74%, y la meta v2
   de septiembre al 1-sep quedaría en S/19,468,590. **Recomendado; falta el visto bueno del
   usuario.** Si se incluyen: `motor_v2.REENG = True`. Detalle menor: 1.1% de los reenganches
   ocurre con el crédito en mora 1-30 (~310 créditos en 20 meses); v2 no cuenta ese cierre como
   pago, porque la deuda pasa al crédito nuevo.

4. **Bug 28 CORREGIDO** (noche): la tasa se calibra con el saldo anclado como denominador
   (`motor_v2.TASA_ANCLADA = True`; paso 0 de arriba y `DECISIONES.md`).

(El plan de octubre que estaba acá —re-correr las 4 queries de tarea 24 y un `meta_octubre_v2.py`—
quedó reemplazado por los pasos 0-7 de arriba: la meta sale de `meta_v2.py` y los insumos de
`tarea25_insumos_octubre.sql`, con el patrón "como el día 1" en vez de `status = 'ACTIVE'`.)

### Tarea 26 — ¿El riesgo de cobranza corta las curvas? — EVALUADA 2026-09-15, NO adoptada (pedido: solo evaluación)

Pedido del usuario: incluir el riesgo de cobranza en las curvas para ver si también corta el rebaje, *"no
modifiques técnicas, esto es solo una evaluación"*. **Respuesta: sí corta, y fuerte**, en nuevos y en antiguos,
dentro de cada banda de avance y tramo, todos los meses con el mismo signo (rebaje de nuevos a 30 días 28.9 / 20.8 /
16.8% para riesgo bajo / medio / alto; antiguos al cierre 22.8 / 12.7 / 9.6%). Para la meta pesó poco hasta ahora
(la mezcla movió la expectativa ±2-3% en recupero, décimas en capital asegurado), pero la entrada de riesgo alto en
nuevos subió de 22% a 31% del saldo en un año. Detalle en `analisis_tarea26_riesgo_cobranza.md`; artifact
[🌡️ Riesgo de cobranza en las curvas](https://claude.ai/artifact/B2jGBzDFD5nb5vxTaFBKKt).

Variable: `prediccion_riesgo_modelo_cobranza` (+ `segmento_modelo_cobranza`) de la cuota en mora, por
`id_loan_nro_cuota`. Evidencia de que no mira hacia adelante (sin verificar contra una foto histórica): se guarda
por cuota, existe también en cuotas pagadas a tiempo y aparece recién en las que vencen desde jun-2025.

**Si el usuario quisiera adoptarlo (no pedido):**
1. Walk-forward de 8 meses con métricas diarias, variante nuevos por banda × riesgo (CLAUDE.md: el cierre no
   arbitra segmentadores). La matriz de tarea 26 está al grano MES de entrada; para el walk-forward hay que
   re-correrla al grano `fecha_entrada` como las v2, y agregar el riesgo al calendario/tasa (la tasa de entrada
   también podría cortar por riesgo: no se midió).
2. Stock: la ventana fija 202504-202606 casi no tiene puntaje; habría que calibrar desde 202508, lo que cruza con
   la tarea 18c (rodar la curva de stock empeoró las métricas).
3. Alternativa a medir si el negocio piensa en la otra variable: `riesgo_mora_gestion` de la asignación (solo
   jul-ago 2026 completos).

**Para la tarea 19:** la deriva hacia más riesgo alto en nuevos es un dato nuevo para explicar la caída de la
velocidad de cobro; en capital asegurado su efecto por mezcla es de décimas, en recupero hasta ~2 puntos.

Archivos: `tarea26_riesgo_matriz_nuevos.sql`, `tarea26_riesgo_matriz_stock.sql`, `tarea26_riesgo_evaluacion.py`,
`riesgo_cobranza.html`, `datos_tarea26/` (CSV y JSON no versionados; logs con el QID).

**2026-09-15, a pregunta del usuario (*"hay dos, ¿recuerdas?"*):** la evaluación usó el puntaje crudo de
cobranza (igual al de mora en el 96% de las cuotas) para todos los créditos. La gestión usa **uno de dos modelos**
(mora o preventivo) y lo pasa por una **tabla fija** a `riesgo_mora_gestion` (tabla en el análisis). **Pendiente,
decide el usuario:** qué riesgo evaluar. Opciones: el crudo (hecho); el de gestión directo desde la asignación
(solo jul-ago 2026); o el de gestión reconstruido hacia atrás, que hoy no se puede, porque el par de la asignación
coincide con el de la cuota vigente solo en 41-77% y no se sabe con qué regla elige mora o preventivo.

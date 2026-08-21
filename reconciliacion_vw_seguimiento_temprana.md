# Reconciliación contra `vw_seguimiento_diario_cohorte_tramo` (TEMPRANA) — plan de cierre

> **Estado (2026-08-20): TEMPRANA CERRADA — los 5 pendientes resueltos.** Pasos 1/2/3
> (mecanismo, diseño, backtest de la capa fantasma) completados y adoptados en producción
> el mismo día — ver bug 14 en `BUGS.md`. La verificación a nivel crédito (pendiente 1)
> encontró un hueco de frontera de mes en la capa fantasma (90.7% de cobertura directa, no
> 100%) — el usuario confirmó adoptar el fix, y al implementarlo se encontró además que la
> tasa `P_FANTASMA` debía recalibrarse junto con el fix (misma definición de "periodo" en
> tasa y calendario, principio de `CLAUDE.md`): **8.4534% → 8.5524%**. Backtest final
> (consistente): junio +2.2%→+2.65%, julio +0.12%→+2.17% — ambos buenos números, el motivo
> del alza (dilución por solapamiento con otros eventos de mora) sigue aplicando. Aplicado
> a `enfoque_capital_asegurado.sql` Q3, `investigacion_capa_fantasma.sql` Q1,
> `backtest_capital_asegurado_junio.py` v4 y `meta_agosto_capital_asegurado.py` v3 (hueco
> del 31-jul: 77 créditos/S/140,194, confirmado con Athena). Meta de agosto sube a
> S/16,410,194. La extensión a agosto (pendiente 2) no repite el ~27% en el agregado
> parcial (mes a mitad de camino), pero sí por cohorte una vez descompuesto — hay que
> re-medir cuando agosto cierre. Los pendientes 3/4/5 quedaron documentados/decididos.

## Contexto y por qué existe este documento

El usuario compartió `vw_seguimiento_diario_cohorte_tramo.txt` (definición de vista SQL,
en la raíz del repo) — una vista "oficial" con el detalle a nivel crédito de la
asignación y el recupero, mantenida fuera de este proyecto. Pidió verificar si nuestro
`capital_asignado` (mora 1-30, Enfoque alfa) cuadra contra esa vista para la fase
`TEMPRANA`, y si no, identificar el motivo exacto — a nivel crédito, no solo a nivel
agregado.

**Verificado 2026-08-19** con esta query de referencia (la que dio el usuario):

```sql
select date_format(fecha,'%Y%m') as periodo, cast(sum(monto_asignado) as double) as capital_asignado
from vw_seguimiento_diario_cohorte_tramo
where fase_estrategia = 'TEMPRANA' and fecha = fecha_ancla
group by date_format(fecha,'%Y%m')
```

Resultado oficial: **julio 2026 = S/18,736,321 (11,718 créditos)**; agosto 2026 (parcial,
al corte de la corrida) = S/14,169,688 (8,941 créditos).

## La vista oficial, en corto (para quien no la haya leído)

`vw_seguimiento_diario_cohorte_tramo` construye, por crédito y mes, un `fecha_ancla` =
el PRIMER día que ese crédito aparece en `dts_asignaciones_gestiones_cobranza` ese mes.
En esa fecha ancla fija `fase_estrategia`, `tipo_mora`, `monto_asignado` (el
`monto_capital_pendiente` de la propia tabla de asignaciones — **no** el saldo de
Mambu) para todo el resto del mes; el saldo de Mambu (`saldo_capital`) sí se actualiza
día a día. Dedup de `dts_mambu_loans_hist` vía `row_number() over (partition by loan,
fecha order by fechaactualizaciontabla desc)` — **ojo:** esto es distinto del fix de
bug 11 de este proyecto (`lastmodifieddate desc, id desc`); `fechaactualizaciontabla`
es el campo que bug 11 ya había descartado como desempate útil (idéntico en 1,314/1,316
casos duplicados) — no se investigó si esto le genera a la vista oficial el mismo
problema de no-reproducibilidad que tuvimos nosotros, queda fuera de alcance de este
documento.

## Reconciliación a nivel crédito (julio 2026)

Query de cruce en `reconciliacion_temprana.sql` (ver "Archivos" abajo). Nuestra
población: stock (mora 1-30 cierre de junio, UNION entrantes día 1 de julio, bug 12) +
nuevos (entradas día 2-31), deduplicada a 1 fila por crédito (`group by id_loan, max(saldo)`
— evita el problema de doble conteo de reentradas dentro del mes, ver bug 13/nota de
sesión 2026-08-19 en `BUGS.md`).

| Categoría | Créditos | Nuestro saldo | Oficial `monto_asignado` |
|---|---:|---:|---:|
| En ambos | 8,269 | S/13,301,944 | S/13,321,309 (saldo Mambu: S/13,125,629) |
| Solo nuestro | 1,224 | S/2,074,931 | — |
| Solo oficial | 3,449 | — | S/5,415,012 |

**Los 8,269 créditos en común cuadran casi exacto (0.15% de diferencia)** — confirma que
el mecanismo de fondo (saldo Mambu, `dayslate` 1-30) está bien. El problema es de
**cobertura de población**, no de cálculo de saldo.

### A. Solo nuestro (1,224 créditos, S/2.07M) — YA EXPLICADO, no requiere acción

| Motivo | Créditos | Saldo |
|---|---:|---:|
| `grupo_control='CONTROL'` en `dts_asignaciones_gestiones_cobranza` | 998 | S/1,693,046 |
| Escalados a Especializada/Recovery por arrastre de DNI | 119 | S/228,015 |
| Aparecen en la tabla de asignaciones pero sin `grupo_control` ni fase Temprana clara | 186 | S/370,536 |
| No aparecen en `dts_asignaciones_gestiones_cobranza` ningún día de julio | 116 | S/172,387 |

**998 de 1,224 (82%) son el grupo de control** (deliberadamente no gestionado, para medir
efecto de la gestión — campo `grupo_control`, ya mencionado sin explorar en
`FUENTES_DATOS.md`). Confirmado por el usuario 2026-08-19: correcto que no aparezcan en
TEMPRANA operativo, no es un error. El resto (119 escalados + 186 + 116, ~17% de este
lado) es menor y queda documentado, no priorizado.

### B. Solo oficial (3,449 créditos, S/5.4M) — ESTO SÍ hay que resolver

| Motivo | Créditos | Monto asignado oficial |
|---|---:|---:|
| **`dayslate`=0 para nosotros, oficial sí marca mora 1-30 (bug 9, punto ciego)** | **3,210** | **S/5,018,712** |
| Excluidos por nuestro filtro `flg_last_loan_in_chain` (reenganches) | 313 | S/488,060 |
| Status no activo | 1 | S/2,705 |

**El punto ciego de `dayslate` (bug 9) es el 93% de esta diferencia — y es 27% de TODA
la población TEMPRANA oficial**, no el ~4% que sugería la muestra anterior (homologación
`tipo_mora`, 2026-08-18, bug 13). Es sistemático, no un caso de borde.

**Actualización 2026-08-21 — dataset filtrable por crédito, a pedido del usuario:** las
tablas A/B de arriba vienen de la sesión 2026-08-19 (perdida, no reproducible exactamente
— ver nota en "Archivos" abajo). Se generaron 2 CSV con **1 fila por crédito y una
columna `motivo`** usando la reconstrucción reproducible (Q7/Q8 de
`reconciliacion_temprana.sql`, misma lógica que la tabla del paso 1 arriba, categorías
mutuamente excluyentes) — los números salen en la misma escala pero no calzan 1 a 1
contra la sesión perdida (esperado, ver pendiente 4 abajo):

- **`datos_reconciliacion_temprana/solo_oficial_motivo_julio.csv`** (3,265 filas):
  `Punto ciego dayslate (bug 9)` 3,128 · `Reenganche (excluido por flg_last_loan_in_chain)`
  137 · (0 `Status no activo` / `Sin match en Mambu` en esta corrida, vs. 1 de la sesión
  perdida — diferencia irrelevante).
- **`datos_reconciliacion_temprana/solo_nuestro_motivo_julio.csv`** (1,246 filas):
  `Grupo de control` 779 · `Sin asignar` 367 · `Escalado a Especializada/Recovery
  (arrastre de DNI)` 94 · `Temprana en asignación, sin match en vista oficial` 6.

**Ojo con "Escalado a Especializada/Recovery" — corregido 2026-08-21 tras verificar con
datos:** la hipótesis inicial ("arrastre de DNI", otro crédito del mismo cliente ya
escalado) es **falsa** — se verificó cruzando los 94 créditos contra todos los `id_loan`
del mismo `dni`+`producto`: **94/94 (100%) son el ÚNICO crédito de su combinación, no hay
ningún hermano que arrastre.** Lo que sí se confirmó con datos: los 94 mantienen la
**misma `fase_estrategia` (Especializada o Recovery) fija los 31 días de julio**, sin
cambiar nunca, mientras que 60 de 94 (64%) tienen en algún momento del mes una mora
`dayslate` baja (≤5 días) — es decir, es una **fase "pegajosa"**: una vez escalado (por
historia previa a julio o un criterio acumulado de riesgo), `gestiones_cobranza` no lo
baja de fase aunque la mora del crédito, vista por `dayslate`, se vea fresca/baja ese
mes. El mecanismo exacto de por qué no baja no se investigó a fondo (bajo volumen, 94
créditos / S/199,604) — queda como hallazgo, no como pendiente bloqueante.

## Paso 1 — resultado (2026-08-20)

**Nota metodológica primero:** los archivos de la sesión del 2026-08-19 solo quedaron en
el scratchpad (nunca se copiaron al repo — ver sección "Archivos" abajo, ya actualizada).
Esta sesión reconstruyó la query de reconciliación desde cero siguiendo el patrón
documentado arriba. Al hacerlo, **se encontró un bug de no-determinismo propio (mismo
patrón que bug 11: `row_number() over (partition by id_loan order by periodo desc)`
con `periodo` constante dentro del CTE — sin desempate, Presto no garantiza orden
estable)**. Corregido con el mismo dedup de bug 11 (`lastmodifieddate desc, id desc`)
y ordenando `cierre_junio` por `dia` real, no por `periodo`. Con el fix, la
reconstrucción es determinista (verificado corriendo 2 veces, mismo resultado) y da
**3,135 créditos / S/4,924,248** en el bucket "dayslate=0 para nosotros" (vs. 3,210 /
S/5,018,712 de la sesión anterior — 2.3% de diferencia en créditos, esperable al
reconstruir sin el SQL original; **misma escala, mismo hallazgo**: 3,135/11,718 =
26.8% de la población oficial TEMPRANA, coincide con el ~27% ya reportado). Query
completa: `reconciliacion_temprana.sql`.

**Hallazgo principal: NO es un patrón nuevo — es 99.5% el mismo mecanismo de bug 9,
solo que a mucha mayor escala de la estimada.** Cruce contra `installmentlastpaiddate`
(`dts_cobranza_creditos_cuotas`) de los 3,135 créditos específicos:

| Sub-bucket | Créditos | % | Mecanismo |
|---|---:|---:|---|
| `fecha_de_vencimiento_cuota` (vista oficial) poblada, cuota pagada exactamente 1 día tarde | 546 | 17.4% | Bug 9 clásico — coincide con la cuota que la propia vista oficial ya señalaba |
| `fecha_de_vencimiento_cuota` **NULA** en la vista oficial (campo sin poblar en la asignación), pero al buscar directamente en `dts_cobranza_creditos_cuotas` la cuota vencida más reciente (`fechavencimiento<=fecha_ancla`): pagada 1 día tarde, **el pago cae el MISMO día que `fecha_ancla`** | 2,573 | 82.1% | Bug 9 — mismo mecanismo, solo que la vista oficial no traía el campo para cruzarlo directo |
| Casos aislados (gap≠1, sin cuota vencida, otros) | 16 | 0.5% | Sin patrón sistemático — outliers |

**Total: 3,119 de 3,135 (99.5%) es el punto ciego de 1 día de `dayslate` (bug 9),
no un fenómeno distinto.** Verificado además:
- **Sin arrastre por DNI:** en 2,581/2,588 casos del sub-bucket de la fecha nula,
  `max_dias_mora_dni` = `dias_mora` (no es un crédito "sano" arrastrado por la mora de
  otro crédito del mismo cliente — la mora es del crédito mismo).
- **Sin sesgo de producto:** BNPL y LD aparecen en ambos sub-buckets en proporciones
  similares al mix general de la cartera (BNPL 2,358 / LD 770 combinado) — no hay un
  producto o tipo de crédito específico concentrando el problema.
- El campo `fecha_de_vencimiento_cuota` de `dts_asignaciones_gestiones_cobranza` está
  **sin poblar en el 82% de estos casos** — es un gap de instrumentación de esa tabla
  (columna nueva, ya marcada "sin explotar" en `FUENTES_DATOS.md`), no evidencia de
  una causa distinta; al buscar la cuota directamente sin depender de ese campo,
  aparece el mismo patrón de bug 9.

**Implicación para el paso 2:** como es el mismo mecanismo ya conocido (no dos
problemas distintos), una corrección quirúrgica —detectar "pagó 1 día tarde" desde
`dias_vencimiento_a_pago`/`installmentlastpaiddate` a nivel cuota y sumarlo como
"entrada en mora de 1 día" sin tocar el resto del cálculo de `dayslate`— es más
acotada que lo que bug 10 advierte (ese caso era reemplazar tasa+curva completas por
una definición de cuota distinta; acá se trata de rellenar un hueco puntual, con
`dayslate` siguiendo como fuente para todo lo demás). Sigue aplicando el principio no
negociable: cualquier opción se valida con el backtest existente antes de adoptarla,
no en abstracto.

**Archivo de esta corrida:** `reconciliacion_temprana.sql` (nuevo, en el repo — a
diferencia de la sesión anterior, esta vez sí se copió).

## Paso 2/3 — resultado (2026-08-20): diseño + backtest en 2 meses cerrados

**Decisión con el usuario:** opción (a) completa — retrospectivo (curva) + prospectivo
(tasa), **solo Enfoque alfa** (capital asegurado; el recupero oficial, que también usa
`P(no paga a tiempo)=13.38%`, queda fuera de esta pasada — 13.38% NO se toca).

**Diseño ("capa fantasma"):** una capa INDEPENDIENTE de `dayslate`/13.38%/la curva
existente, sin mezclarlas (evita repetir bug 10):
- Detecta un crédito que paga una cuota exactamente 1 día tarde (`dias_vencimiento_a_
  pago=1`) sin que `dayslate` lo haya registrado nunca ese mes (mutuamente excluyente de
  la detección real vía `dayslate`, para no duplicar).
- Se activa **100% del saldo, el día siguiente al vencimiento** — no necesita curva de
  maduración propia: por definición, si se detecta el evento es porque ya se pagó.
- Nueva tasa **`P_FANTASMA` = 8.4534%** (29,845/353,054, mismo criterio y ventana fuera de
  muestra que 13.38% — ago-2025 a may-2026, sin junio). Por mes: 7.35%-9.53%, **casi tan
  grande como el propio 13.38%** — no es un ajuste marginal.

**Backtest — junio 2026 (mes calibración/backtest oficial):**

| | Proyectado | Real | Error |
|---|---:|---:|---:|
| Stock (sin cambios) | S/2,611,863 | S/2,436,287 | +7.2% |
| Nuevos (sin cambios) | S/6,206,338 | S/6,789,236 | -8.6% |
| **Fantasma (nuevo)** | S/5,106,866 | S/4,598,430 | +11.1% |
| **Total** | **S/13,925,067** | **S/13,823,953** | **+0.7%** (antes: **-4.4%**) |

**Backtest — julio 2026 (segundo mes cerrado, validación independiente):**

| | Proyectado | Real | Error |
|---|---:|---:|---:|
| Stock+Nuevos (sin cambios) | S/10,306,231 | S/10,770,918 (recalculado esta sesión) | -4.31% |
| **Fantasma (nuevo)** | S/6,226,704 | S/5,742,741 | +8.43% |
| **Total** | **S/16,532,935** | **S/16,513,659** | **+0.12%** |

**El error total baja de forma consistente en los 2 meses cerrados disponibles**
(|-4.4%|→|+0.7%| en junio, |-4.31%|→|+0.12%| en julio) — no es un mes con suerte. La
capa fantasma tiene su propio error (+11.1%/+8.43%, sobreestima) pero va en dirección
OPUESTA al error base (que subestimaba), y el neto mejora en ambos casos.

**Hallazgo colateral — `SEGUIMIENTO.md` tiene el signo de julio (capital asegurado)
invertido:** al recalcular el real de julio de forma independiente (S/3,137,199 stock +
S/7,633,719 nuevos = S/10,770,918, muy cerca del S/10,789,362 ya documentado), el error
correcto es **-4.31%/-1.01%/-5.67%** (subestima, MISMO signo que junio), no
"+4.7%/+1.0%/+6.3%" como dice la tabla hoy — la nota de "signo invertido, sin sesgo
direccional estable" está basada en un error de signo, no en un hallazgo real. **No se
corrigió `SEGUIMIENTO.md` todavía** — queda para que el usuario lo confirme antes de
tocar un registro de mes ya cerrado.

**Archivos de esta corrida:** `investigacion_capa_fantasma.sql` (tasa `P_FANTASMA` +
validación julio). El backtest quedó fusionado directamente en
`backtest_capital_asegurado_junio.py` (producción, v3) +
`datos_backtest_junio/bt_real_fantasma_nuevos_junio.csv` — ya no existe un script
paralelo separado.

**2026-08-20 (mismo día) — adoptado en producción, a pedido explícito del usuario:**
- `enfoque_capital_asegurado.sql` Q3 (tasa `P_FANTASMA`) y `enfoque_capital_asegurado_
  backtest.sql` BT-ASEG-3 (real fantasma junio) — nuevas queries de producción.
- `backtest_capital_asegurado_junio.py` v3 — capa fantasma fusionada (ya no hay script
  paralelo).
- Meta de agosto recalculada — ver `ESTADO.md`/`SEGUIMIENTO.md` para los números vigentes.
- Signo de julio corregido en `SEGUIMIENTO.md` (ver detalle de este documento arriba).

## Pendientes para cerrar TEMPRANA por completo (2026-08-20, revisado con el usuario)

**Bug 11 (filas duplicadas, ver `BUGS.md`) queda descartado como causa de esta
diferencia** — verificado: de los 3,130 créditos "fantasma", solo 1 tiene alguna fila
duplicada en julio y ninguno tiene `dayslate` conflictivo. No bloquea nada de lo de abajo,
pero sigue como pendiente aparte (Tareas 3/6 de `PENDIENTES.md`).

Lo que sí falta para decir que la reconciliación TEMPRANA está cerrada:

1. **~~Verificar la capa fantasma a nivel crédito, no solo agregado.~~ Hecho 2026-08-20 —
   NO es 1:1 directo, pero se explica 99.7% al considerar un hueco nuevo encontrado.**
   Cruce credito-por-crédito (con el dedup de bug 11 ya aplicado): de los **3,130** créditos
   del bucket "solo oficial, `dayslate`=0" (bug9), la capa fantasma tal como está
   implementada en producción (`enfoque_capital_asegurado.sql` Q3) cubre directamente
   **2,839 (90.7%, S/4,479,727 de S/4,915,990)** — no el 100% esperado. Al investigar los
   **291 no cubiertos**, **281 de ellos (96.6% del gap, S/421,046)** resultan ser un patrón
   sistemático nuevo: la cuota que dispara el evento **venció el 30 de junio** (último día
   del mes ANTERIOR), pagada 1 día tarde (1-jul) — el mismo mecanismo de bug 9, pero la capa
   fantasma filtra `fechavencimiento >= '2026-07-01'` (ventana calendario del mes), así que
   una cuota vencida el último día del mes anterior queda fuera de la ventana de julio (y
   tampoco la agarra la ventana de junio, porque el evento — pago 1 día tarde — cae el 1 de
   julio, fuera del rango `20260601`-`20260630` de ese mes). **Es un hueco de frontera de
   mes en la capa fantasma, análogo al bug 12 (antiguos/nuevos) pero para esta capa nueva
   — no estaba cubierto por el diseño original.** Sumando ambos (2,839+281=3,120/3,130 =
   **99.7%**), el mecanismo de bug 9 sigue explicando casi todo — consistente con el 99.5%
   ya reportado en el paso 1 — pero el 9.3% restante (291 créditos) es una brecha real de
   *implementación* de la capa fantasma, no del diagnóstico. Los 10 créditos restantes
   (0.3%) son outliers sin patrón, igual que el 0.5% ya documentado en el paso 1.

   **Continuación 2026-08-20 (mismo día) — CERRADO, fix adoptado en producción con la tasa
   recalibrada.** Se cambió el filtro de la capa fantasma de `fechavencimiento` directo a
   `fecha_pago` (`fechavencimiento+1`) cayendo dentro del mes objetivo — simétrico, sin
   doble conteo. Primera pasada del backtest (con la tasa `P_FANTASMA` vieja, 8.4534%, sin
   recalibrar): junio sin cambio (+2.2%), julio empeora de +0.12% a +1.68%. Investigado el
   motivo: de los 7,468 créditos nuevos que entran al cálculo (cuotas vencidas 30-jun), 600
   (8.03%) pagan 1 día tarde — tasa casi igual al promedio histórico (8.45%) — pero 150 de
   esos 600 (25%) ya estaban contados por otro evento de mora real en julio y se excluyen
   para no duplicar, dejando un neto de 450/7,468=6.03%, por debajo del promedio. Es
   dilución por solapamiento, no un error de cálculo.

   **Hallazgo al implementar: esa primera pasada mezclaba una tasa calibrada SIN el fix
   con un calendario YA corregido — inconsistencia del tipo que bug 10/`CLAUDE.md`
   prohíben.** Se recalibró `P_FANTASMA` con el mismo fix aplicado a su propio cálculo:
   **8.4534% → 8.5524%** (346,396 elegibles / 29,625 entradas, verificado con Athena).
   Backtest final, consistente: **junio +2.2%→+2.65%, julio +0.12%→+2.17%** — ambos siguen
   siendo buenos números. El usuario confirmó adoptar el fix (con la explicación del motivo
   de julio) y luego confirmó también adoptar la tasa recalibrada al encontrarse la
   inconsistencia. **Aplicado a `enfoque_capital_asegurado.sql` Q3, `investigacion_capa_
   fantasma.sql` Q1, `backtest_capital_asegurado_junio.py` v4 y `meta_agosto_capital_
   asegurado.py` v3** — este último con el hueco del 31-jul confirmado con Athena (77
   créditos / S/140,194 en riesgo, no ~101 cuotas como se estimaba antes de medirlo; real
   observado a la fecha: 4 créditos / S/3,556.95). Meta de agosto sube de S/16,351,397 a
   **S/16,410,194**. Detalle completo en bug 14 de `BUGS.md`.
2. **~~Extender la reconciliación de población a agosto~~ Hecho 2026-08-20 — no repite
   igual en el agregado, pero sí por cohorte; el motivo es que agosto está a mitad de
   mes.** Al corte de hoy (20-ago, vista con datos hasta esa fecha: 9,274 créditos /
   S/14,621,415), el bucket `dayslate_cero_bug9` da **1,772 créditos (19.1% de oficial,
   S/2,453,492)** — más chico que el 26.8% de julio, no una repetición directa. Al
   descomponer por cohorte (créditos que ya estaban en la vista oficial en julio, análogo a
   "stock", vs. créditos nuevos en la vista en agosto, análogo a "nuevos"): **"nuevos"
   tiene 30.0% de tasa bug9 (1,374/4,581) — mayor que el 26.8% agregado de julio —
   mientras "stock" tiene solo 8.5% (398/4,693).** Como agosto está solo al día 20 de 31,
   "nuevos" (que crece día a día, tasa bug9 alta) todavía no terminó de acumularse,
   mientras "stock" (tamaño fijo desde el cierre de julio, tasa bug9 baja) ya pesa su
   proporción completa — esto diluye el agregado hacia abajo en un corte parcial. **El
   mecanismo no se debilitó — si algo, el sub-grupo "nuevos" salió más alto que julio** —
   pero la comparación agregado-vs-agregado solo es limpia mes-cerrado-vs-mes-cerrado.
   **Pendiente real:** re-medir cuando agosto cierre (día 31) para una comparación
   apples-to-apples con julio.
3. **~~Decidir si excluir reenganches (313 créditos) de esta comparación puntual~~ Decidido
   con el usuario 2026-08-20: dejarlo documentado, no tocar el filtro.** La vista oficial
   no filtra `flg_last_loan_in_chain` y nosotros sí (regla del proyecto desde bug 3, evita
   sesgar curvas con cuotas `LATE` colgadas de créditos refinanciados que nunca se marcan
   `PAID`). Es una diferencia de alcance deliberada — el gap de 313 créditos / S/488,060 en
   julio **queda documentado como brecha permanente, no se va a cerrar**. Alternativa
   descartada: quitar el filtro de `flg_last_loan_in_chain` para igualar la población a la
   vista oficial — reabriría el problema que el bug 3 resolvió y exigiría recalibrar
   curvas + re-correr el backtest, sin beneficio claro.
4. **~~Revisar la inconsistencia numérica menor en "solo nuestro"~~ Hecho 2026-08-20 — no
   reproducible exactamente, pero el total queda validado de forma independiente.** La
   query exacta de la sesión 2026-08-19 que produjo 998/119/186/116=1,419 (vs. 1,224
   reportado) no está en el repo (mismo problema de no-determinismo/no-reproducibilidad ya
   señalado para esa sesión — ver "Archivos" abajo). Se reconstruyó desde cero (dedup de
   bug 11 aplicado, categorías mutuamente excluyentes por construcción: control primero,
   luego escalado, luego "aparece en Temprana pero no está en la vista oficial", luego
   "no aparece en la tabla de asignaciones"): **783 control + 362 no aparece en
   asignaciones + 95 escalado + 6 aparece en Temprana sin match = 1,246 créditos** — **muy
   cerca del 1,224 original (diferencia de 22, 1.8%)**, aunque las categorías individuales
   NO calzan 1 a 1 contra las originales (783 vs. 998 en "control", 362 vs. 116 en "no
   aparece", etc. — la lógica exacta de clasificación de la sesión perdida no es la misma
   que esta reconstrucción). **Conclusión:** el total original (1,224) queda razonablemente
   validado por una reconstrucción independiente; la inconsistencia de 195 en el desglose
   de motivos de esa sesión es casi seguro un problema de categorías no mutuamente
   excluyentes en esa query puntual (un crédito contado en más de un motivo), no evidencia
   de que el total esté mal. No vale la pena seguir persiguiendo el desglose exacto de una
   query que no existe — la reconstrucción de arriba es la referencia a usar de acá en
   adelante si se necesita el detalle.
5. **~~Auditar el propio dedup de la vista oficial~~ Hecho 2026-08-20 — sí, muy probable
   que tenga el mismo problema, y sin ningún desempate de respaldo.** Confirmado leyendo
   la definición de la vista (`vw_seguimiento_diario_cohorte_tramo.txt` línea 81):
   `ROW_NUMBER() OVER (PARTITION BY id_loan, fecha ORDER BY fechaactualizaciontabla DESC)`
   **sin ningún criterio de desempate adicional** (ni `id`, ni ningún otro campo). Bug 11
   (`BUGS.md`) ya documentó que `fechaactualizaciontabla` es **idéntico entre filas
   duplicadas en 1,314 de 1,316 casos** (vienen del mismo batch de carga ETL) — es decir,
   para prácticamente TODOS los grupos conflictivos, el `ORDER BY` de la vista oficial no
   tiene ningún efecto real, y Presto no garantiza un orden estable ante un empate total.
   Esto es potencialmente **peor** que lo que tenía este proyecto antes del fix (que al
   menos usaba `lastmodifieddate desc, id desc`, con `id` como desempate 100% determinista
   al final). No se puede verificar el impacto real sin acceso de escritura/re-ejecución de
   la vista (es de otro proyecto, fuera de nuestro control) — queda documentado como
   hallazgo para comunicar al equipo que mantiene la vista, no como algo que este proyecto
   pueda corregir.
6. Aplicar la misma capa fantasma al Enfoque acumulado (recupero oficial) si en el futuro
   se decide ampliar el alcance más allá de Enfoque alfa (fuera de esta pasada, ver
   "Alcance tasa 13.38%" — se optó por no tocar `fase1_stock.sql`/`fase2_nuevos.sql`/
   `fase3_backtest.sql`).

## Archivos de esta investigación

- **`reconciliacion_temprana.sql`** (2026-08-20, en el repo): reconstrucción
  determinista de la reconciliación de julio (con el fix de no-determinismo del
  paso 1) + el cruce contra `installmentlastpaiddate`. Reemplaza la corrida
  2026-08-19 (esa quedó solo en scratchpad, nunca se copió al repo, y su SQL exacto
  ya no es recuperable — esta versión es la que hay que usar de acá en adelante).
- Query de cruce a nivel crédito: CTEs `nuestro` (stock+nuevos deduplicado, con el
  dedup de bug 11 aplicado en `fotos`) vs. `oficial` (`vw_seguimiento_diario_cohorte_
  tramo` filtrado a TEMPRANA + `fecha=fecha_ancla`), `left join` por `id_ihfintech_loan`
  para aislar "solo oficial".
- Cruce mecanismo (paso 1): `clasificado` (solo oficial, status activo, sin excluir por
  chain) contra `dts_cobranza_creditos_cuotas` — primero por `fecha_de_vencimiento_cuota`
  exacta (vista oficial), luego, para los que no tienen ese campo poblado, por la cuota
  vencida más reciente (`fechavencimiento<=fecha_ancla`, `installmentstate='PAID'`).
- **Diagnósticos de la sesión 2026-08-19 (solo nuestro / solo oficial por status/chain)
  no se re-verificaron esta sesión** — se asume que siguen vigentes (la reconstrucción
  determinista dio números en la misma escala), pero si se necesita el detalle exacto,
  recrearlos con el patrón de `reconciliacion_temprana.sql`.
- **`reconciliacion_temprana.sql` Q5-Q7`** (2026-08-20, continuación, en el repo):
  verificación de la capa fantasma a nivel crédito (pendiente 1 — resultado: 90.7%
  directo, 99.7% incluyendo el hueco de frontera de mes) y reconstrucción de "solo
  nuestro" categorizado contra `dts_asignaciones_gestiones_cobranza` (pendiente 4).
- **`reconciliacion_agosto.sql`** (2026-08-20, nuevo, en el repo): extensión de la
  reconciliación de población a agosto (pendiente 2) — agregado parcial (Q1) y
  descomposición por cohorte estaba-desde-julio vs. nuevo-en-agosto (Q2), que explica
  por qué el ~27% no se ve igual todavía en un mes a medio cerrar.
- **`reconciliacion_temprana.sql` Q7/Q8** (2026-08-21, nuevo): mismas CTEs de Q1/Q6, sin
  el `group by` final — exportan 1 fila por crédito con columna `motivo` (etiquetas
  legibles) a `datos_reconciliacion_temprana/solo_oficial_motivo_julio.csv` y
  `solo_nuestro_motivo_julio.csv`, para poder filtrar por motivo en Excel/BI en vez de
  solo ver el agregado.

## Referencias

- `vw_seguimiento_diario_cohorte_tramo.txt` — definición de la vista (raíz del repo).
- `BUGS.md` bug 9 (punto ciego de `dayslate`, ahora cuantificado en ~27%), bug 10 (tasa/
  curva consistentes), bug 13 (homologación `tipo_mora` vs. antiguo/nuevo).
- `FUENTES_DATOS.md` — `dts_asignaciones_gestiones_cobranza`, campo `grupo_control`.
- `IDEAS.md` / `PENDIENTES.md` tarea 7 — `installmentlastpaiddate`, sin explotar.

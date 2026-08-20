# Reconciliación contra `vw_seguimiento_diario_cohorte_tramo` (TEMPRANA) — plan de cierre

> **Estado (2026-08-20): paso 1 del plan completado — mecanismo identificado.**
> El punto ciego de `dayslate` (bug 9) explica **99.5%** de los 3,135 créditos de
> esta muestra (julio 2026), no un patrón nuevo. Ver sección "Paso 1 — resultado"
> más abajo y bug 14 en `BUGS.md`. **Sigue pendiente el paso 2** (decidir
> corrección, con el usuario) y el paso 3 (backtest antes de adoptar nada) — no
> se aplicó ningún cambio al modelo todavía.

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

1. **Verificar la capa fantasma a nivel crédito, no solo agregado.** El backtest
   monetario mejoró (+0.7%/+0.1%), pero nunca se volvió a correr la reconciliación
   crédito-por-crédito para confirmar que el bucket "solo oficial, `dayslate`=0" (3,210/
   3,135 créditos) efectivamente se explica 1:1 por la capa fantasma. Esperable que sí
   (99.5% ya matcheaba el mecanismo), pero no verificado explícitamente.
2. **Extender la reconciliación de población a agosto** (la vista ya tiene datos: 8,941
   créditos / S/14,169,688) para confirmar que el ~27% de punto ciego original se repite
   y no fue un artefacto puntual de julio.
3. **Decidir si excluir reenganches (313 créditos) de esta comparación puntual** — la
   vista oficial no filtra `flg_last_loan_in_chain` y nosotros sí. Es una diferencia de
   alcance deliberada, no un bug — este gap **no se va a cerrar** a menos que se decida
   cambiar el filtro, así que es más una decisión de producto que una tarea técnica.
4. **Revisar una inconsistencia numérica menor en el desglose "solo nuestro" original**
   (sesión 2026-08-19): la tabla de motivos suma 998+119+186+116=1,419, pero el total
   reportado de "solo nuestro" es 1,224 (diferencia de 195, nunca explicada). Bajo
   impacto (~S/300K estimado), pero vale la pena revisar antes de cerrar el documento.
5. **Auditar el propio dedup de la vista oficial** (`fechaactualizaciontabla desc`, sin
   `id` como desempate final) — nunca se verificó si le genera a `vw_seguimiento_diario_
   cohorte_tramo` el mismo problema de no-reproducibilidad que bug 11 encontró en
   `dts_mambu_loans_hist`. Menor prioridad, fuera de nuestro control (es de otro proyecto).
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

## Referencias

- `vw_seguimiento_diario_cohorte_tramo.txt` — definición de la vista (raíz del repo).
- `BUGS.md` bug 9 (punto ciego de `dayslate`, ahora cuantificado en ~27%), bug 10 (tasa/
  curva consistentes), bug 13 (homologación `tipo_mora` vs. antiguo/nuevo).
- `FUENTES_DATOS.md` — `dts_asignaciones_gestiones_cobranza`, campo `grupo_control`.
- `IDEAS.md` / `PENDIENTES.md` tarea 7 — `installmentlastpaiddate`, sin explotar.

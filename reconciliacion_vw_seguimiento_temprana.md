# Reconciliación contra `vw_seguimiento_diario_cohorte_tramo` (TEMPRANA) — plan de cierre

> **Estado: hallazgo cuantificado, sin resolver.** Este documento es el punto de
> retomo para la próxima sesión que trabaje esto — no repetir el diagnóstico desde
> cero, ya está hecho. Ver bug 14 en `BUGS.md` para el resumen corto.

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

## Plan de trabajo — próxima sesión

**No repetir el diagnóstico — ya está hecho arriba. Empezar directamente en el paso 1.**

1. **Investigar el mecanismo exacto de los 3,210 créditos.** Usar
   `installmentlastpaiddate` (`dts_cobranza_creditos_cuotas`, IDEAS.md punto 4 /
   PENDIENTES.md tarea 7, nunca explotado) cruzado específicamente contra estos IDs (no
   una muestra genérica): ¿cuánto tiempo pasa entre vencimiento de cuota y pago real?
   ¿Es 100% el punto ciego de 1 día (bug 9), o hay un patrón adicional (producto BNPL
   vs. LD, cuota 1 vs. posteriores, algún tipo de crédito específico)?
2. **Decidir la corrección — NO elegir de antemano, evaluar con datos:**
   - (a) Sustituir/complementar `dayslate` por una señal a nivel cuota para detectar
     "entrada en mora". **Riesgo ya documentado (bug 10):** la tasa `P(no paga a
     tiempo)=13.38%` está calibrada sobre `dayslate` — no es intercambiable con una
     tasa a nivel cuota sin recalibrar (mezclar sobreestimó 66-81% en el pasado).
   - (b) Usar `dts_asignaciones_gestiones_cobranza`/`tipo_mora` como población base de
     "mora 1-30" (ya sabemos que captura estos 3,210 créditos). Requiere validar si la
     curva de maduración actual (`curva_stock_seg.csv` / `curva_asegurado_stock_seg.csv`)
     sigue aplicando a esta población ampliada, o si hay que recalibrarla.
   - (c) Dejarlo documentado como limitación conocida, si el costo de recalibrar supera
     el beneficio (a valorar junto con el usuario).
3. **Backtest obligatorio antes de adoptar cualquier cambio** (principio de modelado no
   negociable, `CLAUDE.md`/`DECISIONES.md`): correr la opción elegida contra un mes
   cerrado (junio y/o julio) y comparar el error contra el modelo actual (capital
   asegurado +4.7%, recupero oficial +17.6% en julio) antes de reemplazar nada.
4. **Menor prioridad:** decidir si excluir reenganches (313 créditos) de esta
   comparación puntual, o dejarlo documentado como diferencia de alcance deliberada (nunca
   fue lo mismo — la vista oficial no filtra `flg_last_loan_in_chain`).
5. **Extender la reconciliación a agosto** (la vista ya tiene datos: 8,941 créditos /
   S/14,169,688 para 202608) para confirmar que el ~27% de punto ciego se repite y no es
   un artefacto puntual de julio.

## Archivos de esta investigación (2026-08-19, en scratchpad de la sesión — no copiados
al repo todavía; si se retoma, recrearlos con este mismo patrón)

- Query de cruce a nivel crédito: CTEs `nuestro` (stock+nuevos deduplicado) vs. `oficial`
  (`vw_seguimiento_diario_cohorte_tramo` filtrado a TEMPRANA + `fecha=fecha_ancla`),
  `full outer join` por `id_ihfintech_loan`.
- Diagnóstico "solo nuestro": cruce contra `dts_asignaciones_gestiones_cobranza` por
  `dni`+`producto` para revisar `grupo_control`.
- Diagnóstico "solo oficial": cruce contra el último snapshot de julio en
  `dts_mambu_loans_hist` para clasificar por `mora=0` / `mora>30` / `status` /
  `flg_last_loan_in_chain`.

## Referencias

- `vw_seguimiento_diario_cohorte_tramo.txt` — definición de la vista (raíz del repo).
- `BUGS.md` bug 9 (punto ciego de `dayslate`, ahora cuantificado en ~27%), bug 10 (tasa/
  curva consistentes), bug 13 (homologación `tipo_mora` vs. antiguo/nuevo).
- `FUENTES_DATOS.md` — `dts_asignaciones_gestiones_cobranza`, campo `grupo_control`.
- `IDEAS.md` / `PENDIENTES.md` tarea 7 — `installmentlastpaiddate`, sin explotar.

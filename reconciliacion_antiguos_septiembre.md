# Por qué nuestros "antiguos" de septiembre (S/3.76M) son menores que TEMPRANA de la vista oficial (S/4.90M)

**2026-09-02.** Pregunta del usuario. Aplica el *principio de universo* de `CLAUDE.md`: la
diferencia se explica con datos, no se asume. Fuentes:
`tarea22_reconcilia_antiguos_septiembre.sql`, `tarea22_hipotesis_fecha_corte.sql`,
`tarea22_solo_nuestro.sql`; resultados en `datos_tarea22/`.

## La respuesta en una línea

**No falta capital: la línea antiguo/nuevo está trazada un día antes.** Nosotros cortamos al
**cierre del mes anterior (31-ago)**; el negocio corta a la **fecha de la primera asignación
(1-sep)**. Los créditos que entraron en mora *el 1 de septiembre* son **antiguos** para la vista y
**nuevos del día 1** para nosotros. Ese capital **sí está en la proyección**, en el componente de
nuevos — no en el de antiguos.

## El cuadre, crédito a crédito

| | Créditos | Saldo |
|---|---|---|
| Vista, 202609 TEMPRANA `antiguo` | 2,789 | **S/4,901,917** |
| Nuestro stock del 1-sep | 2,399 | **S/3,763,294** |
| **En ambos** | 1,807 | S/2,952,721 |
| **Solo la vista** | 982 | S/1,949,196 |
| **Solo nuestro** | 592 | S/810,573 |

Cuadra al céntimo por los dos lados: `2,952,721 + 1,949,196 = 4,901,917` y
`2,952,721 + 810,573 = 3,763,294`.

### Solo la vista (S/1,949,196) — el 99.0% es la cohorte del día 1

| Motivo | Créditos | Saldo |
|---|---|---|
| **Mora 0 el 31-ago y ≥1 el 1-sep** — venció la cuota el 31-ago | **965** | **S/1,929,629** |
| `dias_atraso_cuota` > 30 para nosotros | 12 | S/14,005 |
| Punto ciego real (mora 0 el 31-ago, 1-sep y 2-sep) | 2 | S/4,872 |
| Sin fila en `calendario_diario` | 3 | S/689 |
| Excluido por `flg_last_loan_in_chain` (reenganche) | 1 | S/1,158 |
| Sin foto Mambu al cierre con saldo > 0 | 1 | S/814 |

Los 965 tienen `dias_mora_inicio = 1.0` **exacto** y `fecha_ancla = 2026-09-01` **para todos**.
Es la firma inconfundible de una cuota vencida el 31-ago que entra en mora el 1-sep.

**Importante — esto NO es el punto ciego de `dayslate` (bug 9/14).** Ese punto ciego, que en julio
era el 27% de TEMPRANA, quedó cerrado con la migración a `dias_atraso_cuota` (tarea 17 Fase 4):
acá sobreviven **2 créditos, S/4,872**. La hipótesis del punto ciego se probó y se descartó.

### Solo nuestro (S/810,573)

| Dónde están | Créditos | Saldo | Mora prom. nuestra |
|---|---|---|---|
| No aparecen aún en la vista para 202609 | 487 | S/658,854 | 6.0 días |
| Escalados a **ESPECIALIZADA** (`antiguo`) | 103 | S/150,086 | 23.2 días |
| La vista los marca `nuevo` en TEMPRANA | 2 | S/1,632 | 30.0 días |

Los 103 escalados son la misma categoría que bug 14 ya había identificado en julio (arrastre de
mora por DNI). Los 487 que no aparecen **quedan por confirmar**: al 2-sep la vista solo tiene dos
días de asignación de septiembre, así que puede ser rezago y no ausencia. **Revisar con el mes más
avanzado antes de sacar conclusiones.**

## Por qué las dos definiciones son distintas, y ninguna está mal

- **La vista** congela `tipo_mora` en `fecha_ancla` = primer día que el crédito aparece en
  `dts_asignaciones_gestiones_cobranza` ese mes. Para septiembre eso es el **1-sep**. Quien ya
  estaba en mora ese día — incluido el que entró *ese mismo día* — es `antiguo`.
- **Nuestro motor** define stock como `dias_atraso_cuota` 1-30 **al cierre del mes anterior**, y
  manda la cohorte que entra el día 1 al **calendario de nuevos con `dia_entrada = 1`**. Es una
  decisión explícita del motor unificado (`motor_unificado.py`, punto 4 del docstring): al cierre
  de agosto esos créditos tienen atraso 0, así que **no son stock**. Eso revirtió a propósito el
  parche `dia1_entrantes` de bug 12, y elimina por construcción el hueco de frontera de bug 14/17.

Las dos son internamente consistentes. Lo que **no** se puede hacer es comparar el "antiguo" de una
contra el "antiguo" de la otra sin corregir por ese día.

## La comparación que sí es válida

Para contrastar contra la vista hay que sumar nuestros dos componentes en el día 1:

    nuestro stock del 1-sep                     S/3,763,294
  + nuestra cohorte de nuevos con dia_entrada=1 (proyectada)

El calendario del día 1 son S/9,410,503 de capital que vence el 31-ago; a la tasa de entrada
vigente (24.9081%) proyectamos **S/2,343,975** entrando el 1-sep. La vista observó
**S/1,929,629** entrando ese día como `antiguo`.

**No sacar conclusión de ese −18% todavía:** es un solo día, la vista tiene dos días de septiembre
cargados, y los 487 créditos sin aparecer sugieren que la asignación puede seguir completándose.
Es un dato de seguimiento, no un error medido.

## Qué NO hay que hacer

**No mover nuestro corte al 1-sep para "cuadrar" con la vista.** Eso cambiaría quién entra al
universo y obligaría a recalibrar la curva de stock, la curva de nuevos y la tasa de entrada sobre
la definición nueva — no es un ajuste de una constante (`CLAUDE.md`, principio de modelado, y el
caso real de bug 10). Si alguna vez se hace, se decide con el backtest corrido, no en abstracto.

Lo que **sí** corresponde es lo de este documento: dejar la diferencia **nombrada y cuantificada**,
para que nadie la lea como capital faltante.

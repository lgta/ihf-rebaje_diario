# Enfoque B: reinicio del reloj

> **Estado: deprioritizado, no oficial.** Sirvió como cruce de validación independiente
> del `enfoque_acumulado.md`, pero el usuario confirmó (2026-07-10) que la meta que le
> interesa siempre es la del mes completo, anclada al cierre. No invertir tiempo acá
> salvo pedido explícito. Se documenta igual, completo, para que quede trazable.

## El concepto

En vez de anclar el stock al cierre del mes anterior, trata la foto de **HOY** como nueva
línea base y proyecta los días restantes del mes — "si reasignara todo hoy". Responde una
pregunta distinta a la del enfoque acumulado: no "cuánto falta del mes completo" sino
"si empezara de cero desde hoy, cuánto proyecto".

## Resultado (corte 9-jul-2026)

Stock re-baseline a hoy: **S/4,192,565** (2,380 créditos — mayor que el stock de inicio
de mes porque ya absorbió a los "nuevos" de la primera semana; verificado en vivo,
diferencia de S/2 con una cita anterior por redondeo de segmentos, no un error real).

**Resultado inicial (sin corregir): S/1,261,169** (stock S/462,014 + nuevos S/799,155) —
parecía cruzar bien contra el enfoque acumulado (S/1,248,799, solo +1.0%).

## El bug: aged-out survivors

`meta_desde_hoy.sql` filtraba el stock con `mora between 1 and 30` usando la mora de
**HOY**, no la de asignación — excluía silenciosamente a los créditos del stock original
de julio que ya habían cruzado 30 días de mora entre el 1 y el 9 de julio. Violaba la
regla ya confirmada de que un crédito asignado sigue contando aunque cruce 30 días
(ver `DECISIONES.md`).

Diagnóstico cuantificado sobre el stock de 1-jul (1,756 créditos, S/2,943,958):
- 716 curaron (S/1,062,860) — correctamente excluidos.
- 796 siguen 1-30 hoy (S/1,379,790) — correctamente incluidos.
- **244 cruzaron a más de 30 días (S/501,307) — excluidos por el bug.**

No se puede corregir simplemente quitando el límite superior del filtro — eso arrastraría
S/9.57M de cartera con mora 90+ días que nunca fue parte de la asignación de julio. La
corrección debe ser quirúrgica: JOIN contra la foto de asignación (30-jun) para identificar
solo a los 244 créditos que sí eran parte del stock original.

**Fix aplicado (bloque Q0):** reincorpora a los 244 créditos usando su clasificación y
saldo ORIGINALES (tramo 16-30 en todos los casos — solo créditos ya cerca de 30 días
pueden cruzar en 9 días), con la lógica acumulada `curva_día31 − curva_día9` aplicada a su
saldo de asignación. Aporte: **S/22,510** (chico, porque mora profunda implica baja
frecuencia de pago).

**Fix secundario (Q2):** la exclusión del calendario de "nuevos" pasó a usar TODO el stock
de asignación, no solo el que sigue 1-30 hoy — corrige un doble conteo menor (3 créditos,
S/6,843, que se contaban como aged-out Y como "en riesgo" en el calendario).

## Resultado final corregido

S/22,510 (aged-out) + S/462,014 (stock re-baseline) + S/782,322 (nuevos, calendario
corregido) = **S/1,266,846** — **+1.4%** sobre el enfoque acumulado oficial (más
consistente que el +2.8% estimado antes del fix completo a Q2).

## La variante "precisa" — hallazgo de selección adversa (no guardada como script)

Un intento posterior de descomponer el stock de hoy en sus dos sub-poblaciones reales
(antiguos que siguen en su ciclo original vs. nuevos-ya-asignados que entraron a mitad de
mes) y aplicarles curvas PRECISAS (no la simplificación "hoy = día 1 fresco para todos")
dio **S/1,160,888** (**-7.0%** vs. el enfoque acumulado) — se aleja más, no menos.

**Interpretación:** no es un error, es "selección adversa" — los créditos que siguen en
mora hoy son un mix peor que el promedio histórico (los "fáciles" de curar ya salieron del
pool). Esto revela que "brecha al objetivo original" (lo que mide el acumulado) y
"pronóstico fresco dado el estado actual" (lo que mide esta variante precisa) son
preguntas legítimamente distintas — no convergen al mismo número aunque ambas sean
correctas para lo que miden.

**Este script quedó ad-hoc en el scratchpad de la sesión que lo generó y nunca se guardó
formalmente en el repo como `meta_desde_hoy_preciso.py`** (se ofreció guardarlo, el
usuario no confirmó). Si se retoma este enfoque, reconstruir desde esta descripción o
pedir el detalle en una sesión nueva.

## SQL explicado

Todo vive en `meta_desde_hoy.sql`, 3 queries (Q0, Q1, Q2):

**Q0 — aged-out survivors.** Dos fotos: `fotos_asignacion` (cierre de junio,
`fechaproceso='20260630'`) y `fotos_hoy` (corte, `fechaproceso='20260709'`). Se arma
`stock_asignacion` filtrando `mora between 1 and 30` en la foto de asignación — el stock
"real" de julio. Luego se hace `JOIN` de ese stock contra `fotos_hoy` y se filtra
`f.mora_hoy > 30` — son los créditos que YA CRUZARON 30 días desde la asignación. Se
clasifican por su `tramo`/`avance` de la foto de ASIGNACIÓN (no la de hoy), porque son la
cola del enfoque acumulado, no créditos "frescos".

**Q1 — stock re-baseline.** Una sola foto (`fechaproceso='20260709'`), filtrada a
`mora between 1 and 30` — el stock "tal como se ve hoy", tramo/avance recalculados con la
mora de HOY (por diseño; por eso los aged-out de Q0 quedan fuera de acá, ya cruzaron 30).

**Q2 — calendario desde mañana.** Igual que el calendario del enfoque acumulado
(`dts_cobranza_creditos_cuotas` con `status='ACTIVE'`, `installmentstate='PENDING'`), pero
con `fechavencimiento >= mañana` (no desde el 1 del mes) y excluyendo — vía
`excluir_ids` — a TODO crédito que ya sea stock, tanto el de asignación (cubre a los
aged-out de Q0) como el de hoy (Q1), para no contar el mismo saldo dos veces. Esta unión
de dos fuentes de exclusión fue precisamente el segundo bug (ver arriba): la versión
original solo excluía por `stock_hoy_ids`, dejando pasar 3 créditos que ya estaban
cubiertos por Q0.

**Combinación (`meta_desde_hoy.py`):** `Q1 × curva_stock(tramo,avance,días_restantes) +
Q0 × [curva_stock(tramo_original,avance,día31) − curva_stock(...,día9)] + Q2 × 13.38% ×
curva_nuevos(avance,días_para_madurar)`.

## Archivos

- `meta_desde_hoy.py` + `meta_desde_hoy.sql` (ya con el fix Q0/Q2 aplicado) +
  `datos_meta_desde_hoy/` (incluye `aged_out_hoy.csv`, `calendario_hoy_adelante.csv`).
- La variante "precisa" (selección adversa) NO tiene archivo en el repo — ver nota arriba.

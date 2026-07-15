# Glosario

Definiciones cortas. Si un término tiene matices, acá va la versión de una línea — el
detalle completo está en `guia_tecnica_recupero.md` o `DECISIONES.md`.

**Antiguos / stock** — créditos con mora 1-30 días al cierre del mes anterior. Se les mide
capital una sola vez (ese cierre) y se les da seguimiento con la curva de stock. **Excepción
(solo Enfoque alfa, `BUGS.md` bug 12):** también incluye a los que muestran `dayslate=1`
justo el día 1 del mes — su cuota venció el último día del mes anterior, son antiguos
aunque `dayslate` recién lo refleje al día siguiente. El recupero oficial (`fase1_stock.sql`)
no tiene este ajuste todavía.

**Nuevos / flujo** — créditos que NO estaban en mora al cierre del mes anterior pero
tienen una cuota que vence durante el mes. Cada día de vencimiento genera su propia
cohorte. **En Enfoque alfa**, el día 1 del mes queda excluido de "nuevos" por la excepción
de arriba.

**Tramo** — banda de mora del stock al momento de asignación: 1-8 / 9-15 / 16-30 días.
Fijo todo el mes aunque el crédito cruce 30 días después (ver `DECISIONES.md`). Predice
FRECUENCIA de pago, no severidad.

**Avance de amortización** — `1 - saldo_capital_vigente / monto_financiado`. Bandas: <10%,
10-40%, 40-70%, 70%+. Es el segmentador de SEVERIDAD (cuánto rebaja cuando paga), para
stock y nuevos por igual.

**Entrada en mora** — el momento en que un crédito "nuevo" pasa de estar al día a estar
moroso. Ojo: tiene DOS definiciones distintas en este proyecto, y no son intercambiables:
- *A nivel crédito* (la que usa el modelo oficial): transición `dayslate` 0→1 en la foto
  diaria de `dts_mambu_loans_hist`. Tiene un punto ciego de ~1 día (ver `dayslate` abajo).
- *A nivel cuota*: `dias_vencimiento_a_pago >= 1` en `dts_cobranza_creditos_cuotas` — no
  paga hasta la fecha de vencimiento (inclusive). Captura TODO atraso, incluido el que se
  resuelve al día siguiente.

**`dayslate`** — campo de `dts_mambu_loans_hist`, días de mora del crédito en esa foto.
`NULL` cuando está al día (usar siempre `coalesce(dayslate,0)`). Tiene un punto ciego: una
cuota pagada 1 día tarde casi nunca hace que `dayslate` llegue a mostrar 1 (solo 4.3% de
los casos medidos) — probablemente porque la foto diaria captura el estado después de que
el pago ya se aplicó. Ver bug 9 en `BUGS.md`.

**P(no paga a tiempo)** — probabilidad de que un crédito "elegible" (con cuota venciendo,
no ya en stock) entre en mora ese mes. Valor oficial: **13.38%**, medido a nivel crédito
(`dayslate` 0→1), fuera de muestra. NO confundir con el complemento de "% paga a tiempo" a
nivel cuota (~25-28%) — ver `DECISIONES.md`.

**Curva de recupero acumulado** — % del saldo capital inicial (o de entrada) que se espera
recuperado, acumulado día a día. Hay una para stock (por tramo × avance × día del mes) y
otra para nuevos (por avance × días desde la entrada en mora).

**Cohorte** — el grupo de créditos que vence (o entra en mora) el mismo día. El motor de
nuevos suma una cohorte por cada día de vencimiento del calendario del mes.

**Saldo en riesgo** — saldo capital de los créditos con cuota venciendo un día dado, ANTES
de aplicar P(no paga a tiempo). Es el insumo del calendario de vencimientos.

**Rebaje** — `max(saldo_ayer - saldo_hoy, 0)`. Los aumentos de saldo (ruido, <2% del
total) se tratan como 0, no como rebaje negativo.

**`flg_last_loan_in_chain`** — campo de `dts_cobranza_creditos_cuotas` (nivel cuota) que
marca si un crédito es el último de su cadena de reenganches/refinanciamientos. Se deriva a
nivel crédito con `max(...)` agrupado por `id_ihfintech_loan` (es constante por crédito) y
se usa para excluir a los créditos reemplazados. Ver `FUENTES_DATOS.md`.

**Enfoque acumulado** — la metodología oficial: stock anclado al cierre del mes anterior +
calendario real del mes. Ver `meta_julio.py`.

**Enfoque "reinicio del reloj"** — metodología alternativa (no oficial, deprioritizada):
trata la foto de HOY como nueva línea base. Ver `meta_desde_hoy.py` y `ESTADO.md`.

**Backtest** — comparar la proyección del modelo contra el recupero REAL de un mes ya
cerrado. La única forma confiable de validar un cambio de constante o metodología — ver
`DECISIONES.md`.

**Capital asegurado** — métrica alternativa (enfoque alfa, experimental): saldo capital
COMPLETO de los créditos que muestran al menos 1 día de pago en el mes, sin importar
cuánto pagaron. No es lo mismo que rebaje/recupero (que mide soles efectivamente pagados).
Ver `enfoque_capital_asegurado.md`.

**Cura sin pago** — episodio de mora que termina (`dayslate` vuelve a 0) sin que el saldo
capital baje. Candidato a reestructuración crediticia (facilidad de pago), no un cobro
real. Ver `enfoque_salida_mora.md` (enfoque beta).

**`motivo_apertura`** — campo de `dts_cobranza_creditos_cuotas`
(`_motivo_apertura__motivo_apertura`, nombre duplicado por venir de un custom field
anidado de Mambu), valores 1-4. Poblado en solo 0.4% de los créditos. Sin diccionario de
datos confirmado, pero fuertemente asociado a "cura sin pago" — ver `enfoque_salida_mora.md`.

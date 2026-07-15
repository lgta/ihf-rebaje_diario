# Ideas, pendientes y cosas ya descartadas

Dos secciones. Lee la segunda antes de proponer algo — puede que ya se haya probado.

## Pendientes activos

**Ver [`PENDIENTES.md`](PENDIENTES.md) para la lista accionable vigente** — desde
2026-07-15 el proyecto solo mantiene 2 enfoques (acumulado/oficial y alfa/capital
asegurado, ver `DECISIONES.md`), y ese archivo concentra las tareas concretas para
completarlos, organizadas por enfoque. Esta sección quedó deliberadamente corta para no
duplicar esa lista.

Pendientes de investigación de fondo que no son tareas de "un enfoque" específico (también
listadas en `PENDIENTES.md`, tareas compartidas):
- Extender el backtest a 3-6 meses cerrados más (un solo mes no alcanza para confirmar que
  ±5-16% es el error típico).
- Recalibrar las curvas excluyendo cada mes de prueba del backtest (hoy solo la tasa
  `P(no paga a tiempo)` se recalibra estrictamente fuera de muestra).
- Investigar por qué el stock sobreestimó +16.2%/+7.2% en junio específicamente.
- `installmentlastpaiddate` (`dts_cobranza_creditos_cuotas`, nivel cuota) — sin explotar,
  podría precisar el punto ciego de 1 día de `dayslate` (bug 9 en `BUGS.md`).
- Reorganizar en carpetas (`sql/`, `python/`, `docs/`) si el root sigue creciendo — baja
  prioridad, no bloquea nada.

## Ideas ya probadas y descartadas (no las repitas sin releer por qué fallaron)

- **P(no paga a tiempo) = 25-28% plano** (complemento simple de "% paga a tiempo" a nivel
  cuota, con la curva de recupero actual sin cambios). Sobreestima +66% a +81% en el
  backtest de junio — ver bug 10 en `BUGS.md`. Motivo: la tasa y la curva miden poblaciones
  distintas.
- **Motor "cuota-consistente"** (tasa 8.62% + curva propia, ambas por vencimiento de
  cuota). Subestima -35.7% — falla en la dirección opuesta a la anterior. Ver
  `motor_cuota_vencimiento.sql`.
- **Quitar el límite superior de 30 días al reincorporar aged-out survivors.** Se probó
  mentalmente y se descartó antes de implementar: arrastraría S/9.57M de cartera 90+ días
  que nunca fue parte de la asignación del mes. La corrección correcta es quirúrgica (JOIN
  contra la foto de asignación), no un filtro más laxo.
- **Usar `principalamountpaid`/`principalamountdue` para capital.** Rotos — sobre-atribuyen
  pagos anticipados, el acumulado supera 400%. Ver bug 5.
- **Usar la tasa de entrada del propio mes de prueba para calibrar el backtest de ese
  mismo mes** (la tasa real de junio, 10.96%). Es data leakage — descartado por diseño, se
  usa siempre fuera de muestra.
- **Enfoque "reinicio del reloj"** (recalcular todo desde "hoy" en vez del cierre del mes
  anterior). Deprioritizado desde 2026-07-10 (requería un parche manual cada vez, ver bug 7
  en `BUGS.md`) y descontinuado formalmente el 2026-07-15 — el usuario confirmó que la
  pregunta que le interesa siempre es la del mes completo. Ver `DECISIONES.md`.
- **Enfoque beta "salida de mora"** (cura real vs. reestructuración al salir de mora).
  Exploratorio: llegó a confirmar reincidencia (80.8% de "cura sin pago" vuelve a caer en
  mora), pero se descontinuó el 2026-07-15 al acotar el proyecto a 2 enfoques antes de
  construir la curva/proyección completa (quedaba como opción (a) pendiente). Ver
  `DECISIONES.md` y bug 11 en `BUGS.md` para el hallazgo tal como quedó documentado.

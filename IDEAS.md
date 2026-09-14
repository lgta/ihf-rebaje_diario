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
- ~~Extender el backtest a 3-6 meses cerrados más~~ **hecho 2026-08-26**: 7 meses cerrados
  (202601-202607) en `backtest_capital_asegurado_unificado.py`. El error típico resultó más
  grande de lo que sugerían 4 meses (media 10.55%, febrero -19.6%).
- ~~Recalibrar las curvas excluyendo cada mes de prueba~~ **hecho 2026-08-26** para la curva de
  **nuevos**: calibración rodante de 12 meses, `[M-12, M-1]`. Leak medido: 0.10pp. **Falta la
  curva de stock**, que sigue con ventana fija (tarea 18c).
- ~~**Explicar el sesgo de "nuevos"**~~ **explicado (tarea 19, 2026-09-01):** la tasa de entrada se
  calibraba por conteo y se aplicaba sobre soles. Corregida, lo que queda es la **caída de
  activación** (tarea 19), hoy el frente abierto principal.
- Rodar también la curva de **stock** (lo que queda de tarea 18c). **Probado en 18c/18g: empeora**
  (corr. 0.848→0.820, muestra chica); necesita otro enfoque, no el de nuevos.
- ~~`installmentlastpaiddate`~~ **hecho 2026-08-20** (tarea 7, capa fantasma) y **superado** por
  `dias_atraso_cuota`, que cierra el punto ciego de `dayslate` sin capa aparte (tarea 17).
- Reorganizar en carpetas (`sql/`, `python/`, `docs/`) si el root sigue creciendo — baja
  prioridad, no bloquea nada.

## Ideas ya probadas y descartadas (no las repitas sin releer por qué fallaron)

- **Colapsar `avance_band` de 4 buckets a 3** (fusionar 40-70% con 70%+). Medido 2026-08-26:
  el efecto sobre el total de un mes es **0.008%** — gratis, pero también inútil. Se rechazó
  porque `avance_band` es además el eje por el que se lee la desviación, y colapsado esconde
  que la banda 70%+ corre +89.5% en agosto contra +21.9% de la 40-70%. La observación que lo
  motivó (que las curvas no se separan) **es correcta**: difieren ≤3.9% y se cruzan en el día
  14. Ver `DECISIONES.md`.
- **Corte binario `finde`/`semana` sobre el día de semana del vencimiento** (el que proponían
  Fase 2/3). Está mal especificado: ninguna cuota vence domingo, así que `in (6,7)` es solo
  sábado y deja "vence viernes" —que entra sábado, día no hábil— del lado hábil. Captura ~2/3
  de la ganancia del corte abierto a 6 días (0.781 vs. 0.878 de correlación diaria). Ver bug 21.
- **Factor por día del mes con un parámetro por día (31 parámetros).** Sobreajusta: entre dos
  mitades disjuntas de la ventana la correlación es solo +0.51. Lo que sí reproduce son los
  días de pago de planilla — quincena y 30-31 — así que quedó en **2 parámetros**. Ver
  `DECISIONES.md` y `curvas_crudas.py`.
- **Segmentar la curva por día del mes DE ENTRADA de la cohorte.** No es la forma correcta de
  modelar la quincena: el efecto le pega a *todas* las cohortes vivas ese día, hayan entrado el
  2 o el 14. Es un efecto del día en que llega la plata, no del día de entrada. Segmentarlo como
  cohorte daría ~30 curvas, con las tardías truncadas por el fin de mes, y no resolvería el
  mecanismo. Se modela como factor multiplicativo sobre el día de pago.
- **Agrupar el día de semana en 3 regímenes de día de entrada** (hábil / sábado / domingo).
  Conserva 0.849 de los 0.878 de correlación, pero compra menos robustez de la que parece:
  engrosa solo el lado hábil, que ya era el más gordo, y la celda mínima sube de 1,241 a 1,519
  entradas (+22%, no al doble) porque las celdas flacas son las de sábado y domingo.
- **Usar el error de fin de mes para elegir entre dos segmentaciones de curva.** No tiene
  resolución: la diferencia pareada tiene un desvío 10x su media, harían falta ~1,050 meses.
  Usar métricas diarias. Ver `DECISIONES.md`.

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

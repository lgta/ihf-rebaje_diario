# Ideas, pendientes y cosas ya descartadas

Dos secciones. Lee la segunda antes de proponer algo — puede que ya se haya probado.

## Pendientes activos

1. **Extender el backtest a 3-6 meses más.** Junio 2026 es un solo punto de dato; antes de
   tratar ±5-16% como error típico del modelo, hay que repetirlo en varios meses cerrados.
2. **Recalibrar las curvas excluyendo el mes de prueba.** Hoy `curva_stock`/`curva_nuevos`
   se calibran sobre los 14 meses completos (incluyen junio, peso marginal ~1/14) — solo la
   tasa `P(no paga a tiempo)` se recalibró estrictamente fuera de muestra. Un backtest
   totalmente riguroso recalcularía también las curvas por mes de prueba.
3. **Investigar por qué la sobreestimación del stock fue +16.2% en junio** específicamente
   (vs. +0.7% del motor de nuevos). Podría ser varianza normal (el tramo 9-15 osciló entre
   9.8% y 18.8% de un mes a otro en los 14 meses de historia) o un segmentador que falta.
4. **`installmentlastpaiddate`** (`dts_cobranza_creditos_cuotas`, nivel cuota) — dato
   aportado por el usuario, todavía sin explotar. Podría precisar aún más el punto ciego de
   1 día de `dayslate` (bug 9 en `BUGS.md`) cruzándolo contra la fecha exacta en que
   `dayslate` pasa a 1 para el mismo crédito.
5. **Entender por qué la tasa "cuota-consistente" (8.62%) es tan distinta de la de
   `dayslate` (13.38%)**, dado que ambas deduplican episodios de forma análoga y parten de
   casi la misma población de "elegibles" (358,361 vs 358,580). Sigue sin explicación clara
   — ver bug 10 en `BUGS.md`. Posibles pistas sin probar: si los créditos tienen cuotas de
   cadencia muy frecuente (¿diaria?), el `LAG` sobre `fechavencimiento` podría estar
   comparando cuotas que no son realmente "consecutivas" en el sentido que dayslate captura.
6. **Decidir el destino final del hilo "reinicio del reloj"** (`meta_desde_hoy.*`). Quedó
   deprioritizado (ver `ESTADO.md`) pero no borrado — si nadie lo va a usar, considerar
   archivarlo explícitamente o quitarlo del README para no confundir a quien llegue nuevo.
7. **Actualizar los artifacts marcados "⚠ desactualizado"** en `ESTADO.md` (Meta en vivo,
   Deck) con el fix de aged-out y los hallazgos de dayslate, o retirarlos de circulación si
   no se van a mantener.
8. **Reorganizar en carpetas** (`sql/`, `python/`, `docs/`) si el root sigue creciendo — hoy
   son ~20 archivos sueltos. Baja prioridad, no bloquea nada.
9. **Backtest del enfoque "capital asegurado"** (`enfoque_capital_asegurado.md`) contra
   junio 2026, mismo patrón que `fase3_backtest.sql`. Es experimental y no debe reportarse
   como KPI oficial hasta esto.
10. **Enfoque beta — salida de mora** (`enfoque_salida_mora.md`): decidir si construir la
    curva completa + proyección (como Alfa), investigar reincidencia de los créditos
    "cura sin pago" (¿vuelven a caer en mora?, ¿en cuánto tiempo?), o ambas. Conseguir
    diccionario de datos real para `motivo_apertura` (preguntar a negocio/producto).

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

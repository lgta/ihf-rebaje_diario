# Avance de julio por fase de cobranza (Temprana/Especializada/Recovery)

> **Estado: análisis puntual (snapshot), no un enfoque con curva propia.** Reutiliza las
> curvas ya calibradas del Enfoque alfa (`enfoque_capital_asegurado.md`). Ejecutado
> 2026-07-13, corte al 12-jul.

## El concepto

El proyecto viene trabajando con una población de mora **inferida** (mora 1-30 vía
`dayslate`, ver `FUENTES_DATOS.md`). El usuario proporcionó una tabla nueva,
`dts_asignaciones_cobranza`, que trae la asignación **real** de cobranza día a día — quién
trabaja el negocio, y bajo qué fase de estrategia (`fase_estrategia`: TEMPRANA,
ESPECIALIZADA, RECOVERY). Este análisis cruza esa asignación real contra
`dts_mambu_loans_hist` para medir avance, usando la métrica de **capital asegurado**
(Enfoque alfa: saldo COMPLETO del crédito si mostró ≥1 día de pago, no soles cobrados) —
confirmado con el usuario porque el formato de referencia que pidió reportar tenía
porcentajes (96.9%/85.6%) del orden de magnitud de capital asegurado, no del recupero
oficial (~12-20%/mes).

## `dts_asignaciones_cobranza`: quirks encontrados

1. **Sin datos del 1-jul.** La tabla solo tiene `fecha_base` desde 2026-07-02 (rango real:
   2026-07-02 a 2026-07-10 a la fecha de esta corrida — parece una tabla nueva, recién
   empezó a cargarse). **Se usa 2-jul como "día 1" de julio** (decisión confirmada con el
   usuario, no hay otra opción con datos reales).
2. **No trae `id_ihfintech_loan` directo.** El grano es `(dni_ce, producto)` por
   `fecha_base` — para llegar al crédito hay que cruzar contra
   `dts_cobranza_creditos_cuotas` (`dni`, `producto`, `status='ACTIVE'`,
   `flg_last_loan_in_chain=1`). El cruce es limpio (1:1, sin fan-out) y matchea ~96.5% de
   las filas asignadas — el resto probablemente ya se pagó/canceló entre la asignación y
   la corrida de esta query.
3. **`fase_estrategia` se fija al momento de asignar la campaña, no se recalcula a
   diario.** Un crédito puede seguir etiquetado "Temprana" aunque para el corte de esta
   query ya haya cruzado 30 días de mora (medido vía `dayslate`) — no es un error de
   datos, es el comportamiento esperado del sistema de asignación del negocio.
4. **La asignación a Especializada/Recovery es a nivel CLIENTE (DNI), no crédito.** Si un
   cliente tiene otro crédito en mora profunda, TODOS sus créditos (incluso uno sano o
   recién entrado) se asignan a la fase más severa por arrastre — por eso aparecen
   créditos con mora 0 o 1-30 dentro de Especializada/Recovery.

## Metodología

1. **Cohorte día 1:** créditos asignados el 2026-07-02, cruzados a `id_ihfintech_loan`
   (ver quirk 2).
2. **Segmento nuevo/stock:** se deriva del `dayslate` a cierre de junio (no de la fase del
   negocio) — `nuevo` = no estaba en mora el 30-jun; `stock` = sí estaba (cualquier
   profundidad). Es el mismo criterio "tramo fijo al momento de asignación" que usa el
   resto del proyecto (`DECISIONES.md`).
3. **Sub-tramo (1-8/9-15/16-30):** solo se aplica a Temprana-stock, usando el tramo a
   cierre de junio (`tramo_jun`) — es el único caso con cobertura de curva real. "Nuevo"
   siempre entra con 1-2 días de mora (trivial, no aporta separarlo) y
   Especializada/Recovery casi no tienen saldo dentro de 1-30 (ver cobertura abajo).
4. **Meta (%):** para créditos con tramo/avance dentro de lo calibrado, se usa la curva de
   capital asegurado del Enfoque alfa (`curva_asegurado_stock_seg.csv` para stock,
   `curva_asegurado_nuevos_seg.csv` para nuevos, indexada por días desde entrada),
   evaluada en el **día 11** (2-jul a 12-jul). **Especializada y Recovery no tienen curva
   calibrada** — el Enfoque alfa nunca se construyó más allá de mora 1-30. Se reporta
   "N/D" cuando la cobertura de saldo con curva es 0%.
5. **Real (%):** capital asegurado real observado — suma del saldo día 1 de los créditos
   con al menos 1 día de pago entre el 2-jul y el 12-jul (última fecha con datos en
   `dts_mambu_loans_hist` a la fecha de esta corrida).

Query: `avance_cobranza_fase.sql` (extracción, una fila por crédito). Agregación y cruce
con curvas: `avance_cobranza_fase.py`. Datos cacheados: `datos_avance_fase/`.

## Resultados (corte 2-jul a 12-jul-2026, día 11)

| COBRANZA | Segmento | Cuentas | Asignación (S/) | Cobertura curva | Meta Cap. Aseg. (%) | Meta Cap. Aseg. (S/) | Real Cap. Aseg. (S/) | Real Cap. Aseg. (%) | Real-Meta (pp) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| TEMPRANA | nuevo | 1,258 | 2,186,567 | 85.8% | 74.2% | 1,392,192 | 1,529,667 | 70.0% | -4.3 |
| TEMPRANA | stock (31+, arrastre) | 18 | 29,882 | 0.0% | N/D | N/D | 1,283 | 4.3% | N/D |
| TEMPRANA | stock (1-8) | 540 | 932,634 | 100.0% | 60.8% | 566,771 | 445,591 | 47.8% | -13.0 |
| TEMPRANA | stock (9-15) | 318 | 572,440 | 100.0% | 33.1% | 189,506 | 164,385 | 28.7% | -4.4 |
| TEMPRANA | stock (16-30) | 350 | 651,552 | 100.0% | 20.3% | 132,569 | 150,090 | 23.0% | +2.7 |
| ESPECIALIZADA | nuevo | 2 | 2,002 | 100.0% | 76.4% | 1,530 | 0 | 0.0% | -76.4 |
| ESPECIALIZADA | stock | 1,923 | 3,919,090 | 4.1% | N/D | N/D | 293,003 | 7.5% | N/D |
| RECOVERY | stock | 3,632 | 8,338,449 | 0.0% | N/D | N/D | 34,157 | 0.4% | N/D |
| (sin fase) | nuevo | 137 | 273,452 | 89.7% | 74.6% | 183,144 | 174,511 | 63.8% | -10.8 |
| (sin fase) | stock | 125 | 213,861 | 99.4% | 43.4% | 92,185 | 105,081 | 49.1% | +5.8 |

**Nota:** "ESPECIALIZADA-nuevo" (2 cuentas) es un caso límite de timing de asignación, sin
peso material. "(sin fase)" son 262 créditos (S/487K) sin `fase_estrategia` poblada en la
tabla de asignaciones — residual, no investigado.

## Lectura de resultados

- **Temprana** es la única fase con curva calibrada casi completa (85.8%-100% de
  cobertura). Va **ligeramente atrasada** frente al ritmo esperado a día 11: nuevos -4.3pp,
  stock 1-8 -13.0pp (el tramo más rezagado), stock 9-15 -4.4pp, stock 16-30 **+2.7pp**
  (adelantado). El patrón (peor en 1-8, mejor en 16-30) es la inversa de lo esperado por
  frecuencia histórica (mora baja paga más seguido) — con solo 11 días de dato no alcanza
  para saber si es ruido normal o una señal real; no ajustar nada sin más meses de
  evidencia (mismo principio que el backtest oficial, `DECISIONES.md`).
- **Especializada y Recovery no tienen meta con la que comparar** — el modelo nunca se
  calibró para mora 31+. Lo único que se puede reportar es lo observado: 7.5% y 0.4% de
  capital asegurado respectivamente a día 11, muy por debajo de Temprana — consistente con
  que la mora profunda paga con mucha menor frecuencia (ya documentado en
  `enfoque_capital_asegurado.md`, aunque nunca antes medido para más de 30 días).

## Pendientes / posibles próximos pasos

1. Si este cruce resulta útil de forma recurrente, considerar automatizarlo como parte del
   seguimiento regular (hoy es una corrida puntual, no un job).
2. Si se quiere una "Meta" real para Especializada/Recovery, habría que calibrar curvas de
   capital asegurado (o de recupero) para mora 31+ — no existe ese trabajo hoy, sería un
   enfoque nuevo del proyecto.
3. Investigar el residual "(sin fase)" (262 créditos, S/487K) — por qué no tienen
   `fase_estrategia` poblada.
4. La tabla `dts_asignaciones_cobranza` solo tiene 9 días de historia a la fecha — según
   se acumule más historia, reconsiderar si "día 1 = 2-jul" sigue siendo el mejor ancla o
   si conviene esperar a tener el 1-jul real de un mes futuro.

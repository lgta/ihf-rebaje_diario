# Seguimiento mensual (proyectado vs. real)

Una fila por mes cerrado. El objetivo es detectar si el modelo se degrada con el tiempo —
un solo mes (junio) no alcanza para saber si ±5% es el error típico o una casualidad. Ver
`IDEAS.md` punto 1.

**Cómo agregar un mes:** una vez cerrado, replicar el patrón de `fase3_backtest.sql`
(stock al cierre del mes anterior, calendario real del mes sin filtro `installmentstate`,
recupero real vía `dts_mambu_loans_hist`) ajustando las fechas, y anotar el resultado acá.

## Recupero oficial (soles cobrados) — se sigue trackeando en paralelo

> Desde 2026-07-13 esta ya no es la meta principal reportada en `ESTADO.md` (ver sección
> de capital asegurado abajo) — sigue siendo un modelo validado y se sigue calculando.

> **2026-08-26 (continuación 2) — MOTOR MIGRADO A `dias_atraso_cuota` (tarea 18e, decisión
> del usuario).** Reemplaza `dayslate`/`P_NO_PAGA_DIA0=13.38%` (filas de junio/julio con esa
> metodología quedan como referencia histórica más abajo, no en la tabla vigente). Mismo
> refinamiento de forma que ya está en producción en Capital Asegurado: ventana rodante de 12
> meses sin leak (tasa por SOLES y curva de nuevos), día de semana del vencimiento, factor de
> quincena, factor de cierre real en stock (ventana de stock FIJA — rodarla empeora, ya medido
> en Enfoque alfa vía 18c/18g). Motivo: `dayslate` tiene el mismo punto ciego (bug 9) que ya se
> corrigió en Capital Asegurado, y acá **nunca tuvo compensación** (no hay capa fantasma en
> Recupero Oficial) — el real capturado con `dias_atraso_cuota` es **148%-157% del real
> capturado con `dayslate`** en junio/julio (validado a nivel de caso: créditos donde
> `dayslate` marca 0 el mismo día que pagan, a veces cancelando el saldo completo). Detalle
> completo (Fases A-D + refinamiento v2) en `PENDIENTES.md` tarea 18e. **La meta de AGOSTO
> (fila de abajo) sigue con el motor viejo, sin tocar** — mismo criterio que Capital Asegurado:
> no se cambia el motor de un mes EN CURSO a mitad de mes. La meta de **septiembre** será la
> primera calibrada con este motor, en cuanto agosto cierre (31-ago, ventana `[202508,202607]`).

| Mes | Meta proyectada | Real | Error total | Error stock | Error nuevos | Tasa de entrada | Notas |
|---|---:|---:|---:|---:|---:|---:|---|
| Enero 2026 | S/2,394,155 | S/2,290,411 | **+4.5%** | +3.1% | +4.9% | 25.26% | `dias_atraso_cuota`, rodante. |
| Febrero 2026 | S/2,133,336 | S/2,227,338 | **-4.2%** | -5.6% | -3.8% | 25.00% | `dias_atraso_cuota`, rodante. |
| Marzo 2026 | S/2,998,996 | S/3,061,707 | **-2.0%** | -4.2% | -1.8% | 25.08% | `dias_atraso_cuota`, rodante. |
| Abril 2026 | S/2,715,849 | S/2,614,085 | **+3.9%** | +14.4% | +1.2% | 25.28% | `dias_atraso_cuota`, rodante. |
| Mayo 2026 | S/3,067,507 | S/2,893,212 | **+6.0%** | -0.3% | +7.2% | 25.31% | `dias_atraso_cuota`, rodante. |
| Junio 2026 | S/2,939,249 | S/2,538,947 | **+15.8%** | +12.6% | +16.6% | 25.26% | `dias_atraso_cuota`, rodante. Motor viejo (`dayslate`): +5.4% (ver histórico abajo). |
| Julio 2026 | S/3,882,039 | S/3,280,551 | **+18.3%** | -0.9% | +21.5% | 25.07% | `dias_atraso_cuota`, rodante. Motor viejo (`dayslate`): +17.6% (ver histórico abajo). |
| Agosto 2026 | S/2,108,435 | S/2,178,078 | **-3.2%** | +7.7% | -7.9% | 13.38% (fijo) | **CERRADA 2026-09-01.** Motor viejo (`dayslate`) a propósito — era un mes en curso cuando se migró el motor (18e). **Real medido también con `dayslate`, la misma definición que la meta** (`tarea19_real_agosto_recupero_cierre.sql`): compararla contra el real de `dias_atraso_cuota` inflaría el error por cambio de universo, no por ejecución. Ese real, como referencia, es S/3,174,012 = **146%** del de `dayslate` — en línea con el 148-157% que 18e midió en junio/julio. Stock S/711,160 + nuevos S/1,397,275. Ver `meta_agosto.py` v3. |

Magnitud media de error de cierre (7 meses, motor nuevo): 7.83%. Correlación media de
incrementos diarios: **0.837** (vs. 0.560 antes del refinamiento v2). Calibración: nuevos
rodante `[M-12,M-1]` sin leak (tasa y curva); stock ventana fija 202504-202606. Código:
`backtest_tarea18e_recupero_oficial_v2.py`, series diarias en
`datos_tarea18e/serie_diaria_recupero_v2_*.csv`.

> **Septiembre 2026 — EN CURSO, seguimiento al 12-sep** (último día completo al 13-sep). Meta
> S/3,928,776, la primera con el motor 18e. Real **S/1,089,167 contra S/1,526,191 proyectado al
> mismo día: −28.6%** (stock −17.0%, nuevos −31.2%), correlación diaria 0.948. Va más lejos que el
> alfa: el stock activa +4.0% en alfa pero rebaja −17.0% acá, lo que apunta a pagos más chicos que
> los de la curva (lectura, no verificada crédito a crédito). Real medido con `dias_atraso_cuota`,
> la misma población de la meta (`tarea19_real_septiembre.sql`, columna `rebaje_dia`;
> `seguimiento_septiembre.py`).

**Histórico — motor anterior (`dayslate`, `P_NO_PAGA_DIA0=13.38%`), reemplazado 2026-08-26:**

| Mes | Meta proyectada | Real | Error total | Error stock | Error nuevos | Motivo principal | Notas |
|---|---:|---:|---:|---:|---:|---|---|
| Junio 2026 | S/1,806,299 | S/1,713,815 | **+5.4%** | +16.2% | +0.7% | Stock sobreestimado — la curva de maduración de stock corre por encima de lo real ese mes; nuevos casi exacto. | Primer backtest. Curvas calibradas sobre 14 meses (incluyen junio, peso ~1/14 — no es estrictamente fuera de muestra, solo la tasa de entrada lo es). Ver `fase3_backtest.sql`, `backtest_junio.py`. |
| Julio 2026 | S/1,776,174 | S/2,088,911 | **+17.6%** | +2.0% | +22.5% | Nuevos sobreestimado — la tasa/curva de nuevos corre muy por encima de lo real ese mes (fuente principal del error, no el stock). No es el mismo mecanismo que bug 14 (esa reconciliación es solo del enfoque alfa, no de este). | Cerrado 2026-08-18 (mes completo). Ver `cierre_julio.sql` (bloques J3/J4). |

## Capital asegurado (enfoque alfa) — meta principal desde 2026-07-13

> **Desde 2026-07-13 esta es la meta principal del proyecto** (a pedido explícito del
> usuario), no una métrica complementaria. Sigue sin ser comparable en soles contra la
> tabla de recupero de arriba (mide capital que "activó" pago, no soles recuperados — ver
> `enfoque_capital_asegurado.md`). El recupero se sigue trackeando en paralelo en la tabla
> de arriba.

> **2026-08-20 — capa "fantasma" adoptada (bug 14, ver `BUGS.md` y `reconciliacion_
> vw_seguimiento_temprana.md`):** créditos que pagan una cuota exactamente 1 día tarde y
> que `dayslate` nunca ve (punto ciego de bug 9). Tasa nueva e independiente `P_FANTASMA`
> (no reemplaza ni se mezcla con `13.38%`), activada 100% el día siguiente al vencimiento.
> Las filas de junio/julio de abajo ya están recalculadas con esta capa — **al recalcular
> julio también se corrigió un error de signo** que tenía esta tabla (decía
> "+4.7%/+1.0%/+6.3%", sobreestimando; el número correcto —incluso antes de agregar la
> capa fantasma— es que julio SUBESTIMA, igual que junio, no al revés).

> **2026-08-20 (mismo día) — dedup de bug 11 aplicado (ver `BUGS.md`):** regla validada
> contra los 687 casos conflictivos completos de la historia (antes solo una muestra de
> 16) y aplicada a `enfoque_capital_asegurado.sql`/`_backtest.sql`/`cierre_julio.sql`. Junio
> subió de +0.7% a +2.2% (el componente "nuevos" pasó de -8.6% a -5.8% — el fix elimina
> "pagos" espurios detectados contra una fila duplicada en S/0 de un reenganche). Julio no
> se movió (0 filas duplicadas relevantes en su ventana, verificado con los mismos números
> exactos antes/después del fix).

> **2026-08-20 (continuación) — fix de frontera de mes en la capa fantasma + tasa
> `P_FANTASMA` recalibrada (bug 14, ver `BUGS.md`):** la verificación a nivel crédito
> encontró que la capa fantasma no cubría una cuota vencida el ÚLTIMO DÍA de un mes,
> pagada 1 día tarde el mes siguiente (cobertura 90.7%→99.7% al incluirla). Como tasa y
> calendario deben compartir la misma definición de "periodo" (principio no negociable de
> `CLAUDE.md`), `P_FANTASMA` se recalibró junto con el fix: **8.4534% → 8.5524%**. Junio
> sube de +2.2% a **+2.65%** (el 31-may no tiene cuotas, así que el movimiento es 100% de
> la tasa); julio sube de +0.12% a **+2.17%** (el 30-jun sí tiene 9,115 cuotas — el motivo
> del alza en julio está en la sección de bug 14). Ambos siguen siendo buenos números,
> lejos de bug 10. Meta de agosto sube de S/16,351,397 a S/16,410,194 (+0.4%, chico —
> incluye el mismo hueco para el 31-jul, solo 77 créditos/S/140,194).

> **2026-08-24 — fix del índice de la curva de nuevos (bug 18, ver `BUGS.md`):** la curva de
> "nuevos" se calibra indexada desde la ENTRADA en mora (= vencimiento + 1, verificado en el
> 99.99% de los casos), pero los proyectores la indexaban desde el VENCIMIENTO — aplicaban
> `curva[k]` donde correspondía `curva[k−1]`. Corregido a `dias_desde_entrada = d - dd - 1`
> en los 4 backtests y en `meta_agosto_capital_asegurado.py`. **La capa fantasma NO cambió**
> (no usa curva; su índice `d - dd >= 1` ya era correcto) — en junio y agosto hubo que
> desacoplar su guard del de la curva para dejarla intacta, verificado: stock y fantasma dan
> idéntico antes/después en los 4 meses. **El error EMPEORA en los 4 y se corrige igual**
> (principio de `CLAUDE.md`, "el error se explica, no se optimiza"): abril -17.6%→**-19.2%**,
> mayo -4.4%→**-6.8%**, junio +2.65%→**+1.6%**, julio -0.2%→**-3.3%**. El bug estaba
> compensando parcialmente el sesgo ya conocido de que "nuevos" subestima en todos los meses;
> al corregirlo ese sesgo queda expuesto en su tamaño real (-27.3% abr, -20.1% may, -8.0%
> jun, -19.2% jul) y es lo que hay que explicar (volumen/mix/gestión), no tapar. Meta de
> agosto: S/16,410,194 → **S/16,211,015** (-1.2%).

> **2026-08-25 — `P_FANTASMA` recalibrado con `dias_atraso_cuota` (tarea 17 fase 3, ver
> `BUGS.md` bug 16): 8.5524% → 8.6163%.** Redefinición del universo "fantasma" (antes solo
> pagos exactamente 1 día tarde vía `dias_vencimiento_a_pago=1`; ahora cualquier entrada que
> `dias_atraso_cuota` detecta y `dayslate` no ve, mecanismo más amplio — incluye el hueco de
> fin de semana de asignaciones). Fase 3 confirmó primero que la activación instantánea
> (100% el día siguiente, sin curva) sigue siendo correcta incluso con esta definición más
> amplia (99.6% de activación ponderada en el día 0, verificado en 2 ventanas de calibración,
> 12 y 6 meses) — **no cambia la arquitectura, solo la constante**. Se adoptó la tasa de la
> ventana de 12 meses (abr25-mar26, fuera de muestra de los 4 meses de backtest), consistente
> con la ventana usada para las demás curvas del proyecto. Movimiento chico en los 4
> backtests (afecta solo el componente fantasma, stock y nuevos quedan exactamente iguales):
> abril -19.2%→**-19.0%**, mayo -6.8%→**-6.5%**, junio +1.6%→**+1.9%**, julio
> -3.3%→**-3.0%**. Meta de agosto: S/16,211,015 → **S/16,257,325** (+0.3%); avance al 21-ago
> +5.1%→**+4.8%**. Pendiente: día de la semana del vencimiento tiene una tasa fantasma
> distinta (semana 9.08%-9.36% vs. fin de semana 5.67%-6.31%, estable entre ventanas) — no
> se segmentó todavía, queda como refinamiento futuro si se justifica el impacto.

> **2026-08-25 (continuación) — MOTOR UNIFICADO ADOPTADO EN PRODUCCIÓN (tarea 17 Fase 4).
> La capa fantasma se eliminó.** El enfoque alfa pasa de 3 componentes (stock + nuevos +
> fantasma, `dayslate`) a 2 (stock + nuevos, `dias_atraso_cuota`). Una sola tasa
> `P_ENTRADA = 21.9918%` reemplaza a `13.38% + 8.6163%` (suma 21.9963%, 0.005pp de
> diferencia — la masa siempre estuvo bien). La ex-población fantasma pasa a ser el **día 0
> de la curva de nuevos** (30.6%-37.0% según `avance_band`, contra una tasa plana ciega al
> segmento). Un solo calendario indexado por **día de entrada** reemplaza a los dos
> anteriores. Los 4 backtests y la meta de agosto están recalculados; los 2 artifacts,
> republicados. **El error medio sube de 6.20% a 7.22% y se adoptó igual** — Principio de
> interpretación del error de `CLAUDE.md`. Ver `BUGS.md` bug 16 (Fase 4) y bug 20.

> **2026-08-26 (continuación) — MOTOR UNIFICADO v3 (tarea 18g): factor de CIERRE REAL para
> STOCK.** Mismo mecanismo que 18f ya había corregido para nuevos, aplicado a stock por
> primera vez: el "cierre" de cada mes es su ÚLTIMO DÍA REAL (28/29/30/31 según corresponda),
> no un número de día fijo — ver `analisis_sesgo_nuevos_18b.md` sección 2 y
> `analisis_tarea18g_cierre_real.md`. Corrige exactamente el mes que lo necesitaba: **febrero
> (el único mes de 28 días del test) es el único mes donde stock también fallaba fuerte**
> porque su cierre real nunca caía en el grupo "30/31". Error de stock de febrero
> **-11.0% → -8.3%**, correlación diaria de stock 0.818 → 0.856 (mejora real, no resuelve el
> mes del todo). Ventana de stock sigue **FIJA** (202504-202606) — se probó rodarla (cerraría
> tarea 18c) y **empeora las métricas diarias** (correlación 0.848 → 0.820), así que se
> descarta esa parte. El reindex análogo para nuevos se probó pero **no se adoptó** — impacto
> marginal (0.886 → 0.888) frente al riesgo de tocar el esquema que ya usa la meta de agosto
> publicada. **La meta de agosto (S/17,117,628) no se tocó** — sigue leyendo exactamente los
> mismos archivos que ya tenía; el factor de cierre vive en
> `curva_unificada_stock_seg_v3.csv` + `factor_dia_mes_stock.csv`, aparte.

| Mes | Proyectado | Real | Error total | Error stock | Error nuevos | Corr. diaria | Motivo de diferencia | Notas |
|---|---:|---:|---:|---:|---:|---:|---|---|
| Enero 2026 | S/10,162,760 | S/11,429,495 | **-11.1%** | -0.6% | -13.4% | 0.950 | Mes nuevo, agregado al extender el backtest de 4 a 7 meses. El mejor seguimiento diario de los 7. | Calibración rodante [202501-202512]. |
| Febrero 2026 | S/9,404,912 | S/11,620,886 | **-19.1%** | -8.3% | -21.6% | 0.837 | **El peor de los 7.** Con el factor de cierre real (v3) el stock mejora de -11.0% a -8.3% — es el único mes de 28 días, así que es el que más se beneficia. Sigue siendo el dato que más pesa para tarea 18b: con 4 meses el sesgo de nuevos parecía tocar techo en -16%, y acá llega a -21.6%. | Idem. Mes corto (28 días). |
| Marzo 2026 | S/12,440,972 | S/14,466,133 | **-14.0%** | +5.7% | -16.1% | 0.874 | Mes nuevo. Mismo patrón que abril: stock sobreestima, nuevos subestima más fuerte. | Idem. |
| Abril 2026 | S/11,867,742 | S/13,389,034 | **-11.4%** | +8.1% | -15.5% | 0.907 | Con la arquitectura de 3 componentes figuraba en -19.0%, pero ese número tenía un denominador inconsistente (**bug 20**): corregido daba -13.4%. | Recalculado 2026-08-26 con el motor v3 (W3 nuevos + cierre real stock) y calibración rodante. |
| Mayo 2026 | S/13,179,165 | S/14,763,546 | **-10.7%** | -0.4% | -12.3% | 0.857 | **El mes donde más se nota el día de la semana:** era el peor de los 7 en seguimiento diario (0.32) y pasó a 0.86. El error de cierre en cambio empeoró (-8.7% → -10.9%) porque su calendario de fin de mes es 45.8% de vencimientos de fin de semana. Las dos cosas son ciertas a la vez. | Idem. |
| Junio 2026 | S/13,177,167 | S/13,539,856 | **-2.7%** | +5.8% | -4.7% | 0.900 | Junto con julio, el mes más cerca de su meta. | Idem. |
| Julio 2026 | S/16,816,807 | S/17,323,922 | **-2.9%** | -3.5% | -2.8% | 0.880 | El mes más parejo entre componentes. Su calendario de fin de mes no tiene ningún vencimiento de fin de semana, y por eso es el que más mejora con la curva por día de semana (-5.0% → -2.9%). | Idem. |
| Agosto 2026 | S/17,117,628 | S/17,322,872 | **-1.2%** | -1.3% | -1.1% | — | El mes más ajustado de todo el proyecto, y el más parejo entre componentes (stock -1.3%, nuevos -1.1%). Rompe la racha: "nuevos" venía subestimando en los 7 meses anteriores entre -2.8% y -21.6%. | **CERRADA 2026-09-01.** Meta con motor v2 (W3), sin el factor de cierre de stock (v3) — deliberado, ver bloque 2026-08-26: stock S/3,795,022 + nuevos S/13,322,607. Curvas [202507-202606]. `meta_agosto_capital_asegurado.py` v8; real de `tarea19_real_agosto_cierre.sql`. **Caveat de honestidad:** las curvas nunca vieron agosto, pero la ADOPCIÓN de W3 se decidió el 26-ago con 25 días del mes ya visibles — no es un test prospectivo limpio como lo será septiembre. Los cortes publicados se movieron al re-medir (21-ago S/11,595,123→S/11,547,707, -0.4%; 25-ago S/13,484,959→S/13,398,433, -0.6%): `dts_mambu_loans_hist` se re-expresa para días pasados. |

> **Septiembre 2026 — EN CURSO, seguimiento al 12-sep** (último día completo al 13-sep). Meta
> S/20,477,271 (v1, fijada el 1-sep). Real acumulado **S/7,155,605 contra S/8,666,800 proyectado al
> mismo día: −17.4%** (stock +4.0%, nuevos −21.6%). La forma se sigue muy bien: correlación de
> incrementos diarios **0.982** (nuevos 0.971). **El caveat de ~10% se está materializando, y lo
> supera:** en los 8 meses del backtest el cociente real/proyectado del día 12 quedó siempre entre
> 0.93 y 1.08, y el cierre terminó a ±4pp de él (agosto, con la meta prospectiva: 0.973 el día 12,
> 1.012 al cierre). Septiembre está en 0.826, fuera de ese rango. **La brecha es de volumen más que de
> conversión:** entró en mora 17.1% menos saldo que el esperado (calendario × tasa; hasta ~8pp de eso
> es el ancla al cierre de agosto, que no descuenta la amortización), y cada sol que entró activó
> 5.4% menos. Con la definición v2, la meta que habría salido el 1-sep es **S/19,814,433** y su real
> va en 0.849 de la trayectoria (`meta_septiembre_v2_dia1.py`): la definición explica una parte chica.
> **Descomposición con v2** (`backtest_septiembre_v2.py`): de 0.847 a 0.901 es el ancla — la tasa se
> calibra sobre el saldo al vencimiento y la meta la aplica sobre el del 31-ago, 10.5% mayor (bug 28) —;
> de 0.901 a 0.944 es la tasa realizada (22.90% contra 24.36%, el nivel de jun-ago); el resto es
> conversión (nuevos 0.909). El stock va en 0.998. Código: `tarea19_real_septiembre.sql` +
> `seguimiento_septiembre.py` (descomposición con `tarea24_v2_septiembre.sql`).

**Magnitud media de error de fin de mes, 7 meses: 10.26%** (10.55% antes del factor de cierre
de stock). **Correlación media de incrementos diarios de nuevos: 0.886** (sin cambios — el
reindex de nuevos no se adoptó); **de stock: 0.848** (0.841 antes). Los números de error y de
correlación miden cosas distintas y hay que leerlos juntos — ver abajo.
**Cómo leer las dos métricas — no son intercambiables.** El error de fin de mes ES la meta
contra la ejecución: es el número de negocio y el insumo de tarea 18b. Pero **no puede
arbitrar** si una curva está mejor segmentada que otra: la diferencia pareada entre variantes
tiene media -0.13pp y desvío **1.49pp**, o sea el ruido es 10x el efecto, porque el signo lo
fija la composición de fin de mes de cada mes. Resolver 0.13pp sobre el cierre necesitaría
~1,050 meses. La correlación de incrementos diarios aporta ~30 observaciones por mes en vez
de 1, y ahí los refinamientos de forma sí se distinguen — el día de semana del vencimiento
mejora los 7 meses sin excepción.

**Dos advertencias sobre el nivel de esta tabla.** (1) La curva de **stock** todavía no rueda
(sigue calibrada en 202504-202606), así que 6 de los 7 meses están dentro de su ventana y su
error de ene-jun está subestimado — es lo que queda abierto de tarea 18c. La curva de nuevos
sí rueda en los 7. (2) El motor unificado es ~1pp peor en error de cierre que la arquitectura
de 3 componentes y se adoptó igual — ver `BUGS.md` bug 16 (Fase 4): el parche plano
enmascaraba el sesgo de "nuevos" por ser sistemáticamente generoso, y el criterio de adopción
es la fidelidad del universo y de la medición, no el error.

## Qué mirar si el error crece

1. ¿El error es de stock o de nuevos? (la tabla ya los separa — en los 7 meses de 2026 el
   sesgo vive en nuevos, que subestima entre -2.8% y -21.6%, mientras el stock oscila entre
   -11.0% y +5.3% sin signo fijo. Febrero es el único donde los dos fallan en la misma
   dirección y fuerte).
1b. ¿El seguimiento **diario** también se degradó, o solo el cierre? Son cosas distintas: un
   mes puede terminar lejos de la meta y aun así haber sido seguido bien día a día (mayo:
   -10.9% de cierre con 0.857 de correlación diaria). Si lo que cae es la correlación, el
   problema es de forma de la curva; si lo que cae es solo el cierre, es volumen o gestión.
2. ¿Está dentro del rango de volatilidad mensual ya observado en la calibración? (ej. el
   tramo 9-15 del stock osciló 9.8%-18.8% entre meses en los 14 de historia — un +16% de
   error en un mes puntual puede ser varianza normal, no necesariamente un problema).
3. ¿Cambió la mezcla de la cartera? La cartera crece rápido (53k créditos mar-25 → 200k
   jul-26) — si la composición por tramo/avance se movió mucho respecto al histórico
   calibrado, eso solo se ve comparando el enfoque agregado vs. segmentado (ver
   `DECISIONES.md`, "mantener dos enfoques en paralelo").

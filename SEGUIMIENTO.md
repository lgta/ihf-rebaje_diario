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

| Mes | Meta proyectada | Real | Error total | Error stock | Error nuevos | Motivo principal | Notas |
|---|---:|---:|---:|---:|---:|---|---|
| Junio 2026 | S/1,806,299 | S/1,713,815 | **+5.4%** | +16.2% | +0.7% | Stock sobreestimado — la curva de maduración de stock corre por encima de lo real ese mes; nuevos casi exacto. | Primer backtest. Curvas calibradas sobre 14 meses (incluyen junio, peso ~1/14 — no es estrictamente fuera de muestra, solo la tasa de entrada lo es). Ver `fase3_backtest.sql`, `backtest_junio.py`. |
| Julio 2026 | S/1,776,174 | S/2,088,911 | **+17.6%** | +2.0% | +22.5% | Nuevos sobreestimado — la tasa/curva de nuevos corre muy por encima de lo real ese mes (fuente principal del error, no el stock). No es el mismo mecanismo que bug 14 (esa reconciliación es solo del enfoque alfa, no de este). | Cerrado 2026-08-18 (mes completo). Un solo mes adicional todavía no alcanza para saber si es varianza normal o degradación — ver tarea 9 de `PENDIENTES.md`. Ver `cierre_julio.sql` (bloques J3/J4). |
| Agosto 2026 | S/2,108,435 | *(mes en curso, corte 18-ago: S/1,147,110, -1.5% vs. proyectado al mismo día)* | — | — | — | — (mes en curso) | Stock S/711,160 + nuevos S/1,397,275. Ver `meta_agosto.py`. Cerrar esta fila cuando termine agosto. |

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

| Mes | Proyectado | Real | Error total | Error stock | Error nuevos | Motivo de diferencia | Notas |
|---|---:|---:|---:|---:|---:|---|---|
| Abril 2026 | S/11,708,992 | S/13,390,788 | **-12.6%** | +5.3% | -16.4% | El error más grande de los 4, mismo signo que el resto. Con la arquitectura anterior figuraba en -19.0%, pero ese número tenía un denominador inconsistente (**bug 20**): corregido daba -13.4%, muy cerca del -12.6% del motor unificado. | Recalculado 2026-08-25 con el motor unificado. Ver `backtest_capital_asegurado_unificado.py`. |
| Mayo 2026 | S/13,485,767 | S/14,767,586 | **-8.7%** | -1.3% | -9.8% | El mes que más empeora al pasar al motor unificado (-6.5% → -8.7%): con 3 componentes, el fantasma sobreestimaba +8.2% y compensaba parte del -20.1% de nuevos. Sin ese parche, el sesgo queda a la vista completo — aunque su magnitud baja a la mitad (-9.8%). | Idem. |
| Junio 2026 | S/13,191,522 | S/13,543,570 | **-2.6%** | +3.1% | -3.9% | Cambia de signo respecto de la arquitectura anterior (+1.9% → -2.6%) por la misma razón: el fantasma sobreestimaba +13.2% y empujaba el total por encima de lo real. | Idem. |
| Julio 2026 | S/16,454,855 | S/17,327,495 | **-5.0%** | -4.5% | -5.1% | El mes más parejo entre componentes — stock y nuevos se desvían casi lo mismo. Con 3 componentes: nuevos -19.2% contra fantasma +16.3%. | Idem. Este julio es el cuarto número que tiene el mes: +2.17% (calendario huérfano, bug 17), -0.2% (reconstruido), -3.0% (fix de índice, bug 18) y ahora -5.0%. |
| Agosto 2026 | S/17,274,766 | *(mes en curso, corte 21-ago: S/11,600,930, **-0.3%** vs. proyectado al mismo día; al 24-ago **-1.4%**)* | — | — | — | — (mes en curso, sin cerrar) | Meta con motor unificado: stock S/3,795,022 + nuevos S/13,479,744. La meta sube de S/16,257,325 a S/17,274,766 (+6.3%) — casi todo por el stock, que con `dias_atraso_cuota` resulta 30.2% mayor al cierre de julio (S/5.81M vs S/4.46M). El **real** casi no se mueve (S/11,600,930 vs S/11,620,780, -0.2%): es la misma realidad medida sin partir la población en tres. Ver `meta_agosto_capital_asegurado.py` v7. Cerrar esta fila cuando termine agosto. |

**Magnitud media de error, 4 meses: 7.22%** (arquitectura anterior con bug 20 corregido:
6.20%). El modelo unificado es ~1pp peor y se adoptó igual — ver la nota de arriba y
`BUGS.md` bug 16 (Fase 4): el parche plano enmascaraba el sesgo de "nuevos" por ser
sistemáticamente generoso, y el criterio de adopción es la fidelidad del universo, no el
error.

## Qué mirar si el error crece

1. ¿El error es de stock o de nuevos? (la tabla ya los separa — en junio casi todo el
   error vino del stock, +16.2%, mientras nuevos acertó casi exacto).
2. ¿Está dentro del rango de volatilidad mensual ya observado en la calibración? (ej. el
   tramo 9-15 del stock osciló 9.8%-18.8% entre meses en los 14 de historia — un +16% de
   error en un mes puntual puede ser varianza normal, no necesariamente un problema).
3. ¿Cambió la mezcla de la cartera? La cartera crece rápido (53k créditos mar-25 → 200k
   jul-26) — si la composición por tramo/avance se movió mucho respecto al histórico
   calibrado, eso solo se ve comparando el enfoque agregado vs. segmentado (ver
   `DECISIONES.md`, "mantener dos enfoques en paralelo").

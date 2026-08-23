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

| Mes | Proyectado | Real | Error total | Error stock | Error nuevos | Error fantasma | Motivo de diferencia (vs. reconciliación bug 14) | Notas |
|---|---:|---:|---:|---:|---:|---:|---|---|
| Mayo 2026 | S/14,053,372 | S/14,697,936 | **-4.4%** | -0.8% | -14.9% | +7.4% | **Signo OPUESTO a junio/julio en el total** — el modelo SUBestima este mes, no sobreestima. "Nuevos" es la fuente principal (-14.9%, mucho mayor que el -5.8%/-5.7% de junio/julio) — pero el signo (real > proyectado en nuevos) es el MISMO que junio y julio: **los 3 meses backtested hasta ahora muestran "nuevos" subestimado**, consistente con el hallazgo de volumen de agosto (ver `analisis_volumen_efectividad_agosto.md`) — puede no ser varianza aleatoria. | Tercer mes cerrado del backtest (tarea 9 de `PENDIENTES.md`), agregado 2026-08-22. Mismas curvas/tasa de producción, sin recalibrar (siguen incluyendo mayo en su propia calibración — ver tarea 10, pendiente aparte). **Corregido el mismo día** (ver bug 17 en `BUGS.md`): el primer cálculo (-7.6%, fantasma -1.5%) usaba el calendario de "nuevos" también para fantasma, sin el ajuste de frontera de mes (cuota vencida 30-abr) — con el calendario correcto, fantasma pasa a +7.4% y el total a -4.4%. Ver `backtest_capital_asegurado_mayo.py` y `enfoque_capital_asegurado_backtest_mayo.sql`. |
| Junio 2026 | S/13,947,775 | S/13,587,829 | **+2.65%** | +7.3% | -5.8% | +12.4% | Fantasma sobreestima (+12.4%) más de lo que nuevos subestima (-5.8%) — la tasa `P_FANTASMA=8.5524%` (calibrada fuera de muestra, ago25-may26) no calza exacto con junio específico. El 31-may no tiene cuotas vencidas, así que nada del error de este mes viene del hueco de frontera de mes en sí — es 100% el efecto de subir la tasa. | Con capa fantasma (tasa recalibrada 8.5524%, fix de frontera de mes) y dedup de bug 11, ambos 2026-08-20. Sin el fix de frontera (tasa 8.4534%): +2.2% (fantasma +11.1%, idéntico en stock/nuevos). Sin fantasma ni dedup: -4.4%. Ver `backtest_capital_asegurado_junio.py` v4. |
| Julio 2026 | S/17,125,792 | S/17,154,500 | **-0.2%** | -1.9% | -12.2% | +15.4% | **Número reconstruido y adoptado 2026-08-22** (reemplaza el +2.17% anterior — ver bug 17 en `BUGS.md`, decisión tomada con el usuario). "Nuevos" subestima (-12.2%) — mismo signo que mayo (-14.9%) y junio (-5.8%), consistente con el hallazgo de volumen de agosto (ver `analisis_volumen_efectividad_agosto.md`). Fantasma sobreestima (+15.4%), mismo mecanismo de dilución por solapamiento que ya explicaba el número anterior (ver nota histórica abajo), solo que recalculado con el calendario correcto. | Reconstrucción completa vía `backtest_capital_asegurado_julio_diario.py` (dedup de bug 11 + calendario de fantasma frontier-adjusted, ambos aplicados de forma consistente día a día — el script anterior de junio tenía el mismo patrón pero no lo necesitaba, ver bug 17). El número viejo (+2.17%, stock -1.0%/nuevos -5.7%/fantasma +13.0%) usaba `jul_calendario.csv`, un archivo huérfano sin construcción documentada que corría 7.9% alto — verificado que NO era por deduplicado (se probó explícitamente, mismo resultado con/sin dedup); causa de fondo del archivo viejo sin confirmar del todo, ver bug 17. Ver `enfoque_capital_asegurado_backtest_mayo.sql` para el patrón de queries (aplicado a julio con fechas ajustadas) y el artifact [📈 Proyectado vs. Real](https://claude.ai/code/artifact/f80d3761-732c-483b-99ad-d85c95c896aa). |
| Agosto 2026 | S/16,410,194 | *(mes en curso, corte 18-ago: S/9,626,322, -2.1% vs. proyectado al mismo día)* | — | — | — | — | — (mes en curso, sin cerrar) | Meta con capa fantasma (tasa recalibrada + fix de frontera 2026-08-20): stock S/2,951,390 + nuevos S/7,269,629 + fantasma S/6,189,175 (incluye 77 créditos/S/140,194 del 31-jul). Ver `meta_agosto_capital_asegurado.py` v3 + `datos_avance_capital_asegurado_agosto/`. Cerrar esta fila cuando termine agosto. |

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

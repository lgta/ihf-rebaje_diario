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

| Mes | Meta proyectada | Real | Error total | Error stock | Error nuevos | Notas |
|---|---:|---:|---:|---:|---:|---|
| Junio 2026 | S/1,806,299 | S/1,713,815 | **+5.4%** | +16.2% | +0.7% | Primer backtest. Curvas calibradas sobre 14 meses (incluyen junio, peso ~1/14 — no es estrictamente fuera de muestra, solo la tasa de entrada lo es). Ver `fase3_backtest.sql`, `backtest_junio.py`. |
| Julio 2026 | S/1,776,174 | S/2,088,911 | **+17.6%** | +2.0% | +22.5% | Cerrado 2026-08-18 (mes completo). El error es notablemente mayor que junio, y va en dirección opuesta al de capital asegurado del mismo mes (abajo) — "nuevos" es la fuente principal (+22.5%), no "stock" como en junio. Un solo mes adicional todavía no alcanza para saber si es varianza normal o degradación — ver tarea 9 de `PENDIENTES.md`. Ver `cierre_julio.sql` (bloques J3/J4). |
| Agosto 2026 | S/2,108,435 | *(mes en curso, corte 18-ago: S/1,147,110, -1.5% vs. proyectado al mismo día)* | — | — | — | Stock S/711,160 + nuevos S/1,397,275. Ver `meta_agosto.py`. Cerrar esta fila cuando termine agosto. |

## Capital asegurado (enfoque alfa) — meta principal desde 2026-07-13

> **Desde 2026-07-13 esta es la meta principal del proyecto** (a pedido explícito del
> usuario), no una métrica complementaria. Sigue sin ser comparable en soles contra la
> tabla de recupero de arriba (mide capital que "activó" pago, no soles recuperados — ver
> `enfoque_capital_asegurado.md`). El recupero se sigue trackeando en paralelo en la tabla
> de arriba.

> **2026-08-20 — capa "fantasma" adoptada (bug 14, ver `BUGS.md` y `reconciliacion_
> vw_seguimiento_temprana.md`):** créditos que pagan una cuota exactamente 1 día tarde y
> que `dayslate` nunca ve (punto ciego de bug 9). Tasa nueva e independiente `P_FANTASMA
> =8.4534%` (no reemplaza ni se mezcla con `13.38%`), activada 100% el día siguiente al
> vencimiento. Las filas de junio/julio de abajo ya están recalculadas con esta capa —
> **al recalcular julio también se corrigió un error de signo** que tenía esta tabla
> (decía "+4.7%/+1.0%/+6.3%", sobreestimando; el número correcto —incluso antes de
> agregar la capa fantasma— es que julio SUBESTIMA, igual que junio, no al revés).

| Mes | Proyectado | Real | Error total | Error stock | Error nuevos | Error fantasma | Notas |
|---|---:|---:|---:|---:|---:|---:|---|
| Junio 2026 | S/13,925,067 | S/13,823,953 | **+0.7%** | +7.2% | -8.6% | +11.1% | Con capa fantasma (2026-08-20). Sin ella: -4.4% (stock +7.2%, nuevos -8.6%, sin fantasma). Ver `backtest_capital_asegurado_junio.py` v3. |
| Julio 2026 | S/16,532,935 | S/16,513,659 | **+0.1%** | -1.0% | -5.7% | +8.4% | Cerrado 2026-08-18, capa fantasma agregada 2026-08-20. Sin ella: **-4.3%** (stock -1.0%, nuevos -5.7%) — signo corregido, antes decía +4.7% por error. Ver `reconciliacion_vw_seguimiento_temprana.md` paso 2/3 e `investigacion_capa_fantasma.sql` Q3/Q4. |
| Agosto 2026 | S/16,351,397 | *(mes en curso, corte 18-ago: S/9,622,765, -1.8% vs. proyectado al mismo día)* | — | — | — | — | Meta con capa fantasma: stock S/2,956,828 + nuevos S/7,288,868 + fantasma S/6,105,701. Antes de la capa fantasma el avance parecía +8.7% adelantado; con la capa completa va -1.8% (ligeramente atrás). Ver `meta_agosto_capital_asegurado.py` v2 + `datos_avance_capital_asegurado_agosto/`. Cerrar esta fila cuando termine agosto. |

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

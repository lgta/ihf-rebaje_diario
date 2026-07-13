# Seguimiento mensual (proyectado vs. real)

Una fila por mes cerrado. El objetivo es detectar si el modelo se degrada con el tiempo —
un solo mes (junio) no alcanza para saber si ±5% es el error típico o una casualidad. Ver
`IDEAS.md` punto 1.

**Cómo agregar un mes:** una vez cerrado, replicar el patrón de `fase3_backtest.sql`
(stock al cierre del mes anterior, calendario real del mes sin filtro `installmentstate`,
recupero real vía `dts_mambu_loans_hist`) ajustando las fechas, y anotar el resultado acá.

| Mes | Meta proyectada | Real | Error total | Error stock | Error nuevos | Notas |
|---|---:|---:|---:|---:|---:|---|
| Junio 2026 | S/1,806,299 | S/1,713,815 | **+5.4%** | +16.2% | +0.7% | Primer backtest. Curvas calibradas sobre 14 meses (incluyen junio, peso ~1/14 — no es estrictamente fuera de muestra, solo la tasa de entrada lo es). Ver `fase3_backtest.sql`, `backtest_junio.py`. |
| Julio 2026 | S/1,776,174 | *(mes en curso, corte 9-jul: S/527,375)* | — | — | — | Meta oficial vigente, ver `ESTADO.md`. Cerrar esta fila cuando termine julio. |

## Capital asegurado (enfoque alfa, complementario — no reemplaza el recupero)

Métrica distinta, no comparable en soles contra la tabla de arriba (mide capital que
"activó" pago, no soles recuperados — ver `enfoque_capital_asegurado.md`). Misma
mecánica de seguimiento: proyectado vs. real por mes cerrado.

| Mes | Proyectado | Real | Error total | Error stock | Error nuevos | Notas |
|---|---:|---:|---:|---:|---:|---|
| Junio 2026 | S/8,771,300 | S/9,202,188 | **-4.7%** | +5.6% | -8.4% | Primer backtest, 2026-07-13. Reutiliza población/calendario de `datos_backtest_junio/` y curvas de `datos_capital_asegurado/`. Ver `enfoque_capital_asegurado.md`, `backtest_capital_asegurado_junio.py`. |

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

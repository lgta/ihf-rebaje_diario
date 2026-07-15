# Enfoque oficial: acumulado

> **Estado: oficial, validado.** Es la meta que se reporta. Backtest sobre junio 2026
> (mes real cerrado): +5.4% de error. Este archivo es un resumen corto — la explicación
> completa con SQL replicable está en `guia_tecnica_recupero.md`.

## El concepto

Stock (créditos con mora 1-30 al cierre del mes anterior) + nuevos (créditos que caen en
mora durante el mes) proyectados con el modelo evento × magnitud:
`Recupero esperado = P(paga) × E(% del saldo que rebaja al pagar)`.

El stock se ancla al cierre real del mes anterior (no al día de la consulta) — clasifica
tramo y saldo UNA sola vez, al momento de asignación, y nunca vuelve a re-filtrar por la
mora del día corriente. Por eso no sufre el bug de "aged-out survivors" que sí afectaba al
enfoque "reinicio del reloj" (descontinuado 2026-07-15, ver `DECISIONES.md`).

## Por qué es el oficial

- Es el único enfoque con backtest contra un mes real y cerrado (junio 2026): **+5.4%** de
  error (stock +16.2%, nuevos +0.7%).
- Metodológicamente más simple y robusto: una sola clasificación por crédito al mes,
  sin necesidad de parches para créditos que cruzan límites de tramo a mitad de mes.
- El usuario confirmó explícitamente (2026-07-10) que la meta que le interesa es siempre
  la del mes completo, anclada al cierre — no una recalculada desde "hoy".

## Resultado vigente

Ver `ESTADO.md` para la cifra actualizada del mes en curso. Julio 2026 (corte 9-jul):
meta total S/1,776,174 (stock S/426,651 + nuevos S/1,349,523); real a la fecha S/527,375;
resta S/1,248,799.

## SQL explicado

El detalle completo con SQL copiable está en `guia_tecnica_recupero.md` §3. Resumen de
las 4 piezas:

**1. Stock (`fase1_stock.sql`)** — toma la ÚLTIMA foto de cada crédito dentro del mes
anterior (`row_number() over (partition by id_loan, periodo order by fechaproceso desc)`,
se queda con `rn=1`), filtra `mora between 1 and 30`, y clasifica tramo/avance con esa
misma foto. Luego, para cada día del mes siguiente, cruza ese stock contra las fotos
diarias y suma el rebaje (`saldo_ayer - saldo_hoy`, solo si es positivo) acumulado por
`tramo` — eso da la curva `% recuperado acumulado por tramo × día`.

**2. Nuevos (`fase2_nuevos.sql`)** — detecta "entradas" con la transición
`mora_ant = 0 and mora = 1` (usando `lag(mora) over (partition by id_loan order by
fechaproceso)`), calcula el avance en ese momento, y sigue el rebaje día a día durante
31 días desde la entrada — da la curva `% recuperado acumulado por avance × días desde
entrada`.

**3. Calendario (`fase3_meta.sql` / `meta_julio.py`)** — trae, para cada
`fechavencimiento` del mes, el saldo capital de los créditos con cuota venciendo ese día
(`dts_cobranza_creditos_cuotas` join `dts_okaapi_loans`), segmentado por avance. Ese es
el "saldo en riesgo" — se multiplica por `13.38%` (la tasa de entrada, calibrada en
`fase3_backtest.sql` bloque 3H) para obtener el saldo que efectivamente entra en mora ese
día, y luego se le aplica la curva de nuevos según los días que le quedan hasta el cierre.

**4. Combinación (`meta_julio.py`)** — para cada día `d` del mes: `stock(d) =
Σ saldo_stock(tramo,avance) × curva_stock(tramo,avance,d)`; `nuevos(d) = Σ(D≤d)
saldo_riesgo(D,avance) × 13.38% × curva_nuevos(avance, d−D)`; la meta es `stock(d) +
nuevos(d)`.

## Archivos

- `meta_julio.py` + `datos_meta_julio/` — script de proyección del mes en curso.
- `backtest_junio.py` + `datos_backtest_junio/` — validación contra junio real.
- `fase1_stock.sql`, `fase2_nuevos.sql`, `fase3_meta.sql`, `fase3_backtest.sql` — motores
  y calibración completos.
- `guia_tecnica_recupero.md` — explicación completa con SQL replicable (el documento de
  referencia técnica externa).
- `meta_recupero_detalle.html` — artifact con curvas interactivas y el detalle completo
  del cálculo (composición de stock, calendario de nuevos, cohortes, trayectoria).

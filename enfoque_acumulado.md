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
mora del día corriente. Por eso no sufre el bug de "aged-out survivors" que sí afecta al
`enfoque_reinicio_reloj.md`.

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

## Archivos

- `meta_julio.py` + `datos_meta_julio/` — script de proyección del mes en curso.
- `backtest_junio.py` + `datos_backtest_junio/` — validación contra junio real.
- `fase1_stock.sql`, `fase2_nuevos.sql`, `fase3_meta.sql`, `fase3_backtest.sql` — motores
  y calibración completos.
- `guia_tecnica_recupero.md` — explicación completa con SQL replicable (el documento de
  referencia técnica externa).
- `meta_recupero_detalle.html` — artifact con curvas interactivas y el detalle completo
  del cálculo (composición de stock, calendario de nuevos, cohortes, trayectoria).

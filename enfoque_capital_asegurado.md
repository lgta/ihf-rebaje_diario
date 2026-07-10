# Enfoque alfa: capital asegurado

> **Estado: experimental, sin backtest todavía.** No es la meta oficial (esa sigue siendo
> `meta_julio.py`, ver `ESTADO.md`). Es una métrica complementaria, propuesta por el
> usuario el 2026-07-10. Antes de usarla para reportar hacia el negocio, correrle el mismo
> tratamiento que al modelo oficial: backtest contra un mes real cerrado (ver pendientes
> al final de este archivo).

## El concepto

No mide cuántos soles se recuperan (eso lo hace el rebaje / la meta oficial). Mide
**cuánto del capital asignado pertenece a créditos que muestran actividad de pago —
así sea mínima— durante el mes**, ponderado por el saldo COMPLETO del crédito, no por lo
que efectivamente pagó.

Ejemplo original del usuario:

| Crédito | Saldo capital | Pago del mes | Aporta a "rebaje" | Aporta a "capital asegurado" |
|---|---:|---:|---:|---:|
| A | S/12,000 | S/50 | S/50 | **S/12,000** (el saldo completo, porque activó) |
| B | S/8,000 | S/0 | S/0 | S/0 (no activó, aunque su saldo sea grande) |

Un crédito "activa" su saldo completo con solo mostrar 1 día de pago; uno que no paga
nada no aporta nada, sin importar cuán grande sea su saldo.

## Por qué es una métrica distinta, no un reemplazo

Un mes puede tener bajo recupero en soles pero alto capital asegurado (muchos créditos
empezando a pagar poco a poco) — eso es una señal de **actividad temprana / contacto
efectivo**, distinta de "nadie está pagando". Sirve como complemento, no sustituto, de la
meta de recupero.

## Metodología

Mismo mecanismo de combinación que el modelo oficial (ver `guia_tecnica_recupero.md`
§4.1), pero reemplazando la curva de "% recuperado" por una curva de "% del saldo con
≥1 día de pago", acumulada de la misma forma:

```
CapitalAsegurado_stock(d)  = Σ(tramo,avance) saldo_stock(tramo,avance) × curva_asegurado_stock(tramo,avance,d)

CapitalAsegurado_nuevos(d) = Σ(D≤d) Σ(avance) saldo_riesgo(D,avance) × P(no paga a tiempo) × curva_asegurado_nuevos(avance, d−D)
```

**La tasa `P(no paga a tiempo)=13.38%` es la misma que usa el modelo oficial**, y sigue
siendo válida acá porque `curva_asegurado_nuevos` se calibró sobre la MISMA definición de
"entrada" (`dayslate` 0→1) que `curva_nuevos` — ver `feedback-tasa-curva-consistente` en
memoria y `DECISIONES.md`. Si en algún momento se cambia cómo se define "entrada" para
esta curva, hay que recalibrar la tasa junto con ella, no una sin la otra.

Queries: `enfoque_capital_asegurado.sql` (Q1 stock, Q2 nuevos). Script de proyección:
`meta_julio_capital_asegurado.py`. Datos cacheados: `datos_capital_asegurado/`.

## Resultados (calibración 14 meses, mar-2025 a jun-2026)

### Stock — % de saldo asegurado al día 31, por tramo × avance

| Tramo | avance <10% | avance 10-40% | avance 40-70% | avance 70%+ |
|---|---:|---:|---:|---:|
| 1-8 | 69.7% | 81.1% | 85.5% | 90.3% |
| 9-15 | 41.2% | 58.6% | 64.6% | 74.6% |
| 16-30 | 22.6% | 40.6% | 52.0% | 56.3% |

**Hallazgo:** a diferencia de la curva de recupero (donde avance predice severidad y
tramo predice frecuencia, casi independientes), acá el avance también empuja la
*activación* dentro de un mismo tramo — no es solo que pague más, es que tiene más
probabilidad de pagar algo.

### Nuevos — % de saldo asegurado al día 31, por avance

| avance <10% | avance 10-40% | avance 40-70% | avance 70%+ |
|---:|---:|---:|---:|
| 82.0% | 89.0% | 91.8% | 93.1% |

Mucho más alto que el stock en todos los segmentos — la mora recién entrada activa
muchísimo más que la mora crónica (consistente con la frecuencia ya conocida: 83%/58%/39%
por tramo en el motor de stock).

## Proyección de julio 2026 (corte 30-jun, mismo stock que la meta oficial)

| | Stock | Nuevos | Total |
|---|---:|---:|---:|
| Capital asegurado proyectado (31-jul) | S/1,725,470 | S/7,194,140 | **S/8,919,611** |

58.6% del stock inicial (S/2,943,958) queda "asegurado" para fin de mes. El total
(S/8.9M) supera varias veces la meta de recupero oficial (S/1,776,174) — esperable, ya
que "mostrar 1 pago" es un umbral mucho más bajo que "recuperar todo el saldo".

Artifact publicado: [🔒 Capital asegurado — julio 2026](https://claude.ai/code/artifact/3a6b8cb9-0b2a-4dac-9569-473327a84b0a)
(`capital_asegurado.html`) — curvas interactivas + trayectoria de julio.

## Pendientes de este enfoque

1. **Backtest contra un mes real cerrado** (junio 2026, mismo patrón que
   `fase3_backtest.sql`) — todavía no se hizo. Sin esto, no se sabe si la proyección de
   julio (S/8.9M) es razonable o está sesgada.
2. Decidir si tiene sentido reportar esto hacia el negocio como KPI regular, o si es solo
   una lente analítica interna.
3. Si se adopta, sumarlo a `SEGUIMIENTO.md` como columna adicional (capital asegurado
   proyectado vs. real), igual que se hace con el recupero.

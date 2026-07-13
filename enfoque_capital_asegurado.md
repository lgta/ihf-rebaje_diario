# Enfoque alfa: capital asegurado

> **Estado: backtest superado (-4.7% de error, junio 2026).** No es la meta oficial (esa
> sigue siendo `meta_julio.py`, ver `ESTADO.md`). Es una métrica complementaria, propuesta
> por el usuario el 2026-07-10. Ya se le corrió el mismo tratamiento que al modelo
> oficial: backtest contra un mes real cerrado (ver sección "Backtest" más abajo). Un solo
> mes no basta para confirmar el error típico (mismo caveat que el modelo oficial, ver
> `IDEAS.md` punto 1) — pero el resultado da confianza para reportarlo como métrica
> complementaria regular.

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

## SQL explicado

Ambas queries parten de las mismas CTEs base que `fase1_stock.sql`/`fase2_nuevos.sql`
(`loan_chain`, `fotos`, exclusión de reenganches) — lo único que cambia es qué se
acumula al final.

**Q1 — stock.** Después de armar `stock` (igual que el enfoque oficial: última foto del
mes anterior, `mora between 1 and 30`), se cruza contra las fotos del mes con un flag
binario por día: `case when saldo_ant > saldo then 1 else 0 end as pago_flag` (no importa
CUÁNTO bajó, solo si bajó). Luego `primer_pago` toma, por crédito, el `min(dia)` entre los
días con `pago_flag=1` — el día en que ese crédito "se activa" por primera vez en el mes.
`activado_por_dia` suma el `saldo_inicial` COMPLETO (no el rebaje) de los créditos cuyo
primer pago cayó en cada día. La curva final es un acumulado (`sum(...) over (partition by
tramo, avance_band order by dia)`) de esos saldos, dividido entre el saldo total del
segmento — el mismo patrón de curva acumulada que las demás, pero acumulando "saldo de
créditos ya activados" en vez de "soles rebajados".

**Q2 — nuevos.** Misma lógica de detección de entradas que `fase2_nuevos.sql`
(`mora_ant=0 and mora=1`), y el mismo truco de `primer_pago`/`activado_por_dia`, pero
anclado a `dia_desde_entrada` (no al día calendario) y usando `saldo_entrada` (el saldo al
momento de entrar en mora) como base para acumular.

**La diferencia clave con las curvas de recupero** (`curva_stock`/`curva_nuevos`): ahí se
acumula `sum(rebaje)` — soles efectivamente pagados. Acá se acumula `sum(saldo_inicial)`
de los créditos activados — el saldo COMPLETO, una sola vez, el día que ese crédito paga
por primera vez. Es la diferencia entre "cuánto se cobró" y "cuánto capital ya mostró
señales de vida".

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

## Backtest (junio 2026)

Ejecutado 2026-07-13, mismo mes que el backtest oficial de recupero (para comparar
manzanas con manzanas). Mismo patrón que `fase3_backtest.sql`: stock al cierre de mayo,
calendario real de junio sin filtro `installmentstate`, capital asegurado real vía
`dts_mambu_loans_hist` (mismo criterio `pago_flag`/`primer_pago` que
`enfoque_capital_asegurado.sql`). Reutiliza la población (stock/calendario) ya cacheada en
`datos_backtest_junio/` y las curvas ya calibradas en `datos_capital_asegurado/` — lo único
nuevo son los CSV de activación real (`bt_real_aseg_stock.csv`, `bt_real_aseg_nuevos.csv`).
Script: `backtest_capital_asegurado_junio.py`.

| | Proyectado | Real | Error |
|---|---:|---:|---:|
| Total | S/8,771,300 | S/9,202,188 | **-4.7%** |
| Stock | S/2,573,309 | S/2,436,810 | +5.6% |
| Nuevos | S/6,197,991 | S/6,765,378 | -8.4% |

**El error total (-4.7%) es del mismo orden de magnitud que el backtest del modelo oficial
de recupero (+5.4%)** — buena señal de que la curva de capital asegurado no está sesgada
de forma grosera, aunque va en la dirección opuesta (oficial sobreestima, este subestima) y
el desglose stock/nuevos también se invierte (acá el stock sobreestima y nuevos
subestima, al revés que en recupero). No se tocó la tasa `P(no paga a tiempo)=13.38%` ni la
curva por separado — el error no es lo bastante grande como para justificarlo, y el
principio de modelado de `CLAUDE.md` aplica igual acá.

## Pendientes de este enfoque

1. ~~Backtest contra un mes real cerrado~~ — hecho 2026-07-13, ver arriba. Al igual que el
   modelo oficial, sigue siendo un solo mes de dato (`IDEAS.md` punto 1) — extenderlo a
   3-6 meses más antes de tratar -4.7% como error típico.
2. **Decisión: sí, pasa a reportarse como métrica complementaria regular** (no reemplaza
   recupero, que sigue siendo la meta oficial). El backtest da confianza suficiente. Ya
   sumado a `SEGUIMIENTO.md` como columna adicional.

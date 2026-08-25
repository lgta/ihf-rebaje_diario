# Enfoque alfa: capital asegurado

> **Estado: meta principal desde 2026-07-13, a pedido explícito del usuario.** Backtest en
> 2 meses cerrados (junio +2.65%, julio +2.17%, ambos con la "capa fantasma" completa —
> tasa recalibrada + fix de frontera de mes, adoptada 2026-08-20 — ver sección "Capa
> fantasma" abajo y bug 14 en `BUGS.md`) **y con el dedup de bug 11 aplicado (2026-08-20,
> ver `BUGS.md`)**. El recupero oficial (`meta_julio.py`) se sigue calculando y trackeando
> en paralelo, pero ya no es el número que lidera `ESTADO.md`. Propuesta original por el
> usuario el 2026-07-10. Solo 2 meses de backtest — seguir extendiendo antes de tratar
> ±2-3% como error típico (`IDEAS.md` punto 1).

## Capa "fantasma" (adoptada 2026-08-20, bug 14)

Un crédito que paga una cuota **exactamente 1 día tarde** nunca hace que `dayslate`
muestre mora — la foto nocturna ya ve el pago (bug 9). Esto quedó invisible tanto para la
curva de "nuevos" (no tenía bucket día-0) como para la tasa `P(no paga a tiempo)=13.38%`
(también mide transiciones `dayslate`, ciega al mismo fenómeno). Al reconciliar contra una
vista externa oficial se cuantificó en **~27% de toda la población real de mora 1-30/
TEMPRANA** — no es un caso de borde (ver `reconciliacion_vw_seguimiento_temprana.md`).

Se agregó una capa **independiente** (no reemplaza ni mezcla `13.38%` ni la curva de Q2 —
evita repetir bug 10): detecta la entrada en mora no vista por `dayslate`, y se activa
**100% del saldo el día siguiente al vencimiento** (sin curva propia — por definición, si
se detecta el evento es porque ya se pagó; confirmado vigente incluso con la definición
ampliada de tarea 17, ver nota abajo). Tasa vigente `P_FANTASMA=8.6163%` (348,605/30,037,
recalibrada 2026-08-25 con `dias_atraso_cuota` — ver `tarea17_fase3_curva_fantasma.sql` y
bug 16 en `BUGS.md`; antes 8.5524%, calibrada con `dias_vencimiento_a_pago=1` sobre
`enfoque_capital_asegurado.sql` Q3, que queda como referencia histórica). Por mes: ~7-10%,
casi tan grande como el propio `13.38%`.

**Actualización 2026-08-25 (tarea 17 fase 3):** la definición de "fantasma" se amplió de
"paga exactamente 1 día tarde" a "cualquier entrada que `dias_atraso_cuota` detecta y
`dayslate` no ve" — mecanismo más amplio, incluye el hueco de fin de semana (`BUGS.md` bug
16). Se confirmó con datos que la activación instantánea sigue siendo correcta bajo esta
definición ampliada (99.6% ponderado en el día 0, verificado en 2 ventanas de calibración) —
no hizo falta reemplazar la arquitectura de tasa plana por una curva multi-día, solo
actualizar la constante.

**Fix de frontera de mes (2026-08-20, mismo día):** la verificación a nivel crédito
encontró que la capa fantasma original (basada en `fechavencimiento` directo) solo cubría
90.7% del bucket de bug 9 — una cuota vencida el ÚLTIMO DÍA de un mes, pagada 1 día tarde,
"ocurre" el mes siguiente, análogo a bug 12. Fix: el "periodo" de cada cuota se determina
por `fecha_pago` (`fechavencimiento+1`), no por `fechavencimiento` directo — cierra la
cobertura a 99.7%. Como tasa y calendario deben compartir la misma definición (principio de
`CLAUDE.md`), `P_FANTASMA` se recalibró junto con el fix (antes 8.4534%, sobre
353,054/29,845). Backtest re-corrido con la tasa consistente: junio +2.2%→+2.65%, julio
+0.12%→+2.17% — ambos siguen siendo buenos números. Ver bug 14 en `BUGS.md` para el
detalle completo, incluyendo el hallazgo de que aplicar el fix de frontera SIN recalibrar
la tasa (calendario nuevo + tasa vieja) es una inconsistencia del tipo que bug 10 prohíbe.

**Alcance:** solo este enfoque (Enfoque alfa) — el recupero oficial (`fase1_stock.sql`/
`fase2_nuevos.sql`/`fase3_backtest.sql`) no se tocó, decisión explícita con el usuario.

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
siendo válida acá porque mide si la entrada a mora ocurre (`dayslate` 0→1) a nivel crédito,
no en qué día del mes cae — el bucketing stock/nuevos (bug 12, ver `BUGS.md`) no cambia esa
tasa. `curva_asegurado_nuevos` YA NO usa exactamente la misma población que `curva_nuevos`
del recupero oficial: excluye las entradas del día 1 del mes (que pasan a `curva_asegurado_
stock`), mientras que `curva_nuevos` (recupero) todavía no tiene ese ajuste — ver
`feedback-tasa-curva-consistente` en memoria y `DECISIONES.md`. Si en algún momento se
cambia de nuevo cómo se define "entrada" para esta curva, hay que recalibrar la tasa junto
con ella, no una sin la otra.

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

**Recalibrado 2026-07-14 (bug 12, ver `BUGS.md`):** la definición de antiguos/nuevos se
corrigió — un crédito que entra en mora (`dayslate` 0→1) el día 1 del mes es antiguo (su
cuota venció el último día del mes anterior), no nuevo. Ya no reutiliza
`bt_stock_junio.csv` (compartido con el backtest oficial de recupero, que ancla solo al
cierre de mayo) — usa `bt_stock_junio_aseg.csv`, propio de este enfoque
(`enfoque_capital_asegurado_backtest.sql` BT-ASEG-0).

| | Proyectado | Real | Error |
|---|---:|---:|---:|
| Total (sin fantasma) | S/8,781,121 | S/8,989,398 | -2.3% |
| Stock | S/2,590,436 | S/2,414,649 | +7.3% |
| Nuevos | S/6,190,685 | S/6,574,749 | -5.8% |
| **Fantasma (2026-08-20, tasa recalibrada + fix de frontera)** | S/5,166,655 | S/4,598,430 | +12.4% |
| **Total con capa fantasma** | **S/13,947,775** | **S/13,587,829** | **+2.65%** |

(Antes de la corrección de bug 12: -4.7% total, stock +5.6%, nuevos -8.4% — esa corrección
dejó el error total prácticamente igual. La capa fantasma, 2026-08-20, movió el error de
-4.4% a +0.7%. **El mismo día, el dedup de bug 11 (`BUGS.md`) se aplicó a este backtest
— el error subió de +0.7% a +2.2%** (stock +7.2%→+7.3%, fantasma +11.1% sin cambio,
nuevos -8.6%→-5.8% — el componente que más se movió, porque el fix elimina "pagos"
espurios detectados al comparar contra una fila duplicada en S/0 de un reenganche).
**Más tarde el mismo día, el fix de frontera de mes + la tasa `P_FANTASMA` recalibrada
(8.4534%→8.5524%) subieron el error de +2.2% a +2.65%** (fantasma +11.1%→+12.4%, stock/
nuevos sin cambio — el 31-may no tiene cuotas vencidas). Julio (segundo mes cerrado) no se
movió con el dedup de bug 11, pero sí con el fix de frontera+tasa (+0.12%→+2.17%) — ver
tabla de `SEGUIMIENTO.md` y bug 14 en `BUGS.md`. La tasa `P(no paga a tiempo)=13.38%` no se
tocó — sigue midiendo si la entrada a mora ocurre vía `dayslate`; `P_FANTASMA` es una tasa
nueva e independiente, recalibrada solo sobre su propia definición (nunca mezclada con
13.38%).

**El error total final (+2.65% junio, +2.17% julio) sigue siendo del mismo orden de
magnitud que el backtest del modelo oficial de recupero (+5.4%)** — buena señal de que la
curva de capital asegurado no está sesgada de forma grosera. No se tocó la tasa
`P(no paga a tiempo)=13.38%` ni la curva de nuevos/stock — el error no es lo bastante
grande como para justificar tocarlas, y el principio de modelado de `CLAUDE.md` aplica
igual acá.

## Tracking en vivo — julio 2026 (meta principal)

Igual mecanismo que `meta_julio.py` para el recupero oficial (stock anclado al cierre
real de junio + calendario de julio × P(no paga)=13.38%), pero con las curvas de capital
asegurado. Script: `avance_capital_asegurado_julio.py`. Datos reales generados con el
mismo patrón que el backtest de junio (`jul_aseg_real_stock.csv`/`jul_aseg_real_nuevos.csv`
en `datos_avance_capital_asegurado_julio/`, adaptando fechas a julio).

| | Proyectado (mes completo) | Real al 13-jul | Proyectado al mismo día (13) |
|---|---:|---:|---:|
| Total | S/8,919,611 | S/4,969,508 | S/3,634,008 |
| Stock | S/1,725,470 | S/1,311,107 | — |
| Nuevos | S/7,194,140 | S/3,658,402 | — |

**Avance real: 55.7% de la meta del mes, +36.8% por encima de lo proyectado para el mismo
día.** Lectura de un solo mes a mitad de camino (día 13 de 31) — el backtest de junio (mes
completo, cerrado) dio -4.7%, así que este +36.8% de adelanto a mitad de mes no debe
tratarse como una revisión del backtest: puede diluirse o revertirse antes del cierre.
Seguir el avance semana a semana; no ajustar tasa ni curva sin repetir el backtest
(principio de modelado, `CLAUDE.md`).

**Nota de refresco intradía (13-jul):** el real del día 13 subió de S/4,800,372 a
S/4,969,508 al re-consultar horas después (stock 1,303,515→1,311,107, nuevos
3,496,857→3,658,402) — `dts_mambu_loans_hist` sigue recibiendo fotos del día en curso, así
que "hoy" es el único día que puede moverse en una corrida posterior; los días ya cerrados
no cambiaron (verificado). Ver el desglose día a día completo (asignación de nuevos +
activación de nuevos/antiguos, desde el 1-jul) en `avance_capital_asegurado_julio_diario.sql`
y `datos_avance_capital_asegurado_julio/tabla_diaria_alfa.csv`.

## Pendientes de este enfoque

1. ~~Backtest contra un mes real cerrado~~ — hecho 2026-07-13, ver arriba. Al igual que el
   modelo oficial, sigue siendo un solo mes de dato (`IDEAS.md` punto 1) — extenderlo a
   3-6 meses más antes de tratar -4.7% como error típico.
2. ~~Decidir si pasa a reportarse como KPI~~ — **promovido a meta principal el
   2026-07-13** (a pedido explícito del usuario), reemplazando al recupero como el número
   que lidera `ESTADO.md`. El recupero oficial se sigue calculando y trackeando en
   paralelo, no se descontinuó.
3. ~~Cerrar la fila de julio en `SEGUIMIENTO.md`~~ — hecho 2026-08-18, y recalculada con
   la capa fantasma + signo corregido el 2026-08-20 (ver arriba).
4. Cerrar la fila de agosto en `SEGUIMIENTO.md` cuando termine el mes — meta vigente
   S/16,410,194 (con capa fantasma completa: tasa recalibrada + fix de frontera de mes),
   ver `ESTADO.md`.
5. Extender el backtest a 3-6 meses más (junio/julio son los únicos 2 disponibles) antes
   de tratar ±2-3% como error típico con la capa fantasma.

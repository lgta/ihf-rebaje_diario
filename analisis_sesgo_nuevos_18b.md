# Tarea 18b — por qué "nuevos" subestima en los 7 meses, y por qué febrero también rompe stock

**Ejecutado 2026-08-26**, sesión de continuación del handoff. Sin Athena: todo sale de los CSV
que ya produjo el walk-forward de 18a/18f (`datos_tarea18a/`) y de la matriz cruda
(`curva_cruda.csv`). Script reproducible: `analisis_sesgo_nuevos_18b.py`. **Diagnóstico, no
ajuste** — no se tocó `P_ENTRADA` ni ninguna curva de producción (`CLAUDE.md`, "El error se
explica, no se optimiza").

## Punto de partida

| Mes | error total | err. stock | err. nuevos |
|---|---:|---:|---:|
| Ene | -11.2% | -1.5% | -13.4% |
| Feb | -19.6% | **-11.0%** | -21.6% |
| Mar | -14.1% | +4.7% | -16.1% |
| Abr | -11.9% | +5.3% | -15.5% |
| May | -10.9% | -1.3% | -12.3% |
| Jun | -3.2% | +3.1% | -4.7% |
| Jul | -3.0% | -4.5% | -2.8% |

Dos preguntas del handoff: **(1)** qué explica que "nuevos" subestime en los 7 meses sin
excepción, y **(2)** por qué febrero es el único mes donde **stock también** falla fuerte.
Son dos mecanismos distintos — cada uno se resuelve por separado.

## 1. "Nuevos": el ~78% de la magnitud del error es un mismatch de unidad, no de forma

**Hallazgo: `P_ENTRADA` (21.9918%) se calibró contando CRÉDITOS, pero se aplica en producción
multiplicando SALDO EN SOLES.** `tarea17_fase4_tasa.sql` lo dice en su propio comentario
("Salida en creditos (no soles) — misma unidad que P_NO_PAGA_DIA0") y su SELECT lo confirma:
`count(*)` sobre `calendario_mes` (créditos elegibles) y `sum(case when ... then 1 else 0)`
(créditos que entran) — `75,621 / 343,860` son conteos, no soles. Ese número se importa tal
cual a `motor_unificado.py` y `proyectar()` lo multiplica contra `saldo` (soles) del
calendario: `acum_nuevos += saldo * p_entrada * pct / 100.0 * fac`. Lo mismo corre en
producción (`meta_agosto_capital_asegurado.py`, misma constante, mismo calendario en soles).

**Por qué eso genera sesgo de signo constante:** ya está medido (`analisis_volumen_
efectividad_agosto.md`) que el exceso de entrada a mora de agosto está concentrado en
créditos de saldo más alto, no en más créditos — la tasa por conteo (14.52% real vs. 13.38%
modelado, +8.5%) es mucho más chica que la tasa en soles (+26.3%). Una tasa calibrada por
conteo estructuralmente subestima la tasa en soles **siempre que el saldo correlacione con
la probabilidad de entrar en mora** — no hace falta que la tasa "derive" mes a mes (y no
deriva: `BUGS.md` línea 1069, rango 20.39%-23.82% **por conteo**, sin tendencia) para que el
gap persista, porque el gap no es temporal, es de definición.

**Medición mes a mes (tasa real ponderada por soles, misma matriz cruda que arma la curva de
producción):**

| Mes | tasa real (soles) | vs. P_ENTRADA fijo (21.99%) | err. nuevos (fijo) | err. nuevos (con tasa real del mes) | % de la magnitud explicada |
|---|---:|---:|---:|---:|---:|
| Ene | 26.20% | +19.1% | -13.4% | +3.2% | 76.4% |
| Feb | 27.06% | +23.1% | -21.6% | -3.5% | 83.6% |
| Mar | 27.22% | +23.8% | -16.1% | +3.8% | 76.1% |
| Abr | 26.81% | +21.9% | -15.5% | +3.0% | 81.0% |
| May | 25.95% | +18.0% | -12.3% | +3.5% | 71.3% |
| Jun | 24.34% | +10.7% | -4.7% | +5.5% | (magnitud sube — ver nota) |
| Jul | — | — | -2.8% | — | sin datos (matriz cruda cubre entradas hasta 20260630) |

**La tasa real en soles corre 19%-24% por encima de la fija en los 6 meses medibles, sin
excepción.** Sustituyendo únicamente `P_ENTRADA` por la tasa real de cada mes (dejando la
curva y todo lo demás intacto) la magnitud del error de "nuevos" cae **~78% en promedio en 5
de los 6 meses** (71%-84%), de errores de dos dígitos a residuos de ±3-6%. Correlación entre
el error con la tasa fija y el nivel de la tasa real del mes: **r = -0.93** — el mes con mayor
exceso de tasa (marzo, +23.8%) es también uno de los de mayor error, y el de menor exceso
(junio, +10.7%) es el de menor error. **Junio es la excepción:** ahí la tasa fija ya daba un
error chico (-4.7%) y usar la tasa real lo sobrepasa hacia el otro signo (+5.5%) — señal de
que el residuo no explicado por la tasa (la forma de la curva, ver más abajo) también importa,
solo que en junio pesa proporcionalmente más al ser el mes con menor exceso de tasa.

**Esto no contradice "P_ENTRADA sin deriva mensual" de `BUGS.md`/tarea 17 Fase 4 — mide otra
cosa.** Esa medición (rango 20.39%-23.82%) es por **conteo de créditos**, la métrica correcta
para comparar contra `P_NO_PAGA_DIA0` (que también era por conteo). La tasa que importa para
el modelo de capital asegurado — que multiplica soles, no créditos — es la ponderada por
saldo, y esa es la que corre sistemáticamente 19-24 puntos porcentuales por encima. Las dos
mediciones son coherentes entre sí y con el hallazgo de agosto: **no es que entren más
créditos en mora de lo histórico, es que los que entran pesan más en soles** — mismo mecanismo,
ahora confirmado en los 6 meses del backtest con la definición unificada (`dias_atraso_cuota`,
no solo con la arquitectura vieja de agosto).

**Lo que esto NO es:** un llamado a cambiar `P_ENTRADA` a la tasa en soles. Eso sería exactamente
el error que el bug 10 ya enseñó — cambiar una constante sin verificar que la curva a la que se
aplica esté calibrada consistentemente con la nueva definición, y sin correr el backtest
completo con el cambio (`CLAUDE.md`, "Principio de modelado"). Es una hipótesis fuerte y
cuantificada sobre el mecanismo, pendiente de que el usuario decida si amerita ese trabajo.

## 2. Febrero: el 79% del gap de stock vive en un solo día — el último

**Hallazgo: el 28 de febrero, solo, explica el 79.3% del gap de stock del mes entero.** Ningún
otro mes tiene una concentración remotamente parecida en su último día (los demás van de -95%
a +55%, con signos mixtos — ruido normal repartido en el mes). Febrero es además, por lejos, el
mes con el gap de stock más grande en soles (S/244,299, contra un rango de -124,550 a +89,333
en el resto).

**Mecanismo: el modelo indexa el "fin de mes" por NÚMERO DE DÍA CALENDARIO (30/31), no por
proximidad real al cierre.** El factor `f` de 18f define el grupo "fin de mes" como los días
30 y 31 exactos (`GRUPOS_DIA_MES` en `motor_unificado.py`); la curva de stock, indexada por día
del mes 1-31, aprende su propio nivel para el día 28 mezclando observaciones de TODOS los meses
de su ventana de calibración, la mayoría de 30-31 días — para esos meses el día 28 genuinamente
no es fin de mes (todavía faltan 2-3 días de repunte de cobranza por pago de planilla). Para
febrero, el día 28 **es** el cierre real del mes, pero el modelo no tiene forma de distinguir
eso: nunca le aplica el nivel elevado que sí les da a los días 30/31 de los demás meses.

**La evidencia día a día muestra la misma rampa que en los meses largos, corrida 2-3 días
antes** (ratio real/proyectado del incremento diario de stock):

| Mes | ... | 3 días antes del cierre | 2 días antes | 1 día antes | **día de cierre** |
|---|---|---:|---:|---:|---:|
| Enero (31d) | | d28: 0.60 | d29: 1.15 | d30: 2.20 | **d31: 3.56** |
| **Febrero (28d)** | | **d25: 0.99** | **d26: 0.71** | **d27: 1.73** | **d28: 3.45** |
| Julio (31d) | | d28: 0.19 | d29: 0.18 | d30: 0.69 | **d31: 2.44** |

Enero y febrero muestran la rampa más limpia de los 7 meses (3 días de aceleración terminando
en un ratio >3 el día de cierre) — la MISMA forma, apenas desplazada porque el mes es más
corto. Marzo/abril/junio tienen un patrón de cierre más ruidoso (posiblemente por el propio
factor de quincena/fin de mes ya parcialmente capturado en esos meses vía calibración), pero
ninguno concentra el gap total en un solo día como febrero.

**Por qué esto no afecta a los demás meses con la misma fuerza:** los meses de 30 días (abril,
junio) sí alcanzan el día 30 y reciben *parte* del boost de "fin de mes"; los de 31 días
(enero, marzo, mayo, julio) lo reciben completo (30 y 31). Solo febrero, al no tener ni día 29
ni 30 ni 31, se queda estructuralmente afuera del grupo "fin de mes" — su verdadero cierre cae
siempre en un día que el modelo trata como "resto" (factor 0.9812, **por debajo** del promedio,
no por encima).

**Nota importante:** el factor `f` de 18f solo se aplica a la curva de NUEVOS (`proyectar()`
lo multiplica contra `acum_nuevos`, no contra `proy_stock`) — el mecanismo en stock es el mismo
en espíritu (indexación por número de día calendario en vez de proximidad a cierre) pero vive
directamente en cómo se calibra `curva_unificada_stock_seg.csv`, no en el factor `f`. Esto
también es la limitación de tarea 18c ya documentada (la curva de stock no rueda) — pero el
hallazgo de acá es independiente de eso: aunque la curva de stock rodara, seguiría sin
distinguir "día 28 en un mes de 31" de "día 28 = cierre".

**Corrección 2026-08-26 (repregunta del usuario) — el efecto NO es "último o penúltimo día",
es específicamente el último día real del mes.** Reagrupando la activación de NUEVOS por
**días-para-fin-de-mes** (0 = el último día de ESE mes en particular, sea 28/30/31) en vez de
por número de día fijo, sobre toda la ventana (20250101-20260630, ~S/4,300M de exposición):

| días para fin de mes | tasa de activación |
|---:|---:|
| **0 (último día real)** | **4.536%** |
| 1 (penúltimo) | 2.827% |
| 2 | 3.028% |
| 3-7 | 2.3%-3.5% |
| resto (baseline, ≥8) | 2.786% |

El día 0 salta **+63% sobre el baseline**; el día 1 (penúltimo) queda prácticamente en el
baseline (2.827% vs. 2.786%, diferencia no significativa). **El efecto es un pico angosto en
el cierre real, no una rampa de 2-3 días** — coincide con la intuición de que el pago se
concentra en el cierre del mes, pero es más estrecho de lo que "último o penúltimo" sugeriría.

**Esto además revela que el grupo `{30,31}` actual del factor `f` mezcla dos días de
naturaleza distinta.** En un mes de 31 días, el día 31 ES el pico (`dpf=0`) pero el día 30 es
apenas el penúltimo (`dpf=1`, ~baseline) — confirmado separando el propio día 29 por longitud
del mes: en meses de 30 días (día 29 = penúltimo, `dpf=1`) la tasa es 2.544%; en meses de 31
días (día 29 = antepenúltimo, `dpf=2`) es 3.047%, ambos cerca del baseline, ninguno cerca del
4.5% de `dpf=0`. Agrupar el pico angosto (día 31) junto con un día casi-baseline (día 30) en
un solo factor **diluye** el valor calibrado de "fin de mes" (1.1848) por debajo de lo que el
verdadero pico ameritaría — un efecto adicional al de febrero, presente en TODOS los meses de
31 días, no solo en febrero.

**Con STOCK el patrón es direccionalmente igual pero más ruidoso** (componente con mucha menos
masa por mes — ver `BUGS.md`, "el stock es el componente errático del backtest"): el % del
total real que cae en el último día real oscila 1.3%-12.3% según el mes, sin que agregar el
penúltimo día sume mucho más en la mayoría de los casos — consistente con un pico angosto,
pero con demasiada varianza mes a mes para confirmarlo con la misma solidez que en nuevos.

## 3. Hipótesis descartada: el tamaño del calendario del mes NO es el driver

El handoff pedía revisar si el sesgo correlaciona con el tamaño del calendario del mes.
Medido y descartado como explicación principal:

| Variable comparada con `err_nuevos` | correlación (r) |
|---|---:|
| tasa de entrada real del mes (soles) | **-0.93** |
| tiempo (índice de mes, ene=1...jun=6) | -0.69 |
| calendario total del mes (soles) | +0.48 |
| días calendario del mes | +0.47 |

El tamaño del calendario (en soles o en días) correlaciona débil, y ese poco que correlaciona
es porque la cartera crece con el tiempo (r=0.66 entre calendario y tiempo) — es un proxy
ruidoso del mismo efecto temporal, no un mecanismo propio. La tasa de entrada real domina por
mucho al resto de las variables candidatas.

## Conclusión

- **"Nuevos" subestima en los 7 meses porque `P_ENTRADA` mezcla una tasa calibrada por
  conteo de créditos con un calendario medido en soles**, y el exceso de entrada está
  concentrado en créditos de saldo alto (ya sabido desde agosto). Esto explica **~78% de la
  magnitud del error en 5 de 6 meses medibles** — el residuo (±3-6%, más en junio) es lo que
  queda para forma de curva y otros efectos menores.
- **Febrero además rompe en stock porque es el único mes de 28 días del test**, y el modelo
  indexa "fin de mes" por número de día calendario (30/31) en vez de por cercanía real al
  cierre — su verdadero último día nunca recibe el nivel que el modelo reserva para los días
  30/31 de los demás meses. Esto explica el **79.3%** del gap de stock de febrero, concentrado
  en un solo día. El efecto real (medido en nuevos, la muestra grande) es un **pico angosto
  específicamente en el último día del mes** (+63% sobre el baseline), no una rampa de 2-3
  días — y de paso diluye el factor `f` calibrado hoy para TODOS los meses de 31 días, porque
  agrupa ese pico junto con el día 30, que en un mes de 31 días es apenas penúltimo y no se
  despega del baseline.
- El tamaño del calendario del mes, medido directamente, **no** es el mecanismo — se descarta.
- **Nada de esto se ajustó.** Son dos hipótesis cuantificadas con evidencia, no cambios de
  producción. Si el usuario decide actuar sobre alguna: la de `P_ENTRADA` requiere recalibrar
  con la definición consistente (soles) y correr el backtest completo, no parchar la constante
  (bug 10); la de febrero requeriría re-indexar por "días hasta fin de mes" en vez de número de
  día calendario, un cambio de forma de la curva (mismo tipo de decisión que 18a/18f, se
  arbitraría con métricas diarias, no con el error de cierre).

# Tarea 19 — La corrección de 18b, medida; y lo que destapa

**Fecha:** 2026-09-01. **Estado: ADOPTADO** el mismo día, decisión del usuario — la meta de
septiembre del Enfoque alfa usa la tasa por SOLES (24.9081%, rodante `[202508,202607]`),
S/20,477,271. El motivo es la consistencia definicional, **no** que el error baje: para los
últimos 3 meses sube. La sección 6 deja escrito el razonamiento con el que se decidió.

Punto de partida: la decisión de recalibrar `P_ENTRADA` por SOLES en el Enfoque alfa (lo que
18b diagnosticó y 18e ya adoptó en Recupero Oficial), **verificándola con el backtest y no
parchando la constante** — bug 10 es el caso que dejó esa regla escrita.

---

## 1. La tasa de 18e sirve tal cual para el Enfoque alfa — verificado, no asumido

Los dos motores usan **la misma definición de entrada** (`dias_atraso_cuota` 0→1, calendario
elegible = entrada dentro del mes, excluye stock, mismos filtros de `CLAUDE.md`). Lo que
difiere aguas abajo es la **curva** (activación vs. rebaje), no quién entra. Sobre la ventana
`[202508, 202605]`, la query de soles reproduce el `P_ENTRADA` del alfa en créditos:

| | entran / elegibles | tasa |
|---|---|---:|
| `tarea17_fase4_tasa.sql` (alfa, producción) | 75,621 / 343,860 | 21.9918% |
| `tarea19_tasa_soles.sql`, columna de créditos | 75,613 / 343,788 | **21.9941%** |
| `tarea19_tasa_soles.sql`, columna de soles | S/112.8M / S/447.9M | **25.1924%** |

8 créditos de diferencia (los filtros `amountfinanced > 0` y el join de saldo al vencimiento).
**Misma población, dos unidades** — no hacía falta una query nueva, y el `+14.5%` de 18b queda
confirmado por una vía independiente.

## 2. El backtest: 3 variantes, para no confundir dos cambios en uno

Sin la variante B, el salto A→C mezclaría "rodar la tasa" con "cambiar de unidad".

| Mes | A. conteo fijo (producción) | B. rodante conteo | C. rodante soles |
|---|---:|---:|---:|
| Enero 2026 | -11.1% | -12.6% | **-0.5%** |
| Febrero 2026 | -19.1% | -20.5% | **-10.3%** |
| Marzo 2026 | -14.0% | -15.1% | **-3.3%** |
| Abril 2026 | -11.4% | -11.5% | **-0.9%** |
| Mayo 2026 | -10.7% | -10.8% | **+0.9%** |
| Junio 2026 | -2.7% | -2.8% | **+8.9%** |
| Julio 2026 | -2.9% | -3.4% | **+9.2%** |
| **Agosto 2026** (real, cerrado) | **-1.2%** | — | **+9.8%** (contrafáctico) |
| magnitud media (8m) | **9.14%** | — | **5.48%** |
| magnitud media, últimos 3 | **2.26%** | — | **9.30%** |

- **A→B: rodar la tasa por conteo no aporta** (10.26% → 10.96% en los 7 meses). El efecto es
  todo de la unidad, no de la ventana.
- **B→C: la corrección definicional arregla ene-may y sobreestima jun-ago.** No es que una
  tasa sea "mejor": es un **offset constante** de ~+14.5% sobre el componente nuevos.
- **Correlación diaria idéntica en las 3 variantes (0.886).** Era lo esperado y se reporta
  para dejar constancia: cambiar una tasa es un cambio de **nivel**, y la correlación de
  incrementos es invariante a escala. Acá el error de cierre **sí** es la métrica pertinente
  — no estamos arbitrando una forma (`CLAUDE.md`, "qué métrica arbitra qué").

## 3. Lo que el backtest destapa: la activación real viene cayendo

Las dos variantes **derivan ~+10pp en paralelo** a lo largo de los 8 meses. Una deriva que
sobrevive al cambio de tasa no puede ser un problema de la tasa. Medido directo:

| meta de | calendario | real nuevos | real/calendario | tasa entrada (soles) |
|---|---:|---:|---:|---:|
| 202601 | S/47,225,319 | S/9,352,471 | **19.80%** | 23.42% |
| 202602 | S/42,729,740 | S/9,400,119 | 22.00% | 26.00% |
| 202603 | S/61,743,553 | S/13,064,327 | 21.16% | 27.19% |
| 202604 | S/51,790,681 | S/11,019,816 | 21.28% | 25.10% |
| 202605 | S/66,309,552 | S/12,845,781 | 19.37% | 25.07% |
| 202606 | S/57,132,764 | S/10,949,101 | 19.16% | 23.34% |
| 202607 | S/84,497,576 | S/15,319,728 | 18.13% | 24.19% |
| 202608 | S/73,990,868 | S/13,476,394 | **18.21%** | — |

**La activación real cae -0.46pp por mes (r = -0.77); 20.99% en ene-mar → 18.50% en jun-ago.**
Mientras tanto la **tasa de entrada por soles no tiene tendencia** (23.3%-27.2%, oscila sin
dirección) y el calendario **creció +90%** en 9 meses (S/47M → S/90M).

O sea: la operación captura una **porción decreciente de una cartera que crece rápido**. Eso es
una señal de negocio — capacidad de gestión que no escala al ritmo del libro — exactamente la
clase de cosa que el modelo existe para hacer visible (`CLAUDE.md`, principio de interpretación
del error). No es un defecto del modelo ni algo a ajustar con una constante.

**Y explica por qué la tasa por conteo venía "funcionando":** al ser ~14.5% más baja de lo que
su propia definición pide, **compensaba la caída por accidente**. Es el mismo patrón que ya
mordió dos veces en este proyecto — bug 18 (índice corrido que tapaba el sesgo de nuevos) y la
capa fantasma (tasa plana sistemáticamente generosa justo donde nuevos subestimaba). Un número
mal definido tapando un sesgo real.

## 4. Acortar la ventana de calibración NO sigue esa caída

Hipótesis obvia: si la activación cae, una ventana más corta la seguiría. **Medido y
descartado** (variante C, curva y tasa en la misma ventana):

| ventana | magnitud media de error | correlación diaria | MAE diario | jun / jul |
|---|---:|---:|---:|---:|
| 6 meses | 5.29% | 0.876 | S/65,354 | +9.0% / +9.3% |
| 9 meses | **4.75%** | 0.882 | S/62,259 | +8.5% / +8.2% |
| 12 meses (protocolo) | 4.86% | **0.886** | **S/62,136** | +8.9% / +9.2% |

6 meses **empeora** las métricas diarias, que son las que arbitran esto; 9 ≈ 12 y la diferencia
está muy por debajo del ruido conocido (desvío pareado 1.49pp). Jun/jul quedan en +8.2-9.3% con
cualquiera. **El protocolo de 12 meses queda confirmado**, y la caída de activación no es un
problema de ventana: es un cambio de régimen que ninguna calibración ve venir.

## 5. El mismo mecanismo está en Recupero Oficial — que ya adoptó la tasa por soles

No es una peculiaridad del alfa. El motor de 18e v2, corrido sobre **agosto** (mes que no vio,
insumos prospectivos, ventana honesta `[202507,202606]`):

| | proyectado | real | error |
|---|---:|---:|---:|
| stock | S/902,367 | S/816,375 | +10.5% |
| nuevos | S/2,700,253 | S/2,357,637 | +14.5% |
| **total** | **S/3,602,620** | **S/3,174,012** | **+13.5%** |

Correlación diaria 0.738. En línea con junio (+15.8%) y julio (+18.3%). **La meta de
septiembre de Recupero Oficial (S/3,928,776) hereda ese sesgo** — no es una consecuencia de
la decisión pendiente en el alfa, ya está adoptada.

## 6. Cómo se decidió

Los dos principios de `CLAUDE.md` apuntan en direcciones distintas y hay que elegir a
sabiendas:

- **Principio de modelado** → adoptar soles. Tasa y curva deben calibrarse sobre la misma
  definición. Y hay precedente directo: **bug 18 se corrigió aunque empeoró los 4 meses**,
  porque corregía cómo se mide.
- **Consecuencia práctica** → con soles, la meta de septiembre del alfa sube **+11.6%**
  (S/18,342,247 → S/20,477,271), y la evidencia de los últimos 3 meses dice que sobreestimaría
  ~10%. Una meta que el negocio no alcanza no es neutral: es el número contra el que se lo mide.

Lo que **no** es una opción es elegir la tasa por conteo *porque el error sale más chico* —
eso es ajuste ex-post, y el hallazgo de la sección 3 dice explícitamente que su buen desempeño
reciente es una compensación accidental, no un mérito.

**Recomendación:** adoptar la tasa por soles (consistencia definicional, precedente de bug 18)
y **reportar el sesgo de activación decreciente como el hallazgo de negocio del mes**, con la
meta acompañada de esa lectura explícita. La alternativa defendible es diferir la adopción un
mes y usar septiembre como test prospectivo limpio de las dos — pero eso deja un mes más de
producción con una tasa que sabemos mal definida.

---

> **Nota de precisión (2026-09-02):** el contrafáctico de agosto se reporta con el motor
> **completo** vigente — curva de stock v3 (factor de cierre real) + tasa por soles — que da
> **+9.8%** (S/19,028,522 vs. S/17,322,872). La primera medición de esta tabla usó la
> configuración de stock de la meta v8 publicada y daba +9.7%; la diferencia es 0.13% y no
> mueve ninguna conclusión, pero el número comparable con septiembre es el de arriba.

**Archivos:** `backtest_tarea19_tasa_soles.py`, `tarea19_agosto_cadena_segmentada.sql`,
`armar_asignado_a_asegurado.py`, `tarea19_tasa_soles.sql`,
`generar_curvas_septiembre.py`, `meta_septiembre_capital_asegurado.py` (calcula las dos tasas;
`MODO_TASA` es el único switch), `meta_septiembre_recupero.py`, datos en `datos_tarea19/`.

---

# Addendum 2026-09-02 — el +9.8% de agosto se parte en dos, y una parte es convención

Al extender el backtest oficial a 8 meses con la tasa por soles apareció una discrepancia que
había que explicar: **agosto da +2.7% en el backtest, pero el contrafáctico de la meta daba
+9.8%.** Los dos números son correctos; miden cosas distintas, y separarlos es útil.

La diferencia es **qué calendario usa cada uno**:

| | calendario de agosto | proyectado | vs. real |
|---|---:|---:|---:|
| **Meta** (insumos prospectivos: saldo anclado al cierre de julio, `status='ACTIVE'`) | S/73,990,868 | S/19,028,522 | **+9.8%** |
| **Backtest** (insumos medidos: saldo del día del vencimiento, `ACTIVE`+`COMPLETED`) | S/68,408,838 | S/17,795,255 | **+2.7%** |

**El calendario prospectivo corre +8.2% por encima del real.** Y el mecanismo se ve directo en
el gradiente por día del mes:

| día de entrada | prospectivo | medido | exceso |
|---|---:|---:|---:|
| 1–5 | S/11,519,735 | S/11,054,112 | +4.2% |
| 6–10 | S/10,674,109 | S/10,116,345 | +5.5% |
| 11–15 | S/12,281,906 | S/11,400,147 | +7.7% |
| 16–20 | S/14,184,296 | S/13,066,128 | +8.6% |
| 21–25 | S/11,188,642 | S/10,031,747 | **+11.5%** |
| 26–31 | S/14,142,181 | S/12,740,359 | +11.0% |

Es **amortización**: cuanto más lejos está el vencimiento de la fecha de ancla, más ha pagado el
cliente en el medio, y más sobreestima el saldo anclado. Monótono, con la forma exacta que
predice el mecanismo — no es ruido.

**Descomposición del +9.8% de la meta de agosto:**

```
meta con insumos prospectivos   S/19,028,522
  −6.5%  convención de calendario (el ancla no descuenta la amortización)
backtest con insumos medidos    S/17,795,255
  +2.7%  el modelo propiamente dicho (caída de activación)
real                            S/17,319,324
```

**Qué significa esto para la meta de septiembre.** De su desvío esperado, ~6-8pp serían
convención y no ejecución. Es decir: **el caveat de "~10% alta" sigue en pie, pero su causa
principal NO es la caída de activación — es el anclaje del calendario.** Esa corrección hay que
hacerla en el texto que acompaña a la meta.

**Y esto es corregible, a diferencia de la caída de activación.** El decaimiento del saldo entre
la fecha de ancla y el vencimiento es **amortización conocida y medible**, no una sorpresa de
comportamiento. Un factor de decaimiento por "días entre el ancla y el vencimiento", calibrado
sobre historia, haría que el calendario proyectado represente lo que realmente estará en riesgo.
Eso es una corrección de **universo/medición** (el calendario hoy no mide lo que dice medir), no
un ajuste ex-post — cae del lado que `CLAUDE.md` manda corregir. **No se hizo: requiere
calibrarlo sobre historia y correr el backtest, y es la primera tarea del frente abierto.**

**Cuidado con la trampa:** ese factor NO se calibra contra el residuo del backtest (eso sí sería
ajuste ex-post). Se calibra midiendo, sobre meses históricos, cuánto cae el saldo de una cuota
entre el cierre del mes anterior y su fecha de vencimiento, abierto por días de distancia.

> **Nota 2026-09-13:** este factor quedó resuelto de otra forma — la tasa de entrada se calibra con el
> saldo anclado como denominador, el mismo que la meta multiplica (bug 28, `motor_v2.TASA_ANCLADA`).

---

# Addendum 2026-09-14 — Con las definiciones v2, la caída es sobre todo MENOS ENTRADAS; la conversión no tiene tendencia

Pregunta 2 del frente abierto (¿es composición?), medida sin Athena con la matriz de nuevos vigente
(`datos_tarea24/v2_matriz_nuevos.csv`) y los filtros de producción del motor v2: antiguo = en mora el
día 1, arrastre por DNI fuera, reenganches incluidos. Script: `tarea19_composicion_activacion.py`;
salida en `datos_tarea19/composicion_activacion.log` (local, no se versiona).

**1. La composición no explica la caída.** Shift-share de ene-mar contra may-jul 2026, sobre la
conversión a 30 días desde la entrada (92.82% → 91.75%, −1.08pp):

| segmentación | mezcla | dentro del segmento |
|---|---:|---:|
| banda de avance | +0.04pp | −1.13pp |
| día de semana del vencimiento | +0.00pp | −1.05pp |
| banda × día de semana (la de la curva) | +0.05pp | −1.10pp |
| tercio del mes de entrada | −0.04pp | −1.06pp |

Sobre la conversión dentro del mes (la que cuenta la meta; ene-mar → jun-ago, −1.13pp), la mezcla por
día de semana y por tercio jugó **a favor** (+0.4 a +0.5pp): tapó parte de la caída. La pendiente
2026-01 a 2026-07 con la mezcla fija casi no cambia (−0.30 → −0.29pp/mes). La dimensión "reenganche"
parece explicar 17-24%, pero no es mezcla: su peso cae de ~11% a 2.2% en agosto porque los reenganches
de los meses recientes todavía no ocurrieron (bug 25). Es la etiqueta, no la población.

**2. Lo que cae es la entrada, no la conversión.** La medida de la sección 3 (activado / calendario)
partida en sus factores, con v2 y el calendario medido:

| | ene-mar 2026 | jun-ago 2026 | cambio |
|---|---:|---:|---:|
| activado en el mes / calendario | 20.20% | 18.95% | −6.2% |
| tasa de entrada | 23.81% | 22.63% | **−5.0%** |
| conversión en el mes | 84.84% | 83.72% | −1.3% |

Con el calendario anclado de la meta: −5.7% = −4.4% de tasa y −1.3% de conversión. Coincide con el
backtest del motor adoptado (`datos_tarea25/backtest_ancla.log`, variante fix): julio sobreestima
nuevos +8.2% con una tasa anclada realizada de 19.15% contra 20.77% calibrada (−7.8% de volumen).
**La lectura de la sección 3 —la operación captura una porción decreciente, capacidad que no escala— no
se sostiene como caída de conversión:** con v2 la conversión cae 1.3%; el grueso es que entra menos
gente en mora, que es volumen y no ejecución de cobranza.

**3. La conversión a 30 días no tiene tendencia, y ene-mar 2026 fue un pico.** En 19 meses (2025-01 a
2026-07) la pendiente es −0.02pp/mes (r = −0.13), entre 91.3% y 94.3%. La velocidad cuenta lo mismo:

| de lo activado a 30 días, parte que activó… | ene-mar 2026 | may-jul 2026 | 2025, rango mensual |
|---|---:|---:|---:|
| el mismo día de la entrada | 45.9% | 38.3% | 35.4 – 42.9% |
| hasta el día 7 (mezcla banda × dow × tercio fija) | 90.3% | 87.5% | 85.4 – 89.5% |
| hasta el día 14 | 96.2% | 95.4% | 94.8 – 96.1% |

Todo lo que se compara contra ene-mar 2026 exagera la caída: ese trimestre activó más rápido que
cualquier otro de la serie y después volvió al nivel de 2025.

**4. Lo que esto dice de septiembre.** El volumen que entró es el esperado (+0.6%) y la brecha de
nuevos al día 12 es de **arranque**: 0.649 activado por sol que entró (entradas de los días 2-12) contra
0.731 proyectado. Ese número, histórico, va de 0.596 a 0.771 en los últimos 12 meses (media 0.705):
ene-mar 2026 dio 0.74-0.77 y may-ago bajó de 0.72 a 0.67. La curva de la meta se calibra en [202508,
202607], que incluye el pico de ene-mar, así que espera un arranque más rápido que el de los meses
recientes. **Si el patrón histórico se sostiene (la velocidad varía, la conversión a 30 días no), la
brecha de nuevos de septiembre debería achicarse después de la quincena.** Se verifica con el
seguimiento del 16-17 de septiembre y al cierre; si no se achica, sí es conversión y es un quiebre.

**5. De paso, tarea 21.** La base de la matriz (cada entrada) y el numerador de la tasa (una cuota por
crédito) coinciden a 0.00-0.04% por mes; la excepción es 202512 (+3.7%). El doble conteo de entradas
en el nivel de la base es despreciable salvo diciembre 2025. La forma de la curva no se midió.

**Qué queda abierto:** (a) qué pasó en ene-mar 2026 —activación más rápida en toda la cartera—, una
pregunta para el negocio (¿estrategia, campaña, canal?); (b) por qué bajó la tasa de entrada en jun-jul
(la anclada de julio, 19.15%, es la más baja de la serie): es cartera u originación, no cobranza; (c) la
prueba de septiembre después de la quincena.

**No se ajusta nada** (`CLAUDE.md`): es diagnóstico. La ventana de 12 meses sigue (sección 4).

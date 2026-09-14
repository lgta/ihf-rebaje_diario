# Decisiones metodológicas

Por qué se eligió cada pieza del modelo. Si alguien pregunta "¿por qué hacemos X y no Y?",
la respuesta debería estar acá.

### Modelo evento × magnitud, no rebaje diario promedio
El pago es "grumoso": 92% de los crédito-mes en mora tiene 0 o 1 evento de pago al mes
(24% no rebaja nada, 68% rebaja en exactamente 1 día). Promediar el rebaje del mes entre 30
días no sobrevive a este chequeo. Se modela en cambio `P(paga) × E(% del saldo que rebaja
al pagar)`. Confirmado con datos en `fase0_diagnostico.sql` bloque 0.2.

### Tramo fijo aunque el crédito cruce 30 días de mora
Un crédito asignado con, digamos, 28 días de mora al inicio del mes sigue sumando a la meta
(y conserva su tramo original) aunque cruce 30 días a mitad de mes. Confirmado por el
usuario y validado empíricamente: el bug de "aged-out survivors" (bug 7 en `BUGS.md`)
apareció precisamente por NO respetar esta regla en un enfoque alternativo, y corregirlo
acercó el resultado al esperado.

### Avance de amortización como segmentador de severidad, no `term`
Ambos predicen severidad de forma parecida (son proxies el uno del otro: avance ≈ 1/term),
pero avance es más directo — mide cuánto le queda al crédito, no cuántas cuotas tenía al
inicio. Se usa avance como segmentador operativo único; los números de `term` de la corrida
original de Fase 2 quedaron con el bug de window-function (bug 4) y nunca se recalcularon —
no confiar en ellos.

### Tramo predice frecuencia, avance predice severidad — son ejes distintos
Hallazgo empírico de Fase 1: la severidad es casi PLANA entre tramos (~24% cuando el
crédito paga algo); lo que cae con la mora es la frecuencia (83%/58%/39% pagan algo en el
mes, tramos 1-8/9-15/16-30). El tramo no debe usarse como proxy de severidad.

### Dos filtros de `status` distintos según se mire pasado o futuro
- **Histórico/calibración** (curvas, tasas): `status IN ('ACTIVE','COMPLETED')` — se
  quiere el comportamiento completo, incluidos los que ya terminaron de pagar bien.
- **Calendario prospectivo** (qué va a vencer): `status = 'ACTIVE'` solamente — un crédito
  `COMPLETED` ya no tiene obligaciones futuras.
- **Backtest de un mes cerrado:** `status IN ('ACTIVE','COMPLETED')`, SIN filtrar por
  `installmentstate` — ya se conoce el desenlace real vía `dts_mambu_loans_hist`, filtrar
  por `PENDING` perdería casi todas las cuotas (ya resueltas).

### P(no paga a tiempo) = 13.38%, no 25-28%, no 27.4%
Es la tasa medida a nivel CRÉDITO (`dayslate` 0→1), fuera de muestra, y la que efectivamente
pasó el backtest (+5.4% de error). El complemento simple de "% paga a tiempo" a nivel CUOTA
(~25-28%) mide una población distinta (incluye pagos 1-día-tarde que `dayslate` nunca
llega a ver — bug 9) y sobreestima +66% a +81% si se usa con la curva actual. Ver
`feedback-tasa-curva-consistente` en memoria: **la tasa y la curva de recupero deben
calibrarse sobre la misma definición de "entrada"** — no se puede mezclar. Detalle completo
en `BUGS.md` (bugs 6, 9, 10) y el artifact
[⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8).

### Mantener dos enfoques en paralelo (agregado vs. segmentado)
A pedido explícito del usuario, para poder comparar. El segmentado (tramo×avance /
avance) es más fiel a la mezcla real de la cartera; el agregado es más simple de mantener.
La diferencia entre ambos es en sí misma una señal útil (si crece con el tiempo, indica que
la mezcla de la cartera se está moviendo respecto al histórico).

### Enfoque "acumulado" (anclado al cierre del mes anterior) es el oficial
No el "reinicio del reloj" (recalcular todo desde hoy). El acumulado nunca re-filtra por
mora del día corriente — clasifica una sola vez al momento de asignación, lo cual evita
estructuralmente el bug de aged-out survivors. El "reinicio del reloj" es útil como
sanity-check ocasional pero requiere un parche manual cada vez que se usa (ver bug 7). El
usuario confirmó el 2026-07-10 que la pregunta que le interesa siempre es la del mes
completo — no seguir invirtiendo en el enfoque alternativo salvo pedido explícito.

### Verificar contra el backtest, no razonar en abstracto, ante cualquier cambio de constante
Cuando se propone cambiar una tasa o constante del modelo, la forma de resolverlo no es
debatir en teoría qué número es "más correcto" — es correr el backtest ya existente con el
cambio propuesto y ver el error real. Esto resolvió en minutos la discusión sobre 13.38% vs
25% donde el razonamiento abstracto se hubiera estancado. Ver
`feedback-tasa-curva-consistente` en memoria para el detalle.

### Las curvas deben representar TODA la mora que ocurre, no solo la que el negocio gestiona (2026-08-24)
Al investigar el mecanismo detrás del punto ciego de `dayslate` (bug 9/16), se encontró que
`dts_asignaciones_gestiones_cobranza` (la asignación real de cobranza) no tiene NINGUNA fila
los sábados/domingos — el negocio gestiona solo de lunes a viernes. Esto abrió una pregunta
de fondo: si una reconstrucción más fina (`dias_atraso_cuota`) ve mora real que el propio
negocio nunca llega a gestionar (porque su ciclo no corre fines de semana), ¿la curva debe
representar esa mora igual, o solo la que el negocio puede gestionar? **El usuario decidió
que la curva debe capturar el comportamiento de CUALQUIER día donde haya vencimientos**,
gestionado o no — un crédito que entra en mora el sábado y paga el domingo sí entró en mora
de verdad, aunque el negocio nunca lo haya visto. Verificado antes de aceptar la decisión:
(1) un crédito que vence sábado y sigue sin pagar aparece oficialmente como "nuevo" recién
el lunes (100% en 259 casos reales); (2) la forma de la curva sí difiere por día de semana
del vencimiento (fin de semana paga ~2x más rápido en el día 1 desde la entrada) — sin
gestión activa el sábado, más créditos "se escapan" a mora pero pagan apenas los llaman el
lunes. Esto convierte a `dias_atraso_cuota` en el universo correcto para calibrar de acá en
adelante (reemplaza `dayslate`) y al día de la semana del vencimiento en un segmentador de
curva pendiente de incorporar. Ver bug 16 en `BUGS.md` y tarea 17 en `PENDIENTES.md` para el
detalle completo, las queries y los números.

### Enfoque "reinicio del reloj" y Enfoque beta "salida de mora" descontinuados (2026-07-15)
A pedido explícito del usuario, el proyecto acota su alcance a **2 enfoques**: el
acumulado/oficial (rebaje, capital reducido) y el alfa (capital asegurado, meta principal
desde 2026-07-13). Ambos venían ya señalados como no prioritarios (el primero
"deprioritizado" desde el 2026-07-10, ver más arriba; el segundo "exploratorio") pero
nunca se había formalizado su descarte. Se eliminaron del repo sus archivos
(`enfoque_reinicio_reloj.md`, `meta_desde_hoy.py/.sql`, `datos_meta_desde_hoy/`,
`enfoque_salida_mora.md/.sql`, `salida_mora.html`, `datos_salida_mora/`) junto con
`guia_4_enfoques.html`/`ejemplos_4_enfoques.sql` (quedaba obsoleta: explicaba 2 enfoques
que ya no existen). Quedan recuperables vía `git log`/`git show` de cualquier commit
anterior a esta limpieza — no se pierde el trabajo, solo deja de mantenerse. Los
artifacts ya publicados de ambos no se retiran de claude.ai, solo se sacan de las tablas
de "vigente" en `README.md`/`ESTADO.md`. El plan de continuación para los 2 enfoques que
quedan está en `PENDIENTES.md`.

### La métrica que arbitra un refinamiento de forma es la trayectoria diaria, no el error de cierre (2026-08-26)

**Decisión:** los cambios de **forma** del modelo (segmentadores, índices, factores) se
evalúan con la **correlación entre incrementos diarios proyectados y reales** y el MAE del
incremento diario. El **error de fin de mes** queda reservado para lo que sí mide: la meta
contra la ejecución, y el insumo para explicar el sesgo.

**Por qué, con números:** la diferencia pareada del error de cierre entre dos variantes de
curva tiene media **-0.13pp** y desvío **1.49pp** — el ruido es 10x el efecto, porque el signo
lo fija la composición de fin de mes de cada mes (en mayo el 45.8% del calendario de los
últimos 5 días vence en fin de semana; en julio, 0.0%). Detectar 0.13pp sobre el cierre
necesitaría **~1,050 meses**. No es que falten datos: el estadístico no tiene resolución para
esa pregunta, y nunca la va a tener.

Las métricas diarias aportan ~30 observaciones por mes en vez de 1, y ahí el mismo cambio se
distingue sin ambigüedad: el día de semana del vencimiento mejora la correlación en los 7
meses de test **sin excepción** (0.611 → 0.886) y baja el MAE del incremento diario 41%.

**Consecuencia que hay que saber leer:** un cambio puede **empeorar el cierre y mejorar el
seguimiento diario a la vez**. Mayo 2026 es el caso: -8.7% → -10.9% de error de cierre,
correlación diaria 0.32 → 0.86. Las dos cosas son ciertas y miden cosas distintas. Reportar
siempre las dos.

Esto **no reemplaza** el "Principio de interpretación del error" — lo complementa: aquel dice
que el error no se optimiza, este dice que además no sirve para arbitrar cambios de forma.

### `avance_band` se queda en 4 buckets — no se colapsa a 3 (2026-08-26)

**Decisión:** no fusionar `c. avance 40-70%` con `d. avance 70%+`, pese a que la observación
que lo motivó era correcta.

La observación original —que las dos bandas no se separan— **es cierta como enunciado sobre la
curva**: difieren ≤3.9% en relativo y se **cruzan** en el día 14 (d es más lenta al principio y
más rápida al final). Y el colapso es numéricamente gratis: mueve el total de un mes **0.008%**
como máximo.

**Se rechaza igual porque `avance_band` no es solo un segmentador de curva — es el eje por el
que se lee la desviación.** En agosto 2026 la banda 70%+ corre **+89.5%** sobre lo proyectado y
la 40-70% **+21.9%**; colapsadas dan +28.6%, que esconde que el bucket chico va al doble. Per
el criterio de adopción, el colapso no hace la medición más fiel: la hace más gruesa.

### Protocolo de calibración: 12 meses rodantes, 7 meses de test (2026-08-26)

**Decisión:** las curvas de "nuevos" se calibran sobre una ventana **rodante de 12 meses**
(`[M-12, M-1]`), y el backtest oficial corre sobre **7 meses** (202601-202607).

**Por qué 12 y no más:** medido en `tarea18_ventana_calibracion.sql`. El ruido mes a mes del
día 0 de la curva es ±2.8pp mirando desde 202501; estirar a 202401 lo **sube** a ±4.4pp, porque
esos meses son carteras de <20% del tamaño actual. Doce meses es donde el ruido mensual ya se
promedió y todavía no entra régimen viejo. La cola de la curva (día 30) es estable en todas las
ventanas (±1.0pp), o sea la deriva vive en el arranque, no en el nivel.

**Por qué 7 meses de test:** con piso de 3,000 entradas/mes la historia usable arranca en
202501, y `[usable] - [ventana]` da 7 meses. Bajando el piso a 1,000 se llega a 13, pero a
costa de meses cuya cartera es un tercio de la actual.

**Para una meta prospectiva la ventana termina en el último mes COMPLETAMENTE OBSERVADO**, no
en el mes anterior: una cohorte necesita 31 días de seguimiento. Para la meta de agosto la
ventana es `[202507, 202606]` — julio queda afuera aunque ya haya pasado, porque al 1-ago sus
cohortes no estaban cerradas. Meter julio sería usar información que la meta no podía tener.

**Beneficio medido:** con la ventana rodante el leak de calibración queda **medido, no
estimado**: 0.10pp (0.11 / 0.17 / 0.01 / -0.09 en los 4 meses comparables), consistente con los
0.15-0.2pp que tarea 10 había medido sobre la arquitectura de 3 componentes.

### Motor unificado v2 (W3): día de semana del vencimiento + factor por día del mes (2026-08-26)

**Decisión del usuario:** adoptar W3 en producción y **recalcular la meta de agosto** a mitad
de mes (no congelarla).

Dos dimensiones nuevas en la curva de "nuevos", ambas medidas antes y probadas contra el
backtest de 7 meses:

1. **Día de la semana del vencimiento**, abierto a los 6 días que existen. El día 0 va de
   18.7% (venc. sábado, entra domingo) a 42.0% (venc. martes, entra miércoles); antes se
   aplicaba a todos los días el promedio ponderado, 34.3%, **que no corresponde a ninguno** —
   cada día del calendario tiene un día de semana único, no es una mezcla.
2. **Factor multiplicativo por día del mes** sobre el incremento diario: quincena 1.0855, días
   30-31 1.1848, resto 0.9812. **2 parámetros, no 31**: con uno por día sobreajusta
   (correlación entre mitades disjuntas de la ventana, solo +0.51). El día 29 sale bajo en
   todas las ventanas, así que el efecto es de **fecha de pago** (planilla), no de "últimos
   días del mes".

**Confirmación independiente del mecanismo de (2):** la curva de **stock**, que ya estaba
indexada por día del mes y por lo tanto sí puede verlo, tiene la quincena **+12%** sobre su
propia tendencia local. El efecto existe en los datos; el componente de nuevos era el único
ciego a él, por estar indexado en días-desde-la-entrada.

**Criterio de adopción aplicado:** el error de cierre pasa de 10.43% a 10.55% — irrelevante y
además no arbitrable (ver arriba). Se adopta porque cambia **cómo se mide**, y la trayectoria
diaria queda más fiel en los 7 meses sin excepción.

**Alternativas evaluadas y descartadas:** el corte binario `finde`/`semana` de Fase 2/3 (mal
especificado, ver bug 21 — captura solo ~2/3 de la ganancia) y una agrupación de 3 regímenes de
día de entrada (0.849 vs. 0.878 de correlación, y engrosa solo las celdas que ya eran gruesas:
la celda mínima sube de 1,241 a 1,519 entradas, +22%, no al doble).

### Recupero oficial migrado a `dias_atraso_cuota` (tarea 18e, 2026-08-26 continuación 2)

**Decisión del usuario:** migrar el motor de Recupero Oficial (`fase1_stock.sql`/
`fase2_nuevos.sql`/`fase3_backtest.sql`, hasta entonces con `dayslate`) al mismo universo que
ya usa Capital Asegurado desde tarea 17 Fase 4. Alcance de Fase 4 había sido deliberadamente
solo Capital Asegurado; esta decisión cierra esa asimetría.

**Por qué:** mismo argumento que ya justificó Fase 4 — el punto ciego de `dayslate` (bug 9,
~1 día) no tenía ninguna compensación acá (Recupero Oficial nunca tuvo capa fantasma). Medido
en el backtest de 7 meses: el real capturado con `dias_atraso_cuota` es **148%-157% del real
capturado con `dayslate`** en junio/julio — mucho más que el +26-30% ya conocido en conteo de
créditos, porque la población invisible a `dayslate` paga casi instantáneo (99.60% el mismo
día, bug 16 Fase 3) y aporta rebaje ~1:1 de su saldo apenas se detecta. Validado a nivel de
caso (`tarea18e_validacion_casos_fantasma.sql`): créditos donde `dayslate` marca 0 el día
exacto en que pagan, algunos cancelando el saldo completo ese mismo día.

**Se corrigió la tasa de entrada por la misma razón que 18b encontró en Capital Asegurado**:
calibrarla CONTANDO créditos pero aplicarla sobre un calendario en SOLES subestima, porque el
exceso de entrada se concentra en créditos de saldo alto. La tasa de Recupero Oficial se
calibró por SOLES desde el arranque (25.19% agregada, 23.4%-27.2% por mes rodante) — no se
repitió el error para descubrirlo después del backtest, como pasó la primera vez.

**Refinamiento de forma aplicado desde el arranque** (no como pasada separada): ventana rodante
de 12 meses sin leak para nuevos, día de semana del vencimiento, factor de quincena, factor de
cierre real en stock (ventana de stock fija — rodarla ya se había probado y empeora en Capital
Asegurado, mismo mecanismo, no se repitió el experimento). Correlación de incrementos diarios
0.560→0.837, mismo salto que el refinamiento análogo dio en Capital Asegurado.

**Criterio de adopción aplicado:** no se adoptó por mejora de error (el error de cierre del
motor nuevo, 7.83% de magnitud media, no es comparable uno a uno contra el viejo — universos
distintos). Se adoptó porque el universo capturado queda más fiel — el mismo criterio ya
aplicado en Fase 4 y en W3.

**Excepción deliberada, mismo patrón que 18g con la meta de Capital Asegurado:** la meta de
AGOSTO de Recupero Oficial (`meta_agosto.py`) NO se recalculó — sigue con `dayslate`/13.38%
hasta que agosto cierre. Cambiar el motor de un mes ya en curso movería la lectura "real vs.
proyectado" de los últimos días sin necesidad. La meta de **septiembre** es la primera en usar
el motor nuevo, calibrable recién cuando julio complete sus 31 días de seguimiento (~31-ago,
ver el protocolo de calibración de arriba) — no antes, y no por el cierre de agosto en sí.

---

### La tasa de entrada se calibra en SOLES, aunque eso empeore el error reciente (2026-09-01, tarea 19)

`P_ENTRADA` se calibraba **contando créditos** (21.9918%) pero el motor la aplica
**multiplicando el saldo en soles** del calendario. Los créditos que caen en mora tienen saldo
por encima del promedio, así que la tasa correcta en soles corre **~14.5% más alta** (25%).
18b ya había diagnosticado que esa mezcla explicaba ~78% del sesgo de "nuevos"; 18e ya lo había
corregido en Recupero Oficial. Agosto cerró, así que dejó de aplicar la regla de "no cambiar el
motor de un mes en curso".

**No hacía falta una query nueva.** Los dos enfoques comparten la definición de entrada
(`dias_atraso_cuota` 0→1, calendario elegible = entrada dentro del mes, excluye stock); lo que
difiere aguas abajo es la curva (activación vs. rebaje), no quién entra. Verificado: la query de
soles de 18e reproduce el `P_ENTRADA` del alfa en créditos con 8 créditos de diferencia sobre
343,788 (21.9941% vs. 21.9918%).

**Se probó con 3 variantes, no 2**, para no confundir dos cambios en uno: fija por conteo (A),
rodante por conteo (B), rodante por soles (C). A→B mide el efecto de *rodar*; B→C el de cambiar
de *unidad*. Rodar solo no aporta (10.26%→10.96%): el efecto es todo de la unidad.

**Por qué se adoptó aunque el error sube en los últimos 3 meses** (jun/jul/ago pasan de ~-2% a
~+9%): por el **principio de modelado** — tasa y curva deben calibrarse sobre la misma
definición — y con el precedente directo de bug 18, que se corrigió aunque empeoró los 4 meses
de entonces. Elegir la tasa de conteo *porque el error sale más chico* habría sido ajuste
ex-post; y además su buen desempeño reciente no era mérito sino **compensación accidental** de
la caída de activación (abajo).

La correlación de incrementos diarios es **idéntica en las 3 variantes** (0.886). Era lo
esperado: un cambio de tasa es de **nivel**, no de forma, y la correlación es invariante a
escala. Acá el error de cierre sí es la métrica pertinente — no se está arbitrando una forma.

### La caída de activación es hallazgo de negocio, no parámetro a ajustar (2026-09-01, tarea 19)

Las dos variantes de tasa **derivan ~+10pp en paralelo** a lo largo de 8 meses. Una deriva que
sobrevive al cambio de tasa no puede ser de la tasa. Medido directo: el capital asegurado de
nuevos como % del calendario **cae -0.46pp/mes** (20.99% ene-mar → 18.50% jun-ago, r=-0.77),
mientras la tasa de entrada por soles no tiene tendencia y el calendario **creció +90%** en 9
meses. Se captura una porción decreciente de una cartera que crece rápido.

**Qué NO se hizo, y por qué.** No se metió un factor correctivo ni se acortó la ventana para
"seguir" la caída. Lo segundo se **midió**: 6 meses empeora las métricas diarias (0.886→0.876),
9 ≈ 12, y jun/jul quedan en +8.2-9.3% con cualquier ventana. No es un problema de calibración:
es un cambio de régimen que ninguna ventana ve venir. Ajustarlo convertiría el modelo en un
ajuste ex-post y destruiría lo que lo hace útil como meta fijada al inicio del mes.

**Qué se hizo en cambio.** La meta de septiembre se publica con el caveat explícito de que corre
~10% por encima de lo alcanzable si la tendencia sigue — en `ESTADO.md`, en el docstring del
script y en el artifact. La meta es la referencia contra la cual se lee la ejecución; la
desviación se explica.

### Antiguo = "en mora el día 1": la definición de la vista, con flag de arrastre por DNI (2026-09-13, tarea 24)

**Decisión del usuario.** Un crédito que entra en mora el día 1 del mes es **antiguo**, como en
`vw_seguimiento_diario_cohorte_tramo`, y no un nuevo con `dia_entrada = 1` como lo trataba el motor
unificado desde tarea 17 Fase 4. Se recalibra lo que haga falta.

**Por qué es la regla correcta y no solo "la del negocio".** El negocio calcula `tipo_mora` con
`dias_mora >= day(fecha_base)`, que en cualquier día de asignación equivale a "entró en mora el día 1
o antes". Con esa definición el cuadre contra la vista pasa de −23.9% a **+0.5%**, con el monto
idéntico al céntimo en 2,749 de 2,751 créditos compartidos: es el *principio de universo* de
`CLAUDE.md` cumplido. Y es reproducible en toda la historia sin la tabla de asignaciones, porque va
anclada al día 1 calendario y no al primer día hábil.

**Lo que arrastra la misma regla, y coincide con el negocio:** sale del stock quien estaba en mora al
cierre pero pagó el último día del mes (478 en septiembre; si vuelve a caer, entra por el
calendario), y quien pasa de 30 a 31 el día 1 (46, van a ESPECIALIZADA).

**Arrastre por DNI: como la vista, pero con flag.** El crédito en mora 1-30 cuyo DNI tiene otro
crédito con más de 30 días no es TEMPRANA. Se marca con `flg_arrastre_dni` en vez de borrarlo, para
poder separarlo en reporte y análisis (pedido del usuario). Reconstrucción validada al 99.9% contra
el `max_dias_mora_dni` del negocio.

**Qué NO se decidió:** qué hacer con los reenganches — el filtro mira hacia adelante (bug 25), medido
y con la decisión pendiente del usuario. Tampoco se cambió de fuente por el punto ciego de
`dias_atraso_cuota` (bug 26, 1.3%).

**Cómo se aplica a las metas.** La de septiembre, ya publicada, no se toca: v2 se calcula en paralelo.
Octubre es la primera meta con la definición nueva. El criterio de siempre: se corrige el universo
aunque el error suba, y se mide con el backtest.

### Se adopta el motor v2: cohorte del día 1 con la curva de nuevos, arrastre por DNI fuera (2026-09-13, tarea 24)

**Decisión del usuario**, con el backtest de 8 meses a la vista (`backtest_tarea24_v1_v2.py`): las
metas desde **octubre 2026** se calculan con el motor v2 (`motor_v2.py` + `meta_v2.py`).

- **Stock** = `dias_atraso_cuota` 1-30 el día 1, con el saldo de la última foto del mes anterior.
- **La cohorte que entra en mora el día 1** (0-53% del stock según el mes, porque sigue a las cuotas
  que vencen el 30) se proyecta con la curva de **nuevos** por banda y día de semana del
  vencimiento, sobre su saldo real y sin tasa (variante S2). Ganó en las métricas diarias en los dos
  enfoques contra mezclarla en el tramo 1-8 (S0) o darle un tramo propio en la curva de stock (S1):
  la curva de nuevos sabe que el día 0 de esa cohorte depende del día en que venció la cuota.
- **Nuevos** = calendario desde el día 2, una cuota por crédito, tasa por soles sobre esa misma
  población (24.36% en [202508, 202607], contra 24.94% de v1). Resuelve bug 23 por construcción.
- **Arrastre por DNI: fuera de TEMPRANA**, como en la vista, porque se cobra en ESPECIALIZADA.
  Marcado con `flg_arrastre_dni`, no borrado. Medido: dentro o fuera no cambia el modelo.
- Ventanas: nuevos (curva y tasa) en **[M-13, M-2]**, los 12 meses hasta el último completamente
  observado el día 1 (`motor_v2.ventana_meta`); stock fija 202504-202606.

**Por qué se adopta aunque el error de recupero suba** (8.26% → 8.94%): cambia QUIÉN entra al
universo — cuadra con la vista al +0.5% — y ese es el criterio de `CLAUDE.md`. En alfa el error baja
(4.55% → 4.09%) con la misma correlación diaria.

**Septiembre no se toca:** su meta se fijó el 1-sep con la definición anterior, y una meta no se
cambia a mitad de mes. La meta v2 que habría salido ese día (S/19,814,433 alfa, S/3,856,429 recupero;
`meta_septiembre_v2_dia1.py`) queda como referencia, salvo que el usuario decida otra cosa.

**Pendiente:** si la calibración incluye a los créditos que después tuvieron un **reenganche** (bug 25).
El usuario aclaró que un reenganche es un crédito adicional en la misma línea y no un
refinanciamiento de cobranzas; los datos lo confirman (`tarea24_reenganches_que_son.sql`).

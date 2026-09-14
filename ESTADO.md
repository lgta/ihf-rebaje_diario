# Estado actual

> Este archivo se **reescribe**, no crece. Si algo de acá cambia (una meta se recalcula,
> un artifact se actualiza, un pendiente se resuelve), se edita esta misma sección — no
> se agrega una entrada nueva al final. Para saber **por qué** se decidió algo, ver
> `DECISIONES.md`. **`plan_analisis.md` cubre solo hasta julio 2026** — desde agosto el
> historial cronológico vive en los bloques fechados de este archivo, no allá.

Última actualización: 2026-09-13, tarde (seguimiento de septiembre + recalibración v2 de tarea 24).

> **PARA ARRANCAR UNA SESIÓN NUEVA:** el prompt de handoff vigente es
> [`prompt_handoff_2026-09-13.txt`](prompt_handoff_2026-09-13.txt) (actualizado la tarde del 13-sep)
> — reemplaza al del 2026-09-11. Después: los dos bloques de abajo + "La meta vigente", y
> `PENDIENTES.md` **tarea 24** (recalibración hecha, adopción pendiente) y **tareas 20, 21 y 23**.

> **2026-09-13 (tarde) — SEPTIEMBRE SEGUIDO CONTRA LA META Y RECALIBRACIÓN v2 EJECUTADA. Nada
> adoptado ni commiteado: quedan tres decisiones del usuario.**
>
> **SEPTIEMBRE VA −17.4% CONTRA LA TRAYECTORIA DE LA META (alfa, al 12-sep).** Real S/7,155,605
> contra S/8,666,800 proyectado al mismo día; stock +4.0%, nuevos −21.6%; correlación diaria 0.982.
> Recupero, −28.6%. El caveat de ~10% se materializa y lo supera: en los 8 meses del backtest el
> cociente del día 12 nunca bajó de 0.93, y el cierre terminó a ±4pp de él. La brecha es sobre todo
> de **volumen** (entró en mora 17.1% menos saldo que el esperado, hasta ~8pp por el ancla sin
> amortizar) y en menor medida de **conversión** (−5.4% por sol que entró). Detalle en
> `SEGUIMIENTO.md`.
>
> **RECALIBRACIÓN v2 (antiguo = en mora el día 1) HECHA, con v1 y v2 de la misma foto.** Cuatro
> queries nuevas (`tarea24_v2_*.sql`) que, filtradas como v1, reproducen las de tarea 19 (≤1.2%), y un
> backtest v1 reconstruido que reproduce el publicado (4.55% contra 4.54%). En 8 meses: alfa, v1 4.55%
> / corr. 0.826 → **v2 S2 4.09% / 0.826**, con un MAE diario 4% menor; recupero, 8.26% / 0.826 →
> 8.94% / 0.811. La cohorte del día 1 pesa 0-53% del stock según el mes y se proyecta mejor con la
> curva de NUEVOS (variante S2, gana en métricas diarias en los dos enfoques). v2 **resuelve bug 23**
> por construcción. Septiembre en paralelo: v2 daría **S/19,283,694** en alfa, contra S/19,932,405 de
> v1 re-medida hoy (−3.3%).
>
> **Tres decisiones pendientes del usuario:** (1) adoptar v2 con S2 para octubre (recomendado); (2)
> arrastre por DNI: el mensaje de arranque dejó la respuesta en blanco, se corrió con "fuera, con
> flag" y dentro/fuera no cambia el modelo (4.09% contra 4.10%); (3) reenganches: incluirlos baja el
> error de alfa de 4.09% a 3.74% y explica ~1.5-2pp de la deriva de jun-jul (entran en mora mucho
> menos, tasa 15-19%). Detalle en `PENDIENTES.md` tarea 24.

> **2026-09-13 — TAREA 24: ANTIGUO PASA A SER "EN MORA EL DÍA 1", LA DEFINICIÓN DE LA VISTA
> (decisión del usuario). Reconciliado, decidido lo que colgaba, recalibración por empezar.**
> Con la definición nueva el cuadre de antiguos de septiembre contra la vista pasa de **−23.9% a
> +0.5%** (2,837 créditos / S/4,930,217 contra 2,790 / S/4,904,773), con el monto idéntico al céntimo
> en 2,749 de 2,751 compartidos. La regla del negocio (`dias_mora >= day(fecha_base)`) equivale a
> "entró en mora el día 1 o antes", así que se reproduce en toda la historia. Los 487 que el 2-sep "no
> aparecían" **no eran rezago**: pagaron el 31-ago y nadie los asignó. Decisiones: arrastre por DNI
> como la vista pero con flag (reconstrucción validada al 99.9%); punto ciego de `dias_atraso_cuota`
> documentado (pagos regularizados con fecha valor, bug 26); **reenganches medidos, decisión
> pendiente** — el filtro mira hacia adelante y saca 8-11% del saldo de nuevos en los meses completos
> (bug 25). **La meta de septiembre (S/20,477,271) no se tocó**; octubre sería la primera meta v2.
> La recalibración y el seguimiento de septiembre se hicieron esa misma tarde (bloque de arriba).
> Detalle y plan en `PENDIENTES.md` tarea 24; decisión en `DECISIONES.md`.

> **2026-09-01/02 — AGOSTO CERRADO, METAS DE SEPTIEMBRE FIJADAS, Y UN HALLAZGO DE NEGOCIO QUE
> CAMBIA LA LECTURA DEL SESGO (tarea 19).**
>
> **AGOSTO CERRÓ.** Capital asegurado: meta S/17,117,628 vs. real **S/17,322,872 = -1.2%**
> (stock -1.3%, nuevos -1.1%) — **el mes más ajustado del proyecto**, y rompe la racha de 7
> meses en que "nuevos" subestimaba (-2.8% a -21.6%). Recupero oficial: meta S/2,108,435 vs.
> real **S/2,178,078 = -3.2%**, con el real medido con `dayslate`, la misma definición que la
> meta (medirlo con `dias_atraso_cuota` daría S/3,174,012 = **146%**, en línea con el 148-157%
> de 18e — pero eso infla el error por cambio de universo, no por ejecución). Dos honestidades
> anotadas en `SEGUIMIENTO.md`: (1) las curvas nunca vieron agosto, pero la ADOPCIÓN de W3 se
> decidió el 26-ago con 25 días visibles — septiembre es el primer test prospectivo limpio;
> (2) los cortes ya publicados se movieron al re-medir (25-ago S/13,484,959→S/13,398,433,
> -0.6%) porque `dts_mambu_loans_hist` se re-expresa para días pasados.
>
> **ADOPTADO: `P_ENTRADA` del Enfoque alfa pasa a calibrarse por SOLES** (decisión del
> usuario), cerrando lo que 18b había diagnosticado y 18e ya había adoptado en Recupero
> Oficial. Primero se verificó que **no hacía falta query nueva**: los dos motores usan la
> misma definición de entrada, y la query de 18e reproduce el `P_ENTRADA` del alfa en créditos
> (75,613/343,788 = 21.9941% contra 75,621/343,860 = 21.9918%). Misma población, dos unidades.
> Backtest de 3 variantes (`backtest_tarea19_tasa_soles.py`): rodar la tasa por conteo **no
> aporta** (10.26%→10.96%); el efecto es todo de la unidad. La correlación diaria es idéntica
> en las 3 (0.886) — es un cambio de NIVEL, no de forma, así que acá el error de cierre sí es
> la métrica pertinente.
>
> **EL HALLAZGO: la activación real viene cayendo, y la tasa mal definida la estaba tapando.**
> Las dos variantes derivan **~+10pp en paralelo** a lo largo de 8 meses — una deriva que
> sobrevive al cambio de tasa no puede ser de la tasa. Medido directo: la **activación real
> como % del calendario cae -0.46pp/mes** (20.99% en ene-mar → 18.50% en jun-ago, r=-0.77),
> mientras la tasa de entrada por soles **no tiene tendencia** (23.3%-27.2%) y el calendario
> **creció +90%** en 9 meses (S/47M→S/90M). La operación captura una porción decreciente de una
> cartera que crece rápido — señal de negocio, no defecto del modelo. Y la tasa por conteo, al
> ser 14.5% más baja de lo que su definición pide, **compensaba esa caída por accidente**:
> mismo patrón de bug 18 y de la capa fantasma. **Se adoptó igual, con el error subiendo en los
> últimos 3 meses**, por el mismo criterio con que se corrigió bug 18. Probado y descartado:
> acortar la ventana **no** sigue la caída (6m empeora las métricas diarias 0.886→0.876; 9m≈12m;
> jun/jul quedan en +8.2-9.3% con cualquiera) — **el protocolo de 12 meses queda confirmado**.
> El mismo mecanismo está en Recupero Oficial: su motor, corrido contra agosto (mes que no vio),
> da **+13.5%**. Detalle completo en `analisis_tarea19_activacion_decreciente.md`.
>
> **CÓDIGO Y DATOS NUEVOS:** 10 queries `tarea19_*.sql` (las `tarea18*` quedan congeladas como
> el registro de lo que produjo la meta de agosto), `generar_curvas_septiembre.py`,
> `meta_septiembre_capital_asegurado.py`, `meta_septiembre_recupero.py`,
> `backtest_tarea19_tasa_soles.py`, `armar_asignado_a_asegurado.py`, datos en `datos_tarea19/`.
>
> **ARTIFACT NUEVO (2026-09-02): [🎯 De asignado a asegurado](https://claude.ai/code/artifact/949ab3c2-52a3-447a-b3ce-52531e680fde)**
> — reescritura completa en la URL que ocupaba "De julio a agosto". Explica el enfoque desde
> cero (para alguien que no siguió el proyecto): la cadena **capital asignado → capital
> asegurado**, los tres ratios con nombre y denominador explícito, la diferencia entre antiguos
> (todo asignado el día 1) y nuevos (entran día a día por vencimientos), todo por tramo × banda
> × día de semana, con agosto cerrado y septiembre proyectado. Necesitó una query nueva
> (`tarea19_agosto_cadena_segmentada.sql`): las que existían daban el real activado pero no los
> **denominadores**, que es lo que faltaba para poder mostrar cada paso como una división.
> **Los otros dos artifacts se republicaron el mismo día** (Capital asegurado d4140b13,
> Proyectado vs. Real f80d3761), los dos conservando su URL.

> **2026-09-11 — CIERRE DE SESIÓN. Todo lo de las tareas 20/21/22 está commiteado; quedan 3
> frentes abiertos y ninguno bloquea al otro.** Esta sesión no tocó el motor ni las metas: la meta
> de septiembre sigue siendo **S/20,477,271** (alfa) y **S/3,928,776** (recupero), fijadas el 1-sep.
> Lo que se hizo fue **medir tres cosas que estaban asumidas** y dejar una variante construida sin
> adoptar. Los tres frentes abiertos, en orden de lo que rinde más:
>
> 1. ~~**SEGUIR SEPTIEMBRE CONTRA LA META.**~~ **Hecho el 2026-09-13** (`tarea19_real_septiembre.sql`
>    + `seguimiento_septiembre.py`): al 12-sep, −17.4% en alfa. Ver el bloque del 13-sep (tarde).
> 2. **Explicar la caída de activación** (−0.46pp/mes) — sigue medida y no explicada. Es el frente
>    de fondo, con el plan en 3 pasos en `PENDIENTES.md` tarea 19.
> 3. **Tarea 23**, pedida por el usuario y no empezada: proyectar *lo que realmente entra a gestión*,
>    excluyendo al que entra en mora sábado y se resuelve antes del lunes. Tiene una pregunta abierta
>    para el usuario antes de construirla (¿los feriados cuentan como días sin asignación?).
>
> **Lo que quedó pendiente de re-chequear y ahora YA SE PUEDE:** los **487 créditos (S/658,854)** que
> el 2-sep no aparecían en `vw_seguimiento_diario_cohorte_tramo` para 202609. Ese día la vista tenía
> solo 2 días de asignación cargados, así que no se pudo distinguir rezago de ausencia. Con 11 días
> corridos, re-correr `tarea22_solo_nuestro.sql` lo resuelve en una corrida.

> **2026-09-02 (tarde) — TAREA 22: RECONCILIADOS LOS "ANTIGUOS" DE SEPTIEMBRE CONTRA LA VISTA
> OFICIAL. La diferencia es UN DÍA de definición, no capital faltante.** El usuario comparó nuestro
> stock del 1-sep (**S/3,763,294**) contra `vw_seguimiento_diario_cohorte_tramo` 202609 TEMPRANA
> `antiguo` (**S/4,901,917**) y pidió explicar el −23.2%. Cuadre crédito a crédito, exacto por los
> dos lados: **en ambos 1,807 (S/2,952,721) · solo la vista 982 (S/1,949,196) · solo nuestro 592
> (S/810,573)**.
>
> **El 99.0% de "solo la vista" son 965 créditos (S/1,929,629) con `dias_mora_inicio = 1.0` exacto y
> `fecha_ancla = 2026-09-01` para todos**: cuotas vencidas el 31-ago que entraron en mora el 1-sep.
> La vista los llama `antiguo` porque congela el atributo en la **fecha de la primera asignación**;
> nuestro motor los manda al **calendario de nuevos con `dia_entrada = 1`**, porque al cierre de
> agosto tienen atraso 0 y no son stock (decisión explícita del motor unificado, que revirtió el
> parche `dia1_entrantes` de bug 12). **Ese capital SÍ está en la proyección, en nuevos.**
>
> **Se probó y se DESCARTÓ que fuera el punto ciego de bug 9/14:** sobreviven **2 créditos,
> S/4,872**. La migración a `dias_atraso_cuota` lo cerró. Del lado "solo nuestro": 103 créditos
> (S/150,086) escalados a ESPECIALIZADA (misma categoría que bug 14 ya conocía) y **487
> (S/658,854) que aún no aparecen en la vista — a reconfirmar con el mes más avanzado**, porque al
> 2-sep solo hay dos días de asignación cargados.
>
> **NO se tocó el motor.** Mover nuestro corte al 1-sep para cuadrar cambiaría quién entra al
> universo y obligaría a recalibrar las dos curvas y la tasa — se decide con backtest, no en
> abstracto (`CLAUDE.md`). Detalle completo en `reconciliacion_antiguos_septiembre.md`.

> **2026-09-02 (tarde) — TAREA 21: EL DOBLE CONTEO ANTIGUO/NUEVO, MEDIDO. Variante "primera
> entrada" entregada, NO adoptada.** Pregunta del usuario: como la gestión congela el atributo
> antiguo/nuevo al inicio del mes, un crédito que arranca en mora, cura y vuelve a vencer dentro del
> mes podría contarse dos veces (stock + calendario). **Resultado: son dos solapamientos y solo uno
> estaba vivo.** (A) *stock × calendario* **ya estaba excluido** (`not in stock_agosto`) y no es
> menor — S/3,311,800 en agosto y S/3,703,671 en septiembre, o sea el **92% de los créditos del
> stock** de septiembre tiene además un vencimiento en el mes. (B) *dos vencimientos del mismo
> crédito en el mes* **no** estaba excluido, pero es diminuto: **2 créditos, S/1,913 en agosto y
> S/6,546 en septiembre**.
>
> **Las reentradas SÍ son frecuentes, y es el dato que justifica (A):** en agosto **1,035 de los
> 3,608 créditos del stock (28.7%, S/1,659,914) curan y reentran dentro del mismo mes**. Ese
> comportamiento ya está absorbido por la curva de stock, que se calibra sobre esa misma población —
> contarlos además en el calendario de nuevos sería el doble conteo que la exclusión evita.
> Trayectorias día a día de 8 casos reales en `datos_tarea21/casos_reentrada_trayectorias.txt`.
>
> **La variante `meta_septiembre_primera_entrada.py`** (cada crédito cuenta una sola vez, por su
> primera entrada) da **S/20,411,584 contra S/20,412,734 del método vigente sobre la misma foto de
> datos: −0.0056%**. No cambia la meta de septiembre, que sigue siendo **S/20,477,271**. Se conserva
> igual porque el tamaño **depende del mes** (en 202603 y 202607 el calendario corre +12.7% y +12.9%
> sobre el universo deduplicado) y porque **alinea la definición del universo con la de `P_ENTRADA`**,
> que ya deduplicaba — media tarea 20 cerrada. **Pendiente real:** la curva de nuevos sigue
> calibrada sobre entradas sin deduplicar; falta una corrida de Athena para medirlo.
> Detalle en `PENDIENTES.md` tarea 21.

> **2026-08-26 (continuación 2) — TAREA 18e FASES A-D EJECUTADAS: motor completo de Recupero
> Oficial migrado a `dias_atraso_cuota`, respaldado con backtest de 7 meses. NO adoptado —
> recomendación armada, decisión pendiente del usuario.** Plan de 4 fases (tasa por soles,
> curva de stock en rebaje, curva de nuevos en rebaje, backtest) ejecutado completo en una
> sesión, reusando `motor_unificado.proyectar()` tal cual (genérico: no asume "activación" vs.
> "rebaje", solo cambian los insumos). `P_NO_PAGA_DIA0=13.38%` se calibra CONTANDO créditos
> pero `meta_agosto.py:110` la aplica multiplicando SALDO en soles — mismo error que 18b
> diagnosticó en Enfoque alfa, corregido desde el arranque acá (Fase A: tasa por soles
> **25.1924%**, +14.5% sobre la de conteo, mismo mecanismo que 18b).
>
> **Backtest de 7 meses (`backtest_tarea18e_recupero_oficial_dac.py`,
> `datos_tarea18e/backtest_recupero_oficial_dac.log`): magnitud media de error 7.99%** (sin
> refinamientos de forma — día de semana, factor de quincena, ventana rodante — todavía no se
> probaron para este motor). **Hallazgo principal, de universo, no de error:** el real
> capturado con `dias_atraso_cuota` es **148%-157% del real capturado con `dayslate`**
> (junio S/2.54M vs. S/1.71M; julio S/3.28M vs. S/2.09M) — **+48-57% de rebaje real que el
> motor vigente nunca ve**, mucho más que el +26-30% ya medido en créditos (Fase 1 de tarea
> 17). Mecanismo coherente con lo ya conocido: la razón `P_ENTRADA/P_NO_PAGA_DIA0=1.643×` ya
> anticipaba el salto en entradas, y bug 16 Fase 3 ya midió que esa población invisible a
> `dayslate` se activa 99.60% el mismo día — paga casi instantáneo, aportando rebaje ~1:1 de
> su saldo apenas se detecta. **Validado a nivel de caso** (`tarea18e_validacion_casos_
> fantasma.sql`): 10 créditos reales de julio confirman el mecanismo — `dayslate=0` el día
> exacto en que `dias_atraso_cuota` detecta la entrada, con rebaje real ese mismo día (varios
> cancelan el saldo COMPLETO, ej. S/7,749.55→S/0) — no es un artefacto de la query. **Nada
> tocó producción** — Recupero Oficial sigue con `dayslate`/13.38%. Detalle completo, con la
> tabla de 7 meses y la recomendación (no se adopta por mejora de error, se adopta si el
> universo queda más fiel — `CLAUDE.md`), en `PENDIENTES.md` tarea 18e.
>
> **Refinamiento de forma (v2) + ADOPCIÓN, mismo día (decisión del usuario).** Aplicado al
> motor de 18e el mismo tratamiento que ya está en producción en Capital Asegurado (ventana
> rodante de 12 meses sin leak para nuevos, día de semana, factor de quincena, factor de
> cierre real en stock — stock sigue con ventana FIJA, rodarla ya se probó y empeora). Reusa
> `curvas_crudas.py`/`curvas_crudas_stock.py` **sin tocar una sola línea** — el IPF que
> calibran no le importa si la masa observada es "activación" o "rebaje", así que calibra
> igual sobre una matriz cruda de rebaje nueva
> (`datos_tarea18e/curva_cruda_{nuevos,stock}_rebaje.csv`). **Correlación diaria 0.560→0.837**
> (mismo salto que el refinamiento análogo logró en Enfoque alfa, 0.611→0.886); error de
> cierre casi no se mueve (7.99%→7.83%, y es a propósito).
>
> **ADOPTADO: `SEGUIMIENTO.md` reemplazó la fila vigente de Recupero Oficial** (7 meses
> enero-julio con `dias_atraso_cuota`; los números viejos con `dayslate` quedan como
> referencia histórica en el mismo archivo). **`meta_agosto.py` NO se tocó** — mismo criterio
> que Capital Asegurado: no se cambia el motor de un mes EN CURSO a mitad de mes; agosto sigue
> con `dayslate`/13.38% hasta que cierre. **Pendiente, no bloqueante:** al cerrar agosto
> (31-ago), calibrar la meta de **septiembre** de Recupero Oficial con este motor (ventana
> `[202508,202607]`) — necesita un `meta_septiembre.py` nuevo; la maquinaria de calibración ya
> está lista en `backtest_tarea18e_recupero_oficial_v2.py`. Detalle en `PENDIENTES.md` tarea 18e.
>
> **Artifact [🎯 De julio a agosto](https://claude.ai/code/artifact/949ab3c2-52a3-447a-b3ce-52531e680fde)
> actualizado el mismo día** con el motor migrado: julio recalculado (+18.3%, antes +17.6% con
> `dayslate`), agosto sigue con el motor viejo a propósito, sección 4 y tabla de 7 meses
> ampliadas a los dos enfoques. Ver `armar_artifact_julio_agosto.py`.

> **2026-08-26 (continuación) — MOTOR UNIFICADO v3: FACTOR DE CIERRE REAL PARA STOCK ADOPTADO
> EN PRODUCCIÓN (tarea 18g, decisión del usuario).** Mismo mecanismo que 18f ya corregía para
> nuevos, ahora también en stock: el "cierre" de un mes es su **último día real** (28/29/30/31
> según corresponda), no un número de día fijo — `proyectar()` acepta un nuevo `f_dm_stock`
> opcional (`None` reproduce v2 al céntimo, verificado con regresión). Explica por qué
> **febrero (único mes de 28 días del test) era también el único mes donde stock fallaba
> fuerte**: su cierre real nunca caía en el grupo fijo "30/31". Efecto en el backtest oficial
> (7 meses): error de stock de febrero **-11.0%→-8.3%**, correlación diaria de stock
> 0.841→0.848 (0.818→0.856 en febrero), magnitud media de error **10.55%→10.26%**. **Se probó
> además rodar la ventana de calibración de stock (cerraría tarea 18c) y EMPEORA** (correlación
> 0.848→0.820) — se descarta, 18c sigue abierta. El reindex análogo para nuevos se probó pero
> **no se adoptó**: impacto marginal (0.886→0.888) frente al riesgo de tocar el esquema
> compartido que usa la meta de agosto ya publicada.
>
> **La meta de agosto (S/17,117,628) NO se tocó — verificado con regresión** (mismo avance
> +1.0% al 25-ago antes y después). `meta_agosto_capital_asegurado.py` sigue leyendo
> `curva_unificada_stock_seg.csv` sin el sufijo `_v3`; el factor de cierre vive aparte, en
> `curva_unificada_stock_seg_v3.csv` + `factor_dia_mes_stock.csv`, y lo usan el backtest
> oficial y, en su momento, la meta de septiembre — que todavía no se puede calibrar en su
> ventana propia [202508,202607] hasta que julio complete sus 31 días de seguimiento (recién
> el 31-ago). Detalle en `analisis_sesgo_nuevos_18b.md`, `analisis_tarea18g_cierre_real.md` y
> `PENDIENTES.md` tarea 18g.

> **2026-08-26 — MOTOR UNIFICADO v2 (W3) ADOPTADO EN PRODUCCIÓN, y el backtest oficial pasa
> de 4 a 7 meses con calibración rodante sin fuga (tareas 18a + 18f, decisión del usuario).**
> La curva de nuevos suma dos dimensiones que estaban medidas pero nunca probadas:
> - **Día de la semana del vencimiento**, abierto a los 6 días que existen (ninguna cuota vence
>   domingo — bug 21). El día 0 va de **18.7%** (venc. sábado, entra domingo) a **42.0%**
>   (venc. martes, entra miércoles); antes se aplicaba a todos los días el promedio ponderado,
>   34.3%, que no corresponde a ninguno.
> - **Factor por día del mes sobre el incremento diario**: quincena **1.0855**, días 30-31
>   **1.1848**, resto **0.9812**. Son **2 parámetros, no 31** — con uno por día sobreajusta
>   (correlación entre mitades disjuntas: +0.51). El 29 sale bajo en todas las ventanas, así
>   que es **fecha de pago**, no "fin de mes". Confirmación independiente: la curva de stock,
>   que sí ve el día del mes, tiene la quincena +12% sobre su propia tendencia local.
>
> **Efecto: la trayectoria diaria mejora fuerte, el cierre casi no se mueve — y es a propósito.**
> Correlación de incrementos diarios **0.611 → 0.886**, mejorando los **7 meses sin excepción**;
> error absoluto medio del incremento diario **-41%** (S/124K → S/73K). El error de fin de mes
> pasa de 10.43% a **10.55%** y no es el árbitro: la diferencia pareada entre variantes tiene un
> desvío 10x su media (harían falta ~1,050 meses para resolverla). **`avance_band` NO se colapsa
> a 3 buckets** — efecto máximo 0.008% sobre el total de un mes, y borra la resolución donde hay
> señal (la banda 70%+ corre +89.5% en agosto contra +21.9% de la 40-70%).
>
> **Protocolo nuevo: calibración de 12 meses rodantes + 7 meses de test (202601-202607).** Sale
> de medir la historia usable: antes de 202501 la cartera es <20% de la actual y la dispersión
> de la curva se duplica. Cuesta **0 queries por ventana** porque las curvas se arman desde una
> **matriz cruda** al grano `(fecha_entrada, banda, día_primer_pago)`. Con eso **18c queda
> resuelta para la curva de nuevos**: el leak medido es **0.10pp**, consistente con los
> 0.15-0.2pp de tarea 10. Falta rodar la curva de **stock** — por eso el nivel de error de
> ene-jun es optimista.
>
> **BACKTEST OFICIAL, 7 MESES:** ene **-11.2%**, feb **-19.6%**, mar **-14.1%**, abr **-11.9%**,
> may **-10.9%**, jun **-3.2%**, jul **-3.0%**. **Con 7 meses el sesgo de "nuevos" se ve más
> grande que con 4** (feb -21.6% en ese componente) — es el frente abierto principal (18b), y
> ninguno de estos refinamientos lo toca.
>
> **META VIGENTE DE AGOSTO: S/17,274,766 → S/17,117,628 (-0.9%).** Curvas calibradas
> **[202507, 202606]** — los 12 meses completamente observados al 1-ago; julio queda afuera a
> propósito porque al fijar la meta sus cohortes no tenían los 31 días de seguimiento. **Avance
> al 21-ago: -0.7%** sobre lo proyectado al mismo día; **al 25-ago: +1.0%** (real S/13,484,959,
> 78.8% de la meta).
>
> **Código nuevo:** `curvas_crudas.py` (calibración desde la matriz cruda, cualquier ventana o
> segmentación sin re-consultar), `generar_curvas_produccion.py`, `backtest_tarea18a.py` y
> `backtest_tarea18f.py` (las 7 variantes que decidieron W3), `armar_proyectado_vs_real.py` y
> `armar_capital_asegurado.py` (regeneran los datos de los artifacts), `motor_unificado.py` **v2**,
> `meta_agosto_capital_asegurado.py` **v8**, `backtest_capital_asegurado_unificado.py` reescrito a
> 7 meses rodantes. Queries: `tarea18f_curva_cruda.sql`, `tarea18_ventana_calibracion.sql`,
> `tarea18a_curva_nuevos_dow{,7}.sql`, `tarea18_{calendario,stock_pob,real_stock,real_nuevos}_7m.sql`.
> Curvas en `datos_capital_asegurado/curva_unificada_nuevos_dow_seg.csv` + `factor_dia_mes.csv`.
> **Los 2 artifacts republicados** (URLs conservadas). Detalle en `PENDIENTES.md` tareas
> 18a/18c/18f y `BUGS.md` bugs 21 y 22.

> **2026-08-25 (continuación) — MOTOR UNIFICADO ADOPTADO EN PRODUCCIÓN. LA CAPA FANTASMA
> SE ELIMINÓ (tarea 17 Fase 4, decisión del usuario).** El Enfoque alfa pasa de 3 componentes
> (stock + nuevos + fantasma, calibrados con `dayslate`) a 2 (stock + nuevos, calibrados con
> `dias_atraso_cuota`).
> - **Una sola tasa:** `P_ENTRADA = 21.9918%` (75,621/343,860, ago25-may26) reemplaza a
>   `P_NO_PAGA_DIA0 = 13.38%` + `P_FANTASMA = 8.6163%`. La suma anterior daba 21.9963% —
>   0.005pp de diferencia: **la masa siempre estuvo bien, lo que estaba mal era el reparto.**
> - **Una sola curva de nuevos, que arranca en el DÍA 0.** La ex-población fantasma es el
>   día 0 de esa curva (36.97% banda a → 30.61% banda d), en vez de una tasa plana ciega a
>   `avance_band`. Ese era el defecto real del parche: mismo 8.62% para todas las bandas.
> - **Un solo calendario, indexado por DÍA DE ENTRADA** (= vencimiento + 1), en vez de dos.
> - **4 clases de bug quedan imposibles por construcción:** bug 12 (`dia1_entrantes`), bug
>   14/17 (hueco de frontera de mes), bug 18 (índice corrido) y bug 20 (denominador de abril).
>
> **Backtest (4 meses):** abril **-12.6%**, mayo **-8.7%**, junio **-2.6%**, julio **-5.0%**
> — magnitud media **7.22%** contra 6.20% de la arquitectura anterior (con bug 20 corregido).
> **El error empeora ~1pp y se adoptó igual**, por el "Principio de interpretación del error"
> de `CLAUDE.md`: el cambio corrige quién entra al universo y cómo se mide. El parche plano
> **enmascaraba** el sesgo de "nuevos" por ser sistemáticamente generoso (sobreestimaba justo
> donde nuevos subestimaba); ahora los 4 meses subestiman con **signo constante**, que es una
> señal de negocio a explicar y no un error que cambia de signo según el mes.
>
> **META VIGENTE DE AGOSTO: S/16,257,325 → S/17,274,766 (+6.3%).** Casi todo el movimiento es
> el stock: con `dias_atraso_cuota` el stock al cierre de julio es **30.2% mayor**
> (S/5.81M vs. S/4.46M), consistente con la cobertura ya medida en Fase 1 (78.4% → 98.6%).
> El **real casi no se mueve** (S/11,600,930 vs. S/11,620,780 al 21-ago, -0.2%): es la misma
> realidad de negocio, medida sin partir la población en tres. **El avance al 21-ago pasa de
> +4.8% a -0.3%** (al 24-ago: -1.4%) — agosto viene en línea, no adelantado; el "+4.8%" era
> en buena parte un artefacto del reparto entre nuevos y fantasma.
>
> **Código nuevo:** `motor_unificado.py` (proyector compartido),
> `backtest_capital_asegurado_unificado.py` (4 meses en una corrida + series diarias en
> `datos_backtest_unificado/`), `meta_agosto_capital_asegurado.py` **v7**, curvas en
> `datos_capital_asegurado/curva_unificada_{stock,nuevos}_seg.csv`, 9 queries
> `tarea17_fase4_*.sql`, datos en `datos_tarea17_fase4/`. Los 4 scripts de backtest viejos
> quedan como referencia histórica. **Los 2 artifacts republicados** (URLs conservadas).
> Detalle completo en `BUGS.md` bug 16 (Fase 4) y bug 20.

> **PROMPT DE HANDOFF VIGENTE:** [`prompt_handoff_2026-09-02.txt`](prompt_handoff_2026-09-02.txt)
> — orden de lectura, dónde está el proyecto, qué está resuelto y no hay que re-probar, lo que
> sigue en orden, el **ciclo mensual** para fijar la meta del mes siguiente, y las trampas
> conocidas. *(`prompt_handoff_2026-08-26.txt` queda como registro: hablaba de "cerrar agosto" y
> del plan de 18e, los dos ya hechos.)*

> **LO QUE SIGUE (2026-09-01, `PENDIENTES.md` tarea 19):** (1) **republicar los 3 artifacts**
> desactualizados por el cierre de agosto y la meta de septiembre — lo único con fecha; (2)
> **explicar la caída de activación** (-0.46pp/mes) — está medida, no explicada, y es el frente
> principal: capacidad de gestión vs. composición de cartera; (3) **seguir septiembre** contra
> la meta de S/20,477,271, que es el primer test prospectivo limpio del proyecto y lleva el
> caveat de correr ~10% alta; (4) 18c (rodar la curva de stock) sigue sin resolver. El bloque
> de abajo es el estado de tarea 18 al 26-ago, que quedó cerrada salvo 18c.

> **LO QUE SIGUE (tarea 18, `PENDIENTES.md`):** (a) ✅ **CERRADA Y ADOPTADA** (W3);
> (b) ✅ **MEDIDA 2026-08-26** (diagnóstico, no ajuste — ver `analisis_sesgo_nuevos_18b.md`):
> el ~78% de la magnitud del sesgo de "nuevos" (5 de 6 meses medibles) es que `P_ENTRADA` se
> calibró por CONTEO de créditos pero se aplica sobre SOLES del calendario — la tasa real
> ponderada por soles corre 24-27% contra 21.99% fijo, r=-0.93 con el error. Además, febrero
> (único mes de 28 días) es el único mes donde stock también falla fuerte porque el modelo
> indexa "fin de mes" por día calendario (30/31) y un mes de 28 días nunca llega ahí — el 28-feb
> solo explica 79.3% del gap de stock del mes. La hipótesis de "tamaño del calendario" del
> handoff se descarta (r=+0.48, mucho más débil que la tasa real). Nada de esto se llevó a
> producción; (c) ✅ resuelta para la curva de nuevos (leak 0.10pp medido) — falta rodar la
> curva de **stock**, que sigue fija y hace optimista el nivel de error de ene-jun (y es
> además donde vive el mecanismo de febrero de arriba); (d) ✅ **REHECHO 2026-08-26** — artifact
> reescrito sobre motor v3, capa fantasma retirada de todo el texto, republicado en la misma
> URL; (e) ✅ **EJECUTADA Y ADOPTADA 2026-08-26 (continuación 2)** — las 4 fases del plan
> corridas en una sesión (tasa por soles, curvas de stock/nuevos en rebaje, backtest),
> refinadas con el mismo tratamiento de forma que (a)/(f)/(g) (ventana rodante, día de semana,
> quincena, cierre real en stock) y adoptadas en `SEGUIMIENTO.md` — `meta_agosto.py` no se
> tocó (mes en curso), la meta de septiembre migra al cerrar agosto. Ver `PENDIENTES.md` tarea
> 18e; (f) ✅ **CERRADA Y ADOPTADA** (el factor de quincena ES 18f); (g) ✅ **ADOPTADA
> PARCIALMENTE 2026-08-26** (motor v3, ver bloque de arriba y `analisis_tarea18g_cierre_real.md`):
> formalizó el reindex por cierre real de (b) contra el walk-forward de 7 meses. **Stock +
> factor de cierre: adoptado en producción** (mejora modesta y dirigida — febrero: err. stock
> -11.0%→-8.3%, corr. diaria 0.818→0.856 — no lo resuelve del todo). Nuevos reindexado casi no
> se mueve (el grupo fijo {30,31} ya capturaba la mayor
> parte de la señal). **Rodar además la ventana de stock (que resolvería (c)) EMPEORA las
> métricas diarias** — no sale gratis como en nuevos, stock es el componente de mayor varianza
> muestral; (c) queda abierta, necesita su propio enfoque, no se adoptó. El nuevos reindexado
> tampoco se adoptó (impacto marginal, no justifica el riesgo). La meta de agosto no se tocó.

> **2026-08-25 (continuación) — BUG 20, encontrado por el diagnóstico de Fase 4 y resuelto
> por construcción:** el calendario de fantasma de ABRIL excluía `entradas_reales` del
> denominador; ningún otro mes lo hacía y `P_FANTASMA` se calibraba sobre un denominador que
> NO las excluía — tasa y denominador de distinta definición, mismo patrón de bug 10.
> Calendario corregido: S/43,576,331 → **S/52,115,389** (+19.6%), validado contra la
> reconstrucción independiente de Fase 4 (S/51,809,606, 0.6% de diferencia explicada por la
> regla de exclusión de stock). **El abril de la arquitectura anterior pasa de -19.0% a
> -13.4%**, y deja de ser el outlier que parecía. Con el motor unificado el bug desaparece:
> ya no hay dos calendarios que mantener sincronizados.


> **2026-08-25 (continuación) — BUG 20 NUEVO, encontrado por el diagnóstico de Fase 4: el
> calendario de fantasma de ABRIL excluye `entradas_reales` del denominador; ningún otro mes
> lo hace y `P_FANTASMA` se calibra sobre un denominador que NO las excluye.** Tasa y
> denominador de distinta definición — mismo patrón de bug 10. Calendario corregido:
> S/43,576,331 → **S/52,115,389** (+19.6%), validado contra la reconstrucción independiente de
> Fase 4 (S/51,809,606, diferencia 0.6% explicada por la regla de exclusión de stock).
> **Impacto en el número oficial de abril: proyectado S/10,766,352 → S/11,502,103, error
> -19.0% → -13.4%.** NO corregido en `SEGUIMIENTO.md` todavía — decisión del usuario, y queda
> resuelto por construcción si se adopta Fase 4. Si NO se adopta, hay que aplicarlo igual.

> **2026-08-25 — TAREA 17 FASE 3 EJECUTADA: resultado inesperado, la activación instantánea
> de `P_FANTASMA` ya era correcta, NO hace falta una curva multi-día.** Calibrado con 2
> ventanas a pedido del usuario (12 y 6 meses, no la historia completa 2023-10-17+ del plan
> original — el portafolio de esa época es ~1000x más chico que el actual). Con la definición
> ampliada de "fantasma" (vía `dias_atraso_cuota`, no solo pagos exactamente 1 día tarde), la
> activación ponderada en el día 0 es **99.60%** (12m), 99.49%-100% por segmento (6m) — el
> día de semana del vencimiento y `avance_band` no cambian la forma. Lo que sí varía por día
> de semana es la TASA de entrada (semana 9.08%/9.36% vs. fin de semana 5.67%/6.31%,
> 12m/6m) — dirección opuesta al hallazgo de fin de semana de Fase 1, con mecanismo distinto
> (`dayslate` corre 7 días a la semana, a diferencia de la tabla de asignaciones). Tasa
> agregada nueva (8.617%/8.923%) casi idéntica a la actual (8.5524%). Se encontró y corrigió
> un bug propio en el camino (saldo de referencia mal anclado — ver bug 16, `BUGS.md`).
> **Sin cambios a producción todavía** — recomendación pendiente de decisión del usuario:
> actualizar la tasa (con o sin segmentar por día de semana), verificado con backtest antes
> de adoptar. Detalle completo en bug 16 (`BUGS.md`) y tarea 17 (`PENDIENTES.md`).

> **2026-08-24 (continuación 7) — DECISIÓN DEL USUARIO: la curva debe representar TODA la
> mora que ocurre, no solo la que el negocio gestiona. FASE 2 (montos) DE TAREA 17
> EJECUTADA Y CERRADA.** Resuelve la pregunta conceptual que dejó abierta Fase 1 — el
> universo correcto para calibrar de acá en adelante es `dias_atraso_cuota`. Verificado con
> 2 chequeos antes de aceptar: (1) un crédito que vence sábado y sigue sin pagar entra
> oficialmente como "nuevo" el lunes — confirmado 100% con 259 casos reales; (2) la forma de
> la curva sí difiere por día de semana del vencimiento — fin de semana paga ~2x más rápido
> en el día 1 desde la entrada (30.96% vs. 14.84%), porque sin gestión activa el sábado más
> créditos "se escapan" a mora pero pagan apenas los llaman el lunes (hipótesis del usuario,
> reemplaza la mía de rezago de procesamiento, descartada). **Implicación para Fase 3: día de
> semana del vencimiento pasa a ser segmentador de la curva.** También: corrección de wording
> ("días de gestión" → "días calendario", el modelo ya estaba bien, solo mal nombrado) y
> observación del usuario de que el segmentador `avance_band` (4 buckets) simplifica a 3
> (40-70% y 70%+ no se separan bien). **Fase 2 (soles):** cobertura del universo oficial sube
> de 75.9%→**97.8%** (julio) y 84.2%→**99.3%** (agosto) al usar `dias_atraso_cuota`; el hueco
> baja de S/4.22M→S/390K (julio) y S/2.37M→S/101K (agosto). En el camino se detectó y
> corrigió un bug propio (saldo de fin de mes en vez de saldo al momento de entrada),
> verificado 99.94% de coincidencia tras el fix. **Sin cambios a producción todavía** —
> siguiente paso es Fase 3 (curva real, reemplaza `P_FANTASMA` plano). Detalle completo en
> bug 16 (`BUGS.md`) y tarea 17 (`PENDIENTES.md`).

> **2026-08-24 (continuación 6) — TAREA 17 FASE 1 (cantidad) EJECUTADA Y CERRADA: el
> mecanismo horario propuesto por el usuario se confirma (~97% de reducción del punto ciego
> de `dayslate`), pero aparece un mecanismo HERMANO no anticipado, más grande — el fin de
> semana.** `dts_asignaciones_gestiones_cobranza` no tiene NINGUNA fila sábado/domingo — el
> negocio asigna de lunes a viernes solamente. `dias_atraso_cuota`, al reconstruir día por
> día, detecta episodios de mora reales pero breves que nacen y se resuelven DENTRO de un fin
> de semana, invisibles para la asignación semanal-hábil — verificado en 4 subpoblaciones
> (91-100% de coincidencia). **Cobertura del universo oficial TEMPRANA: 70.4%→96.3% (julio),
> 78.4%→98.6% (agosto)** al cambiar de `dayslate` a `dias_atraso_cuota`. El punto ciego
> específico baja de 3,130→87 (julio) y 2,093→63 (agosto). Queda un residual sin forzar
> explicación (150 créditos, <1% del universo, patrón mixto) y una pregunta conceptual
> abierta para Fase 3: si `dias_atraso_cuota` ve mora que el negocio nunca llega a gestionar
> (por su propio ciclo semanal), ¿la curva debe representar TODA la mora o solo la
> gestionable? **Sin cambios a producción todavía** (Fase 1 es solo cantidad/créditos, no
> montos) — Fase 2 (soles) es el siguiente paso, no ejecutada. Queries nuevas copiadas al
> repo (a diferencia de bug 16 original, que se perdió en scratchpad):
> `tarea17_universo_dias_atraso_cuota.sql`, `tarea17_fase1_mecanismo.sql`,
> `datos_tarea17_universo/`. Detalle completo en bug 16 (`BUGS.md`) y tarea 17
> (`PENDIENTES.md`).

> **2026-08-24 (continuación) — BUG 18 CORREGIDO Y DESPLEGADO.** Índice de la curva de
> nuevos cambiado a `dias_desde_entrada = d - dd - 1` en los 4 backtests y en la meta de
> agosto; capa fantasma intacta (verificado: stock y fantasma idénticos al céntimo en los 4
> meses — en `_junio.py` y `meta_agosto_*` hubo que desacoplar el guard que fantasma
> compartía con la curva). Resultados nuevos: abril **-19.2%**, mayo **-6.8%**, junio
> **+1.6%**, julio **-3.3%** — exactamente los pre-medidos. **Meta vigente de agosto:
> S/16,410,194 → S/16,211,015** (-1.2%); el avance al 21-ago pasa de +2.6% a **+5.1%** sobre
> lo proyectado al mismo día. `SEGUIMIENTO.md`, `ESTADO.md`, `BUGS.md` (bug 18 cerrado),
> `PENDIENTES.md` (tarea 13 cerrada) y los 2 artifacts actualizados.
> **Lo que esto deja abierto — y es el punto:** sin el bug compensando, el sesgo de "nuevos"
> queda expuesto en su tamaño real (**-27.3% abr, -20.1% may, -8.0% jun, -19.2% jul**,
> subestima en los 4 sin excepción). Eso **se explica** (volumen/mix/gestión — ver
> `analisis_volumen_efectividad_agosto.md` y tarea 9), no se ajusta con una constante.

> **2026-08-24 (continuación 2) — TAREA 14 CERRADA: los 302 créditos sin asignación (bug 19)
> se explican con datos, y son dos mecanismos distintos.** Hipótesis del usuario (pagos que
> resuelven el crédito antes de que el proceso de asignación del día los alcance),
> verificada por separado en stock y nuevos:
> - **~69 créditos (50 stock + 19 nuevos, 22.8%) confirman la hipótesis, limpio.** El stock
>   pagó el **01-ago** (día 1 del mes) sin excepción; los 19 nuevos con salida observada
>   salieron de mora en exactamente 1 día el **100%** de las veces (vs. 37.6% de baseline).
> - **232 créditos (77.2% del total) son OTRA cosa — censura por el corte de fecha del
>   propio ejercicio de validación**, no un hallazgo de negocio: entraron en mora el
>   **23-ago**, el último día de la ventana de asignaciones usada, y simplemente no tuvieron
>   tiempo de aparecer todavía.
> No cambia la lectura de bug 19 (el hueco del 21.6% y la contaminación asimétrica
> 15.6%/5.8% siguen de pie). Detalle y queries en bug 19 (`BUGS.md`) y
> `tarea14_no_aparece_asignaciones.sql`.

> **2026-08-24 (continuación 3) — TAREAS 15/16 MEDIDAS con julio 2026 (único mes cerrado con
> asignaciones completas): el gap real por componente es grande, pero el efecto agregado es
> chico.** ESPECIALIZADA/RECOVERY activa capital muchísimo menos que TEMPRANA gestionado —
> stock 9.6% vs. 64.7% (-55.1pp), nuevos 11.6% vs. 73.0% (-61.4pp), gap con sentido de
> negocio (son los casos que no respondieron a gestión temprana). **Pero en el agregado
> ("todos" vs. "solo TEMPRANA") el movimiento es chico** — stock 64.6% vs. 64.7% (-0.1pp),
> nuevos 71.5% vs. 73.0% (-1.5pp) — porque ESPECIALIZADA/RECOVERY es poco volumen (6.5%
> stock, 0.7% nuevos) y su arrastre se compensa con otros buckets. **Recomendación (no
> decisión, sigue siendo del usuario): no tocar la calibración de producción por esto ahora**
> (mismo criterio que tarea 10, impacto chico) — documentar el gap real y esperar a que
> importe en la práctica (ej. si el volumen de escalados crece). Detalle completo, el bucket
> residual sin explicar y la nota sobre grupo control (no apareció en esta partición de
> julio) en bug 19 (`BUGS.md`) y `tarea15_16_sesgo_gestionado_julio.sql`.

> **2026-08-24 (continuación 4) — VALIDACIÓN DEL UNIVERSO EN CAPITAL (soles, no solo
> créditos), julio Y agosto, a pedido del usuario.** Pregunta distinta de tareas 14/15/16:
> ¿la lógica con la que reconstruimos el universo en meses históricos (sin tabla de
> asignaciones) devuelve el mismo CAPITAL que la tabla formal, en un mes donde sí la
> tenemos? **Resultado: nuestro universo captura 87.6% (julio) / 89.1% (agosto) del capital
> oficial TEMPRANA** — mejor cobertura en soles que en créditos (80.7%/83.6%), porque lo que
> falta son créditos de saldo relativamente chico. **El hueco no es nuevo ni misterioso: es
> 95-100% el mismo bug 9 ya documentado** (punto ciego de `dayslate`) + reenganches
> (exclusión correcta). La capa fantasma ya suma esta población aparte — el hueco no es
> "capital perdido del modelo", es capital modelado con un mecanismo distinto (tasa plana,
> no curva). **Lo que sigue sin resolver** (punto original de tarea 15): la curva de
> "nuevos" se calibra solo sobre el 88% dayslate-visible — si esa población tiene una FORMA
> de activación distinta, no solo un nivel distinto, eso no se captura con una tasa plana.
> Se corrigió también un gap real en la query V1 original de bug 19 (`saldo_nuestro` para
> "solo oficial" salía en cero por construcción — nunca se supo cuántos soles representaba
> el hueco). Detalle completo, tabla por categoría y casos individuales (23,502 filas con
> `id_ihfintech_loan` completo) en bug 19 (`BUGS.md`), `validacion_universo_capital_julio_
> agosto.sql` y `datos_validacion_universo_capital/`.

> **2026-08-24 (continuación 5) — REPLANTEO: el hueco de bug 9 tiene una explicación
> MECÁNICA concreta (horario), y esto REVIVE bug 16. PLANIFICADO en 4 fases, NADA ejecutado
> todavía — es el primer paso de la sesión siguiente.** El usuario propuso el mecanismo: el
> snapshot de `dts_mambu_loans_hist` corre ~10pm; un crédito que entra en mora
> (vencimiento+1) y paga esa misma tarde (después de las 9am, cuando ya se armó la
> asignación del día, pero antes de las 10pm) queda asignado a TEMPRANA en la tabla oficial
> pero invisible para `dayslate`. Verificado a nivel de caso: crédito
> `1f49097f-3bb7-4886-8a22-7ca10a5f5704`, cuota vencida 2026-07-07, pagada
> **2026-07-08 12:39:41** — encaja exacto. **3 correcciones del usuario al plan, ya
> incorporadas en tarea 17 (`PENDIENTES.md`) y en la actualización de bug 16 (`BUGS.md`):**
> (1) mirar solo la cuota VIGENTE de cada crédito (usar `dias_atraso_cuota`, que ya resuelve
> eso, no `dts_cobranza_creditos_cuotas` directo); (2) el objetivo es identificar y explicar
> diferencias, **no reducirlas** — mismo principio de `CLAUDE.md` aplicado a la
> reconciliación de universo; (3) el propósito real es validar si `dayslate` es ciego a esta
> población en **toda la historia de calibración**, no solo julio/agosto — esos meses son
> el banco de pruebas porque son los únicos con tabla de asignaciones. **Plan en 4 fases:**
> cantidad (créditos) → montos (soles) → curva real para reemplazar `P_FANTASMA` (tasa
> plana, tarea 7/bug 14) → evaluar recalibrar toda la producción con `dias_atraso_cuota`.
> Detalle completo en tarea 17 (`PENDIENTES.md`) y bug 16 (`BUGS.md`, actualización).

> **2026-08-24 — DOS HALLAZGOS ESTRUCTURALES a partir de un punto conceptual del usuario:
> el índice de la curva de nuevos está corrido 1 día (bug 18, **ya corregido — ver bloque
> de arriba**) y el universo de calibración no coincide con las reglas de ejecución del

> **2026-08-24 — DOS HALLAZGOS ESTRUCTURALES a partir de un punto conceptual del usuario:
> el índice de la curva de nuevos está corrido 1 día (bug 18, **ya corregido — ver bloque
> de arriba**) y el universo de calibración no coincide con las reglas de ejecución del
> negocio (bug 19, sin corregir).**
>
> **El punto de partida (usuario):** *"la fecha de vencimiento es el último día que el
> cliente puede pagar sin entrar en mora — entra en mora si no paga ese día, sino
> después"*. De ahí: **entrada en mora = vencimiento + 1**, y por eso el día 1 del mes solo
> puede tener antiguos (ya era bug 12, aplicado en Enfoque alfa).
>
> 1. **Bug 18 — índice de la curva corrido 1 día, VERIFICADO con datos.** El gap
>    vencimiento→`dayslate`=1 es exactamente 1 día en el **99.99%** de los casos
>    (7,144/7,145, julio 2026). La curva se calibra desde `fecha_entrada` (día 1 de la curva
>    = vencimiento+2) pero los proyectores la indexan desde `fechavencimiento` — aplican
>    `curva[k]` donde corresponde `curva[k−1]`. Impacto medido en los 4 meses: abril
>    -17.6%→**-19.2%**, mayo -4.4%→**-6.8%**, junio +2.65%→**+1.6%**, julio -0.2%→**-3.3%**.
>    **Corregirlo EMPEORA el error agregado y aun así hay que corregirlo** — estaba
>    compensando el sesgo ya conocido de que "nuevos" subestima. La capa fantasma NO está
>    afectada (no usa curva).
>    **Hipótesis descartada con datos en el camino:** la tasa `13.38%` NO tiene el mismo
>    problema de frontera de mes — recalibrada emparejando por fecha exacta da **13.5688%**
>    vs. 13.4488% del criterio original, solo +0.9% relativo.
> 2. **Bug 19 — el universo de calibración no cuadra con la ejecución real.** Ejercicio
>    diseñado por el usuario: reconstruir agosto con el método histórico **sin mirar la tabla
>    de asignaciones** y recién después cruzarlo contra la ejecución real (corte 23-ago, vía
>    `aux02`). Resultado: nuestro universo 8,385 créditos vs. oficial TEMPRANA 10,035 —
>    **falta el 21.6%** que el negocio sí gestiona (2,093 punto ciego `dayslate` + 76
>    reenganches) y **sobra población que el negocio NO gestiona, de forma asimétrica**:
>    stock **15.6%** no gestionado vs. nuevos **5.8%**. Queries reproducibles en
>    `validacion_universo_ejecucion.sql` (V0/V1/V2).
>    **Acotado por el usuario:** el grupo control solo existió en julio y parte de agosto
>    2026 → **NO contamina las curvas históricas** (calibradas `202504`-`202606`). Quedan
>    como incoherencias estructurales reales: el punto ciego de `dayslate` (~21%, la curva
>    está calibrada sobre una población sin los mejores pagadores) y los escalados a
>    ESPECIALIZADA/RECOVERY (6.5% del stock, sí existen en todo el histórico).
> 3. **Principio nuevo en `CLAUDE.md`, aportado por el usuario:** *"la proyección ES la meta
>    del mes; el error mide si la ejecución va de acuerdo al histórico esperado — las
>    diferencias se explican, no se huye de ellas"*. Nunca ajustar constantes/índices para
>    reducir el error del backtest; sí corregir universo y reglas aunque el error suba.
>
> **Plan acordado para la sesión siguiente** (detalle en `PENDIENTES.md` tareas 13-16 y en
> "Prompt de continuación" abajo): (1) corregir bug 18 — es error puro y toca la meta
> vigente; (2) investigar los 302 créditos sin asignación; (3) recién ahí decidir sobre las
> incoherencias de universo, que requieren decisión del usuario sobre qué debe representar
> la curva.

> **2026-08-23 (continuación, sesión nueva) — commit del trabajo pendiente, caveat de
> `grupo_control` resuelto, backtest extendido a 4 meses (abril agregado).** A pedido del
> usuario: (1) se commiteó todo lo acumulado desde `43ad543` (el bloque completo descrito
> abajo, "2026-08-22/23" en adelante) — commit `60390dc`. (2) El usuario confirmó que
> `grupo_control` es **aleatorización estratificada por riesgo y monto** (no regla de
> negocio) — resuelve el caveat de causalidad abierto en `analisis_volumen_efectividad_
> agosto.md` y bug 16 de `BUGS.md`; la conclusión de esa sección ("el exceso es volumen, no
> efectividad de gestión") queda con soporte causal, no solo correlacional. (3) Abril 2026
> agregado como **cuarto mes cerrado** del backtest de capital asegurado
> (`backtest_capital_asegurado_abril.py`, `enfoque_capital_asegurado_backtest_abril.sql`):
> error **-17.6%** (stock +7.9%, nuevos -24.1%, fantasma -18.9%) — el más grande de los 4
> meses. Con los 4 (abril -17.6%, mayo -4.4%, junio +2.65%, julio -0.2%), **"nuevos"
> subestima en los 4 sin excepción** — señal cada vez más consistente con sesgo real en
> `P_NO_PAGA_DIA0=13.38%`, no solo varianza. A diferencia de mayo/julio, esta vez la query
> del calendario de fantasma frontier-adjusted (bug 17) quedó copiada al repo desde el
> inicio, no solo en el scratchpad de la sesión. Ver `SEGUIMIENTO.md` (fila de abril) y
> `PENDIENTES.md` tarea 9 para el detalle completo. **Pendiente que deja esto:** confirmar
> si marzo 2026 sostiene la magnitud de abril o si es un outlier puntual (abril tiene signo
> distinto a mayo/junio/julio en fantasma y stock, no solo en magnitud); actualizar el
> artifact [📈 Proyectado vs. Real](https://claude.ai/code/artifact/f80d3761-732c-483b-99ad-d85c95c896aa)
> con la tabla ampliada a 4 meses (todavía no se tocó). Ítem 3 original (reestructurar
> `curvas_matriz_alfa.html`) sigue pendiente de las observaciones del usuario.

> **2026-08-22/23 (continuación) — 3 artifacts nuevos/reconstruidos, backtest extendido a 3
> meses, número oficial de julio corregido, tarea 10 cerrada.** A pedido del usuario, en
> orden:
> 1. **Artifact [🧮 Cómo se calcula 13.38%](https://claude.ai/code/artifact/8f7ba3ea-de3e-4bdb-84dd-9105eda2a637):**
>    reconstruye `P_NO_PAGA_DIA0` paso a paso (embudo elegibles/entradas, 2 créditos reales,
>    desglose de 10 meses) más, agregado después, **la curva diaria de 365 días** (pedido
>    explícito del usuario) — reveló un patrón semanal limpio (lunes sin cuotas vencidas,
>    domingo se corre a lunes; martes absorbe el fin de semana, 2-6× el volumen normal).
>    Verificación de robustez: el deduplicado de bug 11 mueve la tasa +0.07pp (13.38%→13.45%,
>    nada), y ventanas de 6/10/12 meses dan 13.19%/13.45%/13.38% — la tasa no está
>    desactualizada.
> 2. **Extensión del backtest a mayo 2026** (tercer mes cerrado) — error -4.4% (stock -0.8%,
>    nuevos -14.9%, fantasma +7.4%). Al reconstruirlo se encontró y corrigió un bug propio
>    (el calendario de fantasma necesita su propio rango frontier-adjusted, no el mismo que
>    "nuevos" — ver bug 17 en `BUGS.md`) que también reveló que **el número oficial de julio
>    estaba mal** (`jul_calendario.csv`, un archivo huérfano, corría 7.9% alto) — el usuario
>    confirmó adoptar el número reconstruido: **julio pasa de +2.17% a -0.2%**
>    (stock -1.9%, nuevos -12.2%, fantasma +15.4%). Con los 3 meses, **"nuevos" subestima
>    sin excepción** (mayo/junio/julio), consistente con el hallazgo de volumen de agosto.
> 3. **Tarea 10 (`PENDIENTES.md`) cerrada:** curvas recalibradas excluyendo estrictamente
>    mayo/junio/julio de su propia calibración — movimiento de solo 0.15-0.2pp en los 3
>    meses, no se adopta (impacto no lo justifica), pero confirma que el modelo no depende
>    de la fuga.
> 4. **Artifact [📈 Proyectado vs. Real](https://claude.ai/code/artifact/f80d3761-732c-483b-99ad-d85c95c896aa):**
>    explica el mecanismo de 3 motores (stock+nuevos+fantasma) con julio y mayo día a día,
>    la tabla de los 3 meses, y la prueba de robustez de las curvas.
> 5. **Tarea 2 (`PENDIENTES.md`) cerrada — `capital_asegurado.html` reconstruido por
>    completo**, no un simple refresco (el archivo predataba bug 12 Y capa fantasma): curvas
>    actuales, backtest de 3 meses, avance en vivo de agosto (corte 21-ago, +2.7%) y
>    segmentado, 5 créditos de ejemplo nuevos (agosto real). URL vieja ya no existía (mismo
>    patrón que `curvas_matriz_alfa.html`) — republicado en
>    [🔒 Capital asegurado](https://claude.ai/code/artifact/d4140b13-4017-4313-b140-7d8f6356d5d7).
>
> **Pendientes que deja esta sesión** (detalle completo en "Prompt de continuación" abajo):
> extender el backtest más allá de 3 meses (tarea 9, `PENDIENTES.md` — el usuario pidió
> explícitamente seguir corriendo backtest); explicar la causa de fondo de por qué
> `jul_calendario.csv` corría alto (pista sin confirmar: reenganches con saldo stale); ítem 1
> original (reestructurar `curvas_matriz_alfa.html`) sigue sin tocar.

> **2026-08-22 (continuación, sesión nueva) — volumen vs. efectividad (pendiente de bug 16)
> ejecutado: el exceso Real>Proyectado de agosto es volumen, no efectividad de gestión.**
> A pedido del usuario, se comparó proyectado-a-la-fecha vs. real-a-la-fecha (mismo corte,
> 21-ago, no un mes cerrado), desagregado por segmento, y se corrió la prueba pendiente de
> bug 16: tasa de activación de `grupo_control` (no gestionado) vs. gestionado, mismo corte.
> Total: **+2.61%** (stock +1.54%, nuevos +24.21%, fantasma −19.78%, este último parcialmente
> timing — verificado, no un hueco real). Descompuesto el exceso de "nuevos" en volumen
> (+26.3% en soles / +8.5% en # créditos, el capital que entra en mora supera lo que
> `P_NO_PAGA_DIA0=13.38%` asume) vs. tasa de activación condicional (real **levemente por
> DEBAJO** del modelo, −1.1pp, no por encima). Grupo control vs. gestionado: stock (muestra
> grande) sin diferencia (64.8% vs. 65.1%); nuevos con control activando MÁS que gestionado
> (94.0% vs. 69.3%, pero n=50 en control, no concluyente). **Conclusión: no hay evidencia de
> que una mejora real de efectividad de cobranza explique el error del modelo — es volumen.**
> Caveat sin resolver: no se confirmó si `grupo_control` es asignación aleatoria o regla de
> negocio. Ver `analisis_volumen_efectividad_agosto.md`/`.sql` para el detalle completo y
> bug 16 en `BUGS.md` para el cierre del pendiente. `meta_agosto_capital_asegurado.py`
> refrescado a v5 (corte 21-ago) en el mismo paso — ver "La meta vigente" abajo. **Queda
> pendiente de esta sesión:** ítem 1 del pedido original (reestructurar
> `curvas_matriz_alfa.html`) — el usuario prefirió describir las observaciones en texto,
> todavía no las dio.

> **2026-08-22 — investigación de `dias_atraso_cuota` (`dts_cobranza_creditos_calendario_
> diario`) como reemplazo de `dayslate`, resultado MIXTO, NO adoptado en producción.** A
> pedido del usuario, se probó reconstruir el universo de mora "desde el origen" (sin el
> parche aditivo de capa fantasma) usando una tabla nueva que reconstruye día a día los
> días de atraso por crédito. Cierra ~83% del hueco de bug 9 al reconciliar contra
> `vw_seguimiento_diario_cohorte_tramo` (S/5.1M→S/854K sin capturar, de los cuales 89% es
> la exclusión deliberada de reenganches, no un hueco nuevo). Pero el backtest completo
> (curva + tasa recalibradas, primera vez excluyendo ambos meses de prueba) da error mixto:
> junio +0.93% (mejora vs. +2.65% actual), julio +9.71% (empeora vs. +2.17% actual). **Sin
> cambios a la meta vigente ni a la metodología de producción** — ver bug 16 en `BUGS.md`
> para el detalle completo y los pendientes (extender backtest, revisar volatilidad del
> componente stock, probar si el error refleja mejora real de cobranza vía `grupo_control`).
> Se agregó un principio nuevo a `CLAUDE.md` ("Principio de universo"): siempre cuadrar el
> universo histórico contra una fuente formal disponible antes de confiar en curvas propias.

> **2026-08-21 (continuación, 4ta vuelta) — `homologacion_tipo_mora_gestiones.sql` (bug
> 13) re-verificado con `aux02`, bajo impacto CONFIRMADO (no solo esperado). Los 3 archivos
> del proyecto que cruzan contra `dts_asignaciones_gestiones_cobranza` quedan corregidos —
> no queda ningún uso del crosswalk `dni`+`producto` viejo en el repo.** Re-corrido Q1/Q2/Q3
> con `aux02`: el acuerdo del día representativo (10-ago) pasa de 98.52% a **98.49%**
> (897+929=1,826/1,854 vs. 917+947=1,864/1,892 antes) — prácticamente idéntico, y **los
> mismos 28 casos exactos** de desacuerdo (0 en la dirección opuesta, igual que antes). La
> población matcheada baja levemente (-2%) — `aux02` a veces referencia un eslabón anterior
> de una cadena de reenganche en vez del vigente, diferencia menor que no cambia ninguna
> conclusión de bug 13. Ver bug 15 en `BUGS.md` para el detalle completo.

> **2026-08-21 (continuación, 3ra vuelta) — desplegado el fix de `aux02` (bug 15) a
> `avance_cobranza_fase.sql`, tarea 1 de `PENDIENTES.md` CERRADA.** A pedido del usuario,
> se re-corrió `avance_cobranza_fase.sql` con 3 fixes juntos: bug 15 (`aux02` en vez del
> crosswalk `dni`+`producto` — cohorte crece de 8,303 a 8,614 créditos, +3.7%, concentrado
> en TEMPRANA), bug 12 (día 1 de julio = antiguo/stock, no nuevo — nunca se había aplicado
> a este archivo; "nuevo" baja de 1,258 a 571 créditos, la mayoría del bucket viejo eran
> entrantes de día 1 mal clasificados) y bug 11 (dedup, exigido por `CLAUDE.md` para
> cualquier `row_number()`/`lag()` nuevo sobre `dts_mambu_loans_hist`, este archivo tampoco
> lo tenía). Verificado: la tasa `13.38%`/`P_FANTASMA` y las curvas de maduración **no se
> ven afectadas** por ninguno de estos hallazgos — se calibran exclusivamente contra
> `dts_mambu_loans_hist`/`dts_cobranza_creditos_cuotas`, sin ninguna dependencia de
> `dts_asignaciones_gestiones_cobranza` (confirmado con grep en los archivos de
> calibración/backtest/meta, 0 referencias). Con los 3 fixes, la lectura de avance de
> Temprana cambia de "atrasada" a "adelantada" en el segmento nuevo (+6.6pp vs. -4.3pp
> antes) — es un cambio de clasificación, no una señal nueva de que el ritmo de pago real
> cambió. Especializada/Recovery casi no se movieron (tienen poco saldo dentro de mora
> 1-30, donde pegan estos fixes). Sin impacto en la meta vigente de agosto. Ver
> `avance_cobranza_fase.md` para el detalle completo y la tabla de resultados actualizada.
> **Queda pendiente, menor prioridad:** revisar `homologacion_tipo_mora_gestiones.sql`
> (bug 13) con el mismo fix — impacto esperado bajo (ya daba 98.5% de acuerdo).

> **2026-08-21 (continuación, 2da vuelta) — Q7/Q8 de la reconciliación TEMPRANA
> verificadas como SQL ejecutable real, los 2 huecos de "solo nuestro" investigados, y
> hallazgo mayor de metodología: `dts_asignaciones_gestiones_cobranza` SÍ tiene
> `id_ihfintech_loan` directo (columna `aux02`) — corregido y aplicado.** A pedido
> explícito del usuario, se relanzó el cálculo desde cero contra Athena (sin confiar en el
> CSV guardado): Q7/Q8 nunca habían quedado como SQL real en el repo (solo pseudocódigo) —
> re-corridas, dan **3,265/3,265 y 1,246/1,246 filas idénticas** al CSV ya commiteado a
> nivel crédito — sin no-determinismo de bug 11, sin drift de datos. Al investigar "Sin
> asignar" (367 créditos), se encontró primero un bug de matching (crosswalk
> `dni`+`producto` con filtro `status='ACTIVE'` demasiado estricto) y luego, señalado por
> el usuario, algo más grande: la tabla **SÍ tiene el ID de crédito directo** en una
> columna sin nombre descriptivo (`aux02`) — verificado con Athena (99.97% de match real,
> mejor que el ~96.5% del crosswalk que el proyecto venía usando desde bug 13). **Corregido
> y aplicado en el mismo día:** `FUENTES_DATOS.md`, `reconciliacion_temprana.sql` (Q11/Q12
> reemplazan a Q6/Q8) y el CSV `solo_nuestro_motivo_julio.csv` regenerado — números
> finales: Grupo de control 1,017 (antes 779), Sin asignar 120 (antes 367), Doble producto
> en otra fase 65 (antes 58), Escalado fase fija 36 (igual), Revisar 8 (antes 6, ese motivo
> resultó ser además un artefacto de anclaje de fecha, no un hueco real — no relacionado al
> fix de `aux02`). Con esto, **TEMPRANA queda completamente cerrada**. **Pendiente, fuera
> de esta pasada:** aplicar el mismo fix de `aux02` en `avance_cobranza_fase.sql` (ya
> pendiente por bug 12) y revisar `homologacion_tipo_mora_gestiones.sql` (bug 13, bajo
> impacto esperado). Sin cambios a producción de la meta vigente de agosto. Ver bug 15 en
> `BUGS.md` y `reconciliacion_vw_seguimiento_temprana.md` pendiente 4 para el detalle
> completo, y `reconciliacion_temprana.sql` Q7-Q12 para las queries reales.

> **2026-08-21 (continuación) — cobertura de agosto de la capa fantasma: hipótesis de
> timing confirmada, no hay hueco nuevo.** El 81.8% de cobertura (vs. 99.7% julio,
> `reconciliacion_agosto.sql` Q3) se desagregó por `installmentstate` (Q4): **98.3% de
> los 412 no cubiertos todavía no pagan su cuota** (timing de mitad de mes, julio ya
> tiene todos los desenlaces resueltos y agosto no) — solo 1.7% (7 créditos, S/6,704) es
> un hueco real, volumen despreciable. Sin cambios a producción (no bloqueante). Ver bug
> 14 en `BUGS.md` y `reconciliacion_vw_seguimiento_temprana.md` pendiente 2.

> **2026-08-20 — "capa fantasma" diseñada, validada con backtest en 2 meses cerrados, y
> ADOPTADA en producción (a pedido explícito del usuario):** el punto ciego de `dayslate`
> (bug 9) es 99.5% el mecanismo ya conocido, no uno nuevo (paso 1). Se diseñó una
> corrección quirúrgica (opción (a) completa, solo Enfoque alfa, no toca `13.38%` ni la
> curva existente — tasa nueva e independiente `P_FANTASMA=8.4534%`) y el backtest mostró
> mejora consistente en los 2 meses cerrados disponibles: **error total -4.4%→+0.7% en
> junio, -4.31%→+0.12% en julio** (esto último con un signo que estaba mal en
> `SEGUIMIENTO.md`, ya corregido). Aplicado a `enfoque_capital_asegurado.sql`/
> `_backtest.sql`, `backtest_capital_asegurado_junio.py`, `meta_agosto_capital_asegurado.py`
> y `SEGUIMIENTO.md` — ver bug 14 en `BUGS.md` y `reconciliacion_vw_seguimiento_
> temprana.md` ("Paso 2/3 — resultado") para el detalle completo. La meta de agosto
> cambia de forma material — ver "La meta vigente" abajo.

> **2026-08-20 (mismo día) — bug 11 (filas duplicadas) validado y aplicado a Enfoque
> alfa:** la regla mejorada de dedup (saldo≠0 antes de `lastmodifieddate`) se validó
> contra los 687 casos conflictivos completos de la historia (no solo la muestra de 16) —
> 100% de las referencias no-ambiguas disponibles confirman el saldo no-cero. Aplicada a
> `enfoque_capital_asegurado.sql`/`_backtest.sql`/`cierre_julio.sql`. Backtest re-corrido:
> junio sube de +0.7% a **+2.2%** (nuevos -8.6%→-5.8%); julio no se movió (0 filas
> duplicadas relevantes en su ventana). Ver bug 11 en `BUGS.md` y `SEGUIMIENTO.md`. La meta
> de agosto (curvas Q1/Q2) se movió <1pp — no se recalculó (bajo impacto confirmado).

> **2026-08-20 (mismo día) — reconciliación TEMPRANA CERRADA, los 5 pendientes
> resueltos:** los pendientes 2-5 de `reconciliacion_vw_seguimiento_temprana.md` quedaron
> resueltos: (b) el ~27% de punto ciego no repite igual en el agregado de agosto a mitad de
> mes (19.1% al corte 20-ago) pero sí por cohorte (nuevos: 30.0%, mayor que julio) — hay
> que re-medir cuando agosto cierre. Reenganches (313 créditos) quedan documentados como
> diferencia de alcance deliberada (decidido con el usuario). El pendiente 1 (capa fantasma
> a nivel crédito) encontró que solo cubría 90.7% directo (no 100%) por un hueco de
> frontera de mes — **fix adoptado en producción**: cobertura 90.7%→99.7%, y la tasa
> `P_FANTASMA` se recalibró junto con el fix (8.4534%→8.5524%, misma definición de
> "periodo" en tasa y calendario). Backtest final: junio +2.2%→+2.65%, julio
> +0.12%→+2.17% (ambos buenos números, motivo del alza: dilución por solapamiento con
> otros eventos de mora, no un error) — ver bug 14 en `BUGS.md` para el detalle completo.

> **2026-08-19 — reconciliación contra vista oficial externa, punto ciego de `dayslate`
> cuantificado en ~27%:** ver bug 14 en `BUGS.md` y el plan de trabajo en
> `reconciliacion_vw_seguimiento_temprana.md`. Nuestra población de mora 1-30 cuadra casi
> exacto con la oficial (`vw_seguimiento_diario_cohorte_tramo`) donde ambas coinciden — el
> gap es de cobertura, no de cálculo.

> **2026-08-18 — homologación con `gestiones_cobranzas` + julio cerrado + meta de agosto:**
> ver bug 13 en `BUGS.md` (homologación de `tipo_mora`) y `SEGUIMIENTO.md` (cierre de julio,
> ambos enfoques). `dts_asignaciones_cobranza` quedó congelada desde 2026-07-10 — repuntado
> a `dts_asignaciones_gestiones_cobranza` en `avance_cobranza_fase.sql`/`FUENTES_DATOS.md`.
> El repo había estado ~1 mes sin actividad (último commit antes de hoy: `b0b5f73`,
> 2026-07-15) — ya resuelto: julio cerrado y agosto con meta + tracking en vivo (ver "La
> meta vigente" abajo). **Sigue pendiente:** re-correr `avance_cobranza_fase.md` con la
> definición corregida (bug 12, tarea 1 de `PENDIENTES.md`) — no se tocó en este cierre.

> **2026-07-15 — recorte de alcance a 2 enfoques:** a pedido explícito del usuario, el
> proyecto ahora solo mantiene el enfoque acumulado/oficial (rebaje, capital reducido) y
> el enfoque alfa (capital asegurado). "Reinicio del reloj" y "salida de mora" (beta) se
> descontinuaron y sus archivos se eliminaron del repo — ver `DECISIONES.md`. **Para
> completar lo pendiente de los 2 enfoques vigentes, ver [`PENDIENTES.md`](PENDIENTES.md)
> — es el documento de handoff, pensado para retomar sin releer todo este archivo.**

## La meta vigente

> **Desde 2026-07-13, la meta principal reportada es capital asegurado (Enfoque alfa)**,
> a pedido explícito del usuario — no el recupero en soles. El recupero oficial se sigue
> calculando y trackeando (sigue siendo válido, con su propio backtest +5.4%), pero ya no
> es el número que lidera esta sección. Ver `enfoque_capital_asegurado.md`.

> **2026-07-14 — corrección de definición antiguos/nuevos (bug 12, ver `BUGS.md`):** un
> crédito que entra en mora el DÍA 1 de un mes viene siempre de una cuota vencida el
> ÚLTIMO DÍA DEL MES ANTERIOR — es antiguo, no nuevo. Se corrigió en curvas y backtest.
> `avance_cobranza_fase.md` (el análisis por fase) **todavía no** se re-corrió con la
> definición nueva — pendiente (tarea 1, `PENDIENTES.md`).

> **2026-08-18 — julio cerrado, meta vigente pasa a agosto:** ver `SEGUIMIENTO.md` para el
> detalle de ambos cierres. Julio quedó con **+4.7% de error** en capital asegurado (stock
> +1.0%, nuevos +6.3%) y **+17.6%** en recupero oficial (stock +2.0%, nuevos +22.5% — el
> error más alto medido hasta ahora en este enfoque, ver nota de cautela abajo). Fuente:
> `cierre_julio.sql`.

**Septiembre 2026 — Capital asegurado, motor unificado v3 + tasa por SOLES.** Meta proyectada
**S/20,477,271** (stock S/2,241,903 + nuevos S/18,235,368). **La meta se fija una sola vez al
inicio del mes; no se recalcula día a día.** Fijada el 1-sep, con agosto ya cerrado — es la
**primera meta prospectiva limpia** del proyecto (ninguna decisión de modelo se tomó viendo
datos de septiembre).

- Tasa de entrada **24.9081%**, por SOLES, rodante `[202508, 202607]` — reemplaza el
  `P_ENTRADA = 21.9918%` calibrado por conteo. Con la definición vieja la meta sería
  S/18,342,247 (**-11.6%**).
- Curvas de nuevos calibradas **[202508, 202607]** — los 12 meses completamente observados al
  1-sep; agosto queda afuera a propósito (sus cohortes no tienen 31 días de seguimiento).
  Curva de stock: ventana **fija** 202504-202606, sin cambios (18g; rodarla empeora — 18c).
- Fuente: `meta_septiembre_capital_asegurado.py` (`MODO_TASA = "soles_rodante"`).

> ⚠️ **CAVEAT QUE VIAJA CON ESTA META, y es el hallazgo del mes.** La activación real como % del
> calendario **cae -0.46pp/mes** (20.99% ene-mar → 18.50% jun-ago). Si esa tendencia sigue, esta
> meta corre **~10% por encima de lo alcanzable** — el contrafáctico de agosto con este mismo
> motor da **+9.8%**. Se adoptó igual porque tasa y curva deben compartir definición (mismo criterio
> con que se corrigió bug 18, que también empeoró el error). **La meta se reporta junto con esta
> lectura, no sola.** Ver `analisis_tarea19_activacion_decreciente.md`.

> **Seguimiento al 12-sep (medido el 13-sep): −17.4%** contra la trayectoria de la meta (S/7,155,605
> real contra S/8,666,800 proyectado a esa fecha), con correlación diaria 0.982. Supera el caveat y
> queda fuera del rango histórico del día 12 (0.93-1.08 en los 8 meses del backtest). Es sobre todo
> volumen de entradas. Ver `SEGUIMIENTO.md`.

**Septiembre 2026 — Recupero oficial.** Meta proyectada **S/3,928,776** (stock S/537,381 +
nuevos S/3,391,395). **Primera meta de este enfoque con el motor migrado a `dias_atraso_cuota`**
(18e, adoptado 2026-08-26) — agosto quedó con el motor viejo a propósito, por ser mes en curso.
Mismo caveat: el motor corrido contra agosto sobreestima **+13.5%**, en línea con junio (+15.8%)
y julio (+18.3%). Fuente: `meta_septiembre_recupero.py`. **Al 12-sep: −28.6%** contra la trayectoria
(S/1,089,167 real contra S/1,526,191), correlación diaria 0.948.

**Agosto 2026 — CERRADO.** Capital asegurado: meta S/17,117,628, real **S/17,322,872**,
**-1.2%** (stock -1.3%, nuevos -1.1%) — el mes más ajustado del proyecto. Recupero oficial:
meta S/2,108,435, real **S/2,178,078**, **-3.2%** (real medido con `dayslate`, igual que la
meta). Detalle y caveats en `SEGUIMIENTO.md`.

**Cómo leer el avance:** hay que mirar dos números, no uno. El **error de cierre** (meta vs.
ejecución) y la **correlación diaria** miden cosas distintas y pueden moverse en direcciones
opuestas — ver `DECISIONES.md`. Un mes puede terminar lejos de su meta y aun así haber sido
seguido bien día a día.

**Backtest oficial, 8 meses cerrados** (ene-ago 2026), ya corrido con la tasa por soles
adoptada (`backtest_capital_asegurado_unificado.py`): ene **-0.6%**, feb **-10.4%**, mar
**-3.4%**, abr **-1.0%**, may **+0.6%**, jun **+8.7%**, jul **+8.9%**, ago **+2.7%**. Magnitud
media **4.54%** (con la definición vieja de la tasa: 9.14%); correlación diaria media **0.889**,
que **no se movió** al cambiar la tasa — un cambio de tasa es de nivel, no de forma.

> **Ojo al comparar con el contrafáctico de agosto (+9.8%).** Ese número usa los insumos
> **prospectivos** (calendario anclado al cierre de julio, `status='ACTIVE'`), que es lo que una
> meta puede conocer; el backtest usa los insumos **medidos** (saldo del día del vencimiento).
> El calendario anclado corre **+8.2%** por encima del real porque no descuenta la amortización
> entre el ancla y el vencimiento — de ahí que agosto dé +9.8% como meta y +2.7% como backtest.
> Los dos son correctos; miden preguntas distintas. Detalle en el addendum de
> `analisis_tarea19_activacion_decreciente.md`. Detalle por mes en `SEGUIMIENTO.md`, mecanismo en el
artifact [📈 Proyectado vs. Real](https://claude.ai/code/artifact/f80d3761-732c-483b-99ad-d85c95c896aa)
(republicado 2026-09-02 con estos números).

**Lo que sigue sin resolver:** la curva de **stock** todavía no rueda (ventana fija
202504-202606), así que su error de ene-jun está subestimado — es lo que queda de 18c. Y la
caída de activación de tarea 19 no tiene explicación causal todavía: está medida, no explicada.

**Metodología vigente:** dos motores. **Stock** = población en mora al cierre del mes anterior
(`dias_atraso_cuota` 1-30) × curva por tramo × avance, indexada por día del mes, con factor de
cierre real (18g). **Nuevos** = calendario por día de entrada (= vencimiento + 1) × tasa de
entrada **por soles** × curva por `(avance_band, día de semana del vencimiento)` **desde el día
0**, con factor multiplicativo por día del mes de pago. Sin capa fantasma. Código:
`motor_unificado.py` v2/v3 + `curvas_crudas.py`. El detalle conceptual de
`enfoque_capital_asegurado.md` describe la arquitectura **anterior** — para el motor vigente,
leer `motor_unificado.py`.

## Artifacts publicados

| Artifact | Estado | Contenido |
|---|---|---|
| [Metodología ejecutiva](https://claude.ai/code/artifact/909de8df-443f-4440-b85a-e39af636c8e7) | ✓ vigente | Modelo conceptual, curvas, backtest de junio |
| [Guía técnica](https://claude.ai/code/artifact/9df13c20-7758-4174-8346-ed6563d25c5d) | ✓ vigente | SQL replicable para Athena |
| [Meta en vivo — julio](https://claude.ai/code/artifact/52d8badf-bb51-4b92-a3c1-f4f2017aaa27) | ⚠ desactualizado | No refleja el fix de aged-out ni la investigación de dayslate |
| [Deck (11 slides)](https://claude.ai/code/artifact/ae2f5e71-ff14-48bd-af00-909b0aa634cf) | ⚠ desactualizado | Mismo motivo |
| [**Detalle con curvas interactivas**](https://claude.ai/code/artifact/71e5d69d-7586-4ba1-aedc-de7397eea425) | ✓ vigente, el más completo | Composición stock, calendario nuevos, curvas por avance, cohortes, trayectoria — todo con gráficos hover |
| [⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8) | ✓ vigente, es una advertencia | Registro de por qué la tasa oficial es 13.38% y no el complemento simple de "paga a tiempo" |
| [🔒 Capital asegurado](https://claude.ai/code/artifact/d4140b13-4017-4313-b140-7d8f6356d5d7) | ✓ vigente, **republicado 2026-09-02** — agosto cerrado y meta de septiembre | Enfoque alfa, **meta principal** — 5 créditos reales de agosto, curvas por segmento, backtest de **7 meses cerrados** (enero a julio, calibración rodante de 12 meses sin fuga) y avance en vivo de agosto por segmento. La actualización de 18a/18f tocó: banner nuevo, meta S/17.27M→**S/17.12M**, tabla de 7 meses con columna de correlación diaria, avance al 21-ago -0.3%→**-0.7%** y corte fresco al **25-ago (+1.0%)**, y todo el bloque de datos regenerado con `armar_capital_asegurado.py`. |
| [🔒 Curvas + matriz mensual](https://claude.ai/code/artifact/8f58cd63-14d4-4280-a198-f9bdace76e85) | ✓ vigente (republicado 2026-08-22, URL nueva — la anterior dejó de estar disponible) | Enfoque alfa — curvas de maduración interactivas (antiguo por tramo, nuevos) + matriz mes a mes (mar-2025 a jul-2026) de asignado/asegurado/% por segmento, con la definición corregida (bug 12). Agregado 2026-08-22: banner de "Principio de universo" + estado de la investigación de `dias_atraso_cuota` (bug 16, no adoptada). Fuente: `curvas_matriz_alfa.html` + `matriz_mensual_alfa.sql` |
| [🎯 De asignado a asegurado](https://claude.ai/code/artifact/949ab3c2-52a3-447a-b3ce-52531e680fde) | ✓ vigente, **publicado 2026-09-02 (tarea 19)** — es **el artifact para explicar el enfoque** | **Reescritura completa; reemplaza a "De julio a agosto"** en la misma URL (`resumen_julio_agosto.html` queda en el repo como la versión anterior). Escrito para alguien que no siguió el proyecto: define capital asegurado (≥1 pago, no soles cobrados), la entrada en mora como vencimiento+1, y la diferencia entre **antiguos** (se asignan **todos el día 1**, solo pueden achicarse) y **nuevos** (**no existen el día 1**, entran día a día según vencimientos). Eje estructural: la **cadena asignado → asegurado**, con los tres ratios nombrados y con denominador explícito — *ratio de activación de antiguos* 66.7%, *tasa de entrada en mora* 22.8%, *ratio de activación de nuevos* 86.2% — y la advertencia de que el calendario **no** es capital asignado. Todo abierto por tramo × banda de avance × día de semana del vencimiento; incluye las curvas de maduración (antiguos indexada por día del mes, nuevos por días desde la entrada) y los factores de quincena/cierre. Cubre **agosto cerrado** (real S/17,322,872; −1.2% vs. la meta publicada y **+9.8%** vs. el enfoque actual, con la descomposición del error) y **septiembre proyectado** (S/20,477,271), más la **caída de activación** (−0.46pp/mes) y su implicancia. **Republicado 2026-09-02 (tarde)** con: gráfico diario en dos pisos (soles + ratio de activación por cohorte, con la barra de *entra en mora* que faltaba), **tablas de cohortes por día de entrada** para los dos meses, y la sección **«Qué mueve cada corte»** (tasa de entrada real por banda ±18%, por día de semana ±6%, por cercanía al pago ±2%, contra lo que el modelo efectivamente segmenta). Fuente: `asignado_a_asegurado.html` + `armar_asignado_a_asegurado.py` + `tarea19_agosto_cadena_segmentada.sql`. |

| [🧮 Cómo se calcula 13.38%](https://claude.ai/code/artifact/8f7ba3ea-de3e-4bdb-84dd-9105eda2a637) | ✓ vigente, nuevo 2026-08-22 | Reconstruye paso a paso `P_NO_PAGA_DIA0=13.38%`: el embudo elegibles/entradas, 2 créditos reales día por día, desglose mensual (10 meses) y diario (365 días) con curva por día, y las pruebas de robustez de esta sesión (dedup bug 11, ventanas 6/10/12 meses). Fuente: `tasa_1338.html`. |
| [📈 Proyectado vs. Real](https://claude.ai/code/artifact/f80d3761-732c-483b-99ad-d85c95c896aa) | ✓ vigente, **republicado 2026-09-02** — 8 meses y tasa por soles, más la sección "Dos calendarios" | Cómo se arma el backtest mensual completo (2 motores: stock + nuevos), explicado con julio y mayo 2026 día a día. Ahora con la tabla de los **7 meses cerrados** y su correlación diaria, la fuga de calibración **medida** sobre el motor unificado (0.10pp, reemplaza la prueba vieja que se había corrido sobre la arquitectura de 3 motores) y la explicación de cuánta historia conviene usar. Mayo quedó como el ejemplo de por qué el cierre y el seguimiento diario pueden moverse en direcciones opuestas. Series regeneradas con `armar_proyectado_vs_real.py`. Fuente: `proyectado_vs_real.html`. |

> **✔ 2026-09-02 (tarde) — «De asignado a asegurado» (949ab3c2) REPUBLICADO otra vez**, a pedido
> del usuario, para cerrar dos huecos de lectura que él detectó en el artifact:
> (1) el gráfico diario mostraba *vence* y *asegurado* pero **no** *entra en mora*, así que invitaba
> a leer `asegurado ÷ vence` (19.7%), un ratio que mezcla los dos pasos; ahora va en **dos pisos** —
> las tres magnitudes en soles arriba (con el umbral de entrada marcado), y el **ratio de activación
> por cohorte** abajo en su propia escala, porque en soles ese segundo salto ocupa 2 píxeles;
> (2) el «ratio de activación» del cuadro de septiembre (81.7%) se leía como parámetro del modelo
> cuando es el **promedio ponderado de 26 cohortes truncadas** (88.4% la del día 1, 52.1% la del 30).
> Se agregaron **tablas de cohortes por día de entrada** (agosto y septiembre) con los días que le
> quedan a cada una, y la sección **«Qué mueve cada corte»**. Fuente: `armar_asignado_a_asegurado.py`
> (bloque `cortes` nuevo) + `asignado_a_asegurado.html`.
>
> **REPUBLICADO OTRA VEZ el mismo día, tercera pasada:** faltaba **mostrar las curvas de
> maduración** — se usaban en todo el motor pero el artifact casi no las enseñaba (solo 6 miniaturas
> de una sola banda), y la columna «Qué le hace a la curva» de la tabla de cortes decía *«día 0 va de
> 19.2% – 45.8% · techo 90.3%»* sin aclarar siquiera de qué población hablaba. Ahora hay una sección
> propia, **«La curva de maduración: el reloj de cada cohorte»**, que **se movió antes de «Qué mueve
> cada corte»** (primero qué es una curva, después cuánto la mueve cada corte). Arranca siguiendo la
> cohorte del **2 de agosto** día por día (entró S/882,739 → la curva proyecta 91.3% → terminó en
> 92.3%), y muestra las tres curvas completas: **nuevos por banda** (el orden **se invierte** entre el
> día 0 y el cierre: <10% arranca en 37.5% y termina en 88.2%, 70%+ arranca en 30.2% y termina en
> 94.9%), **nuevos por día de semana** (toda la diferencia vive en los 3 primeros días — sábado 19.1%
> contra martes 42.0% — y para el día 7 convergen en ~78%) y **antiguos por tramo** (74.2% / 55.9% /
> 36.2% al día 30). La columna confusa se reemplazó por una **miniatura de la curva** del segmento,
> todas en la misma escala. Se agregaron **rampas secuenciales** (`--ramp-n-*`, `--ramp-a-*`) porque
> banda y tramo son escalas ordenadas, no categorías; contraste ≥3:1 y lightness monótona verificados
> en los dos temas. Datos nuevos en `armar_asignado_a_asegurado.py`: `curvas_nuevos_banda`,
> `curvas_nuevos_dow`, `curvas_stock_tramo`, `curvas_stock_banda` — agregadas ponderando por la masa
> real de septiembre, que es la ponderación con la que esas curvas se combinan en la proyección.
>
> **HALLAZGO DE ESA SECCIÓN, sin adoptar nada (`PENDIENTES.md` tarea 20):** medida sobre
> **202601-202607** desde la matriz cruda, la **tasa de entrada real sí se mueve por banda de
> avance** — 30.8% en `<10%` contra 22.8% en `10-40%`, un índice de **1.184 a 0.874 (±18%)** — y el
> modelo la aplica **plana**. Por día de semana del vencimiento el rango es ±6% (estable: miércoles
> por encima los 7 meses, lunes por debajo los 7); por **cercanía al pago es ±2%**, o sea la
> quincena/fin de mes **no cambian quién cae en mora**, solo **cuándo paga el que ya cayó** (ahí sí
> el modelo los usa, ×1.087 y ×1.225 sobre la activación). **No se tocó el modelo** — segmentar la
> tasa por banda es un cambio que se decide con backtest, no en abstracto.
>
> **✔ 2026-09-02 — LOS 3 ARTIFACTS AFECTADOS YA ESTÁN REPUBLICADOS**, todos conservando su URL:
> **De asignado a asegurado** (949ab3c2, reescritura completa que reemplaza a "De julio a
> agosto"), **Capital asegurado** (d4140b13, agosto cerrado + meta de septiembre + backtest de
> 8 meses) y **Proyectado vs. Real** (f80d3761, 8 meses + sección nueva "Dos calendarios").

Para explicar el enfoque de cero, el recomendado es **De asignado a asegurado**. Para
compartir con el equipo, ese más "Metodología ejecutiva" y "Detalle con curvas interactivas".
Los "⚠ desactualizado" no tienen error, solo no incorporan los hallazgos más recientes —
no republicar sin actualizarlos primero.

> **✔ 2026-08-25 — `P_FANTASMA` recalibrado (tarea 17 fase 3) y artifacts republicados.**
> Los 4 errores mensuales se movieron un poco más (abril -19.2%→**-19.0%**, mayo
> -6.8%→**-6.5%**, junio +1.6%→**+1.9%**, julio -3.3%→**-3.0%**) y la meta de agosto pasó de
> S/16,211,015 a **S/16,257,325**. **📈 Proyectado vs. Real** y **🔒 Capital asegurado** ya
> fueron republicados con los números nuevos pasando `url=` (URLs conservadas) — incluye las
> series diarias de julio (ambos artifacts) y agosto (Capital asegurado) regeneradas desde
> los scripts, no solo los totales. Ver bug 16 (`BUGS.md`) y `SEGUIMIENTO.md` para el detalle
> completo.

> **✔ 2026-08-24 — bug 18 corregido y artifacts republicados.** Los 4 errores mensuales
> cambiaron (abril -17.6%→**-19.2%**, mayo -4.4%→**-6.8%**, junio +2.65%→**+1.6%**, julio
> -0.2%→**-3.3%**) y la meta de agosto pasó de S/16,410,194 a **S/16,211,015**.
> **📈 Proyectado vs. Real** y **🔒 Capital asegurado** ya fueron republicados con los
> números nuevos pasando `url=` (URLs conservadas). Los demás artifacts que citan estos
> números de pasada siguen marcados "⚠ desactualizado" abajo.

*(Los artifacts de "Salida de mora" y "Los 4 enfoques explicados" ya no están en esta
tabla — sus enfoques se descontinuaron 2026-07-15, ver `DECISIONES.md`. Los artifacts
siguen existiendo en claude.ai, solo dejaron de mantenerse.)*

## Índice de enfoques

> Todos los enfoques construidos hasta ahora, en un solo lugar — pensado para que una
> sesión futura pueda armar un markdown integral sin tener que releer todo el historial.
> Cada uno tiene su propio archivo `enfoque_*.md` con el detalle completo.

> **Solo estos 2 enfoques se mantienen desde 2026-07-15** (ver `DECISIONES.md`). "Reinicio
> del reloj" y "Beta — Salida de mora" se descontinuaron y sus archivos se eliminaron del
> repo (recuperables vía git history).

| Enfoque | Archivo | Qué mide | Estado |
|---|---|---|---|
| **Alfa — Capital asegurado** (meta principal desde 2026-07-13) | motor vigente: `motor_unificado.py` (el detalle conceptual de `enfoque_capital_asegurado.md` describe la arquitectura ANTERIOR, con capa fantasma) | % de capital con ≥1 pago en el mes (no soles recuperados) | ✅ **Backtest de 8 meses cerrados** (ene-ago 2026), calibración rodante de 12 meses sin fuga. Con la tasa por SOLES adoptada 2026-09-01: **-0.5% / -10.3% / -3.3% / -0.9% / +0.9% / +8.9% / +9.2% / +9.8%**. Correlación diaria media **0.886**. El sesgo ya no es de signo constante: los últimos 3 meses SOBREESTIMAN ~+9-10%, y eso es la caída de activación (tarea 19), no ruido. Meta de septiembre: **S/20,477,271**. |
| Acumulado (recupero oficial, en paralelo) | `enfoque_acumulado.md` (conceptual); motor vigente `backtest_tarea18e_recupero_oficial_v2.py` | Soles recuperados (rebaje), mes completo anclado al cierre anterior | ✅ **Backtest de 7 meses** con `dias_atraso_cuota` (migrado en 18e): magnitud media 7.83%, correlación diaria 0.837. Agosto cerró -3.2% con el motor viejo (era mes en curso). Corrido contra agosto, el motor nuevo da **+13.5%** — mismo sesgo de activación que el alfa. Meta de septiembre: **S/3,928,776**, la primera con el motor migrado. |
| Tasa 25% plano / motor cuota-consistente | ver `BUGS.md` bug 10 | Alternativas de `P(no paga a tiempo)` (respaldo de una decisión del enfoque acumulado, no es un enfoque propio) | ❌ Descartados por backtest (+66% a +81% / -35.7%) |

Detalle del último:
- ⚠️ **Descartado por backtest:** tasa plana 25-28% (sobreestima +66% a +81%); motor
  "cuota-consistente" con tasa 8.62% + curva propia (subestima -35.7%). Ver `BUGS.md` y
  `motor_cuota_vencimiento.sql`. No es un "enfoque" completo (solo toca la constante
  `P(no paga a tiempo)` del enfoque acumulado), por eso no tiene `enfoque_*.md` propio.

## Análisis puntuales (snapshots, no enfoques con curva propia)

- **Avance de julio por fase de cobranza** (`avance_cobranza_fase.md`, ejecutado
  2026-07-13, **re-corrido 2026-08-21**): cruza la asignación REAL del negocio (tabla
  `dts_asignaciones_gestiones_cobranza`) contra capital asegurado (Enfoque alfa) por fase
  TEMPRANA / ESPECIALIZADA / RECOVERY × nuevo/stock. Corte 2-jul a 12-jul (misma ventana en
  ambas corridas). **✅ Tarea 1 de `PENDIENTES.md` CERRADA** — re-corrido con 3 fixes: bug
  12 (día 1 = antiguo/stock, no nuevo — nunca se había aplicado a este archivo, cohorte
  "nuevo" bajó de 1,258 a 571 créditos), bug 15 (`aux02` en vez del crosswalk
  `dni`+`producto`, cohorte total creció de 8,303 a 8,614 créditos) y bug 11 (dedup, este
  archivo tampoco lo tenía). Con los fixes, Temprana pasa de verse uniformemente atrasada a
  mostrar "nuevo" +6.6pp adelantado (antes -4.3pp) — la lectura cambió porque se redefinió
  qué créditos caen en cada categoría, no porque el ritmo de pago real haya cambiado.
  Especializada/Recovery siguen sin curva calibrada (el modelo nunca cubrió mora 31+), sin
  cambio material ahí. Ver bug 15 en `BUGS.md` y `avance_cobranza_fase.md` para el detalle
  completo.
- **Homologación con `gestiones_cobranzas`** (2026-08-18, `homologacion_tipo_mora_gestiones.sql`,
  bug 13 en `BUGS.md`): el `tipo_mora` de ese proyecto hermano valida el fix de bug 12 —
  98.5% de acuerdo con nuestra clasificación antiguo/nuevo en la población mora 1-30
  (muestra 10-ago). El 1.5% de diferencia es un comportamiento esperado (créditos que curan
  y recaen dentro del mes; este proyecto fija "stock" todo el mes por diseño). No requiere
  cambios al modelo. **Re-verificado 2026-08-21 con el fix de `aux02` (bug 15):** 98.49% de
  acuerdo (prácticamente idéntico) y los mismos 28 casos exactos de desacuerdo — bajo
  impacto confirmado, no solo esperado.
- **Reconciliación contra `vw_seguimiento_diario_cohorte_tramo`** (2026-08-19/20, vista
  externa "oficial" aportada por el usuario, bug 14 en `BUGS.md`): nuestra población de
  mora 1-30 cuadra casi exacto (0.15%) con la oficial en los créditos que ambas comparten,
  pero el punto ciego de `dayslate` (bug 9) explica ~27% de TODA la población TEMPRANA
  oficial que no estábamos capturando. **✅ Resuelto 2026-08-20:** 99.5% es el mismo
  mecanismo de bug 9 (no un patrón nuevo) — corrección ("capa fantasma") diseñada,
  validada con backtest en 2 meses cerrados y adoptada en producción, incluyendo un
  segundo fix (frontera de mes + tasa `P_FANTASMA` recalibrada) encontrado al verificar a
  nivel crédito. Números finales: **+2.65%/junio, +2.17%/julio**. **TEMPRANA cerrada
  2026-08-20** (los 5 pendientes de cierre resueltos, ver `reconciliacion_vw_seguimiento_
  temprana.md`): (a) la verificación a nivel crédito encontró que la capa fantasma
  original cubría solo 90.7% directo del bucket bug9 — el 9.3% restante era el mismo
  mecanismo pero con un hueco de frontera de mes (cuota vencida el último día del mes
  anterior), análogo a bug 12 — **corregido, cobertura ahora 99.7%**; (b) el ~27% no
  repite igual en agosto a mitad de mes (19.1% agregado al 20-ago) pero sí por cohorte
  (nuevos: 30.0%, más alto que julio) — hay que re-medir cuando agosto cierre. Reenganches
  (313 créditos) quedan documentados como diferencia de alcance deliberada, decidido con
  el usuario. Aplicar la capa fantasma al Enfoque acumulado sigue fuera de alcance.

  **2026-08-21 — dataset filtrable por crédito + corrección verificada:** se generaron
  `datos_reconciliacion_temprana/solo_oficial_motivo_julio.csv` y
  `solo_nuestro_motivo_julio.csv` (1 fila por crédito, columna `motivo`, vía Q7/Q8 de
  `reconciliacion_temprana.sql`) para poder filtrar los motivos de diferencia en vez de
  solo ver el agregado. Al verificar el motivo "escalado a Especializada/Recovery" se
  encontró que la hipótesis de "arrastre de DNI" era **falsa** (94/94 son el único
  crédito de su `dni`+`producto`, sin hermano) — el motivo real es una **fase fija/
  "pegajosa"** en `gestiones_cobranza` que no baja aunque `dayslate` muestre mora fresca.
  Ver bug 13 en `BUGS.md` para el detalle.

  **2026-08-21 (continuación) — Q7/Q8 verificadas como SQL real, los 2 huecos restantes
  cerrados, y hallazgo mayor de metodología (`aux02`) corregido — TEMPRANA completamente
  cerrada:** Q7/Q8 nunca habían quedado como SQL ejecutable en el repo — re-corridas
  contra Athena, reproducen exacto los 2 CSV ya commiteados a nivel crédito. Al investigar
  "Sin asignar" (367 créditos) se encontró primero un bug de matching (crosswalk
  `dni`+`producto` con filtro `status='ACTIVE'` demasiado estricto) y luego, señalado por
  el usuario, que `dts_asignaciones_gestiones_cobranza` **sí tiene `id_ihfintech_loan`
  directo** en una columna sin nombre descriptivo (`aux02`, 99.97% de match verificado) —
  mejor que el crosswalk `dni`+`producto` que el proyecto venía usando desde bug 13.
  **Corregido y aplicado:** Q11/Q12 reemplazan a Q6/Q8, CSV regenerado — Grupo de control
  1,017 (antes 779), Sin asignar 120 (antes 367), Doble producto en otra fase 65 (antes
  58), Escalado fase fija 36 (igual), Revisar 8 (antes 6, artefacto de anclaje de fecha,
  no relacionado al fix). Ver bug 15 en `BUGS.md` para el detalle completo y
  `reconciliacion_temprana.sql` Q9-Q12 para las queries. **Pendiente:** aplicar el mismo
  fix en `avance_cobranza_fase.sql` y revisar `homologacion_tipo_mora_gestiones.sql`.

## Pendiente de copiar al repo desde scratchpad

**No recuperable, pero documentado el patrón:** las queries usadas para reconstruir
`capital_asegurado.html` (2026-08-23) — real diario de agosto por día (stock/nuevos/
fantasma), la recalibración de curvas de tarea 10, y las queries de los 5 créditos de
ejemplo — se corrieron en el scratchpad de la sesión y se borraron al limpiar (no
sobreviven entre sesiones). **Los RESULTADOS sí están guardados**: embebidos en el JSON de
`capital_asegurado.html`, y las curvas recalibradas en `datos_capital_asegurado_recal/`. Si
hace falta reconstruir las queries, el patrón exacto (stock/nuevos/fantasma real por día,
frontier-adjusted) ya está documentado y SÍ guardado en `enfoque_capital_asegurado_
backtest_mayo.sql` — solo cambian las fechas (julio→agosto en vez de abril→mayo).

**Cuando termines una sesión con hallazgos nuevos, revisa esta sección antes de cerrar** —
si algo quedó solo en el scratchpad de Claude Code, anótalo aquí para no perderlo.

## Prompt de continuación

> Copiar/pegar esto al abrir la siguiente sesión para retomar sin releer todo:

```
CONTEXTO MÍNIMO PARA ARRANCAR (leer en este orden):
1. ESTADO.md, bloques "2026-08-24 (continuación)" a "(continuación 5)" arriba -- bug 18 YA
   CORREGIDO (backtests, meta de agosto, docs y los 2 artifacts), tareas 13/14 YA CERRADAS,
   tareas 15/16 YA MEDIDAS (decisión del usuario sigue pendiente, no urgente), universo
   validado EN CAPITAL julio/agosto con el método `dayslate` (87.6%/89.1% en soles). La
   PRIORIDAD de esta sesión es la tarea 17 (abajo) -- NO tareas 15/16, que quedan en pausa
   hasta que tarea 17 (que puede cambiar el universo base de toda curva) esté resuelta.
2. BUGS.md bug 16 COMPLETO (la investigación original de `dias_atraso_cuota`, archivada por
   resultado mixto -- releer qué se probó exactamente antes de repetir nada) y su
   actualización 2026-08-24 (el mecanismo horario, el caso verificado, las 3 correcciones
   del usuario). Bug 19 solo si hace falta contexto de la validación de capital previa.
3. CLAUDE.md, "Principio de interpretación del error" -- aplica DIRECTO a tarea 17: el
   objetivo es identificar y explicar diferencias de universo, NO reducirlas. No tratar un
   "% sin explicar" chico como la meta.
4. PENDIENTES.md tarea 17 COMPLETA -- tiene el plan en 4 fases y las 3 correcciones del
   usuario ya incorporadas. Es la única tarea nueva de esta sesión; el resto (15/16 y las
   más antiguas) esperan.
5. En memoria: feedback-error-se-explica-no-se-optimiza,
   feedback-verificar-antes-de-afirmar y feedback-cuadrar-universo-fuente-formal.

EL PUNTO CONCEPTUAL QUE ORIGINÓ TODO (del usuario, tenerlo presente en cualquier query
nueva): la fecha de vencimiento es el último día que el cliente puede pagar SIN entrar en
mora. Entra en mora al día SIGUIENTE. Por eso: "nuevo" = vence dentro del mes y cae en mora
dentro del mes; "antiguo" = está en mora por una cuota que venció en un mes anterior; y el
día 1 del mes SOLO puede tener antiguos. Verificado: entrada = vencimiento + 1 en 99.99%.

PLAN ACORDADO -- TAREA 17 ES EL PRIMER PASO, en este orden (detalle completo en
PENDIENTES.md tarea 17 y BUGS.md bug 16, no reescribir el plan desde cero):

**Fase 1 -- Cuadrar CANTIDAD (créditos), julio primero, agosto después.**
1. Reconstruir el universo de julio con `dias_atraso_cuota`
   (`dts_cobranza_creditos_calendario_diario`) en vez de `dayslate` -- mismo patrón que bug
   16 pero COPIADO AL REPO esta vez (las queries originales, `sc_A` a `sc_AC`, se perdieron
   en un scratchpad y nunca se recuperaron). A nivel de CASO, `id_ihfintech_loan` completo
   -- no agregado.
2. Comparar contra `dts_asignaciones_gestiones_cobranza` en cantidad de créditos, mismo
   esquema de categorías que `validacion_universo_capital_julio_agosto.sql` (en ambos /
   solo nuestro -grupo control, ESP-REC, no aparece- / solo oficial -sin match, status,
   reenganche, resto-).
3. Para lo que quede "solo oficial" sin explicar, usar `installmentlastpaiddate` (tiene
   timestamp completo) para verificar sistemáticamente si cae en la ventana 9am-10pm.
4. Repetir para agosto (corte 23-ago).
5. **Entregable: tabla de categorías CON MOTIVO, no un % único a minimizar** -- ver
   corrección 2 del usuario abajo, es la regla más importante de esta tarea.

**Fase 2 (recién después de Fase 1 completa) -- montos (soles), misma metodología.**

**Fase 3 -- si el mecanismo horario se confirma sistemáticamente:** construir una curva real
(no una tasa plana) para la población "paga 1 día tarde", calibrada sobre la historia
completa de `dias_atraso_cuota`/`installmentlastpaiddate` (desde 2023-10-17) --
reemplazando `P_FANTASMA` (tasa plana actual, tarea 7/bug 14) que el usuario señaló como
inadecuada.

**Fase 4 (pendiente de Fase 3) --** evaluar si conviene recalibrar TODAS las curvas de
producción (stock, nuevos) con `dias_atraso_cuota` en vez de `dayslate` -- pregunta que bug
16 dejó abierta con resultado mixto, sin investigar a fondo.

**3 correcciones del usuario a tener SIEMPRE presentes en tarea 17 (dadas 2026-08-24,
después de un primer intento de plan que las necesitó):**
1. Al mirar casos de cuotas, SOLO la cuota vigente de cada crédito (la que coincide con
   asignaciones) -- no otras cuotas del mismo crédito. Usar `dias_atraso_cuota`, que ya
   resuelve cuál es la vigente; no reinventar esa lógica desde `dts_cobranza_creditos_
   cuotas` directo.
2. **El objetivo es identificar diferencias y sus motivos, NO reducirlas.** Si algo queda
   sin explicar, se documenta como tal -- no se optimiza para que el número sea chico.
3. El propósito real es validar si `dayslate` es ciego a esta población en TODA la historia
   de calibración (14 meses), no solo julio/agosto -- esos meses son el banco de pruebas
   porque son los únicos con tabla de asignaciones formal.

**Punto de partida ya verificado (no repetir):** crédito
`1f49097f-3bb7-4886-8a22-7ca10a5f5704`, cuota vencida 2026-07-07, pagada
2026-07-08 12:39:41 (vencimiento+1, dentro de la ventana 9am-10pm) -- confirma el mecanismo
a nivel de caso individual.

PENDIENTE, EN PAUSA hasta que tarea 17 avance -- NO es lo siguiente a hacer:
- Tareas 15/16: decisión del usuario sobre excluir ESPECIALIZADA/RECOVERY de la calibración
  (gap real -55/-61pp por componente, efecto agregado chico -0.1pp/-1.5pp). Si el usuario
  pregunta por esto antes de tarea 17, responder con lo ya medido (BUGS.md bug 19) -- no
  hace falta esperar a tarea 17 para eso específicamente, son preguntas relacionadas pero
  independientes.

PENDIENTES MÁS ANTIGUOS, sin tocar (menor prioridad que lo de arriba):
- Tarea 9: extender el backtest a marzo 2026. Usar `enfoque_capital_asegurado_backtest_
  abril.sql` como plantilla. Ya se puede hacer (bug 18 corregido) pero **esperar a que
  tarea 17 defina si el universo cambia** -- no tiene sentido correr un quinto mes con
  `dayslate` si se va a recalibrar con `dias_atraso_cuota` poco después.
- Tarea 6: aplicar bug 12 + dedup de bug 11 al motor de recupero oficial (fase1_stock.sql,
  fase2_nuevos.sql, fase3_backtest.sql). fase1_stock.sql documenta explícitamente lo
  CONTRARIO a la regla del usuario ("los que entran en mora el día 1 quedan como nuevos").
- Bug 17 pendiente: por qué `jul_calendario.csv` corría 7.9% alto (pista: saldo promedio
  ~11% más alto por crédito con MENOS créditos; NO es el dedup, ya se descartó con datos).
- Reestructurar el artifact `curvas_matriz_alfa.html`
  (https://claude.ai/code/artifact/8f58cd63-14d4-4280-a198-f9bdace76e85). El usuario iba a
  dar las observaciones en texto y todavía no las dio -- PREGUNTARLE antes de tocar el HTML.
- Tarea 5 (destino de artifacts desactualizados), tarea 11 (stock errático -- ahora con la
  pista de bug 19), tarea 12 (reorganizar en carpetas).

REGLAS DE DATOS QUE APLICAN SIEMPRE (CLAUDE.md): status IN ('ACTIVE','COMPLETED') para
histórico, excluir reenganches vía flg_last_loan_in_chain, coalesce(dayslate,0) siempre,
dedup de bug 11 (saldo<>0 antes de lastmodifieddate) en cualquier row_number()/lag() nuevo
sobre dts_mambu_loans_hist, capa fantasma con su PROPIO calendario frontier-adjusted (bug
17, no reusar el de "nuevos"), join contra asignaciones SIEMPRE vía aux02 (bug 15, nunca el
crosswalk dni+producto), y cuadrar cualquier población nueva contra una fuente formal antes
de confiar en ella -- ver BUGS.md antes de escribir queries nuevas.
```

## Estado de git

> **2026-09-13 (tarde) — COMMITEADO Y PUSHEADO a `origin`** (pedido del usuario): el seguimiento de
> septiembre, la recalibración v2 y la documentación, en commits separados (ver `git log`).
> **Desde acá los CSV no se versionan:** `*.csv` en `.gitignore`, y los 162 CSV que estaban
> trackeados (16.9 MB) salieron del índice con `git rm --cached` — siguen en disco y en el
> historial de git; sacarlos del historial exigiría reescribirlo con force-push, y no se hizo.
> `rebaje_diario` es un remoto viejo (35 commits atrás) y no se toca.

> **✔ 2026-09-02 — TODO COMMITEADO. Working tree limpio.** Se cerró el hueco que venía desde el
> 26-ago (99 archivos sin commitear, con código que producía la meta vigente sin respaldo).
> **No se pusheó** — el usuario controla el push (`CLAUDE.md`). Hay 2 remotos: `origin` y
> `rebaje_diario`.
>
> Cinco commits, agrupados por unidad de trabajo:
>
> | commit | qué |
> |---|---|
> | `9d7fbb2` | Motor unificado v2/v3 — día de semana, factor de quincena y cierre real (18a/18b/18f/18g) |
> | `e08a22d` | Migración del motor de Recupero Oficial a `dias_atraso_cuota` (18e) |
> | `b692de8` | Cierre de agosto, `P_ENTRADA` por soles, metas de septiembre (19) |
> | `0d21736` | Republicación de los 3 artifacts |
> | `052928f` | Documentación al día |
>
> **`.gitignore` ganó `*.log`** — son los logs de las corridas de Athena (QID + estado), no
> datos. El repo ya tenía 0 `.log` trackeados; ahora la regla es explícita.

Lo de abajo es el detalle histórico de qué quedó pendiente en cada sesión previa, desde antes
del commit `60390dc`. Se conserva como registro; **ya no hay nada pendiente de esa lista**.

## Índice de los demás documentos

- `BUGS.md` — bugs y gotchas encontrados, con causa y fix.
- `IDEAS.md` — pendientes activos + ideas ya probadas y descartadas (no las repitas).
- `DECISIONES.md` — por qué se eligió cada pieza de la metodología.
- `GLOSARIO.md` — definición corta de cada término (tramo, avance, dayslate, etc.).
- `FUENTES_DATOS.md` — las 4 tablas de Athena del proyecto (3 base + la nueva de
  asignaciones), su grano y sus quirks.
- `LINAJE.md` — de qué sistema viene cada columna (Mambu, OkaAPI, o calculada internamente).
- `SEGUIMIENTO.md` — tabla mes a mes de proyectado vs. real (empieza con junio 2026).
- `plan_analisis.md` — bitácora cronológica completa (el historial crudo, incluye el
  historial de los enfoques descontinuados).
- `guia_tecnica_recupero.md` — guía técnica externa con SQL replicable.
- `enfoque_acumulado.md`, `enfoque_capital_asegurado.md` — un archivo por enfoque (los
  únicos 2 vigentes), ver "Índice de enfoques" arriba.
- `avance_cobranza_fase.md` — análisis puntual por fase de cobranza, ver sección arriba.
- `reconciliacion_vw_seguimiento_temprana.md` — reconciliación contra vista externa
  oficial, punto ciego de `dayslate` (bug 14) — **5/5 pendientes cerrados 2026-08-20**. SQL
  en `reconciliacion_temprana.sql` (julio), `reconciliacion_agosto.sql` (agosto) e
  `investigacion_frontera_mes_fantasma.sql` (hueco de frontera de mes, fix adoptado).
- `PENDIENTES.md` — plan de continuación accionable para los 2 enfoques vigentes.
- `analisis_volumen_efectividad_agosto.md`/`.sql` — proyectado-vs-real mismo corte
  desagregado por segmento + descomposición volumen vs. efectividad de gestión (corte
  21-ago), cierra el pendiente de comparación grupo_control de bug 16.
- `validacion_universo_ejecucion.sql` — **(nuevo 2026-08-24)** valida si la REGLA de
  construcción del universo de calibración de curvas coincide con las reglas de ejecución
  real del negocio, tratando agosto como un mes histórico y cruzándolo contra
  `dts_asignaciones_gestiones_cobranza` (V0 rangos, V1 cruce con motivos, V2 desglose
  stock/nuevos por situación de ejecución). Resultado en bug 19 de `BUGS.md`.

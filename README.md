# Meta de recupero diaria — cartera de cobranza (mora 1–30)

Metodología y herramientas para estimar, **día a día**, la cartera de cobranza en mora
1–30 días — calibrada con 14 meses de historia real (dts_mambu_loans_hist,
dts_okaapi_loans, dts_cobranza_creditos_cuotas en Athena, `dev_datalake_master`) y
validada contra un mes real cerrado. **Desde 2026-07-13 la meta principal es capital
asegurado** (Enfoque alfa: % de capital con actividad de pago; backtest de 8 meses cerrados
con calibración rodante, magnitud media de error 4.54% y correlación diaria 0.889 — los dos
números miden cosas distintas, ver `SEGUIMIENTO.md`); el recupero oficial en soles se sigue
trackeando en paralelo.
Ver [`ESTADO.md`](ESTADO.md) para el detalle.

> **Desde 2026-07-15 el proyecto mantiene solo estos 2 enfoques.** "Reinicio del reloj" y
> el enfoque beta "salida de mora" se descontinuaron a pedido explícito del usuario — ver
> `DECISIONES.md`. Sus archivos se eliminaron del repo (recuperables vía git history).

## Empezar por acá

**[`prompt_handoff_2026-09-13.txt`](prompt_handoff_2026-09-13.txt)** — si vas a arrancar una
sesión nueva, empieza por acá: orden de lectura, dónde está el proyecto, qué está resuelto y no
hay que re-probar, las tareas abiertas en orden, el ciclo mensual para fijar la meta siguiente y
las trampas conocidas. *(Los handoffs anteriores — `2026-09-11`, `2026-09-02` y `2026-08-26` —
quedan como registro; están viejos.)*

**[`ESTADO.md`](ESTADO.md)** — foto del momento: meta vigente, artifacts actualizados,
qué está validado vs. experimental, pendientes. Es el archivo que se mantiene al día; todo
lo demás es o bien historial (`plan_analisis.md`) o referencia estable (glosario, fuentes
de datos, decisiones).

**[`PENDIENTES.md`](PENDIENTES.md)** — plan de continuación accionable para los 2
enfoques vigentes (alfa y acumulado), pensado para que alguien que recién llega complete
lo que falta sin releer todo el historial.

## Documentos publicados

| Documento | Público | Contenido |
|---|---|---|
| [Metodología ejecutiva](https://claude.ai/code/artifact/909de8df-443f-4440-b85a-e39af636c8e7) — `metodologia_recupero.html` | Negocio | Modelo conceptual, curvas, backtest de junio |
| [Guía técnica](https://claude.ai/code/artifact/9df13c20-7758-4174-8346-ed6563d25c5d) — `guia_tecnica_recupero.md` | Técnico | Mismo contenido + SQL copiable para Athena |
| [Detalle con curvas interactivas](https://claude.ai/code/artifact/71e5d69d-7586-4ba1-aedc-de7397eea425) — `meta_recupero_detalle.html` | Equipo | El más completo: composición, calendario, curvas por avance, cohortes, trayectoria — todo interactivo |
| [⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8) — `julio_25pct_no_recomendado.html` | Referencia | Registro de por qué la tasa oficial es 13.38%, no el complemento simple de "paga a tiempo" |
| [🔒 Capital asegurado](https://claude.ai/code/artifact/d4140b13-4017-4313-b140-7d8f6356d5d7) — `capital_asegurado.html` | Meta principal, ✓ vigente (2026-09-02) | Enfoque alfa: % del capital asignado con actividad de pago, no soles recuperados. 5 créditos reales de agosto, curvas por segmento, backtest de **8 meses cerrados** (enero a agosto, calibración rodante de 12 meses sin fuga), **agosto cerrado** (-1.2% contra su meta) y la **meta de septiembre: S/20.48M**. Republicado 2026-09-02 con la tasa de entrada **por soles** (24.91%) — con el motor actual agosto habría dado +9.8%, de los cuales ~6.5pp son convención de anclaje del calendario. Ver `motor_unificado.py` v3 y `meta_septiembre_capital_asegurado.py`. |
| [🔒 Curvas + matriz mensual](https://claude.ai/code/artifact/8f58cd63-14d4-4280-a198-f9bdace76e85) — `curvas_matriz_alfa.html` | Equipo | Enfoque alfa: curvas de maduración interactivas (antiguo por tramo, nuevos) + matriz mes a mes de asignado/asegurado/%, ya con la definición corregida (bug 12). Ver `matriz_mensual_alfa.sql` |
| [Meta en vivo — julio](https://claude.ai/code/artifact/52d8badf-bb51-4b92-a3c1-f4f2017aaa27) — `meta_julio_en_vivo.html` | Operativo, ⚠ desactualizado | Caso de uso real: cálculo de la meta del mes en curso |
| [Deck completo](https://claude.ai/code/artifact/ae2f5e71-ff14-48bd-af00-909b0aa634cf) — `deck_meta_recupero.html` | Presentación, ⚠ desactualizado | De la asignación (antiguos/nuevos) a la meta, en 11 slides |
| [🎯 De asignado a asegurado](https://claude.ai/code/artifact/949ab3c2-52a3-447a-b3ce-52531e680fde) — `asignado_a_asegurado.html` | **El recomendado para explicar el enfoque**, ✓ vigente (2026-09-02) | Escrito para que lo entienda alguien que no siguió el proyecto. Eje: la **cadena de capital asignado → capital asegurado**, con los tres ratios nombrados y con su denominador explícito — ratio de activación de antiguos (66.7%), tasa de entrada en mora (22.8%) y ratio de activación de nuevos (86.2%) — y la distinción entre antiguos (se asignan **todos el día 1**) y nuevos (**entran día a día** según vencimientos). Todo abierto por tramo de atraso, banda de avance y día de semana del vencimiento. Cubre **agosto 2026 cerrado** (−1.2% vs. la meta publicada, **+9.8%** vs. el enfoque actual) y **septiembre proyectado** (S/20,477,271) con la misma cadena, más el hallazgo de la caída de activación (−0.46pp/mes). Fuente: `armar_asignado_a_asegurado.py` + `tarea19_agosto_cadena_segmentada.sql`. **Reemplazó a "De julio a agosto"** (`resumen_julio_agosto.html`, que queda en el repo como la versión anterior). **Republicado el 2026-09-02 por la tarde:** el gráfico diario pasó a **dos pisos** (las tres magnitudes en soles arriba — antes faltaba *entra en mora*, así que se leía `asegurado ÷ vence`, que mezcla los dos pasos — y el **ratio de activación por cohorte** abajo, en su propia escala); se agregaron **tablas de cohortes por día de entrada** que muestran el truncamiento de fin de mes (la cohorte del día 1 activa 88.4%, la del 30 solo 52.1%, y el 81.7% del total es su promedio ponderado); y la sección **«Qué mueve cada corte»**, que mide la tasa de entrada **real** por banda de avance (±18%), día de semana del vencimiento (±6%) y cercanía al pago (±2%) contra los cortes que el modelo efectivamente usa. **Tercera pasada del mismo día:** sección nueva **«La curva de maduración: el reloj de cada cohorte»** — las curvas se usaban en todo el motor pero casi no se mostraban. Sigue una cohorte real día por día y enseña las tres curvas completas (nuevos por banda, donde el orden se invierte entre el día 0 y el cierre; nuevos por día de semana, que convergen al día 7; antiguos por tramo). Va **antes** de «Qué mueve cada corte», y en esa tabla la columna críptica «día 0 va de X a Y · techo Z» se reemplazó por la miniatura de la curva del segmento. |
| [🧮 Cómo se calcula 13.38%](https://claude.ai/code/artifact/8f7ba3ea-de3e-4bdb-84dd-9105eda2a637) — `tasa_1338.html` | Técnico | Reconstruye paso a paso `P_NO_PAGA_DIA0=13.38%`: embudo elegibles/entradas, 2 créditos reales día por día, desglose mensual y diario, pruebas de robustez (dedup, ventanas 6/10/12 meses). |
| [📈 Proyectado vs. Real](https://claude.ai/code/artifact/f80d3761-732c-483b-99ad-d85c95c896aa) — `proyectado_vs_real.html` | Técnico, ✓ vigente (2026-09-02) | Los **2 motores** del backtest mensual (stock + nuevos) explicados con julio y mayo 2026 día a día, la fuga de calibración medida (0.10pp) y la tabla de los **8 meses cerrados**. Republicado 2026-09-02 con la tasa por soles y una sección nueva, **"Dos calendarios"**: por qué una meta y un backtest no miden el mismo mes, y cómo el desvío se parte en convención de anclaje (-6.5pp) y modelo (+2.7pp). |

*(Los artifacts son privados hasta que se compartan explícitamente desde su menú de
compartir en claude.ai. Los marcados ⚠ no tienen error, solo no incorporan el fix de
aged-out ni la investigación de dayslate — ver `ESTADO.md`. Los artifacts de "Salida de
mora" y "Los 4 enfoques explicados" se quitaron de esta tabla al descontinuarse esos
enfoques el 2026-07-15 — ver `DECISIONES.md`; siguen existiendo en claude.ai, solo
dejaron de mantenerse.)*

## El modelo, en una frase

El pago es un evento (92% de los créditos en mora paga 0 o 1 vez al mes), no un flujo
diario — por eso el recupero se modela como **P(paga) × E(% del saldo que rebaja al
pagar)**, para dos poblaciones con motores distintos:

- **Stock (antiguos):** créditos con mora 1–30 al cierre del mes anterior. Curva de
  recupero por **tramo de mora × día del mes**. **Decidido el 2026-09-13 (tarea 24), por
  implementar:** pasa a ser *mora 1-30 el día 1 del mes*, la definición de la vista oficial, que
  incluye a quien entra en mora ese mismo día. Los motores vigentes usan todavía la definición
  del cierre hasta que se complete la recalibración.
- **Nuevos:** créditos que caen en mora durante el mes, uno por cada día del calendario
  de vencimientos que no se paga a tiempo. Curva de recupero por **avance de
  amortización × días desde la entrada en mora**.

Ver [`guia_tecnica_recupero.md`](guia_tecnica_recupero.md) para la explicación completa
con SQL replicable, [`plan_analisis.md`](plan_analisis.md) para la bitácora técnica
completa (todas las decisiones, corridas y correcciones, en orden cronológico), o los
archivos de referencia de abajo para consultas puntuales.

## Documentos de referencia (no cronológicos)

| Archivo | Para qué |
|---|---|
| [`ESTADO.md`](ESTADO.md) | Foto del momento — empezar por acá |
| [`PENDIENTES.md`](PENDIENTES.md) | Plan de continuación accionable para los 2 enfoques vigentes |
| [`BUGS.md`](BUGS.md) | Bugs y gotchas encontrados, con causa y fix |
| [`IDEAS.md`](IDEAS.md) | Pendientes de investigación de fondo + ideas ya probadas y descartadas |
| [`DECISIONES.md`](DECISIONES.md) | Por qué se eligió cada pieza de la metodología |
| [`GLOSARIO.md`](GLOSARIO.md) | Definición corta de cada término |
| [`FUENTES_DATOS.md`](FUENTES_DATOS.md) | Las 4 tablas de Athena del proyecto, su grano y sus quirks |
| [`LINAJE.md`](LINAJE.md) | De qué sistema viene cada columna (Mambu, OkaAPI, o calculada internamente) |
| [`SEGUIMIENTO.md`](SEGUIMIENTO.md) | Tabla mes a mes de proyectado vs. real |
| [`CLAUDE.md`](CLAUDE.md) | Instrucciones para cualquier sesión de Claude Code en este repo |
| [`enfoque_acumulado.md`](enfoque_acumulado.md) | Enfoque oficial (validado): resumen corto, apunta a `guia_tecnica_recupero.md` |
| [`enfoque_capital_asegurado.md`](enfoque_capital_asegurado.md) | Enfoque alfa: % de capital con actividad de pago. **Ojo: describe la arquitectura anterior** — el motor vigente es `motor_unificado.py` v2, ver `ESTADO.md` |
| [`avance_cobranza_fase.md`](avance_cobranza_fase.md) | Análisis puntual: avance de julio por fase de cobranza (Temprana/Especializada/Recovery), usando la asignación real del negocio |
| [`reconciliacion_antiguos_septiembre.md`](reconciliacion_antiguos_septiembre.md) | **Cierra la pregunta del 2026-09-02**: por qué nuestros antiguos de septiembre (S/3.76M) son menores que TEMPRANA de la vista oficial (S/4.90M). Cuadre crédito a crédito; el 99% de la diferencia son 965 créditos que vencieron el 31-ago y entraron en mora el 1-sep — `antiguo` para la vista, **nuevos del día 1** para el motor. No es capital faltante. **Superado el 2026-09-13 (tarea 24):** el usuario adoptó la definición de la vista (antiguo = en mora el día 1); con ella el cuadre queda en +0.5%, y los 487 que "no aparecían" resultaron ser créditos que pagaron el 31-ago. |
| [`reconciliacion_vw_seguimiento_temprana.md`](reconciliacion_vw_seguimiento_temprana.md) | **Pendiente activo** — reconciliación contra la vista oficial externa `vw_seguimiento_diario_cohorte_tramo`: cuadra casi exacto en la población compartida, pero cuantifica el punto ciego de `dayslate` en ~27% de TEMPRANA (bug 14, `BUGS.md`) |

## Estructura del repositorio

```
fase0_diagnostico.sql        Auditoría de datos: grumosidad del pago, mecánica de dayslate
fase1_stock.sql              Motor del stock — curva por tramo × avance × día
fase2_nuevos.sql             Motor de nuevos — curva por avance × días desde entrada
fase3_meta.sql               Calendario de vencimientos + mecanismo de combinación
fase3_backtest.sql           Backtest sobre un mes real y cerrado (junio 2026)
ejemplo_cohorte_julio.sql    Ejemplo replicable de una sola cohorte, paso a paso
investigacion_dayslate.sql   Investigación del punto ciego de 1 día en dayslate
motor_cuota_vencimiento.sql  Motor alternativo por vencimiento de cuota (descartado, ver BUGS.md)
enfoque_capital_asegurado.sql  Enfoque alfa: curvas con dayslate + capa fantasma (HISTORICO, reemplazado por el motor v2)
enfoque_capital_asegurado_backtest.sql  Backtest de junio del enfoque alfa
avance_cobranza_fase.sql     Análisis puntual: avance por fase de cobranza (Temprana/Especializada/Recovery)
homologacion_tipo_mora_gestiones.sql  Homologación antiguo/nuevo contra tipo_mora del proyecto gestiones_cobranzas (bug 13)
cierre_julio.sql             Cierre de julio 2026 (real final, ambos enfoques) vs. proyectado

--- MOTOR VIGENTE DEL ENFOQUE ALFA (v2, W3 — 2026-08-26) ---------------------
tarea18f_curva_cruda.sql     MATRIZ CRUDA (fecha_entrada, banda, dia_primer_pago). Fuente
                             unica de las curvas de "nuevos": desde aca se arma cualquier
                             segmentacion y cualquier ventana rodante SIN volver a Athena
curvas_crudas.py             Calibracion desde la matriz cruda (curva + factor por dia del mes)
motor_unificado.py           Proyector compartido: tasa, curvas, factor, segmentacion del calendario
generar_curvas_produccion.py Escribe las curvas de produccion a datos_capital_asegurado/
backtest_capital_asegurado_unificado.py  BACKTEST OFICIAL: 7 meses, calibracion rodante de 12m
meta_agosto_capital_asegurado.py  Meta del mes en curso (v8)
armar_proyectado_vs_real.py  Regenera los datos del artifact proyectado_vs_real.html
armar_capital_asegurado.py   Regenera los datos del artifact capital_asegurado.html
tarea18_ventana_calibracion.sql  Cuanta historia es usable y cuanto deriva la curva
tarea18a_curva_nuevos_dow.sql / _dow7.sql  Curvas por dia de semana (binaria y abierta)
tarea18_{calendario,stock_pob,real_stock,real_nuevos}_7m.sql  Insumos de los 7 meses de test
backtest_tarea18a.py         Las 7 variantes de segmentacion que decidieron W3 (evidencia)
backtest_tarea18f.py         Walk-forward de 7 meses, W0/W1/W2/W3 (evidencia de la decision)
-----------------------------------------------------------------------------

--- UNIVERSO: DOBLE CONTEO Y RECONCILIACION (tareas 21 y 22 - 2026-09-02) ----
tarea21_diagnostico_doble_entrada.sql  Mide los 2 solapamientos antiguo/nuevo en septiembre
tarea21_agosto_doble_entrada.sql  El mismo diagnostico sobre agosto (mes cerrado)
tarea21_casos_reentrada.sql   Cuantos antiguos curan y REENTRAN dentro del mes (28.7%), con casos
tarea21_insumos_primera_entrada.sql  Insumos de la variante; emite los DOS calendarios en UNA corrida,
                             para que la comparacion aisle el metodo de la re-expresion de Mambu
meta_septiembre_primera_entrada.py  La variante proyectada (NO adoptada): -0.0056% en septiembre
tarea22_reconcilia_antiguos_septiembre.sql  Cuadre credito a credito contra la vista oficial
tarea22_hipotesis_fecha_corte.sql  Prueba las 3 hipotesis del gap -- gana la FECHA DE CORTE (965
                             creditos que vencieron el 31-ago y entraron el 1-sep)
tarea22_solo_nuestro.sql      Donde estan los 592 creditos que la vista no marca en TEMPRANA
reconciliacion_antiguos_septiembre.md  El informe: por que S/3.76M y no S/4.90M
-----------------------------------------------------------------------------

--- ANTIGUO = "EN MORA EL DIA 1" (tarea 24 - 2026-09-13) ---------------------
tarea24_reconcilia_antiguos_sep_v2.sql  Cuadre v2 contra la vista: -23.9% -> +0.5%
tarea24_diagnostico_diferencias.sql  Lo que entra/sale al mover el corte (los 487 pagaron el 31-ago)
tarea24_diagnostico_vista.sql  Punto ciego, reenganches y arrastre, con el anclaje replicado
tarea24_casos_b.sql          Los 25 que dias_atraso_cuota no ve, uno por uno
tarea24_casos_b_transacciones.sql  Sus transacciones Mambu: 17 son pagos regularizados
tarea24_validacion_arrastre_dni.sql  Flag de arrastre por DNI reconstruido: 99.9% contra el negocio
tarea24_reenganches_historico.sql  Peso del filtro de reenganches que mira adelante (bug 25)
tarea24_sabados_asignacion.sql  Asignacion de sabado desde el 25-jul (solo canales complementarios)
tarea24_status_okaapi.sql      El filtro de status NO mira adelante (flag 0 = todo COMPLETED)
vw_seguimiento_diario_cohorte_tramo.txt  Definicion de la vista, actualizada con SHOW CREATE VIEW
-----------------------------------------------------------------------------

armar_trayectoria_seg.py     Combina curvas + calendario en una trayectoria diaria (rolling)
backtest_junio.py            Compara proyección vs. recupero real de junio (backtest)
backtest_capital_asegurado_junio.py  Backtest de junio del enfoque alfa (capital asegurado)
backtest_motor_cuota.py      Backtest del motor alternativo (descartado)
meta_julio.py                Meta de julio (histórico, mes ya cerrado — ver cierre_julio.sql)
meta_julio_25pct.py          Meta de julio bajo el escenario 25% plano (no recomendado)
meta_julio_capital_asegurado.py  Proyección de julio bajo el enfoque alfa (histórico)
meta_agosto.py                Meta de agosto (recupero oficial, motor viejo) — mes CERRADO, -3.2%
meta_agosto_capital_asegurado.py  Meta de agosto (enfoque alfa, v8) — mes CERRADO, -1.2%
meta_septiembre_capital_asegurado.py  META VIGENTE (enfoque alfa), tasa por SOLES, anclada al cierre de agosto
meta_septiembre_recupero.py   META VIGENTE (recupero oficial), primera con el motor 18e
meta_septiembre_primera_entrada.py  VARIANTE de universo (tarea 21), NO adoptada: cada crédito
                              cuenta una sola vez, por su primera entrada en mora. Proyecta el
                              método vigente y el nuevo sobre la MISMA foto, para aislar el efecto
generar_curvas_septiembre.py  Curvas de producción de septiembre, ventana [202508,202607]
backtest_tarea19_tasa_soles.py  P_ENTRADA por conteo vs. por soles, 3 variantes sobre 8 meses
avance_cobranza_fase.py      Agregación + cruce con curvas del análisis por fase de cobranza

datos_backtest_junio/        Insumos (CSV) del backtest de junio (recupero + capital asegurado)
datos_meta_julio/            Insumos (CSV) de la meta de julio (enfoque acumulado, histórico)
datos_meta_agosto/            Insumos (CSV) de la meta de agosto (enfoque acumulado)
datos_tarea19/                Insumos del ciclo de septiembre: matrices crudas a 202607, tasa
                              por soles, cierre de agosto, insumos de la meta de septiembre
datos_tarea21/                Doble conteo antiguo/nuevo: diagnósticos de agosto y septiembre,
                              insumos de la variante "primera entrada", y las trayectorias día
                              por día de 8 casos reales de reentrada dentro del mes
datos_tarea22/                Reconciliación de los antiguos de septiembre contra la vista
                              oficial: cuadre crédito a crédito, prueba de las 3 hipótesis del
                              gap, y dónde están los 592 que solo tenemos nosotros
datos_tarea24/                Antiguo = en mora el día 1: cuadre v2 contra la vista, diagnóstico
                              de cada diferencia, los 25 casos del punto ciego con sus
                              transacciones, validación del flag de arrastre, peso histórico de
                              los reenganches, sábados y status
datos_motor_cuota/           Insumos (CSV) del motor alternativo por vencimiento
datos_capital_asegurado/     Insumos (CSV) del enfoque alfa (capital asegurado, curvas)
datos_avance_capital_asegurado_agosto/  Insumos (CSV) de la meta de agosto (enfoque alfa)
datos_tarea18a/              Matriz cruda + curvas por dia de semana + insumos de los 7 meses
datos_tarea17_fase4/         Insumos del motor unificado (calendario, stock, real por mes)
datos_backtest_unificado/    Series diarias del backtest oficial, un CSV por mes
datos_avance_fase/           Insumos (CSV) del análisis de avance por fase de cobranza
scripts/run_athena.sh        Helper para correr un .sql contra Athena y bajar el CSV

plan_analisis.md             Bitácora técnica completa — historial cronológico (incluye lo
                              descontinuado: reinicio del reloj, salida de mora)
guia_tecnica_recupero.md     Guía técnica con SQL replicable (copia del artifact)
metodologia_recupero.html    Documento ejecutivo (copia del artifact)
meta_julio_en_vivo.html      Caso de uso en vivo (copia del artifact, desactualizado)
deck_meta_recupero.html      Deck de presentación (copia del artifact, desactualizado)
meta_recupero_detalle.html   Detalle con curvas interactivas (copia del artifact)
julio_25pct_no_recomendado.html  Por qué NO usar 25% (copia del artifact)
capital_asegurado.html       Enfoque alfa: capital asegurado (copia del artifact)
enfoque_capital_asegurado.md Doc dedicado del enfoque alfa: concepto, metodología, resultados
resumen_julio_agosto.html    De julio a agosto (versión anterior del artifact 949ab3c2)
asignado_a_asegurado.html    De asignado a asegurado: la cadena completa por segmento,
                             agosto cerrado + septiembre proyectado. Publicado 2026-09-02
                             en el artifact 949ab3c2 (reemplaza al anterior)
armar_asignado_a_asegurado.py   Prepara e inyecta los datos de asignado_a_asegurado.html
armar_artifact_julio_agosto.py  Prepara los datos embebidos de resumen_julio_agosto.html
PENDIENTES.md                Plan de continuación accionable para los 2 enfoques vigentes
```

**Nota (2026-07-15):** `enfoque_reinicio_reloj.md`, `meta_desde_hoy.py`/`.sql`,
`datos_meta_desde_hoy/`, `enfoque_salida_mora.md`/`.sql`, `salida_mora.html`,
`datos_salida_mora/`, `guia_4_enfoques.html` y `ejemplos_4_enfoques.sql` se eliminaron del
repo al descontinuarse esos 2 enfoques — ver `DECISIONES.md`. Recuperables vía git history.

## Resultados clave

Ver [`ESTADO.md`](ESTADO.md) para la cifra vigente (se actualiza ahí, no acá) y
[`SEGUIMIENTO.md`](SEGUIMIENTO.md) para el histórico mes a mes de proyectado vs. real.
Resumen al 2026-08-18:

- **Desde 2026-07-13, la meta principal reportada es capital asegurado** (Enfoque alfa,
  `enfoque_capital_asegurado.md`), a pedido explícito del usuario — no el recupero en
  soles. El recupero oficial se sigue calculando y trackeando en paralelo.
- **Julio 2026 cerrado (mes completo) — capital asegurado:** proyectado S/10,306,231, real
  S/10,789,362 — **+4.7% de error** (stock +1.0%, nuevos +6.3%). Ver `SEGUIMIENTO.md`,
  `cierre_julio.sql`.
- **Julio 2026 cerrado — recupero oficial:** proyectado S/1,776,174, real S/2,088,911 —
  **+17.6% de error** (stock +2.0%, nuevos +22.5%) — el error más alto medido hasta ahora en
  este enfoque, concentrado en "nuevos". Con solo 2 meses cerrados (junio +5.4%, julio
  +17.6%) todavía no hay base para saber si es tendencia o varianza — ver `PENDIENTES.md`
  tarea 9.
- **Meta de agosto 2026 — capital asegurado:** S/10,245,695 proyectado (stock S/2,956,828 +
  nuevos S/7,288,868). Al corte del día 18: real S/6,795,074 (66.3% de avance, +8.7% sobre
  lo proyectado al mismo día). Ver `meta_agosto_capital_asegurado.py`.
- **Meta de agosto 2026 — recupero oficial:** S/2,108,435 proyectado (stock S/711,160 +
  nuevos S/1,397,275). Al corte del día 18: real S/1,147,110 (54.4% de avance, -1.5% vs. lo
  proyectado al mismo día). Ver `meta_agosto.py`.
- **Backtest de capital asegurado sobre junio 2026:** -4.4% de error al cierre (stock
  +7.2%, nuevos -8.6%) — mismo orden de magnitud que el backtest del recupero oficial.
- **Recupero oficial — backtest sobre junio 2026 (mes real y cerrado):** +5.4% de error al
  cierre (stock +16.2%, nuevos +0.7% — casi exacto). Dos alternativas de tasa de entrada a
  mora (25% plano, motor "cuota-consistente" 8.62%) se probaron y fallaron el backtest, en
  direcciones opuestas (ver `BUGS.md` bug 10).
- **Recupero mensual del stock por tramo:** 1–8 días: 18.1% · 9–15: 12.7% · 16–30: 7.8%
  del saldo capital.
- **Severidad determinada por avance de amortización, no por tramo de mora** — de 14.9%
  (avance <10%) a 74.8% (avance 70%+), consistente en stock y en nuevos.
- **2026-07-15 — recorte de alcance:** el enfoque "reinicio del reloj" y el enfoque beta
  "salida de mora" se descontinuaron formalmente y sus archivos se eliminaron del repo —
  el proyecto ahora mantiene solo el enfoque acumulado y el alfa. Ver `DECISIONES.md`.
- **2026-08-18 — homologación con `gestiones_cobranzas`:** `tipo_mora` valida el fix de bug
  12 (98.5% de acuerdo en mora 1-30) y se repuntó el desarrollo de `dts_asignaciones_
  cobranza` (congelada desde 2026-07-10) a `dts_asignaciones_gestiones_cobranza`. Ver
  `BUGS.md` bug 13.

## Pendientes

**Ver [`PENDIENTES.md`](PENDIENTES.md)** para la lista accionable de los 2 enfoques
vigentes (qué falta re-correr, qué artifact refrescar, qué queda para cerrar julio). Ver
[`IDEAS.md`](IDEAS.md) para pendientes de investigación de fondo (extender el backtest a
3–6 meses más, recalibrar curvas excluyendo cada mes de prueba, `installmentlastpaiddate`)
e ideas ya descartadas (para no repetirlas).

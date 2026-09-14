# Glosario

Definiciones cortas. Si un término tiene matices, acá va la versión de una línea — el
detalle completo está en `guia_tecnica_recupero.md` o `DECISIONES.md`.

**Antiguos / stock** — **definición decidida el 2026-09-13 (tarea 24), la de la vista oficial:**
créditos con `dias_atraso_cuota` entre 1 y 30 **el día 1 del mes**, con el saldo del cierre del mes
anterior. Incluye a quien entra en mora ese mismo día (su cuota venció el último día del mes
anterior) y excluye a quien estaba en mora al cierre pero pagó el último día. Es la regla del
negocio (`tipo_mora`: `dias_mora >= day(fecha_base)` → antiguo). Se les mide capital una sola vez y
se les da seguimiento con la curva de stock. **La recalibración está hecha (2026-09-13), pero las
metas siguen con la definición anterior hasta que el usuario la adopte** — mora 1-30 **al cierre**
del mes anterior, con la cohorte del día 1 en nuevos (motor unificado, tarea 17 Fase 4). Ver
"v1 / v2" al final.

**Nuevos / flujo** — créditos que entran en mora durante el mes (entrada = vencimiento + 1): del
día 2 en adelante con la definición nueva. Cada día de entrada genera su propia cohorte.

**Arrastre por DNI (`flg_arrastre_dni`)** — crédito en mora 1-30 cuyo DNI tiene otro crédito con
más de 30 días de mora: el negocio lo asigna a ESPECIALIZADA/RECOVERY, no a TEMPRANA. Decidido el
2026-09-13: se trata como en la vista, pero **marcado con un flag, no borrado**, para poder
separarlo en reporte y análisis. Se reconstruye desde `calendario_diario.dni` (99.9% contra el
`max_dias_mora_dni` del negocio).

**Pago regularizado** — pago registrado días después con una fecha valor anterior. La tabla de
cuotas y `dias_atraso_cuota` se re-expresan con la fecha valor, así que el crédito puede "no haber
estado nunca" en mora un día en que el negocio sí lo gestionó (bug 26).

**Tramo** — banda de mora del stock al momento de asignación: 1-8 / 9-15 / 16-30 días.
Fijo todo el mes aunque el crédito cruce 30 días después (ver `DECISIONES.md`). Predice
FRECUENCIA de pago, no severidad.

**Avance de amortización** — `1 - saldo_capital_vigente / monto_financiado`. Bandas: <10%,
10-40%, 40-70%, 70%+. Es el segmentador de SEVERIDAD (cuánto rebaja cuando paga), para
stock y nuevos por igual.

**Entrada en mora** — el momento en que un crédito "nuevo" pasa de estar al día a estar
moroso. Ojo: tiene DOS definiciones distintas en este proyecto, y no son intercambiables:
- *A nivel crédito* (la que usa el modelo oficial): transición `dayslate` 0→1 en la foto
  diaria de `dts_mambu_loans_hist`. Tiene un punto ciego de ~1 día (ver `dayslate` abajo).
- *A nivel cuota*: `dias_vencimiento_a_pago >= 1` en `dts_cobranza_creditos_cuotas` — no
  paga hasta la fecha de vencimiento (inclusive). Captura TODO atraso, incluido el que se
  resuelve al día siguiente.

**`tipo_mora`** — campo de `dts_asignaciones_gestiones_cobranza` (proyecto hermano
`gestiones_cobranzas`): `antiguo`/`nuevo`/`sin mora`, calculado A NIVEL CUOTA
(`dias_mora >= day(current_date)` → antiguo) y **recalculado a diario** desde la cuota
vigente — a diferencia del "tramo" de este proyecto, que se fija una vez al mes y no
cambia aunque el crédito cure y recaiga. Homologado (2026-08-18) contra antiguo/nuevo
(`dayslate`+bug 12): 98.5% de acuerdo en mora 1-30; el 1.5% de diferencia son créditos que
curan y vuelven a caer en mora con una cuota distinta dentro del mismo mes — ver bug 13 en
`BUGS.md` y `homologacion_tipo_mora_gestiones.sql`.

**`dayslate`** — campo de `dts_mambu_loans_hist`, días de mora del crédito en esa foto.
`NULL` cuando está al día (usar siempre `coalesce(dayslate,0)`). Tiene un punto ciego: una
cuota pagada 1 día tarde casi nunca hace que `dayslate` llegue a mostrar 1 (solo 4.3% de
los casos medidos) — probablemente porque la foto diaria captura el estado después de que
el pago ya se aplicó. Ver bug 9 en `BUGS.md`.

**`dias_atraso_cuota`** — campo de `dts_cobranza_creditos_calendario_diario` (nivel
crédito-día, datos desde 2023-10-17): días de atraso de la cuota VIGENTE de cada crédito,
reconstruidos día por día desde el pago real (no un snapshot único como `dayslate`). `NULL`
cuando está al día (mismo patrón que `dayslate`, usar `coalesce(...,0)`). Cierra ~97% del
punto ciego de `dayslate` (bug 9) porque ve episodios de mora reales pero breves que
`dayslate` nunca captura — decidido 2026-08-24 (ver `DECISIONES.md`) como el universo
correcto para calibrar curvas de acá en adelante, reemplazando `dayslate`. Detalle completo
en bug 16 (`BUGS.md`) y tarea 17 (`PENDIENTES.md`).

**Días calendario (hasta fin de mes)** — el índice que elige qué % de la curva de
maduración aplicar al proyectar un vencimiento (días transcurridos desde el vencimiento
hasta el día que se proyecta). Es literal: incluye sábados y domingos aunque no haya
gestión de cobranza esos días — NO confundir con "días de gestión" (término impreciso, ya
no se usa). El modelo funciona bien así porque la curva se calibra sobre la misma base de
días calendario — ver bug 16 en `BUGS.md`, actualización 2026-08-24.

**P(no paga a tiempo)** — probabilidad de que un crédito "elegible" (con cuota venciendo,
no ya en stock) entre en mora ese mes. Valor oficial: **13.38%**, medido a nivel crédito
(`dayslate` 0→1), fuera de muestra. NO confundir con el complemento de "% paga a tiempo" a
nivel cuota (~25-28%) — ver `DECISIONES.md`. **Sigue vigente SOLO para la meta de agosto de
Recupero Oficial** (mes en curso, sin recalcular — ver tarea 18e en `PENDIENTES.md`); desde
julio hacia atrás y desde septiembre en adelante, Recupero Oficial usa la tasa por SOLES de
18e (~25.2%, ver "Tasa por soles vs. por conteo" abajo), no esta.

**Curva de recupero acumulado** — % del saldo capital inicial (o de entrada) que se espera
recuperado, acumulado día a día. Hay una para stock (por tramo × avance × día del mes) y
otra para nuevos (por avance × días desde la entrada en mora).

**Cohorte** — el grupo de créditos que vence (o entra en mora) el mismo día. El motor de
nuevos suma una cohorte por cada día de vencimiento del calendario del mes.

**Saldo en riesgo** — saldo capital de los créditos con cuota venciendo un día dado, ANTES
de aplicar P(no paga a tiempo). Es el insumo del calendario de vencimientos.

**Rebaje** — `max(saldo_ayer - saldo_hoy, 0)`. Los aumentos de saldo (ruido, <2% del
total) se tratan como 0, no como rebaje negativo.

**`flg_last_loan_in_chain`** — campo de `dts_cobranza_creditos_cuotas` (nivel cuota) que
marca si un crédito es el último de su cadena de reenganches/refinanciamientos. Se deriva a
nivel crédito con `max(...)` agrupado por `id_ihfintech_loan` (es constante por crédito) y
se usa para excluir a los créditos reemplazados. Ver `FUENTES_DATOS.md`.

**Enfoque acumulado** — la metodología oficial: stock anclado al cierre del mes anterior +
calendario real del mes. Ver `meta_julio.py`.

**Enfoque "reinicio del reloj"** — metodología alternativa: trataba la foto de HOY como
nueva línea base. **Descontinuada 2026-07-15** (ver `DECISIONES.md`) — el proyecto solo
mantiene el enfoque acumulado y el alfa. Archivos eliminados, recuperables vía git history.

**Backtest** — comparar la proyección del modelo contra el recupero REAL de un mes ya
cerrado. La única forma confiable de validar un cambio de constante o metodología — ver
`DECISIONES.md`.

**Capital asegurado** — métrica alternativa (enfoque alfa, experimental): saldo capital
COMPLETO de los créditos que muestran al menos 1 día de pago en el mes, sin importar
cuánto pagaron. No es lo mismo que rebaje/recupero (que mide soles efectivamente pagados).
Ver `enfoque_capital_asegurado.md`.

**Cura sin pago** — episodio de mora que termina (`dayslate` vuelve a 0) sin que el saldo
capital baje. Candidato a reestructuración crediticia (facilidad de pago), no un cobro
real. Era el foco del enfoque beta "salida de mora", **descontinuado 2026-07-15** (ver
`DECISIONES.md`) — el hallazgo (80.8% de reincidencia) queda documentado en `BUGS.md`
bug 11 y `plan_analisis.md`.

**`motivo_apertura`** — campo de `dts_cobranza_creditos_cuotas`
(`_motivo_apertura__motivo_apertura`, nombre duplicado por venir de un custom field
anidado de Mambu), valores 1-4. Poblado en solo 0.4% de los créditos. Sin diccionario de
datos confirmado, pero fuertemente asociado a "cura sin pago" — ver `enfoque_salida_mora.md`.

---

## Términos del motor unificado v2 (agregados 2026-08-26)

**Día de entrada** — el día en que un crédito pasa a mora, siempre `fechavencimiento + 1`. Es
el índice del **calendario** del Enfoque alfa (`dia_entrada` = día del mes de esa fecha) y el
origen desde el que se mide la curva de nuevos. Indexar por acá —y no por el vencimiento— es
lo que vuelve imposibles por construcción los bugs 12, 14/17, 18 y 20. No confundir con
"día del mes", que es la posición dentro del mes calendario.

**Día 0 de la curva de nuevos** — el día de entrada mismo, y **no vale cero**: entre 18.7% y
42.0% del capital de la cohorte se resuelve ahí, según banda de avance y día de semana del
vencimiento. Es exactamente la población que hasta el 2026-08-25 modelaba la "capa fantasma"
con una tasa plana aparte.

**Capa fantasma** — término **histórico**. Tercer componente aditivo (tasa plana 8.62%,
activación instantánea) que parcheaba el punto ciego de `dayslate`. Eliminado el 2026-08-25:
esa población es ahora el día 0 de la curva de nuevos. Si aparece en un archivo, ese archivo
describe la arquitectura anterior.

**Factor por día del mes (`f`)** — multiplicador sobre el **incremento diario** de la curva de
nuevos, no sobre el acumulado. Tres niveles: quincena (días 15-16) 1.0855, días 30-31 1.1848,
resto 0.9812. Normalizado a media ponderada 1, así que **redistribuye** masa dentro del mes en
vez de agregarla. Captura el efecto de fecha de pago de planilla, que la curva indexada en
días-desde-la-entrada no puede ver. Ojo: el día 29 **no** entra — el efecto es de fecha, no de
"últimos días del mes".

**Ventana rodante** — la calibración `[M-12, M-1]` que usa cada mes proyectado, de modo que la
curva nunca ve el mes que proyecta. Para una meta prospectiva la ventana termina en el último
mes **completamente observado** (31 días de seguimiento cumplidos), no en el mes anterior.

**Matriz cruda** — `datos_tarea18a/curva_cruda.csv`, al grano
`(fecha_entrada, avance_band, día_primer_pago)`. Fuente única de las curvas de nuevos: desde
ahí se arma cualquier segmentación y cualquier ventana sin volver a Athena.

**Correlación diaria** — correlación entre el **incremento diario** proyectado y el real del
componente de nuevos, dentro de un mes. Es la métrica que arbitra los refinamientos de forma;
el error de fin de mes no puede hacerlo (ver `DECISIONES.md`). No confundir con el error de
cierre: un mes puede tener buen seguimiento diario y aun así terminar lejos de su meta.

## Términos de tarea 18e (Recupero Oficial migrado, agregados 2026-08-26 continuación 2)

**Tasa por soles vs. por conteo** — dos formas de calibrar "qué % de lo elegible entra en
mora": contando CRÉDITOS (numerador y denominador en unidades de crédito) o sumando SOLES
(numerador y denominador en saldo). Aplicar una tasa calibrada por conteo sobre un calendario
en soles subestima, porque el exceso de entrada se concentra en créditos de saldo alto —
hallazgo de tarea 18b (Capital Asegurado) y confirmado en 18e (Recupero Oficial): la tasa por
soles corre 24-27% contra ~22% por conteo, mismo mecanismo en los dos enfoques.

**Rebaje real vs. Capital asegurado** — misma "matriz cruda" y mismo motor
(`motor_unificado.proyectar`, `curvas_crudas.py`) sirven para las dos métricas: Capital
Asegurado mide ACTIVACIÓN (saldo completo del crédito que tuvo al menos 1 día de pago),
Recupero Oficial mide REBAJE (soles efectivamente bajados, sumado día a día — puede haber
varios eventos de rebaje por crédito, no solo el primero). El algoritmo de calibración (IPF)
no distingue entre las dos: solo cambia qué se le pasa como masa observada por celda.

**Motor migrado (tarea 18e)** — el motor de Recupero Oficial reescrito sobre
`dias_atraso_cuota`, con el mismo tratamiento que Capital Asegurado (ventana rodante, día de
semana, quincena, factor de cierre en stock) pero calibración propia (no comparte curvas ni
tasa). Vigente para todo mes CERRADO desde julio 2026 en adelante y para la meta de
SEPTIEMBRE; la meta de AGOSTO es la única excepción — sigue con el motor viejo (`dayslate`,
`P_NO_PAGA_DIA0`) porque ya estaba en curso cuando se migró. Ver `DECISIONES.md`.

## Términos de tarea 24 (recalibración con antiguo = en mora el día 1, agregados 2026-09-13)

**v1 / v2 (definición de antiguo)** — v1: stock = mora 1-30 al **cierre** del mes anterior (la de
producción hasta que el usuario adopte v2). v2: mora 1-30 **el día 1** del mes, la de la vista
oficial. Las matrices `datos_tarea24/v2_*` traen las dos de la misma foto de Mambu.

**Cohorte d1** — los créditos que entran en mora el día 1 (su cuota venció el último día del mes
anterior). En v1 eran "nuevos con día de entrada 1" y se proyectaban con calendario × tasa; en v2
son stock, y se conocen el día 1. Pesan de 0% a 53% del stock según el mes, porque siguen a las
cuotas que vencen el día 30.

**Variantes S0 / S1 / S2** — cómo proyectar la cohorte d1 dentro del stock v2. S0: mezclada en el
tramo 1-8 de la curva de stock. S1: tramo propio en la curva de stock. **S2 (recomendada):** con la
curva de NUEVOS por banda y día de semana del vencimiento, sobre su saldo real y sin tasa. Gana en
las métricas diarias porque el día 0 de esa cohorte depende del día en que venció la cuota.

**Re-medición** — la diferencia entre un insumo leído el día en que se fijó la meta y el mismo
insumo leído días después. Dos fuentes: Mambu se re-expresa (−0.3% a −0.8%) y el calendario
prospectivo pierde a los que terminaron de pagar (hoy `COMPLETED`). Para comparar definiciones se
compara contra la versión re-medida, no contra la publicada.

**Reenganche marcado** — incluir en la calibración los créditos con `flg_last_loan_in_chain = 0`
(que hoy se excluyen con un flag que mira adelante, bug 25), marcados con `reeng`, sin contar como
pago el salto de saldo del día en que Mambu los cierra por refinanciamiento.

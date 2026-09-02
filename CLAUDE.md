# Instrucciones del proyecto

Meta de recupero diaria de cartera de cobranza (mora 1-30 días), en saldo capital, para
OKA (fintech peruana). **Antes de tocar cualquier análisis nuevo, lee `ESTADO.md`** — es
el punto de entrada, dice qué está vigente y qué pendiente hay. Luego `BUGS.md` (para no
repetir un error ya encontrado) e `IDEAS.md` (para no re-probar algo ya descartado).

## Reglas de datos — siempre

- `dts_mambu_loans_hist.dayslate` es `NULL` cuando el crédito está al día. Usar siempre
  `coalesce(dayslate,0)`, nunca comparar contra `dayslate` directo.
- Dos filtros de `status` distintos según el caso — **no usar el mismo en ambos**:
  - Histórico/calibración: `status IN ('ACTIVE','COMPLETED')`.
  - Calendario prospectivo (qué va a vencer): `status = 'ACTIVE'` solamente.
  - Backtest de mes cerrado: `status IN ('ACTIVE','COMPLETED')`, sin filtrar `installmentstate`.
- Excluir siempre reenganches/refinanciamientos: `dts_okaapi_loans` no tiene el flag
  correcto — derivarlo desde `dts_cobranza_creditos_cuotas.flg_last_loan_in_chain`
  (`max(...)` agrupado por `id_ihfintech_loan`) y filtrar `coalesce(last_in_chain,1)=1`.
- Nunca usar `principalamountpaid`/`principalamountdue` (`dts_cobranza_creditos_cuotas`)
  para capital — están rotos (sobre-atribuyen pagos, superan 400% acumulado). Para capital,
  usar deltas de `balances_principalbalance` en `dts_mambu_loans_hist`.
- **Para CALIBRAR curvas nuevas, usar `dts_cobranza_creditos_calendario_diario.
  dias_atraso_cuota` en vez de `dts_mambu_loans_hist.dayslate`** (decisión 2026-08-24, ver
  `DECISIONES.md`) — `dayslate` es un snapshot único diario con un punto ciego de ~1 día
  (bug 9) que `dias_atraso_cuota` cierra en ~97% al reconstruir día por día. Mismo patrón
  `coalesce(dias_atraso_cuota,0)`, `NULL` cuando está al día. **Desde 2026-08-25 las curvas de
  producción del Enfoque alfa ya están migradas a `dias_atraso_cuota`** (tarea 17 Fase 4,
  motor unificado — ver `motor_unificado.py`): stock + nuevos, sin capa fantasma. **Desde
  2026-08-26 (tarea 18e) el motor de recupero oficial también migró** —
  `fase1_stock.sql`/`fase2_nuevos.sql`/`fase3_backtest.sql` quedan como referencia histórica;
  el motor vigente es `backtest_tarea18e_recupero_oficial_v2.py` (rebaje real, no activación).
  **Agosto 2026 cerró con los motores viejos a propósito** (era mes en curso cuando se migró);
  las metas de **septiembre** son las primeras con los motores nuevos en los dos enfoques.
- **La tasa de entrada se calibra en SOLES, no contando créditos** (adoptado 2026-09-01, tarea
  19). Se aplica multiplicando el **saldo en soles** del calendario, así que tiene que
  calibrarse sobre soles — los créditos que caen en mora tienen saldo por encima del promedio,
  y la tasa en soles corre **~14.5% más alta** que la de conteo (25% vs. 22%). Los **dos**
  enfoques usan la misma tasa, porque comparten la definición de entrada; lo que difiere aguas
  abajo es la curva (activación vs. rebaje), no quién entra. Verificado: la query de soles
  reproduce el viejo `P_ENTRADA` de conteo al 0.002pp. `motor_unificado.P_ENTRADA = 21.9918%`
  sigue existiendo como default del módulo pero **la producción le pasa `p_entrada=` explícito**
  — no usarla como si fuera la tasa vigente.
- **Ninguna cuota vence domingo** (0.00% del calendario y de la calibración) — OKA no programa
  vencimientos ese día. Como la entrada en mora es siempre `vencimiento + 1`, **tampoco existe
  ninguna entrada un lunes**. Cualquier corte "fin de semana" definido sobre el vencimiento
  tiene que tenerlo en cuenta: `in (6,7)` es en la práctica solo sábado, y deja "vence viernes"
  (que entra **sábado**, día no hábil) del lado de los días hábiles. Ver bug 21.

## No re-consultar Athena para recalibrar una curva de "nuevos"

Existe una **matriz cruda** al grano `(fecha_entrada, avance_band, día_primer_pago)`. Desde ahí,
`curvas_crudas.py` arma **cualquier** curva sin volver a Athena: por banda, por día de semana del
vencimiento, con factor por día del mes, y sobre **cualquier ventana rodante**. Un walk-forward de
8 meses × 4 variantes cuesta 0 corridas adicionales. Antes de escribir una query nueva de
calibración de nuevos, revisar si sale de ahí.

**Cuál es la vigente:** `datos_tarea19/curva_cruda_nuevos.csv` (alfa) y
`curva_cruda_nuevos_rebaje.csv` (recupero), más las dos de stock — cubren hasta **202607**. Las de
`datos_tarea18a/` cubren hasta 202606 y quedan congeladas: son el registro de lo que produjo la
meta de agosto. **Cada mes hay que extenderlas un mes** corriendo las `tarea19_*.sql` con las
ventanas movidas; ese es el único costo recurrente de Athena del ciclo.

## Protocolo de calibración y test — vigente desde 2026-08-26

- **Calibración: 12 meses rodantes**, `[M-12, M-1]` para cada mes proyectado. No estirar a 15-18
  meses: eso mete meses de 2024, cuando la cartera es <20% de la actual, y la dispersión de la
  curva **se duplica** (±4.4pp vs. ±2.8pp en el día 0). Medido en `tarea18_ventana_calibracion.sql`.
  **Tampoco acortar:** 6 meses empeora las métricas diarias (0.886→0.876) y 9 ≈ 12 — probado en
  tarea 19 contra la hipótesis de que una ventana corta seguiría la caída de activación. No lo hace.
- **Test: 8 meses** (202601-202608), con piso de 3,000 entradas/mes.
- **Para una meta prospectiva, la ventana termina en el último mes COMPLETAMENTE OBSERVADO** al
  momento de fijarla — una cohorte necesita 31 días de seguimiento. Para la meta de septiembre eso
  es `[202508, 202607]`: agosto queda afuera aunque el mes ya cerró. Usar datos que no existían
  al fijar la meta es el mismo ajuste ex-post que prohíbe el principio de interpretación del error.
- **La curva de STOCK es la excepción: ventana FIJA `202504-202606`, no rueda.** Rodarla se probó
  en 18c/18g y **empeora** (corr. 0.848→0.820): stock tiene mucha menos masa que nuevos, así que
  12 meses le dan una muestra ruidosa. Queda abierto como tarea 18c y **necesita otro enfoque**,
  no el mismo tratamiento que nuevos.

## Qué métrica arbitra qué — no negociable

**El error de fin de mes NO puede decidir si una curva está mejor segmentada.** La diferencia
pareada entre variantes tiene media -0.13pp y desvío **1.49pp** — el ruido es 10x el efecto,
porque el signo lo fija la composición de fin de mes de cada mes. Resolver 0.13pp sobre el
cierre necesitaría **~1,050 meses**. No hay cantidad realista de historia que lo arregle.

- **Refinamientos de forma** (segmentadores, índices, factores) se deciden con **métricas
  diarias** — correlación de incrementos diarios proyectado-vs-real, y MAE del incremento
  diario. Aportan ~30 observaciones por mes en vez de 1.
- **El error de fin de mes** es el número de negocio y el insumo para explicar el sesgo: es la
  meta contra la ejecución, no un test estadístico.

Corolario práctico: un cambio puede **empeorar el cierre y mejorar el seguimiento diario a la
vez**, y eso no es contradicción (caso real: mayo 2026, -8.7%→-10.9% de cierre con la
correlación diaria subiendo de 0.32 a 0.86). Reportar las dos cosas, nunca una sola.
- Ver `FUENTES_DATOS.md` para el detalle completo de las tablas y `GLOSARIO.md` para los
  términos (tramo, avance, entrada en mora, etc.).

## Gotcha de Presto/Athena

`WHERE columna IN (...)` en la MISMA query que `SUM(...) OVER (ORDER BY columna)` aplica
el `WHERE` ANTES de la window function — el acumulado arranca mal. Siempre calcular el
acumulado completo en una CTE y filtrar en una consulta externa. Ya mordió 2+ veces en este
proyecto (ver bug 4 en `BUGS.md`).

## Principio de modelado — no negociable

**Una tasa/probabilidad y la curva que se le aplica deben calibrarse sobre la misma
definición exacta de "entrada"/cohorte.** No sustituir solo una constante por una medida de
otra población, aunque parezca "más correcta" en teoría. Si alguien propone cambiar una
constante del modelo (ej. `P(no paga a tiempo)`), la forma correcta de resolverlo es
**correr el backtest existente con el cambio, no debatir en abstracto**. Ver
`DECISIONES.md` y bug 10 en `BUGS.md` para el caso real donde esto importó (swap a 25%
sobreestimó +66%, la reconstrucción "consistente" subestimó -35.7% — ninguna ganó).

## Principio de universo — no negociable

**Las curvas del proyecto existen para poder estimar una meta al inicio del mes, antes de
que ese mes ocurra.** Para que esa proyección sea confiable, el universo histórico sobre el
que se calibran curvas y tasas debe **cuadrar exacto contra los puntos de referencia clave
disponibles** — no basta con que la lógica interna (`dayslate`, etc.) "parezca" correcta.
Para julio y agosto 2026 el punto de referencia es la vista formal de asignaciones
(`vw_seguimiento_diario_cohorte_tramo` / `dts_asignaciones_gestiones_cobranza`). A partir de
cuadrar contra esa fuente se han derivado las reglas que corrigen el universo en meses
pasados (bug 9/14/15 en `BUGS.md`) — **siempre buscar cuadrar el universo contra alguna
fuente formal disponible antes de confiar en curvas/tasas calibradas solo con la lógica
propia**, y tratar cualquier diferencia como algo a explicar con datos (exclusión deliberada,
diferencia de sistemas, hueco real), no a asumir.

## Principio de interpretación del error — no negociable

**La proyección de un mes ES la meta de ese mes; el real permite ver si la ejecución va de
acuerdo al histórico esperado.** Un error de -17% no significa "modelo malo" — significa que
la gestión, el mix o el volumen se movieron respecto al histórico. **Las diferencias se
explican, no se huye de ellas.** Nunca ajustar una constante, un índice o una regla con el
objetivo de reducir el error del backtest: eso convierte al modelo en un ajuste ex-post y
destruye lo que lo hace útil como meta fijada al inicio del mes.

Lo que **sí** hay que corregir es que el universo o las reglas de construcción no coincidan
con las reglas de ejecución del negocio (ahí las curvas quedan calibradas sobre una población
equivocada). Ante un hallazgo, la pregunta correcta es *"¿esto cambia QUIÉN entra al universo
o CÓMO se mide?"* — si sí, corregir **aunque el error suba** (caso real: bug 18, el fix del
índice empeora los 4 meses y se corrige igual); si no, documentar la diferencia como señal de
negocio a explicar.

## Ejecutar SQL contra Athena

DB `dev_datalake_master`, workgroup `primary`, output
`s3://aws-athena-query-results-882281946095-us-east-2/tmp-claude-rebaje/`. Helper:
`scripts/run_athena.sh <archivo.sql>` (hace polling y baja el CSV resultante).

## Git

El usuario controla explícitamente cuándo se hace commit y push — no commitear ni pushear
sin que lo pida. Si un push a un remoto agregado en la sesión queda bloqueado por el
clasificador de seguridad de auto-mode, no intentar workarounds (curl+token, etc.) — dar al
usuario el comando exacto para que lo corra desde su terminal.

## Artifacts (HTML/MD publicados)

Cuando se publique un artifact nuevo, copiar también el archivo fuente a este repo (mismo
nombre) — es la convención ya establecida (ver los `.html` en la raíz). Actualizar la tabla
de artifacts en `ESTADO.md` y `README.md`.

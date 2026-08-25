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
  `coalesce(dias_atraso_cuota,0)`, `NULL` cuando está al día. **Las curvas de producción
  vigentes (stock, nuevos) siguen calibradas con `dayslate` todavía** — migrarlas es tarea
  17 Fase 4, pendiente y no decidida; no reemplazar `dayslate` en código de producción sin
  revisar el estado de esa fase en `PENDIENTES.md`.
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

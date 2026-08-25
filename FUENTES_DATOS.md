# Fuentes de datos

Las 3 tablas que se usan en prácticamente todo el análisis, más una cuarta (nueva,
2026-07-13) usada solo en `avance_cobranza_fase.md`. DB `dev_datalake_master`,
Athena workgroup `primary`, output `s3://aws-athena-query-results-882281946095-us-east-2/tmp-claude-rebaje/`.
Cuenta AWS 882281946095, us-east-2.

> Para el linaje de cada columna (de qué sistema viene — Mambu, OkaAPI, o calculado
> internamente) ver [`LINAJE.md`](LINAJE.md).

## `dts_mambu_loans_hist`
**Grano:** una fila por crédito por día (`fechaproceso`, string `YYYYMMDD`). Histórico
completo desde nov-2023, sin huecos, ~58M filas desde 2025-03. La cartera crece rápido
(53k créditos mar-25 → 200k jul-26) — calibrar con meses recientes y vigilar cambio de
mezcla.

| Campo | Notas |
|---|---|
| `_datos_adicionales_loan_accounts_id_ihfintech` | ID del crédito, llave de join con las otras dos tablas |
| `balances_principalbalance` | saldo capital vigente ese día — la fuente de verdad para "rebaje" |
| `dayslate` | días de mora. **`NULL` cuando está al día** — usar siempre `coalesce(dayslate,0)`. Tiene un punto ciego de ~1 día, ver `GLOSARIO.md` y bug 9 en `BUGS.md` |

Confirmado que la tabla SÍ trae la foto del día de la consulta (verificado 2026-07-09),
aunque en general puede tardar en llegar hasta el día anterior — revisar si una corrida
futura parece faltarle el día de hoy. `vw_mambu_loans_hist` (la vista) NO sirve como
sustituto: solo tiene ~33 fechas puntuales dispersas en 2+ años, no una foto diaria.

## `dts_okaapi_loans`
**Grano:** una fila por crédito (no histórico, estado actual). Se usa por `amountfinanced`
(monto financiado, denominador del avance de amortización), `status`, y `term`.

| Campo | Notas |
|---|---|
| `status` | `ACTIVE` / `COMPLETED` / otros. Dos reglas de filtro distintas según el caso — ver `DECISIONES.md` |
| `amountfinanced` | denominador de avance: `1 - balances_principalbalance/amountfinanced` |
| `term` | cantidad de cuotas. Redundante con avance (proxy 1/term) — no usar como segmentador principal |

**No tiene** un flag de "último crédito de la cadena" equivalente a
`flg_last_loan_in_chain`. Tiene `extendedbyloan_id`/`extendedloan_id` y flags
`flag_reenganche_*`, pero NO capturan lo mismo (`extendedbyloan_id` solo afecta ~2% de la
población de mora 1-30, mientras que el filtro correcto de cuotas afecta 5-8pp en la curva
global de toda la cartera). Usar siempre la derivación desde `dts_cobranza_creditos_cuotas`
descrita abajo.

## `dts_cobranza_creditos_cuotas`
**Grano:** una fila por cuota (`id_loan_nro_cuota`) por crédito. Se usa para el calendario
de vencimientos y para la validación en # de operaciones.

| Campo | Notas |
|---|---|
| `fechavencimiento` | fecha de vencimiento de la cuota — el ÚLTIMO día para pagar (inclusive) |
| `installmentstate` | `PAID` / `PENDING` / `LATE` / otros |
| `dias_vencimiento_a_pago` | días entre vencimiento y pago real (a nivel cuota, no crédito) |
| `flg_last_loan_in_chain` | 1 si es el último crédito de su cadena de reenganches. Constante por `id_ihfintech_loan` (verificado) — derivar a nivel crédito con `max(flg_last_loan_in_chain)` agrupado por `id_ihfintech_loan` y unir a `dts_mambu_loans_hist`/`dts_okaapi_loans` |
| `installmentlastpaiddate` | fecha real de pago de la cuota. Aportado por el usuario, **sin explotar todavía** — ver `IDEAS.md` punto 4 |
| `principalamountpaid` / `principalamountdue` | **ROTOS para capital** — sobre-atribuyen pagos anticipados a cuotas individuales (el acumulado supera 400%). Solo sirven para la curva de validación en # de operaciones, nunca para montos |

Sin `flg_last_loan_in_chain=1`, la curva de # operaciones sale ~10 puntos más baja de lo
real (cuotas de créditos reenganchados quedan `LATE` para siempre).

## `dts_cobranza_creditos_calendario_diario` (universo correcto para calibrar curvas — decisión 2026-08-24)

**Grano:** una fila por crédito por día (`fecha_calendario`, tipo `date`), datos desde
2023-10-17 — más profundo que los 14 meses de calibración actuales. Reconstruye día por día
(desde el pago real, no un snapshot único como `dts_mambu_loans_hist`) cuántos días de
atraso tiene la cuota VIGENTE de cada crédito. Sin duplicados por (crédito, día) (verificado,
a diferencia de `dts_mambu_loans_hist`, ver bug 11).

| Campo | Notas |
|---|---|
| `id_ihfintech_loan` | ID del crédito, llave de join con las otras tablas |
| `dias_atraso_cuota` | días de atraso de la cuota vigente. **`NULL` cuando está al día** — usar siempre `coalesce(dias_atraso_cuota,0)`, mismo patrón que `dayslate` |
| `fechaporvencer` | fecha de vencimiento de la cuota vigente en esa fila |
| `fecha_pago` | fecha real de pago de la cuota (no explotada todavía en detalle) |

Join con `dts_mambu_loans_hist`: `date_format(c.fecha_calendario, '%Y%m%d') = a.fechaproceso
and a._datos_adicionales_loan_accounts_id_ihfintech = c.id_ihfintech_loan` (ver `rebaje.sql`
para el patrón original). Requiere los mismos filtros de `dts_okaapi_loans.status` y
`flg_last_loan_in_chain` que el resto del proyecto (`dts_cobranza_creditos_calendario_diario`
no los trae incorporados).

**Por qué importa (decisión 2026-08-24, ver `DECISIONES.md`):** `dayslate`
(`dts_mambu_loans_hist`) tiene un punto ciego de ~1 día (bug 9) porque es un snapshot único
diario (~10pm) — no ve mora que nace y se resuelve antes de esa foto. `dias_atraso_cuota`,
al reconstruir día por día, cierra ~97% de ese punto ciego (verificado julio/agosto 2026
contra `dts_asignaciones_gestiones_cobranza`, bug 16 en `BUGS.md`). El usuario decidió que
la curva debe representar TODA la mora que ocurre (no solo la que el negocio gestiona) —
`dias_atraso_cuota` es de acá en adelante el universo correcto para calibrar curvas,
reemplazando `dayslate`. Investigación completa, queries reproducibles y plan de migración
en bug 16 (`BUGS.md`) y tarea 17 (`PENDIENTES.md`).

## `dts_asignaciones_gestiones_cobranza` (tabla viva — usar esta, no la de abajo)

**Grano:** `(dni_ce, producto)` por `fecha_base` — la asignación REAL de cobranza día a
día, escrita por el Lambda del proyecto hermano `gestiones_cobranzas` (a diferencia de las
3 tablas de arriba, esto viene directo del sistema de asignación del negocio, no es una
población inferida vía `dayslate`). **Reemplaza a `dts_asignaciones_cobranza`** (ver nota
de abajo — esa quedó congelada el 2026-07-10). Confirmado 2026-08-18 vía
`homologacion_tipo_mora_gestiones.sql`, ver bug 13 en `BUGS.md`.

**No tiene NINGUNA fila los sábados/domingos** (verificado julio 2026: `fecha_base` saltea
los 8 sábados/domingos del mes por completo) — el proceso de asignación del negocio corre
solo de lunes a viernes. Un crédito que entra en mora y se resuelve DENTRO de un fin de
semana nunca aparece en esta tabla para todo el mes, aunque `dias_atraso_cuota` sí lo vea
brevemente en mora — no es un hueco de esta tabla a "corregir", es simplemente su cadencia
real. Ver bug 16 en `BUGS.md` para el mecanismo completo y su impacto en la calibración.

| Campo | Notas |
|---|---|
| `dni_ce` | documento del cliente |
| `aux02` | **`id_ihfintech_loan` DIRECTO — corrección 2026-08-21, ver bug 15 en `BUGS.md`.** Columna sin nombre descriptivo (por eso pasó desapercibida hasta ahora) pero confirmado con Athena: 99.97% de los valores (18,613/18,618, julio 2026) matchean contra `id_ihfintech_loan` real en `dts_okaapi_loans` — mucho más confiable que el cruce `dni`+`producto` de abajo (~96.5%, y con un 13.5% adicional de filas donde ese cruce fallaba por completo pero `aux02` sí resolvía). **Usar `aux02` para cualquier join nuevo contra esta tabla — no reconstruir el cruce `dni`+`producto`.** El campo `dni_ce`+`producto` (fila anterior) sigue siendo el grano de la tabla y sirve para casos que necesiten agrupar por cliente (ej. "otro crédito del mismo cliente en otra fase"), pero para ir de una fila de esta tabla a un crédito específico, `aux02` es la vía correcta. |
| `fecha_base` | fecha de la foto de asignación. **`varchar` (`'YYYY-MM-DD'`), no `date`** — comparar con literal string, no `date('...')`. Datos desde 2026-07-01, continuos hasta hoy |
| `tipo_mora` | `antiguo` / `nuevo` / `sin mora`, calculado A NIVEL CUOTA vigente (`dias_mora >= day(current_date)` → antiguo) y **recalculado a diario** — no fijo como el "tramo" de este proyecto. Homologado contra `dayslate`+bug12: 98.5% de acuerdo en mora 1-30 (ver bug 13, `BUGS.md`); el 1.5% de diferencia son créditos que curan y recaen dentro del mismo mes (este proyecto los mantiene "antiguo" todo el mes por diseño, gestiones_cobranzas los reclasifica a "nuevo") |
| `fase_estrategia` | TEMPRANA / ESPECIALIZADA / RECOVERY — se fija al momento de asignar la campaña, NO se recalcula a diario (un crédito puede seguir en una fase aunque su mora real ya haya cambiado de tramo) |
| `subsegmento_fase_estrategia` | sub-banda de mora dentro de la fase (ej. "VENCIDO 1 A 8"), definida por el negocio — no coincide exactamente con los tramos `a.1-8/b.9-15/c.16-30` que usa el resto del proyecto |
| `dias_mora` / `max_dias_mora_dni` | mora del negocio a nivel cuota — puede diferir de `dayslate` (definición/timing distintos); no mezclar sin verificar |
| `monto_capital_pendiente` / `monto_capital_pendiente_asignado` | saldo según esta tabla — **no usarlo para capital**, seguir el patrón del proyecto de tomar el saldo desde `dts_mambu_loans_hist` (mismo principio que descartó `principalamountpaid`/`principalamountdue`, bug 5 en `BUGS.md`) |
| `grupo_control` | confirmado 2026-08-19 (`reconciliacion_vw_seguimiento_temprana.md`): valores incluyen `'CONTROL'` (créditos deliberadamente NO gestionados, para medir "efecto de la gestión") y `NULL`/otros — explica la mayoría (82%) de los créditos en mora 1-30 propios que NO aparecen en la fase TEMPRANA oficial. Sigue sin explorarse a fondo su uso para medir el efecto causal de la gestión |
| `fecha_de_vencimiento_cuota`, `hora_base`, `fecha_proceso`, `abtest_cob_wapp`, `segmento_piloto_cbr`, `grupo_control_fisica` | columnas nuevas vs. `dts_asignaciones_cobranza`, sin explotar todavía en este proyecto |

**La asignación a Especializada/Recovery es a nivel CLIENTE, no crédito** — si un cliente
tiene otro crédito en mora profunda, todos sus créditos (sanos o no) se asignan a la fase
más severa por arrastre. Ver `avance_cobranza_fase.md` para el detalle completo.

**Tablas hermanas `_recon`:** `dts_asignaciones_gestiones_cobranza_recon`/`_recon_v2`/
`_recon_v3`/`_recon_v4` — mismo esquema, cubren TODO julio (2026-07-01 a 2026-07-31) de una
sola vez. Confirmado por el usuario (2026-08-18): son las tablas que usa `gestiones_
cobranzas` para **validar su propia reconstrucción** (versiones sucesivas de un reproceso,
no la tabla operativa viva) — no usar como fuente de la asignación real del día a día, solo
como referencia si se necesita auditar una reconstrucción puntual de julio.

## `dts_asignaciones_cobranza` (⚠️ congelada desde 2026-07-10, no usar en desarrollo nuevo)

Incorporada 2026-07-13, usada originalmente por `avance_cobranza_fase.md`/`.sql`/`.py`
(corte 2-jul a 12-jul). **Dejó de recibir datos el 2026-07-10** (confirmado 2026-08-18:
rango real `2026-07-02` a `2026-07-10`, 7 días — nunca se actualizó después). Se mantiene
esta sección solo como referencia histórica de esa corrida; cualquier re-corte nuevo debe
usar `dts_asignaciones_gestiones_cobranza` de arriba (mismo grano y columnas, superset).

## `vw_seguimiento_diario_cohorte_tramo` (vista externa "oficial", aportada por el usuario 2026-08-19)

Vista de Athena mantenida FUERA de este proyecto (definición completa en
`vw_seguimiento_diario_cohorte_tramo.txt`, raíz del repo). Da el detalle a nivel crédito
de la asignación real (fase_estrategia, tipo_mora, `monto_asignado` fijado al primer día
del mes que el crédito aparece en `dts_asignaciones_gestiones_cobranza`) y el saldo/mora
de Mambu día a día. Usada como fuente de verdad externa para reconciliar nuestra
población de mora 1-30 — ver `reconciliacion_vw_seguimiento_temprana.md` y bug 14 en
`BUGS.md` para el resultado (cuadra casi exacto en la población compartida; el punto
ciego de `dayslate` explica el 93% de lo que la vista oficial ve y nosotros no, ~27% de
toda la población TEMPRANA). **No usar `monto_asignado` de esta vista como sustituto del
saldo de Mambu para nuestro propio cálculo de capital** — es el mismo campo
`monto_capital_pendiente` de `dts_asignaciones_gestiones_cobranza` que `FUENTES_DATOS.md`
ya advierte no usar (mismo principio que bug 5), aunque en la práctica difiere solo ~1%
del saldo Mambu en la muestra vista hasta ahora.

## Patrón de CTEs base (aparece en casi todos los `.sql` del proyecto)

```sql
with loan_chain as (
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas group by 1
)
, fotos as (
  select ...
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')   -- o solo 'ACTIVE' si es prospectivo, ver DECISIONES.md
    and coalesce(lc.last_in_chain, 1) = 1
)
```

## Ejecutar queries

`scripts/run_athena.sh <archivo.sql>` — envía la query, hace polling del estado, y baja el
CSV de resultado desde S3 (stdout).

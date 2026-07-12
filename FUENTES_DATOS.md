# Fuentes de datos

Las 3 tablas que se usan en prácticamente todo el análisis. DB `dev_datalake_master`,
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

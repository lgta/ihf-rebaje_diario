# Linaje de columnas

> **Nivel de confianza:** lo que dice "confirmado por query" se verificó ejecutando SQL
> contra Athena en esta sesión o sesiones previas. Lo que dice "inferido" se dedujo del
> nombre de la tabla/columna y del patrón de datos, pero **no está confirmado por un
> diccionario de datos oficial ni por el equipo de datos/ingeniería** — si algo de esto
> importa para una decisión de negocio, validarlo con ellos antes de asumirlo.

## Sistemas de origen (inferido por prefijo de tabla y patrón de campos)

| Sistema | Qué es | Tablas que alimenta |
|---|---|---|
| **Mambu** | Core bancario — donde vive el estado real del crédito (saldo, mora, cronograma) | `dts_mambu_loans_hist` (foto diaria completa); campos replicados en `dts_cobranza_creditos_cuotas` |
| **OkaAPI** | Plataforma de originación propia de OKA — donde se crea el crédito | `dts_okaapi_loans` |
| **ETL/analítica interna** | Tablas y campos calculados por el equipo de datos de OKA, no vienen de ningún sistema transaccional directo | Buena parte de `dts_cobranza_creditos_cuotas` (flags de gestión, segmentos de modelo, `flg_last_loan_in_chain`) |

`dts_cobranza_creditos_cuotas` es una tabla **mixta/enriquecida**: junta el cronograma de
cuotas (que en su origen sale de Mambu) con custom fields de Mambu (como
`motivo_apertura`) y con campos que claramente son de analítica interna de cobranza
(`segmento_modelo_cobranza`, `prediccion_riesgo_modelo_mora`, `flg_contacto_whatsapp`,
etc. — nombres que no corresponden a ningún campo estándar de Mambu ni OkaAPI).

## Columna por columna (solo las que usa este proyecto)

| Columna | Tabla | Origen | Tipo | Notas |
|---|---|---|---|---|
| `dayslate` | `dts_mambu_loans_hist` | Mambu (confirmado por query) | Raw | Cálculo propio de Mambu. `NULL` cuando el crédito está al día — ver `GLOSARIO.md`. Tiene el "punto ciego de 1 día" documentado en `BUGS.md` bug 9 |
| `balances_principalbalance` | `dts_mambu_loans_hist` | Mambu | Raw | Saldo capital vigente en esa foto diaria |
| `accountstate`, `accountsubstate` | `dts_mambu_loans_hist` | Mambu | Raw | Estado de cuenta a nivel Mambu (no se usa directamente en este proyecto, se prefiere `status` de `dts_okaapi_loans`) |
| `amountfinanced` | `dts_okaapi_loans` (replicado también en `dts_cobranza_creditos_cuotas`) | OkaAPI | Raw | Monto financiado al desembolso — denominador del avance de amortización |
| `status` | `dts_okaapi_loans` (replicado también en `dts_cobranza_creditos_cuotas`) | OkaAPI | Raw | `ACTIVE`/`COMPLETED`/etc. Ver los dos filtros distintos en `DECISIONES.md` |
| `type`, `producto`, `subproducto` | `dts_okaapi_loans` | OkaAPI | Raw | Clasificación de producto |
| `extendedbyloan_id`, `extendedloan_id` | `dts_okaapi_loans` | OkaAPI (inferido) | Raw | Vínculo entre créditos de una cadena de refinanciamiento — se evaluó como alternativa a `flg_last_loan_in_chain` y se descartó (solo captura ~2% del fenómeno, ver `plan_analisis.md`) |
| `flag_reenganche_mismo_dia/mes/reenganche` | `dts_okaapi_loans` | ETL interno (inferido) | Derivado | No correlaciona limpiamente con `motivo_apertura` (probado en la investigación del Enfoque beta) |
| `installmentstate`, `fechavencimiento`, `dias_vencimiento_a_pago`, `principalamountpaid`, `principalamountdue` | `dts_cobranza_creditos_cuotas` | Mambu, vía cronograma (inferido) | Semi-derivado | `principalamountpaid`/`principalamountdue` están **rotos** para capital — ver `BUGS.md` bug 5. Usar deltas de `balances_principalbalance` en su lugar |
| `flg_last_loan_in_chain` | `dts_cobranza_creditos_cuotas` | ETL interno (inferido) | Derivado | No existe campo equivalente directo en Mambu ni OkaAPI. Constante por crédito (verificado). Fuente adoptada para excluir reenganches — ver `FUENTES_DATOS.md` |
| `"_motivo_apertura__motivo_apertura"` | `dts_cobranza_creditos_cuotas` | Mambu, custom field (inferido por el nombre) | Raw (custom field) | El nombre duplicado (`_grupo__campo`) es el patrón típico de un custom field anidado de la API de Mambu. Poblado en solo 0.4% de créditos. Valores confirmados por el usuario (negocio, 2026-07-12): 1 y 4 = reprogramación; 2 y 3 = adelanto de cuotas o problemas con producto — ver `enfoque_salida_mora.md` |
| `segmento_modelo_cobranza`, `prediccion_riesgo_modelo_cobranza`, `segmento_modelo_mora`, `prediccion_riesgo_modelo_mora`, `flg_contacto_*`, `flg_gestion_*` | `dts_cobranza_creditos_cuotas` | ETL interno / modelos de riesgo de OKA | Derivado | No se usan en este proyecto — mencionados acá solo para dejar constancia de que existen y de dónde vienen (analítica interna, no un sistema transaccional) |

## Métricas calculadas por este proyecto (no son columnas de ninguna tabla)

| Métrica | Fórmula | Combina |
|---|---|---|
| `mora` | `coalesce(dayslate, 0)` | Solo Mambu |
| `tramo` | Bucketing de `mora`: 1-8 / 9-15 / 16-30 | Solo Mambu |
| **Avance de amortización** | `1 - balances_principalbalance / amountfinanced` | Mambu (saldo) + OkaAPI (monto financiado) — es la única métrica de este proyecto que cruza los dos sistemas de origen |
| `rebaje` | `max(saldo_ayer - saldo_hoy, 0)` | Solo Mambu (fotos consecutivas) |
| `avance_band` | Bucketing del avance: &lt;10% / 10-40% / 40-70% / 70%+ | Derivado del avance |

## Pendiente

Todo lo marcado "(inferido)" arriba debería confirmarse con el equipo de datos/ingeniería
de OKA en algún momento — especialmente el origen exacto de `flg_last_loan_in_chain`
(¿lo calcula un ETL, o viene de algún proceso de reenganche identificable en Mambu/OkaAPI
que todavía no se mapeó?). (`motivo_apertura` ya se confirmó con negocio el 2026-07-12,
ver la tabla arriba.)

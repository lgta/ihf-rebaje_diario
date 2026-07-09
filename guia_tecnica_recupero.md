<title>Guía técnica: meta de recupero diaria — metodología, SQL y backtest</title>

# Guía técnica: meta de recupero diaria

Referencia completa para entender y **replicar** el análisis de recupero de cartera en cobranza (mora 1–30 días) en tu propio Athena. Cubre: metodología, estadísticas clave, SQL listo para copiar y correr, cómo se arma la proyección diaria, y el backtest sobre un mes real.

> **Motor de base de datos:** Athena / Presto, sobre `dev_datalake_master`. Las queries de este documento están simplificadas para copiar-pegar; las versiones completas y todas las variantes viven en la carpeta del proyecto (`fase0_diagnostico.sql` … `fase3_backtest.sql`).

---

## Índice

1. [Metodología](#1-metodología)
2. [Estadísticas clave](#2-estadísticas-clave)
3. [Cómo replicar el análisis en Athena](#3-cómo-replicar-el-análisis-en-athena)
4. [Cómo se arma la proyección](#4-cómo-se-arma-la-proyección)
5. [Backtest: validación sobre un mes real](#5-backtest-validación-sobre-un-mes-real)
6. [Archivos y siguiente paso](#6-archivos-y-siguiente-paso)

---

## 1. Metodología

### 1.1 El objetivo

Estimar, **día a día**, cuánto saldo capital debería recuperarse de la cartera de cobranza en mora 1–30 días — no solo un número al cierre del mes, sino una curva diaria contra la cual comparar el avance real.

### 1.2 Por qué no se promedia el rebaje diario

El primer instinto — dividir el rebaje del mes entre 30 días — no sobrevive al primer chequeo de datos (ver [§2.1](#21-el-pago-es-un-evento-no-un-flujo)): el pago es un evento puntual, no un goteo. El modelo en cambio separa **frecuencia** de **magnitud**:

```
Recupero esperado = P(el crédito paga dentro de la ventana) × E(% del saldo que rebaja al pagar)
```

### 1.3 Dos poblaciones, dos motores

| Población | Qué es | Se mide con |
|---|---|---|
| **Stock** | Créditos con mora 1–30 al cierre del mes anterior. Se conoce por completo desde el día 1. | Curva de recupero acumulado por **tramo de mora** y día del mes. |
| **Nuevos** | Créditos que no estaban en mora al iniciar el mes pero dejan de pagar una cuota durante el mes. | Curva de recupero acumulado por **días desde que entró en mora**, aplicada a una cohorte por cada día de vencimiento del calendario. |

El **tramo** (para stock) y el **día de entrada** (para nuevos) determinan *cuánto tiempo* tiene el crédito para madurar dentro del mes. El **avance de amortización** (`saldo capital / monto financiado`) determina *cuánto rebaja* cuando paga — es el segmentador de severidad que aplica igual a ambas poblaciones.

### 1.4 Definiciones operativas

| Término | Definición |
|---|---|
| Tramo | 1–8 / 9–15 / 16–30 días de mora al cierre del mes anterior. Se conserva todo el mes aunque el crédito cruce los 30 días. |
| Avance de amortización | `saldo_capital / monto_financiado`. Bandas: <10%, 10–40%, 40–70%, 70%+. |
| Entrada en mora | Transición `dayslate` 0→1 (o `NULL`→1) para un crédito. |
| Rebaje diario | `max(saldo_ayer − saldo_hoy, 0)` — los aumentos de saldo (ruido, <2% del total) se tratan como 0. |
| Cadena / reenganche | Un crédito reemplazado por uno nuevo (refinanciamiento). Se excluye vía `flg_last_loan_in_chain`. |

---

## 2. Estadísticas clave

### 2.1 El pago es un evento, no un flujo

De los crédito-mes en mora (14 meses, mar-2025 a jun-2026):

| # de días con rebaje en el mes | % de crédito-mes |
|---|---|
| 0 | 24% |
| 1 | 68% |
| 2 | 8% |
| 3+ | <1% |

**92% tiene cero o un solo evento de pago al mes.** Esto es lo que descarta modelar "rebaje diario promedio" y obliga al enfoque evento × magnitud.

### 2.2 Motor del stock — recupero por tramo

| Tramo (mora al inicio de mes) | % que paga algo en el mes | Severidad si paga | **Recupero total del mes** |
|---|---|---|---|
| 1–8 días | 83% | 23.3% | **18.1%** |
| 9–15 días | 58% | 24.2% | **12.7%** |
| 16–30 días | 39% | 23.8% | **7.8%** |

**Hallazgo clave:** la severidad es prácticamente **plana** entre tramos (~24%). El tramo predice si el crédito paga, no cuánto rebaja cuando lo hace.

Severidad por avance de amortización (tramo 1–8):

| Avance | Severidad |
|---|---|
| < 10% | 14.9% |
| 10–40% | 20.2% |
| 40–70% | 40.8% |
| 70%+ | 74.8% |

### 2.3 Motor de nuevos — recupero por días desde entrada en mora

| Día desde entrada | 1 | 8 | 15 | 30 | 31 |
|---|---|---|---|---|---|
| % recuperado acum. | 4.5% | 12.8% | 14.8% | 20.8% | 22.3% |

Segmentado por avance (día 31):

| Avance | % recuperado (d31) |
|---|---|
| < 10% | 14.4% |
| 10–40% | 19.8% |
| 40–70% | 40.9% |
| 70%+ | 74.2% |

### 2.4 Validación cruzada con # de operaciones

Reconstruyendo la curva de pago por días-desde-vencimiento en **# de operaciones** (no capital), como control independiente: **72.6%** paga a tiempo, **81.2%** acumulado al día 1, plateau **93.8%** al día 31 — consistente con la referencia de negocio (~70% / ~85%).

> ⚠️ Esta curva de # de operaciones es de **cuota** (`dts_cobranza_creditos_cuotas`), y **no es intercambiable** con la tasa de entrada a mora a nivel **crédito** (`dayslate`). Confundir las dos fue la causa del primer error grande del backtest — ver [§5](#5-backtest-validación-sobre-un-mes-real).

---

## 3. Cómo replicar el análisis en Athena

Todas las queries asumen la base `dev_datalake_master` y estas tres tablas:

| Tabla | Para qué |
|---|---|
| `dts_mambu_loans_hist` | Foto diaria de saldo capital y `dayslate` por crédito (histórico completo). |
| `dts_okaapi_loans` | Producto, monto financiado, término, estado del crédito. |
| `dts_cobranza_creditos_cuotas` | Calendario de cuotas: vencimiento, estado, `flg_last_loan_in_chain`. |

### 3.1 Diagnóstico previo (correr una vez, antes de todo)

**Grumosidad del pago** — confirma el enfoque evento × magnitud:

```sql
with base as (
select
  substr(a.fechaproceso, 1, 6)                       as periodo
, cast(substr(a.fechaproceso, 7, 2) as int)          as dia
, a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
, a.balances_principalbalance                        as saldo
, a.dayslate
, lag(a.balances_principalbalance) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as saldo_ant
from dts_mambu_loans_hist a
join dts_okaapi_loans b
  on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and a.fechaproceso >= '20250301'
)
, credito_mes as (
select periodo, id_loan
, sum(case when saldo_ant > saldo then 1 else 0 end) as dias_con_rebaje
, max(dayslate) as mora_max
, max(case when dia = 1 then dayslate end) as mora_dia1
from base
group by 1, 2
)
select dias_con_rebaje, count(*) as creditos_mes,
  round(100.0 * count(*) / sum(count(*)) over (), 2) as pct
from credito_mes
where mora_max >= 1 and coalesce(mora_dia1, 0) <= 30
group by 1
order by 1;
```

**Mecánica de `dayslate`** — confirma que es `NULL` al día (no `0`), y que la mora avanza limpiamente:

```sql
with base as (
select
  a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
, coalesce(a.dayslate, 0)                            as mora
, lag(coalesce(a.dayslate, 0)) over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as mora_ant
, row_number() over (
    partition by a._datos_adicionales_loan_accounts_id_ihfintech
    order by a.fechaproceso)                         as nro_foto
from dts_mambu_loans_hist a
join dts_okaapi_loans b
  on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
where b.status in ('ACTIVE','COMPLETED')
  and a.fechaproceso >= '20250301'
)
select
  case
    when nro_foto = 1                  then 'a. primer registro'
    when mora_ant = 0 and mora = 0     then 'b. al dia'
    when mora_ant = 0 and mora = 1     then 'c. entra en mora'
    when mora = mora_ant + 1           then 'd. mora avanza +1'
    when mora = mora_ant and mora > 0  then 'e. mora congelada'
    when mora_ant > 0 and mora = 0     then 'f. cura'
    else                                    'g. otro'
  end as transicion
, count(*) as filas
, round(100.0 * count(*) / sum(count(*)) over (), 2) as pct
from base
group by 1
order by 1;
```

> **Checklist antes de seguir:** ¿el pago sale grumoso (>85% con 0–1 evento/mes)? ¿`dayslate` viene `NULL` al día? Si tu cartera se comporta distinto, ajusta el modelo antes de copiar el resto.

### 3.2 CTEs base — reutilizadas en todo lo demás

Este bloque de CTEs es el corazón del pipeline. Aparece (con pequeñas variaciones) en Fase 1, 2 y 3:

```sql
with loan_chain as (
  -- flg_last_loan_in_chain vive a nivel CUOTA; se deriva a nivel CREDITO
  -- (es constante por credito, verificado). dts_okaapi_loans NO tiene
  -- un campo equivalente directo.
  select id_ihfintech_loan, max(flg_last_loan_in_chain) as last_in_chain
  from dts_cobranza_creditos_cuotas
  group by 1
)
, fotos as (
  select
    substr(a.fechaproceso, 1, 6)                       as periodo
  , a.fechaproceso
  , a._datos_adicionales_loan_accounts_id_ihfintech    as id_loan
  , a.balances_principalbalance                        as saldo
  , coalesce(a.dayslate, 0)                            as mora
  , b."term"                                           as term
  , b.amountfinanced
  , lag(a.balances_principalbalance) over (
      partition by a._datos_adicionales_loan_accounts_id_ihfintech
      order by a.fechaproceso)                         as saldo_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b
    on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc
    on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED')   -- HISTORICO: incluye COMPLETED
    and a.fechaproceso >= '20250301'
    and coalesce(lc.last_in_chain, 1) = 1     -- excluye reenganches
)
```

**Dos filtros que casi siempre se equivocan al replicar esto:**

1. `status IN ('ACTIVE','COMPLETED')`, nunca solo `'ACTIVE'` — para análisis **histórico**. `COMPLETED` son los que ya terminaron de pagar bien; excluirlos sesga cualquier ratio hacia abajo. (Para un calendario **prospectivo** — "qué va a vencer" — sí usar `status='ACTIVE'` solamente, ver [§4.3](#43-el-calendario-de-vencimientos)).
2. `coalesce(lc.last_in_chain, 1) = 1` — sin esto, los créditos reenganchados dejan cuotas "colgadas" que distorsionan cualquier curva calculada sobre el total de cartera.

### 3.3 Fase 1 — Curva del stock (por tramo × día)

```sql
with loan_chain as (...)     -- igual que 3.2
, fotos as (...)             -- igual que 3.2
, cierre_mes as (
  select *, row_number() over (partition by id_loan, periodo order by fechaproceso desc) as rn
  from fotos
)
, stock as (
  select
    date_format(date_add('month', 1, date_parse(periodo, '%Y%m')), '%Y%m') as periodo_meta
  , id_loan, saldo as saldo_inicial
  , case when mora between 1 and 8  then 'a. 1-8'
         when mora between 9 and 15 then 'b. 9-15'
         else                            'c. 16-30' end as tramo
  from cierre_mes
  where rn = 1 and mora between 1 and 30 and saldo > 0
)
, rebajes as (
  select s.periodo_meta, s.tramo, s.id_loan, s.saldo_inicial, f.dia,  -- f.dia = substr(fechaproceso,7,2)
    case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from stock s
  join fotos f on f.id_loan = s.id_loan and f.periodo = s.periodo_meta
  where s.periodo_meta between '202504' and '202606'   -- <-- AJUSTAR a tu ventana
)
, rebaje_dia as (select tramo, dia, sum(rebaje) as rebaje_dia from rebajes group by 1, 2)
, saldo_ini as (select tramo, sum(saldo_inicial) as saldo_inicial_total from stock
                 where periodo_meta between '202504' and '202606' group by 1)
select r.tramo, r.dia,
  round(sum(r.rebaje_dia) over (partition by r.tramo order by r.dia) / s.saldo_inicial_total * 100, 3) as pct_recupero_acum
from rebaje_dia r join saldo_ini s on s.tramo = r.tramo
order by r.tramo, r.dia;
```

> ⚠️ **Gotcha de Presto/Athena:** si filtras `WHERE dia IN (...)` en la MISMA query que un `SUM(...) OVER (ORDER BY dia)`, el `WHERE` se aplica **antes** de la window function y el acumulado arranca mal. Si quieres solo algunos días, envuélvelo en una subconsulta: calcula el acumulado completo primero, filtra después.

### 3.4 Fase 2 — Curva de nuevos (por días desde entrada en mora)

```sql
with loan_chain as (...)     -- igual que 3.2, pero fechaproceso >= '20250201'
, fotos as (
  select ..., 
    lag(coalesce(a.dayslate,0)) over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant,
    row_number() over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as nro_foto
  from ...   -- misma base, con mora_ant y nro_foto agregados
)
, entradas as (
  select id_loan, fechaproceso as fecha_entrada,
    date_parse(fechaproceso, '%Y%m%d') as fecha_entrada_d,
    saldo as saldo_entrada, amountfinanced,
    case when saldo >= 0.9*amountfinanced then 'a. avance <10%'
         when saldo >= 0.6*amountfinanced then 'b. avance 10-40%'
         when saldo >= 0.3*amountfinanced then 'c. avance 40-70%'
         else 'd. avance 70%+' end as avance_band
  from fotos
  where nro_foto > 1 and mora_ant = 0 and mora = 1
    and fechaproceso between '20250301' and '20260531'   -- deja 31+ dias de cola
)
, rebajes as (
  select e.id_loan, e.avance_band, e.saldo_entrada,
    date_diff('day', e.fecha_entrada_d, date_parse(f.fechaproceso, '%Y%m%d')) as dia_desde_entrada,
    case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end as rebaje
  from entradas e
  join fotos f on f.id_loan = e.id_loan
    and f.fechaproceso > e.fecha_entrada
    and f.fechaproceso <= date_format(date_add('day', 31, e.fecha_entrada_d), '%Y%m%d')
)
, rebaje_dia as (select avance_band, dia_desde_entrada, sum(rebaje) as rebaje_dia from rebajes group by 1,2)
, base_total as (select avance_band, sum(saldo_entrada) as saldo_entrada_total from entradas group by 1)
select r.avance_band, r.dia_desde_entrada,
  round(sum(r.rebaje_dia) over (partition by r.avance_band order by r.dia_desde_entrada) / b.saldo_entrada_total * 100, 3) as pct_recupero_acum
from rebaje_dia r join base_total b on b.avance_band = r.avance_band
order by r.avance_band, r.dia_desde_entrada;
```

### 3.5 Validación en # de operaciones (opcional, cruce independiente)

```sql
with cuotas as (
  select id_ihfintech_loan, id_loan_nro_cuota, installmentstate, dias_vencimiento_a_pago
  from dts_cobranza_creditos_cuotas
  where fechavencimiento >= date('2025-03-01') and fechavencimiento <= date('2026-05-31')
    and status in ('ACTIVE','COMPLETED')
    and flg_last_loan_in_chain = 1        -- <-- critico, ver nota abajo
)
, dias as (select d as dia from unnest(sequence(0, 31)) as t(d))
select d.dia,
  count(distinct case when c.installmentstate = 'PAID' and c.dias_vencimiento_a_pago <= d.dia
                       then c.id_loan_nro_cuota end) * 100.0
    / count(distinct c.id_loan_nro_cuota) as pct_operaciones_acum
from cuotas c cross join dias d
group by 1 order by 1;
```

> ⚠️ Sin `flg_last_loan_in_chain = 1` esta curva sale ~10 puntos más baja de lo real — las cuotas de créditos reenganchados quedan `LATE` para siempre y arrastran el promedio. NO uses `principalamountpaid`/`principalamountdue` de esta tabla para capital — están rotos para este propósito (sobre-atribuyen pagos anticipados; el acumulado supera 400%).

---

## 4. Cómo se arma la proyección

### 4.1 La fórmula

```
Meta_acumulada(d) = Stock_acumulado(d) + Nuevos_acumulado(d)

Stock_acumulado(d)  = Σ(tramo,avance)  saldo_stock(tramo,avance) × curva_stock(tramo,avance,d)

Nuevos_acumulado(d) = Σ(D≤d) Σ(avance) saldo_en_riesgo(D,avance) × P(no paga a tiempo) × curva_nuevos(avance, d−D)
```

### 4.2 La mecánica de cohortes (la pieza no trivial)

Cada día `D` del calendario de vencimientos que un grupo de créditos no paga a tiempo, nace una **cohorte** con su propio reloj. Al proyectar el día `d`, cada cohorte activa aporta el valor de `curva_nuevos` en `d − D` días de maduración. Un crédito que entra en mora el día 20 nunca "ve" el valor de la curva en el día 25 — el mes se cierra antes.

En pseudocódigo (así está implementado en `armar_trayectoria_seg.py`):

```python
for d in range(1, N_DIAS + 1):
    stock_cum = sum(saldo_stock[t, a] * curva_stock[t, a][d] for t, a in segmentos)
    nuevos_cum = 0
    for D in range(1, d + 1):
        dias_desde_entrada = d - D
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in calendario[D].items():
            nuevos_cum += saldo_riesgo * P_NO_PAGA * curva_nuevos[avance][dias_desde_entrada]
    meta[d] = stock_cum + nuevos_cum
```

### 4.3 El calendario de vencimientos

**Regla importante — dos filtros distintos según se mire pasado o futuro:**

| | Histórico / calibración | Calendario prospectivo | Backtest (mes cerrado) |
|---|---|---|---|
| `status` | `IN ('ACTIVE','COMPLETED')` | `= 'ACTIVE'` solamente | `IN ('ACTIVE','COMPLETED')` |
| `installmentstate` | (no aplica) | `= 'PENDING'` | (sin filtro — ya se conoce el desenlace) |
| `flg_last_loan_in_chain` | `= 1` | `= 1` | `= 1` |

Un crédito `COMPLETED` ya no tiene obligaciones futuras — por eso el calendario prospectivo usa `status='ACTIVE'` solo. Pero para reconstruir un mes ya cerrado, si filtras por `installmentstate='PENDING'` te perderías las cuotas que ya se resolvieron (que son casi todas) — ahí no filtras por estado, porque el desenlace real ya lo sabes por `dts_mambu_loans_hist`.

```sql
-- Calendario PROSPECTIVO (para proyectar el mes en curso o el siguiente)
select
  c.fechavencimiento
, case when b.balances_principalbalance >= 0.9*b.amountfinanced then 'a. avance <10%'
       when b.balances_principalbalance >= 0.6*b.amountfinanced then 'b. avance 10-40%'
       when b.balances_principalbalance >= 0.3*b.amountfinanced then 'c. avance 40-70%'
       else 'd. avance 70%+' end as avance_band
, round(sum(b.balances_principalbalance), 0) as saldo_en_riesgo
from dts_cobranza_creditos_cuotas c
join dts_okaapi_loans b on b.id_ihfintech_loan = c.id_ihfintech_loan
where c.status = 'ACTIVE'
  and c.flg_last_loan_in_chain = 1
  and c.fechavencimiento > date(current_date)
  and c.installmentstate = 'PENDING'
  and b.amountfinanced > 0
group by 1, 2
order by 1, 2;
```

### 4.4 Dos enfoques, mantenidos en paralelo

Se conservan **dos formas de calcular la meta**, a pedido explícito, para poder compararlas:

| | Agregado | Segmentado |
|---|---|---|
| Curva de stock | Una por tramo | Cruzada tramo × avance |
| Curva de nuevos | Una global | Cruzada por avance |
| Corrida de referencia (31 días) | S/ 3,763,453 | S/ 3,592,446 (**−4.5%**) |

La segmentada es más fiel a la mezcla real de la cartera; la agregada es más simple de mantener. La diferencia entre ambas (−4.5% en la corrida de referencia) es, en sí misma, una señal útil: si crece con el tiempo, indica que la mezcla de avance de la cartera se está moviendo respecto al promedio histórico.

---

## 5. Backtest: validación sobre un mes real

### 5.1 Diseño del backtest

Se reconstruyó la meta que se habría fijado el **1 de junio de 2026**, y se comparó contra el recupero **real** de junio (ya cerrado), día a día:

- **Stock** anclado al cierre real de mayo-2026 (no al día de la consulta).
- **Calendario** de junio reconstruido con `fechavencimiento` real, sin filtrar por `installmentstate`.
- **Recupero real** calculado con el mismo método fotos-based de las Fases 1/2, separado en población stock vs. población que entró en mora durante junio.

```sql
-- Recupero REAL diario de junio, poblacion STOCK (para comparar contra la proyeccion)
with loan_chain as (...), fotos as (... con lag, fechaproceso 20260501-20260630 ...)
, fotos_may_close as (
  select id_loan, saldo, mora, row_number() over (partition by id_loan order by fechaproceso desc) as rn
  from fotos where fechaproceso <= '20260531'
)
, stock_junio_ids as (
  select id_loan from fotos_may_close where rn=1 and mora between 1 and 30 and saldo > 0
)
select f.fechaproceso, sum(case when f.saldo_ant > f.saldo then f.saldo_ant - f.saldo else 0 end) as rebaje_dia
from fotos f join stock_junio_ids s on s.id_loan = f.id_loan
where f.fechaproceso >= '20260601' and f.fechaproceso <= '20260630'
group by 1 order by 1;
```

*(La versión completa, incluida la contraparte para "nuevos", está en `fase3_backtest.sql` bloques 3G-3 y 3G-4.)*

### 5.2 Primer intento: +79% de error

La primera corrida sobreestimó junio por 79%. La causa: la constante `P(no paga a tiempo)` usada en la fórmula (27.4%, tomada del **día 0 de la curva de `dias_vencimiento_a_pago` a nivel cuota**, §2.4) no corresponde a la tasa real de créditos que transicionan a mora **a nivel crédito** (`dayslate` 0→1). Son dos fenómenos distintos — probablemente `dayslate` tiene un período de gracia antes de marcar mora oficial, mientras que la curva de cuotas cuenta cualquier atraso desde el día 1.

### 5.3 Recalibración — y por qué no usar el dato del propio junio

Medida directamente en junio, la tasa real fue 10.96%. Pero usar el dato del **propio mes que se está validando** para calibrar el modelo es *data leakage* — de curso, el backtest saldría bien. La calibración correcta usa **10 meses anteriores a junio, sin incluirlo**:

```sql
-- Tasa de entrada a mora, fuera de muestra (ago-2025 a may-2026, SIN junio)
with loan_chain as (...)
, fotos as (
  select substr(a.fechaproceso,1,6) as periodo, a.fechaproceso,
    a._datos_adicionales_loan_accounts_id_ihfintech as id_loan,
    coalesce(a.dayslate, 0) as mora,
    lag(coalesce(a.dayslate, 0)) over (partition by a._datos_adicionales_loan_accounts_id_ihfintech order by a.fechaproceso) as mora_ant
  from dts_mambu_loans_hist a
  join dts_okaapi_loans b on b.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  left join loan_chain lc on lc.id_ihfintech_loan = a._datos_adicionales_loan_accounts_id_ihfintech
  where b.status in ('ACTIVE','COMPLETED') and coalesce(lc.last_in_chain,1) = 1
    and a.fechaproceso >= '20250201'
)
, cierre_mes as (
  select periodo, id_loan, mora, row_number() over (partition by id_loan, periodo order by fechaproceso desc) as rn
  from fotos
)
, stock_ids as (   -- excluir del "elegible" a los que ya estaban en mora (son stock, no nuevos)
  select date_format(date_add('month',1,date_parse(periodo,'%Y%m')), '%Y%m') as periodo_target, id_loan
  from cierre_mes where rn = 1 and mora between 1 and 30
)
, entradas as (select distinct periodo, id_loan from fotos where mora_ant = 0 and mora = 1)
, calendario as (
  select substr(cast(c.fechavencimiento as varchar),1,7) as periodo_venc, c.id_ihfintech_loan as id_loan
  from dts_cobranza_creditos_cuotas c
  where c.status in ('ACTIVE','COMPLETED') and c.flg_last_loan_in_chain = 1
    and c.fechavencimiento >= date('2025-08-01') and c.fechavencimiento <= date('2026-05-31')
)
, calendario_mes as (
  select replace(periodo_venc,'-','') as periodo, id_loan
  from calendario cal
  where not exists (select 1 from stock_ids s where s.periodo_target = replace(cal.periodo_venc,'-','') and s.id_loan = cal.id_loan)
  group by 1, 2
)
select cm.periodo,
  count(distinct cm.id_loan) as elegibles,
  count(distinct e.id_loan) as entradas,
  round(100.0*count(distinct e.id_loan)/count(distinct cm.id_loan), 2) as pct_entra_en_mora
from calendario_mes cm
left join entradas e on e.periodo = cm.periodo and e.id_loan = cm.id_loan
group by 1 order by 1;
```

**Resultado:** estable entre 11.4% y 14.6% mes a mes, promedio ponderado **13.38%** (47,966 entradas / 358,580 elegibles). Este es el valor correcto para `P(no paga a tiempo)` — reemplaza el 27.4% original.

### 5.4 Resultado final del backtest

| Día de junio | Proyectado acum. | Real acum. | Error |
|---|---|---|---|
| 10 | S/ 637,700 | S/ 548,638 | +16.2% |
| 19 | S/ 1,114,598 | S/ 1,058,352 | +5.3% |
| 25 | S/ 1,448,039 | S/ 1,377,155 | +5.1% |
| **30 (cierre)** | **S/ 1,806,299** | **S/ 1,713,815** | **+5.4%** |

Descomposición del cierre:

| Componente | Proyectado | Real | Error |
|---|---|---|---|
| Stock | S/ 601,379 | S/ 517,683 | +16.2% |
| Nuevos | S/ 1,204,920 | S/ 1,196,132 | **+0.7%** |

El motor de **nuevos** — la mecánica de cohortes, la pieza más nueva del modelo — acertó casi exacto. El motor de **stock** sobreestimó 16.2%, dentro del rango de variación mensual ya observado al calibrar (el tramo 9–15 osciló entre 9.8% y 18.8% de un mes a otro en los 14 meses de historia).

### 5.5 Qué NO está resuelto todavía

- **Un solo mes de backtest.** Junio es un punto de dato. Antes de tratar ±5–16% como error típico, hay que repetir esto en 3–6 meses más.
- **Las curvas de stock/nuevos siguen calibradas sobre los 14 meses completos** (incluyen junio, con peso marginal ~1/14) — no son estrictamente fuera de muestra. Un backtest totalmente riguroso las recalcularía excluyendo cada mes de prueba.
- **La sobreestimación de stock (+16.2%)** no está explicada — podría ser varianza normal de junio, o un segmentador adicional que falta.
- **`installmentlastpaiddate`** (nivel cuota, dato aportado por el usuario) — pendiente de usar para cuantificar el período de gracia de `dayslate` que causó el error de +79%, cruzándolo contra el día exacto en que `dayslate` pasa a 1 para el mismo crédito.

---

## 6. Archivos y siguiente paso

| Archivo | Contiene |
|---|---|
| `fase0_diagnostico.sql` | Los 5 diagnósticos de §2.1 y calidad de datos. |
| `fase1_stock.sql` | Curva de stock, estabilidad mensual, frecuencia×severidad, segmentadores. |
| `fase2_nuevos.sql` | Curva de nuevos, validación en # operaciones, segmentación por avance. |
| `fase3_meta.sql` | Calendario prospectivo, stock vigente, mecánica de combinación (§4). |
| `fase3_backtest.sql` | Las queries de §5 completas (stock de junio, calendario real, recupero real, calibración fuera de muestra). |
| `armar_trayectoria_seg.py` | Combina los CSV de Athena en la trayectoria diaria — ventana rodante. |
| `backtest_junio.py` | Igual, pero para comparar contra un mes cerrado (`python backtest_junio.py`). |
| `plan_analisis.md` | Bitácora técnica completa — todas las decisiones, corridas y correcciones, en orden cronológico. |

**Siguiente paso natural:** extender el backtest a más meses cerrados (repetir §5 con julio, agosto, etc. una vez cierren) para saber si el ±5.4% de junio es representativo.

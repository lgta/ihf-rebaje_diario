# Enfoque beta: salida de mora (cura real vs. reestructuración)

> **Estado: exploratorio.** Se validó el patrón con datos reales (2026-07-10) y se publicó
> como hallazgo — [🔓 Salida de mora — hallazgos](https://claude.ai/code/artifact/f1b0c577-4044-40a3-bebd-e01f5141ed98)
> (`salida_mora.html`) — pero todavía no hay curva día a día ni proyección, a diferencia
> de `enfoque_capital_asegurado.md` (Enfoque alfa). Falta decidir el siguiente paso —
> ver "Pendientes" al final.

## El concepto

No basta con que el sistema deje de marcar mora (`dayslate` vuelve a 0) para contar como
una salida real de mora — el saldo capital también tiene que haber bajado durante el
episodio. Los casos donde el crédito sale de mora **sin que el saldo baje** son candidatos
a **reestructuración crediticia**: una facilidad de pago que resetea el estado de mora sin
que haya cobro real de por medio.

Propuesto por el usuario el 2026-07-10, con la pista de revisar si existe una columna
`motivo_apertura` (valores 1-4) que ayude a confirmar la hipótesis.

## Metodología

1. **Detección de episodios de mora completos** (entrada → salida) por crédito, usando el
   patrón SQL "gaps and islands" (`rn − row_number() partition by id_loan, en_mora`) para
   agrupar corridas consecutivas de `mora>0`.
2. Para cada episodio: `saldo_entrada` (saldo el día que entra en mora) vs. `saldo_salida`
   (saldo el primer día que vuelve a mora=0).
3. Clasificación:
   - **Cura real** (baja >1% el saldo): pago genuino.
   - **Cura parcial** (baja ≤1%): probablemente ruido/redondeo, no reestructuración.
   - **Cura sin pago** (el saldo no baja): candidato a reestructuración.
   - **Sin salida observada**: el episodio sigue abierto al final de la ventana de datos
     (censurado, no se puede clasificar).
4. **Validación cruzada** contra `dts_cobranza_creditos_cuotas."_motivo_apertura__motivo_apertura"`
   (nombre así de literal — viene de un custom field anidado de Mambu). Está poblada en
   solo 721 de ~198,000 créditos (0.4%). Diccionario confirmado por el usuario (negocio,
   2026-07-12): 1 y 4 = reprogramación; 2 y 3 = adelanto de cuotas o problemas con
   producto — ver el desglose recalculado más abajo.

Queries completas: `enfoque_salida_mora.sql` (Q1 clasificación agregada, Q2 desglose por
código de motivo, Q3 referencia de valores de motivo_apertura).

## SQL explicado

**El truco "gaps and islands" (agrupar días consecutivos en mora):** con las fotos
diarias ordenadas (`fotos`), se crea `mora_flag` con `en_mora = case when mora>0 then 1
else 0 end`. Después, la parte no obvia:

```sql
rn - row_number() over (partition by id_loan, en_mora order by fechaproceso) as grp
```

`rn` es la posición de la fila en la serie completa del crédito (1, 2, 3, 4...). El
segundo `row_number()` cuenta solo dentro de las filas con el MISMO `en_mora` (por
ejemplo, solo entre los días en mora). Mientras los días en mora sean consecutivos, ambos
contadores avanzan al mismo ritmo y su resta (`grp`) da el mismo número — pero apenas hay
una interrupción (el crédito cura y vuelve a entrar en mora después), `rn` sigue subiendo
con TODOS los días de por medio mientras el segundo contador solo cuenta los días en mora,
así que la resta salta a un valor distinto. Cada valor distinto de `grp` es un episodio
distinto — de ahí el nombre "islas" (los episodios) separadas por "huecos" (los días al
día). Agrupando por `(id_loan, grp)` con `en_mora=1` se obtiene un episodio por fila:
`fecha_inicio`, `fecha_fin`, `rn_inicio`, `rn_fin`.

**Encontrar el saldo de entrada y de salida:** `saldo_entrada` es la foto en `rn_inicio`
(el primer día del episodio). `saldo_salida` es la foto en `rn_fin + 1` — la fila
INMEDIATAMENTE siguiente a la última en mora, vía un `left join` sobre `rn`. Como las
fotos diarias no tienen huecos (validado en `fase0_diagnostico.sql`), `rn_fin + 1` es
siempre literalmente "el día siguiente" — no hace falta calcular fechas. Si no existe esa
fila (el crédito sigue en mora al final de la ventana de datos), `saldo_salida` sale
`NULL` → se clasifica como "sin salida observada" (censurado).

**Clasificación:** `saldo_entrada - saldo_salida` comparado contra el umbral de 1% del
saldo de entrada — no un umbral fijo en soles, porque episodios de créditos grandes y
chicos necesitan un criterio proporcional.

**Cruce con motivo_apertura (Q1/Q2):** simple `left join`/`join` contra un `select
distinct id_ihfintech_loan, "_motivo_apertura__motivo_apertura"` de
`dts_cobranza_creditos_cuotas` filtrando `is not null` — el campo es constante por
crédito (aunque vive a nivel cuota), por eso el `distinct` alcanza para des-duplicar.

## Resultados (2025-03 a 2026-05)

> **Corregido 2026-07-13** (ver `BUGS.md` bug 11): la primera corrida tenía un bug de
> filas duplicadas por (crédito, día) en `dts_mambu_loans_hist` sin desempate, que
> fragmentaba episodios reales en varios episodios falsos — afectaba sobre todo a
> `cura_sin_pago` (episodios más cortos, más sensibles a una foto de más). Los conteos de
> abajo ya están corregidos con el fix de dedup. **El hallazgo cualitativo (la razón
> ~97x/~15x por motivo_apertura) no cambió de forma material** — solo los conteos crudos.

| Clasificación | Episodios | Créditos | Saldo de entrada | % con `motivo_apertura` |
|---|---:|---:|---:|---:|
| Cura real (baja >1%) | 70,208 | 34,191 | S/104,554,272 | 0.9% |
| Cura parcial (baja ≤1%) | 120 | 117 | S/663,482 | 6.8% |
| **Cura sin pago (no baja)** | **376** | **363** | **S/1,121,302** | **68.6%** |
| Sin salida observada | 7,300 | 7,300 | S/15,479,914 | 2.8% |

**El patrón confirma la hipótesis del usuario, con una señal muy fuerte:** un crédito que
sale de mora sin bajar su saldo tiene ~75 veces más probabilidad de tener
`motivo_apertura` registrado que uno que sale pagando de verdad (68.6% vs. 0.9%).

### Desglose por código de motivo_apertura (dentro de cura_real vs. cura_sin_pago)

| Clasificación | motivo=1 | motivo=2 | motivo=3 | motivo=4 |
|---|---:|---:|---:|---:|
| Cura real — créditos | 223 | 83 | 2 | 4 |
| Cura real — días en mora prom. | 12.9 | 5.8 | 89.3 | 55.8 |
| Cura sin pago — créditos | 230 | 12 | 2 | 5 |
| Cura sin pago — días en mora prom. | 48.8 | 19.5 | 22.0 | 155.0 |

**Diccionario confirmado por el usuario (negocio), 2026-07-12:** `motivo_apertura` 1 y 4
= reprogramación; 2 y 3 = adelanto de cuotas o problemas con producto.

Agrupando por esa definición y normalizando por el tamaño de cada población (no solo el
conteo crudo dentro del 0.4% con el campo poblado), el mapeo sí es limpio:

| Motivo agrupado | % de créditos cura_sin_pago (n=363) | % de créditos cura_real (n=34,191) | Razón |
|---|---:|---:|---:|
| Reprogramación (1+4) | 64.7% | 0.7% | ~98x |
| Adelanto/producto (2+3) | 3.9% | 0.2% | ~16x |

La reprogramación explica la gran mayoría de las "curas sin pago": casi dos tercios de
esos 363 créditos tienen el código, contra apenas 0.7% de los que curaron pagando de
verdad. El código 1 aislado ya lo insinuaba (dentro de motivo=1, "cura sin pago" pasa casi
4x más tiempo en mora antes de salir que "cura real": 48.8 vs. 12.9 días — con el fix de
dedup esta brecha se ve más grande que en la primera corrida, no más chica) pero al
agruparlo con el 4 y normalizar por población, la señal deja de ser ambigua. Adelanto de
cuotas/problemas con producto (2+3) también aparece algo elevado en cura_sin_pago (~16x)
pero es un orden de magnitud menos frecuente que la reprogramación — no es el motor
principal del fenómeno.

## Reincidencia: ¿los créditos "cura sin pago" vuelven a caer en mora?

Investigado 2026-07-13 (opción b de los pendientes, ver abajo) — pregunta clave para
saber si construir la curva completa (opción a) vale la pena, y para el hallazgo de
"pérdida de cronicidad" de la sección anterior.

**Metodología:** de los episodios con salida observada antes del 2026-04-01 (para
garantizar ≥90 días de seguimiento uniforme dentro de la ventana de datos, que llega
hasta 2026-06-30 — sin este corte, los episodios más recientes tendrían menos tiempo para
recaer y sesgarían la tasa hacia abajo), se busca si el mismo crédito tiene un episodio de
mora POSTERIOR (`lead(fecha_inicio)` particionado por crédito), sin importar cómo se
resuelva ese episodio siguiente. Queries: `enfoque_salida_mora.sql` Q4 (resumen) y Q5
(distribución de días hasta recaída). Resultado cacheado en `datos_salida_mora/`.

| Clasificación | Episodios elegibles | Con recaída | % recae | Días prom. hasta recaída | Mediana |
|---|---:|---:|---:|---:|---:|
| Cura real | 51,852 | 33,078 | **63.8%** | 38.8 | 28.1 |
| Cura sin pago | 287 | 232 | **80.8%** | 42.6 | 31.0 |

**Distribución de días hasta recaída (solo los que sí recaen):**

| Bucket | Cura real | Cura sin pago |
|---|---:|---:|
| ≤30 días | 72.3% | 49.1% |
| 31-60 días | 15.9% | 36.6% |
| 61-90 días | 5.8% | 6.5% |
| 90+ días | 6.0% | 7.8% |

**Hallazgo:** los créditos "cura sin pago" recaen en mora con **mucha más frecuencia**
que los que curan de verdad (80.8% vs. 63.8% — 1.27x) pero **no más rápido**: la mediana
de días hasta la recaída es similar o incluso algo mayor (31.0 vs. 28.1 días), y cuando sí
recaen, "cura real" concentra más recaídas en el primer mes (72.3% ≤30 días) mientras
"cura sin pago" se reparte más hacia 31-60 días (36.6% vs. 15.9%). Nota: la primera
corrida (antes del fix de dedup, bug 11 en `BUGS.md`) había sugerido lo contrario —que
"cura sin pago" recaía más rápido (mediana 20.3 días)— un artefacto de episodios
fragmentados que se corrigió al arreglar la duplicación de filas.

**Esto confirma la hipótesis central de este enfoque:** una "cura sin pago" no es una
salida real del problema — 8 de cada 10 vuelven a caer en mora (vs. 6 de cada 10 en curas
reales), consistente con la interpretación de reprogramación/facilidad de pago que no
resuelve la causa. Con esta base, **construir la curva completa (opción a de los
pendientes) sí parece justificado** — hay una señal de reincidencia clara y medible que
respalda invertir en el paso siguiente.

## Hallazgo importante para el modelo oficial

**El motor de rebaje/recupero actual ya está protegido de esto.** Rebaje se mide como
`saldo_ayer − saldo_hoy` (solo cuenta si es positivo) — una cura sin pago nunca genera un
rebaje, así que no contamina la meta de recupero oficial ni el backtest de junio.

**Lo que sí revela, y no se estaba viendo antes:** estos 363 créditos "desaparecen" de la
mora sin pagar. El mes siguiente ya no cuentan como stock (porque su `dayslate` volvió a
0), y si vuelven a caer en mora más adelante, aparecerían como "nuevos" (entrada fresca)
en vez de como una recaída del mismo problema — subestimando la verdadera cronicidad de
esa cartera. **Confirmado con datos en la sección de reincidencia arriba: 80.8% de estos
créditos efectivamente vuelven a caer en mora**, contra 63.8% de los que curaron pagando
de verdad.

## Pendientes

1. ~~Decidir el siguiente paso~~ — **resuelto 2026-07-13**, se investigó primero (b)
   reincidencia por ser más barato y porque su resultado informa si (a) vale la pena:
   - b. Investigar **reincidencia** — **hecho**, ver sección arriba. 80.8% de los
     créditos "cura sin pago" recaen en mora (vs. 63.8% de "cura real"), en un plazo
     similar (mediana ~31 días). La señal es clara y justifica construir (a).
   - a. Construir la curva completa de "capital que sale de mora" (real vs.
     reestructurado) + proyección + artifact, igual que se hizo con Enfoque alfa — **el
     resultado de (b) recomienda hacerlo, sigue pendiente para una próxima sesión.**
2. ~~Conseguir un diccionario de datos real para `motivo_apertura`~~ — **resuelto
   2026-07-12**, confirmado por el usuario (negocio): 1 y 4 = reprogramación; 2 y 3 =
   adelanto de cuotas o problemas con producto. Ver el desglose recalculado arriba.
3. Si se construye la curva completa, sumarla a `SEGUIMIENTO.md` y evaluar si el "capital
   reestructurado" debería restarse de la definición de stock del mes siguiente (ya que
   estos créditos siguen siendo, en la práctica, cartera problema).
4. **El artifact publicado** ([🔓 Salida de mora — hallazgos](https://claude.ai/code/artifact/f1b0c577-4044-40a3-bebd-e01f5141ed98),
   `salida_mora.html`) tiene los números de ANTES del fix de dedup (513/364, no 376/363) —
   no republicar sin actualizarlo primero. Ver `BUGS.md` bug 11.

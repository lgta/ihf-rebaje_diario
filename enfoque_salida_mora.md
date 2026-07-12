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
   solo 721 de ~198,000 créditos (0.4%) — no hay diccionario de datos confirmado para qué
   significa cada valor 1-4, pendiente preguntar a negocio/producto.

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

| Clasificación | Episodios | Créditos | Saldo de entrada | % con `motivo_apertura` |
|---|---:|---:|---:|---:|
| Cura real (baja >1%) | 70,314 | 34,223 | S/104,705,444 | 0.9% |
| Cura parcial (baja ≤1%) | 121 | 118 | S/667,674 | 6.8% |
| **Cura sin pago (no baja)** | **513** | **364** | **S/1,204,077** | **67.9%** |
| Sin salida observada | 7,300 | 7,300 | S/15,479,914 | 2.8% |

**El patrón confirma la hipótesis del usuario, con una señal muy fuerte:** un crédito que
sale de mora sin bajar su saldo tiene ~75 veces más probabilidad de tener
`motivo_apertura` registrado que uno que sale pagando de verdad (67.9% vs. 0.9%).

### Desglose por código de motivo_apertura (dentro de cura_real vs. cura_sin_pago)

| Clasificación | motivo=1 | motivo=2 | motivo=3 | motivo=4 |
|---|---:|---:|---:|---:|
| Cura real — créditos | 224 | 83 | 2 | 4 |
| Cura real — días en mora prom. | 12.0 | 5.8 | 89.3 | 55.8 |
| Cura sin pago — créditos | 229 | 12 | 2 | 5 |
| Cura sin pago — días en mora prom. | 34.5 | 19.5 | 22.0 | 155.0 |

**No hay un mapeo limpio "código X = reestructuración".** El código 1 es el más común en
ambos grupos, en cantidades similares — pero dentro del código 1, los casos "cura sin
pago" pasan casi 3x más tiempo en mora antes de salir (34.5 vs. 12.0 días) que los de
"cura real". Es decir: `motivo_apertura` por sí solo no separa limpiamente, pero
combinado con la clasificación de saldo (que sí es objetiva y no depende de un campo
disperso al 0.4%) da una señal consistente.

## Hallazgo importante para el modelo oficial

**El motor de rebaje/recupero actual ya está protegido de esto.** Rebaje se mide como
`saldo_ayer − saldo_hoy` (solo cuenta si es positivo) — una cura sin pago nunca genera un
rebaje, así que no contamina la meta de recupero oficial ni el backtest de junio.

**Lo que sí revela, y no se estaba viendo antes:** estos 364 créditos "desaparecen" de la
mora sin pagar. El mes siguiente ya no cuentan como stock (porque su `dayslate` volvió a
0), y si vuelven a caer en mora más adelante, aparecerían como "nuevos" (entrada fresca)
en vez de como una recaída del mismo problema — subestimando la verdadera cronicidad de
esa cartera.

## Pendientes

1. **Decidir el siguiente paso** (pregunta abierta al usuario, 2026-07-10):
   a. Construir la curva completa de "capital que sale de mora" (real vs. reestructurado)
      + proyección + artifact, igual que se hizo con Enfoque alfa.
   b. Investigar **reincidencia**: ¿cuántos de los 364 créditos "cura sin pago" vuelven a
      caer en mora después, y en cuánto tiempo, comparado contra los que curaron de
      verdad?
   c. Ambas.
2. Conseguir un diccionario de datos real para `motivo_apertura` (preguntar a
   negocio/producto) — hoy la interpretación de los códigos 1-4 es inferida, no
   confirmada.
3. Si se construye la curva completa, sumarla a `SEGUIMIENTO.md` y evaluar si el "capital
   reestructurado" debería restarse de la definición de stock del mes siguiente (ya que
   estos créditos siguen siendo, en la práctica, cartera problema).

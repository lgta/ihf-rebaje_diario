# Issue: `dts_mambu_loans_hist` es una foto nocturna con cortes irregulares

Documento portable — escrito para poder pegarse/usarse en OTRO proyecto/sesión (ej. un análisis
de rebaje diario) sin depender del contexto de `gestiones_cobranzas`. Encontrado y resuelto en ese
proyecto al reconstruir capital histórico desde Mambu; el mecanismo del bug es genérico a
cualquier análisis que use esta tabla con una regla de offset por día (D-1, D-3, etc.).

## Qué es la tabla

`dts_mambu_loans_hist` es una **foto diaria** del core Mambu (`dts_mambu_loans`), una fila por
crédito por día de proceso (`fechaproceso`, formato `YYYYMMDD` varchar). No es un log incremental
real — es una foto completa tomada en un momento del día.

## El problema

- La foto de `fechaproceso = D` normalmente se **cierra ~22:00-22:15** de ese mismo día D. La base
  que consume esta foto (reportes, reconstrucciones, pipelines) generalmente se genera la mañana
  siguiente y usa **la última foto disponible antes de generarse** — en el caso normal, eso es la
  foto de `fechaproceso = D`, que ya vio todo lo que pasó en D hasta las ~22:15.
- **El bug real**: algunos días, por algún motivo del job de carga, la foto **cierra mucho más
  temprano** (se han visto casos a las 12:15pm y 14:15pm en vez de ~22:15). Cualquier evento del
  crédito que ocurra DESPUÉS de esa hora de cierte real — típicamente un **pago** que baja el
  saldo/capital — queda **AFUERA** de la foto de ese día, aunque genuinamente ocurrió ese mismo día
  calendario.
- Consecuencia: para cualquier reconstrucción que use `Mambu(D)` como "el estado del crédito al
  cierre del día D" (ej. `capital(D+1) = Mambu(D)`, o cualquier regla de offset D-1/D-3), un día con
  cierre temprano hace que Mambu(D) se comporte como la foto de un momento **intermedio** del día D,
  no de su cierre real — rompiendo la asunción de que "ya vio todo lo que pasó ese día".

## Por qué es especialmente peligroso para un análisis de REBAJE diario

Un análisis de rebaje (paydown día a día) es una **resta entre 2 fotos consecutivas**
(`rebaje(D) = saldo(D-1) - saldo(D)`, o el equivalente que se use). Un día con corte temprano no
solo da un número "un poco viejo" — **desplaza el evento de rebaje al día equivocado**:

- El pago que cayó fuera de la foto de D-1 (cierre temprano) hace que `saldo(D-1)` capturado quede
  **inflado** (más alto de lo que realmente era al cierre real de D-1).
- Si el saldo de D (el día siguiente, con foto normal) SÍ refleja ese pago, el rebaje calculado
  para D sale **artificialmente alto** (absorbe 2 días de pago en 1), y el rebaje de D-1 sale
  **artificialmente bajo o cero** (el pago que realmente ocurrió en D-1 "desaparece" de ese día).
- Esto es fácil de no notar porque el TOTAL acumulado en varios días suele seguir siendo correcto
  — el error es de **atribución al día**, no de magnitud total. Un análisis que mire rebaje día a
  día (no solo el acumulado) SÍ lo va a notar como un pico/valle anómalo en un día puntual.

## Cómo detectarlo

Verificar la hora de cierre REAL de cada foto usando la columna `fechaactualizaciontabla` (NO
asumir un corte fijo de "10pm" solo por convención):

```sql
SELECT
    fechaproceso,
    MAX(fechaactualizaciontabla) AS cierre_real,
    date_format(MAX(fechaactualizaciontabla), '%H:%i') AS hora_cierre
FROM dts_mambu_loans_hist
WHERE fechaproceso BETWEEN '<inicio_rango>' AND '<fin_rango>'
GROUP BY fechaproceso
ORDER BY fechaproceso
```

Comparar `hora_cierre` contra el patrón normal del resto de días del rango (en el caso ya
encontrado, ~22:15 era el patrón; días con `hora_cierre` varias horas antes son los sospechosos).
Nunca asumir que el rango que a uno le toca analizar está libre de este problema solo porque no se
ha visto — cada proyecto/rango de fechas debe correr su propio chequeo.

## Cómo corregir un día con corte temprano detectado

1. **Identificar el rango de tiempo perdido**: desde la hora de cierre real (ej. 12:15pm) hasta la
   medianoche de ese mismo día calendario D — cualquier pago en esa ventana quedó afuera de la
   foto de D.
2. **Identificar los créditos afectados**: buscar pagos (créditos con evento de pago) que ocurrieron
   DENTRO de esa ventana de tiempo perdida, para ese día D. Fuentes típicas para esto (usar la que
   ya tenga el proyecto destino):
   - A nivel cuota: `installmentlastpaiddate` en la tabla de cuotas (ej.
     `dts_cobranza_creditos_cuotas`) — da la fecha/hora exacta del último pago de esa cuota.
   - A nivel transacción (más preciso si hay varios pagos el mismo día): `dts_mambu_loanstransactions`
     (`creationdate`, `type = 'REPAYMENT'`, `affectedamounts_principalamount` para el componente de
     capital del pago).
3. **Calcular el valor correcto**: `valor_correcto(D) = Mambu(D, foto parcial) − monto_pagado_en_la_ventana_perdida`.
   Es decir, HAY que restar manualmente el pago que la foto no llegó a capturar, para llegar al
   saldo real de cierre de ese día.
4. **Verificar contra un valor independiente si existe uno** (ej. lo que ya mostraba producción,
   u otra fuente que no dependa de esta foto) — en el caso ya resuelto, el valor corregido coincidió
   exacto con lo que producción ya mostraba antes de tocar nada, confirmando la dirección de la
   corrección.
5. **Acotar el impacto**: el problema queda matemáticamente limitado a: (a) el/los día(s) con
   cierre temprano, y (b) dentro de esos días, solo los créditos con un evento (pago) en la ventana
   perdida. En el caso ya resuelto, de ~8,000+ créditos en la partición afectada, terminaron siendo
   exactamente **5 créditos** — no hace falta descartar el día completo, solo corregir los casos
   puntuales identificados.

## Ejemplo real (para calibrar expectativas de magnitud, no para asumir que aplica a otro rango)

En el proyecto donde se encontró esto, sobre un rango de ~13 meses, se detectaron 3 días con cierre
temprano: uno a las 12:15pm y dos a las 14:15pm (vs. ~22:15 habitual). El impacto cuantificado del
primero fue exactamente 5 créditos con un valor de saldo inflado en la foto siguiente. Esto NO
implica que cualquier otro rango de fechas tenga la misma cantidad de días anómalos ni el mismo
número de créditos afectados — cada rango necesita su propio chequeo de `fechaactualizaciontabla`.

## Checklist para aplicar esto en un análisis nuevo

- [ ] Correr el chequeo de `fechaactualizaciontabla` por `fechaproceso` sobre el rango de fechas
      propio del análisis.
- [ ] Si hay días anómalos: identificar la ventana de tiempo perdida de cada uno.
- [ ] Cruzar esa ventana contra pagos reales (cuotas o transacciones) para acotar los créditos
      afectados — no asumir que afecta a toda la partición del día.
- [ ] Si el análisis es de REBAJE/paydown día a día (no solo saldo puntual): revisar
      específicamente el rebaje calculado para el día ANTERIOR al día con foto parcial y el día
      SIGUIENTE — ahí es donde el evento se "desplaza" (rebaje faltante en uno, inflado en el otro).
      Corregir el saldo del día con foto parcial (paso "Cómo corregir" arriba) resuelve ambos
      números automáticamente, sin tocar nada más.
- [ ] Documentar los días anómalos encontrados y el alcance real (cuántos créditos), para no tener
      que re-descubrir esto en la siguiente corrida del mismo análisis.

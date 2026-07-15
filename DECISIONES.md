# Decisiones metodológicas

Por qué se eligió cada pieza del modelo. Si alguien pregunta "¿por qué hacemos X y no Y?",
la respuesta debería estar acá.

### Modelo evento × magnitud, no rebaje diario promedio
El pago es "grumoso": 92% de los crédito-mes en mora tiene 0 o 1 evento de pago al mes
(24% no rebaja nada, 68% rebaja en exactamente 1 día). Promediar el rebaje del mes entre 30
días no sobrevive a este chequeo. Se modela en cambio `P(paga) × E(% del saldo que rebaja
al pagar)`. Confirmado con datos en `fase0_diagnostico.sql` bloque 0.2.

### Tramo fijo aunque el crédito cruce 30 días de mora
Un crédito asignado con, digamos, 28 días de mora al inicio del mes sigue sumando a la meta
(y conserva su tramo original) aunque cruce 30 días a mitad de mes. Confirmado por el
usuario y validado empíricamente: el bug de "aged-out survivors" (bug 7 en `BUGS.md`)
apareció precisamente por NO respetar esta regla en un enfoque alternativo, y corregirlo
acercó el resultado al esperado.

### Avance de amortización como segmentador de severidad, no `term`
Ambos predicen severidad de forma parecida (son proxies el uno del otro: avance ≈ 1/term),
pero avance es más directo — mide cuánto le queda al crédito, no cuántas cuotas tenía al
inicio. Se usa avance como segmentador operativo único; los números de `term` de la corrida
original de Fase 2 quedaron con el bug de window-function (bug 4) y nunca se recalcularon —
no confiar en ellos.

### Tramo predice frecuencia, avance predice severidad — son ejes distintos
Hallazgo empírico de Fase 1: la severidad es casi PLANA entre tramos (~24% cuando el
crédito paga algo); lo que cae con la mora es la frecuencia (83%/58%/39% pagan algo en el
mes, tramos 1-8/9-15/16-30). El tramo no debe usarse como proxy de severidad.

### Dos filtros de `status` distintos según se mire pasado o futuro
- **Histórico/calibración** (curvas, tasas): `status IN ('ACTIVE','COMPLETED')` — se
  quiere el comportamiento completo, incluidos los que ya terminaron de pagar bien.
- **Calendario prospectivo** (qué va a vencer): `status = 'ACTIVE'` solamente — un crédito
  `COMPLETED` ya no tiene obligaciones futuras.
- **Backtest de un mes cerrado:** `status IN ('ACTIVE','COMPLETED')`, SIN filtrar por
  `installmentstate` — ya se conoce el desenlace real vía `dts_mambu_loans_hist`, filtrar
  por `PENDING` perdería casi todas las cuotas (ya resueltas).

### P(no paga a tiempo) = 13.38%, no 25-28%, no 27.4%
Es la tasa medida a nivel CRÉDITO (`dayslate` 0→1), fuera de muestra, y la que efectivamente
pasó el backtest (+5.4% de error). El complemento simple de "% paga a tiempo" a nivel CUOTA
(~25-28%) mide una población distinta (incluye pagos 1-día-tarde que `dayslate` nunca
llega a ver — bug 9) y sobreestima +66% a +81% si se usa con la curva actual. Ver
`feedback-tasa-curva-consistente` en memoria: **la tasa y la curva de recupero deben
calibrarse sobre la misma definición de "entrada"** — no se puede mezclar. Detalle completo
en `BUGS.md` (bugs 6, 9, 10) y el artifact
[⚠️ Por qué NO 25%](https://claude.ai/code/artifact/fa602fcb-a2f9-489f-a7bf-697a92fdbcf8).

### Mantener dos enfoques en paralelo (agregado vs. segmentado)
A pedido explícito del usuario, para poder comparar. El segmentado (tramo×avance /
avance) es más fiel a la mezcla real de la cartera; el agregado es más simple de mantener.
La diferencia entre ambos es en sí misma una señal útil (si crece con el tiempo, indica que
la mezcla de la cartera se está moviendo respecto al histórico).

### Enfoque "acumulado" (anclado al cierre del mes anterior) es el oficial
No el "reinicio del reloj" (recalcular todo desde hoy). El acumulado nunca re-filtra por
mora del día corriente — clasifica una sola vez al momento de asignación, lo cual evita
estructuralmente el bug de aged-out survivors. El "reinicio del reloj" es útil como
sanity-check ocasional pero requiere un parche manual cada vez que se usa (ver bug 7). El
usuario confirmó el 2026-07-10 que la pregunta que le interesa siempre es la del mes
completo — no seguir invirtiendo en el enfoque alternativo salvo pedido explícito.

### Verificar contra el backtest, no razonar en abstracto, ante cualquier cambio de constante
Cuando se propone cambiar una tasa o constante del modelo, la forma de resolverlo no es
debatir en teoría qué número es "más correcto" — es correr el backtest ya existente con el
cambio propuesto y ver el error real. Esto resolvió en minutos la discusión sobre 13.38% vs
25% donde el razonamiento abstracto se hubiera estancado. Ver
`feedback-tasa-curva-consistente` en memoria para el detalle.

### Enfoque "reinicio del reloj" y Enfoque beta "salida de mora" descontinuados (2026-07-15)
A pedido explícito del usuario, el proyecto acota su alcance a **2 enfoques**: el
acumulado/oficial (rebaje, capital reducido) y el alfa (capital asegurado, meta principal
desde 2026-07-13). Ambos venían ya señalados como no prioritarios (el primero
"deprioritizado" desde el 2026-07-10, ver más arriba; el segundo "exploratorio") pero
nunca se había formalizado su descarte. Se eliminaron del repo sus archivos
(`enfoque_reinicio_reloj.md`, `meta_desde_hoy.py/.sql`, `datos_meta_desde_hoy/`,
`enfoque_salida_mora.md/.sql`, `salida_mora.html`, `datos_salida_mora/`) junto con
`guia_4_enfoques.html`/`ejemplos_4_enfoques.sql` (quedaba obsoleta: explicaba 2 enfoques
que ya no existen). Quedan recuperables vía `git log`/`git show` de cualquier commit
anterior a esta limpieza — no se pierde el trabajo, solo deja de mantenerse. Los
artifacts ya publicados de ambos no se retiran de claude.ai, solo se sacan de las tablas
de "vigente" en `README.md`/`ESTADO.md`. El plan de continuación para los 2 enfoques que
quedan está en `PENDIENTES.md`.

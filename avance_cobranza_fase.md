# Avance de julio por fase de cobranza (Temprana/Especializada/Recovery)

> **Estado: análisis puntual (snapshot), no un enfoque con curva propia.** Reutiliza las
> curvas ya calibradas del Enfoque alfa (`enfoque_capital_asegurado.md`). Ejecutado
> originalmente 2026-07-13, **re-ejecutado 2026-08-21** con 3 fixes (bugs 11/12/15, ver
> nota abajo). Corte al 12-jul en ambos casos (misma ventana, para aislar el efecto de los
> fixes).

## El concepto

> **Nota 2026-08-18:** esta corrida (12-jul) usó `dts_asignaciones_cobranza`, que quedó
> congelada el 2026-07-10 poco después — ver bug 13 en `BUGS.md`. El SQL ya se repuntó a
> `dts_asignaciones_gestiones_cobranza` (tabla viva, mismo grano).
>
> **Actualización 2026-08-21 (continuación) — re-corrida completa con 3 fixes, tarea 1 de
> `PENDIENTES.md` CERRADA:**
> 1. **Bug 15** (`BUGS.md`): la tabla SÍ tiene `id_ihfintech_loan` directo, columna `aux02`
>    (99.97% de match, sin nombre descriptivo — hallazgo del usuario, ver reconciliación
>    TEMPRANA) — reemplaza el crosswalk `dni`+`producto` que se usaba antes (quirk 2 de
>    abajo, ahora obsoleto). La cohorte crece de 8,303 a **8,614 créditos** (+3.7%),
>    concentrado en TEMPRANA (+249 — mismo mecanismo que "Sin asignar" de la reconciliación
>    TEMPRANA: el crosswalk viejo perdía créditos ya `COMPLETED`).
> 2. **Bug 12** (antiguo/nuevo, día 1 del mes): nunca se había aplicado a este archivo. Un
>    crédito con `mora=1` el día 1 de julio viene de una cuota vencida el último día de
>    junio — es "antiguo"/stock, no "nuevo". Impacto grande aquí (mucho más que en la
>    calibración de 14 meses) porque esta cohorte es una ventana de solo 11 días — el 1-jul
>    solo por sí solo pesaba **60-70% de todo el bucket "nuevo"** de la corrida vieja.
>    "nuevo" baja de 1,258 a 571 créditos, "stock" sube correspondientemente.
> 3. **Bug 11** (dedup de filas duplicadas): agregado — este archivo nunca lo había tenido.
>
> Los números de este documento (tabla de resultados y lectura) son los de la re-corrida
> 2026-08-21. La corrida original (12-jul-2026, previa a los 3 fixes) queda solo en el
> historial de `plan_analisis.md` si se necesita comparar.

El proyecto viene trabajando con una población de mora **inferida** (mora 1-30 vía
`dayslate`, ver `FUENTES_DATOS.md`). El usuario proporcionó una tabla nueva,
`dts_asignaciones_cobranza` (hoy reemplazada por `dts_asignaciones_gestiones_cobranza`, ver
nota arriba), que trae la asignación **real** de cobranza día a día — quién
trabaja el negocio, y bajo qué fase de estrategia (`fase_estrategia`: TEMPRANA,
ESPECIALIZADA, RECOVERY). Este análisis cruza esa asignación real contra
`dts_mambu_loans_hist` para medir avance, usando la métrica de **capital asegurado**
(Enfoque alfa: saldo COMPLETO del crédito si mostró ≥1 día de pago, no soles cobrados) —
confirmado con el usuario porque el formato de referencia que pidió reportar tenía
porcentajes (96.9%/85.6%) del orden de magnitud de capital asegurado, no del recupero
oficial (~12-20%/mes).

## `dts_asignaciones_gestiones_cobranza`: quirks encontrados

1. **Sin datos del 1-jul (histórico, ya no aplica).** La corrida original (12-jul-2026) usó
   `dts_asignaciones_cobranza`, que solo tenía `fecha_base` desde 2026-07-02. **Se usa
   2-jul como "día 1" de julio** para esta cohorte, y se mantiene así en la re-corrida
   2026-08-21 para no alterar la ventana de comparación (ver nota arriba) — pero la tabla
   viva (`dts_asignaciones_gestiones_cobranza`) sí tiene 1-jul, así que un futuro re-corte
   desde cero podría anclar ahí directamente.
2. **~~No trae `id_ihfintech_loan` directo~~ — CORREGIDO 2026-08-21, ver bug 15
   (`BUGS.md`).** La tabla SÍ tiene el ID de crédito directo en la columna `aux02` (sin
   nombre descriptivo, por eso no se había visto antes) — 99.97% de match verificado
   contra `dts_okaapi_loans`, mejor que el crosswalk `dni`+`producto` que se usaba antes
   (que además tenía el problema de excluir créditos ya `COMPLETED` vía el filtro
   `status='ACTIVE'`). La query ahora usa `aux02` directo, sin crosswalk.
3. **`fase_estrategia` se fija al momento de asignar la campaña, no se recalcula a
   diario.** Un crédito puede seguir etiquetado "Temprana" aunque para el corte de esta
   query ya haya cruzado 30 días de mora (medido vía `dayslate`) — no es un error de
   datos, es el comportamiento esperado del sistema de asignación del negocio.
4. **La asignación a Especializada/Recovery es a nivel CLIENTE (DNI), no crédito.** Si un
   cliente tiene otro crédito en mora profunda, TODOS sus créditos (incluso uno sano o
   recién entrado) se asignan a la fase más severa por arrastre — por eso aparecen
   créditos con mora 0 o 1-30 dentro de Especializada/Recovery.

## Metodología

1. **Cohorte día 1:** créditos asignados el 2026-07-02, con `id_ihfintech_loan` directo vía
   `aux02` (ver quirk 2).
2. **Segmento nuevo/stock:** se deriva del `dayslate` a cierre de junio (no de la fase del
   negocio) — `nuevo` = no estaba en mora el 30-jun; `stock` = sí estaba (cualquier
   profundidad). Es el mismo criterio "tramo fijo al momento de asignación" que usa el
   resto del proyecto (`DECISIONES.md`). **Corrección 2026-08-21 (bug 12):** un crédito
   con `mora=1` exactamente el DÍA 1 de julio (mora=0 el 30-jun) viene matemáticamente de
   una cuota vencida el ÚLTIMO DÍA de junio — es "antiguo"/stock, no "nuevo". Estos
   créditos se reclasifican a `stock` con tramo fijo `'a. 1-8'` (mismo patrón que
   `enfoque_capital_asegurado.sql`).
3. **Sub-tramo (1-8/9-15/16-30):** solo se aplica a Temprana-stock, usando el tramo a
   cierre de junio (`tramo_jun`) — es el único caso con cobertura de curva real. "Nuevo"
   siempre entra con 1-2 días de mora (trivial, no aporta separarlo) y
   Especializada/Recovery casi no tienen saldo dentro de 1-30 (ver cobertura abajo).
4. **Meta (%):** para créditos con tramo/avance dentro de lo calibrado, se usa la curva de
   capital asegurado del Enfoque alfa (`curva_asegurado_stock_seg.csv` para stock,
   `curva_asegurado_nuevos_seg.csv` para nuevos, indexada por días desde entrada),
   evaluada en el **día 11** (2-jul a 12-jul). **Especializada y Recovery no tienen curva
   calibrada** — el Enfoque alfa nunca se construyó más allá de mora 1-30. Se reporta
   "N/D" cuando la cobertura de saldo con curva es 0%.
5. **Real (%):** capital asegurado real observado — suma del saldo día 1 de los créditos
   con al menos 1 día de pago entre el 2-jul y el 12-jul (última fecha con datos en
   `dts_mambu_loans_hist` a la fecha de esta corrida).

Query: `avance_cobranza_fase.sql` (extracción, una fila por crédito). Agregación y cruce
con curvas: `avance_cobranza_fase.py`. Datos cacheados: `datos_avance_fase/`.

## Resultados (corte 2-jul a 12-jul-2026, día 11 — re-corrida 2026-08-21 con bugs 11/12/15)

| COBRANZA | Segmento | Cuentas | Asignación (S/) | Cobertura curva | Meta Cap. Aseg. (%) | Meta Cap. Aseg. (S/) | Real Cap. Aseg. (S/) | Real Cap. Aseg. (%) | Real-Meta (pp) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| TEMPRANA | nuevo | 571 | 827,094 | 61.8% | 72.8% | 372,358 | 657,401 | 79.5% | +6.6 |
| TEMPRANA | stock (31+, arrastre) | 19 | 30,159 | 0.0% | N/D | N/D | 1,560 | 5.2% | N/D |
| TEMPRANA | stock (1-8) | 1,445 | 2,359,992 | 100.0% | 62.5% | 1,475,866 | 1,391,566 | 59.0% | -3.6 |
| TEMPRANA | stock (9-15) | 337 | 577,561 | 100.0% | 33.2% | 191,554 | 169,506 | 29.3% | -3.8 |
| TEMPRANA | stock (16-30) | 361 | 656,095 | 100.0% | 20.4% | 133,569 | 154,633 | 23.6% | +3.2 |
| ESPECIALIZADA | nuevo | 2 | ~0 | 0.0% | N/D | N/D | 0 | 0.0% | N/D |
| ESPECIALIZADA | stock | 1,948 | 3,929,626 | 4.2% | 24.2%* | 39,513* | 302,786 | 7.7% | N/D* |
| RECOVERY | nuevo | 1 | ~0 | 0.0% | N/D | N/D | 0 | 0.0% | N/D |
| RECOVERY | stock | 3,635 | 8,347,759 | 0.0% | 54.6%* | 1,610* | 51,367 | 0.6% | N/D* |
| (sin fase) | nuevo | 54 | 65,050 | 56.8% | 73.2% | 27,054 | 46,896 | 72.1% | -1.1 |
| (sin fase) | stock | 241 | 434,750 | 99.7% | 53.6% | 232,481 | 245,182 | 56.4% | +2.8 |

**Notas:**
- **Cambios grandes vs. la corrida original (12-jul, sin los 3 fixes):** TEMPRANA-nuevo
  baja de 1,258 a 571 cuentas (la mayoría eran entrantes del día 1 mal clasificados, bug
  12) mientras TEMPRANA-stock (1-8) sube de 540 a 1,445. La cohorte total crece de 8,303 a
  8,614 créditos (bug 15), concentrado en TEMPRANA. Ningún otro tramo/segmento se movió por
  una razón distinta a estos 2 fixes.
- **(\*) Meta con cobertura marginal (<5%) — no representativa del segmento completo.**
  ESPECIALIZADA-stock y RECOVERY-stock tienen prácticamente nada de saldo dentro de la
  curva calibrada (4.2% y ~0.04% respectivamente) — el % de Meta que muestra la tabla es
  el promedio SOLO de ese sliver marginal, no del segmento entero (la mayoría de esos
  créditos, mora 31+, no tiene curva calibrada — ver más abajo). Tratar como si fuera N/D
  para efectos prácticos; se deja el número real (no forzado a N/D) por transparencia.
- "ESPECIALIZADA-nuevo"/"RECOVERY-nuevo" (2+1 cuentas) son casos límite de timing de
  asignación con saldo ~0 en el día de corte, sin peso material. "(sin fase)" son 295
  créditos (S/500K aprox.) sin `fase_estrategia` poblada en la tabla de asignaciones —
  residual, no investigado (mismo hallazgo que antes, ahora con más créditos por el fix de
  `aux02`).

## Lectura de resultados

- **Temprana** sigue siendo la única fase con curva calibrada casi completa (56.8%-100% de
  cobertura). Con los 3 fixes aplicados, el panorama de avance **cambia de signo**: antes
  se veía uniformemente atrasada (nuevos -4.3pp, stock 1-8 -13.0pp); ahora **nuevos va
  +6.6pp adelantado**, stock 1-8 -3.6pp (más leve que antes), stock 9-15 -3.8pp, stock
  16-30 +3.2pp (adelantado, igual que antes). La lectura cambia porque la población de
  "nuevo" y "stock (1-8)" se redefinió por completo (bug 12) — no es que el ritmo de pago
  real haya cambiado, es que ahora se compara cada crédito contra la curva correcta para su
  categoría real. Con solo 11 días de dato sigue sin alcanzar para saber si estos pp son
  ruido normal o una señal real — no ajustar nada sin más meses de evidencia (mismo
  principio que el backtest oficial, `DECISIONES.md`).
- **Especializada y Recovery siguen sin meta confiable con la que comparar** — el modelo
  nunca se calibró para mora 31+, y con los fixes aplicados esto no cambió (siguen con
  0-4% de cobertura de curva). Lo único reportable es lo observado: 7.7% y 0.6% de capital
  asegurado respectivamente a día 11 (antes 7.5%/0.4% — prácticamente sin cambio, como se
  esperaba ya que estas fases casi no tienen saldo dentro de mora 1-30 y por lo tanto casi
  no las tocan los fixes de bug 12/15) — consistente con que la mora profunda paga con
  mucha menor frecuencia.

## Pendientes / posibles próximos pasos

1. Si este cruce resulta útil de forma recurrente, considerar automatizarlo como parte del
   seguimiento regular (hoy es una corrida puntual, no un job).
2. Si se quiere una "Meta" real para Especializada/Recovery, habría que calibrar curvas de
   capital asegurado (o de recupero) para mora 31+ — no existe ese trabajo hoy, sería un
   enfoque nuevo del proyecto.
3. Investigar el residual "(sin fase)" (295 créditos, ~S/500K) — por qué no tienen
   `fase_estrategia` poblada. Sigue sin investigar (el fix de `aux02` agregó más créditos a
   este residual, no lo explicó).
4. **~~La tabla solo tiene 9 días de historia~~ ya no aplica** — `dts_asignaciones_
   gestiones_cobranza` es una tabla viva con historia continua desde 2026-07-01. Si se
   quiere re-correr este análisis desde cero (no solo re-ejecutar la misma ventana 2/12-jul
   con fixes), ahora sí se puede anclar directo a 1-jul en vez de 2-jul, y/o extender a un
   mes completo o a un mes más reciente (agosto) en vez de la ventana parcial de julio.
5. **Tarea 1 de `PENDIENTES.md` — CERRADA 2026-08-21.** Los 3 fixes pendientes (bugs
   11/12/15) quedaron aplicados en esta re-corrida.

"""
Meta de capital asegurado de agosto 2026 (enfoque alfa), anclada al cierre
REAL de julio. Mismo mecanismo que meta_julio_capital_asegurado.py: stock
(cierre julio UNION entrantes del dia 1 de agosto, bug 12) x curva_asegurado_
stock + calendario x P(no paga)=13.38% x curva_asegurado_nuevos. Curvas y
tasa SIN cambios.

v2 (2026-08-20, bug 14): capa "fantasma" agregada -- ver enfoque_capital_
asegurado.sql Q3 y reconciliacion_vw_seguimiento_temprana.md paso 2/3.
Independiente de 13.38%/curva de nuevos, se activa 100% el dia siguiente al
vencimiento. Corte mantenido al 18-ago (mismo dia ya reportado en ESTADO.md
antes de este cambio) para que la comparacion sea antes/despues, no una
actualizacion de fecha -- un refresco a la fecha de hoy es una tarea aparte.

v3 (2026-08-20, continuacion, bug 14): fix de frontera de mes -- la
verificacion a nivel credito encontro que la capa fantasma no cubria el caso
de una cuota vencida el ULTIMO DIA de un mes (aqui: 31-jul), pagada 1 dia
tarde el 1-ago -- fuera de ago_calendario.csv (que arranca en 2026-08-01).
Impacto confirmado con Athena (no supuesto): 77 creditos / S/140,194 en
riesgo (chico, ver CUOTAS_31JUL_FANTASMA abajo). Ademas, como tasa y
calendario deben compartir la misma definicion (principio de CLAUDE.md), se
recalibro P_FANTASMA junto con el fix: 8.4534% -> 8.5524% (ver
enfoque_capital_asegurado.sql Q3, backtest re-corrido: junio +2.2%->+2.65%,
julio +0.12%->+2.17%, ver BUGS.md bug 14).

Insumos:
  datos_avance_capital_asegurado_agosto/stock_agosto_aseg_seg.csv : stock (K1, 2026-08-18)
  datos_meta_agosto/ago_calendario.csv : calendario (K3, reutilizado -- igual que en julio,
                                          el calendario no tiene el bug 12, ver BUGS.md)
  datos_capital_asegurado/curva_asegurado_stock_seg.csv / curva_asegurado_nuevos_seg.csv

Real a la fecha (1-18 ago), query K4 (2026-08-18): ASEG_STOCK saldo_asegurado_real=2,605,896.73
(1,678/2,696 creditos activados), ASEG_NUEVOS saldo_asegurado_real=4,189,176.85
(2,773/4,141 creditos activados). Real fantasma (1-18 ago, investigacion_capa_
fantasma.sql patron): S/2,827,691.80 (1,997 creditos) + S/3,556.95 (4 creditos)
de la cohorte 31-jul (bug14 v3) = S/2,831,248.75.

v4 (2026-08-21, a pedido del usuario): refresco del corte a 20-ago -- NO se
espera a que cierre agosto, se sigue el avance con la data disponible hasta
ayer (hoy=21-ago). Las 3 queries K1/K2/K3 (mismo patron que cierre_julio.sql
J1/J2 e investigacion_capa_fantasma.sql Q3, ancladas a julio->agosto, corte
20-ago) se corrieron frescas contra Athena -- ya no hardcodeadas de memoria,
quedan documentadas en el scratchpad de esa sesion si hace falta reconstruir.
K3 (fantasma) ya incluye la cohorte 31-jul unificada en el mismo filtro de
fecha_pago (1-ago a 20-ago), no hace falta sumarla aparte como en v2/v3.

Real a la fecha (1-20 ago):
  ASEG_STOCK   saldo_asegurado_real=2,690,562.16 (1,741/2,695 creditos activados)
  ASEG_NUEVOS  saldo_asegurado_real=5,173,860.76 (3,369/4,744 creditos activados)
  FANTASMA     saldo_asegurado_real=3,134,320.83 (2,255 creditos, cohorte 31-jul incluida)

v5 (2026-08-22, a pedido del usuario -- item 2/3 del pedido de sesion):
refresco del corte a 21-ago. Corte elegido 21-ago (no 22-ago/hoy) porque
dts_asignaciones_gestiones_cobranza (usada en el analisis de volumen vs
efectividad de la misma sesion) solo tiene datos hasta 21-ago -- un solo
corte para todo el analisis. Queries K1/K2/K3 ahora SI quedan en el repo,
segmentadas por tramo/avance ademas del agregado -- ver
analisis_volumen_efectividad_agosto.sql/.md y
datos_volumen_efectividad_agosto/. Desagregado por segmento (item 3) y
descomposicion volumen-vs-efectividad (item 4) documentados ahi, no en
este archivo (este archivo solo trackea el agregado del avance en vivo).

Real a la fecha (1-21 ago):
  ASEG_STOCK   saldo_asegurado_real=2,734,665.08 (1,772/2,695 creditos activados)
  ASEG_NUEVOS  saldo_asegurado_real=5,537,430.70 (3,618/5,196 creditos activados)
  FANTASMA     saldo_asegurado_real=3,348,684.20 (2,403 creditos, cohorte 31-jul incluida)

v6 (2026-08-25, tarea 17 fase 3): P_FANTASMA recalibrado con dias_atraso_cuota
(dts_cobranza_creditos_calendario_diario) en vez de dias_vencimiento_a_pago=1
-- 8.5524% -> 8.6163% (ventana 12m, abr25-mar26, fuera de muestra de los 4
meses de backtest). Fase 3 confirmo que la activacion instantanea (100% el
dia siguiente al vencimiento, sin curva) sigue siendo correcta con la
definicion ampliada -- no cambia la LOGICA de esta funcion, solo la
constante. "Real a la fecha" sigue en el corte 21-ago (no se refresco la
fecha de hoy en este cambio, es una actualizacion de constante, no de
tracking). Ver BUGS.md bug 16 para el detalle completo.
"""
import csv
from datetime import date, timedelta

DIR_AGO = "datos_meta_agosto"
DIR_ASEG_AGO = "datos_avance_capital_asegurado_agosto"
DIR_ASEG = "datos_capital_asegurado"

stock_agosto = {}
with open(f"{DIR_ASEG_AGO}/stock_agosto_aseg_seg.csv") as f:
    for row in csv.DictReader(f):
        stock_agosto[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_aseg_stock = {}
with open(f"{DIR_ASEG}/curva_asegurado_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_aseg_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

curva_aseg_nuevos = {}
with open(f"{DIR_ASEG}/curva_asegurado_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_aseg_nuevos.setdefault(row["avance_band"], {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

calendario_agosto = {}
with open(f"{DIR_AGO}/ago_calendario.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_en_riesgo"]
        calendario_agosto.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

def lookup(curva, d):
    if d <= 0 or not curva:
        return 0.0
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

P_NO_PAGA_DIA0 = 47966 / 358580  # 13.38%
P_FANTASMA = 30037 / 348605      # 8.6163% -- recalibrado con dias_atraso_cuota (tarea 17
                                  # fase 3, 2026-08-25, ventana 12m abr25-mar26). Antes 8.5524%
                                  # (29625/346396, dias_vencimiento_a_pago=1). Ver BUGS.md bug 16.
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

# bug14 v3 (2026-08-20): cuota vencida 31-jul-2026, fecha_pago=1-ago -- fuera
# de ago_calendario.csv (arranca 2026-08-01). 77 creditos / S/140,194 en
# riesgo, confirmado con Athena. Solo aplica a fantasma (NO a nuevos/13.38%
# -- los que entran en mora REAL el dia 1 de agosto ya estan cubiertos por
# el stock de agosto via el mismo mecanismo de bug 12, no por el calendario
# de "nuevos").
CUOTAS_31JUL_FANTASMA = {
    "a. avance <10%": 52928.0,
    "b. avance 10-40%": 56252.0,
    "c. avance 40-70%": 23453.0,
    "d. avance 70%+": 7561.0,
}
SALDO_31JUL_FANTASMA = sum(CUOTAS_31JUL_FANTASMA.values())  # 140,194

INICIO = date(2026, 8, 1)
HOY = date(2026, 8, 21)
N_DIAS = 31
saldo_stock_inicial = sum(stock_agosto.values())

REAL_STOCK_A_HOY = 2734665.08
REAL_NUEVOS_A_HOY = 5537430.70
REAL_FANTASMA_A_HOY = 3348684.20  # ya incluye la cohorte 31-jul (bug14 v3), ver docstring

filas = []
for d in range(1, N_DIAS + 1):
    fecha = INICIO + timedelta(days=d - 1)

    aseg_stock = sum(
        stock_agosto.get((t, a), 0.0) * lookup(curva_aseg_stock.get((t, a), {}), d) / 100.0
        for t in TRAMOS for a in AVANCES
    )
    aseg_nuevos = 0.0
    # bug14 v3: cohorte 31-jul, activa 100% desde el dia 1 de agosto (fecha_pago=1-ago).
    aseg_fantasma = SALDO_31JUL_FANTASMA * P_FANTASMA
    for dd in range(1, d + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        riesgo_por_avance = calendario_agosto.get(fecha_venc, {})
        if d - dd < 1:
            continue
        # fantasma: 100% activado el dia siguiente al vencimiento, sin curva.
        # NO afectado por bug18 -- no usa curva, su indice (d - dd >= 1) es correcto.
        aseg_fantasma += sum(riesgo_por_avance.values()) * P_FANTASMA
        # bug18: la curva de nuevos se calibra desde la ENTRADA en mora
        # (= vencimiento + 1), no desde el vencimiento. Indice = d - dd - 1.
        dias_desde_entrada = d - dd - 1
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in riesgo_por_avance.items():
            pct = lookup(curva_aseg_nuevos.get(avance, {}), dias_desde_entrada)
            aseg_nuevos += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0

    filas.append({
        "dia": d, "fecha": fecha.isoformat(),
        "aseg_stock": aseg_stock, "aseg_nuevos": aseg_nuevos, "aseg_fantasma": aseg_fantasma,
        "aseg_total": aseg_stock + aseg_nuevos + aseg_fantasma,
    })

if __name__ == "__main__":
    print(f"Stock al 1 de agosto (cierre real de julio): S/ {saldo_stock_inicial:,.0f}\n")
    print(f"{'dia':>3} {'fecha':>11} | {'aseg_total':>11}")
    for r in filas:
        marca = " <- hoy" if r["fecha"] == HOY.isoformat() else ""
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['aseg_total']:>11,.0f}{marca}")

    hoy_row = next(r for r in filas if r["fecha"] == HOY.isoformat())
    fin_row = filas[-1]
    real_total_hoy = REAL_STOCK_A_HOY + REAL_NUEVOS_A_HOY + REAL_FANTASMA_A_HOY
    print(f"\n=== RESUMEN AL {HOY.isoformat()} -- ENFOQUE ALFA: CAPITAL ASEGURADO, AGOSTO 2026 (con capa fantasma) ===")
    print(f"Meta total de agosto (proyectada al cierre):     S/ {fin_row['aseg_total']:,.0f}")
    print(f"  stock: S/ {fin_row['aseg_stock']:,.0f}  |  nuevos: S/ {fin_row['aseg_nuevos']:,.0f}  |  fantasma: S/ {fin_row['aseg_fantasma']:,.0f}")
    print(f"Ya asegurado real (1-{HOY.day} ago):                     S/ {real_total_hoy:,.0f}")
    print(f"  stock: S/ {REAL_STOCK_A_HOY:,.0f}  |  nuevos: S/ {REAL_NUEVOS_A_HOY:,.0f}  |  fantasma: S/ {REAL_FANTASMA_A_HOY:,.0f}")
    print(f"Meta proyectada acumulada al mismo día (día {HOY.day}):  S/ {hoy_row['aseg_total']:,.0f}")
    avance_pct = 100 * real_total_hoy / fin_row['aseg_total']
    print(f"Avance real vs meta total del mes: {avance_pct:.1f}%")
    err_hoy = real_total_hoy - hoy_row['aseg_total']
    print(f"Real vs. proyectado AL MISMO DIA ({HOY.day}): {100*err_hoy/hoy_row['aseg_total']:+.1f}%")
    print(f"\n>>> LO QUE RESTA DEL MES (día {HOY.day+1} al 31): S/ {fin_row['aseg_total'] - real_total_hoy:,.0f} <<<")

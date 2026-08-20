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

Insumos:
  datos_avance_capital_asegurado_agosto/stock_agosto_aseg_seg.csv : stock (K1, 2026-08-18)
  datos_meta_agosto/ago_calendario.csv : calendario (K3, reutilizado -- igual que en julio,
                                          el calendario no tiene el bug 12, ver BUGS.md)
  datos_capital_asegurado/curva_asegurado_stock_seg.csv / curva_asegurado_nuevos_seg.csv

Real a la fecha (1-18 ago), query K4 (2026-08-18): ASEG_STOCK saldo_asegurado_real=2,605,896.73
(1,678/2,696 creditos activados), ASEG_NUEVOS saldo_asegurado_real=4,189,176.85
(2,773/4,141 creditos activados) -- hardcodeado abajo, no hay CSV diario.
Real fantasma a la fecha (1-18 ago, query 2026-08-20, investigacion_capa_fantasma.sql
patron): S/2,827,691.80 (1,997 creditos) -- hardcodeado abajo, no hay CSV diario.
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
P_FANTASMA = 29845 / 353054      # 8.4534% -- capa fantasma, ver enfoque_capital_asegurado.sql Q3
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

INICIO = date(2026, 8, 1)
HOY = date(2026, 8, 18)
N_DIAS = 31
saldo_stock_inicial = sum(stock_agosto.values())

REAL_STOCK_A_HOY = 2605896.73
REAL_NUEVOS_A_HOY = 4189176.85
REAL_FANTASMA_A_HOY = 2827691.80

filas = []
for d in range(1, N_DIAS + 1):
    fecha = INICIO + timedelta(days=d - 1)

    aseg_stock = sum(
        stock_agosto.get((t, a), 0.0) * lookup(curva_aseg_stock.get((t, a), {}), d) / 100.0
        for t in TRAMOS for a in AVANCES
    )
    aseg_nuevos = 0.0
    aseg_fantasma = 0.0
    for dd in range(1, d + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        riesgo_por_avance = calendario_agosto.get(fecha_venc, {})
        dias_desde_entrada = d - dd
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in riesgo_por_avance.items():
            pct = lookup(curva_aseg_nuevos.get(avance, {}), dias_desde_entrada)
            aseg_nuevos += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0
        # fantasma: 100% activado el dia siguiente al vencimiento, sin curva
        aseg_fantasma += sum(riesgo_por_avance.values()) * P_FANTASMA

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
    print(f"Ya asegurado real (1-18 ago):                     S/ {real_total_hoy:,.0f}")
    print(f"  stock: S/ {REAL_STOCK_A_HOY:,.0f}  |  nuevos: S/ {REAL_NUEVOS_A_HOY:,.0f}  |  fantasma: S/ {REAL_FANTASMA_A_HOY:,.0f}")
    print(f"Meta proyectada acumulada al mismo día (día 18):  S/ {hoy_row['aseg_total']:,.0f}")
    avance_pct = 100 * real_total_hoy / fin_row['aseg_total']
    print(f"Avance real vs meta total del mes: {avance_pct:.1f}%")
    err_dia18 = real_total_hoy - hoy_row['aseg_total']
    print(f"Real vs. proyectado AL MISMO DIA (18): {100*err_dia18/hoy_row['aseg_total']:+.1f}%")
    print(f"\n>>> LO QUE RESTA DEL MES (día 19 al 31): S/ {fin_row['aseg_total'] - real_total_hoy:,.0f} <<<")

"""
Reconstruye la meta de recupero del mes en curso (julio 2026), anclada al
cierre real de junio, y compara contra el recupero real a la fecha de corte.
Ver meta_julio_en_vivo.html para la version presentacion, y guia_tecnica_recupero.md
seccion de proyeccion para la explicacion completa del mecanismo.

Insumos (CSV en datos_meta_julio/):
  stock_julio_seg.csv  : stock al cierre de junio, por tramo x avance
  jul_calendario.csv   : calendario de vencimientos de julio (saldo exacto dias
                          1-9, saldo vigente como proxy dias 10-31), por avance
  jul_real_a_hoy.csv   : rebaje diario real de julio (1-9), stock y nuevos
  curva_stock_seg.csv / curva_nuevos_seg.csv : curvas calibradas (14 meses)

Para replicar en un corte de fecha distinto: recalcular jul_calendario.csv y
jul_real_a_hoy.csv con el mismo patron de fase3_backtest.sql, ajustando las
fechas de corte.
"""
import csv
from datetime import date, timedelta

DIR = "datos_meta_julio"

stock_julio = {}
with open(f"{DIR}/stock_julio_seg.csv") as f:
    for row in csv.DictReader(f):
        stock_julio[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_stock = {}
with open(f"{DIR}/curva_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_recupero_acum"])

curva_nuevos = {}
with open(f"{DIR}/curva_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_nuevos.setdefault(row["avance_band"], {})[int(row["dia_desde_entrada"])] = float(row["pct_recupero_acum"])

calendario_julio = {}
with open(f"{DIR}/jul_calendario.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_en_riesgo"]
        calendario_julio.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

real_dia = {"stock": {}, "nuevos": {}}
with open(f"{DIR}/jul_real_a_hoy.csv") as f:
    for row in csv.DictReader(f):
        real_dia[row["poblacion"]][row["fechaproceso"]] = float(row["rebaje_dia"])

def lookup(curva, d):
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

P_NO_PAGA_DIA0 = 47966 / 358580  # 13.38%, calibrada fuera de muestra (ver backtest de junio)
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

INICIO = date(2026, 7, 1)
HOY = date(2026, 7, 9)
N_DIAS = 31
saldo_stock_inicial = sum(stock_julio.values())

filas = []
real_stock_acum = 0.0
real_nuevos_acum = 0.0
for d in range(1, N_DIAS + 1):
    fecha = INICIO + timedelta(days=d - 1)
    fecha_s = fecha.strftime("%Y%m%d")

    proy_stock = sum(
        stock_julio.get((t, a), 0.0) * lookup(curva_stock.get((t, a), {}), d) / 100.0
        for t in TRAMOS for a in AVANCES
    )
    proy_nuevos = 0.0
    for dd in range(1, d + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        riesgo_por_avance = calendario_julio.get(fecha_venc, {})
        dias_desde_entrada = d - dd
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in riesgo_por_avance.items():
            pct = lookup(curva_nuevos.get(avance, {}), dias_desde_entrada)
            proy_nuevos += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0

    if fecha <= HOY:
        real_stock_acum += real_dia["stock"].get(fecha_s, 0.0)
        real_nuevos_acum += real_dia["nuevos"].get(fecha_s, 0.0)

    filas.append({
        "dia": d, "fecha": fecha.isoformat(),
        "proy_stock": proy_stock, "proy_nuevos": proy_nuevos, "proy_total": proy_stock + proy_nuevos,
        "real_stock": real_stock_acum, "real_nuevos": real_nuevos_acum, "real_total": real_stock_acum + real_nuevos_acum,
    })

print(f"Stock al 1 de julio (cierre real de junio): S/ {saldo_stock_inicial:,.0f}\n")
print(f"{'dia':>3} {'fecha':>11} | {'proy_total':>11} | {'real_total (si ya paso)':>22}")
for r in filas:
    marca = " <- hoy" if r["fecha"] == HOY.isoformat() else ""
    real_str = f"{r['real_total']:,.0f}" if date.fromisoformat(r["fecha"]) <= HOY else ""
    print(f"{r['dia']:>3} {r['fecha']:>11} | {r['proy_total']:>11,.0f} | {real_str:>22}{marca}")

hoy_row = next(r for r in filas if r["fecha"] == HOY.isoformat())
fin_row = filas[-1]
print(f"\n=== RESUMEN AL {HOY.isoformat()} ===")
print(f"Meta total de julio (proyectada al cierre):     S/ {fin_row['proy_total']:,.0f}")
print(f"  stock: S/ {fin_row['proy_stock']:,.0f}  |  nuevos: S/ {fin_row['proy_nuevos']:,.0f}")
print(f"Ya recuperado real (1-9 jul):                    S/ {hoy_row['real_total']:,.0f}")
print(f"  stock: S/ {hoy_row['real_stock']:,.0f}  |  nuevos: S/ {hoy_row['real_nuevos']:,.0f}")
print(f"Meta proyectada acumulada al mismo día (día 9):  S/ {hoy_row['proy_total']:,.0f}")
avance_pct = 100*hoy_row['real_total']/fin_row['proy_total']
print(f"Avance real vs meta total del mes: {avance_pct:.1f}%")
print(f"\n>>> LO QUE RESTA DEL MES (día 10 al 31): S/ {fin_row['proy_total'] - hoy_row['real_total']:,.0f} <<<")

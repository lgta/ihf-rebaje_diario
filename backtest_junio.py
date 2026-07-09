"""
Backtest de la meta de recupero sobre junio 2026 (mes real y cerrado).
Compara la proyeccion (curvas calibradas + calendario real de vencimientos)
contra el recupero REAL de junio, dia a dia. Ver plan_analisis.md seccion
"Backtest sobre junio 2026" para el analisis completo.

Resultado: +5.4% de error al cierre (stock +16.2%, nuevos +0.7%).

Insumos (CSV en datos_backtest_junio/, exportados de Athena via
fase3_backtest.sql bloques 3G-1 a 3G-4, y fase1_stock.sql / fase2_nuevos.sql
para las curvas segmentadas):
  bt_stock_junio.csv     : stock al cierre de mayo-2026, por tramo x avance (3G-1)
  bt_calendario_junio.csv: calendario real de vencimientos de junio, por avance (3G-2)
  bt_real_stock.csv      : rebaje diario REAL de junio, poblacion stock (3G-3)
  bt_real_nuevos.csv     : rebaje diario REAL de junio, poblacion nuevos (3G-4)
  curva_stock_seg.csv    : curva de stock por tramo x avance x dia (fase1_stock.sql)
  curva_nuevos_seg.csv   : curva de nuevos por avance x dia desde entrada (fase2_nuevos.sql)
"""
import csv
from datetime import date, timedelta

DIR = "datos_backtest_junio"

stock_junio = {}
with open(f"{DIR}/bt_stock_junio.csv") as f:
    for row in csv.DictReader(f):
        stock_junio[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_stock = {}
with open(f"{DIR}/curva_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_recupero_acum"])

curva_nuevos = {}
with open(f"{DIR}/curva_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_nuevos.setdefault(row["avance_band"], {})[int(row["dia_desde_entrada"])] = float(row["pct_recupero_acum"])

calendario_junio = {}
with open(f"{DIR}/bt_calendario_junio.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_en_riesgo"]
        calendario_junio.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

real_stock_dia = {}
with open(f"{DIR}/bt_real_stock.csv") as f:
    for row in csv.DictReader(f):
        real_stock_dia[row["fechaproceso"]] = float(row["rebaje_dia"])

real_nuevos_dia = {}
with open(f"{DIR}/bt_real_nuevos.csv") as f:
    for row in csv.DictReader(f):
        real_nuevos_dia[row["fechaproceso"]] = float(row["rebaje_dia"])

def lookup(curva, d):
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

# Tasa fuera de muestra (ago-2025 a may-2026, SIN junio) -- ver fase3_backtest.sql 3H.
# NO usar la tasa propia de junio (10.96%) para validar junio: seria data leakage.
P_NO_PAGA_DIA0 = 47966 / 358580  # 13.38%
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

INICIO = date(2026, 6, 1)
N_DIAS = 30
saldo_stock_inicial = sum(stock_junio.values())

filas = []
real_stock_acum = 0.0
real_nuevos_acum = 0.0
for d in range(1, N_DIAS + 1):
    fecha = INICIO + timedelta(days=d - 1)
    fecha_s = fecha.strftime("%Y%m%d")
    fecha_iso = fecha.isoformat()

    proy_stock = sum(
        stock_junio.get((t, a), 0.0) * lookup(curva_stock.get((t, a), {}), d) / 100.0
        for t in TRAMOS for a in AVANCES
    )
    proy_nuevos = 0.0
    for dd in range(1, d + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        riesgo_por_avance = calendario_junio.get(fecha_venc, {})
        dias_desde_entrada = d - dd
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in riesgo_por_avance.items():
            pct = lookup(curva_nuevos.get(avance, {}), dias_desde_entrada)
            proy_nuevos += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0

    real_stock_acum += real_stock_dia.get(fecha_s, 0.0)
    real_nuevos_acum += real_nuevos_dia.get(fecha_s, 0.0)

    filas.append({
        "dia": d, "fecha": fecha_iso,
        "proy_stock": proy_stock, "proy_nuevos": proy_nuevos, "proy_total": proy_stock + proy_nuevos,
        "real_stock": real_stock_acum, "real_nuevos": real_nuevos_acum, "real_total": real_stock_acum + real_nuevos_acum,
    })

if __name__ == "__main__":
    print(f"Stock al cierre de mayo (dia 1 de junio): S/ {saldo_stock_inicial:,.0f}\n")
    print(f"{'dia':>3} {'fecha':>11} | {'proy_stock':>10} {'proy_nuevos':>11} {'PROY_total':>11} | {'real_stock':>10} {'real_nuevos':>11} {'REAL_total':>11} | {'error':>8}")
    for r in filas:
        err = r["proy_total"] - r["real_total"]
        errp = 100 * err / r["real_total"] if r["real_total"] else 0
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['proy_stock']:>10,.0f} {r['proy_nuevos']:>11,.0f} {r['proy_total']:>11,.0f} | {r['real_stock']:>10,.0f} {r['real_nuevos']:>11,.0f} {r['real_total']:>11,.0f} | {errp:>+7.1f}%")

    f = filas[-1]
    print(f"\n=== CIERRE DE JUNIO (dia 30) ===")
    print(f"Proyectado: S/ {f['proy_total']:,.0f}  (stock S/ {f['proy_stock']:,.0f} + nuevos S/ {f['proy_nuevos']:,.0f})")
    print(f"Real:       S/ {f['real_total']:,.0f}  (stock S/ {f['real_stock']:,.0f} + nuevos S/ {f['real_nuevos']:,.0f})")
    err = f["proy_total"] - f["real_total"]
    print(f"Error: S/ {err:+,.0f}  ({100*err/f['real_total']:+.1f}%)")

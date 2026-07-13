"""
Tracking en vivo del capital asegurado de julio 2026 (enfoque alfa), anclado
al cierre real de junio -- misma poblacion (stock/calendario) que meta_julio.py,
comparado contra el capital asegurado REAL a la fecha de corte. Mismo patron
que meta_julio.py, cambiando la curva de "% recuperado" por la de "% con >=1
pago" (capital asegurado) -- ver enfoque_capital_asegurado.md.

Insumos:
  datos_meta_julio/stock_julio_seg.csv, jul_calendario.csv (poblacion, reutilizada)
  datos_capital_asegurado/curva_asegurado_stock_seg.csv, curva_asegurado_nuevos_seg.csv
  datos_avance_capital_asegurado_julio/jul_aseg_real_stock.csv, jul_aseg_real_nuevos.csv
    (capital REAL activado por dia, poblacion stock/nuevos, generado igual que el
    backtest de junio -- enfoque_capital_asegurado_backtest.sql, adaptado a julio)
"""
import csv
from datetime import date, timedelta

DIR_JULIO = "datos_meta_julio"
DIR_ASEG = "datos_capital_asegurado"
DIR_REAL = "datos_avance_capital_asegurado_julio"

stock_julio = {}
with open(f"{DIR_JULIO}/stock_julio_seg.csv") as f:
    for row in csv.DictReader(f):
        stock_julio[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_aseg_stock = {}
with open(f"{DIR_ASEG}/curva_asegurado_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_aseg_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

curva_aseg_nuevos = {}
with open(f"{DIR_ASEG}/curva_asegurado_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_aseg_nuevos.setdefault(row["avance_band"], {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

calendario_julio = {}
with open(f"{DIR_JULIO}/jul_calendario.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_en_riesgo"]
        calendario_julio.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

real_dia = {"stock": {}, "nuevos": {}}
with open(f"{DIR_REAL}/jul_aseg_real_stock.csv") as f:
    for row in csv.DictReader(f):
        real_dia["stock"][row["fechaproceso"]] = float(row["saldo_activado_dia"])
with open(f"{DIR_REAL}/jul_aseg_real_nuevos.csv") as f:
    for row in csv.DictReader(f):
        real_dia["nuevos"][row["fechaproceso"]] = float(row["saldo_activado_dia"])

def lookup(curva, d):
    if d <= 0 or not curva:
        return 0.0
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

P_NO_PAGA_DIA0 = 47966 / 358580  # 13.38%, misma tasa que el modelo oficial
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

INICIO = date(2026, 7, 1)
HOY = date(2026, 7, 13)  # ultima fecha con datos en dts_mambu_loans_hist a la corrida
N_DIAS = 31
saldo_stock_inicial = sum(stock_julio.values())

filas = []
real_stock_acum = 0.0
real_nuevos_acum = 0.0
for d in range(1, N_DIAS + 1):
    fecha = INICIO + timedelta(days=d - 1)
    fecha_s = fecha.strftime("%Y%m%d")

    aseg_stock = sum(
        stock_julio.get((t, a), 0.0) * lookup(curva_aseg_stock.get((t, a), {}), d) / 100.0
        for t in TRAMOS for a in AVANCES
    )
    aseg_nuevos = 0.0
    for dd in range(1, d + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        riesgo_por_avance = calendario_julio.get(fecha_venc, {})
        dias_desde_entrada = d - dd
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in riesgo_por_avance.items():
            pct = lookup(curva_aseg_nuevos.get(avance, {}), dias_desde_entrada)
            aseg_nuevos += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0

    if fecha <= HOY:
        real_stock_acum += real_dia["stock"].get(fecha_s, 0.0)
        real_nuevos_acum += real_dia["nuevos"].get(fecha_s, 0.0)

    filas.append({
        "dia": d, "fecha": fecha.isoformat(),
        "aseg_stock": aseg_stock, "aseg_nuevos": aseg_nuevos, "aseg_total": aseg_stock + aseg_nuevos,
        "real_stock": real_stock_acum, "real_nuevos": real_nuevos_acum, "real_total": real_stock_acum + real_nuevos_acum,
    })

if __name__ == "__main__":
    print(f"Stock al 1 de julio (cierre real de junio): S/ {saldo_stock_inicial:,.0f}\n")
    print(f"{'dia':>3} {'fecha':>11} | {'proy_total':>11} | {'real_total (si ya paso)':>22}")
    for r in filas:
        marca = " <- hoy" if r["fecha"] == HOY.isoformat() else ""
        real_str = f"{r['real_total']:,.0f}" if date.fromisoformat(r["fecha"]) <= HOY else ""
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['aseg_total']:>11,.0f} | {real_str:>22}{marca}")

    hoy_row = next(r for r in filas if r["fecha"] == HOY.isoformat())
    fin_row = filas[-1]
    print(f"\n=== RESUMEN AL {HOY.isoformat()} -- ENFOQUE ALFA: CAPITAL ASEGURADO ===")
    print(f"Meta total de julio (proyectada al cierre):     S/ {fin_row['aseg_total']:,.0f}")
    print(f"  stock: S/ {fin_row['aseg_stock']:,.0f}  |  nuevos: S/ {fin_row['aseg_nuevos']:,.0f}")
    print(f"Ya asegurado real (1-13 jul):                    S/ {hoy_row['real_total']:,.0f}")
    print(f"  stock: S/ {hoy_row['real_stock']:,.0f}  |  nuevos: S/ {hoy_row['real_nuevos']:,.0f}")
    print(f"Meta proyectada acumulada al mismo día (día 13): S/ {hoy_row['aseg_total']:,.0f}")
    avance_pct = 100 * hoy_row['real_total'] / fin_row['aseg_total']
    print(f"Avance real vs meta total del mes: {avance_pct:.1f}%")
    err_dia13 = hoy_row['real_total'] - hoy_row['aseg_total']
    print(f"Real vs. proyectado AL MISMO DIA (13): {100*err_dia13/hoy_row['aseg_total']:+.1f}%")
    print(f"\n>>> LO QUE RESTA DEL MES (día 14 al 31): S/ {fin_row['aseg_total'] - hoy_row['real_total']:,.0f} <<<")

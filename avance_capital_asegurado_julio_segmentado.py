"""
Avance de julio 2026 (capital asegurado) desglosado por segmento -- tramo
x avance para stock, avance para nuevos. Complementa
avance_capital_asegurado_julio.py (que solo da el total). Ver
enfoque_capital_asegurado.md seccion "Tracking en vivo" y el artifact
capital_asegurado.html.

Insumos:
  avance_capital_asegurado_julio_segmentado.sql -> Q1/Q2, resultado en
    datos_avance_capital_asegurado_julio/jul_aseg_real_stock_seg.csv y
    jul_aseg_real_nuevos_seg.csv
  datos_capital_asegurado/curva_asegurado_stock_seg.csv, curva_asegurado_nuevos_seg.csv
  datos_meta_julio/jul_calendario.csv (calendario de julio por avance, reutilizado)
"""
import csv
from datetime import date, timedelta

DIR_ASEG = "datos_capital_asegurado"
DIR_JULIO = "datos_meta_julio"
DIR_REAL = "datos_avance_capital_asegurado_julio"

def lookup(curva, d):
    if d <= 0 or not curva:
        return 0.0
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

curva_stock = {}
for row in csv.DictReader(open(f"{DIR_ASEG}/curva_asegurado_stock_seg.csv")):
    key = (row["tramo"], row["avance_band"])
    curva_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

curva_nuevos = {}
for row in csv.DictReader(open(f"{DIR_ASEG}/curva_asegurado_nuevos_seg.csv")):
    curva_nuevos.setdefault(row["avance_band"], {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

calendario_julio = {}
for row in csv.DictReader(open(f"{DIR_JULIO}/jul_calendario.csv")):
    val = row["saldo_en_riesgo"]
    calendario_julio.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

P_NO_PAGA = 47966 / 358580  # 13.38%, misma tasa que el modelo oficial
DIA = 13  # dia de corte (2-jul = dia1 ... ajustar segun corte vigente)
INICIO = date(2026, 7, 1)

# ---- STOCK ----
real_stock = list(csv.DictReader(open(f"{DIR_REAL}/jul_aseg_real_stock_seg.csv")))
stock_rows = []
tot_asig = tot_meta = tot_real = 0.0
for r in real_stock:
    tramo, avance = r["tramo"], r["avance_band"]
    asignado = float(r["saldo_total"])
    real = float(r["saldo_asegurado_real"])
    pct_meta = lookup(curva_stock.get((tramo, avance), {}), DIA)
    meta_s = asignado * pct_meta / 100.0
    real_pct = 100 * real / asignado if asignado else 0
    tot_asig += asignado; tot_meta += meta_s; tot_real += real
    stock_rows.append({"tramo": tramo, "avance": avance, "creditos": int(r["creditos"]),
        "asignado": asignado, "meta_pct": pct_meta, "meta_s": meta_s, "real_s": real,
        "real_pct": real_pct, "diff_pp": real_pct - pct_meta})

# ---- NUEVOS ----
real_nuevos = list(csv.DictReader(open(f"{DIR_REAL}/jul_aseg_real_nuevos_seg.csv")))
nuevos_rows = []
tot_asig_n = tot_meta_n = tot_real_n = 0.0
for r in real_nuevos:
    avance = r["avance_band"]
    asignado = float(r["saldo_total"])
    real = float(r["saldo_asegurado_real"])
    meta_s = 0.0
    for dd in range(1, DIA + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        saldo_riesgo = calendario_julio.get(fecha_venc, {}).get(avance, 0.0)
        dias_desde_entrada = DIA - dd
        if dias_desde_entrada < 1:
            continue
        pct = lookup(curva_nuevos.get(avance, {}), dias_desde_entrada)
        meta_s += saldo_riesgo * P_NO_PAGA * pct / 100.0
    real_pct = 100 * real / asignado if asignado else 0
    diff_pct = 100 * (real - meta_s) / meta_s if meta_s else 0
    tot_asig_n += asignado; tot_meta_n += meta_s; tot_real_n += real
    nuevos_rows.append({"avance": avance, "entradas": int(r["entradas"]), "asignado": asignado,
        "real_s": real, "real_pct": real_pct, "meta_s": meta_s, "diff_pct": diff_pct})

if __name__ == "__main__":
    print("=== STOCK (tramo x avance) -- dia", DIA, "===")
    for r in stock_rows:
        print(f"{r['tramo']:<10} {r['avance']:<18} {r['creditos']:>6}  asignado {r['asignado']:>10,.0f}  meta {r['meta_pct']:>5.1f}% ({r['meta_s']:>9,.0f})  real {r['real_pct']:>5.1f}% ({r['real_s']:>9,.0f})  diff {r['diff_pp']:>+5.1f}pp")
    print(f"TOTAL STOCK: asignado {tot_asig:,.0f} | meta {100*tot_meta/tot_asig:.1f}% ({tot_meta:,.0f}) | real {100*tot_real/tot_asig:.1f}% ({tot_real:,.0f})")

    print("\n=== NUEVOS (por avance) -- dia", DIA, "===")
    for r in nuevos_rows:
        print(f"{r['avance']:<18} {r['entradas']:>6}  asignado {r['asignado']:>10,.0f}  real {r['real_pct']:>5.1f}% ({r['real_s']:>9,.0f})  meta modelo {r['meta_s']:>9,.0f}  real vs meta {r['diff_pct']:>+6.1f}%")
    print(f"TOTAL NUEVOS: asignado {tot_asig_n:,.0f} | real {tot_real_n:,.0f} | meta {tot_meta_n:,.0f} | real vs meta {100*(tot_real_n-tot_meta_n)/tot_meta_n:+.1f}%")

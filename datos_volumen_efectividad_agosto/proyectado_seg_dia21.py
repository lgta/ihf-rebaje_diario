"""
Proyectado a dia 21 de agosto, segmentado (tramo x avance para stock, avance
para nuevos) -- para comparar contra el real segmentado de K1/K2 (corte
21-ago, sesion 2026-08-22). Reutiliza las curvas y el calendario ya
calibrados (sin cambios), solo evalua en dia=21 y desagrega por segmento en
vez de sumar.
"""
import csv

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
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

from datetime import date, timedelta
INICIO = date(2026, 8, 1)
D = 21  # dia de corte (2026-08-21, mismo corte que K1/K2/K3/K4/K5 de esta sesion)

print("=== PROYECTADO STOCK (tramo x avance) a dia 21 ===")
print(f"{'tramo':>10} {'avance':>18} | {'saldo_pob':>12} {'pct_curva':>10} {'proyectado':>12}")
tot_stock = 0.0
for t in TRAMOS:
    for a in AVANCES:
        pob = stock_agosto.get((t, a), 0.0)
        pct = lookup(curva_aseg_stock.get((t, a), {}), D)
        proy = pob * pct / 100.0
        tot_stock += proy
        print(f"{t:>10} {a:>18} | {pob:>12,.0f} {pct:>10.3f} {proy:>12,.0f}")
print(f"{'TOTAL STOCK':>29} | {'':>12} {'':>10} {tot_stock:>12,.0f}")

print("\n=== PROYECTADO NUEVOS (avance) a dia 21 -- calendario acumulado dia2-21 ===")
por_avance_nuevos = {a: 0.0 for a in AVANCES}
por_avance_elegible = {a: 0.0 for a in AVANCES}
for dd in range(1, D + 1):
    fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
    riesgo_por_avance = calendario_agosto.get(fecha_venc, {})
    dias_desde_entrada = D - dd
    if dias_desde_entrada < 1:
        continue
    for avance, saldo_riesgo in riesgo_por_avance.items():
        pct = lookup(curva_aseg_nuevos.get(avance, {}), dias_desde_entrada)
        por_avance_nuevos[avance] = por_avance_nuevos.get(avance, 0.0) + saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0
        por_avance_elegible[avance] = por_avance_elegible.get(avance, 0.0) + saldo_riesgo
tot_nuevos = 0.0
print(f"{'avance':>18} | {'saldo_riesgo_calend':>20} {'proyectado':>12}")
for a in AVANCES:
    tot_nuevos += por_avance_nuevos[a]
    print(f"{a:>18} | {por_avance_elegible[a]:>20,.0f} {por_avance_nuevos[a]:>12,.0f}")
print(f"{'TOTAL NUEVOS':>18} | {'':>20} {tot_nuevos:>12,.0f}")

P_FANTASMA = 29625 / 346396
CUOTAS_31JUL_FANTASMA = {
    "a. avance <10%": 52928.0, "b. avance 10-40%": 56252.0,
    "c. avance 40-70%": 23453.0, "d. avance 70%+": 7561.0,
}
saldo_31jul = sum(CUOTAS_31JUL_FANTASMA.values())
aseg_fantasma = saldo_31jul * P_FANTASMA
for dd in range(1, D + 1):
    fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
    riesgo_por_avance = calendario_agosto.get(fecha_venc, {})
    dias_desde_entrada = D - dd
    if dias_desde_entrada < 1:
        continue
    aseg_fantasma += sum(riesgo_por_avance.values()) * P_FANTASMA

print(f"\n=== PROYECTADO FANTASMA (agregado, sin segmentar) a dia 21: S/ {aseg_fantasma:,.0f} ===")
print(f"\n=== TOTAL PROYECTADO A DIA 21: S/ {tot_stock + tot_nuevos + aseg_fantasma:,.0f} ===")
print(f"  stock: S/ {tot_stock:,.0f} | nuevos: S/ {tot_nuevos:,.0f} | fantasma: S/ {aseg_fantasma:,.0f}")

"""
Meta "reinicio del reloj": trata la foto de HOY como una nueva linea
base (en vez de anclar al cierre del mes anterior) y proyecta el resto
del mes desde ahi. Ver meta_desde_hoy.sql para las queries de origen.

Contraste con meta_julio.py (ancla a cierre de junio, cohortes por
fecha de entrada real): mas simple pero trata a los creditos que ya
llevaban dias en mora como si fueran "dia 1" frescos hoy. Ambos
enfoques convergieron a +1.0% de diferencia el 2026-07-09 -- util como
cruce de validacion, no reemplaza el enfoque acumulado.

Insumos en datos_meta_desde_hoy/:
  stock_hoy_09jul.csv        : stock de HOY, por tramo x avance (Q1)
  calendario_hoy_adelante.csv: vencimientos desde manana, por avance (Q2)
  curva_stock_seg.csv / curva_nuevos_seg.csv : curvas calibradas (14 meses)
"""
import csv
from datetime import date, timedelta

DIR = "datos_meta_desde_hoy"

stock_hoy = {}
with open(f"{DIR}/stock_hoy_09jul.csv") as f:
    for row in csv.DictReader(f):
        stock_hoy[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_stock = {}
with open(f"{DIR}/curva_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_recupero_acum"])

curva_nuevos = {}
with open(f"{DIR}/curva_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_nuevos.setdefault(row["avance_band"], {})[int(row["dia_desde_entrada"])] = float(row["pct_recupero_acum"])

calendario = {}
with open(f"{DIR}/calendario_hoy_adelante.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_en_riesgo"]
        calendario.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

def lookup(curva, d):
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

P_NO_PAGA = 47966 / 358580  # 13.38%, fuera de muestra
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

HOY = date(2026, 7, 9)
FIN_MES = date(2026, 7, 31)
N_DIAS_RESTANTES = (FIN_MES - HOY).days  # 22

print("=" * 78)
print("PASO 1 - STOCK RE-BASELINEADO A HOY (9-jul), detalle por segmento")
print("=" * 78)
print(f"{'tramo':<10} {'avance':<18} {'saldo hoy':>12} {'curva d22':>10} {'aporte a d31':>14}")
total_stock = 0.0
stock_rows = []
for t in TRAMOS:
    for a in AVANCES:
        saldo = stock_hoy.get((t, a), 0.0)
        pct = lookup(curva_stock.get((t, a), {}), N_DIAS_RESTANTES)
        aporte = saldo * pct / 100.0
        total_stock += aporte
        stock_rows.append((t, a, saldo, pct, aporte))
        print(f"{t:<10} {a:<18} {saldo:>12,.0f} {pct:>9.2f}% {aporte:>14,.0f}")
print(f"{'TOTAL STOCK':<29} {sum(stock_hoy.values()):>12,.0f} {'':>10} {total_stock:>14,.0f}")

print()
print("=" * 78)
print("PASO 2 - CALENDARIO DE NUEVOS DESDE 10-JUL, agregado por banda de avance")
print("=" * 78)
print(f"{'avance':<18} {'saldo en riesgo':>16} {'entra en mora':>14} {'aporte a d31':>14}")
total_nuevos = 0.0
nuevos_por_banda = {a: {"saldo_riesgo": 0.0, "entra_mora": 0.0, "aporte": 0.0} for a in AVANCES}
for fecha_venc, bandas in calendario.items():
    D = date.fromisoformat(fecha_venc)
    dias_desde_entrada = (FIN_MES - D).days  # dias que tendra esa cohorte para madurar hasta cierre
    for a, saldo_riesgo in bandas.items():
        entra_mora = saldo_riesgo * P_NO_PAGA
        pct = lookup(curva_nuevos.get(a, {}), dias_desde_entrada) if dias_desde_entrada >= 1 else 0.0
        aporte = entra_mora * pct / 100.0
        nuevos_por_banda[a]["saldo_riesgo"] += saldo_riesgo
        nuevos_por_banda[a]["entra_mora"] += entra_mora
        nuevos_por_banda[a]["aporte"] += aporte
        total_nuevos += aporte

for a in AVANCES:
    r = nuevos_por_banda[a]
    print(f"{a:<18} {r['saldo_riesgo']:>16,.0f} {r['entra_mora']:>14,.0f} {r['aporte']:>14,.0f}")
print(f"{'TOTAL NUEVOS':<18} {sum(r['saldo_riesgo'] for r in nuevos_por_banda.values()):>16,.0f} "
      f"{sum(r['entra_mora'] for r in nuevos_por_banda.values()):>14,.0f} {total_nuevos:>14,.0f}")

print()
print("=" * 78)
print(f"META DESDE HOY ({HOY.isoformat()}) HASTA CIERRE DE JULIO ({N_DIAS_RESTANTES} dias)")
print("=" * 78)
print(f"  Stock (re-baseline):  S/ {total_stock:,.0f}")
print(f"  Nuevos (10-31 jul):   S/ {total_nuevos:,.0f}")
print(f"  META TOTAL:           S/ {total_stock + total_nuevos:,.0f}")

print()
print("Comparacion con el enfoque anterior (acumulado real + resto proyectado")
print("del stock anclado a 1-jul): S/ 1,248,799")
print(f"Diferencia: {100*((total_stock+total_nuevos)-1248799)/1248799:+.1f}%")

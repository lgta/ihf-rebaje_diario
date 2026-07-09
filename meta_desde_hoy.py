"""
Meta "reinicio del reloj": trata la foto de HOY como una nueva linea
base (en vez de anclar al cierre del mes anterior) y proyecta el resto
del mes desde ahi. Ver meta_desde_hoy.sql para las queries de origen.

Contraste con meta_julio.py (ancla a cierre de junio, cohortes por
fecha de entrada real): mas simple pero trata a los creditos que ya
llevaban dias en mora como si fueran "dia 1" frescos hoy -- salvo el
caso "aged-out" corregido abajo, que SI necesita la logica acumulada.

BUG CORREGIDO 2026-07-09 (ver plan_analisis.md "Meta en vivo de
julio"): la version anterior filtraba el stock con "mora between 1
and 30" usando la mora de HOY, lo que excluia silenciosamente a los
creditos del stock original de julio que ya habian cruzado 30 dias de
mora -- 244 creditos, S/501,307 (todos originalmente tramo 16-30).
Esta version los reincorpora como un componente aparte (PASO 0),
usando su clasificacion y saldo ORIGINALES (30-jun) con la logica
acumulada (curva dia31 - curva dia9), porque su punto de referencia
real es la asignacion, no hoy. El resultado final (S/1,283,679) queda
MAS lejos del enfoque acumulado oficial (S/1,248,799, +2.8% en vez de
+1.0%) que antes de corregir el bug -- la cercania original de +1.0%
era en parte casualidad, compensada por la sobreestimacion de tratar
a los supervivientes de julio-1 como "dia 1 fresco". Se mantiene el
enfoque acumulado (meta_julio.py) como fuente oficial; este script es
solo un cruce de validacion secundario.

Insumos en datos_meta_desde_hoy/:
  stock_hoy_09jul.csv        : stock de HOY, por tramo x avance (Q1)
  aged_out_hoy.csv           : supervivientes >30 dias del stock original (Q0)
  calendario_hoy_adelante.csv: vencimientos desde manana, por avance (Q2, ya
                                excluye Q0 y Q1 para no duplicar saldo)
  curva_stock_seg.csv / curva_nuevos_seg.csv : curvas calibradas (14 meses)
"""
import csv
from datetime import date, timedelta

DIR = "datos_meta_desde_hoy"

stock_hoy = {}
with open(f"{DIR}/stock_hoy_09jul.csv") as f:
    for row in csv.DictReader(f):
        stock_hoy[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

aged_out = {}
with open(f"{DIR}/aged_out_hoy.csv") as f:
    for row in csv.DictReader(f):
        aged_out[(row["tramo_original"], row["avance_band"])] = float(row["saldo_asignacion_total"])

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
ASIGNACION = date(2026, 6, 30)
FIN_MES = date(2026, 7, 31)
N_DIAS_RESTANTES = (FIN_MES - HOY).days          # 22
DIA_HOY_DESDE_ASIGNACION = (HOY - ASIGNACION).days  # 9
DIA_FIN_DESDE_ASIGNACION = (FIN_MES - ASIGNACION).days  # 31

print("=" * 78)
print("PASO 0 - CREDITOS AGED-OUT (stock original de julio, cruzaron 30 dias)")
print("=" * 78)
print(f"{'tramo orig.':<10} {'avance':<18} {'saldo 30-jun':>12} {'curva d31':>9} {'curva d9':>9} {'resto':>7} {'aporte':>12}")
total_aged_out = 0.0
for t in TRAMOS:
    for a in AVANCES:
        saldo = aged_out.get((t, a), 0.0)
        if saldo == 0:
            continue
        pct31 = lookup(curva_stock.get((t, a), {}), DIA_FIN_DESDE_ASIGNACION)
        pct9 = lookup(curva_stock.get((t, a), {}), DIA_HOY_DESDE_ASIGNACION)
        resto_pct = pct31 - pct9
        aporte = saldo * resto_pct / 100.0
        total_aged_out += aporte
        print(f"{t:<10} {a:<18} {saldo:>12,.0f} {pct31:>8.2f}% {pct9:>8.2f}% {resto_pct:>6.2f}% {aporte:>12,.0f}")
print(f"{'TOTAL AGED-OUT':<29} {sum(aged_out.values()):>12,.0f} {'':>9} {'':>9} {'':>7} {total_aged_out:>12,.0f}")

print()
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

meta_total = total_aged_out + total_stock + total_nuevos

print()
print("=" * 78)
print(f"META DESDE HOY ({HOY.isoformat()}) HASTA CIERRE DE JULIO ({N_DIAS_RESTANTES} dias)")
print("=" * 78)
print(f"  Aged-out (stock original >30 dias hoy): S/ {total_aged_out:,.0f}")
print(f"  Stock (re-baseline, sigue 1-30 hoy):    S/ {total_stock:,.0f}")
print(f"  Nuevos (10-31 jul):                     S/ {total_nuevos:,.0f}")
print(f"  META TOTAL (corregida):                 S/ {meta_total:,.0f}")

print()
print("Comparacion con el enfoque acumulado oficial (meta_julio.py):")
print("  Resto del mes segun acumulado: S/ 1,248,799")
print(f"  Diferencia: {100*(meta_total-1248799)/1248799:+.1f}%")

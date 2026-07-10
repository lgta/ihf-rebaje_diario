"""
Enfoque alfa: "capital asegurado" -- en vez de medir cuantos soles se
recuperan (rebaje), mide cuanto del capital ASIGNADO pertenece a
creditos que muestran AL MENOS 1 dia de pago en el mes. Un credito que
paga S/50 de un saldo de S/12,000 "asegura" los S/12,000 completos, no
solo los S/50 -- es una metrica de actividad/contacto efectivo, no de
recupero.

Usa el mismo mecanismo de combinacion (stock anclado a cierre de junio +
calendario de vencimientos x P(no paga)=13.38%) que el modelo oficial,
solo que reemplaza curva_stock/curva_nuevos (% recuperado) por
curva_asegurado_stock/curva_asegurado_nuevos (% con >=1 pago). La tasa
de entrada (13.38%) es la misma y sigue siendo consistente porque ambas
curvas (asegurado y recupero) se calibraron sobre la MISMA definicion de
entrada a mora (dayslate 0->1) -- ver feedback-tasa-curva-consistente.

Insumos: datos_meta_julio/ (stock y calendario, ya existentes) +
datos_capital_asegurado/ (curvas nuevas).
"""
import csv
from datetime import date, timedelta

DIR_JULIO = "datos_meta_julio"
DIR_ASEG = "datos_capital_asegurado"

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

def lookup(curva, d):
    if d <= 0:
        return 0.0
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

P_NO_PAGA = 47966 / 358580  # 13.38%, misma tasa que el modelo oficial (dayslate, fuera de muestra)
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]
INICIO = date(2026, 7, 1)
N_DIAS = 31

saldo_stock_inicial = sum(stock_julio.values())

filas = []
for d in range(1, N_DIAS + 1):
    fecha = INICIO + timedelta(days=d - 1)

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
            aseg_nuevos += saldo_riesgo * P_NO_PAGA * pct / 100.0

    filas.append({
        "dia": d, "fecha": fecha.isoformat(),
        "aseg_stock": aseg_stock, "aseg_nuevos": aseg_nuevos, "aseg_total": aseg_stock + aseg_nuevos,
    })

if __name__ == "__main__":
    print(f"Stock inicial (30-jun): S/ {saldo_stock_inicial:,.0f}\n")
    print(f"{'dia':>3} {'fecha':>11} | {'aseg_stock':>11} {'aseg_nuevos':>11} {'ASEG_total':>11}")
    for r in filas:
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['aseg_stock']:>11,.0f} {r['aseg_nuevos']:>11,.0f} {r['aseg_total']:>11,.0f}")

    f = filas[-1]
    print(f"\n=== CIERRE DE JULIO (dia 31) -- ENFOQUE ALFA: CAPITAL ASEGURADO ===")
    print(f"Capital asegurado proyectado: S/ {f['aseg_total']:,.0f}")
    print(f"  stock: S/ {f['aseg_stock']:,.0f}  |  nuevos: S/ {f['aseg_nuevos']:,.0f}")
    print(f"Stock inicial: S/ {saldo_stock_inicial:,.0f} -> {100*f['aseg_stock']/saldo_stock_inicial:.1f}% del stock queda 'asegurado'")

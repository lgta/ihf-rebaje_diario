import csv
from datetime import date, timedelta

DIR = "datos_backtest_junio"
DIRC = "datos_motor_cuota"

stock_junio = {}
with open(f"{DIR}/bt_stock_junio.csv") as f:
    for row in csv.DictReader(f):
        stock_junio[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_stock = {}
with open(f"{DIR}/curva_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_recupero_acum"])

curva_nuevos_dayslate = {}
with open(f"{DIR}/curva_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_nuevos_dayslate.setdefault(row["avance_band"], {})[int(row["dia_desde_entrada"])] = float(row["pct_recupero_acum"])

curva_nuevos_cuota = {}
with open(f"{DIRC}/curva_nuevos_cuota.csv") as f:
    for row in csv.DictReader(f):
        curva_nuevos_cuota.setdefault(row["avance_band"], {})[int(row["dia_desde_entrada"])] = float(row["pct_recupero_acum"])

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

AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]
INICIO = date(2026, 6, 1)
N_DIAS = 30

real_stock_total = sum(real_stock_dia.get((INICIO+timedelta(days=d-1)).strftime("%Y%m%d"),0.0) for d in range(1,N_DIAS+1))
real_nuevos_total = sum(real_nuevos_dia.get((INICIO+timedelta(days=d-1)).strftime("%Y%m%d"),0.0) for d in range(1,N_DIAS+1))
real_total = real_stock_total + real_nuevos_total

def correr_nuevos(p_no_paga, curva_nuevos):
    proy_nuevos_cierre = 0.0
    for dd in range(1, N_DIAS + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        riesgo_por_avance = calendario_junio.get(fecha_venc, {})
        dias_desde_entrada = N_DIAS - dd
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in riesgo_por_avance.items():
            pct = lookup(curva_nuevos.get(avance, {}), dias_desde_entrada)
            proy_nuevos_cierre += saldo_riesgo * p_no_paga * pct / 100.0
    return proy_nuevos_cierre

proy_stock_cierre = sum(
    stock_junio.get((t, a), 0.0) * lookup(curva_stock.get((t, a), {}), N_DIAS) / 100.0
    for t in TRAMOS for a in AVANCES
)

print(f"Real junio: stock S/{real_stock_total:,.0f} + nuevos S/{real_nuevos_total:,.0f} = S/{real_total:,.0f}")
print(f"Stock proyectado (motor sin cambios): S/{proy_stock_cierre:,.0f}  (error {100*(proy_stock_cierre-real_stock_total)/real_stock_total:+.1f}%)\n")

print(f"{'motor':>40} | {'proy_nuevos':>12} | {'err nuevos':>11} | {'proy_total':>12} | {'err total':>10}")
for label, p, curva in [
    ("dayslate 13.38% + curva dayslate", 47966/358580, curva_nuevos_dayslate),
    ("cuota 8.62% + curva cuota (NUEVO)", 30901/358361, curva_nuevos_cuota),
]:
    pn = correr_nuevos(p, curva)
    total = proy_stock_cierre + pn
    err_n = 100*(pn-real_nuevos_total)/real_nuevos_total
    err_t = 100*(total-real_total)/real_total
    print(f"{label:>40} | S/{pn:>10,.0f} | {err_n:>+10.1f}% | S/{total:>10,.0f} | {err_t:>+9.1f}%")

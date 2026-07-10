import csv, json
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

def lookup(curva, d):
    if d <= 0:
        return 0.0
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]
INICIO = date(2026, 7, 1)
N_DIAS = 31
P_OFICIAL = 47966 / 358580   # 13.38%
P_PLANO_25 = 0.25

saldo_stock_inicial = sum(stock_julio.values())

def correr(p_no_paga):
    filas = []
    for d in range(1, N_DIAS + 1):
        fecha = INICIO + timedelta(days=d - 1)
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
                proy_nuevos += saldo_riesgo * p_no_paga * pct / 100.0
        filas.append({"dia": d, "fecha": fecha.isoformat(), "proy_stock": proy_stock, "proy_nuevos": proy_nuevos, "proy_total": proy_stock + proy_nuevos})
    return filas

filas_oficial = correr(P_OFICIAL)
filas_25 = correr(P_PLANO_25)

f_of = filas_oficial[-1]
f_25 = filas_25[-1]
print(f"Stock inicial (30-jun): S/{saldo_stock_inicial:,.0f}\n")
print(f"OFICIAL (13.38%): stock S/{f_of['proy_stock']:,.0f} + nuevos S/{f_of['proy_nuevos']:,.0f} = S/{f_of['proy_total']:,.0f}")
print(f"25% PLANO (no recomendado): stock S/{f_25['proy_stock']:,.0f} + nuevos S/{f_25['proy_nuevos']:,.0f} = S/{f_25['proy_total']:,.0f}")
print(f"Diferencia nuevos: {100*(f_25['proy_nuevos']-f_of['proy_nuevos'])/f_of['proy_nuevos']:+.1f}%")
print(f"Diferencia total: {100*(f_25['proy_total']-f_of['proy_total'])/f_of['proy_total']:+.1f}%")

with open("datos_motor_cuota/julio_25_vs_oficial.json", "w") as f:
    json.dump({"oficial": filas_oficial, "plano25": filas_25, "stock_inicial": saldo_stock_inicial}, f)
print("\nguardado datos_motor_cuota/julio_25_vs_oficial.json")

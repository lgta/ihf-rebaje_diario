"""
Meta de recupero de agosto 2026 (enfoque oficial), anclada al cierre REAL
de julio (mes ya cerrado, a diferencia de cuando se corrio meta_julio.py).
Mismo mecanismo que meta_julio.py: stock x curva_stock + calendario x
P(no paga)=13.38% x curva_nuevos. Curvas y tasa SIN cambios (calibradas
sobre 14 meses de historia, ver DECISIONES.md).

Insumos:
  datos_meta_agosto/stock_agosto_seg.csv : stock al cierre de julio, tramo x avance (K2, 2026-08-18)
  datos_meta_agosto/ago_calendario.csv   : calendario de vencimientos de agosto (K3) -- saldo
                                            exacto dias 1-18, saldo vigente (18-ago) como proxy 19-31
  datos_meta_julio/curva_stock_seg.csv / curva_nuevos_seg.csv : curvas ya calibradas (reutilizadas)

Real a la fecha (1-18 ago) query K5 (avance_agosto_ad_hoc, ver mensaje de
sesion 2026-08-18): RECUP_STOCK rebaje_real=447,341.09 (2,683 creditos),
RECUP_NUEVOS rebaje_real=699,769.22 (4,686 creditos).

v2 (2026-08-21, a pedido del usuario, junto con el refresco de meta_agosto_
capital_asegurado.py): corte movido a 20-ago -- no se espera al cierre de
agosto. Mismo patron que cierre_julio.sql J3/J4 (rebaje real, sin el dedup
de bug 11 -- tarea 6 de PENDIENTES.md, pendiente para el motor oficial,
fuera de alcance de este refresco puntual), anclado a julio->agosto:
  RECUP_STOCK  rebaje_real=473,452.25 (2,682 creditos)
  RECUP_NUEVOS rebaje_real=859,026.81 (4,954 creditos)
"""
import csv
from datetime import date, timedelta

DIR_AGO = "datos_meta_agosto"
DIR_CURVAS = "datos_meta_julio"

stock_agosto = {}
with open(f"{DIR_AGO}/stock_agosto_seg.csv") as f:
    for row in csv.DictReader(f):
        stock_agosto[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_stock = {}
with open(f"{DIR_CURVAS}/curva_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_recupero_acum"])

curva_nuevos = {}
with open(f"{DIR_CURVAS}/curva_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_nuevos.setdefault(row["avance_band"], {})[int(row["dia_desde_entrada"])] = float(row["pct_recupero_acum"])

calendario_agosto = {}
with open(f"{DIR_AGO}/ago_calendario.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_en_riesgo"]
        calendario_agosto.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

def lookup(curva, d):
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

P_NO_PAGA_DIA0 = 47966 / 358580  # 13.38%, misma tasa que el resto del proyecto
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

INICIO = date(2026, 8, 1)
HOY = date(2026, 8, 20)
N_DIAS = 31
saldo_stock_inicial = sum(stock_agosto.values())

REAL_STOCK_A_HOY = 473452.25
REAL_NUEVOS_A_HOY = 859026.81

filas = []
for d in range(1, N_DIAS + 1):
    fecha = INICIO + timedelta(days=d - 1)

    proy_stock = sum(
        stock_agosto.get((t, a), 0.0) * lookup(curva_stock.get((t, a), {}), d) / 100.0
        for t in TRAMOS for a in AVANCES
    )
    proy_nuevos = 0.0
    for dd in range(1, d + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        riesgo_por_avance = calendario_agosto.get(fecha_venc, {})
        dias_desde_entrada = d - dd
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in riesgo_por_avance.items():
            pct = lookup(curva_nuevos.get(avance, {}), dias_desde_entrada)
            proy_nuevos += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0

    filas.append({
        "dia": d, "fecha": fecha.isoformat(),
        "proy_stock": proy_stock, "proy_nuevos": proy_nuevos, "proy_total": proy_stock + proy_nuevos,
    })

if __name__ == "__main__":
    print(f"Stock al 1 de agosto (cierre real de julio): S/ {saldo_stock_inicial:,.0f}\n")
    print(f"{'dia':>3} {'fecha':>11} | {'proy_total':>11}")
    for r in filas:
        marca = " <- hoy" if r["fecha"] == HOY.isoformat() else ""
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['proy_total']:>11,.0f}{marca}")

    hoy_row = next(r for r in filas if r["fecha"] == HOY.isoformat())
    fin_row = filas[-1]
    real_total_hoy = REAL_STOCK_A_HOY + REAL_NUEVOS_A_HOY
    print(f"\n=== RESUMEN AL {HOY.isoformat()} -- RECUPERO OFICIAL, AGOSTO 2026 ===")
    print(f"Meta total de agosto (proyectada al cierre):     S/ {fin_row['proy_total']:,.0f}")
    print(f"  stock: S/ {fin_row['proy_stock']:,.0f}  |  nuevos: S/ {fin_row['proy_nuevos']:,.0f}")
    print(f"Ya recuperado real (1-{HOY.day} ago):                    S/ {real_total_hoy:,.0f}")
    print(f"  stock: S/ {REAL_STOCK_A_HOY:,.0f}  |  nuevos: S/ {REAL_NUEVOS_A_HOY:,.0f}")
    print(f"Meta proyectada acumulada al mismo día (día {HOY.day}):  S/ {hoy_row['proy_total']:,.0f}")
    avance_pct = 100 * real_total_hoy / fin_row['proy_total']
    print(f"Avance real vs meta total del mes: {avance_pct:.1f}%")
    err_hoy = real_total_hoy - hoy_row['proy_total']
    print(f"Real vs. proyectado AL MISMO DIA ({HOY.day}): {100*err_hoy/hoy_row['proy_total']:+.1f}%")
    print(f"\n>>> LO QUE RESTA DEL MES (día {HOY.day+1} al 31): S/ {fin_row['proy_total'] - real_total_hoy:,.0f} <<<")

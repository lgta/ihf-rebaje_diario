"""
Backtest del enfoque alfa ("capital asegurado") sobre mayo 2026 (mes real y
cerrado) -- extension del backtest a un tercer mes cerrado (tarea 9 de
PENDIENTES.md, ejecutado 2026-08-22 a pedido del usuario). Mismo patron
exacto que backtest_capital_asegurado_junio.py v4 (bug 12 + capa fantasma
con tasa P_FANTASMA=8.5524% y fix de frontera de mes, bug 14) -- ningun
cambio de metodologia, solo un mes adicional de evidencia.

OJO -- las curvas usadas aca (curva_asegurado_stock_seg.csv/curva_asegurado_
nuevos_seg.csv) siguen siendo las de PRODUCCION actual, calibradas sobre
periodo_meta '202504'-'202606' -- eso INCLUYE mayo 2026 en su propia
calibracion (no es estrictamente fuera de muestra para este mes especifico).
Ver tarea 10 de PENDIENTES.md / BUGS.md -- pendiente aparte, no resuelto en
este script.

Insumos (queries nuevas, ver analisis_volumen_efectividad_agosto.sql-style
patron en bt_mayo_*.sql del scratchpad de esta sesion, no copiadas al repo
por ahora -- ver nota en BUGS.md si hace falta reconstruir):
  datos_backtest_mayo/bt_stock_mayo_aseg.csv   : stock (cierre abril UNION dia1 mayo)
  datos_backtest_mayo/bt_calendario_mayo.csv   : calendario real de mayo, excluye stock
  datos_capital_asegurado/curva_asegurado_stock_seg.csv / curva_asegurado_nuevos_seg.csv
  datos_backtest_mayo/bt_real_aseg_stock.csv   : capital real activado por dia, stock
  datos_backtest_mayo/bt_real_aseg_nuevos.csv  : capital real activado por dia, nuevos
  datos_backtest_mayo/bt_real_fantasma_nuevos_mayo.csv : capital real activado por dia, fantasma
"""
import csv
from datetime import date, timedelta

DIR_BT = "datos_backtest_mayo"
DIR_ASEG = "datos_capital_asegurado"

stock_mayo = {}
with open(f"{DIR_BT}/bt_stock_mayo_aseg.csv") as f:
    for row in csv.DictReader(f):
        stock_mayo[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_aseg_stock = {}
with open(f"{DIR_ASEG}/curva_asegurado_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_aseg_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

curva_aseg_nuevos = {}
with open(f"{DIR_ASEG}/curva_asegurado_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_aseg_nuevos.setdefault(row["avance_band"], {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

calendario_mayo = {}
with open(f"{DIR_BT}/bt_calendario_mayo.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_en_riesgo"]
        calendario_mayo.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

# Calendario SEPARADO para fantasma, frontier-adjusted (bug 14): incluye la
# cuota vencida 30-abr (fecha_pago=1-may, keyed por fechavencimiento para
# que el loop diario la pueda indexar igual que dd), excluye 31-may
# (fecha_pago=1-jun, pertenece a junio). Sin esto, proy_fantasma queda
# ~1M por debajo del real -- error encontrado y corregido 2026-08-22.
calendario_fantasma_mayo = {}
with open(f"{DIR_BT}/bt_calendario_fantasma_mayo.csv") as f:
    for row in csv.DictReader(f):
        calendario_fantasma_mayo[row["fechavencimiento"]] = float(row["saldo_en_riesgo"])

real_aseg_stock_dia = {}
with open(f"{DIR_BT}/bt_real_aseg_stock.csv") as f:
    for row in csv.DictReader(f):
        real_aseg_stock_dia[row["fechaproceso"]] = float(row["saldo_activado_dia"])

real_aseg_nuevos_dia = {}
with open(f"{DIR_BT}/bt_real_aseg_nuevos.csv") as f:
    for row in csv.DictReader(f):
        real_aseg_nuevos_dia[row["fechaproceso"]] = float(row["saldo_activado_dia"])

real_fantasma_dia = {}
with open(f"{DIR_BT}/bt_real_fantasma_nuevos_mayo.csv") as f:
    for row in csv.DictReader(f):
        real_fantasma_dia[row["fechaproceso"]] = float(row["saldo_activado_dia"])

def lookup(curva, d):
    if d <= 0:
        return 0.0
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

P_NO_PAGA_DIA0 = 47966 / 358580  # 13.38%
P_FANTASMA = 29625 / 346396      # 8.5524%
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

INICIO = date(2026, 5, 1)
N_DIAS = 31
saldo_stock_inicial = sum(stock_mayo.values())

filas = []
real_stock_acum = 0.0
real_nuevos_acum = 0.0
real_fantasma_acum = 0.0
for d in range(1, N_DIAS + 1):
    fecha = INICIO + timedelta(days=d - 1)
    fecha_s = fecha.strftime("%Y%m%d")
    fecha_iso = fecha.isoformat()

    proy_stock = sum(
        stock_mayo.get((t, a), 0.0) * lookup(curva_aseg_stock.get((t, a), {}), d) / 100.0
        for t in TRAMOS for a in AVANCES
    )
    proy_nuevos = 0.0
    proy_fantasma = 0.0
    for dd in range(1, d + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        riesgo_por_avance = calendario_mayo.get(fecha_venc, {})
        dias_desde_entrada = d - dd
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in riesgo_por_avance.items():
            pct = lookup(curva_aseg_nuevos.get(avance, {}), dias_desde_entrada)
            proy_nuevos += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0
    # fantasma: calendario propio (frontier-adjusted), dd puede incluir el
    # dia ANTERIOR al inicio del mes (30-abr) -- por eso este loop es
    # independiente del de arriba, con su propio rango dd.
    for dd in range(0, d + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        saldo_riesgo_fant = calendario_fantasma_mayo.get(fecha_venc, 0.0)
        dias_desde_entrada = d - dd
        if dias_desde_entrada < 1:
            continue
        proy_fantasma += saldo_riesgo_fant * P_FANTASMA

    real_stock_acum += real_aseg_stock_dia.get(fecha_s, 0.0)
    real_nuevos_acum += real_aseg_nuevos_dia.get(fecha_s, 0.0)
    real_fantasma_acum += real_fantasma_dia.get(fecha_s, 0.0)

    filas.append({
        "dia": d, "fecha": fecha_iso,
        "proy_stock": proy_stock, "proy_nuevos": proy_nuevos, "proy_fantasma": proy_fantasma,
        "proy_total": proy_stock + proy_nuevos + proy_fantasma,
        "real_stock": real_stock_acum, "real_nuevos": real_nuevos_acum, "real_fantasma": real_fantasma_acum,
        "real_total": real_stock_acum + real_nuevos_acum + real_fantasma_acum,
    })

if __name__ == "__main__":
    print(f"Stock al cierre de abril (dia 1 de mayo): S/ {saldo_stock_inicial:,.0f}\n")
    print(f"{'dia':>3} {'fecha':>11} | {'proy_stock':>10} {'proy_nuevos':>11} {'proy_fant':>9} {'PROY_total':>11} | {'real_stock':>10} {'real_nuevos':>11} {'real_fant':>9} {'REAL_total':>11} | {'error':>8}")
    for r in filas:
        err = r["proy_total"] - r["real_total"]
        errp = 100 * err / r["real_total"] if r["real_total"] else 0
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['proy_stock']:>10,.0f} {r['proy_nuevos']:>11,.0f} {r['proy_fantasma']:>9,.0f} {r['proy_total']:>11,.0f} | {r['real_stock']:>10,.0f} {r['real_nuevos']:>11,.0f} {r['real_fantasma']:>9,.0f} {r['real_total']:>11,.0f} | {errp:>+7.1f}%")

    f = filas[-1]
    print(f"\n=== CIERRE DE MAYO (dia 31) -- ENFOQUE ALFA: CAPITAL ASEGURADO (con capa fantasma) ===")
    print(f"Proyectado: S/ {f['proy_total']:,.0f}  (stock S/ {f['proy_stock']:,.0f} + nuevos S/ {f['proy_nuevos']:,.0f} + fantasma S/ {f['proy_fantasma']:,.0f})")
    print(f"Real:       S/ {f['real_total']:,.0f}  (stock S/ {f['real_stock']:,.0f} + nuevos S/ {f['real_nuevos']:,.0f} + fantasma S/ {f['real_fantasma']:,.0f})")
    err = f["proy_total"] - f["real_total"]
    err_stock = f["proy_stock"] - f["real_stock"]
    err_nuevos = f["proy_nuevos"] - f["real_nuevos"]
    err_fantasma = f["proy_fantasma"] - f["real_fantasma"]
    print(f"Error total:     S/ {err:+,.0f}  ({100*err/f['real_total']:+.1f}%)")
    print(f"Error stock:     S/ {err_stock:+,.0f}  ({100*err_stock/f['real_stock']:+.1f}%)")
    print(f"Error nuevos:    S/ {err_nuevos:+,.0f}  ({100*err_nuevos/f['real_nuevos']:+.1f}%)")
    print(f"Error fantasma:  S/ {err_fantasma:+,.0f}  ({100*err_fantasma/f['real_fantasma']:+.1f}%)")

"""
Backtest del enfoque alfa ("capital asegurado") sobre junio 2026 (mes real y
cerrado) -- mismo mes que el backtest oficial de recupero (backtest_junio.py),
para poder comparar manzanas con manzanas. Ver enfoque_capital_asegurado.md,
seccion "Pendientes", punto 1.

v2 (2026-07-14, bug 12): definicion de antiguos/nuevos corregida -- un
credito que entra en mora (dayslate 0->1) el DIA 1 de un mes viene siempre
de una cuota vencida el ULTIMO DIA DEL MES ANTERIOR, es antiguo, no nuevo.
YA NO reutiliza bt_stock_junio.csv (fase3_backtest.sql 3G-1, compartido con
el backtest oficial de recupero) para la poblacion de stock -- ese archivo
ancla al cierre de mayo y no incluye a esos entrantes de dia 1. Usa en su
lugar bt_stock_junio_aseg.csv (stock de mayo UNION entrantes de dia 1, ver
enfoque_capital_asegurado_backtest.sql BT-ASEG-0). Resultado: -4.4% de error
total (antes -4.7%), ver BUGS.md bug 12.

v3 (2026-08-20, bug 14): capa "fantasma" agregada -- creditos que pagan una
cuota EXACTAMENTE 1 dia tarde y que dayslate NUNCA registra en mora (punto
ciego de bug 9, cuantificado en ~27% de la poblacion real de mora 1-30 al
reconciliar contra una vista externa, ver reconciliacion_vw_seguimiento_
temprana.md). Capa INDEPENDIENTE de 13.38%/la curva de nuevos (evita repetir
bug 10) -- se activa 100% el dia siguiente al vencimiento, sin curva propia.
Resultado: error total -4.4% -> +0.7% (segunda validacion en julio 2026,
mes cerrado independiente: -4.31% -> +0.12%, ver reconciliacion_vw_
seguimiento_temprana.md paso 2/3 e investigacion_capa_fantasma.sql).

Insumos:
  datos_backtest_junio/bt_stock_junio_aseg.csv : stock (BT-ASEG-0, solo de este enfoque)
  datos_backtest_junio/bt_calendario_junio.csv : calendario real de junio (fase3_backtest.sql 3G-2,
                                                  compartido con recupero -- ya scopeado a vencimientos
                                                  DENTRO de junio, no tenia el bug)
  datos_capital_asegurado/curva_asegurado_stock_seg.csv  : curva ya calibrada (enfoque_capital_asegurado.sql Q1)
  datos_capital_asegurado/curva_asegurado_nuevos_seg.csv : curva ya calibrada (enfoque_capital_asegurado.sql Q2)
  datos_backtest_junio/bt_real_aseg_stock.csv  : capital real activado por dia, stock (BT-ASEG-1)
  datos_backtest_junio/bt_real_aseg_nuevos.csv : capital real activado por dia, nuevos (BT-ASEG-2)
  datos_backtest_junio/bt_real_fantasma_nuevos_junio.csv : capital real activado por dia, fantasma (BT-ASEG-3)

Misma tasa P(no paga a tiempo)=13.38% que el modelo oficial -- sigue siendo
consistente porque mide si la entrada ocurre (a nivel credito), no en que
dia del mes cae -- el bug 12 solo cambia el bucketing (stock vs nuevos) de
entradas ya ocurridas, no cuenta ni deja de contar ninguna. Ver
feedback-tasa-curva-consistente en memoria y DECISIONES.md. P_FANTASMA es
una tasa NUEVA e independiente (8.4534%, ver enfoque_capital_asegurado.sql
Q3) -- no reemplaza ni se mezcla con 13.38%.
"""
import csv
from datetime import date, timedelta

DIR_BT = "datos_backtest_junio"
DIR_ASEG = "datos_capital_asegurado"

stock_junio = {}
with open(f"{DIR_BT}/bt_stock_junio_aseg.csv") as f:
    for row in csv.DictReader(f):
        stock_junio[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_aseg_stock = {}
with open(f"{DIR_ASEG}/curva_asegurado_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_aseg_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

curva_aseg_nuevos = {}
with open(f"{DIR_ASEG}/curva_asegurado_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_aseg_nuevos.setdefault(row["avance_band"], {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

calendario_junio = {}
with open(f"{DIR_BT}/bt_calendario_junio.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_en_riesgo"]
        calendario_junio.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

real_aseg_stock_dia = {}
with open(f"{DIR_BT}/bt_real_aseg_stock.csv") as f:
    for row in csv.DictReader(f):
        real_aseg_stock_dia[row["fechaproceso"]] = float(row["saldo_activado_dia"])

real_aseg_nuevos_dia = {}
with open(f"{DIR_BT}/bt_real_aseg_nuevos.csv") as f:
    for row in csv.DictReader(f):
        real_aseg_nuevos_dia[row["fechaproceso"]] = float(row["saldo_activado_dia"])

real_fantasma_dia = {}
with open(f"{DIR_BT}/bt_real_fantasma_nuevos_junio.csv") as f:
    for row in csv.DictReader(f):
        real_fantasma_dia[row["fechaproceso"]] = float(row["saldo_activado_dia"])

def lookup(curva, d):
    if d <= 0:
        return 0.0
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0

# Tasa fuera de muestra (ago-2025 a may-2026, SIN junio) -- misma que el modelo
# oficial (fase3_backtest.sql 3H) y que meta_julio_capital_asegurado.py.
P_NO_PAGA_DIA0 = 47966 / 358580  # 13.38%
P_FANTASMA = 29845 / 353054      # 8.4534% -- capa fantasma, ver enfoque_capital_asegurado.sql Q3
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

INICIO = date(2026, 6, 1)
N_DIAS = 30
saldo_stock_inicial = sum(stock_junio.values())

filas = []
real_stock_acum = 0.0
real_nuevos_acum = 0.0
real_fantasma_acum = 0.0
for d in range(1, N_DIAS + 1):
    fecha = INICIO + timedelta(days=d - 1)
    fecha_s = fecha.strftime("%Y%m%d")
    fecha_iso = fecha.isoformat()

    proy_stock = sum(
        stock_junio.get((t, a), 0.0) * lookup(curva_aseg_stock.get((t, a), {}), d) / 100.0
        for t in TRAMOS for a in AVANCES
    )
    proy_nuevos = 0.0
    proy_fantasma = 0.0
    for dd in range(1, d + 1):
        fecha_venc = (INICIO + timedelta(days=dd - 1)).isoformat()
        riesgo_por_avance = calendario_junio.get(fecha_venc, {})
        dias_desde_entrada = d - dd
        if dias_desde_entrada < 1:
            continue
        for avance, saldo_riesgo in riesgo_por_avance.items():
            pct = lookup(curva_aseg_nuevos.get(avance, {}), dias_desde_entrada)
            proy_nuevos += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0
        # fantasma: 100% activado el dia siguiente al vencimiento, sin curva (ya esta pagado cuando se detecta)
        proy_fantasma += sum(riesgo_por_avance.values()) * P_FANTASMA

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
    print(f"Stock al cierre de mayo (dia 1 de junio): S/ {saldo_stock_inicial:,.0f}\n")
    print(f"{'dia':>3} {'fecha':>11} | {'proy_stock':>10} {'proy_nuevos':>11} {'proy_fant':>9} {'PROY_total':>11} | {'real_stock':>10} {'real_nuevos':>11} {'real_fant':>9} {'REAL_total':>11} | {'error':>8}")
    for r in filas:
        err = r["proy_total"] - r["real_total"]
        errp = 100 * err / r["real_total"] if r["real_total"] else 0
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['proy_stock']:>10,.0f} {r['proy_nuevos']:>11,.0f} {r['proy_fantasma']:>9,.0f} {r['proy_total']:>11,.0f} | {r['real_stock']:>10,.0f} {r['real_nuevos']:>11,.0f} {r['real_fantasma']:>9,.0f} {r['real_total']:>11,.0f} | {errp:>+7.1f}%")

    f = filas[-1]
    print(f"\n=== CIERRE DE JUNIO (dia 30) -- ENFOQUE ALFA: CAPITAL ASEGURADO (con capa fantasma) ===")
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

"""
Combina las curvas y poblaciones de Fase 1/2/3 (ya agregadas via Athena,
exportadas a CSV) en la trayectoria diaria de la meta de recupero,
segmentada por tramo x avance de amortizacion.

Formula:
  Meta_cum(d) = Sum(tramo,avance) saldo_stock(tramo,avance) x curva_stock(tramo,avance,d)
              + Sum(D<=d) Sum(avance) saldo_riesgo(D,avance) x (1-C_ops(0)) x curva_nuevos(avance, d-D)

Insumos esperados (CSV en el mismo directorio, exportados de Athena via fase1_stock.sql / fase2_nuevos.sql / fase3_meta.sql):
  stock_hoy_seg.csv     : tramo, avance_band, creditos, saldo_total   (bloque 3C)
  curva_stock_seg.csv   : tramo, avance_band, dia, pct_recupero_acum  (bloque 3D)
  curva_nuevos_seg.csv  : avance_band, dia_desde_entrada, pct_recupero_acum (bloque 3E)
  calendario_seg.csv    : fechavencimiento, avance_band, creditos_vencen, saldo_capital_en_riesgo (bloque 3B)

CAVEATS (ver fase3_meta.sql seccion 3F):
  - Esta version usa el stock del dia de la corrida como "dia 1" (demo /
    proyeccion rodante). Para la meta oficial de un mes calendario, el
    stock debe anclarse al cierre del mes anterior.
  - El calendario usado aqui es prospectivo (solo vencimientos futuros).
    Para reconstruir/backtestear un mes ya cerrado, traer las cuotas de
    ese mes por fechavencimiento sin filtrar por installmentstate.
"""
import csv
from datetime import date, timedelta

DIR = "."

stock_hoy = {}
with open(f"{DIR}/stock_hoy_seg.csv") as f:
    for row in csv.DictReader(f):
        stock_hoy[(row["tramo"], row["avance_band"])] = float(row["saldo_total"])

curva_stock = {}
with open(f"{DIR}/curva_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_recupero_acum"])

def lookup_stock(tramo, avance, d):
    c = curva_stock.get((tramo, avance))
    if not c:
        return 0.0
    if d in c:
        return c[d]
    keys = [k for k in c if k <= d]
    return c[max(keys)] if keys else 0.0

curva_nuevos = {}
with open(f"{DIR}/curva_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_nuevos.setdefault(row["avance_band"], {})[int(row["dia_desde_entrada"])] = float(row["pct_recupero_acum"])

def lookup_nuevos(avance, dd):
    c = curva_nuevos.get(avance)
    if not c or dd < 1:
        return 0.0
    if dd in c:
        return c[dd]
    keys = [k for k in c if k <= dd]
    return c[max(keys)] if keys else 0.0

calendario = {}
with open(f"{DIR}/calendario_seg.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_capital_en_riesgo"]
        calendario.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

# CORREGIDO tras el backtest de junio-2026 (ver fase3_backtest.sql bloque 3H):
# 1-0.726 (27.4%, de la curva de # operaciones a nivel CUOTA) NO es la tasa real
# de entrada a mora a nivel CREDITO -- usarla producia un error de +79% en el
# backtest. La tasa correcta, medida directamente (dayslate 0->1) y fuera de
# muestra en 10 meses (ago-2025 a may-2026), es 13.38% -- con esta el backtest
# de junio dio +5.4% de error. Ver plan_analisis.md "Backtest sobre junio 2026".
P_NO_PAGA_DIA0 = 47966 / 358580  # 13.38%
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]

HOY = date(2026, 7, 8)   # ajustar: dia de la corrida / cierre del mes anterior
N_DIAS = 31

def construir_trayectoria():
    filas = []
    for d in range(1, N_DIAS + 1):
        stock_cum = sum(
            stock_hoy.get((t, a), 0.0) * lookup_stock(t, a, d) / 100.0
            for t in TRAMOS for a in AVANCES
        )
        nuevos_cum = 0.0
        for dd in range(1, d + 1):
            fecha_venc = (HOY + timedelta(days=dd)).isoformat()
            riesgo_por_avance = calendario.get(fecha_venc, {})
            dias_desde_entrada = d - dd
            if dias_desde_entrada < 1:
                continue
            for avance, saldo_riesgo in riesgo_por_avance.items():
                pct = lookup_nuevos(avance, dias_desde_entrada)
                nuevos_cum += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0
        meta_cum = stock_cum + nuevos_cum
        fecha = HOY + timedelta(days=d)
        filas.append((d, fecha.isoformat(), stock_cum, nuevos_cum, meta_cum))
    return filas

if __name__ == "__main__":
    filas = construir_trayectoria()
    print(f"{'dia':>3} {'fecha':>11} {'stock_cum':>12} {'nuevos_cum':>12} {'META_cum':>12}")
    for d, fecha, s, n, m in filas:
        print(f"{d:>3} {fecha:>11} {s:>12,.0f} {n:>12,.0f} {m:>12,.0f}")
    print(f"\nMeta acumulada al dia {N_DIAS}: S/ {filas[-1][4]:,.0f}")
    print(f"  stock:  S/ {filas[-1][2]:,.0f} ({100*filas[-1][2]/filas[-1][4]:.1f}%)")
    print(f"  nuevos: S/ {filas[-1][3]:,.0f} ({100*filas[-1][3]/filas[-1][4]:.1f}%)")

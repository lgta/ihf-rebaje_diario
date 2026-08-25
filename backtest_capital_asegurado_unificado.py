"""
Backtest del Enfoque alfa ("capital asegurado") con el MOTOR UNIFICADO
(`dias_atraso_cuota`, sin capa fantasma) sobre los 4 meses cerrados:
abril, mayo, junio y julio 2026 -- los 4 en una sola corrida.

Reemplaza a backtest_capital_asegurado_{abril,mayo,junio}.py y
backtest_capital_asegurado_julio_diario.py, que quedan como referencia
historica de la arquitectura anterior (stock + nuevos + fantasma, dayslate).

Ver motor_unificado.py para QUE cambia y POR QUE, y BUGS.md bug 16 (Fase 4)
para el detalle completo, incluida la razon por la que se adopta un modelo
con ~1pp MAS de error: el parche plano de la capa fantasma enmascaraba el
sesgo de "nuevos" por ser sistematicamente generoso.

Insumos (todos de tarea17_fase4_*.sql, en datos_tarea17_fase4/):
  curva_stock.csv   Q-C  curva de stock, tramo x avance x dia del mes
  curva_nuevos.csv  Q-B  curva de nuevos, avance x dias desde entrada (DESDE EL DIA 0)
  stock_pob.csv     Q-E  poblacion de stock por mes, tramo x avance
  calendario.csv    Q-D  calendario unificado por mes, dia_entrada x avance
  real_stock.csv    Q-F1 capital real activado por dia, componente stock
  real_nuevos.csv   Q-F2 capital real activado por dia, componente nuevos

Las curvas de produccion viven en datos_capital_asegurado/curva_unificada_*.csv
(copia de las anteriores); los insumos por mes se quedan en datos_tarea17_fase4/.

Salida: tabla por mes en consola + series diarias en
datos_backtest_unificado/serie_diaria_{periodo}.csv (las consume el artifact).
"""
import csv
import collections
import os

from motor_unificado import (P_ENTRADA, cargar_curva_stock, cargar_curva_nuevos,
                             proyectar, acumular_real)

DIR_F4 = "datos_tarea17_fase4"
DIR_OUT = "datos_backtest_unificado"

MESES = [("202604", 30, "Abril 2026"), ("202605", 31, "Mayo 2026"),
         ("202606", 30, "Junio 2026"), ("202607", 31, "Julio 2026")]

# Numeros de la arquitectura anterior (SEGUIMIENTO.md antes de Fase 4), para
# la columna de comparacion. Abril lleva el numero YA CORREGIDO por bug 20
# (-13.4%, calendario de fantasma sin la exclusion de entradas_reales) -- el
# -19.0% que figuraba antes tenia un denominador inconsistente con la tasa.
PROD_ANTERIOR = {
    "202604": (11502103, 13287964),   # corregido por bug 20
    "202605": (13741464, 14697936),
    "202606": (13844523, 13587829),
    "202607": (16639656, 17154500),
}

curva_stock = cargar_curva_stock(f"{DIR_F4}/curva_stock.csv")
curva_nuevos = cargar_curva_nuevos(f"{DIR_F4}/curva_nuevos.csv")

stock_pob = collections.defaultdict(dict)
with open(f"{DIR_F4}/stock_pob.csv") as f:
    for r in csv.DictReader(f):
        stock_pob[r["periodo_meta"]][(r["tramo"], r["avance_band"])] = float(r["saldo_total"])

calendario = collections.defaultdict(lambda: collections.defaultdict(dict))
with open(f"{DIR_F4}/calendario.csv") as f:
    for r in csv.DictReader(f):
        calendario[r["periodo"]][int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo_en_riesgo"])

real_stock = collections.defaultdict(dict)
with open(f"{DIR_F4}/real_stock.csv") as f:
    for r in csv.DictReader(f):
        real_stock[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])

real_nuevos = collections.defaultdict(dict)
with open(f"{DIR_F4}/real_nuevos.csv") as f:
    for r in csv.DictReader(f):
        real_nuevos[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])


def correr(periodo, n_dias):
    proy = proyectar(stock_pob[periodo], calendario[periodo], curva_stock, curva_nuevos, n_dias)
    rs = acumular_real(real_stock[periodo], n_dias)
    rn = acumular_real(real_nuevos[periodo], n_dias)
    for i, fila in enumerate(proy):
        fila["real_stock"] = rs[i]
        fila["real_nuevos"] = rn[i]
        fila["real_total"] = rs[i] + rn[i]
    return proy


if __name__ == "__main__":
    os.makedirs(DIR_OUT, exist_ok=True)
    print("=" * 104)
    print("BACKTEST -- MOTOR UNIFICADO (dias_atraso_cuota, sin capa fantasma)")
    print("=" * 104)
    print(f"P_ENTRADA = {100*P_ENTRADA:.4f}%   (arquitectura anterior: 13.38% + 8.6163% = 21.9963%)\n")

    hdr = (f"{'Mes':<12} | {'Proyectado':>12} {'Real':>12} {'error':>8} | "
           f"{'err stock':>10} {'err nuevos':>11} | {'error anterior':>14}")
    print(hdr)
    print("-" * len(hdr))
    errores = []
    for periodo, n, nombre in MESES:
        filas = correr(periodo, n)
        f = filas[-1]
        err = 100 * (f["proy_total"] - f["real_total"]) / f["real_total"]
        es = 100 * (f["proy_stock"] - f["real_stock"]) / f["real_stock"]
        en = 100 * (f["proy_nuevos"] - f["real_nuevos"]) / f["real_nuevos"]
        pp, pr = PROD_ANTERIOR[periodo]
        errores.append(abs(err))
        print(f"{nombre:<12} | {f['proy_total']:>12,.0f} {f['real_total']:>12,.0f} {err:>+7.1f}% | "
              f"{es:>+9.1f}% {en:>+10.1f}% | {100*(pp-pr)/pr:>+13.1f}%")

        with open(f"{DIR_OUT}/serie_diaria_{periodo}.csv", "w", newline="") as out:
            w = csv.DictWriter(out, fieldnames=["dia", "proy_stock", "proy_nuevos",
                                                "proy_total", "real_stock", "real_nuevos",
                                                "real_total"])
            w.writeheader()
            for fila in filas:
                w.writerow({k: (round(v, 2) if k != "dia" else v) for k, v in fila.items()})

    print()
    print(f"Magnitud media de error: {sum(errores)/len(errores):.2f}%"
          f"   (arquitectura anterior, con bug 20 corregido: 6.20%)")
    print()
    print("El error es ~1pp peor A PROPOSITO -- ver motor_unificado.py y BUGS.md bug 16:")
    print("el parche plano enmascaraba el sesgo de 'nuevos' por ser generoso. El sesgo que")
    print("queda tiene signo constante en los 4 meses: es una senal de negocio a explicar")
    print("(volumen/mix/gestion), no un defecto a ajustar.")
    print()
    print(f"Series diarias escritas en {DIR_OUT}/")

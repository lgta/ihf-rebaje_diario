"""
Meta de RECUPERO OFICIAL (rebaje en soles) de SEPTIEMBRE 2026, anclada al
cierre REAL de agosto.

PRIMERA meta de este enfoque con el motor migrado a `dias_atraso_cuota`
(tarea 18e, adoptada 2026-08-26). La meta de agosto quedo con el motor viejo
(`dayslate` / P_NO_PAGA_DIA0 = 13.38%) a proposito -- no se cambia el motor de
un mes EN CURSO a mitad de mes. Agosto cerro el 31-ago, asi que septiembre es
la primera que puede nacer con el motor nuevo, como estaba planificado.

Que cambia respecto de `meta_agosto.py`:
  - tasa: 13.38% por conteo (dayslate)  ->  ~25% por SOLES, rodante
  - curvas: las de `datos_meta_julio/` (fijas, dayslate, sin dow ni factor)
            ->  curvas de rebaje calibradas con `dias_atraso_cuota`, con dia
                de semana del vencimiento y factor por dia del mes
  - calendario: por dia de ENTRADA (vencimiento+1), no por vencimiento
  - el calendario ya no arrastra la limitacion de `ago_calendario.csv` (saldo
    del 18-ago repetido como proxy para los dias 19-31): el saldo de TODAS las
    cuotas esta anclado al cierre de agosto, convencion unica y reproducible.

INSUMOS (todos de `datos_tarea19/`, ver tarea19_*.sql):
  meta_septiembre_insumos.csv     stock al cierre de agosto + calendario de sep
                                  -- EL MISMO archivo que usa el Enfoque alfa:
                                  el universo de entrada es identico en los dos
                                  motores, lo que difiere es la CURVA (rebaje
                                  vs. activacion), no quien entra.
  curva_sep_nuevos_rebaje.csv     curva de rebaje de nuevos, [202508, 202607]
  factor_dia_mes_sep_rebaje.csv   factor de quincena/fin de mes (18f)
  curva_sep_stock_rebaje.csv      curva de rebaje de stock, ventana FIJA
  factor_dia_mes_sep_stock_rebaje.csv   factor de cierre real (18g)
  tasa_soles.csv                  tasa de entrada por soles, mensual

VENTANAS: nuevos [202508, 202607] (12 meses rodantes, ultimo mes completamente
observado al 1-sep); stock 202504-202606 FIJA -- rodarla ya se probo en 18c/18g
y empeora las metricas diarias. Es lo que sigue debiendo tarea 18c.

Backtest de referencia de este motor (7 meses, `backtest_tarea18e_recupero_
oficial_v2.py`): magnitud media de error 7.83%, correlacion diaria 0.837.
"""
import collections
import csv

from motor_unificado import (cargar_curva_stock, cargar_curva_nuevos,
                             cargar_factor_dia_mes, cargar_factor_dia_mes_stock,
                             segmentar_calendario, proyectar)

DIR_19 = "datos_tarea19"
N_DIAS = 30
VENTANA = ("202508", "202607")


def leer(p):
    with open(p) as f:
        return list(csv.DictReader(f))


def tasa_soles_rodante():
    e = n = 0.0
    for r in leer(f"{DIR_19}/tasa_soles.csv"):
        if VENTANA[0] <= r["periodo"] <= VENTANA[1]:
            e += float(r["elegibles_soles"])
            n += float(r["entran_soles"])
    return n / e


P_ENTRADA_SOLES = tasa_soles_rodante()

curva_stock = cargar_curva_stock(f"{DIR_19}/curva_sep_stock_rebaje.csv")
f_dm_stock = cargar_factor_dia_mes_stock(f"{DIR_19}/factor_dia_mes_sep_stock_rebaje.csv")
curva_nuevos = cargar_curva_nuevos(f"{DIR_19}/curva_sep_nuevos_rebaje.csv")
factor_dia_mes = cargar_factor_dia_mes(f"{DIR_19}/factor_dia_mes_sep_rebaje.csv")

stock_sep = {}
calendario_sep = collections.defaultdict(dict)
for r in leer(f"{DIR_19}/meta_septiembre_insumos.csv"):
    if r["tipo"] == "stock":
        stock_sep[(r["tramo"], r["avance_band"])] = float(r["saldo"])
    else:
        calendario_sep[int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo"])

filas = proyectar(stock_sep, segmentar_calendario(calendario_sep, "202609"),
                  curva_stock, curva_nuevos, N_DIAS, p_entrada=P_ENTRADA_SOLES,
                  f_dm=factor_dia_mes, f_dm_stock=f_dm_stock)
for i, fila in enumerate(filas):
    fila["fecha"] = f"2026-09-{i+1:02d}"

if __name__ == "__main__":
    print("=" * 78)
    print("META DE SEPTIEMBRE 2026 -- RECUPERO OFICIAL (rebaje), motor 18e v2")
    print("=" * 78)
    print(f"Stock al 1-sep (dias_atraso_cuota 1-30 al cierre de agosto): S/ {sum(stock_sep.values()):>12,.0f}")
    print(f"Calendario de septiembre (por dia de entrada, excl. stock):  S/ "
          f"{sum(sum(v.values()) for v in calendario_sep.values()):>12,.0f}")
    print(f"Tasa de entrada por SOLES, rodante [{VENTANA[0]}, {VENTANA[1]}]: {100*P_ENTRADA_SOLES:.4f}%")
    print("Factor por dia del mes (nuevos): " + "  ".join(
        f"{g}={factor_dia_mes.get(g, 1.0):.4f}" for g in ("quincena", "fin de mes", "resto")))
    print("Factor por dia del mes (stock):  " + "  ".join(
        f"{g}={f_dm_stock.get(g, 1.0):.4f}" for g in ("quincena", "cierre", "resto")))
    print()

    f = filas[-1]
    print("=== META DE SEPTIEMBRE 2026 -- RECUPERO OFICIAL ===")
    print(f"Meta total del mes:  S/ {f['proy_total']:,.0f}")
    print(f"  stock:             S/ {f['proy_stock']:,.0f}")
    print(f"  nuevos:            S/ {f['proy_nuevos']:,.0f}")
    print()
    print("Referencias de agosto (motor viejo, `dayslate` -- NO comparable en nivel):")
    print("  meta S/ 2,108,435   real S/ 2,178,078   error -3.20%")
    print("  el mismo agosto medido con dias_atraso_cuota: real S/ 3,174,012 (146%)")
    print(f"  septiembre vs. ese real de agosto: {100*(f['proy_total']/3174012-1):+.1f}%")
    print()
    print(f"{'dia':>3} {'fecha':>11} | {'proy_stock':>11} {'proy_nuevos':>12} | {'proy_total':>12}")
    for r in filas:
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['proy_stock']:>11,.0f} "
              f"{r['proy_nuevos']:>12,.0f} | {r['proy_total']:>12,.0f}")

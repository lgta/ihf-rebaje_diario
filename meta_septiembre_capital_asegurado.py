"""
Meta de capital asegurado de SEPTIEMBRE 2026 (Enfoque alfa), anclada al
cierre REAL de agosto.

MOTOR: unificado v3 (mismo que la meta de agosto) -- stock + nuevos, sin capa
fantasma, calibrado con `dias_atraso_cuota`. Lo unico que cambia respecto de
agosto son los INSUMOS (todos corridos un mes) y la ventana de calibracion:

  curvas de nuevos   [202508, 202607]  (12 meses rodantes, 1 mes adelante)
  curva de stock     202504-202606     FIJA, sin cambios (18g/18c)
  stock inicial      cierre de agosto (31-ago), dias_atraso_cuota 1-30
  calendario         entradas (vencimiento+1) dentro de septiembre, ACTIVE

VENTANA [202508, 202607] -- ultimo mes COMPLETAMENTE OBSERVADO al 1-sep. Una
cohorte necesita 31 dias de seguimiento: las entradas de julio recien
terminaron de observarse el 31-ago; las de agosto todavia no. Usar agosto
seria usar datos que la meta no puede tener (`CLAUDE.md`).

--------------------------------------------------------------------------
LA TASA DE ENTRADA CAMBIO DE DEFINICION -- este archivo calcula LAS DOS.
--------------------------------------------------------------------------
`P_ENTRADA = 21.9918%` se calibro CONTANDO creditos pero se aplica
multiplicando SALDO EN SOLES. 18b midio que esa mezcla explica ~78% de la
magnitud del sesgo de "nuevos"; Recupero Oficial ya lo corrigio en 18e. La
version consistente es la tasa por SOLES sobre la misma poblacion (verificado:
en creditos reproduce P_ENTRADA al 0.002pp).

Lo que midio el backtest de 8 meses (`backtest_tarea19_tasa_soles.py`):

  mes    conteo fijo   rodante soles
  ene       -11.1%          -0.5%
  feb       -19.1%         -10.3%
  mar       -14.0%          -3.3%
  abr       -11.4%          -0.9%
  may       -10.7%          +0.9%
  jun        -2.7%          +8.9%
  jul        -2.9%          +9.2%
  ago        -1.2%          +9.7%   <- agosto real, contrafactual
  media       9.14%          5.46%
  ult. 3      2.26%          9.27%

La correccion definicional arregla ene-may y SOBREESTIMA jun-ago. No es que
una tasa sea "mejor": las dos derivan +10pp a lo largo de los 8 meses, en
paralelo, porque el mecanismo real es otro -- la ACTIVACION REAL como % del
calendario viene cayendo (21.0% en ene-mar -> 18.5% en jun-ago, -0.46pp/mes,
r=-0.77) mientras la tasa de entrada por soles se mantiene plana (23-27%, sin
tendencia). La tasa por conteo, al ser ~14.5% mas baja, venia COMPENSANDO esa
caida por accidente -- el mismo patron de bug 18 y de la capa fantasma: un
numero mal definido que tapaba un sesgo real.

Acortar la ventana de calibracion NO sigue esa caida (probado: 6m empeora las
metricas diarias, 0.876 vs 0.886; 9m ~ 12m; jun/jul quedan en +8.5-9.3% con
cualquiera). El protocolo de 12 meses queda confirmado.

ADOPTADO 2026-09-01 (decision del usuario): MODO_TASA = "soles_rodante".
El motivo es la CONSISTENCIA DEFINICIONAL, no que el error baje -- de hecho para los
ultimos 3 meses SUBE. Precedente directo: bug 18 se corrigio aunque empeoro los 4
meses, porque corregia como se mide. Con la tasa mal definida el sesgo real quedaba
tapado; ahora queda a la vista y es lo que hay que explicar, no ajustar.

CAVEAT QUE VIAJA CON ESTA META: si la caida de activacion sigue al ritmo medido, esta
meta corre ~10% por encima de lo alcanzable. No es ruido -- es la lectura de negocio
del mes, y se reporta junto con el numero.

Cambiar MODO_TASA es lo unico que hay que tocar para pasar de una a otra.
"""
import collections
import csv

from motor_unificado import (P_ENTRADA, cargar_curva_stock, cargar_curva_nuevos,
                             cargar_factor_dia_mes, cargar_factor_dia_mes_stock,
                             segmentar_calendario, proyectar, acumular_real)

DIR_19 = "datos_tarea19"
DIR_CA = "datos_capital_asegurado"
N_DIAS = 30
VENTANA = ("202508", "202607")

# "conteo_fijo" = definicion de produccion hasta agosto (P_ENTRADA 21.9918%)
# "soles_rodante" = definicion consistente (18b/18e), rodante en VENTANA
MODO_TASA = "soles_rodante"   # ADOPTADO 2026-09-01, decision del usuario (ver docstring)


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


TASAS = {"conteo_fijo": P_ENTRADA, "soles_rodante": tasa_soles_rodante()}

curva_stock = cargar_curva_stock(f"{DIR_CA}/curva_unificada_stock_seg_v3.csv")
f_dm_stock = cargar_factor_dia_mes_stock()
curva_nuevos = cargar_curva_nuevos(f"{DIR_CA}/curva_sep_nuevos_dow_seg.csv")
factor_dia_mes = cargar_factor_dia_mes(f"{DIR_CA}/factor_dia_mes_sep.csv")

stock_sep = {}
calendario_sep = collections.defaultdict(dict)
for r in leer(f"{DIR_19}/meta_septiembre_insumos.csv"):
    if r["tipo"] == "stock":
        stock_sep[(r["tramo"], r["avance_band"])] = float(r["saldo"])
    else:
        calendario_sep[int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo"])

cal_seg = segmentar_calendario(calendario_sep, "202609")


def proyeccion(modo):
    return proyectar(stock_sep, cal_seg, curva_stock, curva_nuevos, N_DIAS,
                     p_entrada=TASAS[modo], f_dm=factor_dia_mes, f_dm_stock=f_dm_stock)


filas = proyeccion(MODO_TASA)
for i, fila in enumerate(filas):
    fila["fecha"] = f"2026-09-{i+1:02d}"

if __name__ == "__main__":
    print("=" * 78)
    print("META DE SEPTIEMBRE 2026 -- ENFOQUE ALFA (capital asegurado), motor unificado v3")
    print("=" * 78)
    print(f"Stock al 1-sep (dias_atraso_cuota 1-30 al cierre de agosto): S/ {sum(stock_sep.values()):>12,.0f}")
    print(f"Calendario de septiembre (por dia de entrada, excl. stock):  S/ "
          f"{sum(sum(v.values()) for v in calendario_sep.values()):>12,.0f}")
    print(f"Curvas de nuevos calibradas en [{VENTANA[0]}, {VENTANA[1]}]; stock en 202504-202606 (fija)")
    print("Factor por dia del mes: " + "  ".join(
        f"{g}={factor_dia_mes.get(g, 1.0):.4f}" for g in ("quincena", "fin de mes", "resto")))
    print()
    print("Septiembre tiene 30 dias. No hay entradas los lunes (7, 14, 21 y 28) --")
    print("ninguna cuota vence domingo, asi que ningun credito entra en mora un lunes (bug 21).")
    print()

    print("--- LAS DOS TASAS EN DISCUSION (ver docstring) ---")
    res = {}
    for modo in ("conteo_fijo", "soles_rodante"):
        f = proyeccion(modo)[-1]
        res[modo] = f
        print(f"  {modo:<14} tasa {100*TASAS[modo]:>6.2f}%   meta S/ {f['proy_total']:>12,.0f}"
              f"   (stock S/ {f['proy_stock']:>10,.0f} + nuevos S/ {f['proy_nuevos']:>12,.0f})")
    d = res["soles_rodante"]["proy_total"] / res["conteo_fijo"]["proy_total"] - 1
    print(f"  diferencia: {100*d:+.1f}%  (S/ {res['soles_rodante']['proy_total']-res['conteo_fijo']['proy_total']:,.0f})")
    print()

    f = filas[-1]
    print(f"=== META VIGENTE (MODO_TASA = '{MODO_TASA}') ===")
    print(f"Meta total de septiembre:  S/ {f['proy_total']:,.0f}")
    print(f"  stock:                   S/ {f['proy_stock']:,.0f}")
    print(f"  nuevos:                  S/ {f['proy_nuevos']:,.0f}")
    print(f"\nAgosto cerro en S/ 17,322,872 (meta S/ 17,117,628, error -1.18%)")
    print(f"Septiembre vs. el REAL de agosto: {100*(f['proy_total']/17322872-1):+.1f}%")
    print()
    print(f"{'dia':>3} {'fecha':>11} | {'proy_stock':>11} {'proy_nuevos':>12} | {'proy_total':>12}")
    for r in filas:
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['proy_stock']:>11,.0f} "
              f"{r['proy_nuevos']:>12,.0f} | {r['proy_total']:>12,.0f}")

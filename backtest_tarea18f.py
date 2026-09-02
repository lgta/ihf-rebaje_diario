"""
TAREA 18a + 18f -- WALK-FORWARD DE 7 MESES, SIN LEAK EN LA CURVA DE NUEVOS.

Cierra las dos preguntas abiertas del motor unificado con un solo backtest:

  18a  segmentar la curva de nuevos por dia de la semana del vencimiento
  18f  factor por dia del mes DE PAGO (quincena y fin de mes)

Variantes (la segmentacion por avance_band NO se toca: 4 bandas, ver
tarea 18a para por que no se colapsa a 3):

  W0  banda                        <- estructura de produccion
  W1  banda x dow_venc             <- 18a (era V4)
  W2  banda           + f          <- 18f solo
  W3  banda x dow_venc + f         <- ambos

PROTOCOLO (decidido con el usuario, ver tarea 18c):
  - Calibracion: 12 meses RODANTES, [M-12, M-1] para cada mes de test M.
    La curva de nuevos nunca ve el mes que proyecta. Sale gratis porque
    se arma desde la matriz cruda (`curvas_crudas.py`), no de una query
    por ventana.
  - Test: 7 meses, 202601-202607. Es lo que da la historia con piso de
    3,000 entradas/mes (ver `tarea18_ventana_calibracion.sql`): antes de
    202501 la cartera es <20% de la actual y la dispersion de la curva se
    duplica.

LIMITACION QUE HAY QUE LEER ANTES DE INTERPRETAR EL NIVEL DE ERROR: la
curva de STOCK sigue siendo la de produccion (calibrada 202504-202606),
o sea NO rueda, y por lo tanto 6 de los 7 meses de test estan dentro de
su ventana de calibracion. El nivel absoluto de error de ene-jun es
optimista por eso. No afecta la comparacion entre W0/W1/W2/W3 -- el
componente de stock es identico en las 4 y se cancela. Rodar tambien el
stock es lo que queda de tarea 18c.
"""
import csv
import collections
import datetime as dt
import statistics

import curvas_crudas as CC
from motor_unificado import P_ENTRADA, cargar_curva_stock, lookup, acumular_real

DIR_18A = "datos_tarea18a"
DIR_F4 = "datos_tarea17_fase4"

MESES = [("202601", 31), ("202602", 28), ("202603", 31), ("202604", 30),
         ("202605", 31), ("202606", 30), ("202607", 31)]


def leer(path):
    with open(path) as f:
        return list(csv.DictReader(f))


curva_stock = cargar_curva_stock(f"{DIR_F4}/curva_stock.csv")

stock_pob = collections.defaultdict(dict)
for r in leer(f"{DIR_18A}/stock_pob_7m.csv"):
    stock_pob[r["periodo_meta"]][(r["tramo"], r["avance_band"])] = float(r["saldo_total"])

calendario = collections.defaultdict(lambda: collections.defaultdict(dict))
for r in leer(f"{DIR_18A}/calendario_7m.csv"):
    calendario[r["periodo"]][int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo_en_riesgo"])

real_stock, real_nuevos = collections.defaultdict(dict), collections.defaultdict(dict)
for r in leer(f"{DIR_18A}/real_stock_7m.csv"):
    real_stock[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])
for r in leer(f"{DIR_18A}/real_nuevos_7m.csv"):
    real_nuevos[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])

base_raw, acts_raw = CC.cargar_matriz()


def ventana(periodo, meses=12):
    """[M-12, M-1] como ('YYYYMM','YYYYMM')."""
    d = dt.date(int(periodo[:4]), int(periodo[4:]), 1)
    fin = d - dt.timedelta(days=1)
    ini = fin
    for _ in range(meses - 1):
        ini = (ini.replace(day=1) - dt.timedelta(days=1))
    return ini.strftime("%Y%m"), fin.strftime("%Y%m")


_cache = {}


def curva_de(periodo, con_dow, con_f):
    k = (periodo, con_dow, con_f)
    if k not in _cache:
        d, h = ventana(periodo)
        _cache[k] = CC.calibrar(base_raw, acts_raw, d, h, con_dow=con_dow, con_f=con_f)
    return _cache[k]


def dow_venc(periodo, dia_entrada):
    f = dt.date(int(periodo[:4]), int(periodo[4:]), dia_entrada)
    return (f - dt.timedelta(days=1)).weekday() + 1


def proyectar_f(periodo, n_dias, curva_n, f_dm, con_dow):
    """Serie diaria acumulada. `f_dm` multiplica el INCREMENTO del dia.

    En la proyeccion el dia del mes DEL PAGO es simplemente `d`, porque
    todo lo que se proyecta cae dentro del mes -- por eso f entra como
    f(grupo(d)) y no hace falta arrastrar la fecha de entrada.
    """
    # incrementos de la curva por segmento
    inc = {}
    for seg, cur in curva_n.items():
        prev, m = 0.0, {}
        for k in sorted(cur):
            m[k] = cur[k] - prev
            prev = cur[k]
        inc[seg] = m

    st = stock_pob[periodo]
    filas, acum_n = [], 0.0
    for d in range(1, n_dias + 1):
        fac = f_dm.get(CC._grupo_dm(d, "estructural"), 1.0)
        for de in range(1, d + 1):
            seg_dow = dow_venc(periodo, de)
            for banda, saldo in calendario[periodo].get(de, {}).items():
                seg = (banda, seg_dow) if con_dow else banda
                acum_n += saldo * P_ENTRADA * inc.get(seg, {}).get(d - de, 0.0) / 100.0 * fac
        proy_stock = sum(saldo * lookup(curva_stock.get(kk, {}), d) / 100.0
                         for kk, saldo in st.items())
        filas.append({"dia": d, "proy_stock": proy_stock, "proy_nuevos": acum_n,
                      "proy_total": proy_stock + acum_n})
    return filas


VARIANTES = [("W0  banda", False, False),
             ("W1  banda x dow", True, False),
             ("W2  banda + f", False, True),
             ("W3  banda x dow + f", True, True)]


def correr(con_dow, con_f):
    out = []
    for periodo, n in MESES:
        curva_n, f_dm = curva_de(periodo, con_dow, con_f)
        filas = proyectar_f(periodo, n, curva_n, f_dm, con_dow)
        rs, rn = acumular_real(real_stock[periodo], n), acumular_real(real_nuevos[periodo], n)
        f = filas[-1]
        rt = rs[-1] + rn[-1]
        pn = [x["proy_nuevos"] for x in filas]
        d = lambda s: [s[0]] + [s[i] - s[i - 1] for i in range(1, n)]
        out.append({
            "periodo": periodo, "err": 100 * (f["proy_total"] - rt) / rt,
            "err_nuevos": 100 * (f["proy_nuevos"] - rn[-1]) / rn[-1],
            "corr": statistics.correlation(d(pn), d(rn)),
            "mae_inc": sum(abs(a - b) for a, b in zip(d(pn), d(rn))) / n,
            "proy": f["proy_total"], "real": rt, "serie": filas,
        })
    return out


if __name__ == "__main__":
    print("=" * 108)
    print("TAREA 18a+18f -- WALK-FORWARD 7 MESES, calibracion rodante de 12m sin leak")
    print("=" * 108)
    d, h = ventana("202607")
    print(f"Ejemplo de ventana: para testear 202607 se calibra [{d}, {h}]")
    _, f_ej = curva_de("202607", True, True)
    print("Factor f de esa ventana: " + "  ".join(
        f"{g}={f_ej.get(g, 1.0):.4f}" for g in ("quincena", "fin de mes", "resto")))
    print()

    res = {n: correr(dw, cf) for n, dw, cf in VARIANTES}
    hdr = f"{'Variante':<21} | " + " ".join(f"{m[0][4:]:>7}" for m in MESES) + " |   media"
    for etq, campo, fmt in [("ERROR TOTAL de fin de mes", "err", "{:>+6.1f}%"),
                            ("CORRELACION de incrementos diarios (nuevos)", "corr", "{:>7.3f}")]:
        print(etq)
        print(hdr)
        print("-" * len(hdr))
        for n, *_ in VARIANTES:
            v = [f[campo] for f in res[n]]
            agg = sum(abs(x) for x in v) / len(v) if campo == "err" else sum(v) / len(v)
            print(f"{n:<21} | " + " ".join(fmt.format(x) for x in v)
                  + f" | {agg:>7.3f}" + ("%" if campo == "err" else ""))
        print()

    print("MAE del incremento diario de nuevos, miles de S/ (mas bajo = mejor)")
    print(hdr)
    print("-" * len(hdr))
    for n, *_ in VARIANTES:
        v = [f["mae_inc"] / 1000 for f in res[n]]
        print(f"{n:<21} | " + " ".join(f"{x:>7.0f}" for x in v) + f" | {sum(v)/len(v):>7.1f}")

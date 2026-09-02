"""
TAREA 18g -- WALK-FORWARD DE 7 MESES: reindexar "fin de mes" por el
CIERRE REAL de cada mes (dias-para-fin-de-mes = 0) en vez de por numero
de dia calendario fijo (30/31).

Continuacion directa de 18b (`analisis_sesgo_nuevos_18b.md`): reagrupando
la activacion por dias-para-fin-de-mes real, el pico de pago vive
SOLAMENTE en el ultimo dia real del mes (+63% sobre baseline en nuevos,
medido en toda la ventana 20250101-20260630) -- el penultimo dia no se
distingue del resto. El grupo {30,31} de produccion diluye ese pico
(mezcla el verdadero cierre de un mes de 31 dias con su penultimo dia,
que en un mes de 31 dias es casi-baseline) y no cubre NUNCA el cierre de
un mes de 28 dias como febrero -- que por eso es el unico mes del test
donde STOCK tambien falla fuerte (-11.0%, 79.3% del gap concentrado en un
solo dia).

Variantes (parten de W3 = produccion vigente 2026-08-26):

  Y0  = W3 tal cual (nuevos: estructural, rolling 12m; stock: fijo, sin factor)
  Y1  = nuevos reindexado por cierre real (rolling), stock sin cambios
  Y2  = nuevos sin cambios, stock + factor de cierre real (ventana FIJA, igual a produccion)
  Y3  = Y1 + Y2 combinados
  Y4  = Y3 + stock con ventana RODANTE de 12m (bonus: cierra tambien 18c)

PROTOCOLO: igual que 18a/18f -- calibracion rodante [M-12,M-1] sin leak
para todo lo que rueda, arbitrado con metricas DIARIAS (correlacion de
incrementos + MAE), no con el error de fin de mes (CLAUDE.md, "que
metrica arbitra que"). El error de cierre se reporta como contexto, no
como argumento de decision.

Diagnostico -- nada de esto se llevo a produccion todavia.
"""
import csv
import collections
import datetime as dt
import statistics

import curvas_crudas as CC
import curvas_crudas_stock as CS
from motor_unificado import P_ENTRADA, cargar_curva_stock, lookup, acumular_real

DIR_18A = "datos_tarea18a"
DIR_18G = "datos_tarea18g"
MESES_CALIBRACION = 12

MESES = [("202601", 31), ("202602", 28), ("202603", 31), ("202604", 30),
         ("202605", 31), ("202606", 30), ("202607", 31)]


def leer(path):
    with open(path) as f:
        return list(csv.DictReader(f))


curva_stock_fija = cargar_curva_stock()  # produccion: 202504-202606, sin factor

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

base_n, acts_n = CC.cargar_matriz()
base_s, acts_s = CS.cargar_matriz()

FIJA_STOCK = ("202504", "202606")  # ventana de produccion, sin rodar


def ventana(periodo, meses=MESES_CALIBRACION):
    y, m = int(periodo[:4]), int(periodo[4:])
    fin_y, fin_m = (y, m - 1) if m > 1 else (y - 1, 12)
    ini = fin_y * 12 + (fin_m - 1) - (meses - 1)
    return f"{ini // 12:04d}{ini % 12 + 1:02d}", f"{fin_y:04d}{fin_m:02d}"


def dow_venc(periodo, dia_entrada):
    f = dt.date(int(periodo[:4]), int(periodo[4:]), dia_entrada)
    return (f - dt.timedelta(days=1)).weekday() + 1


_cache_n, _cache_s = {}, {}


def curva_nuevos_de(periodo, granularidad):
    k = (periodo, granularidad)
    if k not in _cache_n:
        d, h = ventana(periodo)
        _cache_n[k] = CC.calibrar(base_n, acts_n, d, h, con_dow=True, con_f=True,
                                   granularidad=granularidad)
    return _cache_n[k]


def curva_stock_de(rueda, modo_cierre):
    """rueda=False usa la ventana fija de produccion para TODOS los meses
    (misma curva, cacheada una vez). rueda=True recalibra [M-12,M-1] por
    mes de test."""
    k = ("fija", modo_cierre)
    if not rueda:
        if k not in _cache_s:
            d, h = FIJA_STOCK
            _cache_s[k] = CS.calibrar(base_s, acts_s, d, h, con_f=(modo_cierre is not None),
                                       modo_cierre=modo_cierre or "real")
        return _cache_s[k]
    return None  # se resuelve por periodo en proyectar_g


def grupo_proyeccion(d, n_dias, modo):
    """Grupo de dia-del-mes durante la PROYECCION (no calibracion): `d` ya
    es el dia dentro del mes que se esta proyectando, de largo `n_dias`
    conocido -- 'cierre' es simplemente d==n_dias, sin calendario."""
    if d in (15, 16):
        return "quincena"
    if modo == "real" and d == n_dias:
        return "cierre"
    if modo == "estructural" and d in (30, 31):
        return "fin de mes"
    return "resto"


def proyectar_g(periodo, n_dias, curva_n, f_n, modo_n, curva_s, f_s, modo_s):
    inc_n = {}
    for seg, cur in curva_n.items():
        prev, m = 0.0, {}
        for k in sorted(cur):
            m[k] = cur[k] - prev
            prev = cur[k]
        inc_n[seg] = m

    # incrementos de la curva de stock POR SEGMENTO, dia 1..n_dias
    inc_s = {}
    for seg, saldo in stock_pob[periodo].items():
        cur = curva_s.get(seg, {})
        prev = 0.0
        m = {}
        for d in range(1, n_dias + 1):
            v = lookup(cur, d) / 100.0
            m[d] = (v - prev) * saldo
            prev = v
        inc_s[seg] = m

    filas, acum_n, acum_s = [], 0.0, 0.0
    for d in range(1, n_dias + 1):
        fac_n = f_n.get(grupo_proyeccion(d, n_dias, modo_n), 1.0)
        for de in range(1, d + 1):
            seg_dow = dow_venc(periodo, de)
            for banda, saldo in calendario[periodo].get(de, {}).items():
                acum_n += saldo * P_ENTRADA * inc_n.get((banda, seg_dow), {}).get(d - de, 0.0) / 100.0 * fac_n

        fac_s = f_s.get(grupo_proyeccion(d, n_dias, modo_s), 1.0) if f_s else 1.0
        acum_s += sum(m.get(d, 0.0) for m in inc_s.values()) * fac_s

        filas.append({"dia": d, "proy_stock": acum_s, "proy_nuevos": acum_n,
                      "proy_total": acum_s + acum_n})
    return filas


def correr(modo_n, stock_factor, stock_rueda):
    """modo_n: 'estructural' (W3) o 'real' (Y1+). stock_factor: None (sin
    factor, produccion) o 'real'. stock_rueda: si la ventana de stock
    tambien rueda 12m (bonus, resuelve 18c)."""
    out = []
    for periodo, n in MESES:
        curva_n, f_n = curva_nuevos_de(periodo, modo_n)

        if stock_rueda:
            d, h = ventana(periodo)
            curva_s, f_s = CS.calibrar(base_s, acts_s, d, h, con_f=(stock_factor is not None),
                                        modo_cierre=stock_factor or "real")
        elif stock_factor:
            curva_s, f_s = curva_stock_de(False, stock_factor)
        else:
            curva_s, f_s = curva_stock_fija, {}

        modo_s = "real" if stock_factor else "estructural"
        filas = proyectar_g(periodo, n, curva_n, f_n, modo_n, curva_s, f_s, modo_s)
        rs, rn = acumular_real(real_stock[periodo], n), acumular_real(real_nuevos[periodo], n)
        f = filas[-1]
        rt = rs[-1] + rn[-1]
        pn = [x["proy_nuevos"] for x in filas]
        ps = [x["proy_stock"] for x in filas]
        pt = [x["proy_total"] for x in filas]
        rt_serie = [a + b for a, b in zip(rs, rn)]
        d_ = lambda s: [s[0]] + [s[i] - s[i - 1] for i in range(1, n)]
        out.append({
            "periodo": periodo,
            "err": 100 * (f["proy_total"] - rt) / rt,
            "err_stock": 100 * (f["proy_stock"] - rs[-1]) / rs[-1],
            "err_nuevos": 100 * (f["proy_nuevos"] - rn[-1]) / rn[-1],
            "corr_nuevos": statistics.correlation(d_(pn), d_(rn)),
            "corr_stock": statistics.correlation(d_(ps), d_(rs)),
            "corr_total": statistics.correlation(d_(pt), d_(rt_serie)),
            "mae_nuevos": sum(abs(a - b) for a, b in zip(d_(pn), d_(rn))) / n,
            "mae_stock": sum(abs(a - b) for a, b in zip(d_(ps), d_(rs))) / n,
        })
    return out


VARIANTES = [
    ("Y0 W3 (produccion)          ", "estructural", None, False),
    ("Y1 nuevos cierre real       ", "real", None, False),
    ("Y2 stock + factor cierre    ", "estructural", "real", False),
    ("Y3 Y1+Y2 combinado          ", "real", "real", False),
    ("Y4 Y3 + stock rodando (18c) ", "real", "real", True),
]

if __name__ == "__main__":
    print("=" * 118)
    print("TAREA 18g -- reindex por CIERRE REAL del mes (nuevos y stock), walk-forward 7 meses")
    print("=" * 118)
    print()

    res = {n: correr(mn, sf, sr) for n, mn, sf, sr in VARIANTES}

    hdr = f"{'Variante':<30} | " + " ".join(f"{m[0][4:]:>7}" for m in MESES) + " |   media"
    for etq, campo, fmt in [
        ("ERROR TOTAL de fin de mes (contexto, NO arbitro)", "err", "{:>+6.1f}%"),
        ("CORRELACION incrementos diarios -- TOTAL", "corr_total", "{:>7.3f}"),
        ("CORRELACION incrementos diarios -- stock", "corr_stock", "{:>7.3f}"),
        ("CORRELACION incrementos diarios -- nuevos", "corr_nuevos", "{:>7.3f}"),
    ]:
        print(etq)
        print(hdr)
        print("-" * len(hdr))
        for n, *_ in VARIANTES:
            v = [f[campo] for f in res[n]]
            agg = sum(abs(x) for x in v) / len(v) if campo == "err" else sum(v) / len(v)
            print(f"{n:<30} | " + " ".join(fmt.format(x) for x in v)
                  + f" | {agg:>7.3f}" + ("%" if campo == "err" else ""))
        print()

    print("MAE del incremento diario, miles de S/ (mas bajo = mejor)")
    print(hdr)
    print("-" * len(hdr))
    for campo, etq in [("mae_stock", "stock"), ("mae_nuevos", "nuevos")]:
        for n, *_ in VARIANTES:
            v = [f[campo] / 1000 for f in res[n]]
            print(f"{n:<24} {etq:<6} | " + " ".join(f"{x:>7.0f}" for x in v) + f" | {sum(v)/len(v):>7.1f}")
        print()

    print("Febrero especificamente -- err_stock e incremento day-28 (donde vive el hallazgo de 18b):")
    for n, *_ in VARIANTES:
        f = res[n][1]  # 202602
        print(f"  {n}: err_stock={f['err_stock']:>+6.1f}%  err_nuevos={f['err_nuevos']:>+6.1f}%  "
              f"err_total={f['err']:>+6.1f}%")

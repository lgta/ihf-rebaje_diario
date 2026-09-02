"""
TAREA 18e -- MOTOR DE RECUPERO OFICIAL, v2: REFINAMIENTO DE FORMA sobre
las Fases A-D (backtest_tarea18e_recupero_oficial_dac.py), aplicando a
este motor el mismo tratamiento que 18a/18f/18g ya validaron para el
Enfoque alfa -- ventana rodante sin leak, dia de semana del vencimiento,
factor de quincena en nuevos, factor de cierre real en stock.

Reusa `curvas_crudas.py`/`curvas_crudas_stock.py` TAL CUAL (no se toca
ninguna linea de esos modulos): el IPF que calibran trata la columna
"saldo" de cada celda como una masa observada, sin asumir que es
"activacion" -- la misma mecanica calibra una curva de REBAJE si se le
da una matriz cruda de rebaje en vez de activacion. Los insumos nuevos
son:
  - datos_tarea18e/curva_cruda_nuevos_rebaje.csv (tarea18e_matriz_cruda_
    nuevos_rebaje.sql): mismo esquema que curva_cruda.csv, pero la fila
    tipo='act' es SUMA DE REBAJE por (fecha_entrada, avance_band, dia
    desde entrada) -- no solo el dia del primer pago.
  - datos_tarea18e/curva_cruda_stock_rebaje.csv (tarea18e_matriz_cruda_
    stock_rebaje.sql): analogo para stock.
  - datos_tarea18e/tasa_soles_18m.csv (tarea18e_tasa_soles_18m.sql):
    desglose MENSUAL de la tasa de entrada por SOLES (Fase A extendida a
    202501-202606) -- permite rodarla junto con la curva de nuevos, sin
    leak, en vez de fijarla como P_ENTRADA (que en Enfoque alfa nunca
    rodo).

DECISIONES DE DISENO (para no repetir experimentos ya resueltos):
  - NUEVOS rueda [M-12,M-1] (curva Y tasa) -- mismo mecanismo que 18a/18f
    ya midio (leak ~0.10pp, curva mejora la trayectoria diaria en TODOS
    los meses).
  - STOCK NO rueda -- ventana FIJA 202504-202606, igual que produccion de
    Enfoque alfa. Rodar stock ya se PROBO en 18c/18g para el Enfoque alfa
    y EMPEORA (corr. 0.848->0.820, stock es el componente de mayor
    varianza muestral) -- se aplica la misma decision aca en vez de
    re-medir el mismo mecanismo dos veces.
  - STOCK SI lleva el factor de cierre real (modo "real", como v3 del
    motor unificado) -- ese refinamiento es INDEPENDIENTE de rodar o no
    la ventana, y si se adopto en Enfoque alfa (mejora medida y dirigida).
  - NUEVOS con dow + factor de quincena, modo "estructural" (como W3 en
    produccion) -- no se prueba el modo "real" para nuevos aca (18g ya
    midio que es marginal, 0.886->0.888).

CRITERIO (CLAUDE.md): las metricas DIARIAS (correlacion de incrementos,
MAE) arbitran si la forma mejora -- el error de fin de mes es contexto,
no arbitro (mismo "Que metrica arbitra que" de siempre).
"""
import csv
import collections
import datetime as dt
import statistics

import curvas_crudas as CC
import curvas_crudas_stock as CS
from motor_unificado import lookup, acumular_real

DIR_18A = "datos_tarea18a"
DIR_18E = "datos_tarea18e"
MESES_CALIBRACION = 12

MESES = [("202601", 31, "Enero 2026"), ("202602", 28, "Febrero 2026"),
         ("202603", 31, "Marzo 2026"), ("202604", 30, "Abril 2026"),
         ("202605", 31, "Mayo 2026"), ("202606", 30, "Junio 2026"),
         ("202607", 31, "Julio 2026")]

FIJA_STOCK = ("202504", "202606")  # ventana de produccion, sin rodar (18c)

# Motor vigente (dayslate) y v1/Fase D (dias_atraso_cuota, sin refinar),
# para contexto -- ver backtest_tarea18e_recupero_oficial_dac.py.
VIGENTE_DAYSLATE = {"202606": 5.4, "202607": 17.6}
V1_SIN_REFINAR = {"202601": 0.5, "202602": -6.1, "202603": -4.0, "202604": 1.4,
                  "202605": 8.6, "202606": 16.8, "202607": 18.5}


def leer(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def ventana(periodo, meses=MESES_CALIBRACION):
    """[M-meses, M-1] como ('YYYYMM','YYYYMM'). Nunca ve el mes M."""
    y, m = int(periodo[:4]), int(periodo[4:])
    fin_y, fin_m = (y, m - 1) if m > 1 else (y - 1, 12)
    ini = fin_y * 12 + (fin_m - 1) - (meses - 1)
    return f"{ini // 12:04d}{ini % 12 + 1:02d}", f"{fin_y:04d}{fin_m:02d}"


def dow_venc(periodo, dia_entrada):
    f = dt.date(int(periodo[:4]), int(periodo[4:]), dia_entrada)
    return (f - dt.timedelta(days=1)).weekday() + 1


def grupo_proyeccion(d, n_dias):
    """Nuevos: modo estructural (quincena 15-16, fin de mes 30/31 fijo).
    Stock: modo real (quincena 15-16, cierre = d==n_dias)."""
    if d in (15, 16):
        return "quincena", "quincena"
    gn = "fin de mes" if d in (30, 31) else "resto"
    gs = "cierre" if d == n_dias else "resto"
    return gn, gs


# ---------------------------------------------------------------------
# Insumos
# ---------------------------------------------------------------------
stock_pob = collections.defaultdict(dict)
for r in leer(f"{DIR_18A}/stock_pob_7m.csv"):
    stock_pob[r["periodo_meta"]][(r["tramo"], r["avance_band"])] = float(r["saldo_total"])

calendario = collections.defaultdict(lambda: collections.defaultdict(dict))
for r in leer(f"{DIR_18A}/calendario_7m.csv"):
    calendario[r["periodo"]][int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo_en_riesgo"])

real_stock, real_nuevos = collections.defaultdict(dict), collections.defaultdict(dict)
for r in leer(f"{DIR_18E}/real_rebaje_7m.csv"):
    destino = real_stock if r["componente"] == "stock" else real_nuevos
    destino[r["periodo"]][int(r["dia"])] = float(r["rebaje_dia"])

tasa_mes = {}  # periodo -> (elegibles_soles, entran_soles)
for r in leer(f"{DIR_18E}/tasa_soles_18m.csv"):
    tasa_mes[r["periodo"]] = (float(r["elegibles_soles"]), float(r["entran_soles"]))


def tasa_rodante(periodo):
    d, h = ventana(periodo)
    elig = sum(v[0] for p, v in tasa_mes.items() if d <= p <= h)
    ent = sum(v[1] for p, v in tasa_mes.items() if d <= p <= h)
    return ent / elig


base_n, acts_n = CC.cargar_matriz(f"{DIR_18E}/curva_cruda_nuevos_rebaje.csv")
base_s, acts_s = CS.cargar_matriz(f"{DIR_18E}/curva_cruda_stock_rebaje.csv")

curva_s_fija, f_s_fija = CS.calibrar(base_s, acts_s, *FIJA_STOCK, con_f=True, modo_cierre="real")

_cache_n = {}


def curva_nuevos_de(periodo):
    if periodo not in _cache_n:
        d, h = ventana(periodo)
        _cache_n[periodo] = CC.calibrar(base_n, acts_n, d, h, con_dow=True, con_f=True,
                                         granularidad="estructural")
    return _cache_n[periodo]


def proyectar(periodo, n_dias):
    p_entrada = tasa_rodante(periodo)
    curva_n, f_n = curva_nuevos_de(periodo)

    inc_n = {}
    for seg, cur in curva_n.items():
        prev, m = 0.0, {}
        for k in sorted(cur):
            m[k] = cur[k] - prev
            prev = cur[k]
        inc_n[seg] = m

    inc_s = {}
    for seg, saldo in stock_pob[periodo].items():
        cur = curva_s_fija.get(seg, {})
        prev, m = 0.0, {}
        for d in range(1, n_dias + 1):
            v = lookup(cur, d) / 100.0
            m[d] = (v - prev) * saldo
            prev = v
        inc_s[seg] = m

    filas, acum_n, acum_s = [], 0.0, 0.0
    for d in range(1, n_dias + 1):
        gn, gs = grupo_proyeccion(d, n_dias)
        fac_n = f_n.get(gn, 1.0)
        fac_s = f_s_fija.get(gs, 1.0)
        for de in range(1, d + 1):
            seg_dow = dow_venc(periodo, de)
            for banda, saldo in calendario[periodo].get(de, {}).items():
                acum_n += saldo * p_entrada * inc_n.get((banda, seg_dow), {}).get(d - de, 0.0) / 100.0 * fac_n
        acum_s += sum(m.get(d, 0.0) for m in inc_s.values()) * fac_s
        filas.append({"dia": d, "proy_stock": acum_s, "proy_nuevos": acum_n,
                      "proy_total": acum_s + acum_n})
    return filas, p_entrada


if __name__ == "__main__":
    print("=" * 122)
    print("TAREA 18e v2 -- RECUPERO OFICIAL REFINADO: ventana rodante (nuevos) + dow + quincena")
    print("+ factor de cierre real (stock), walk-forward 7 meses, sin leak")
    print("=" * 122)
    print()

    hdr = (f"{'Mes':<14} | {'Proyectado':>12} {'Real (dac)':>12} {'error':>8} | "
           f"{'err stock':>10} {'err nuevos':>11} {'corr diaria':>12} | {'p_entrada':>9} | "
           f"{'v1 s/refinar':>12} | {'vigente':>9}")
    print(hdr)
    print("-" * len(hdr))
    errores, corrs = [], []
    import os
    os.makedirs(DIR_18E, exist_ok=True)
    for periodo, n, nombre in MESES:
        filas, p_ent = proyectar(periodo, n)
        rs = acumular_real(real_stock[periodo], n)
        rn_ = acumular_real(real_nuevos[periodo], n)
        for i, fila in enumerate(filas):
            fila["real_stock"] = rs[i]
            fila["real_nuevos"] = rn_[i]
            fila["real_total"] = rs[i] + rn_[i]
        f = filas[-1]
        err = 100 * (f["proy_total"] - f["real_total"]) / f["real_total"]
        es = 100 * (f["proy_stock"] - f["real_stock"]) / f["real_stock"]
        en = 100 * (f["proy_nuevos"] - f["real_nuevos"]) / f["real_nuevos"]
        pt = [x["proy_total"] for x in filas]
        rt = [x["real_total"] for x in filas]
        inc = lambda s: [s[0]] + [s[i] - s[i - 1] for i in range(1, n)]
        c = statistics.correlation(inc(pt), inc(rt))
        errores.append(abs(err))
        corrs.append(c)
        v1 = V1_SIN_REFINAR.get(periodo)
        vig = VIGENTE_DAYSLATE.get(periodo)
        print(f"{nombre:<14} | {f['proy_total']:>12,.0f} {f['real_total']:>12,.0f} "
              f"{err:>+7.1f}% | {es:>+9.1f}% {en:>+10.1f}% {c:>12.3f} | {100*p_ent:>8.2f}% | "
              + (f"{v1:>+11.1f}%" if v1 is not None else f"{'--':>12}") + " | "
              + (f"{vig:>+8.1f}%" if vig is not None else f"{'--':>9}"))

        with open(f"{DIR_18E}/serie_diaria_recupero_v2_{periodo}.csv", "w", newline="") as out:
            w = csv.DictWriter(out, fieldnames=["dia", "proy_stock", "proy_nuevos",
                                                "proy_total", "real_stock", "real_nuevos",
                                                "real_total"])
            w.writeheader()
            for fila in filas:
                w.writerow({k: (round(v, 2) if k != "dia" else v)
                            for k, v in fila.items() if k in w.fieldnames})

    print()
    print(f"Magnitud media de error de fin de mes: {sum(errores)/len(errores):.2f}%  "
          f"(v1 sin refinar: {sum(abs(v) for v in V1_SIN_REFINAR.values())/7:.2f}%)")
    print(f"Correlacion media de incrementos diarios (total): {sum(corrs)/len(corrs):.3f}")
    print()
    print(f"Series diarias escritas en {DIR_18E}/serie_diaria_recupero_v2_*.csv")

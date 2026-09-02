"""
Prepara TODOS los datos del artifact "De asignado a asegurado"
(`asignado_a_asegurado.html`): la cadena completa por segmento, para
agosto 2026 (mes cerrado, real medido) y septiembre 2026 (proyeccion).

Escribe `datos_asignado_a_asegurado.json`, que el HTML embebe.

QUE ES CADA COSA (los nombres importan -- confundir dos ratios de
distinta definicion es el error de bug 10 / 18b):

  ANTIGUOS (stock). Ya estan en mora el dia 1. Se asignan TODOS de una
  vez al inicio del mes. Un solo ratio:
      ratio de activacion de antiguos = asegurado / asignado

  NUEVOS. No existen el dia 1: van apareciendo dia a dia, cuando vence
  su cuota y no pagan. Dos ratios encadenados:
      tasa de entrada en mora = entran / calendario
      ratio de activacion de nuevos = asegurado / entran
  El calendario NO es capital asignado -- es el universo de cuotas que
  vencen, y la mayoria paga a tiempo y nunca entra a cobranza.

DOS CALENDARIOS, A PROPOSITO (y hay que decirlo, no esconderlo):
  - el calendario REAL de un mes cerrado usa el saldo del dia del
    vencimiento y `status IN ('ACTIVE','COMPLETED')`;
  - el calendario PROSPECTIVO de una meta usa el saldo anclado al cierre
    del mes anterior y `status = 'ACTIVE'` (regla de CLAUDE.md), porque
    al fijar la meta no se conoce el saldo futuro.
  Por eso los dos numeros no coinciden y no deberian.
"""
import collections
import csv
import datetime as dt
import json

import curvas_crudas as CC
from motor_unificado import (cargar_curva_stock, cargar_curva_nuevos,
                             cargar_factor_dia_mes, cargar_factor_dia_mes_stock,
                             lookup, grupo_dia_mes, grupo_dia_mes_stock)

DIR_19 = "datos_tarea19"
DIR_CA = "datos_capital_asegurado"
DIR_F4 = "datos_tarea17_fase4"

NOM_DOW = {1: "lunes", 2: "martes", 3: "miércoles", 4: "jueves", 5: "viernes", 6: "sábado"}
ENTRA_DOW = {1: "martes", 2: "miércoles", 3: "jueves", 4: "viernes", 5: "sábado", 6: "domingo"}
BANDAS = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]


def leer(p):
    with open(p) as f:
        return list(csv.DictReader(f))


def dow_venc(periodo, dia_entrada):
    f = dt.date(int(periodo[:4]), int(periodo[4:]), dia_entrada)
    return (f - dt.timedelta(days=1)).weekday() + 1


def d0(dic, *k):
    for kk in k:
        dic = dic.setdefault(kk, {})
    return dic


# =====================================================================
# 1. AGOSTO REAL -- la cadena medida, por segmento
# =====================================================================
cad = leer(f"{DIR_19}/agosto_cadena_segmentada.csv")
ag = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0.0]))
for r in cad:
    cr, sa = int(r["creditos"]), float(r["saldo"])
    t = r["tipo"]
    if t.startswith("stock"):
        k = (r["tramo"], r["avance_band"])
    else:
        k = (r["avance_band"], int(r["dia_entrada"]))
    ag[t][k][0] += cr
    ag[t][k][1] += sa


def tot(t):
    return [sum(v[0] for v in ag[t].values()), sum(v[1] for v in ag[t].values())]


# --- antiguos por (tramo, avance) ---
stock_real = []
for tr in TRAMOS:
    for b in BANDAS:
        base = ag["stock_base"].get((tr, b), [0, 0.0])
        act = ag["stock_act"].get((tr, b), [0, 0.0])
        if base[1] <= 0:
            continue
        stock_real.append({
            "tramo": tr, "banda": b,
            "cred_asignado": base[0], "asignado": base[1],
            "cred_asegurado": act[0], "asegurado": act[1],
            "ratio": 100 * act[1] / base[1],
        })

# --- nuevos por banda, y por dia de la semana del vencimiento ---
def agrupar_nuevos(keyfn):
    out = collections.defaultdict(lambda: [0.0, 0.0, 0.0, 0, 0, 0])
    for tipo, i in (("nuevos_cal", 0), ("nuevos_ent", 1), ("nuevos_act", 2)):
        for (b, de), v in ag[tipo].items():
            k = keyfn(b, de)
            out[k][i] += v[1]
            out[k][i + 3] += v[0]
    return out


nuevos_banda = []
for k, v in sorted(agrupar_nuevos(lambda b, de: b).items()):
    nuevos_banda.append({
        "banda": k, "calendario": v[0], "entran": v[1], "asegurado": v[2],
        "cred_cal": v[3], "cred_ent": v[4], "cred_act": v[5],
        "tasa_entrada": 100 * v[1] / v[0] if v[0] else 0,
        "ratio_activacion": 100 * v[2] / v[1] if v[1] else 0,
    })

nuevos_dow = []
for k, v in sorted(agrupar_nuevos(lambda b, de: dow_venc("202608", de)).items()):
    nuevos_dow.append({
        "dow": k, "vence": NOM_DOW[k], "entra": ENTRA_DOW[k],
        "calendario": v[0], "entran": v[1], "asegurado": v[2],
        "tasa_entrada": 100 * v[1] / v[0] if v[0] else 0,
        "ratio_activacion": 100 * v[2] / v[1] if v[1] else 0,
    })

nuevos_dia = []
for k, v in sorted(agrupar_nuevos(lambda b, de: de).items()):
    nuevos_dia.append({"dia": k, "calendario": v[0], "entran": v[1],
                       "asegurado": v[2], "dow": dow_venc("202608", k)})

# =====================================================================
# 2. AGOSTO CON EL MOTOR NUEVO (tasa por soles) vs. lo que se publico
# =====================================================================
def cargar_insumos(path):
    stock, cal = {}, collections.defaultdict(dict)
    for r in leer(path):
        if r["tipo"] == "stock":
            stock[(r["tramo"], r["avance_band"])] = float(r["saldo"])
        else:
            cal[int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo"])
    return stock, cal


def tasa_soles(desde, hasta):
    e = n = 0.0
    for r in leer(f"{DIR_19}/tasa_soles.csv"):
        if desde <= r["periodo"] <= hasta:
            e += float(r["elegibles_soles"])
            n += float(r["entran_soles"])
    return n / e


def proyectar_segmentado(stock, cal, curva_s, curva_n, f_dm, f_dm_s, p_ent,
                         periodo, n_dias):
    """Igual que motor_unificado.proyectar pero devolviendo la apertura por
    segmento al cierre del mes, ademas de la serie diaria total."""
    # --- antiguos ---
    filas_s = []
    for (tr, b), saldo in stock.items():
        acum = 0.0
        for d in range(1, n_dias + 1):
            inc = lookup(curva_s.get((tr, b), {}), d) - lookup(curva_s.get((tr, b), {}), d - 1)
            acum += saldo * inc / 100.0 * (f_dm_s.get(grupo_dia_mes_stock(d, n_dias), 1.0))
        filas_s.append({"tramo": tr, "banda": b, "asignado": saldo,
                        "asegurado": acum, "ratio": 100 * acum / saldo if saldo else 0})
    # --- nuevos ---
    por_banda = collections.defaultdict(lambda: [0.0, 0.0])
    por_dow = collections.defaultdict(lambda: [0.0, 0.0])
    por_dia = collections.defaultdict(lambda: [0.0, 0.0])
    for de, seg in cal.items():
        dw = dow_venc(periodo, de)
        for b, saldo in seg.items():
            acum = 0.0
            for d in range(de, n_dias + 1):
                cur = curva_n.get((b, dw), {})
                inc = lookup(cur, d - de, True) - (lookup(cur, d - de - 1, True) if d > de else 0.0)
                acum += saldo * p_ent * inc / 100.0 * f_dm.get(grupo_dia_mes(d), 1.0)
            for tgt, k in ((por_banda, b), (por_dow, dw), (por_dia, de)):
                tgt[k][0] += saldo
                tgt[k][1] += acum
    return filas_s, por_banda, por_dow, por_dia


curva_s_v3 = cargar_curva_stock(f"{DIR_CA}/curva_unificada_stock_seg_v3.csv")
f_s = cargar_factor_dia_mes_stock()

# --- agosto, ventana honesta al 1-ago ---
stock_ago, cal_ago = cargar_insumos(f"{DIR_F4}/meta_agosto_insumos.csv")
base_n, acts_n = CC.cargar_matriz(f"{DIR_19}/curva_cruda_nuevos.csv")
curva_n_ago, f_n_ago = CC.calibrar(base_n, acts_n, "202507", "202606", con_dow=True, con_f=True)
p_ago = tasa_soles("202507", "202606")
s_ago, nb_ago, nd_ago, ndia_ago = proyectar_segmentado(
    stock_ago, cal_ago, curva_s_v3, curva_n_ago, f_n_ago, f_s, p_ago, "202608", 31)

# --- septiembre ---
stock_sep, cal_sep = cargar_insumos(f"{DIR_19}/meta_septiembre_insumos.csv")
curva_n_sep = cargar_curva_nuevos(f"{DIR_CA}/curva_sep_nuevos_dow_seg.csv")
f_n_sep = cargar_factor_dia_mes(f"{DIR_CA}/factor_dia_mes_sep.csv")
p_sep = tasa_soles("202508", "202607")
s_sep, nb_sep, nd_sep, ndia_sep = proyectar_segmentado(
    stock_sep, cal_sep, curva_s_v3, curva_n_sep, f_n_sep, f_s, p_sep, "202609", 30)


def empaquetar(filas_s, nb, nd, ndia, periodo, p_ent):
    return {
        "tasa_entrada": 100 * p_ent,
        "stock": sorted(filas_s, key=lambda r: (r["tramo"], r["banda"])),
        "nuevos_banda": [{"banda": k, "calendario": v[0], "entran": v[0] * p_ent,
                          "asegurado": v[1],
                          "ratio_activacion": 100 * v[1] / (v[0] * p_ent) if v[0] else 0}
                         for k, v in sorted(nb.items())],
        "nuevos_dow": [{"dow": k, "vence": NOM_DOW[k], "entra": ENTRA_DOW[k],
                        "calendario": v[0], "entran": v[0] * p_ent, "asegurado": v[1],
                        "ratio_activacion": 100 * v[1] / (v[0] * p_ent) if v[0] else 0}
                       for k, v in sorted(nd.items())],
        "nuevos_dia": [{"dia": k, "calendario": v[0], "asegurado": v[1],
                        "dow": dow_venc(periodo, k)} for k, v in sorted(ndia.items())],
    }


# =====================================================================
# 3. Curvas, para mostrar la forma
# =====================================================================
curvas_stock = {f"{tr}|{b}": [{"dia": d, "pct": curva_s_v3[(tr, b)][d]}
                              for d in sorted(curva_s_v3[(tr, b)])]
                for (tr, b) in curva_s_v3}
curvas_nuevos = {f"{b}|{dw}": [{"dia": d, "pct": curva_n_sep[(b, dw)][d]}
                               for d in sorted(curva_n_sep[(b, dw)])]
                 for (b, dw) in curva_n_sep}

# serie diaria real de agosto, para la trayectoria
real_dia = collections.defaultdict(lambda: {"stock": 0.0, "nuevos": 0.0})
for r in leer(f"{DIR_19}/real_agosto_cierre.csv"):
    real_dia[int(r["dia"])][r["componente"]] += float(r["saldo_activado_dia"])

out = {
    "agosto_real": {
        "stock": stock_real,
        "nuevos_banda": nuevos_banda,
        "nuevos_dow": nuevos_dow,
        "nuevos_dia": nuevos_dia,
        "totales": {k: tot(k) for k in ("stock_base", "stock_act", "nuevos_cal",
                                        "nuevos_ent", "nuevos_act")},
        "serie": [{"dia": d, "stock": real_dia[d]["stock"], "nuevos": real_dia[d]["nuevos"]}
                  for d in sorted(real_dia)],
    },
    "agosto_modelo": empaquetar(s_ago, nb_ago, nd_ago, ndia_ago, "202608", p_ago),
    "septiembre": empaquetar(s_sep, nb_sep, nd_sep, ndia_sep, "202609", p_sep),
    "curvas_stock": curvas_stock,
    "curvas_nuevos": curvas_nuevos,
    "factores": {
        "nuevos_sep": cargar_factor_dia_mes(f"{DIR_CA}/factor_dia_mes_sep.csv"),
        "stock": f_s,
    },
}

HTML = "asignado_a_asegurado.html"
INI, FIN = "/*DATOS*/", "/*/DATOS*/"


def inyectar(datos):
    """Reemplaza el bloque entre marcadores en el HTML por el JSON."""
    with open(HTML, encoding="utf-8") as f:
        s = f.read()
    i, j = s.index(INI), s.index(FIN)
    s = s[:i + len(INI)] + json.dumps(datos, ensure_ascii=False, separators=(",", ":")) + s[j:]
    with open(HTML, "w", encoding="utf-8") as f:
        f.write(s)
    return len(s)


if __name__ == "__main__":
    with open("datos_asignado_a_asegurado.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    n = inyectar(out)
    print(f"{HTML}: {n:,} bytes (datos inyectados)")

    tr = out["agosto_real"]["totales"]
    print("AGOSTO 2026 -- CADENA REAL")
    print(f"  antiguos: asignado S/{tr['stock_base'][1]:>12,.0f} -> asegurado S/{tr['stock_act'][1]:>12,.0f}"
          f"   ({100*tr['stock_act'][1]/tr['stock_base'][1]:.2f}%)")
    print(f"  nuevos:   calendario S/{tr['nuevos_cal'][1]:>10,.0f} -> entran S/{tr['nuevos_ent'][1]:>12,.0f}"
          f"   ({100*tr['nuevos_ent'][1]/tr['nuevos_cal'][1]:.2f}%)")
    print(f"            entran     S/{tr['nuevos_ent'][1]:>10,.0f} -> asegurado S/{tr['nuevos_act'][1]:>12,.0f}"
          f"   ({100*tr['nuevos_act'][1]/tr['nuevos_ent'][1]:.2f}%)")
    real_tot = tr["stock_act"][1] + tr["nuevos_act"][1]
    print(f"  TOTAL ASEGURADO REAL: S/{real_tot:,.0f}")
    print()
    for nom, d, real in (("AGOSTO, MOTOR NUEVO (tasa por soles)", out["agosto_modelo"], real_tot),
                         ("SEPTIEMBRE (proyeccion)", out["septiembre"], None)):
        st = sum(r["asegurado"] for r in d["stock"])
        nu = sum(r["asegurado"] for r in d["nuevos_banda"])
        print(f"{nom}")
        print(f"  tasa de entrada usada: {d['tasa_entrada']:.4f}%")
        print(f"  antiguos S/{st:>12,.0f} + nuevos S/{nu:>12,.0f} = S/{st+nu:>12,.0f}")
        if real:
            print(f"  vs. real S/{real:,.0f}  ->  {100*((st+nu)/real-1):+.2f}%")
        print()
    print("datos_asignado_a_asegurado.json escrito")

"""
Prepara los datos embebidos del artifact resumen_julio_agosto.html: curvas de
maduración (ambos enfoques), composición de la asignación de julio y agosto
(stock + calendario de nuevos), y el avance real-vs-proyectado hasta el corte.

v2 (2026-08-26, tarea 18d) -- reescrito sobre el motor UNIFICADO. Ya no hay
capa fantasma (eliminada en tarea 17 Fase 4, 2026-08-25): capital asegurado
es 2 componentes (stock + nuevos), calibrados con `dias_atraso_cuota` y
P_ENTRADA=21.9918%, con la curva de nuevos segmentada por día de semana del
vencimiento + factor de quincena/fin de mes (motor_unificado.py v2, W3).

Julio (mes cerrado) usa el BACKTEST OFICIAL v3 (motor_unificado.py + el
factor de cierre real de stock, tarea 18g) -- es el número más fiel
disponible para un mes ya cerrado. Agosto (mes en curso) usa la META YA
FIJADA v2/W3 (`meta_agosto_capital_asegurado.py`) -- a propósito NO se
retoca con v3 a mitad de mes (ver PENDIENTES.md tarea 18g: "la meta de
agosto no se toca"), así que julio y agosto de este artifact usan versiones
de motor consecutivas pero no idénticas -- se explica en el texto.

v3 (2026-08-26 continuación 2, tarea 18e) -- Recupero oficial MIGRADO a
`dias_atraso_cuota` (adoptado, ver PENDIENTES.md/SEGUIMIENTO.md), mismo
patrón que capital asegurado: JULIO (cerrado) usa el motor nuevo v2 de 18e
(`backtest_tarea18e_recupero_oficial_v2.py` -- ventana rodante de 12 meses
sin leak, día de semana, quincena, factor de cierre real en stock). AGOSTO
(en curso) sigue con el motor viejo (`dayslate`, `P_NO_PAGA_DIA0=13.38%`)
sin tocar -- mismo criterio de no recalibrar un mes a mitad de camino. Como
ambos enfoques miden ahora la MISMA población en julio (`dias_atraso_cuota`
define igual quién es "stock" y quién es "nuevos" sin importar si se mide
activación o rebaje), la composición asignada de julio es idéntica entre
los dos toggles -- solo cambia qué mide la curva sobre esa población.

No inventa metodología nueva -- reutiliza los CSV ya cacheados de sesiones
anteriores (curvas, poblaciones) y replica el loop de proyección ya validado
en motor_unificado.py. Escribe datos_artifact_julio_agosto.json, que
resumen_julio_agosto.html embebe inline (self-contained, sin fetch externo).
"""
import csv
import json
import collections
from datetime import date, timedelta

import curvas_crudas as CC
from motor_unificado import (P_ENTRADA, cargar_curva_stock, cargar_curva_nuevos,
                             cargar_factor_dia_mes, segmentar_calendario,
                             proyectar, acumular_real, lookup)
import backtest_tarea18e_recupero_oficial_v2 as R18E

AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
AVANCE_LABEL = {
    "a. avance <10%": "<10%", "b. avance 10-40%": "10-40%",
    "c. avance 40-70%": "40-70%", "d. avance 70%+": "70%+",
}
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]
TRAMO_LABEL = {"a. 1-8": "1-8 días", "b. 9-15": "9-15 días", "c. 16-30": "16-30 días"}

CORTE = date(2026, 8, 25)
DIR_F4 = "datos_tarea17_fase4"
DIR_18A = "datos_tarea18a"


def load_curva_stock(path, pct_col):
    out = {t: {a: [] for a in AVANCES} for t in TRAMOS}
    with open(path) as f:
        for row in csv.DictReader(f):
            out[row["tramo"]][row["avance_band"]].append([int(row["dia"]), float(row[pct_col])])
    for t in TRAMOS:
        for a in AVANCES:
            out[t][a].sort()
    return out


def load_curva_nuevos(path, pct_col, dia_col):
    out = {a: [] for a in AVANCES}
    with open(path) as f:
        for row in csv.DictReader(f):
            out[row["avance_band"]].append([int(row[dia_col]), float(row[pct_col])])
    for a in AVANCES:
        out[a].sort()
    return out


def load_stock_seg(path):
    out = {t: {a: 0.0 for a in AVANCES} for t in TRAMOS}
    with open(path) as f:
        for row in csv.DictReader(f):
            out[row["tramo"]][row["avance_band"]] = float(row["saldo_total"])
    return out


def total_saldo(stock_seg):
    return sum(stock_seg[t][a] for t in TRAMOS for a in AVANCES)


data = {}

# --- Curvas de maduración ---
# Asegurado: motor unificado v2 vigente -- nuevos se colapsa a "por avance"
# (sin día de semana) para el gráfico resumen; el detalle completo por día
# de semana está en proyectado_vs_real.html.
base_n, acts_n = CC.cargar_matriz()
curva_nuevos_agregada, _ = CC.calibrar(base_n, acts_n, "202507", "202606", con_dow=False, con_f=True)

# Recupero (tarea 18e, MIGRADO 2026-08-26): mismas matrices crudas de rebaje
# y misma ventana [202507,202606] (la que calibra julio, walk-forward
# [M-12,M-1]) que usa R18E para testear julio -- así la curva mostrada acá
# es EXACTAMENTE la que produjo el número de julio de la sección 2. Curva
# BASE (sin el factor de quincena/cierre todavía, igual criterio que
# "asegurado" muestra la curva de producción sin ese factor horneado).
curva_nuevos_recup_agregada, _ = CC.calibrar(R18E.base_n, R18E.acts_n, "202507", "202606",
                                              con_dow=False, con_f=True)

data["curvas"] = {
    "recupero": {
        "stock": {t: {a: sorted(R18E.curva_s_fija.get((t, a), {}).items()) for a in AVANCES} for t in TRAMOS},
        "nuevos": {a: sorted(curva_nuevos_recup_agregada.get(a, {}).items()) for a in AVANCES},
    },
    "asegurado": {
        "stock": load_curva_stock("datos_capital_asegurado/curva_unificada_stock_seg.csv",
                                   "pct_capital_asegurado_acum"),
        "nuevos": {a: sorted(curva_nuevos_agregada.get(a, {}).items()) for a in AVANCES},
    },
}

# --- Julio: composición de la asignación + resultado real vs proyectado ---
# Población: bajo `dias_atraso_cuota` "stock" y "calendario de nuevos" son
# EXACTAMENTE la misma definición para los dos enfoques (tarea 18e migró
# recupero a la misma base que ya usaba capital asegurado) -- se reusa la
# misma composición para ambos toggles, coherente con SEGUIMIENTO.md.
stock_julio_aseg = {t: {a: 0.0 for a in AVANCES} for t in TRAMOS}
for r in csv.DictReader(open(f"{DIR_18A}/stock_pob_7m.csv")):
    if r["periodo_meta"] == "202607":
        stock_julio_aseg[r["tramo"]][r["avance_band"]] = float(r["saldo_total"])
stock_julio_aseg_total = total_saldo(stock_julio_aseg)

calendario_julio_aseg_por_dia_entrada = collections.defaultdict(dict)
for r in csv.DictReader(open(f"{DIR_18A}/calendario_7m.csv")):
    if r["periodo"] == "202607":
        calendario_julio_aseg_por_dia_entrada[int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo_en_riesgo"])
cal_julio_aseg_total = sum(sum(v.values()) for v in calendario_julio_aseg_por_dia_entrada.values())

serie_julio = list(csv.DictReader(open("datos_backtest_unificado/serie_diaria_202607.csv")))
f_jul = serie_julio[-1]

INICIO_JUL = date(2026, 7, 1)
calendario_julio_aseg = {(INICIO_JUL + timedelta(days=d - 1)).isoformat(): v
                          for d, v in calendario_julio_aseg_por_dia_entrada.items()}

# Recupero oficial julio: MIGRADO 2026-08-26 (tarea 18e, adoptado) --
# `dias_atraso_cuota`, ventana rodante [202507,202606], día de semana,
# quincena, factor de cierre real en stock. Reusa el motor de
# backtest_tarea18e_recupero_oficial_v2.py tal cual (misma calibración que
# ya está en SEGUIMIENTO.md: proyectado S/3,882,039, real S/3,280,551,
# +18.3%). El motor viejo (`dayslate`, +17.6%) queda documentado en el
# texto del artifact, no en estos números.
filas_recup_jul, tasa_recup_jul = R18E.proyectar("202607", 31)
f_jul_recup = filas_recup_jul[-1]
rs_recup_jul = acumular_real(R18E.real_stock["202607"], 31)[-1]
rn_recup_jul = acumular_real(R18E.real_nuevos["202607"], 31)[-1]

data["julio"] = {
    "stock_seg": {"asegurado": stock_julio_aseg, "recupero": stock_julio_aseg},
    "calendario": {"asegurado": calendario_julio_aseg, "recupero": calendario_julio_aseg},
    "comparacion": {
        "asegurado": {
            "asignado": {
                "stock": round(stock_julio_aseg_total, 2), "nuevos": round(cal_julio_aseg_total, 2),
                "total": round(stock_julio_aseg_total + cal_julio_aseg_total, 2),
            },
            "proyectado": {
                "stock": round(float(f_jul["proy_stock"]), 2), "nuevos": round(float(f_jul["proy_nuevos"]), 2),
                "total": round(float(f_jul["proy_total"]), 2),
            },
            "real": {
                "stock": round(float(f_jul["real_stock"]), 2), "nuevos": round(float(f_jul["real_nuevos"]), 2),
                "total": round(float(f_jul["real_total"]), 2),
            },
        },
        "recupero": {
            "asignado": {
                "stock": round(stock_julio_aseg_total, 2), "nuevos": round(cal_julio_aseg_total, 2),
                "total": round(stock_julio_aseg_total + cal_julio_aseg_total, 2),
            },
            "proyectado": {
                "stock": round(f_jul_recup["proy_stock"], 2), "nuevos": round(f_jul_recup["proy_nuevos"], 2),
                "total": round(f_jul_recup["proy_total"], 2),
            },
            "real": {
                "stock": round(rs_recup_jul, 2), "nuevos": round(rn_recup_jul, 2),
                "total": round(rs_recup_jul + rn_recup_jul, 2),
            },
        },
    },
}

# --- Agosto: composición + trayectoria proyectada día a día, ambos enfoques ---
INICIO_AGO = date(2026, 8, 1)
N_DIAS = 31


def fecha_iso(dia):
    return (INICIO_AGO + timedelta(days=dia - 1)).isoformat()


# Asegurado -- meta YA FIJADA (v2/W3), sin tocar a mitad de mes.
stock_agosto_aseg, calendario_agosto_aseg = {}, collections.defaultdict(dict)
with open(f"{DIR_F4}/meta_agosto_insumos.csv") as f:
    for r in csv.DictReader(f):
        if r["tipo"] == "stock":
            stock_agosto_aseg[(r["tramo"], r["avance_band"])] = float(r["saldo"])
        else:
            calendario_agosto_aseg[int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo"])

curva_stock_aseg = cargar_curva_stock()
curva_nuevos_aseg = cargar_curva_nuevos()
f_dm_aseg = cargar_factor_dia_mes()
filas_aseg = proyectar(stock_agosto_aseg, segmentar_calendario(calendario_agosto_aseg, "202608"),
                        curva_stock_aseg, curva_nuevos_aseg, N_DIAS, f_dm=f_dm_aseg)

real_por_dia_aseg = collections.defaultdict(dict)
with open(f"{DIR_F4}/real_agosto.csv") as f:
    for r in csv.DictReader(f):
        real_por_dia_aseg[r["componente"]][int(r["dia"])] = float(r["saldo_activado_dia"])
real_stock_aseg = acumular_real(real_por_dia_aseg["stock"], N_DIAS)
real_nuevos_aseg = acumular_real(real_por_dia_aseg["nuevos"], N_DIAS)

proy_aseg = [{"dia": f["dia"], "fecha": fecha_iso(f["dia"]),
              "stock": round(f["proy_stock"], 2), "nuevos": round(f["proy_nuevos"], 2),
              "total": round(f["proy_total"], 2)} for f in filas_aseg]

calendario_aseg_por_fecha = {fecha_iso(d): v for d, v in calendario_agosto_aseg.items()}

# Recupero oficial -- mismas curvas/tasa de siempre (18e no ejecutada), real
# refrescado al mismo corte (tarea18d_real_agosto_recupero.sql).
stock_agosto_recup = load_stock_seg("datos_meta_agosto/stock_agosto_seg.csv")
curva_stock_recup_dict = {}
with open("datos_meta_julio/curva_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_stock_recup_dict.setdefault(row["tramo"], {}).setdefault(row["avance_band"], {})[int(row["dia"])] = float(row["pct_recupero_acum"])
curva_nuevos_recup_raw = {}
with open("datos_meta_julio/curva_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_nuevos_recup_raw.setdefault(row["avance_band"], {})[int(row["dia_desde_entrada"])] = float(row["pct_recupero_acum"])

calendario_agosto_recup = {}
with open("datos_meta_agosto/ago_calendario.csv") as f:
    for row in csv.DictReader(f):
        val = row["saldo_en_riesgo"]
        calendario_agosto_recup.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = float(val) if val else 0.0

P_NO_PAGA_DIA0 = 47966 / 358580  # 13.38%, tasa histórica del enfoque recupero (sin cambios)

proy_recup = []
acum_placeholder = None
for d in range(1, N_DIAS + 1):
    fecha = fecha_iso(d)
    proy_stock = sum(stock_agosto_recup[t][a] * lookup(curva_stock_recup_dict.get(t, {}).get(a, {}), d) / 100.0
                      for t in TRAMOS for a in AVANCES)
    proy_nuevos = 0.0
    for dd in range(1, d + 1):
        fecha_venc = fecha_iso(dd)
        for avance, saldo_riesgo in calendario_agosto_recup.get(fecha_venc, {}).items():
            dias_desde_entrada = d - dd
            if dias_desde_entrada < 1:
                continue
            pct = lookup(curva_nuevos_recup_raw.get(avance, {}), dias_desde_entrada)
            proy_nuevos += saldo_riesgo * P_NO_PAGA_DIA0 * pct / 100.0
    proy_recup.append({"dia": d, "fecha": fecha, "stock": round(proy_stock, 2),
                        "nuevos": round(proy_nuevos, 2), "total": round(proy_stock + proy_nuevos, 2)})

real_por_dia_recup = collections.defaultdict(dict)
with open("datos_meta_agosto/real_agosto_recupero.csv") as f:
    for r in csv.DictReader(f):
        real_por_dia_recup[r["componente"]][int(r["dia"])] = float(r["rebaje_dia"])
real_stock_recup = acumular_real(real_por_dia_recup["stock"], N_DIAS)
real_nuevos_recup = acumular_real(real_por_dia_recup["nuevos"], N_DIAS)

calendario_recup_por_fecha = calendario_agosto_recup

corte_idx = CORTE.day - 1

data["agosto"] = {
    "corte": CORTE.isoformat(),
    "asegurado": {
        "stock_seg": {t: {a: stock_agosto_aseg.get((t, a), 0.0) for a in AVANCES} for t in TRAMOS},
        "calendario": calendario_aseg_por_fecha,
        "proyeccion_diaria": proy_aseg,
        "real_diaria": [{"dia": d + 1, "stock": round(real_stock_aseg[d], 2),
                          "nuevos": round(real_nuevos_aseg[d], 2),
                          "total": round(real_stock_aseg[d] + real_nuevos_aseg[d], 2)} for d in range(N_DIAS)],
        "meta_total": round(filas_aseg[-1]["proy_total"], 2),
        "real_a_corte": round(real_stock_aseg[corte_idx] + real_nuevos_aseg[corte_idx], 2),
        "real_a_corte_stock": round(real_stock_aseg[corte_idx], 2),
        "real_a_corte_nuevos": round(real_nuevos_aseg[corte_idx], 2),
        "asignado_stock": round(sum(stock_agosto_aseg.values()), 2),
        "asignado_calendario": round(sum(sum(v.values()) for v in calendario_agosto_aseg.values()), 2),
    },
    "recupero": {
        "stock_seg": stock_agosto_recup,
        "calendario": calendario_recup_por_fecha,
        "proyeccion_diaria": proy_recup,
        "real_diaria": [{"dia": d + 1, "stock": round(real_stock_recup[d], 2),
                          "nuevos": round(real_nuevos_recup[d], 2),
                          "total": round(real_stock_recup[d] + real_nuevos_recup[d], 2)} for d in range(N_DIAS)],
        "meta_total": round(proy_recup[-1]["total"], 2),
        "real_a_corte": round(real_stock_recup[corte_idx] + real_nuevos_recup[corte_idx], 2),
        "real_a_corte_stock": round(real_stock_recup[corte_idx], 2),
        "real_a_corte_nuevos": round(real_nuevos_recup[corte_idx], 2),
        "asignado_stock": round(total_saldo(stock_agosto_recup), 2),
        "asignado_calendario": round(sum(sum(v.values()) for v in calendario_agosto_recup.values()), 2),
    },
}

# --- Factores del motor v2/v3 (para la sección "cómo se afina") ---
f_dm_stock = {}
try:
    from motor_unificado import cargar_factor_dia_mes_stock
    f_dm_stock = cargar_factor_dia_mes_stock()
except Exception:
    pass

data["factores"] = {
    "p_entrada": round(P_ENTRADA * 100, 4),
    "p_no_paga_recup": round(P_NO_PAGA_DIA0 * 100, 2),
    "p_entrada_recup_jul": round(tasa_recup_jul * 100, 2),
    "dia_mes_nuevos": f_dm_aseg,
    "dia_mes_stock_v3": f_dm_stock,
}

with open("datos_artifact_julio_agosto.json", "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))

print("OK -- datos_artifact_julio_agosto.json escrito")
print(f"Julio asegurado (v3) -- proyectado {data['julio']['comparacion']['asegurado']['proyectado']['total']:,.0f}"
      f"  real {data['julio']['comparacion']['asegurado']['real']['total']:,.0f}")
print(f"Julio recupero -- proyectado {data['julio']['comparacion']['recupero']['proyectado']['total']:,.0f}"
      f"  real {data['julio']['comparacion']['recupero']['real']['total']:,.0f}")
print(f"Agosto asegurado -- meta {data['agosto']['asegurado']['meta_total']:,.0f}"
      f"  real al corte {data['agosto']['asegurado']['real_a_corte']:,.0f}")
print(f"Agosto recupero  -- meta {data['agosto']['recupero']['meta_total']:,.0f}"
      f"  real al corte {data['agosto']['recupero']['real_a_corte']:,.0f}")

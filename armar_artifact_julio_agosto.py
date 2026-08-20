"""
Prepara los datos embebidos del artifact resumen_julio_agosto.html: curvas de
maduración (ambos enfoques), composición de la asignación de julio y agosto
(stock + calendario de nuevos), y la trayectoria día a día de la proyección de
agosto (mismo mecanismo que meta_agosto.py / meta_agosto_capital_asegurado.py).

No inventa metodología nueva -- reutiliza los CSV ya cacheados de sesiones
anteriores (curvas, poblaciones) y replica el loop de proyección ya validado.
Escribe datos_artifact_julio_agosto.json, que resumen_julio_agosto.html
embebe inline (self-contained, sin fetch externo).
"""
import csv
import json
from datetime import date, timedelta

AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
AVANCE_LABEL = {
    "a. avance <10%": "<10%", "b. avance 10-40%": "10-40%",
    "c. avance 40-70%": "40-70%", "d. avance 70%+": "70%+",
}
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]
TRAMO_LABEL = {"a. 1-8": "1-8 días", "b. 9-15": "9-15 días", "c. 16-30": "16-30 días"}
P_NO_PAGA = 47966 / 358580  # 13.38%, ver DECISIONES.md / BUGS.md bug 6
P_FANTASMA = 29845 / 353054  # 8.4534%, capa fantasma (bug 14, 2026-08-20) -- solo enfoque asegurado


def load_curva_stock(path, pct_col):
    out = {t: {a: [] for a in AVANCES} for t in TRAMOS}
    with open(path) as f:
        for row in csv.DictReader(f):
            out[row["tramo"]][row["avance_band"]].append(
                [int(row["dia"]), float(row[pct_col])]
            )
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


def load_calendario(path):
    out = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            val = row["saldo_en_riesgo"]
            out.setdefault(row["fechavencimiento"], {})[row["avance_band"]] = (
                float(val) if val else 0.0
            )
    return out


def lookup(curva, d):
    if d <= 0 or not curva:
        return 0.0
    curva_d = dict(curva)
    if d in curva_d:
        return curva_d[d]
    keys = [k for k in curva_d if k <= d]
    return curva_d[max(keys)] if keys else 0.0


def proyeccion_diaria(stock_seg, calendario, curva_stock, curva_nuevos, inicio, n_dias, con_fantasma=False):
    filas = []
    for d in range(1, n_dias + 1):
        fecha = inicio + timedelta(days=d - 1)
        proy_stock = sum(
            stock_seg[t][a] * lookup(curva_stock[t][a], d) / 100.0
            for t in TRAMOS for a in AVANCES
        )
        proy_nuevos = 0.0
        proy_fantasma = 0.0
        for dd in range(1, d + 1):
            fecha_venc = (inicio + timedelta(days=dd - 1)).isoformat()
            riesgo = calendario.get(fecha_venc, {})
            dias_desde_entrada = d - dd
            if dias_desde_entrada < 1:
                continue
            for avance, saldo_riesgo in riesgo.items():
                pct = lookup(curva_nuevos[avance], dias_desde_entrada)
                proy_nuevos += saldo_riesgo * P_NO_PAGA * pct / 100.0
            # capa fantasma (bug 14): 100% activado el dia siguiente al vencimiento, sin curva
            if con_fantasma:
                proy_fantasma += sum(riesgo.values()) * P_FANTASMA
        fila = {
            "dia": d, "fecha": fecha.isoformat(),
            "stock": round(proy_stock, 2), "nuevos": round(proy_nuevos, 2),
        }
        if con_fantasma:
            fila["fantasma"] = round(proy_fantasma, 2)
            fila["total"] = round(proy_stock + proy_nuevos + proy_fantasma, 2)
        else:
            fila["total"] = round(proy_stock + proy_nuevos, 2)
        filas.append(fila)
    return filas


data = {}

# --- Curvas de maduración (calibradas sobre 14 meses, sin cambios) ---
data["curvas"] = {
    "recupero": {
        "stock": load_curva_stock("datos_meta_julio/curva_stock_seg.csv", "pct_recupero_acum"),
        "nuevos": load_curva_nuevos("datos_meta_julio/curva_nuevos_seg.csv", "pct_recupero_acum", "dia_desde_entrada"),
    },
    "asegurado": {
        "stock": load_curva_stock("datos_capital_asegurado/curva_asegurado_stock_seg.csv", "pct_capital_asegurado_acum"),
        "nuevos": load_curva_nuevos("datos_capital_asegurado/curva_asegurado_nuevos_seg.csv", "pct_capital_asegurado_acum", "dia"),
    },
}

# --- Julio: composicion de la asignacion + resultado real vs proyectado ---
stock_julio_recup = load_stock_seg("datos_meta_julio/stock_julio_seg.csv")
stock_julio_aseg = load_stock_seg("datos_avance_capital_asegurado_julio/stock_julio_aseg_seg.csv")
calendario_julio = load_calendario("datos_meta_julio/jul_calendario.csv")

def total_saldo(stock_seg):
    return sum(stock_seg[t][a] for t in TRAMOS for a in AVANCES)

# nuevos "asignado" = saldo real de la poblacion que entro en mora en julio (no
# el calendario completo, que incluye a quien SI pago a tiempo) -- query J2
# (asegurado, dia 2-31) y J4b (recupero, dia 1-31, sin ajuste bug 12) de
# cierre_julio.sql, corridas 2026-08-19.
NUEVOS_ASIGNADO_ASEG = 9567714.05
NUEVOS_ASIGNADO_RECUP = 13116158.27

# Capa fantasma julio (bug 14, 2026-08-20) -- solo enfoque asegurado. Proyectado =
# P_FANTASMA x calendario total (vencimientos 1-jul a 30-jul, excluyendo stock);
# real = creditos que pagaron 1 dia tarde sin que dayslate los viera, mismo criterio.
# Ver investigacion_capa_fantasma.sql Q3/Q4 y reconciliacion_vw_seguimiento_temprana.md.
PROY_FANTASMA_JULIO = 6226704.0
REAL_FANTASMA_JULIO = 5742740.84
# Real stock+nuevos verificado independientemente 2026-08-20 (cierre_julio.sql J1/J2
# re-corrido) -- reemplaza el valor anterior (10,789,362.19, con signo de error mal
# calculado en SEGUIMIENTO.md, ver bug 14).
REAL_STOCK_ASEG_JULIO = 3137199.21
REAL_NUEVOS_ASEG_JULIO = 7633719.13

stock_asignado_aseg = total_saldo(stock_julio_aseg)
stock_asignado_recup = total_saldo(stock_julio_recup)

data["julio"] = {
    "stock_recup": stock_julio_recup,
    "stock_aseg": stock_julio_aseg,
    "calendario": calendario_julio,
    "comparacion": {
        "asegurado": {
            "asignado": {
                "stock": round(stock_asignado_aseg, 2), "nuevos": NUEVOS_ASIGNADO_ASEG,
                "total": round(stock_asignado_aseg + NUEVOS_ASIGNADO_ASEG, 2),
            },
            "proyectado": {
                "stock": 3105418, "nuevos": 7200813, "fantasma": PROY_FANTASMA_JULIO,
                "total": round(3105418 + 7200813 + PROY_FANTASMA_JULIO, 2),
            },
            "real": {
                "stock": REAL_STOCK_ASEG_JULIO, "nuevos": REAL_NUEVOS_ASEG_JULIO,
                "fantasma": REAL_FANTASMA_JULIO,
                "total": round(REAL_STOCK_ASEG_JULIO + REAL_NUEVOS_ASEG_JULIO + REAL_FANTASMA_JULIO, 2),
            },
        },
        "recupero": {
            "asignado": {
                "stock": round(stock_asignado_recup, 2), "nuevos": NUEVOS_ASIGNADO_RECUP,
                "total": round(stock_asignado_recup + NUEVOS_ASIGNADO_RECUP, 2),
            },
            "proyectado": {"stock": 426651, "nuevos": 1349523, "total": 1776174},
            "real": {"stock": 435390.98, "nuevos": 1653520.25, "total": 2088911.23},
        },
    },
}

# --- Agosto: composicion + calendario + trayectoria proyectada dia a dia ---
stock_agosto_recup = load_stock_seg("datos_meta_agosto/stock_agosto_seg.csv")
stock_agosto_aseg = load_stock_seg("datos_avance_capital_asegurado_agosto/stock_agosto_aseg_seg.csv")
calendario_agosto = load_calendario("datos_meta_agosto/ago_calendario.csv")

INICIO_AGO = date(2026, 8, 1)
HOY_AGO = date(2026, 8, 18)

proy_recup = proyeccion_diaria(
    stock_agosto_recup, calendario_agosto,
    data["curvas"]["recupero"]["stock"], data["curvas"]["recupero"]["nuevos"],
    INICIO_AGO, 31,
)
proy_aseg = proyeccion_diaria(
    stock_agosto_aseg, calendario_agosto,
    data["curvas"]["asegurado"]["stock"], data["curvas"]["asegurado"]["nuevos"],
    INICIO_AGO, 31, con_fantasma=True,
)

# Real fantasma agosto a la fecha (1-18 ago, query 2026-08-20, mismo patron que julio) --
# ver meta_agosto_capital_asegurado.py v2 y reconciliacion_vw_seguimiento_temprana.md.
REAL_FANTASMA_AGO_A_HOY = 2827691.80

data["agosto"] = {
    "stock_recup": stock_agosto_recup,
    "stock_aseg": stock_agosto_aseg,
    "calendario": calendario_agosto,
    "corte_real": "2026-08-18",
    "tasa_no_paga": round(P_NO_PAGA * 100, 2),
    "tasa_fantasma": round(P_FANTASMA * 100, 4),
    "proyeccion_diaria": {"recupero": proy_recup, "asegurado": proy_aseg},
    "real_a_hoy": {
        "asegurado": {
            "stock": 2605896.73, "nuevos": 4189176.85, "fantasma": REAL_FANTASMA_AGO_A_HOY,
            "total": round(2605896.73 + 4189176.85 + REAL_FANTASMA_AGO_A_HOY, 2),
        },
        "recupero": {"stock": 447341.09, "nuevos": 699769.22, "total": 1147110.31},
    },
}

with open("datos_artifact_julio_agosto.json", "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))

print("OK -- datos_artifact_julio_agosto.json escrito")
print(f"Julio asegurado total proyectado (con fantasma): {data['julio']['comparacion']['asegurado']['proyectado']['total']:,.0f}")
print(f"Julio asegurado total real (con fantasma): {data['julio']['comparacion']['asegurado']['real']['total']:,.0f}")
print(f"Agosto asegurado proyectado dia31 (con fantasma): {proy_aseg[-1]['total']:,.0f}")
print(f"Agosto asegurado real a hoy (con fantasma): {data['agosto']['real_a_hoy']['asegurado']['total']:,.0f}")
print(f"Agosto recupero proyectado dia31: {proy_recup[-1]['total']:,.0f}")

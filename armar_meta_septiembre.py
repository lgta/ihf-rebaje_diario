"""
ARTIFACT «Meta de septiembre» (meta_septiembre.html): la meta de septiembre 2026 re-fijada con el
motor v2, de dónde sale, por qué se recalibró el modelo y el control a la fecha. Este script solo
inyecta los datos en el HTML (entre /*DATOS*/ y /*/DATOS*/); el texto se edita a mano.

    python armar_meta_septiembre.py <ultimo dia completo>

Antes, el real del día (la foto del día en curso está incompleta: último día completo = el penúltimo):
    bash scripts/run_athena.sh tarea25_real_v2_septiembre.sql > datos_tarea25/real_v2_septiembre.csv
    bash scripts/run_athena.sh tarea19_real_septiembre.sql > datos_tarea19/real_septiembre.csv
    python seguimiento_septiembre.py <dia>        (referencia contra la publicada v1)
Después, republicar el HTML con url= del artifact.

El real y la descomposición de nuevos salen de las mismas funciones que `seguimiento_v2.py`, así que
el artifact y el seguimiento dan el mismo número por construcción.
"""
import csv
import datetime as dt
import json
import sys

import motor_v2 as MV
import seguimiento_v2 as SG
from motor_unificado import acumular_real

PERIODO = "202609"
INSUMOS = "datos_tarea24/v2_septiembre_al_1.csv"
REAL = "datos_tarea25/real_v2_septiembre.csv"
REAL_V1 = "datos_tarea19/seguimiento_septiembre.csv"   # la escribe seguimiento_septiembre.py
BACKTEST = "datos_tarea25/backtest_ancla.csv"
HTML = "meta_septiembre.html"
INI, FIN = "/*DATOS*/", "/*/DATOS*/"

# Puente de la publicada a la vigente: datos_tarea25/meta_septiembre_v2_dia1.log
# (meta_septiembre_v2_dia1.py). La meta se fijó una vez: estos números no cambian con el seguimiento.
# (paso, meta, stock, nuevos, tasa de entrada)
PUENTE = {
    "act": [
        ("Publicada el 1-sep (v1)", 20477271, 2241903, 18235368, 0.2491),
        ("v1 rearmada con los datos del 1-sep", 20497476, 2227169, 18270308, 0.2494),
        ("Antiguo = en mora el día 1, como la vista", 19815529, 3497231, 16318298, 0.2436),
        ("Reenganches dentro de la calibración", 19467964, 3529832, 15938132, 0.2350),
        ("Tasa de entrada sobre el saldo que multiplica", 17504932, 3529832, 13975100, 0.2061),
    ],
    "reb": [
        ("Publicada el 1-sep (v1)", 3928776, 537381, 3391395, 0.2491),
        ("v1 rearmada con los datos del 1-sep", 3946246, 535197, 3411050, 0.2494),
        ("Antiguo = en mora el día 1, como la vista", 3856633, 827823, 3028809, 0.2436),
        ("Reenganches dentro de la calibración", 3692262, 821765, 2870496, 0.2350),
        ("Tasa de entrada sobre el saldo que multiplica", 3338715, 821765, 2516950, 0.2061),
    ],
}
# Mismo log: la definición del día 1 con el arrastre por DNI DENTRO (lo que pesa sacarlo).
ARRASTRE_DENTRO = {"act": 19846681, "reb": 3863937}
META_V1 = {"act": 20477271, "reb": 3928776}
# Cuadre de antiguos de septiembre contra vw_seguimiento_diario_cohorte_tramo (tarea 24, ESTADO.md 13-sep).
CUADRE = {"antes_pct": -23.9, "v2": {"creditos": 2837, "saldo": 4930217},
          "vista": {"creditos": 2790, "saldo": 4904773}, "identicos": [2749, 2751]}


def backtest():
    """[fix] = calendario anclado x tasa anclada (como se arma la meta); [anc] = la tasa vieja."""
    out = {}
    with open(BACKTEST) as f:
        for r in csv.DictReader(f):
            if r["variante"] not in ("fix", "anc"):
                continue
            out.setdefault(r["medida"], {}).setdefault(r["variante"], []).append({
                "periodo": r["periodo"], "proy": round(float(r["proy_total"])),
                "real": round(float(r["real_total"])), "err": round(float(r["err_total"]), 2),
                "err_stock": round(float(r["err_stock"]), 2), "err_nuevos": round(float(r["err_nuevos"]), 2),
                "corr": round(float(r["corr_total"]), 3), "r12": round(float(r["ratio_d12"]), 3)})
    return out


def v1(n):
    s = {"alfa": [], "recupero": []}
    with open(REAL_V1) as f:
        for r in csv.DictReader(f):
            s[r["enfoque"]].append(r)
    dias = min(len(s["alfa"]), n)
    if dias < n:
        print(f"OJO: la referencia v1 llega al día {dias}, no al {n} (re-correr seguimiento_septiembre.py {n})")
    par = lambda filas: [[round(float(r["proy_total"])), round(float(r["real_total"]))] for r in filas[:dias]]
    return {"corte": dias, "act": par(s["alfa"]), "reb": par(s["recupero"]), "meta_mes": META_V1}


def main(n):
    meta, _ = SG.leer_meta(PERIODO, INSUMOS)
    real, entradas = SG.leer_real(REAL)
    stock, cal = MV.leer_insumos(INSUMOS)
    d1 = sum(MV.leer_insumos(INSUMOS, solo_d1=True)[0].values())

    series = {}
    for m in ("act", "reb"):
        rs, rn = acumular_real(real[m]["stock"], n), acumular_real(real[m]["nuevos"], n)
        series[m] = [[round(rs[i]), round(rn[i])] for i in range(n)]
    s_alfa = [{"real_nuevos": series["act"][-1][1], "proy_nuevos": meta["act"][n - 1]["proy_nuevos"]}]
    desc = SG.descomposicion(PERIODO, INSUMOS, s_alfa, entradas, n)

    datos = {
        "corte": n, "generado": dt.date.today().isoformat(),
        "tasa": round(desc["tasa"], 6), "tasa_dias": round(desc["tasa_dias"], 6),
        "insumos": {"stock": round(sum(stock.values())), "stock_d1": round(d1),
                    "calendario": round(sum(sum(v.values()) for v in cal.values()))},
        "meta": {m: [[round(x["proy_stock"]), round(x["proy_nuevos"])] for x in meta[m]] for m in ("act", "reb")},
        "real": series,
        "nuevos": {k: (round(v, 6) if isinstance(v, float) and v < 1 else round(v) if isinstance(v, float) else v)
                   for k, v in desc.items()},
        "v1": v1(n),
        "puente": PUENTE, "arrastre_dentro": ARRASTRE_DENTRO,
        "backtest": backtest(), "cuadre": CUADRE,
    }

    with open(HTML, encoding="utf-8") as f:
        s = f.read()
    i, j = s.index(INI), s.index(FIN)
    s = s[:i + len(INI)] + json.dumps(datos, ensure_ascii=False, separators=(",", ":")) + s[j:]
    with open(HTML, "w", encoding="utf-8") as f:
        f.write(s)
    print(f"{HTML}: {len(s):,} bytes (datos al día {n} inyectados)")

    for m, nom in (("act", "capital asegurado"), ("reb", "recupero")):
        p = meta[m][n - 1]
        r = series[m][-1]
        print(f"  {nom:<17} real S/ {sum(r):>11,.0f}  proy S/ {p['proy_total']:>11,.0f}  "
              f"real/proy {sum(r)/p['proy_total']:.3f}  (stock {r[0]/p['proy_stock']:.3f}, "
              f"nuevos {r[1]/p['proy_nuevos']:.3f})")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(int(sys.argv[1]))

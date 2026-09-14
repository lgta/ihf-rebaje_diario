"""
TAREA 24 -- SEPTIEMBRE 2026 CON LA DEFINICION v2 DE ANTIGUO, EN PARALELO.

La meta publicada el 1-sep NO se toca (S/20,477,271 alfa, S/3,928,776
recupero): se fijo con v1 y se sigue con v1 (`seguimiento_septiembre.py`). Esto
es el "v2 en paralelo para comparar" del plan de tarea 24: cuanto habria dado la
meta con la definicion nueva, y como viene el real v2 contra ella.

Tres metas lado a lado, para separar los dos efectos:
  v1 publicada    la del 1-sep (meta_septiembre_*.py), insumos de ese dia
  v1 hoy          el mismo motor, con los insumos y matrices de HOY
                  (tarea24_v2_*.sql). v1 publicada -> v1 hoy es RE-MEDICION: el
                  calendario prospectivo pierde a los que terminaron de pagar en
                  septiembre (ya figuran COMPLETED) y Mambu se re-expresa.
  v2              definicion nueva, mismos insumos y matrices de hoy. v1 hoy ->
                  v2 es el efecto de la DEFINICION, limpio.

Mismo protocolo que la meta publicada: nuevos (curva y tasa) en [202508,
202607]; stock con ventana FIJA 202504-202606; arrastre fuera y reenganches
fuera en v2. El modo de la cohorte d1 (S0/S1/S2, ver backtest_tarea24_v1_v2.py)
se pasa como argumento: `python meta_septiembre_v2.py S2 12` (modo, ultimo dia
completo del real).
"""
import collections
import csv
import statistics
import sys

import curvas_crudas as CC
import curvas_crudas_stock as CS
import curvas_v2 as V
import meta_septiembre_capital_asegurado as ALFA
import meta_septiembre_recupero as RECUPERO
from motor_unificado import acumular_real, dow_venc, proyectar, segmentar_calendario

PERIODO, N = "202609", 30
VENTANA = ("202508", "202607")
FIJA_STOCK = ("202504", "202606")
MODO = sys.argv[1] if len(sys.argv) > 1 else "S2"
ULTIMO_DIA = int(sys.argv[2]) if len(sys.argv) > 2 else 12
INSUMOS = "datos_tarea24/v2_septiembre.csv"
SALIDA = "datos_tarea24/meta_septiembre_v2.csv"

with open(INSUMOS) as f:
    FILAS_INS = list(csv.DictReader(f))


def insumos(definicion, arrastre, reeng, seg_d1=False, solo_d1=None):
    stock = collections.defaultdict(float)
    cal = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in FILAS_INS:
        if r["bloque"] != "insumo" or r["definicion"] != definicion:
            continue
        if not reeng and r["reeng"] == "1":
            continue
        if r["componente"] == "stock":
            if arrastre == "fuera" and r["arrastre"] == "1":
                continue
            if solo_d1 is not None and (r["d1"] == "1") != solo_d1:
                continue
            tramo = V.TRAMO_D1 if (seg_d1 and r["d1"] == "1") else r["tramo"]
            stock[(tramo, r["avance_band"])] += float(r["saldo"])
        else:
            cal[int(r["dia"])][r["avance_band"]] += float(r["saldo"])
    return dict(stock), {d: dict(v) for d, v in cal.items()}


def curvas(definicion, medida, modo, arrastre, reeng=False):
    """Curvas y tasa con las ventanas de la meta de septiembre: nuevos (curva y tasa) en
    VENTANA, stock en FIJA_STOCK. En S2 la curva de stock se calibra sin la cohorte d1."""
    base_s, acts_s = V.stock_matriz(definicion, medida, arrastre, reeng, seg_d1=(modo == "S1"),
                                    solo_d1=(False if modo == "S2" else None))
    curva_s, f_s = CS.calibrar(base_s, acts_s, *FIJA_STOCK, con_f=True, modo_cierre="real")
    base_n, acts_n = V.nuevos_matriz(definicion, medida, arrastre, reeng)
    curva_n, f_n = CC.calibrar(base_n, acts_n, *VENTANA, con_dow=True, con_f=True,
                               granularidad="estructural")
    p = V.tasa(V.tasa_mensual(definicion, arrastre, reeng), *VENTANA)
    return curva_s, f_s, curva_n, f_n, p


def proyectar_mes(c, stock, cal, d1_por_banda=None):
    """Serie diaria del mes con las curvas `c` de `curvas()`. `d1_por_banda` es la cohorte
    que entro en mora el dia 1 (modo S2): se proyecta con la curva de NUEVOS y su saldo real,
    sin tasa, y se suma al stock."""
    curva_s, f_s, curva_n, f_n, p = c
    filas = proyectar(stock, segmentar_calendario(cal, PERIODO), curva_s, curva_n, N,
                      p_entrada=p, f_dm=f_n, f_dm_stock=f_s)
    if d1_por_banda:
        dw = dow_venc(PERIODO, 1)
        extra = proyectar({}, {1: {(b, dw): s for b, s in d1_por_banda.items()}}, {}, curva_n, N,
                          p_entrada=1.0, f_dm=f_n)
        for fila, e in zip(filas, extra):
            fila["proy_stock"] += e["proy_nuevos"]
            fila["proy_total"] += e["proy_nuevos"]
    return filas


def por_banda(stock):
    """{(tramo, banda): saldo} -> {banda: saldo}."""
    out = collections.defaultdict(float)
    for (_t, b), s in stock.items():
        out[b] += s
    return dict(out)


def meta(definicion, medida, modo, arrastre, reeng=False):
    c = curvas(definicion, medida, modo, arrastre, reeng)
    stock, cal = insumos(definicion, arrastre, reeng, seg_d1=(modo == "S1"),
                         solo_d1=(False if modo == "S2" else None))
    d1 = por_banda(insumos(definicion, arrastre, reeng, solo_d1=True)[0]) if modo == "S2" else None
    filas = proyectar_mes(c, stock, cal, d1)
    return filas, c[4], sum(stock.values()), sum(sum(v.values()) for v in cal.values())


def real_v1(medida):
    col = "saldo_activado_dia" if medida == "act" else "rebaje_dia"
    out = {"stock": {}, "nuevos": {}}
    with open("datos_tarea19/real_septiembre.csv") as f:
        for r in csv.DictReader(f):
            out[r["componente"]][int(r["dia"])] = float(r[col])
    return out


def real_v2(medida, arrastre="fuera", reeng=False):
    col = "saldo" if medida == "act" else "rebaje"
    out = {"stock": collections.defaultdict(float), "nuevos": collections.defaultdict(float)}
    for r in FILAS_INS:
        if r["bloque"] != "real" or (not reeng and r["reeng"] == "1"):
            continue
        if arrastre == "fuera" and r["arrastre"] == "1":
            continue
        out[r["componente"]][int(r["dia"])] += float(r[col] or 0)
    return out


def avance(filas, real):
    n = ULTIMO_DIA
    rs, rn = acumular_real(real["stock"], n), acumular_real(real["nuevos"], n)
    rt = [a + b for a, b in zip(rs, rn)]
    pt = [x["proy_total"] for x in filas[:n]]
    inc = lambda s: [s[0]] + [s[i] - s[i - 1] for i in range(1, len(s))]
    return rt[-1] / pt[-1], statistics.correlation(inc(pt), inc(rt)), rt[-1], pt[-1]


if __name__ == "__main__":
    salida = []
    for medida, titulo, pub in (("act", "CAPITAL ASEGURADO (Enfoque alfa)", ALFA.filas),
                                ("reb", "RECUPERO OFICIAL (rebaje)", RECUPERO.filas)):
        v1h, p1, s1, c1 = meta("v1", medida, "S0", "dentro")
        v2, p2, s2, c2 = meta("v2", medida, MODO, "fuera")
        print("=" * 104)
        print(f"{titulo} -- SEPTIEMBRE 2026, v1 vs. v2 (cohorte d1 en modo {MODO}), real al {ULTIMO_DIA:02d}-sep")
        print("=" * 104)
        print(f"{'':<16} | {'meta del mes':>13} {'stock':>12} {'nuevos':>12} | {'tasa':>7} {'pob. stock':>12} "
              f"{'calendario':>12} | {'real/proy d'+str(ULTIMO_DIA):>12} {'corr diaria':>11}")
        for nombre, filas, p, s, c, real in (
                ("v1 publicada", pub, ALFA.TASAS[ALFA.MODO_TASA], sum(ALFA.stock_sep.values()),
                 sum(sum(v.values()) for v in ALFA.calendario_sep.values()), real_v1(medida)),
                ("v1 hoy", v1h, p1, s1, c1, real_v1(medida)),
                (f"v2 ({MODO})", v2, p2, s2, c2, real_v2(medida))):
            ratio, corr, rt, pt = avance(filas, real)
            u = filas[-1]
            print(f"{nombre:<16} | {u['proy_total']:>13,.0f} {u['proy_stock']:>12,.0f} {u['proy_nuevos']:>12,.0f} | "
                  f"{100*p:>6.2f}% {s:>12,.0f} {c:>12,.0f} | {ratio:>12.3f} {corr:>11.3f}")
            for fila in filas:
                salida.append({"medida": medida, "version": nombre, "dia": fila["dia"],
                               "proy_stock": round(fila["proy_stock"], 2),
                               "proy_nuevos": round(fila["proy_nuevos"], 2),
                               "proy_total": round(fila["proy_total"], 2)})
        d_def = v2[-1]["proy_total"] / v1h[-1]["proy_total"] - 1
        d_rem = v1h[-1]["proy_total"] / pub[-1]["proy_total"] - 1
        print(f"  re-medicion (v1 publicada -> v1 hoy): {100*d_rem:+.1f}%   definicion (v1 hoy -> v2): {100*d_def:+.1f}%")
        print()
    with open(SALIDA, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(salida[0].keys()))
        w.writeheader()
        w.writerows(salida)
    print(f"Series en {SALIDA}")

"""
TAREA 24 -- BACKTEST v1 vs. v2 de la definicion de antiguo, 8 meses
(202601-202608), los DOS enfoques, las DOS metricas de CLAUDE.md.

  v1 = antiguo es quien esta en mora 1-30 al CIERRE del mes anterior (produccion)
  v2 = antiguo es quien esta en mora 1-30 el DIA 1 del mes (la vista oficial;
       decision del usuario 2026-09-13)

Todo sale de las matrices de `tarea24_v2_*.sql` -- las dos definiciones de la
misma foto de Mambu, asi que la diferencia v1 -> v2 es solo de definicion, no de
re-expresion. Mismo protocolo que el backtest oficial: nuevos (curva y tasa)
rueda [M-12, M-1]; stock con ventana FIJA 202504-202606; factor de quincena y
fin de mes en nuevos (W3) y de cierre real en stock (18g).

QUE SE COMPARA
  v1 pub   v1 como se publico: el calendario suma las DOS cuotas del credito
           que entra el dia 1 y el 31 (calendario_8m), la tasa cuenta una.
  v1 c1    v1 con una cuota por credito en el calendario -- la misma base que
           la tasa; es la correccion de bug 23 (dos cuotas en el mismo mes) que
           tarea 21 dejo sin adoptar. Aisla su efecto en el backtest.
  v2 S0    stock v2 con curva (tramo, banda): la cohorte que entra el dia 1
           queda mezclada en el tramo 1-8.
  v2 S1    la cohorte d1 como tramo propio de la curva de stock.
  v2 S2    la cohorte d1 proyectada con la curva de NUEVOS (banda x dia de
           semana del vencimiento, factor por dia del mes), con su saldo real
           -- sin tasa, porque el dia 1 ya se sabe quien entro.
Los tres v2 con arrastre FUERA (como la vista) y sin reenganches (produccion).
Sensibilidades: `python backtest_tarea24_v1_v2.py sens` corre ademas la mejor
variante con el arrastre dentro y con los reenganches incluidos.

COMO LEERLO (CLAUDE.md)
  - La comparable entre definiciones es la columna TOTAL: v1 y v2 reparten
    distinto la masa entre stock y nuevos (la cohorte d1 cambia de lado).
  - S0/S1/S2 son variantes de FORMA dentro de v2 (el real es el mismo): se
    deciden con las metricas DIARIAS de stock y total, no con el cierre.
  - Cambiar v1 -> v2 corrige QUIEN entra al universo: se adopta aunque el error
    suba. Pero la adopcion la decide el usuario.
"""
import collections
import csv
import os
import statistics
import sys

import curvas_crudas as CC
import curvas_crudas_stock as CS
import curvas_v2 as V
from motor_unificado import acumular_real, dow_venc, proyectar, segmentar_calendario

MESES = [("202601", 31), ("202602", 28), ("202603", 31), ("202604", 30),
         ("202605", 31), ("202606", 30), ("202607", 31), ("202608", 31)]
FIJA_STOCK = ("202504", "202606")
SALIDA = "datos_tarea24/backtest_v1_v2.csv"

# Error de fin de mes publicado por backtest_capital_asegurado_unificado.py
# (tasa por soles, 2026-09-02) -- referencia para el control de v1.
PUBLICADO_ALFA = {"202601": -0.6, "202602": -10.4, "202603": -3.4, "202604": -1.0,
                  "202605": 0.6, "202606": 8.7, "202607": 8.9, "202608": 2.7}

VARIANTES = {
    # clave: (etiqueta, definicion, modo_stock, arrastre, reeng, cal_todas_las_cuotas)
    "v1pub": ("v1 como se publico", "v1", "S0", "dentro", False, True),
    "v1c1":  ("v1, una cuota por credito", "v1", "S0", "dentro", False, False),
    "v2s0":  ("v2, d1 dentro del tramo 1-8", "v2", "S0", "fuera", False, False),
    "v2s1":  ("v2, d1 como tramo propio", "v2", "S1", "fuera", False, False),
    "v2s2":  ("v2, d1 con la curva de nuevos", "v2", "S2", "fuera", False, False),
}

_curvas_n = {}


def curva_nuevos(definicion, medida, arrastre, reeng, periodo):
    clave = (definicion, medida, arrastre, reeng, periodo)
    if clave not in _curvas_n:
        base, acts = V.nuevos_matriz(definicion, medida, arrastre, reeng)
        _curvas_n[clave] = CC.calibrar(base, acts, *V.ventana(periodo), con_dow=True, con_f=True,
                                       granularidad="estructural")
    return _curvas_n[clave]


def correr_variante(clave, medida, var=None):
    etiqueta, definicion, modo, arrastre, reeng, cal_todas = var or VARIANTES[clave]

    # stock: curva con ventana FIJA; en S2 sin la cohorte d1 (va por la de nuevos)
    base_s, acts_s = V.stock_matriz(definicion, medida, arrastre, reeng, seg_d1=(modo == "S1"),
                                    solo_d1=(False if modo == "S2" else None))
    curva_s, f_s = CS.calibrar(base_s, acts_s, *FIJA_STOCK, con_f=True, modo_cierre="real")
    _, acts_real_s = V.stock_matriz(definicion, medida, arrastre, reeng)      # el real: todo el stock
    base_d1, _ = V.stock_matriz(definicion, medida, arrastre, reeng, solo_d1=True)

    tm = V.tasa_mensual(definicion, arrastre, reeng)
    real_n = V.nuevos_real(definicion, medida, arrastre, reeng)

    filas_mes = []
    for periodo, n in MESES:
        curva_n, f_n = curva_nuevos(definicion, medida, arrastre, reeng, periodo)
        p_ent = V.tasa(tm, *V.ventana(periodo))
        cal = segmentar_calendario(V.calendario(definicion, periodo, reeng, cal_todas), periodo)
        filas = proyectar(V.poblacion(base_s, periodo), cal, curva_s, curva_n, n,
                          p_entrada=p_ent, f_dm=f_n, f_dm_stock=f_s)
        if modo == "S2":
            d1 = V.cohorte_d1(base_d1, periodo)
            if d1:
                dw = dow_venc(periodo, 1)
                extra = proyectar({}, {1: {(b, dw): s for b, s in d1.items()}}, {}, curva_n, n,
                                  p_entrada=1.0, f_dm=f_n)
                for fila, e in zip(filas, extra):
                    fila["proy_stock"] += e["proy_nuevos"]
                    fila["proy_total"] += e["proy_nuevos"]
        rs = acumular_real(V.real_por_dia(acts_real_s, periodo), n)
        rn = acumular_real(real_n.get(periodo, {}), n)
        for i, fila in enumerate(filas):
            fila["real_stock"], fila["real_nuevos"] = rs[i], rn[i]
            fila["real_total"] = rs[i] + rn[i]
        filas_mes.append((periodo, n, filas, p_ent))
    return etiqueta, filas_mes


def metricas(filas, n):
    inc = lambda s: [s[0]] + [s[i] - s[i - 1] for i in range(1, n)]
    out = {}
    for c in ("stock", "nuevos", "total"):
        p = [x[f"proy_{c}"] for x in filas]
        r = [x[f"real_{c}"] for x in filas]
        out[f"err_{c}"] = 100 * (p[-1] - r[-1]) / r[-1]
        out[f"corr_{c}"] = statistics.correlation(inc(p), inc(r))
        out[f"mae_{c}"] = sum(abs(a - b) for a, b in zip(inc(p), inc(r))) / n
        out[f"proy_{c}"], out[f"real_{c}"] = p[-1], r[-1]
    return out


def reporte(clave, medida, var=None):
    etiqueta, filas_mes = correr_variante(clave, medida, var)
    print(f"\n--- [{clave}] {etiqueta} ---")
    print(f"{'mes':<7} | {'proyectado':>12} {'real':>12} {'error':>7} | {'err stk':>8} {'err nvo':>8} | "
          f"{'corr tot':>8} {'corr stk':>8} {'corr nvo':>8} | {'MAE tot':>9} | {'tasa':>6}"
          + (" | publicado" if (clave == "v1pub" and medida == "act") else ""))
    res = []
    for periodo, n, filas, p_ent in filas_mes:
        m = metricas(filas, n)
        m.update(medida=medida, variante=clave, periodo=periodo, tasa=p_ent)
        res.append(m)
        pub = f" | {PUBLICADO_ALFA[periodo]:>+8.1f}%" if (clave == "v1pub" and medida == "act") else ""
        print(f"{periodo:<7} | {m['proy_total']:>12,.0f} {m['real_total']:>12,.0f} {m['err_total']:>+6.1f}% | "
              f"{m['err_stock']:>+7.1f}% {m['err_nuevos']:>+7.1f}% | {m['corr_total']:>8.3f} "
              f"{m['corr_stock']:>8.3f} {m['corr_nuevos']:>8.3f} | {m['mae_total']:>9,.0f} | "
              f"{100*p_ent:>5.2f}%{pub}")
    media = lambda k, f=lambda x: x: sum(f(r[k]) for r in res) / len(res)
    print(f"{'MEDIA':<7} | {'':>12} {'':>12} {media('err_total', abs):>6.2f}% | "
          f"{media('err_stock', abs):>7.2f}% {media('err_nuevos', abs):>7.2f}% | {media('corr_total'):>8.3f} "
          f"{media('corr_stock'):>8.3f} {media('corr_nuevos'):>8.3f} | {media('mae_total'):>9,.0f} |"
          f"   (errores en magnitud)")
    return res


if __name__ == "__main__":
    todos = []
    for medida, titulo in (("act", "ENFOQUE ALFA -- capital asegurado (activacion)"),
                           ("reb", "RECUPERO OFICIAL -- rebaje")):
        print("\n" + "=" * 118)
        print(f"{titulo}   |   8 meses, nuevos rodante [M-12,M-1], stock fijo {FIJA_STOCK[0]}-{FIJA_STOCK[1]}")
        print("=" * 118)
        for clave in VARIANTES:
            todos += reporte(clave, medida)
        if len(sys.argv) > 1 and sys.argv[1] == "sens":
            mejor = sys.argv[2] if len(sys.argv) > 2 else "v2s2"
            et, d, modo, arr, ree, ct = VARIANTES[mejor]
            todos += reporte(f"{mejor}+arr", medida, (et + ", arrastre DENTRO", d, modo, "dentro", ree, ct))
            todos += reporte(f"{mejor}+reeng", medida, (et + ", reenganches INCLUIDOS", d, modo, arr, True, ct))

    os.makedirs(os.path.dirname(SALIDA), exist_ok=True)
    campos = ["medida", "variante", "periodo", "tasa"] + [f"{a}_{c}" for a in ("proy", "real", "err", "corr", "mae")
                                                          for c in ("stock", "nuevos", "total")]
    with open(SALIDA, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=campos)
        w.writeheader()
        for r in todos:
            w.writerow({k: (round(r[k], 6) if isinstance(r[k], float) else r[k]) for k in campos})
    print(f"\nResultados por mes en {SALIDA}")

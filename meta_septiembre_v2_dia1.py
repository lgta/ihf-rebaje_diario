"""
SEPTIEMBRE 2026 -- LA META CON LA DEFINICION v2, COMO HABRIA SALIDO EL 1-SEP.

Pedido del usuario 2026-09-13: "cuanto debo cerrar segun la proyeccion que habria
salido el primer dia de mes". La meta publicada (v1, S/20,477,271) no se toca; esto
responde que meta habria dado la definicion v2 si se hubiera fijado ese dia.

`meta_septiembre_v2.py` usa los insumos leidos HOY, y eso mira adelante: el
calendario pierde a los que terminaron de pagar despues del 1-sep (S/2.8M, hoy
COMPLETED) y el flag de reenganche borra a los que se refinanciaron despues. Aca los
insumos salen de `tarea24_v2_septiembre_al_1.sql`, que reconstruye el universo del
1-sep. CONTROL: v1 con esos insumos reproduce el calendario publicado a +0.14% (dia a
dia, +-0.6%) y el stock a -0.71% (re-expresion de Mambu, que no se puede deshacer).

Curvas y tasa: las de `meta_septiembre_v2.curvas` -- nuevos en [202508, 202607] y
stock fijo 202504-202606, calibradas sobre historia completamente observada antes
del 1-sep.

Las decisiones pendientes (PENDIENTES tarea 24) van con su default -- v2 con la
cohorte del dia 1 en modo S2, arrastre fuera, reenganches fuera de la calibracion -- y
se muestran tambien las alternativas.

Uso: python meta_septiembre_v2_dia1.py [ultimo dia completo del real, default 12]
"""
import collections
import csv
import statistics
import sys

import curvas_v2 as V
import meta_septiembre_v2 as M2
from motor_unificado import acumular_real

INSUMOS = "datos_tarea24/v2_septiembre_al_1.csv"
SALIDA = "datos_tarea24/meta_septiembre_v2_dia1.csv"
ULTIMO_DIA = int(sys.argv[1]) if len(sys.argv) > 1 else 12
HITOS = (12, 15, 20, 25, 30)

with open(INSUMOS) as f:
    FILAS = list(csv.DictReader(f))


def insumos(definicion, arrastre, reeng, seg_d1=False, solo_d1=None):
    """Universo del 1-sep. Con reeng=False (produccion): reeng = 0 o refin_post = 1 -- el
    que se refinancio desde el 1-sep todavia era ultimo de su cadena al cierre de agosto.
    Con reeng=True: todos. El calendario incluye a los que hoy figuran COMPLETED."""
    stock = collections.defaultdict(float)
    cal = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in FILAS:
        if r["definicion"] != definicion:
            continue
        if not reeng and r["reeng"] == "1" and r["refin_post"] == "0":
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


def meta_dia1(definicion, medida, modo, arrastre, reeng=False):
    c = M2.curvas(definicion, medida, modo, arrastre, reeng)
    stock, cal = insumos(definicion, arrastre, reeng, seg_d1=(modo == "S1"),
                         solo_d1=(False if modo == "S2" else None))
    d1 = M2.por_banda(insumos(definicion, arrastre, reeng, solo_d1=True)[0]) if modo == "S2" else None
    return M2.proyectar_mes(c, stock, cal, d1), c[4]


def al_dia(filas, real):
    """(proyectado, real, correlacion de incrementos) al ULTIMO_DIA."""
    n = ULTIMO_DIA
    rs, rn = acumular_real(real["stock"], n), acumular_real(real["nuevos"], n)
    rt = [a + b for a, b in zip(rs, rn)]
    pt = [x["proy_total"] for x in filas[:n]]
    inc = lambda s: [s[0]] + [s[i] - s[i - 1] for i in range(1, len(s))]
    return pt[-1], rt[-1], statistics.correlation(inc(pt), inc(rt))


if __name__ == "__main__":
    salida = []
    for medida, titulo, publicada in (("act", "CAPITAL ASEGURADO (Enfoque alfa)", M2.ALFA.filas),
                                      ("reb", "RECUPERO OFICIAL (rebaje)", M2.RECUPERO.filas)):
        versiones = [
            ("v1 publicada 1-sep", publicada, M2.ALFA.TASAS[M2.ALFA.MODO_TASA], M2.real_v1(medida)),
            ("v1 rearmada al 1-sep", *meta_dia1("v1", medida, "S0", "dentro"), M2.real_v1(medida)),
            ("v2 al 1-sep  <- META", *meta_dia1("v2", medida, "S2", "fuera"),
             M2.real_v2(medida, "fuera", reeng=True)),
            ("  alt: arrastre dentro", *meta_dia1("v2", medida, "S2", "dentro"),
             M2.real_v2(medida, "dentro", reeng=True)),
            ("  alt: con reenganches", *meta_dia1("v2", medida, "S2", "fuera", reeng=True),
             M2.real_v2(medida, "fuera", reeng=True)),
        ]
        print("=" * 116)
        print(f"{titulo} -- SEPTIEMBRE 2026, META COMO HABRIA SALIDO EL 1-SEP  |  real al {ULTIMO_DIA:02d}-sep")
        print("=" * 116)
        print(f"{'':<23} | {'meta del mes':>13} {'stock':>11} {'nuevos':>12} {'tasa':>7} | "
              f"{'proy. al '+str(ULTIMO_DIA):>11} {'real al '+str(ULTIMO_DIA):>11} {'real/proy':>9} "
              f"{'corr':>6} | {'falta p/ meta':>13}")
        for nombre, filas, p, real in versiones:
            u = filas[-1]
            pt, rt, corr = al_dia(filas, real)
            print(f"{nombre:<23} | {u['proy_total']:>13,.0f} {u['proy_stock']:>11,.0f} {u['proy_nuevos']:>12,.0f} "
                  f"{100*p:>6.2f}% | {pt:>11,.0f} {rt:>11,.0f} {rt/pt:>9.3f} {corr:>6.3f} | "
                  f"{u['proy_total']-rt:>13,.0f}")
            for fila in filas:
                salida.append({"medida": medida, "version": nombre.strip(), "dia": fila["dia"],
                               "proy_stock": round(fila["proy_stock"], 2),
                               "proy_nuevos": round(fila["proy_nuevos"], 2),
                               "proy_total": round(fila["proy_total"], 2)})

        filas_v2, _, real_v2 = versiones[2][1], versiones[2][2], versiones[2][3]
        u = filas_v2[-1]
        pt, rt, _ = al_dia(filas_v2, real_v2)
        print(f"\n  Trayectoria de la meta v2 (acumulado que deberias llevar a cada fecha):")
        print("  " + "   ".join(f"{d:02d}-sep S/ {filas_v2[d-1]['proy_total']:,.0f}" for d in HITOS))
        print(f"  Al {ULTIMO_DIA:02d}-sep llevas S/ {rt:,.0f} = {100*rt/u['proy_total']:.1f}% de la meta del mes; "
              f"la trayectoria esperaba {100*pt/u['proy_total']:.1f}%.")
        print(f"  Referencia, NO meta: si el resto del mes sigue al ritmo de hoy ({rt/pt:.3f}), cerrarias en "
              f"~S/ {u['proy_total']*rt/pt:,.0f}. En los 8 meses del backtest el cierre quedo a +-4pp del")
        print(f"  cociente del dia 12: rango ~S/ {u['proy_total']*(rt/pt-0.04):,.0f} a S/ {u['proy_total']*(rt/pt+0.04):,.0f}.")
        print()

    with open(SALIDA, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(salida[0].keys()))
        w.writeheader()
        w.writerows(salida)
    print(f"Series en {SALIDA} (local, no se versiona)")

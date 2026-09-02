"""
BACKTEST OFICIAL del Enfoque alfa ("capital asegurado") -- motor unificado
v3, sobre los 7 meses cerrados de 2026: enero a julio.

v3 (2026-08-26 continuacion, tarea 18g, adoptado a pedido del usuario):
la curva de STOCK suma el factor de cierre real (`f_dm_stock`,
`motor_unificado.grupo_dia_mes_stock`) -- el "cierre" de cada mes es su
ULTIMO DIA REAL (28/29/30/31 segun corresponda), no un numero de dia
fijo. Corrige el mismo mecanismo que 18f ya habia corregido para nuevos,
pero stock nunca lo tenia: por eso febrero (unico mes de 28 dias del
test) es el unico mes donde stock tambien fallaba fuerte -- su cierre
real nunca caia en el grupo "30/31" de nada. Ventana de stock sigue FIJA
(202504-202606, igual que siempre) -- rodarla se probo y empeora las
metricas diarias (`analisis_tarea18g_cierre_real.md`), asi que NO se
adopta esa parte (18c sigue abierta). El reindex analogo para nuevos se
prueba pero tampoco se adopta (impacto marginal, ver el mismo documento)
-- nuevos sigue exactamente como v2/W3.

v2 (2026-08-26, tarea 18a + 18f, adoptado a pedido del usuario). Tres
cambios respecto de la version de tarea 17 Fase 4:

  1. La curva de nuevos se segmenta por DIA DE LA SEMANA DEL VENCIMIENTO
     y lleva el FACTOR POR DIA DEL MES (quincena / dias 30-31). Ver
     `motor_unificado.py` v2.
  2. CALIBRACION RODANTE DE 12 MESES, `[M-12, M-1]` para cada mes de test:
     la curva de nuevos nunca ve el mes que proyecta. Antes la ventana era
     fija (20250301-20260531) y por lo tanto mayo y junio se testeaban con
     su propio mes adentro. El leak medido resulto **0.10pp** (0.11 / 0.17
     / 0.01 / -0.09 en abr/may/jun/jul), consistente con los 0.15-0.2pp
     que tarea 10 midio sobre la arquitectura de 3 componentes.
  3. 7 MESES DE TEST en vez de 4 (202601-202607). Es lo que da la historia
     con piso de 3,000 entradas/mes; antes de 202501 la cartera es <20% de
     la actual (ver `tarea18_ventana_calibracion.sql`).

Sale gratis en corridas de Athena porque las curvas se arman desde la
MATRIZ CRUDA (`curvas_crudas.py` + `tarea18f_curva_cruda.sql`), no de una
query por ventana.

LIMITACION VIGENTE (lo que queda de tarea 18c): la curva de STOCK no
rueda -- sigue calibrada en 202504-202606, asi que 6 de los 7 meses de
test estan dentro de su ventana. El nivel absoluto de error de ene-jun es
optimista por eso. No afecta la comparacion entre variantes de la curva
de nuevos (el stock es identico en todas), que es lo que decidio W3.

La comparacion de variantes que llevo a adoptar W3 esta en
`backtest_tarea18f.py`; los 4 backtests por mes de la arquitectura con
capa fantasma quedan como referencia historica.

Salida: tabla por mes en consola + series diarias en
datos_backtest_unificado/serie_diaria_{periodo}.csv (las consume el artifact).
"""
import csv
import collections
import os
import statistics

import curvas_crudas as CC
from motor_unificado import (P_ENTRADA, cargar_curva_stock, cargar_factor_dia_mes_stock,
                             segmentar_calendario, proyectar, acumular_real)

DIR_19 = "datos_tarea19"
DIR_OUT = "datos_backtest_unificado"
MESES_CALIBRACION = 12

MESES = [("202601", 31, "Enero 2026"), ("202602", 28, "Febrero 2026"),
         ("202603", 31, "Marzo 2026"), ("202604", 30, "Abril 2026"),
         ("202605", 31, "Mayo 2026"), ("202606", 30, "Junio 2026"),
         ("202607", 31, "Julio 2026"), ("202608", 31, "Agosto 2026")]

# Error que publicaba este mismo backtest con la tasa por CONTEO (21.9918%
# fija), antes de la migracion a soles de tarea 19. Se conserva como
# columna de contexto: el cambio es un OFFSET de nivel, no una mejora.
CONTEO_FIJO = {"202601": -11.1, "202602": -19.1, "202603": -14.0, "202604": -11.4,
               "202605": -10.7, "202606": -2.7, "202607": -2.9, "202608": -1.2}


def leer(path):
    with open(path) as f:
        return list(csv.DictReader(f))


curva_stock = cargar_curva_stock("datos_capital_asegurado/curva_unificada_stock_seg_v3.csv")
f_dm_stock = cargar_factor_dia_mes_stock()

stock_pob = collections.defaultdict(dict)
for r in leer(f"{DIR_19}/stock_pob_8m.csv"):
    stock_pob[r["periodo_meta"]][(r["tramo"], r["avance_band"])] = float(r["saldo_total"])

calendario = collections.defaultdict(lambda: collections.defaultdict(dict))
for r in leer(f"{DIR_19}/calendario_8m.csv"):
    calendario[r["periodo"]][int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo_en_riesgo"])

real_stock, real_nuevos = collections.defaultdict(dict), collections.defaultdict(dict)
for r in leer(f"{DIR_19}/real_stock_8m.csv"):
    real_stock[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])
for r in leer(f"{DIR_19}/real_nuevos_8m.csv"):
    real_nuevos[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])

# Tasa de entrada por SOLES, rodante [M-12,M-1] -- adoptada 2026-09-01
# (tarea 19). Reemplaza a `P_ENTRADA` (21.9918%, calibrada CONTANDO
# creditos pero aplicada sobre soles). `P_ENTRADA` se sigue importando
# solo para imprimir la comparacion.
tasa_mes = {r["periodo"]: (float(r["elegibles_soles"]), float(r["entran_soles"]))
            for r in leer(f"{DIR_19}/tasa_soles.csv")}

base_raw, acts_raw = CC.cargar_matriz(f"{DIR_19}/curva_cruda_nuevos.csv")


def ventana(periodo, meses=MESES_CALIBRACION):
    """[M-meses, M-1] como ('YYYYMM','YYYYMM'). La curva nunca ve el mes M."""
    y, m = int(periodo[:4]), int(periodo[4:])
    fin_y, fin_m = (y, m - 1) if m > 1 else (y - 1, 12)
    ini = fin_y * 12 + (fin_m - 1) - (meses - 1)
    return f"{ini // 12:04d}{ini % 12 + 1:02d}", f"{fin_y:04d}{fin_m:02d}"


def tasa_rodante(periodo):
    """Tasa de entrada por SOLES sobre la misma ventana que la curva."""
    d, h = ventana(periodo)
    elig = sum(v[0] for p, v in tasa_mes.items() if d <= p <= h)
    ent = sum(v[1] for p, v in tasa_mes.items() if d <= p <= h)
    return ent / elig


def correr(periodo, n_dias):
    d, h = ventana(periodo)
    curva_n, f_dm = CC.calibrar(base_raw, acts_raw, d, h, con_dow=True, con_f=True)
    filas = proyectar(stock_pob[periodo],
                      segmentar_calendario(calendario[periodo], periodo),
                      curva_stock, curva_n, n_dias, p_entrada=tasa_rodante(periodo),
                      f_dm=f_dm, f_dm_stock=f_dm_stock)
    rs = acumular_real(real_stock[periodo], n_dias)
    rn = acumular_real(real_nuevos[periodo], n_dias)
    for i, fila in enumerate(filas):
        fila["real_stock"] = rs[i]
        fila["real_nuevos"] = rn[i]
        fila["real_total"] = rs[i] + rn[i]
    return filas, (d, h)


if __name__ == "__main__":
    os.makedirs(DIR_OUT, exist_ok=True)
    print("=" * 118)
    print("BACKTEST OFICIAL -- MOTOR UNIFICADO v3 + TASA DE ENTRADA POR SOLES (tarea 19)")
    print("=" * 118)
    print(f"Tasa por soles, rodante [M-12,M-1]   |   calibracion de {MESES_CALIBRACION} "
          f"meses, sin leak   |   8 meses de test")
    print(f"La columna 'conteo' es lo que daba este mismo backtest con P_ENTRADA = "
          f"{100*P_ENTRADA:.4f}% fija (calibrada")
    print("CONTANDO creditos pero aplicada sobre SOLES). El cambio es un offset de nivel, "
          "no una mejora.\n")

    hdr = (f"{'Mes':<14} | {'Proyectado':>12} {'Real':>12} {'error':>8} | "
           f"{'err stock':>10} {'err nuevos':>11} {'corr diaria':>12} | "
           f"{'calibracion':>16} | {'tasa':>7} | {'conteo':>8}")
    print(hdr)
    print("-" * len(hdr))
    errores, corrs = [], []
    for periodo, n, nombre in MESES:
        filas, (d, h) = correr(periodo, n)
        f = filas[-1]
        err = 100 * (f["proy_total"] - f["real_total"]) / f["real_total"]
        es = 100 * (f["proy_stock"] - f["real_stock"]) / f["real_stock"]
        en = 100 * (f["proy_nuevos"] - f["real_nuevos"]) / f["real_nuevos"]
        pn = [x["proy_nuevos"] for x in filas]
        rn = [x["real_nuevos"] for x in filas]
        inc = lambda s: [s[0]] + [s[i] - s[i - 1] for i in range(1, n)]
        c = statistics.correlation(inc(pn), inc(rn))
        errores.append(abs(err))
        corrs.append(c)
        ant = CONTEO_FIJO.get(periodo)
        print(f"{nombre:<14} | {f['proy_total']:>12,.0f} {f['real_total']:>12,.0f} "
              f"{err:>+7.1f}% | {es:>+9.1f}% {en:>+10.1f}% {c:>12.3f} | "
              f"{d}-{h} | {100*tasa_rodante(periodo):>6.2f}% | "
              + (f"{ant:>+7.1f}%" if ant is not None else f"{'--':>8}"))

        with open(f"{DIR_OUT}/serie_diaria_{periodo}.csv", "w", newline="") as out:
            w = csv.DictWriter(out, fieldnames=["dia", "proy_stock", "proy_nuevos",
                                                "proy_total", "real_stock", "real_nuevos",
                                                "real_total"])
            w.writeheader()
            for fila in filas:
                w.writerow({k: (round(v, 2) if k != "dia" else v)
                            for k, v in fila.items() if k in w.fieldnames})

    print()
    print(f"Magnitud media de error de fin de mes: {sum(errores)/len(errores):.2f}%"
          f"   (con la tasa por conteo: "
          f"{sum(abs(v) for v in CONTEO_FIJO.values())/len(CONTEO_FIJO):.2f}%)")
    print(f"Correlacion media de incrementos diarios (nuevos): {sum(corrs)/len(corrs):.3f}"
          f"   (v1, sin dia de semana ni factor: 0.611)")
    print()
    print("COMO LEER ESTOS NUMEROS (CLAUDE.md, principio de interpretacion del error):")
    print("- El error de fin de mes ES la meta vs. la ejecucion, no un test estadistico.")
    print("- EL SESGO YA NO TIENE SIGNO CONSTANTE: los primeros meses quedan cerca de cero y")
    print("  los ULTIMOS TRES SOBREESTIMAN ~+9-10%. Eso no es la tasa: las dos definiciones")
    print("  (conteo y soles) derivan ~+10pp en paralelo a lo largo de los 8 meses. Es la")
    print("  ACTIVACION REAL que viene cayendo -0.46pp/mes mientras el calendario crece +90%")
    print("  -- senal de negocio a explicar (tarea 19), no algo a ajustar con una constante.")
    print("- La correlacion diaria NO cambia con la tasa (es invariante a escala). Un cambio")
    print("  de tasa es de NIVEL; los refinamientos de FORMA se arbitran con metricas diarias.")
    print("- El nivel de ene-jul sigue siendo optimista: la curva de STOCK no rueda (18c).")
    print()
    print(f"Series diarias escritas en {DIR_OUT}/")

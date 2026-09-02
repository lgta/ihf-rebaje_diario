"""
TAREA 18e, FASE D -- BACKTEST del motor de Recupero Oficial migrado a
dias_atraso_cuota (Fases A/B/C de esta tarea), sobre los 7 meses cerrados
de 2026 (enero-julio), motor NUEVO vs. motor VIGENTE (dayslate).

Reusa motor_unificado.proyectar() tal cual -- es generico (solo hace
stock[seg] x curva_stock y saldo_riesgo x p_entrada x curva_nuevos, sin
ningun supuesto sobre "activacion" vs. "rebaje"), asi que el mismo motor
que corre Capital Asegurado corre Recupero Oficial con otros insumos:

  - curva_stock / curva_nuevos: EN REBAJE real (deltas de saldo), no
    activacion binaria -- Fase B/C de esta tarea
    (tarea18e_fase_b_curva_stock_rebaje.sql / _fase_c_curva_nuevos_rebaje.sql).
  - p_entrada: tasa por SOLES (Fase A), no por conteo -- mismo error que
    18b diagnostico para Enfoque alfa, corregido desde el arranque acá.
  - stock inicial / calendario: los mismos `datos_tarea18a/stock_pob_7m.csv`
    y `calendario_7m.csv` que ya usa el backtest de Capital Asegurado
    (poblacion identica, dias_atraso_cuota, no depende del enfoque).
  - real: REBAJE real diario (no activacion) -- Fase D
    (tarea18e_fase_d_real_rebaje_7m.sql), separado stock/nuevos con la
    MISMA definicion de universo que el motor nuevo.

LIMITACION CONOCIDA de esta primera pasada: curva_stock y curva_nuevos
usan ventana de calibracion FIJA (202504-202606 y 20250301-20260531 --
identica a la del motor vigente hoy), no rodante -- mismo alcance que
"V0"/W0" tenia en Enfoque alfa antes de 18a/18c/18f. El leak medido ahi
fue ~0.10-0.2pp, no relevante para lo que Fase D esta decidiendo (universo,
no forma). No se calibro dia de semana ni factor de dia del mes -- esos
son refinamientos de forma (equivalentes a 18a/18f), fuera de alcance de
esta primera pasada; el motor vigente tampoco los tiene, asi que la
comparacion es pareja.

CRITERIO DE ADOPCION (CLAUDE.md): no se adopta por mejora de error -- se
adopta si el universo/medicion queda mas fiel (cierra el punto ciego de
bug 9 en Recupero Oficial), aunque el error suba. El "real" capturado por
el motor nuevo es estructuralmente mayor al del motor vigente (dayslate
nunca ve la entrada de creditos que pagan ~1 dia tarde) -- se reporta esa
cobertura, no solo el error de cierre.
"""
import csv
import collections
import os
import statistics

from motor_unificado import proyectar, acumular_real

DIR_18A = "datos_tarea18a"
DIR_18E = "datos_tarea18e"
DIR_OUT = "datos_tarea18e"

MESES = [("202601", 31, "Enero 2026"), ("202602", 28, "Febrero 2026"),
         ("202603", 31, "Marzo 2026"), ("202604", 30, "Abril 2026"),
         ("202605", 31, "Mayo 2026"), ("202606", 30, "Junio 2026"),
         ("202607", 31, "Julio 2026")]

# Motor VIGENTE (dayslate, P_NO_PAGA_DIA0=13.38%), unicos 2 meses con
# backtest ya corrido -- fase3_backtest.sql (jun) y cierre_julio.sql (jul),
# ver SEGUIMIENTO.md. Universo mas chico (punto ciego de bug 9, sin
# compensar) -- no comparable error-a-error con el real del motor nuevo,
# que captura mas. Se muestra como referencia de contexto, no como barra.
VIGENTE_DAYSLATE = {
    "202606": {"error": 5.4, "err_stock": 16.2, "err_nuevos": 0.7, "real_total": 1_713_815},
    "202607": {"error": 17.6, "err_stock": 2.0, "err_nuevos": 22.5, "real_total": 2_088_911},
}


def leer(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def cargar_curva_stock_rebaje(path=f"{DIR_18E}/curva_stock_rebaje_dac.csv"):
    curva = {}
    for r in leer(path):
        curva.setdefault((r["tramo"], r["avance_band"]), {})[int(r["dia"])] = float(r["pct_recupero_acum"])
    return curva


def cargar_curva_nuevos_rebaje(path=f"{DIR_18E}/curva_nuevos_rebaje_dac.csv"):
    curva = {}
    for r in leer(path):
        curva.setdefault(r["avance_band"], {})[int(r["dia_desde_entrada"])] = float(r["pct_recupero_acum"])
    return curva


def calcular_p_entrada_soles(path=f"{DIR_18E}/tasa_soles.csv"):
    elig, ent = 0.0, 0.0
    for r in leer(path):
        elig += float(r["elegibles_soles"])
        ent += float(r["entran_soles"])
    return ent / elig


curva_stock = cargar_curva_stock_rebaje()
curva_nuevos = cargar_curva_nuevos_rebaje()
P_ENTRADA_SOLES = calcular_p_entrada_soles()

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


def correr(periodo, n_dias):
    filas = proyectar(stock_pob[periodo], calendario[periodo], curva_stock, curva_nuevos,
                       n_dias, p_entrada=P_ENTRADA_SOLES)
    rs = acumular_real(real_stock[periodo], n_dias)
    rn = acumular_real(real_nuevos[periodo], n_dias)
    for i, fila in enumerate(filas):
        fila["real_stock"] = rs[i]
        fila["real_nuevos"] = rn[i]
        fila["real_total"] = rs[i] + rn[i]
    return filas


if __name__ == "__main__":
    os.makedirs(DIR_OUT, exist_ok=True)
    print("=" * 116)
    print("TAREA 18e FASE D -- BACKTEST RECUPERO OFICIAL, MOTOR dias_atraso_cuota (7 meses)")
    print("=" * 116)
    print(f"P_ENTRADA (por SOLES, Fase A) = {100*P_ENTRADA_SOLES:.4f}%   |   "
          f"vigente hoy: P_NO_PAGA_DIA0 = 13.38% (por conteo, dayslate)\n")

    hdr = (f"{'Mes':<14} | {'Proyectado':>12} {'Real (dac)':>12} {'error':>8} | "
           f"{'err stock':>10} {'err nuevos':>11} {'corr diaria':>12} | {'vigente (dayslate)':>28}")
    print(hdr)
    print("-" * len(hdr))
    errores, corrs = [], []
    for periodo, n, nombre in MESES:
        filas = correr(periodo, n)
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
        v = VIGENTE_DAYSLATE.get(periodo)
        vig_str = (f"err {v['error']:+.1f}% (real S/{v['real_total']:,.0f})" if v else "sin backtest previo")
        print(f"{nombre:<14} | {f['proy_total']:>12,.0f} {f['real_total']:>12,.0f} "
              f"{err:>+7.1f}% | {es:>+9.1f}% {en:>+10.1f}% {c:>12.3f} | {vig_str:>28}")

        with open(f"{DIR_OUT}/serie_diaria_recupero_{periodo}.csv", "w", newline="") as out:
            w = csv.DictWriter(out, fieldnames=["dia", "proy_stock", "proy_nuevos",
                                                "proy_total", "real_stock", "real_nuevos",
                                                "real_total"])
            w.writeheader()
            for fila in filas:
                w.writerow({k: (round(v, 2) if k != "dia" else v)
                            for k, v in fila.items() if k in w.fieldnames})

    print()
    print(f"Magnitud media de error de fin de mes (motor nuevo, dac): {sum(errores)/len(errores):.2f}%")
    print(f"Correlacion media de incrementos diarios (total): {sum(corrs)/len(corrs):.3f}")
    print()
    total_jun = sum(real_stock["202606"].values()) + sum(real_nuevos["202606"].values())
    total_jul = sum(real_stock["202607"].values()) + sum(real_nuevos["202607"].values())
    print("COBERTURA DE UNIVERSO -- real (dias_atraso_cuota) vs. real (dayslate, SEGUIMIENTO.md):")
    print(f"  Junio: S/{total_jun:,.0f} (dac) vs. S/{VIGENTE_DAYSLATE['202606']['real_total']:,.0f} "
          f"(dayslate) = {100*total_jun/VIGENTE_DAYSLATE['202606']['real_total']:.1f}%")
    print(f"  Julio: S/{total_jul:,.0f} (dac) vs. S/{VIGENTE_DAYSLATE['202607']['real_total']:,.0f} "
          f"(dayslate) = {100*total_jul/VIGENTE_DAYSLATE['202607']['real_total']:.1f}%")
    print()
    print(f"Series diarias escritas en {DIR_OUT}/serie_diaria_recupero_*.csv")

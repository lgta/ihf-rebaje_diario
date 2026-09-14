"""
TAREA 25 / BUG 28 -- BACKTEST DE LA TASA ANCLADA, 8 meses (202601-202608), los dos
enfoques, las dos metricas de CLAUDE.md.

La tasa de entrada se calibraba sobre el saldo AL VENCIMIENTO y la meta la aplica sobre el
saldo ANCLADO a la ultima foto del mes anterior, el unico que conoce el dia 1. El anclado es
mayor porque no descuenta la amortizacion entre el ancla y el vencimiento (bug 28). Los
backtests nunca lo vieron porque usan el calendario medido en los dos lados. Aca cada mes se
proyecta tambien como lo habria hecho la meta:

  med   calendario MEDIDO  x tasa medida    el backtest de siempre (tarea 24)
  anc   calendario ANCLADO x tasa medida    la meta con el bug: lo que se habria publicado
  fix   calendario ANCLADO x tasa ANCLADA   la correccion (motor_v2.TASA_ANCLADA)
  fixt  fix con la tasa anclada por TERCIO del mes de la entrada (2-10, 11-20, 21-31):
        refinamiento de FORMA, no adoptado. El ancla corre menos sobre el vencimiento en los
        primeros dias del mes (~1.10) que en el mes completo (~1.14), asi que una tasa anclada
        plana baja la trayectoria al principio del mes y la sube al final.
  ctl   med con los reenganches FUERA       control: reproduce el v2 S2 de tarea 24 con la
                                            matriz de calendario nueva

Todo v2 S2, arrastre fuera, reenganches segun motor_v2.REENG (incluidos desde 2026-09-13).
Mismo protocolo que el backtest de tarea 24: nuevos (curva y tasa) rueda [M-12, M-1] y stock
con ventana FIJA 202504-202606. El real, las curvas y el stock son los mismos en med, anc y
fix: solo cambian el calendario de nuevos y la tasa.

COMO LEERLO
  - fix contra anc es la correccion de COMO se mide: la tasa pasa a tener el denominador
    que la meta usa. Se corrige aunque el error suba (CLAUDE.md).
  - fix contra med dice cuanto de la brecha entre la meta y el backtest queda: si el ancla
    corriera siempre igual respecto del vencimiento, fix = med. Lo que queda es cuanto se
    mueve esa relacion de un mes a otro (la tabla del final).
  - fixt contra fix es de forma: se decide con la correlacion y el MAE diarios, no con el
    cierre.

Uso: python backtest_tarea25_ancla.py
"""
import csv
import functools
import os

import curvas_crudas_stock as CS
import curvas_v2 as V
import motor_v2 as MV
from backtest_tarea24_v1_v2 import MESES, curva_nuevos, metricas
from motor_unificado import acumular_real

SALIDA = "datos_tarea25/backtest_ancla.csv"
TERCIOS = ((2, 10), (11, 20), (21, 31))

VARIANTES = {
    # clave: (etiqueta, calendario anclado, tasa anclada, reenganches, tasa por tercio)
    "med": ("calendario medido x tasa medida (backtest de siempre)", False, False, MV.REENG, False),
    "anc": ("calendario anclado x tasa medida (la meta con el bug)", True, False, MV.REENG, False),
    "fix": ("calendario anclado x tasa anclada (la correccion)", True, True, MV.REENG, False),
    "fixt": ("fix con la tasa anclada por tercio del mes (forma, no adoptado)", True, True, MV.REENG, True),
    "ctl": ("control: med con los reenganches fuera (tarea 24, v2 S2)", False, False, False, False),
}


@functools.lru_cache(maxsize=None)
def stock(medida, reeng):
    """Curva de stock (fija, sin la cohorte d1: S2), poblacion, cohorte d1 y real del stock."""
    base_s, acts_s = V.stock_matriz("v2", medida, MV.ARRASTRE, reeng, solo_d1=False)
    curva_s, f_s = CS.calibrar(base_s, acts_s, *MV.FIJA_STOCK, con_f=True, modo_cierre="real")
    _, acts_real = V.stock_matriz("v2", medida, MV.ARRASTRE, reeng)
    base_d1, _ = V.stock_matriz("v2", medida, MV.ARRASTRE, reeng, solo_d1=True)
    return curva_s, f_s, base_s, base_d1, acts_real


@functools.lru_cache(maxsize=None)
def _tm(reeng, ancla, dias=None):
    return V.tasa_mensual("v2", MV.ARRASTRE, reeng, ancla=ancla, dias=dias)


def tasas_tercio(reeng, ancla, desde, hasta):
    """[(desde_dia, hasta_dia, tasa)] de cada tercio del mes en la ventana."""
    return [(lo, hi, V.tasa(_tm(reeng, ancla, (lo, hi)), desde, hasta)) for lo, hi in TERCIOS]


def correr(medida, cal_ancla, tasa_ancla, reeng, tercios=False):
    curva_s, f_s, base_s, base_d1, acts_real = stock(medida, reeng)
    real_n = V.nuevos_real("v2", medida, MV.ARRASTRE, reeng)
    out = []
    for periodo, n in MESES:
        curva_n, f_n = curva_nuevos("v2", medida, MV.ARRASTRE, reeng, periodo)
        p = V.tasa(_tm(reeng, tasa_ancla), *V.ventana(periodo))
        cal = V.calendario("v2", periodo, reeng, ancla=cal_ancla)
        cal_tot = sum(s for v in cal.values() for s in v.values())
        if tercios:
            # tasa del tercio x calendario == tasa plana x (calendario x tasa del tercio / tasa plana)
            f = {d: pg / p for lo, hi, pg in tasas_tercio(reeng, tasa_ancla, *V.ventana(periodo))
                 for d in range(lo, hi + 1)}
            cal = {d: {b: s * f[d] for b, s in v.items()} for d, v in cal.items()}
        filas = MV.proyectar_mes((curva_s, f_s, curva_n, f_n, p), periodo, V.poblacion(base_s, periodo),
                                 cal, V.cohorte_d1(base_d1, periodo))
        rs = acumular_real(V.real_por_dia(acts_real, periodo), n)
        rn = acumular_real(real_n.get(periodo, {}), n)
        for i, fila in enumerate(filas):
            fila["real_stock"], fila["real_nuevos"], fila["real_total"] = rs[i], rn[i], rs[i] + rn[i]
        m = metricas(filas, n)
        m.update(medida=medida, periodo=periodo, tasa=p, calendario=cal_tot,
                 ratio_d12=(rs[11] + rn[11]) / filas[11]["proy_total"])
        out.append(m)
    return out


def reporte(clave, medida):
    etiqueta, cal_ancla, tasa_ancla, reeng, tercios = VARIANTES[clave]
    res = correr(medida, cal_ancla, tasa_ancla, reeng, tercios)
    print(f"\n--- [{clave}] {etiqueta} ---")
    print(f"{'mes':<7} | {'proyectado':>12} {'real':>12} {'error':>7} | {'err stk':>8} {'err nvo':>8} | "
          f"{'corr tot':>8} {'corr nvo':>8} | {'MAE tot':>9} {'MAE nvo':>9} | {'r/p d12':>7} | {'tasa':>6} {'calendario':>12}")
    for m in res:
        print(f"{m['periodo']:<7} | {m['proy_total']:>12,.0f} {m['real_total']:>12,.0f} {m['err_total']:>+6.1f}% | "
              f"{m['err_stock']:>+7.1f}% {m['err_nuevos']:>+7.1f}% | {m['corr_total']:>8.3f} "
              f"{m['corr_nuevos']:>8.3f} | {m['mae_total']:>9,.0f} {m['mae_nuevos']:>9,.0f} | {m['ratio_d12']:>7.3f} | "
              f"{100*m['tasa']:>5.2f}% {m['calendario']:>12,.0f}")
    media = lambda k, f=lambda x: x: sum(f(r[k]) for r in res) / len(res)
    print(f"{'MEDIA':<7} | {'':>12} {'':>12} {media('err_total', abs):>6.2f}% | "
          f"{media('err_stock', abs):>7.2f}% {media('err_nuevos', abs):>7.2f}% | {media('corr_total'):>8.3f} "
          f"{media('corr_nuevos'):>8.3f} | {media('mae_total'):>9,.0f} {media('mae_nuevos'):>9,.0f} | "
          f"{media('ratio_d12'):>7.3f} |   (errores en magnitud)")
    print(f"{'sesgo':<7} | {'':>12} {'':>12} {media('err_total'):>+6.2f}% | "
          f"{media('err_stock'):>+7.2f}% {media('err_nuevos'):>+7.2f}% |   (errores con signo; r/p d12 = real/proy al dia 12)")
    for m in res:
        m["variante"] = clave
    return res


def ancla_por_mes():
    """Cuanto corre el calendario anclado sobre el medido, mes a mes, y las dos tasas: lo que
    fix no puede corregir es cuanto se aparta el cociente de un mes del de su ventana."""
    reeng = MV.REENG
    tm_med, tm_anc = _tm(reeng, False), _tm(reeng, True)
    print("\n" + "=" * 100)
    print("EL ANCLA MES A MES (v2, reenganches " + ("incluidos" if reeng else "fuera") + ", arrastre fuera)")
    print("=" * 100)
    print(f"{'mes':<7} | {'cal. medido':>12} {'cal. anclado':>13} {'anclado/medido':>15} | "
          f"{'tasa med. mes':>13} {'tasa anc. mes':>13} | {'ventana anc/med':>15} {'mes / ventana':>13}")
    periodos = sorted(p for p in tm_med if "202501" <= p <= V.CALENDARIO_HASTA)
    for periodo in periodos:
        e_med, n_med = tm_med[periodo]
        e_anc, n_anc = tm_anc[periodo]
        linea = (f"{periodo:<7} | {e_med:>12,.0f} {e_anc:>13,.0f} {e_anc/e_med:>15.3f} | "
                 f"{100*n_med/e_med:>12.2f}% {100*n_anc/e_anc:>12.2f}% |")
        if periodo >= "202601":
            desde, hasta = V.ventana(periodo)
            r_v = V.tasa(tm_med, desde, hasta) / V.tasa(tm_anc, desde, hasta)
            linea += f" {r_v:>15.3f} {(e_anc/e_med)/r_v:>13.3f}"
        print(linea)
    print("  (elegibles de la tasa: el anclado solo cuenta a quien tiene foto con saldo > 0 el mes anterior;"
          " 'ventana anc/med' = tasa medida / tasa anclada de [M-12, M-1])")
    print("\n  TASA POR TERCIO DEL MES DE LA ENTRADA -- ventana de la meta de octubre [202509, 202608]:")
    print(f"  {'dias':<7} | {'tasa medida':>11} {'tasa anclada':>12} {'anclado/medido':>15}")
    med = tasas_tercio(reeng, False, "202509", "202608")
    anc = tasas_tercio(reeng, True, "202509", "202608")
    for (lo, hi, pm), (_, _, pa) in zip(med, anc):
        print(f"  {lo:>2}-{hi:<4} | {100*pm:>10.2f}% {100*pa:>11.2f}% {pm/pa:>15.3f}")
    pm, pa = V.tasa(tm_med, "202509", "202608"), V.tasa(tm_anc, "202509", "202608")
    print(f"  {'mes':<7} | {100*pm:>10.2f}% {100*pa:>11.2f}% {pm/pa:>15.3f}")


if __name__ == "__main__":
    todos = []
    for medida, titulo in (("act", "ENFOQUE ALFA -- capital asegurado (activacion)"),
                           ("reb", "RECUPERO OFICIAL -- rebaje")):
        print("\n" + "=" * 132)
        print(f"{titulo}   |   8 meses, v2 S2, nuevos rodante [M-12,M-1], stock fijo "
              f"{MV.FIJA_STOCK[0]}-{MV.FIJA_STOCK[1]}")
        print("=" * 132)
        for clave in VARIANTES:
            todos += reporte(clave, medida)
    ancla_por_mes()

    os.makedirs(os.path.dirname(SALIDA), exist_ok=True)
    campos = ["medida", "variante", "periodo", "tasa", "calendario", "ratio_d12"] + [
        f"{a}_{c}" for a in ("proy", "real", "err", "corr", "mae") for c in ("stock", "nuevos", "total")]
    with open(SALIDA, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=campos)
        w.writeheader()
        for r in todos:
            w.writerow({k: (round(r[k], 6) if isinstance(r[k], float) else r[k]) for k in campos})
    print(f"\nResultados por mes en {SALIDA}")

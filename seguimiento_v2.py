"""
SEGUIMIENTO DE UN MES CONTRA SU META v2 (tarea 25, paso 6), los dos enfoques. El primer mes
es octubre 2026, la primera meta del motor v2.

    python seguimiento_v2.py <periodo> <insumos.csv> <real.csv> [ultimo dia completo]
    python seguimiento_v2.py 202610 datos_tarea25/insumos_octubre.csv datos_tarea25/real_v2_octubre.csv 5

La meta NO se recalcula: se lee la serie que `meta_v2.py` dejo junto a los insumos
(meta_v2_<periodo>.csv), la que se fijo el dia 1. El real sale de `tarea25_real_v2.sql` (mismo
esquema que los bloques 'real' y 'real_pob' de tarea24_v2_septiembre.sql), con el universo de la
meta: v2, arrastre por DNI fuera, reenganches segun motor_v2.REENG. El stock no filtra reenganches:
el que tuvo su reenganche despues del dia 1 era parte del stock ese dia.

Dos numeros, como pide CLAUDE.md -- nunca uno solo:
  - AVANCE contra la trayectoria de la meta: real acumulado / proyectado acumulado al mismo dia.
  - CORRELACION y MAE de los incrementos diarios: si la ejecucion sigue la FORMA esperada.
Y la brecha de nuevos partida en VOLUMEN (¿entro lo que calendario anclado x tasa anclada
esperaba?) y CONVERSION (¿activa por sol que entro lo que esperaba la curva?).

OJO DE LECTURA (tarea 25): la tasa anclada es plana, pero el ancla pesa menos en los primeros dias
del mes que en el mes completo (backtest_tarea25_ancla.py, variante fixt). La trayectoria de nuevos
corre algo baja al principio del mes y alta al final; por eso la descomposicion muestra tambien la
tasa anclada historica de los MISMOS dias.

CONTROL: `python seguimiento_v2.py 202609 datos_tarea24/v2_septiembre_al_1.csv
datos_tarea24/v2_septiembre.csv 12` reproduce la capa a de backtest_septiembre_v2.py (0.927 alfa).
"""
import collections
import csv
import os
import statistics
import sys

import curvas_v2 as V
import motor_v2 as MV
from motor_unificado import acumular_real

TITULOS = (("act", "CAPITAL ASEGURADO (Enfoque alfa)"), ("reb", "RECUPERO OFICIAL (rebaje)"))


def leer_meta(periodo, insumos):
    ruta = os.path.join(os.path.dirname(insumos), f"meta_v2_{periodo}.csv")
    series = collections.defaultdict(list)
    with open(ruta) as f:
        for r in csv.DictReader(f):
            series[r["medida"]].append({k: float(r[k]) for k in ("proy_stock", "proy_nuevos", "proy_total")})
    return series, ruta


def leer_real(path):
    """({medida: {componente: {dia: valor}}}, {dia: saldo que entro en mora}) del universo de la meta."""
    real = {m: {"stock": collections.defaultdict(float), "nuevos": collections.defaultdict(float)}
            for m, _ in TITULOS}
    entradas = collections.defaultdict(float)
    with open(path) as f:
        for r in csv.DictReader(f):
            if r["definicion"] != "v2" or r["bloque"] not in ("real", "real_pob"):
                continue
            if MV.ARRASTRE == "fuera" and r["arrastre"] == "1":
                continue
            if r["componente"] == "nuevos" and r["reeng"] == "1" and not MV.REENG:
                continue
            d = int(r["dia"])
            if r["bloque"] == "real":
                real["act"][r["componente"]][d] += float(r["saldo"] or 0)
                real["reb"][r["componente"]][d] += float(r["rebaje"] or 0)
            else:
                entradas[d] += float(r["saldo"] or 0)
    return real, entradas


def inc(s):
    return [s[0]] + [s[i] - s[i - 1] for i in range(1, len(s))]


def reporte(titulo, meta, real, n, periodo):
    rs, rn = acumular_real(real["stock"], n), acumular_real(real["nuevos"], n)
    s = [{"dia": i + 1, **meta[i], "real_stock": rs[i], "real_nuevos": rn[i], "real_total": rs[i] + rn[i]}
         for i in range(n)]
    meta_mes = meta[-1]["proy_total"]
    print("=" * 96)
    print(f"{titulo} -- meta {periodo} S/ {meta_mes:,.0f}  |  real al dia {n} (ultimo dia completo)")
    print("=" * 96)
    print(f"{'dia':>3} | {'proy acum':>12} {'real acum':>12} {'real/proy':>10} | "
          f"{'proy dia':>10} {'real dia':>10} | {'real stock':>11} {'real nuevos':>12}")
    pt, rt = [x["proy_total"] for x in s], [x["real_total"] for x in s]
    ip, ir = inc(pt), inc(rt)
    for i, x in enumerate(s):
        print(f"{x['dia']:>3} | {x['proy_total']:>12,.0f} {x['real_total']:>12,.0f} "
              f"{x['real_total']/x['proy_total']:>10.3f} | {ip[i]:>10,.0f} {ir[i]:>10,.0f} | "
              f"{x['real_stock']:>11,.0f} {x['real_nuevos']:>12,.0f}")
    print()
    for comp in ("stock", "nuevos", "total"):
        p = [x[f"proy_{comp}"] for x in s]
        r = [x[f"real_{comp}"] for x in s]
        c = statistics.correlation(inc(p), inc(r)) if n > 2 else float("nan")
        mae = sum(abs(a - b) for a, b in zip(inc(p), inc(r))) / n
        print(f"  {comp:<7} real/proy al dia {n}: {r[-1]/p[-1]:.3f} ({100*(r[-1]/p[-1]-1):+.1f}%)"
              f"   corr. incrementos diarios {c:.3f}   MAE diario S/ {mae:,.0f}")
    u = s[-1]
    print(f"  avance del mes: real = {100*u['real_total']/meta_mes:.1f}% de la meta del mes; "
          f"la trayectoria de la meta esperaba {100*u['proy_total']/meta_mes:.1f}% a esta fecha")
    print()
    return s


def descomposicion(periodo, insumos, s_alfa, entradas, n):
    cal = MV.leer_insumos(insumos)[1]
    ventana = MV.ventana_meta(periodo)
    p = V.tasa(V.tasa_mensual("v2", MV.ARRASTRE, MV.REENG, ancla=MV.TASA_ANCLADA), *ventana)
    p_dias = V.tasa(V.tasa_mensual("v2", MV.ARRASTRE, MV.REENG, ancla=MV.TASA_ANCLADA, dias=(2, n)), *ventana)
    cal_n = sum(sum(cal.get(d, {}).values()) for d in range(2, n + 1))
    e_real, e_esp = sum(entradas.get(d, 0.0) for d in range(2, n + 1)), p * cal_n
    a_real, a_proy = s_alfa[-1]["real_nuevos"], s_alfa[-1]["proy_nuevos"]
    print("=" * 96)
    print(f"DESCOMPOSICION DE LA BRECHA DE NUEVOS (Enfoque alfa), dias 2-{n}")
    print("=" * 96)
    print(f"  saldo que ENTRO en mora     real S/ {e_real:>12,.0f}   esperado (calendario x {100*p:.2f}%)"
          f" S/ {e_esp:>12,.0f}   {100*(e_real/e_esp-1):+.1f}%")
    print(f"  tasa realizada {100*e_real/cal_n:.2f}% sobre el calendario anclado; la tasa anclada historica de los"
          f" mismos dias 2-{n} es {100*p_dias:.2f}% ({100*(e_real/cal_n/p_dias-1):+.1f}% contra esos dias)")
    print(f"  activado de nuevos          real S/ {a_real:>12,.0f}   proyectado"
          f"                    S/ {a_proy:>12,.0f}   {100*(a_real/a_proy-1):+.1f}%")
    print(f"  activado por sol que entro  real {a_real/e_real:>8.3f}          proyectado"
          f"                        {a_proy/e_esp:>8.3f}      {100*((a_real/e_real)/(a_proy/e_esp)-1):+.1f}%")
    print("  (volumen x conversion = brecha de nuevos)")
    print()


def main(periodo, insumos, real_path, n):
    meta, ruta_meta = leer_meta(periodo, insumos)
    real, entradas = leer_real(real_path)
    print(f"Meta: {ruta_meta} | real: {real_path} | reenganches {'incluidos' if MV.REENG else 'fuera'},"
          f" arrastre {MV.ARRASTRE}\n")
    salida = []
    for medida, titulo in TITULOS:
        s = reporte(titulo, meta[medida], real[medida], n, periodo)
        salida += [{"medida": medida, **x} for x in s]
        if medida == "act":
            s_alfa = s
    descomposicion(periodo, insumos, s_alfa, entradas, n)
    ruta = os.path.join(os.path.dirname(real_path), f"seguimiento_v2_{periodo}.csv")
    with open(ruta, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(salida[0].keys()))
        w.writeheader()
        w.writerows({k: (round(v, 2) if isinstance(v, float) else v) for k, v in x.items()} for x in salida)
    print(f"Serie en {ruta} (local, no se versiona)")


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5):
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) == 5 else 12)

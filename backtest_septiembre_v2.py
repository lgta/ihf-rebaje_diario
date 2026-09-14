"""
TAREA 24 -- VALIDACION DEL FIX CON SEPTIEMBRE (al 12-sep): backtest de la logica con la que
el motor v2 dimensiona stock y nuevos, contra lo que paso. Pedido del usuario 2026-09-13.

Insumos (locales):
  datos_tarea24/v2_dimensionamiento_sep.csv  tarea24_v2_dimensionamiento_sep.sql
  datos_tarea24/v2_septiembre_al_1.csv       stock v2 del dia 1 y calendario anclado (la meta)
  datos_tarea24/v2_septiembre.csv            real v2 por dia (tarea24_v2_septiembre.sql)

Cuatro preguntas:
  1. UNIVERSO DE NUEVOS: ¿nuestras entradas v2 son los nuevos que el negocio asigna a TEMPRANA?
     (el stock ya se cuadro contra la vista credito a credito: +0.5%)
  2. VOLUMEN: ¿entro lo que calendario x tasa esperaba? Separa el ancla (saldo del 31-ago contra
     saldo al vencimiento) de la tasa realizada, y compara la tasa de los dias 2-12 de septiembre
     con la de los mismos dias de los meses anteriores.
  3. BACKTEST EN TRES CAPAS al dia 12, con la misma curva y la misma tasa:
       a. la meta al 1-sep (calendario anclado al 31-ago)
       b. calendario MEDIDO (saldo al vencimiento)          -> saca el efecto del ancla
       c. las entradas REALES, con la curva y sin tasa      -> saca el efecto de la tasa
     Lo que queda en (c) es conversion: si la curva sigue bien a quien entra.
  4. STOCK: la curva de stock contra el real del stock observado el dia 1 (igual en las 3 capas).

Universo: v2, arrastre fuera. Reenganches como en la meta al 1-sep: fuera de la calibracion; en
el stock entra quien tuvo su reenganche despues del 1-sep (era ultimo de su cadena ese dia).

Uso: python backtest_septiembre_v2.py [ultimo dia completo, default 12]
"""
import collections
import csv
import statistics
import sys

import motor_v2 as MV
from motor_unificado import acumular_real

PERIODO = "202609"
DIM = "datos_tarea24/v2_dimensionamiento_sep.csv"
AL_1 = "datos_tarea24/v2_septiembre_al_1.csv"
REAL = "datos_tarea24/v2_septiembre.csv"
ULTIMO_DIA = int(sys.argv[1]) if len(sys.argv) > 1 else 12

with open(DIM) as f:
    FILAS = list(csv.DictReader(f))


def bloque(nombre):
    return [r for r in FILAS if r["bloque"] == nombre]


def num(x):
    return float(x) if x not in ("", None) else 0.0


def real_v2(medida):
    """{componente: {dia: activado o rebajado}}, arrastre fuera. Stock con los reenganches
    posteriores al 1-sep (universo de la meta); nuevos sin reenganches (como el bloque D)."""
    col = "saldo" if medida == "act" else "rebaje"
    out = {"stock": collections.defaultdict(float), "nuevos": collections.defaultdict(float)}
    with open(REAL) as f:
        for r in csv.DictReader(f):
            if r["bloque"] != "real" or r["arrastre"] == "1":
                continue
            if r["componente"] == "nuevos" and r["reeng"] == "1":
                continue
            out[r["componente"]][int(r["dia"])] += num(r[col])
    return out


def cal_desde(nombre, filtro=lambda r: True):
    """{dia_entrada: {banda: saldo}} desde el bloque D o E, dias 2..ULTIMO_DIA."""
    cal = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in bloque(nombre):
        d = int(r["k1"])
        if 2 <= d <= ULTIMO_DIA and filtro(r):
            cal[d][r["k2"]] += num(r["saldo_1"])
    return {d: dict(v) for d, v in cal.items()}


def total(cal, hasta=None):
    return sum(s for d, v in cal.items() if hasta is None or d <= hasta for s in v.values())


def inc(s):
    return [s[0]] + [s[i] - s[i - 1] for i in range(1, len(s))]


# ---------------------------------------------------------------------------
def universo_nuevos():
    B = bloque("B. nuevos v2 vs vista TEMPRANA nuevo")
    s1 = lambda rows: sum(num(r["saldo_1"]) for r in rows)
    s2 = lambda rows: sum(num(r["saldo_2"]) for r in rows)
    n = lambda rows: sum(int(r["creditos"]) for r in rows)
    ambos = [r for r in B if r["k1"] == "a. en ambos"]
    solo_n = [r for r in B if r["k1"] == "b. solo nuestro"]
    solo_v = [r for r in B if r["k1"] == "c. solo la vista"]
    print("=" * 100)
    print(f"1. UNIVERSO DE NUEVOS -- entradas v2 del 2 al {ULTIMO_DIA}-sep contra los NUEVOS de TEMPRANA de la vista")
    print("=" * 100)
    print(f"  en ambos:        {n(ambos):>6,} creditos   nuestro S/ {s1(ambos):>12,.0f}   vista S/ {s2(ambos):>12,.0f}"
          f"   ({100*(s1(ambos)/s2(ambos)-1):+.1f}% de monto)")
    print(f"  solo nuestro:    {n(solo_n):>6,} creditos   S/ {s1(solo_n):>12,.0f}")
    print(f"  solo la vista:   {n(solo_v):>6,} creditos   S/ {s2(solo_v):>12,.0f}")
    comparables = [r for r in solo_n if r["k2"] not in ("arrastre por DNI",)
                   and not r["k2"].startswith("entro el 11-12")]
    print(f"  cobertura: de nuestras entradas TEMPRANA ya asignables, {100*n(ambos)/(n(ambos)+n(comparables)):.1f}% "
          f"en creditos y {100*s1(ambos)/(s1(ambos)+s1(comparables)):.1f}% en saldo estan en la vista;"
          f" de la vista, {100*n(ambos)/(n(ambos)+n(solo_v)):.1f}% esta en lo nuestro")
    for titulo, rows, col in (("desfase entrada -> asignacion (en ambos)", ambos, "saldo_1"),
                              ("solo nuestro, por que", solo_n, "saldo_1"),
                              ("solo la vista, por que", solo_v, "saldo_2")):
        agg = collections.defaultdict(lambda: [0, 0.0])
        for r in rows:
            k = r["k2"] + (f" ({r['k3']})" if r["k3"] else "")
            agg[k][0] += int(r["creditos"])
            agg[k][1] += num(r[col])
        print(f"  -- {titulo}")
        for k, (c, s) in sorted(agg.items(), key=lambda kv: -kv[1][1]):
            print(f"       {k:<62} {c:>6,}  S/ {s:>12,.0f}")
    print()


def volumen(tasa):
    cal_anc = MV.leer_insumos(AL_1)[1]
    anc = sum(s for d, v in cal_anc.items() if 2 <= d <= ULTIMO_DIA for s in v.values())
    med = total(cal_desde("E. calendario medido sep"))
    ent_e = sum(num(r["saldo_2"]) for r in bloque("E. calendario medido sep") if 2 <= int(r["k1"]) <= ULTIMO_DIA)
    real = total(cal_desde("D. entradas reales v2 sep", lambda r: r["k3"] == "0|0"))
    print("=" * 100)
    print(f"2. VOLUMEN DE ENTRADAS, dias 2-{ULTIMO_DIA} -- tasa calibrada {100*tasa:.2f}% (arrastre fuera)")
    print("=" * 100)
    print(f"  calendario anclado al 31-ago (la meta)   S/ {anc:>12,.0f}  x tasa = esperado S/ {anc*tasa:>11,.0f}")
    print(f"  calendario medido al vencimiento         S/ {med:>12,.0f}  x tasa = esperado S/ {med*tasa:>11,.0f}"
          f"   (ancla: {100*(anc/med-1):+.1f}%)")
    print(f"  entradas reales (sin arrastre)                                    real   S/ {real:>11,.0f}"
          f"   ({100*(real/(med*tasa)-1):+.1f}% contra el medido)")
    print(f"  tasa realizada de septiembre, dias 2-{ULTIMO_DIA}: {100*ent_e/med:.2f}% (con arrastre, misma definicion que el bloque C)")
    print(f"  -- tasa de entrada de los dias 2-12 por mes (v2; con arrastre):")
    for r in bloque("C. tasa realizada dias 2-12"):
        t = num(r["saldo_2"]) / num(r["saldo_1"])
        print(f"       {r['k1']}  elegibles S/ {num(r['saldo_1']):>12,.0f}   entran S/ {num(r['saldo_2']):>11,.0f}   {100*t:>6.2f}%")
    print()


def tres_capas(medida, titulo):
    n = ULTIMO_DIA
    c = MV.curvas(PERIODO, medida)
    stock, cal_anc = MV.leer_insumos(AL_1, solo_d1=False)
    d1 = MV.por_banda(MV.leer_insumos(AL_1, solo_d1=True)[0])
    cal_med = cal_desde("E. calendario medido sep")
    cal_real = cal_desde("D. entradas reales v2 sep", lambda r: r["k3"] == "0|0")
    capas = [("a. meta al 1-sep (calendario anclado)", MV.proyectar_mes(c, PERIODO, stock, cal_anc, d1)),
             ("b. calendario medido al vencimiento", MV.proyectar_mes(c, PERIODO, stock, cal_med, d1)),
             ("c. entradas reales, curva sin tasa", MV.proyectar_mes((*c[:4], 1.0), PERIODO, stock, cal_real, d1))]
    real = real_v2(medida)
    rs, rn = acumular_real(real["stock"], n), acumular_real(real["nuevos"], n)
    rt = [a + b for a, b in zip(rs, rn)]
    print("=" * 100)
    print(f"3. BACKTEST EN TRES CAPAS AL {n:02d}-SEP -- {titulo} (tasa {100*c[4]:.2f}%)")
    print("=" * 100)
    print(f"  {'':<40} | {'proy nuevos':>12} {'real nuevos':>12} {'real/proy':>9} {'corr':>6} | "
          f"{'proy total':>12} {'real total':>12} {'real/proy':>9}")
    for nombre, filas in capas:
        pn = [x["proy_nuevos"] for x in filas[:n]]
        pt = [x["proy_total"] for x in filas[:n]]
        print(f"  {nombre:<40} | {pn[-1]:>12,.0f} {rn[-1]:>12,.0f} {rn[-1]/pn[-1]:>9.3f} "
              f"{statistics.correlation(inc(pn), inc(rn)):>6.3f} | {pt[-1]:>12,.0f} {rt[-1]:>12,.0f} {rt[-1]/pt[-1]:>9.3f}")
    ps = [x["proy_stock"] for x in capas[0][1][:n]]
    print(f"  4. STOCK (igual en las 3 capas): proyectado S/ {ps[-1]:,.0f}, real S/ {rs[-1]:,.0f} -> "
          f"{rs[-1]/ps[-1]:.3f}, corr diaria {statistics.correlation(inc(ps), inc(rs)):.3f}")
    print()


if __name__ == "__main__":
    universo_nuevos()
    volumen(MV.curvas(PERIODO, "act")[4])
    tres_capas("act", "CAPITAL ASEGURADO")
    tres_capas("reb", "RECUPERO OFICIAL")

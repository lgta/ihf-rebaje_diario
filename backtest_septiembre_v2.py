"""
TAREA 24 -- VALIDACION DEL FIX CON SEPTIEMBRE: backtest de la logica con la que el motor v2
dimensiona stock y nuevos, contra lo que paso. Pedido del usuario 2026-09-13.

REHECHO EL MISMO 13-SEP (tarea 25) CON EL MOTOR ADOPTADO: reenganches INCLUIDOS (bug 25) y la
tasa ANCLADA (bug 28). `python backtest_septiembre_v2.py 12 reeng_fuera` corre con los
reenganches fuera, como la validacion original.

Insumos (locales):
  datos_tarea24/v2_dimensionamiento_sep.csv  tarea24_v2_dimensionamiento_sep.sql: bloques B
                                             (universo) y D (entradas reales)
  datos_tarea24/v2_septiembre_al_1.csv       stock v2 del dia 1 y calendario anclado (la meta)
  datos_tarea24/v2_septiembre.csv            real v2 por dia (tarea24_v2_septiembre.sql)
  curvas_v2.CT, periodo 202609 (parcial)     calendario MEDIDO y ANCLADO de los dias 2-12, con
                                             o sin reenganches (tarea25_calendario_tasa.sql). Sin
                                             reenganches, el medido reproduce al sol el bloque E
                                             de la validacion original; con reenganches, el
                                             anclado reproduce al sol el calendario de la meta.

Cuatro preguntas:
  1. UNIVERSO DE NUEVOS: ¿nuestras entradas v2 son los nuevos que el negocio asigna a TEMPRANA?
     (el stock ya se cuadro contra la vista credito a credito: +0.5%)
  2. VOLUMEN: ¿entro lo que calendario x tasa esperaba? Separa el ancla de la tasa realizada y
     compara los dias 2-N de septiembre con los mismos dias de los meses anteriores.
  3. BACKTEST EN CAPAS al dia N, con la misma curva:
       a.  la META al 1-sep: calendario anclado x tasa ANCLADA   (motor adoptado)
       a0. calendario anclado x tasa medida                      -> la meta con el bug 28
       b.  calendario MEDIDO x tasa medida                       -> sin el efecto del ancla
       c.  las entradas REALES, con la curva y sin tasa           -> sin el efecto de la tasa
     Lo que queda en (c) es conversion. Con el bug 28 corregido, (a) queda cerca de (b): las
     separa cuanto se aparta el ancla de estos dias de septiembre de la de la ventana.
  4. STOCK: la curva de stock contra el real del stock observado el dia 1 (igual en todas).

Uso: python backtest_septiembre_v2.py [ultimo dia completo, default 12] [reeng_fuera]
"""
import collections
import csv
import statistics
import sys

import curvas_v2 as V
import motor_v2 as MV
from motor_unificado import acumular_real

PERIODO = "202609"
DIM = "datos_tarea24/v2_dimensionamiento_sep.csv"
AL_1 = "datos_tarea24/v2_septiembre_al_1.csv"
REAL = "datos_tarea24/v2_septiembre.csv"
ULTIMO_DIA = int(sys.argv[1]) if len(sys.argv) > 1 else 12
REENG = False if (len(sys.argv) > 2 and sys.argv[2] == "reeng_fuera") else MV.REENG
K3_D = ("0|0", "0|1") if REENG else ("0|0",)     # bloque D: 'arrastre|reeng'

with open(DIM) as f:
    FILAS = list(csv.DictReader(f))

_HASTA = max(V.calendario("v2", PERIODO, True))
if ULTIMO_DIA > _HASTA:
    raise SystemExit(f"{V.CT} trae septiembre hasta el dia {_HASTA}. Para cortar al {ULTIMO_DIA}, re-correr "
                     "tarea25_calendario_tasa.sql, tarea24_v2_dimensionamiento_sep.sql y "
                     "tarea24_v2_septiembre.sql con las fechas corridas hasta ese dia.")


def bloque(nombre):
    return [r for r in FILAS if r["bloque"] == nombre]


def num(x):
    return float(x) if x not in ("", None) else 0.0


def real_v2(medida):
    """{componente: {dia: activado o rebajado}}, arrastre fuera. Stock: el universo de la meta
    (con los reenganches posteriores al 1-sep). Nuevos: con o sin reenganches segun REENG."""
    col = "saldo" if medida == "act" else "rebaje"
    out = {"stock": collections.defaultdict(float), "nuevos": collections.defaultdict(float)}
    with open(REAL) as f:
        for r in csv.DictReader(f):
            if r["bloque"] != "real" or r["arrastre"] == "1":
                continue
            if r["componente"] == "nuevos" and r["reeng"] == "1" and not REENG:
                continue
            out[r["componente"]][int(r["dia"])] += num(r[col])
    return out


def cal_desde(nombre, filtro=lambda r: True):
    """{dia_entrada: {banda: saldo}} desde el bloque D, dias 2..ULTIMO_DIA."""
    cal = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in bloque(nombre):
        d = int(r["k1"])
        if 2 <= d <= ULTIMO_DIA and filtro(r):
            cal[d][r["k2"]] += num(r["saldo_1"])
    return {d: dict(v) for d, v in cal.items()}


def cal_ct(ancla):
    """{dia_entrada: {banda: saldo}} de septiembre desde la matriz de calibracion, dias 2..N."""
    return {d: v for d, v in V.calendario("v2", PERIODO, REENG, ancla=ancla).items()
            if 2 <= d <= ULTIMO_DIA}


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


def volumen(p_med, p_anc):
    n = ULTIMO_DIA
    cal_meta = MV.leer_insumos(AL_1, reeng=REENG)[1]
    anc = sum(s for d, v in cal_meta.items() if 2 <= d <= n for s in v.values())
    anc_ct, med = total(cal_ct(True)), total(cal_ct(False))
    real = total(cal_desde("D. entradas reales v2 sep", lambda r: r["k3"] in K3_D))
    print("=" * 100)
    print(f"2. VOLUMEN DE ENTRADAS, dias 2-{n} -- tasa medida {100*p_med:.2f}%, anclada {100*p_anc:.2f}% "
          f"(arrastre fuera)")
    print("=" * 100)
    print(f"  calendario anclado al 31-ago (la meta)   S/ {anc:>12,.0f}  x tasa anclada = esperado S/ {anc*p_anc:>11,.0f}"
          f"   <- la meta")
    print(f"  {'':<42}{'':>12}  x tasa medida  = esperado S/ {anc*p_med:>11,.0f}   (bug 28)")
    print(f"  calendario medido al vencimiento         S/ {med:>12,.0f}  x tasa medida  = esperado S/ {med*p_med:>11,.0f}"
          f"   (ancla {100*(anc/med-1):+.1f}%)")
    print(f"  entradas reales (sin arrastre)           {'':>14}{'':>31}real S/ {real:>11,.0f}")
    print(f"     {100*(real/(anc*p_anc)-1):+.1f}% contra la meta, {100*(real/(anc*p_med)-1):+.1f}% contra la meta con el bug,"
          f" {100*(real/(med*p_med)-1):+.1f}% contra el medido")
    print(f"  control: el calendario anclado desde la matriz de calibracion da S/ {anc_ct:,.0f} "
          f"({100*(anc_ct/anc-1):+.2f}% contra los insumos de la meta)")
    ventana = MV.ventana_meta(PERIODO)
    tm_med = V.tasa_mensual("v2", MV.ARRASTRE, REENG, dias=(2, n))
    tm_anc = V.tasa_mensual("v2", MV.ARRASTRE, REENG, ancla=True, dias=(2, n))
    filas = [(p, *tm_med[p], *tm_anc[p]) for p in sorted(tm_med) if p >= "202601"]
    filas.append((f"{ventana[0]}-{ventana[1][2:]}",
                  *[sum(tm[p][i] for p in tm if ventana[0] <= p <= ventana[1])
                    for tm in (tm_med, tm_anc) for i in (0, 1)]))
    print(f"  -- los dias 2-{n} de cada mes (arrastre fuera, reenganches {'dentro' if REENG else 'fuera'}); "
          f"la ultima fila es la ventana de la meta:")
    print(f"       {'mes':<11} {'medido':>13} {'anclado':>13} {'anc/med':>8} {'tasa medida':>12} {'tasa anclada':>13}")
    for p, e_m, n_m, e_a, n_a in filas:
        print(f"       {p:<11} {e_m:>13,.0f} {e_a:>13,.0f} {e_a/e_m:>8.3f} {100*n_m/e_m:>11.2f}% {100*n_a/e_a:>12.2f}%")
    print()


def tres_capas(medida, titulo, c, p_anc):
    n = ULTIMO_DIA
    stock, cal_anc = MV.leer_insumos(AL_1, reeng=REENG, solo_d1=False)
    d1 = MV.por_banda(MV.leer_insumos(AL_1, reeng=REENG, solo_d1=True)[0])
    cal_real = cal_desde("D. entradas reales v2 sep", lambda r: r["k3"] in K3_D)
    capas = [("a.  META al 1-sep: anclado x tasa anclada", MV.proyectar_mes((*c[:4], p_anc), PERIODO, stock, cal_anc, d1)),
             ("a0. anclado x tasa medida (bug 28)", MV.proyectar_mes(c, PERIODO, stock, cal_anc, d1)),
             ("b.  calendario medido x tasa medida", MV.proyectar_mes(c, PERIODO, stock, cal_ct(False), d1)),
             ("c.  entradas reales, curva sin tasa", MV.proyectar_mes((*c[:4], 1.0), PERIODO, stock, cal_real, d1))]
    real = real_v2(medida)
    rs, rn = acumular_real(real["stock"], n), acumular_real(real["nuevos"], n)
    rt = [a + b for a, b in zip(rs, rn)]
    print("=" * 110)
    print(f"3. BACKTEST EN CAPAS AL {n:02d}-SEP -- {titulo} (tasa medida {100*c[4]:.2f}%, anclada {100*p_anc:.2f}%)")
    print("=" * 110)
    print(f"  {'':<42} | {'proy nuevos':>12} {'real nuevos':>12} {'real/proy':>9} {'corr':>6} | "
          f"{'proy total':>12} {'real total':>12} {'real/proy':>9}")
    for nombre, filas in capas:
        pn = [x["proy_nuevos"] for x in filas[:n]]
        pt = [x["proy_total"] for x in filas[:n]]
        print(f"  {nombre:<42} | {pn[-1]:>12,.0f} {rn[-1]:>12,.0f} {rn[-1]/pn[-1]:>9.3f} "
              f"{statistics.correlation(inc(pn), inc(rn)):>6.3f} | {pt[-1]:>12,.0f} {rt[-1]:>12,.0f} {rt[-1]/pt[-1]:>9.3f}")
    ps = [x["proy_stock"] for x in capas[0][1][:n]]
    print(f"  4. STOCK (igual en todas las capas): proyectado S/ {ps[-1]:,.0f}, real S/ {rs[-1]:,.0f} -> "
          f"{rs[-1]/ps[-1]:.3f}, corr diaria {statistics.correlation(inc(ps), inc(rs)):.3f}")
    print()


if __name__ == "__main__":
    print(f"Motor v2, arrastre fuera, reenganches {'INCLUIDOS' if REENG else 'FUERA'}; real al {ULTIMO_DIA:02d}-sep\n")
    universo_nuevos()
    c_act = MV.curvas(PERIODO, "act", reeng=REENG, ancla=False)
    p_anc = V.tasa(V.tasa_mensual("v2", MV.ARRASTRE, REENG, ancla=True), *MV.ventana_meta(PERIODO))
    volumen(c_act[4], p_anc)
    tres_capas("act", "CAPITAL ASEGURADO", c_act, p_anc)
    tres_capas("reb", "RECUPERO OFICIAL", MV.curvas(PERIODO, "reb", reeng=REENG, ancla=False), p_anc)

"""
TAREA 19 -- LA CAIDA DE ACTIVACION, ES COMPOSICION? (2026-09-14)

Pregunta 2 del frente abierto de tarea 19: si la cartera nueva entra con otra mezcla (banda de
avance, dia de semana del vencimiento, parte del mes, reenganches), la caida de la activacion
podria ser mezcla y no eficiencia. Se mide sin Athena, con la matriz de nuevos vigente
(curvas_v2.MN) y los filtros de produccion del motor v2: definicion v2, arrastre por DNI fuera,
reenganches incluidos.

Dos medidas de conversion por mes de entrada, las dos sobre el saldo de entrada:
  H30        activo (>= 1 pago) dentro de los 30 dias desde la entrada. Horizonte fijo: mide
             comportamiento sin la truncacion del fin de mes. Solo meses con 30 dias de fotos
             despues de su ultima entrada (hasta 202607 con la matriz de tarea 24).
  en el mes  activo dentro del mismo mes calendario, lo que cuenta la meta. Depende ademas de en
             que dia del mes entra la gente.

Descomposicion shift-share de REC contra REF, para cada segmentacion:
  C(rec) - C(ref) = sum (w_rec - w_ref) c_ref          mezcla
                  + sum w_ref (c_rec - c_ref)           conversion dentro del segmento
                  + sum (w_rec - w_ref)(c_rec - c_ref)  interaccion
w = peso del segmento en el saldo de entrada, c = conversion del segmento.
Y la tendencia mensual con la mezcla fija (pesos de toda la ventana): si la pendiente casi no
cambia, la mezcla no explica la caida.

Uso: python tarea19_composicion_activacion.py > datos_tarea19/composicion_activacion.log
"""
import collections
import csv
import datetime as dt

import curvas_v2 as V

H = 30
REF = ("202601", "202603")        # ene-mar 2026: el nivel alto de tarea 19
REC_H30 = ("202605", "202607")    # los tres ultimos meses con H dias completos
REC_MES = ("202606", "202608")    # jun-ago, el periodo de tarea 19
FOTOS = V._fecha(V.FOTOS_NUEVOS_HASTA)
SALIDA = "datos_tarea19/composicion_activacion.csv"

DOW = {1: "lun", 2: "mar", 3: "mie", 4: "jue", 5: "vie", 6: "sab", 7: "dom"}
# indices sobre la clave (periodo, banda, dow, tercio, reeng)
SEGMENTACIONES = [
    ("banda de avance", (1,)),
    ("dia de semana del venc.", (2,)),
    ("banda x dia de semana (la curva)", (1, 2)),
    ("tercio del mes de entrada", (3,)),
    ("reenganche", (4,)),
    ("banda x dow x tercio x reeng", (1, 2, 3, 4)),
]


def tercio(dia):
    return "02-10" if dia <= 10 else ("11-20" if dia <= 20 else "21-31")


def fin_de_mes(periodo):
    y, m = int(periodo[:4]), int(periodo[4:])
    return dt.date(y + (m == 12), m % 12 + 1, 1) - dt.timedelta(days=1)


def completo_h30(p):
    return fin_de_mes(p) + dt.timedelta(days=H) <= FOTOS


def completo_mes(p):
    return fin_de_mes(p) <= FOTOS


def cargar():
    """{(periodo, banda, dow, tercio, reeng): [base, act_H30, act_mes, creditos]}."""
    cel = collections.defaultdict(lambda: [0.0, 0.0, 0.0, 0.0])
    for r in V._leer(V.MN):
        if not V._pasa(r, "fuera", True) or not V._es_nuevo(r, "v2", para_curva=True):
            continue
        fe = V._fecha(r["fecha_entrada"])
        k = (fe.strftime("%Y%m"), r["avance_band"], (fe - dt.timedelta(days=1)).weekday() + 1,
             tercio(fe.day), r["reeng"])
        s = float(r["saldo"])
        if r["tipo"] == "base":
            cel[k][0] += s
            cel[k][3] += float(r["creditos"])
        elif r["tipo"] == "act":
            d = int(r["dia"])
            if d <= H:
                cel[k][1] += s
            if (fe + dt.timedelta(days=d)).month == fe.month:
                cel[k][2] += s
    return cel


def agrupar(cel, dims, desde, hasta, col):
    """{seg: [base, act]} sumando los meses [desde, hasta]; col 1 = H30, 2 = en el mes."""
    out = collections.defaultdict(lambda: [0.0, 0.0])
    for k, v in cel.items():
        if desde <= k[0] <= hasta:
            seg = tuple(k[i] for i in dims)
            out[seg][0] += v[0]
            out[seg][1] += v[col]
    return dict(out)


def conv(g):
    return sum(v[1] for v in g.values()) / sum(v[0] for v in g.values())


def shift_share(ref, rec):
    br = sum(v[0] for v in ref.values())
    bm = sum(v[0] for v in rec.values())
    mezcla = dentro = inter = 0.0
    for s in set(ref) | set(rec):
        wr = ref[s][0] / br if s in ref else 0.0
        wm = rec[s][0] / bm if s in rec else 0.0
        cr = ref[s][1] / ref[s][0] if s in ref and ref[s][0] else None
        cm = rec[s][1] / rec[s][0] if s in rec and rec[s][0] else None
        if cr is None and cm is None:
            continue
        cr = cm if cr is None else cr
        cm = cr if cm is None else cm
        mezcla += (wm - wr) * cr
        dentro += wr * (cm - cr)
        inter += (wm - wr) * (cm - cr)
    return conv(rec) - conv(ref), mezcla, dentro, inter


def serie_mezcla_fija(cel, dims, meses, col):
    """Conversion de cada mes con los pesos de segmento de todos los `meses` juntos."""
    pesos = agrupar(cel, dims, meses[0], meses[-1], col)
    btot = sum(v[0] for v in pesos.values())
    out = []
    for p in meses:
        g = agrupar(cel, dims, p, p, col)
        out.append(sum(b / btot * (g[s][1] / g[s][0] if s in g and g[s][0] else a / b)
                       for s, (b, a) in pesos.items()))
    return out


def pendiente(serie):
    """OLS contra el indice del mes: (pp por mes, r)."""
    xs = range(len(serie))
    ys = [100 * y for y in serie]
    mx, my = sum(xs) / len(serie), sum(ys) / len(ys)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    return sxy / sxx, sxy / (sxx * syy) ** 0.5


def pct(x):
    return "   --  " if x is None else f"{100 * x:6.2f}%"


def main():
    cel = cargar()
    periodos = sorted({k[0] for k in cel})
    meses_mes = [p for p in periodos if completo_mes(p)]
    meses_h30 = [p for p in meses_mes if completo_h30(p)]

    print("=" * 100)
    print(f"TAREA 19 -- COMPOSICION DE LA CAIDA DE ACTIVACION. Matriz {V.MN} (fotos hasta {V.FOTOS_NUEVOS_HASTA})")
    print("Nuevos v2, arrastre por DNI fuera, reenganches incluidos (filtros de produccion). Todo en saldo de entrada.")
    print("=" * 100)

    # 1. serie mensual y mezcla -------------------------------------------------------------
    print("\n1. POR MES DE ENTRADA\n")
    print(f"{'mes':>7} {'saldo entrada':>15} {'creditos':>9} {'ticket':>8} {'conv H30':>9} {'en el mes':>10}"
          f" {'banda a':>8} {'banda d':>8} {'reeng':>7} {'dias 21-31':>10} {'vence sab':>9}")
    filas = []
    for p in meses_mes:
        g = {k: v for k, v in cel.items() if k[0] == p}
        base = sum(v[0] for v in g.values())
        cred = sum(v[3] for v in g.values())

        def peso(f):
            return sum(v[0] for k, v in g.items() if f(k)) / base
        fila = {
            "periodo": p, "saldo": base, "creditos": cred, "ticket": base / cred,
            "conv_h30": sum(v[1] for v in g.values()) / base if completo_h30(p) else None,
            "conv_mes": sum(v[2] for v in g.values()) / base,
            "banda_a": peso(lambda k: k[1].startswith("a.")),
            "banda_d": peso(lambda k: k[1].startswith("d.")),
            "reeng": peso(lambda k: k[4] == "1"),
            "dias_21_31": peso(lambda k: k[3] == "21-31"),
            "vence_sab": peso(lambda k: k[2] == 6),
        }
        filas.append(fila)
        print(f"{p:>7} {base:>15,.0f} {cred:>9,.0f} {fila['ticket']:>8,.0f} {pct(fila['conv_h30']):>9}"
              f" {pct(fila['conv_mes']):>10} {pct(fila['banda_a']):>8} {pct(fila['banda_d']):>8}"
              f" {pct(fila['reeng']):>7} {pct(fila['dias_21_31']):>10} {pct(fila['vence_sab']):>9}")

    # 2. tendencia observada vs. con la mezcla fija ------------------------------------------
    print("\n2. TENDENCIA (pp por mes, OLS). Si con la mezcla fija la pendiente casi no cambia, la mezcla no explica la caida.\n")
    tramos = [("2026-01 a 2026-07", "202601", "202607"),
              ("12 meses 2025-08 a 2026-07", "202508", "202607"),
              ("todo 2025-01 a 2026-07", "202501", "202607")]
    for col, nombre, meses_ok in ((1, "conv H30", meses_h30), (2, "en el mes", meses_mes)):
        print(f"  {nombre}:")
        print(f"    {'segmentacion con mezcla fija':<36}" + "".join(f"{t:>30}" for t, _, _ in tramos))
        lineas = collections.OrderedDict()
        for t, d, h in tramos:
            meses = [p for p in meses_ok if d <= p <= h]
            obs = [conv(agrupar(cel, (1,), p, p, col)) for p in meses]
            lineas.setdefault("observada", []).append(pendiente(obs))
            for nom, dims in SEGMENTACIONES:
                lineas.setdefault(nom, []).append(pendiente(serie_mezcla_fija(cel, dims, meses, col)))
        for nom, vals in lineas.items():
            print(f"    {nom:<36}" + "".join(f"{f'{m:+.3f} (r={r:+.2f})':>30}" for m, r in vals))
        print()

    # 3. shift-share -------------------------------------------------------------------------
    for col, nombre, rec in ((1, "conv H30", REC_H30), (2, "en el mes", REC_MES)):
        cr = conv(agrupar(cel, (1,), *REF, col))
        cm = conv(agrupar(cel, (1,), *rec, col))
        print(f"3. SHIFT-SHARE, {nombre}: {REF[0]}-{REF[1]} {pct(cr)} -> {rec[0]}-{rec[1]} {pct(cm)}"
              f"  (cambio {100 * (cm - cr):+.2f}pp)\n")
        print(f"    {'segmentacion':<36}{'total':>9}{'mezcla':>9}{'dentro':>9}{'interac.':>9}   mezcla / total")
        for nom, dims in SEGMENTACIONES:
            tot, mez, den, inte = shift_share(agrupar(cel, dims, *REF, col), agrupar(cel, dims, *rec, col))
            print(f"    {nom:<36}{100 * tot:>+8.2f}p{100 * mez:>+8.2f}p{100 * den:>+8.2f}p{100 * inte:>+8.2f}p"
                  f"   {mez / tot:>7.1%}")
        print()

    # 4. la caida, segmento por segmento -----------------------------------------------------
    print(f"4. CONV H30 POR SEGMENTO, {REF[0]}-{REF[1]} vs. {REC_H30[0]}-{REC_H30[1]}: cae en todos o solo en algunos?\n")
    for nom, dims in SEGMENTACIONES[:2] + SEGMENTACIONES[3:5]:
        ref = agrupar(cel, dims, *REF, 1)
        rec = agrupar(cel, dims, *REC_H30, 1)
        br, bm = sum(v[0] for v in ref.values()), sum(v[0] for v in rec.values())
        print(f"  {nom}")
        print(f"    {'segmento':<18}{'peso ref':>9}{'peso rec':>9}{'conv ref':>9}{'conv rec':>9}{'cambio':>9}")
        for s in sorted(set(ref) | set(rec)):
            etiqueta = DOW[s[0]] if dims == (2,) else str(s[0])
            wr, wm = ref.get(s, [0, 0])[0] / br, rec.get(s, [0, 0])[0] / bm
            c_r = ref[s][1] / ref[s][0] if s in ref else None
            c_m = rec[s][1] / rec[s][0] if s in rec else None
            cambio = f"{100 * (c_m - c_r):+8.2f}p" if c_r is not None and c_m is not None else "      --"
            print(f"    {etiqueta:<18}{pct(wr):>9}{pct(wm):>9}{pct(c_r):>9}{pct(c_m):>9}{cambio:>9}")
        print()

    # 5. la cadena de tarea 19 en v2 ---------------------------------------------------------
    # activado en el mes / calendario = (entran / calendario) x (activado / base de la matriz)
    #                                   x (base de la matriz / entran), el ultimo es el control de
    # que la tasa (una cuota por credito) y la matriz (cada entrada) cuentan lo mismo (tarea 21).
    tm = {"med": V.tasa_mensual("v2", "fuera", True, ancla=False),
          "anc": V.tasa_mensual("v2", "fuera", True, ancla=True)}
    fil = {f["periodo"]: f for f in filas if f["periodo"] <= V.CALENDARIO_HASTA}
    print("5. LA CADENA DE TAREA 19 EN v2: activado en el mes / calendario = tasa x conversion x control\n")
    print(f"{'mes':>7} {'calend. medido':>15} {'calend. anclado':>16} {'entran':>12} {'base matriz':>12}"
          f" {'tasa med':>9} {'tasa anc':>9} {'conv mes':>9} {'act/cal med':>12} {'act/cal anc':>12}")
    for p, f in fil.items():
        em, nm = tm["med"][p]
        ea, _ = tm["anc"][p]
        act = f["conv_mes"] * f["saldo"]
        print(f"{p:>7} {em:>15,.0f} {ea:>16,.0f} {nm:>12,.0f} {f['saldo']:>12,.0f} {pct(nm / em):>9}"
              f" {pct(tm['anc'][p][1] / ea):>9} {pct(f['conv_mes']):>9} {pct(act / em):>12} {pct(act / ea):>12}")

    def cadena(d, h, cual):
        ps = [p for p in fil if d <= p <= h]
        e = sum(tm[cual][p][0] for p in ps)
        n = sum(tm[cual][p][1] for p in ps)
        b = sum(fil[p]["saldo"] for p in ps)
        a = sum(fil[p]["conv_mes"] * fil[p]["saldo"] for p in ps)
        return {"act/cal": a / e, "tasa": n / e, "conversion": a / b, "control base/entran": b / n}

    for cual, nombre in (("med", "calendario medido (saldo al vencimiento)"),
                         ("anc", "calendario anclado (saldo del cierre anterior, el de la meta)")):
        r0, r1 = cadena(*REF, cual), cadena(*REC_MES, cual)
        print(f"\n  {nombre}: {REF[0]}-{REF[1]} -> {REC_MES[0]}-{REC_MES[1]}")
        for k in r0:
            print(f"    {k:<22}{pct(r0[k]):>9} -> {pct(r1[k]):>9}   {r1[k] / r0[k] - 1:+7.1%}")
        meses = [p for p in fil if "202601" <= p <= "202607"]
        pen = pendiente([cadena(p, p, cual)["act/cal"] for p in meses])
        print(f"    pendiente de act/cal 2026-01 a 2026-07: {pen[0]:+.3f}pp/mes (r={pen[1]:+.2f})")
    print()

    # 6. el arranque del mes: lo que mide el seguimiento ---------------------------------------
    # seguimiento_v2 compara el activado por sol que entro con las entradas de los dias 2 a N y lo
    # activado hasta el dia N: pesa sobre todo los primeros dias desde la entrada (velocidad), no la
    # conversion a 30 dias. Septiembre 2026 al dia 12 (seguimiento_v2_202609_control.log): real 0.649,
    # proyectado 0.731.
    n = 12
    arr = collections.defaultdict(lambda: [0.0, 0.0])
    for r in V._leer(V.MN):
        if not V._pasa(r, "fuera", True) or not V._es_nuevo(r, "v2", para_curva=True):
            continue
        fe = V._fecha(r["fecha_entrada"])
        if fe.day > n:
            continue
        p = fe.strftime("%Y%m")
        if r["tipo"] == "base":
            arr[p][0] += float(r["saldo"])
        elif r["tipo"] == "act" and fe.day + int(r["dia"]) <= n:
            arr[p][1] += float(r["saldo"])
    ok = [p for p in sorted(arr) if dt.date(int(p[:4]), int(p[4:]), n) <= FOTOS]
    print(f"6. ACTIVADO POR SOL QUE ENTRO: entradas de los dias 2-{n}, activado hasta el dia {n} (lo que mide el seguimiento)\n")
    print(f"{'mes':>7} {'entro dias 2-12':>16} {'activado/entro':>15}")
    for p in ok:
        print(f"{p:>7} {arr[p][0]:>16,.0f} {arr[p][1] / arr[p][0]:>15.3f}")
    ult = [arr[p][1] / arr[p][0] for p in ok[-12:]]
    print(f"\n  ultimos 12 meses ({ok[-12]}-{ok[-1]}): min {min(ult):.3f} | media {sum(ult) / len(ult):.3f} | max {max(ult):.3f}")
    print("  septiembre 2026 al dia 12 (seguimiento_v2): real 0.649, proyectado 0.731\n")

    # 7. velocidad: cuando paga el que activa --------------------------------------------------
    # Si la conversion a 30 dias casi no cambia pero el arranque del mes cae, la gente paga mas
    # tarde. Se mide como la parte de lo activado a 30 dias que ya habia activado k dias despues de
    # la entrada, por mes, observada y con la mezcla banda x dow x tercio fija (pesos = lo activado
    # a 30 dias de todos los meses juntos).
    ks = (0, 3, 7, 14)
    vel = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in V._leer(V.MN):
        if r["tipo"] != "act" or not V._pasa(r, "fuera", True) or not V._es_nuevo(r, "v2", para_curva=True):
            continue
        fe = V._fecha(r["fecha_entrada"])
        p, d = fe.strftime("%Y%m"), int(r["dia"])
        if p not in meses_h30 or d > H:
            continue
        seg = (r["avance_band"], (fe - dt.timedelta(days=1)).weekday() + 1, tercio(fe.day))
        s = float(r["saldo"])
        vel[(p, seg)]["H"] += s
        for k in ks:
            if d <= k:
                vel[(p, seg)][k] += s
    pool = collections.defaultdict(lambda: collections.defaultdict(float))
    for (p, seg), v in vel.items():
        for c, s in v.items():
            pool[seg][c] += s
    htot = sum(v["H"] for v in pool.values())

    def parte(p, k, fija, filtro=lambda seg: True):
        segs = [s for s in pool if filtro(s)]
        if not fija:
            num = sum(vel[(p, s)][k] for s in segs if (p, s) in vel)
            return num / sum(vel[(p, s)]["H"] for s in segs if (p, s) in vel)
        w = sum(pool[s]["H"] for s in segs)
        return sum(pool[s]["H"] / w * (vel[(p, s)][k] / vel[(p, s)]["H"] if (p, s) in vel and vel[(p, s)]["H"]
                                       else pool[s][k] / pool[s]["H"]) for s in segs)

    print("7. VELOCIDAD: de lo activado a 30 dias, que parte ya habia activado k dias despues de la entrada\n")
    print(f"{'mes':>7}" + "".join(f"{f'k<={k}':>9}" for k in ks) + f"{'k<=7 mezcla fija':>18}")
    for p in meses_h30:
        print(f"{p:>7}" + "".join(f"{pct(parte(p, k, False)):>9}" for k in ks) + f"{pct(parte(p, 7, True)):>18}")

    def periodo(d, h, k, fija, filtro=lambda seg: True):
        ps = [p for p in meses_h30 if d <= p <= h]
        return sum(parte(p, k, fija, filtro) for p in ps) / len(ps)

    print(f"\n  promedio de los meses, {REF[0]}-{REF[1]} -> {REC_H30[0]}-{REC_H30[1]}:")
    for k in ks:
        a, b = periodo(*REF, k, False), periodo(*REC_H30, k, False)
        af, bf = periodo(*REF, k, True), periodo(*REC_H30, k, True)
        print(f"    k<={k:<3} observada {pct(a)} -> {pct(b)} ({100 * (b - a):+.2f}pp)"
              f"   mezcla fija {pct(af)} -> {pct(bf)} ({100 * (bf - af):+.2f}pp)")
    print("\n  k<=7 por tercio del mes de entrada (mezcla banda x dow fija dentro del tercio):")
    for t in ("02-10", "11-20", "21-31"):
        a = periodo(*REF, 7, True, lambda seg, t=t: seg[2] == t)
        b = periodo(*REC_H30, 7, True, lambda seg, t=t: seg[2] == t)
        print(f"    entra dias {t}: {pct(a)} -> {pct(b)} ({100 * (b - a):+.2f}pp)")
    print(f"\n  (control: lo activado a 30 dias de todos los meses suma S/ {htot:,.0f})\n")

    with open(SALIDA, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(filas[0]))
        w.writeheader()
        w.writerows(filas)
    print(f"Serie mensual en {SALIDA}")


if __name__ == "__main__":
    main()

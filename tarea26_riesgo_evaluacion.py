"""
TAREA 26 -- EVALUACION: ¿el riesgo de cobranza corta las curvas? (pedido del usuario 2026-09-15)
Solo evaluación: no toca motor_v2, curvas_v2 ni ninguna matriz o meta vigente.

    python tarea26_riesgo_evaluacion.py > datos_tarea26/evaluacion_riesgo.log

Lee datos_tarea26/riesgo_matriz_{nuevos,stock}.csv (tarea26_riesgo_matriz_*.sql): el universo de las
curvas v2 (arrastre fuera, reenganches incluidos, stock sin la cohorte del día 1) con el modelo de
cobranza de la cuota en mora (prediccion_riesgo_modelo_cobranza y segmento_modelo_cobranza). Mide:
  1. cobertura del puntaje y mezcla por mes;
  2. curvas acumuladas de REBAJE (recupero) y ACTIVACIÓN (capital asegurado) por nivel de riesgo;
  3. si el riesgo separa DENTRO de los segmentadores que ya usa el modelo (banda de avance en
     nuevos; tramo x avance en stock): eso dice si trae información nueva o repite la que ya está;
  4. estabilidad del orden mes a mes;
  5. cuánto movería la expectativa de cada mes el cambio de mezcla por riesgo (shift-share con las
     tasas de la ventana; in-sample, es una medida de materialidad, no un backtest).
Adoptarlo como segmentador exigiría además el walk-forward con métricas diarias (CLAUDE.md).
Deja lo necesario para graficar en datos_tarea26/evaluacion_riesgo.json.
"""
import collections
import csv
import json

VENTANA = ("202508", "202607")   # la de la meta de septiembre (motor_v2.ventana_meta)
RIESGOS = ["1. Riesgo Bajo", "2. Riesgo Medio", "3. Riesgo Alto", "sin puntaje"]
SEGS = ["1. MAX_DIASMORA 1-4", "2. MAX_DIASMORA 5-16", "3. MAX_DIASMORA +16", "sin puntaje"]
BANDAS = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]
K_HITOS, D_HITOS = (0, 1, 3, 7, 15, 30), (1, 5, 10, 15, 20, 31)
K_FIN, D_FIN = 30, 31
HTML = "riesgo_cobranza.html"   # artifact «Riesgo de cobranza en las curvas»; recibe los datos al final


def corto(x):
    return x if x == "sin puntaje" else x.split(". ", 1)[1].replace("Riesgo ", "").replace("MAX_DIASMORA ", "máx. ")


def leer(path, eje):
    """Filas con los números convertidos; `eje` es la columna del tiempo (k en nuevos, dia en stock)."""
    with open(path, encoding="utf-8") as f:
        filas = list(csv.DictReader(f))
    for r in filas:
        r["t"], r["saldo"] = int(r[eje]), float(r["saldo"])
        r["mes"] = r.get("periodo") or r["periodo_meta"]
    return filas


def curvas(filas, llave, medida, t_max, filtro=lambda r: True):
    """{grupo: (base, [acumulado / base para t = 0..t_max])}."""
    base = collections.defaultdict(float)
    num = collections.defaultdict(lambda: [0.0] * (t_max + 2))
    for r in filas:
        if not filtro(r):
            continue
        g = llave(r)
        if r["tipo"] == "base":
            base[g] += r["saldo"]
        elif r["tipo"] == medida and 0 <= r["t"] <= t_max:
            num[g][r["t"]] += r["saldo"]
    out = {}
    for g, b in base.items():
        acum, s = [], 0.0
        for t in range(t_max + 1):
            s += num[g][t]
            acum.append(s / b if b else 0.0)
        out[g] = (b, acum)
    return out


def tabla(titulo, cur, orden, hitos, nombre=corto):
    tot = sum(b for b, _ in cur.values())
    print(f"\n{titulo}")
    print(f"  {'grupo':<22} {'% saldo':>8} | " + " ".join(f"{'t=' + str(h):>7}" for h in hitos))
    for g in orden:
        if g in cur:
            b, a = cur[g]
            print(f"  {nombre(g):<22} {100 * b / tot:>7.1f}% | " + " ".join(f"{100 * a[h]:>6.1f}%" for h in hitos))


def cruce(titulo, filas, fila_dim, filas_orden, medida, t_fin, filtro):
    """Tasa al cierre por (segmentador existente x riesgo) y la brecha Alto - Bajo dentro de cada fila."""
    cur = curvas(filas, lambda r: (fila_dim(r), r["riesgo_cob"]), medida, t_fin, filtro)
    fila_sola = curvas(filas, fila_dim, medida, t_fin, filtro)
    print(f"\n{titulo}")
    print(f"  {'':<18} {'todos':>7} | " + " ".join(f"{corto(r):>11}" for r in RIESGOS) + " | Alto - Bajo")
    salida = {}
    for f in filas_orden:
        if f not in fila_sola:
            continue
        celdas = {r: cur.get((f, r), (0, [0.0] * (t_fin + 1))) for r in RIESGOS}
        tasa = {r: c[1][t_fin] for r, c in celdas.items()}
        tot = sum(c[0] for c in celdas.values())
        txt = " ".join(f"{100 * tasa[r]:>5.1f}% ({100 * celdas[r][0] / tot:>2.0f})" if celdas[r][0] else f"{'—':>11}"
                       for r in RIESGOS)
        brecha = 100 * (tasa[RIESGOS[2]] - tasa[RIESGOS[0]])
        print(f"  {f:<18} {100 * fila_sola[f][1][t_fin]:>6.1f}% | {txt} | {brecha:+6.1f}pp")
        salida[f] = {"todos": fila_sola[f][1][t_fin], "peso": {r: celdas[r][0] / tot for r in RIESGOS},
                     "tasa": tasa, "brecha_pp": brecha}
    print("  (entre paréntesis, % del saldo de la fila en ese nivel de riesgo)")
    return salida


def por_mes(filas, medida, t_fin, filtro):
    cur = curvas(filas, lambda r: (r["mes"], r["riesgo_cob"]), medida, t_fin, filtro)
    meses = sorted({m for m, _ in cur})
    out = {}
    for m in meses:
        tot = sum(cur[(m, r)][0] for r in RIESGOS if (m, r) in cur)
        out[m] = {r: {"peso": cur[(m, r)][0] / tot, "tasa": cur[(m, r)][1][t_fin]} for r in RIESGOS if (m, r) in cur}
    return out


def shift_share(filas, dims, medida, t_fin, filtro):
    """Efecto de la mezcla por riesgo de cada mes: tasas de la ventana por (dims) contra (dims x riesgo)."""
    en_v = lambda r: filtro(r) and VENTANA[0] <= r["mes"] <= VENTANA[1]
    sin = curvas(filas, lambda r: tuple(r[d] for d in dims), medida, t_fin, en_v)
    con = curvas(filas, lambda r: tuple(r[d] for d in dims) + (r["riesgo_cob"],), medida, t_fin, en_v)
    base_mes = collections.defaultdict(float)
    for r in filas:
        if r["tipo"] == "base" and filtro(r):
            base_mes[(r["mes"],) + tuple(r[d] for d in dims) + (r["riesgo_cob"],)] += r["saldo"]
    out = {}
    for m in sorted({k[0] for k in base_mes}):
        e_sin = e_con = tot = 0.0
        for k, b in base_mes.items():
            if k[0] != m or k[1:] not in con or k[1:-1] not in sin:
                continue
            e_sin += b * sin[k[1:-1]][1][t_fin]
            e_con += b * con[k[1:]][1][t_fin]
            tot += b
        if tot:
            out[m] = e_con / e_sin - 1
    return out


def main():
    nue = leer("datos_tarea26/riesgo_matriz_nuevos.csv", "k")
    sto = leer("datos_tarea26/riesgo_matriz_stock.csv", "dia")
    ven = lambda r: VENTANA[0] <= r["mes"] <= VENTANA[1]
    sto_s2 = lambda r: r["d1"] == "0"
    sto_v = lambda r: sto_s2(r) and ven(r)
    res = {"ventana": VENTANA, "nuevos": {}, "stock": {}}

    print("=" * 100)
    print(f"TAREA 26 -- RIESGO DE COBRANZA EN LAS CURVAS (evaluación). Ventana {VENTANA[0]}-{VENTANA[1]}")
    print("=" * 100)

    for nom, filas, filtro in (("NUEVOS", nue, lambda r: True), ("STOCK (sin cohorte d1)", sto, sto_s2)):
        pm = por_mes(filas, "reb", K_FIN if nom == "NUEVOS" else D_FIN, filtro)
        print(f"\n{nom} -- mezcla del saldo por nivel de riesgo, por mes (sin puntaje = cobertura faltante)")
        print(f"  {'mes':<7} " + " ".join(f"{corto(r):>12}" for r in RIESGOS))
        for m, v in pm.items():
            print(f"  {m:<7} " + " ".join(f"{100 * v[r]['peso']:>11.1f}%" if r in v else f"{'—':>12}" for r in RIESGOS))
        res["nuevos" if nom == "NUEVOS" else "stock"]["mezcla"] = {m: {r: v[r]["peso"] for r in v} for m, v in pm.items()}

    for medida, etiqueta in (("reb", "REBAJE (recupero oficial)"), ("act", "ACTIVACIÓN (capital asegurado)")):
        cn = curvas(nue, lambda r: r["riesgo_cob"], medida, K_FIN, ven)
        tabla(f"NUEVOS -- {etiqueta}, acumulado por días desde la entrada", cn, RIESGOS, K_HITOS)
        tabla(f"NUEVOS -- {etiqueta}, por segmento del modelo",
              curvas(nue, lambda r: r["seg_cob"], medida, K_FIN, ven), SEGS, K_HITOS)
        todos = curvas(nue, lambda r: "todos", medida, K_FIN, ven)["todos"][1]
        cs = curvas(sto, lambda r: r["riesgo_cob"], medida, D_FIN, sto_v)
        tabla(f"STOCK -- {etiqueta}, acumulado por día del mes", cs, RIESGOS, D_HITOS)
        todos_s = curvas(sto, lambda r: "todos", medida, D_FIN, sto_v)["todos"][1]
        res["nuevos"][medida] = {"todos": todos, **{r: cn[r][1] for r in RIESGOS if r in cn}}
        res["stock"][medida] = {"todos": todos_s, **{r: cs[r][1] for r in RIESGOS if r in cs}}
        res["nuevos"][medida + "_peso"] = {r: cn[r][0] for r in cn}
        res["stock"][medida + "_peso"] = {r: cs[r][0] for r in cs}

        res["nuevos"][medida + "_banda"] = cruce(
            f"NUEVOS -- {etiqueta} a {K_FIN} días, por banda de avance x riesgo",
            nue, lambda r: r["avance_band"], BANDAS, medida, K_FIN, ven)
        res["stock"][medida + "_tramo"] = cruce(
            f"STOCK -- {etiqueta} al cierre, por tramo x riesgo",
            sto, lambda r: r["tramo"], TRAMOS, medida, D_FIN, sto_v)
        res["stock"][medida + "_banda"] = cruce(
            f"STOCK -- {etiqueta} al cierre, por banda de avance x riesgo",
            sto, lambda r: r["avance_band"], BANDAS, medida, D_FIN, sto_v)

        for nom, filas, filtro, t_fin in (("nuevos", nue, lambda r: True, K_FIN), ("stock", sto, sto_s2, D_FIN)):
            pm = por_mes(filas, medida, t_fin, filtro)
            print(f"\n{nom.upper()} -- {etiqueta} al cierre por mes y riesgo (estabilidad del orden)")
            print(f"  {'mes':<7} " + " ".join(f"{corto(r):>12}" for r in RIESGOS[:3]) + "   Alto - Bajo")
            est = {}
            for m, v in pm.items():
                if all(r in v for r in RIESGOS[:3]):
                    br = 100 * (v[RIESGOS[2]]["tasa"] - v[RIESGOS[0]]["tasa"])
                    est[m] = {"tasa": {r: v[r]["tasa"] for r in RIESGOS[:3]}, "brecha_pp": br}
                    print(f"  {m:<7} " + " ".join(f"{100 * v[r]['tasa']:>11.1f}%" for r in RIESGOS[:3]) + f"   {br:+6.1f}pp")
            res[nom][medida + "_por_mes"] = est

        ss_n = shift_share(nue, ("avance_band",), medida, K_FIN, lambda r: True)
        ss_s = shift_share(sto, ("tramo", "avance_band"), medida, D_FIN, sto_s2)
        print(f"\n{etiqueta} -- efecto de la mezcla por riesgo en la expectativa de cada mes "
              f"(tasas de la ventana; + = el riesgo del mes esperaba más)")
        print(f"  {'mes':<7} {'nuevos (banda)':>15} {'stock (tramo x banda)':>22}")
        for m in sorted(set(ss_n) | set(ss_s)):
            n, s = ss_n.get(m), ss_s.get(m)
            print(f"  {m:<7} {('%+.1f%%' % (100 * n)) if n is not None else '—':>15} "
                  f"{('%+.1f%%' % (100 * s)) if s is not None else '—':>22}")
        res["nuevos"][medida + "_mezcla_efecto"], res["stock"][medida + "_mezcla_efecto"] = ss_n, ss_s

    red = lambda x: round(x, 5) if isinstance(x, float) else (
        {k: red(v) for k, v in x.items()} if isinstance(x, dict) else [red(v) for v in x] if isinstance(x, (list, tuple)) else x)
    res = red(res)
    with open("datos_tarea26/evaluacion_riesgo.json", "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False)
    print("\nSalida para graficar en datos_tarea26/evaluacion_riesgo.json")
    # Artifact «Riesgo de cobranza en las curvas»: se le inyectan los datos entre marcadores.
    try:
        with open(HTML, encoding="utf-8") as f:
            s = f.read()
    except FileNotFoundError:
        return
    i, j = s.index("/*DATOS*/"), s.index("/*/DATOS*/")
    s = s[:i + len("/*DATOS*/")] + json.dumps(res, ensure_ascii=False, separators=(",", ":")) + s[j:]
    with open(HTML, "w", encoding="utf-8") as f:
        f.write(s)
    print(f"Datos inyectados en {HTML}")


if __name__ == "__main__":
    main()

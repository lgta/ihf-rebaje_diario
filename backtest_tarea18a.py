"""
TAREA 18a -- prueba contra el backtest de los DOS refinamientos que Fase 4
dejo deliberadamente fuera (una variable a la vez):

  A. segmentar la curva de "nuevos" por DIA DE LA SEMANA DEL VENCIMIENTO
     (habil vs. fin de semana), y
  B. colapsar `avance_band` de 4 buckets a 3 (`<10%` / `10-40%` / `40%+`).

Corre 4 variantes sobre los mismos 4 meses cerrados y el MISMO real
(el universo no cambia, solo la segmentacion de las curvas -- la
comparacion es manzana con manzana):

  V0  4 bandas, sin dow      <- baseline de produccion (motor unificado)
  V1  4 bandas x tipo_venc   <- refinamiento A solo (binario finde/semana)
  V2  3 bandas, sin dow      <- refinamiento B solo
  V3  3 bandas x tipo_venc   <- ambos
  V4  4 bandas x dow abierto <- A pero con los 7 dias, no el corte binario
  V5  3 bandas x dow abierto <- V4 + B

POR QUE HAY UNA VERSION "ABIERTA" DEL DIA DE SEMANA: el corte binario
finde/semana esta mal puesto para este mecanismo. El dia de ENTRADA es
siempre vencimiento + 1, y los datos dicen que NINGUNA cuota vence
domingo (0.00% del calendario y 0.00% de la calibracion) -- OKA no
programa vencimientos ese dia. Entonces 'finde' = {sabado, domingo} es en
la practica solo "vencimiento sabado", y deja "vencimiento viernes"
(que entra SABADO, dia no habil, con dia 0 de 27.4% contra 37-42% de los
dias habiles) del lado de 'semana'. El corte binario parte mal justo la
poblacion que pretende aislar.

DE DONDE SALE CADA VARIANTE:

  - El colapso a 3 buckets se hace EN PYTHON y es EXACTO, no una
    aproximacion: las curvas traen su propio denominador
    (`saldo_entrada_total` / `saldo_total`), asi que
    pct_colapsado(d) = SUM_b pct_b(d)*saldo_b / SUM_b saldo_b
    reconstruye exactamente la curva que habria salido de agrupar por
    3 buckets en SQL. Por eso no hace falta re-correr Athena para B.
    (Se valida con un assert al correr.)

  - El dow SI necesita recalibracion: `tarea18a_curva_nuevos_dow.sql`
    (identica a la Q-B de produccion salvo la dimension `tipo_venc`).
    El calendario NO se re-corre: `dia_entrada = day(fechavencimiento+1)`,
    asi que el dia de la semana del vencimiento es derivable en Python
    desde (periodo, dia_entrada).

  - El STOCK no lleva dow (su curva se indexa por dia del mes, no por
    entrada); si lleva el colapso de bandas en V2/V3, para que la
    segmentacion sea la misma en todo el motor, como en produccion.

CRITERIO DE ADOPCION (CLAUDE.md, no negociable): no se adopta por mejora
de error. Se adopta si el universo o la medicion quedan mas fieles.
"""
import csv
import collections
import datetime as dt
import statistics

from motor_unificado import proyectar, acumular_real, lookup

DIR_F4 = "datos_tarea17_fase4"
DIR_18A = "datos_tarea18a"

MESES = [("202604", 30, "Abril 2026"), ("202605", 31, "Mayo 2026"),
         ("202606", 30, "Junio 2026"), ("202607", 31, "Julio 2026")]

BANDA_3 = {"a. avance <10%": "a. avance <10%",
           "b. avance 10-40%": "b. avance 10-40%",
           "c. avance 40-70%": "c. avance 40%+",
           "d. avance 70%+": "c. avance 40%+"}


def tipo_venc(periodo, dia_entrada):
    """'finde' si la CUOTA vencio sabado o domingo. vencimiento = entrada - 1."""
    return "finde" if dow_venc(periodo, dia_entrada) in (6, 7) else "semana"


def dow_venc(periodo, dia_entrada):
    """Dia de la semana del vencimiento, 1=lunes .. 7=domingo (como Presto)."""
    f_ent = dt.date(int(periodo[:4]), int(periodo[4:]), dia_entrada)
    return (f_ent - dt.timedelta(days=1)).weekday() + 1


def leer(path):
    with open(path) as f:
        return list(csv.DictReader(f))


# curva de nuevos, 4 bandas, sin dow
cn4, cn4_den = collections.defaultdict(dict), {}
for r in leer(DIR_F4 + "/curva_nuevos.csv"):
    cn4[r["avance_band"]][int(r["dia"])] = float(r["pct_capital_asegurado_acum"])
    cn4_den[r["avance_band"]] = float(r["saldo_entrada_total"])

# curva de nuevos con dow: (banda, tipo_venc) -> {dia: pct}
cn4d, cn4d_den = collections.defaultdict(dict), {}
for r in leer(DIR_18A + "/curva_nuevos_dow.csv"):
    k = (r["avance_band"], r["tipo_venc"])
    cn4d[k][int(r["dia"])] = float(r["pct_capital_asegurado_acum"])
    cn4d_den[k] = float(r["saldo_entrada_total"])

# curva de nuevos con el dow abierto: (banda, dow_venc int) -> {dia: pct}
cn4a, cn4a_den = collections.defaultdict(dict), {}
for r in leer(DIR_18A + "/curva_nuevos_dow7.csv"):
    k = (r["avance_band"], int(r["tipo_venc"]))
    cn4a[k][int(r["dia"])] = float(r["pct_capital_asegurado_acum"])
    cn4a_den[k] = float(r["saldo_entrada_total"])

# curva de stock: (tramo, banda) -> {dia: pct}
cs4, cs4_den = collections.defaultdict(dict), {}
for r in leer(DIR_F4 + "/curva_stock.csv"):
    k = (r["tramo"], r["avance_band"])
    cs4[k][int(r["dia"])] = float(r["pct_capital_asegurado_acum"])
    cs4_den[k] = float(r["saldo_total"])

stock_pob = collections.defaultdict(dict)
for r in leer(DIR_F4 + "/stock_pob.csv"):
    stock_pob[r["periodo_meta"]][(r["tramo"], r["avance_band"])] = float(r["saldo_total"])

calendario = collections.defaultdict(lambda: collections.defaultdict(dict))
for r in leer(DIR_F4 + "/calendario.csv"):
    calendario[r["periodo"]][int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo_en_riesgo"])

real_stock, real_nuevos = collections.defaultdict(dict), collections.defaultdict(dict)
for r in leer(DIR_F4 + "/real_stock.csv"):
    real_stock[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])
for r in leer(DIR_F4 + "/real_nuevos.csv"):
    real_nuevos[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])


def colapsar(curvas, dens, mapa_clave, desde_dia0):
    """Recombina curvas acumuladas ponderando por su propio denominador.

    Exacto porque pct_b(d) = activado_b(d)/saldo_b: el numerador vuelve
    multiplicando por saldo_b, y se re-divide por la suma. `lookup`
    evalua la escalera antes de combinar, para que un dia faltante en una
    banda no se cuente como 0.
    """
    grupos = collections.defaultdict(list)
    for k in curvas:
        grupos[mapa_clave(k)].append(k)
    salida, den_out = {}, {}
    for g, miembros in grupos.items():
        dias = sorted({d for k in miembros for d in curvas[k]})
        den = sum(dens[k] for k in miembros)
        salida[g] = {d: sum(lookup(curvas[k], d, desde_dia0) * dens[k]
                            for k in miembros) / den for d in dias}
        den_out[g] = den
    return salida, den_out


cn3, cn3_den = colapsar(cn4, cn4_den, lambda k: BANDA_3[k], True)
cn3d, cn3d_den = colapsar(cn4d, cn4d_den, lambda k: (BANDA_3[k[0]], k[1]), True)
cn3a, cn3a_den = colapsar(cn4a, cn4a_den, lambda k: (BANDA_3[k[0]], k[1]), True)
cs3, cs3_den = colapsar(cs4, cs4_den, lambda k: (k[0], BANDA_3[k[1]]), False)

SIN_DOW, DOW_BIN, DOW_ABIERTO, DOW_ENTRADA3 = 0, 1, 2, 3

# Agrupacion por TIPO DE DIA DE ENTRADA (entrada = vencimiento + 1). El
# mecanismo medido es que el dia 0 se activa mucho menos si el dia de
# entrada no es habil: entrada en dia habil 37-42%, entrada sabado 27.4%,
# entrada domingo 18.7%. Con 3 celdas en vez de 6 los denominadores son
# mas gruesos; se prueba contra la version abierta para ver cuanto de la
# ganancia diaria viene del rezago semanal (lags 1+) y cuanto del dia 0.
TIPO_ENTRADA = {1: "entrada habil", 2: "entrada habil", 3: "entrada habil",
                4: "entrada habil", 5: "entrada sabado", 6: "entrada domingo"}
cn4e, cn4e_den = colapsar(cn4a, cn4a_den, lambda k: (k[0], TIPO_ENTRADA[k[1]]), True)


def insumos(periodo, tres_bandas, modo_dow):
    st = collections.defaultdict(float)
    for (tramo, banda), s in stock_pob[periodo].items():
        st[(tramo, BANDA_3[banda] if tres_bandas else banda)] += s
    cal = collections.defaultdict(lambda: collections.defaultdict(float))
    for de, porbanda in calendario[periodo].items():
        dw = dow_venc(periodo, de)
        seg = {SIN_DOW: None, DOW_BIN: tipo_venc(periodo, de),
               DOW_ABIERTO: dw, DOW_ENTRADA3: TIPO_ENTRADA[dw]}[modo_dow]
        for banda, s in porbanda.items():
            b = BANDA_3[banda] if tres_bandas else banda
            cal[de][b if seg is None else (b, seg)] += s
    return dict(st), {k: dict(v) for k, v in cal.items()}


VARIANTES = [
    ("V0  4 bandas, sin dow", False, SIN_DOW,     cn4,  cs4),
    ("V1  4 bandas x dow bin", False, DOW_BIN,    cn4d, cs4),
    ("V2  3 bandas, sin dow", True,  SIN_DOW,     cn3,  cs3),
    ("V3  3 bandas x dow bin", True,  DOW_BIN,    cn3d, cs3),
    ("V4  4 bandas x dow abie", False, DOW_ABIERTO, cn4a, cs4),
    ("V5  3 bandas x dow abie", True,  DOW_ABIERTO, cn3a, cs3),
    ("V6  4 bandas x entrada3", False, DOW_ENTRADA3, cn4e, cs4),
]

BASELINE_PUB = {"202604": -12.6, "202605": -8.7, "202606": -2.6, "202607": -5.0}


def correr(tres, dow, curva_n, curva_s):
    filas = []
    faltantes = set()
    for periodo, n, _ in MESES:
        st, cal = insumos(periodo, tres, dow)
        faltantes |= {k for d in cal.values() for k in d if k not in curva_n}
        proy = proyectar(st, cal, curva_s, curva_n, n)
        rs, rn = acumular_real(real_stock[periodo], n), acumular_real(real_nuevos[periodo], n)
        f = proy[-1]
        rt = rs[-1] + rn[-1]
        filas.append({
            "periodo": periodo, "proy": f["proy_total"], "real": rt,
            "proy_nuevos": f["proy_nuevos"], "real_nuevos": rn[-1],
            "err": 100 * (f["proy_total"] - rt) / rt,
            "err_stock": 100 * (f["proy_stock"] - rs[-1]) / rs[-1],
            "err_nuevos": 100 * (f["proy_nuevos"] - rn[-1]) / rn[-1],
            "serie": proy,
        })
    assert not faltantes, f"el calendario pide celdas que la curva no tiene: {faltantes}"
    return filas


if __name__ == "__main__":
    print("=" * 100)
    print("TAREA 18a -- dia de semana del vencimiento y avance_band a 3 buckets")
    print("=" * 100)

    for d in (0, 1, 5, 15, 30):
        a = sum(lookup(cn4[b], d, True) * cn4_den[b]
                for b in ("c. avance 40-70%", "d. avance 70%+"))
        b = lookup(cn3["c. avance 40%+"], d, True) * cn3_den["c. avance 40%+"]
        assert abs(a - b) < 1e-6, (d, a, b)
    print("[ok] colapso a 3 buckets validado como exacto (dias 0,1,5,15,30)\n")

    res = {}
    for nombre, tres, dow, cn, cs in VARIANTES:
        res[nombre] = correr(tres, dow, cn, cs)

    hdr = f"{'Variante':<23} | " + " ".join(f"{m[2][:5]:>8}" for m in MESES) + " |    media"
    for etiqueta, campo in (("ERROR TOTAL", "err"), ("ERROR del componente NUEVOS", "err_nuevos")):
        print(etiqueta)
        print(hdr)
        print("-" * len(hdr))
        for nombre, *_ in VARIANTES:
            errs = [f[campo] for f in res[nombre]]
            print(f"{nombre:<23} | " + " ".join(f"{e:>+7.1f}%" for e in errs)
                  + f" | {sum(abs(e) for e in errs)/len(errs):>7.2f}%")
        print()

    # El error de fin de mes NO es la unica medida de fidelidad, y para
    # este refinamiento es la menos sensible: las curvas por dia de semana
    # convergen hacia el dia 5-7, asi que al cierre del mes casi todo se
    # cancela. Lo que el segmentador cambia es la TRAYECTORIA diaria --
    # que es justo lo que el proyecto usa (meta diaria). Se mide con la
    # correlacion entre incrementos diarios proyectados y reales.
    print("FIDELIDAD INTRA-MES -- correlacion de incrementos diarios (nuevos)")
    print(hdr)
    print("-" * len(hdr))
    for nombre, *_ in VARIANTES:
        corrs = []
        for f, (periodo, n, _) in zip(res[nombre], MESES):
            rn = acumular_real(real_nuevos[periodo], n)
            pn = [x["proy_nuevos"] for x in f["serie"]]
            inc = lambda s: [s[0]] + [s[i] - s[i - 1] for i in range(1, n)]
            corrs.append(statistics.correlation(inc(pn), inc(rn)))
        print(f"{nombre:<23} | " + " ".join(f"{c:>+7.3f} " for c in corrs)
              + f" | {sum(corrs)/len(corrs):>7.3f}")
    print()

    print("Chequeo de reproducibilidad: V0 tiene que dar el baseline publicado")
    for f in res[VARIANTES[0][0]]:
        pub = BASELINE_PUB[f["periodo"]]
        ok = "ok" if abs(f["err"] - pub) < 0.06 else "DIFIERE"
        print(f"  {f['periodo']}  V0 {f['err']:+6.2f}%   publicado {pub:+5.1f}%   {ok}")

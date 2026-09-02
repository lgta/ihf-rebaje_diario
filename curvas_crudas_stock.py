"""
TAREA 18g -- construccion de curvas de "stock" desde la MATRIZ CRUDA
(`tarea18g_curva_cruda_stock.sql` -> `datos_tarea18g/curva_cruda_stock.csv`).

Mismo patron de diseno que `curvas_crudas.py` (nuevos), aplicado a stock:
grano minimo (periodo_meta, tramo, avance_band, dia) -> saldo, para poder
sin volver a Athena:

  - reconstruir la curva de produccion (agrupando todo el periodo_meta)
  - RODAR la ventana de calibracion [M-12, M-1] por mes de test (18c)
  - reagrupar por DIAS-PARA-FIN-DE-MES real en vez de numero de dia fijo
    (18g: extension del hallazgo de 18b -- el pico de pago de stock, igual
    que el de nuevos, deberia vivir en el CIERRE REAL del mes, no en los
    dias calendario 30/31 -- ver `analisis_sesgo_nuevos_18b.md` seccion 2)

A diferencia de nuevos, stock no tiene "dia de entrada" dentro del mes --
arranca el dia 1 con mora 1-30 ya acumulada, asi que `dia` YA es
directamente el dia del mes de la observacion (no un desde-entrada `k`).
La fecha real de cada celda es simplemente `date(periodo_meta, dia)`.
"""
import csv
import collections
import calendar as calmod
import datetime as dt

RAW = "datos_tarea18g/curva_cruda_stock.csv"

GRUPOS_DM_FIJO = {15: "quincena", 16: "quincena", 30: "fin de mes", 31: "fin de mes"}


def cargar_matriz(path=RAW):
    """(base, activaciones) al grano (periodo_meta, tramo, avance_band).

    base : {(periodo_meta, tramo, avance_band): saldo_total}
    acts : {(periodo_meta, tramo, avance_band): {dia: saldo activado ese dia}}
    """
    base, acts = {}, collections.defaultdict(dict)
    for r in csv.DictReader(open(path)):
        clave = (r["periodo_meta"], r["tramo"], r["avance_band"])
        s = float(r["saldo"])
        if r["tipo"] == "base":
            base[clave] = base.get(clave, 0.0) + s
        else:
            acts[clave][int(r["dia"])] = acts[clave].get(int(r["dia"]), 0.0) + s
    return base, dict(acts)


def _dias_en_mes(periodo, dia):
    y, m = int(periodo[:4]), int(periodo[4:])
    return calmod.monthrange(y, m)[1]


def _grupo_dia(periodo, dia, modo):
    """modo='fijo': reproduce produccion (dia calendario 30/31 = fin de mes).
    modo='real': el hallazgo de 18b -- solo el ULTIMO DIA REAL del mes
    (dias-para-fin=0) queda elevado; el penultimo no se distingue del
    resto (medido en analisis_sesgo_nuevos_18b.md, r=4.536% en dpf=0 vs.
    2.786% baseline, dpf=1 practicamente en baseline)."""
    if modo == "fijo":
        return GRUPOS_DM_FIJO.get(dia, "resto")
    dias_mes = _dias_en_mes(periodo, dia)
    if dia in (15, 16):
        return "quincena"
    if dia == dias_mes:
        return "cierre"
    return "resto"


def calibrar(base, acts, desde, hasta, con_f=False, modo_cierre="fijo", iteraciones=6):
    """Devuelve (curva_acumulada, f_por_grupo_dia).

    curva: (tramo, avance_band) -> {dia: % acumulado}, IDENTICA en forma a
    `cargar_curva_stock()` de motor_unificado.py cuando con_f=False (la
    curva base no cambia -- el fit del dia-a-dia es el mismo que produccion,
    solo se agrega el factor multiplicativo por encima, igual que 18f hizo
    para nuevos).
    f: {grupo: factor}, todo 1.0 si con_f=False.
    """
    cohortes = [(p, t, b, s) for (p, t, b), s in base.items() if desde <= p <= hasta]
    celdas = []  # (clave, dia, grupo, obs, expo)
    for p, t, b, s in cohortes:
        a = acts.get((p, t, b), {})
        dias_mes_p = calmod.monthrange(int(p[:4]), int(p[4:]))[1]
        for dia in range(1, dias_mes_p + 1):
            grp = _grupo_dia(p, dia, modo_cierre)
            celdas.append(((t, b), dia, grp, a.get(dia, 0.0), s))

    f_dm = collections.defaultdict(lambda: 1.0)
    p_hazard = {}
    for _ in range(iteraciones if con_f else 1):
        num_p, den_p = collections.defaultdict(float), collections.defaultdict(float)
        for kl, dia, grp, obs, expo in celdas:
            num_p[(kl, dia)] += obs
            den_p[(kl, dia)] += expo * f_dm[grp]
        p_hazard = {kk: num_p[kk] / den_p[kk] for kk in num_p if den_p[kk] > 0}
        if not con_f:
            break
        num_f, den_f = collections.defaultdict(float), collections.defaultdict(float)
        for kl, dia, grp, obs, expo in celdas:
            num_f[grp] += obs
            den_f[grp] += expo * p_hazard.get((kl, dia), 0.0)
        bruto = {g: num_f[g] / den_f[g] for g in num_f if den_f[g] > 0}
        media = (sum(bruto[g] * den_f[g] for g in bruto) / sum(den_f[g] for g in bruto))
        f_dm = collections.defaultdict(lambda: 1.0, {g: v / media for g, v in bruto.items()})

    curva = collections.defaultdict(dict)
    for (kl, dia), v in p_hazard.items():
        curva[kl][dia] = 100.0 * v
    for kl in curva:
        ac = 0.0
        for dia in sorted(curva[kl]):
            ac += curva[kl][dia]
            curva[kl][dia] = ac
    return dict(curva), dict(f_dm)


if __name__ == "__main__":
    base, acts = cargar_matriz()

    print("VALIDACION contra la curva de produccion (ventana 202504-202606, sin factor)\n")
    curva, _ = calibrar(base, acts, "202504", "202606", con_f=False)
    prod = collections.defaultdict(dict)
    for r in csv.DictReader(open("datos_tarea17_fase4/curva_stock.csv")):
        prod[(r["tramo"], r["avance_band"])][int(r["dia"])] = float(r["pct_capital_asegurado_acum"])
    print(f"{'segmento':<30} {'d15 crudo':>10} {'d15 prod':>10} {'d30 crudo':>10} {'d30 prod':>10}")
    for k in sorted(prod):
        c15 = curva.get(k, {}).get(15, 0.0)
        c30 = curva.get(k, {}).get(30, 0.0)
        print(f"{str(k):<30} {c15:>9.3f}% {prod[k].get(15,0):>9.3f}% "
              f"{c30:>9.3f}% {prod[k].get(30,0):>9.3f}%")

    print("\nFACTOR POR GRUPO DE DIA, modo FIJO (dia 30/31) vs. modo REAL (cierre = ultimo dia real)")
    _, f_fijo = calibrar(base, acts, "202504", "202606", con_f=True, modo_cierre="fijo")
    _, f_real = calibrar(base, acts, "202504", "202606", con_f=True, modo_cierre="real")
    print("  fijo:", {k: round(v, 4) for k, v in f_fijo.items()})
    print("  real:", {k: round(v, 4) for k, v in f_real.items()})

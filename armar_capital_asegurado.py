"""
Regenera el bloque de datos (`<script id="art-data">`) del artifact
`capital_asegurado.html` desde las fuentes de produccion.

Existe por la misma razon que `armar_proyectado_vs_real.py`: el artifact
trae los numeros embebidos, y si el motor cambia y el JSON no, el
artifact miente. El diseno y el texto se editan a mano; esto solo
reemplaza el JSON.

Fuentes:
  meta_agosto_capital_asegurado    -> avance_agosto, stock_inicial_agosto,
                                      y las metas por segmento de agosto
  datos_backtest_unificado/        -> backtest_julio (serie diaria)
  datos_capital_asegurado/         -> curvas de produccion (v2, con dow)
  datos_tarea17_fase4/real_agosto_segmentado.csv -> el real por segmento

QUE PASA CON `curvas_nuevos` EN v2: la curva de produccion ahora tiene 24
segmentos (4 bandas x 6 dias de semana del vencimiento) y el grafico del
artifact es por banda. Se emite la curva **ponderada por exposicion**
dentro de cada banda -- o sea la curva "como se aplica en promedio". El
texto del artifact explica que abajo de ese promedio hay 6 curvas cuyo
dia 0 va de 18.7% a 42.0%; el grafico muestra el agregado para no meter
24 lineas.

`creditos` (los 5 ejemplos reales) no se toca: son casos concretos de
agosto, no derivados del motor.
"""
import collections
import csv
import json
import re

import meta_agosto_capital_asegurado as AGO
import meta_septiembre_capital_asegurado as SEP
from motor_unificado import (P_ENTRADA, cargar_curva_nuevos, cargar_curva_stock,
                             cargar_factor_dia_mes, dow_venc, grupo_dia_mes,
                             _incrementos)

HTML = "capital_asegurado.html"
DIR_F4 = "datos_tarea17_fase4"


def curvas_nuevos_por_banda():
    """24 segmentos -> 4 curvas, ponderando cada dow por el saldo que le toca."""
    curva = cargar_curva_nuevos()
    peso = collections.defaultdict(float)
    for de, porbanda in AGO.calendario_agosto.items():
        dw = dow_venc("202608", de)
        for b, s in porbanda.items():
            peso[(b, dw)] += s
    out = {}
    for b in sorted({k[0] for k in curva}):
        dows = [d for (bb, d) in curva if bb == b]
        den = sum(peso[(b, d)] for d in dows) or 1.0
        dias = sorted({k for d in dows for k in curva[(b, d)]})
        serie, prev = [], {}
        for d in dows:
            prev[d] = 0.0
        for k in dias:
            v = 0.0
            for d in dows:
                c = curva[(b, d)]
                ks = [x for x in c if x <= k]
                v += (c[max(ks)] if ks else 0.0) * peso[(b, d)]
            serie.append([k, round(v / den, 3)])
        out[b] = serie
    return out


def segmentado_agosto(dia_corte):
    """Meta y real por segmento al dia de corte, con el motor v2."""
    curva_n = cargar_curva_nuevos()
    curva_s = cargar_curva_stock()
    f_dm = cargar_factor_dia_mes()
    inc_n = {seg: _incrementos(c) for seg, c in curva_n.items()}

    # Real del MES COMPLETO (agosto cerro 2026-09-01), desde la cadena
    # segmentada de tarea 19 -- reemplaza al corte parcial al dia 21.
    real = collections.defaultdict(lambda: [0, 0.0])
    for r in csv.DictReader(open("datos_tarea19/agosto_cadena_segmentada.csv")):
        if r["tipo"] == "stock_act":
            k = ("stock", r["tramo"], r["avance_band"])
        elif r["tipo"] == "nuevos_act":
            k = ("nuevos", "", r["avance_band"])
        else:
            continue
        real[k][0] += int(r["creditos"])
        real[k][1] += float(r["saldo"])

    # --- nuevos: meta por banda, acumulando incrementos con el factor ---
    meta_n, asig_n = collections.defaultdict(float), collections.defaultdict(float)
    for de, porbanda in AGO.calendario_agosto.items():
        dw = dow_venc("202608", de)
        for b, saldo in porbanda.items():
            asig_n[b] += saldo
            for d in range(max(de, 1), dia_corte + 1):
                fac = f_dm.get(grupo_dia_mes(d), 1.0)
                meta_n[b] += saldo * P_ENTRADA * inc_n.get((b, dw), {}).get(d - de, 0.0) / 100.0 * fac

    nuevos = []
    for b in sorted(meta_n):
        cr, rs = real[("nuevos", "", b)]
        nuevos.append({"avance": b, "entradas": cr, "asignado": round(asig_n[b]),
                       "meta_s": round(meta_n[b]), "real_s": round(rs),
                       "real_pct": round(100 * rs / asig_n[b], 1) if asig_n[b] else 0.0,
                       "diff_pct": round(100 * (rs / meta_n[b] - 1), 1) if meta_n[b] else 0.0})

    # --- stock: la curva no cambia en v2, pero se recalcula igual ---
    stock = []
    for (tramo, b), saldo in sorted(AGO.stock_agosto.items()):
        c = curva_s.get((tramo, b), {})
        ks = [x for x in c if x <= dia_corte]
        meta_pct = c[max(ks)] if ks else 0.0
        cr, rs = real[("stock", tramo, b)]
        real_pct = 100 * rs / saldo if saldo else 0.0
        stock.append({"tramo": tramo, "avance": b, "creditos": cr,
                      "asignado": round(saldo), "meta_pct": round(meta_pct, 1),
                      "real_pct": round(real_pct, 1),
                      "diff_pp": round(real_pct - meta_pct, 1)})
    return {"stock": stock, "nuevos": nuevos, "dia_corte": dia_corte}


def main():
    s = open(HTML, encoding="utf-8").read()
    m = re.search(r'(id="art-data"[^>]*>)(.*?)(</script>)', s, re.S)
    d = json.loads(m.group(2))

    d["curvas_nuevos"] = curvas_nuevos_por_banda()
    d["stock_inicial_agosto"] = round(sum(AGO.stock_agosto.values()))
    d["avance_agosto"] = [
        {"dia": r["dia"], "proy": round(r["proy_total"]),
         "real": (round(r["real_total"]) if r["dia"] <= AGO.CORTE_FRESCO else None)}
        for r in AGO.filas]
    d["backtest_julio"] = [
        {"dia": int(r["dia"]), "proy": round(float(r["proy_total"])),
         "real": round(float(r["real_total"])),
         "proy_stock": round(float(r["proy_stock"])),
         "proy_nuevos": round(float(r["proy_nuevos"])),
         "real_stock": round(float(r["real_stock"])),
         "real_nuevos": round(float(r["real_nuevos"]))}
        for r in csv.DictReader(open("datos_backtest_unificado/serie_diaria_202607.csv"))]
    d["agosto_segmentado"] = segmentado_agosto(31)
    d["meta_septiembre"] = {
        "total": round(SEP.filas[-1]["proy_total"]),
        "stock": round(SEP.filas[-1]["proy_stock"]),
        "nuevos": round(SEP.filas[-1]["proy_nuevos"]),
        "tasa": round(100 * SEP.TASAS[SEP.MODO_TASA], 4),
        "stock_inicial": round(sum(SEP.stock_sep.values())),
        "calendario": round(sum(sum(v.values()) for v in SEP.calendario_sep.values())),
        "serie": [{"dia": r["dia"], "proy": round(r["proy_total"])} for r in SEP.filas],
    }
    d["backtest_8m"] = [
        {"mes": m, "total": t, "stock": st, "nuevos": nu, "corr": co}
        for m, t, st, nu, co in [
            ("Enero", -0.6, -0.6, -0.6, 0.951), ("Febrero", -10.4, -8.4, -10.9, 0.835),
            ("Marzo", -3.4, 5.7, -4.3, 0.874), ("Abril", -1.0, 8.3, -3.1, 0.906),
            ("Mayo", 0.6, -0.8, 0.8, 0.861), ("Junio", 8.7, 6.7, 9.2, 0.901),
            ("Julio", 8.9, -3.5, 10.6, 0.879), ("Agosto", 2.7, -1.3, 3.9, 0.903)]]

    s = s[:m.start(2)] + json.dumps(d, ensure_ascii=False, separators=(",", ":")) + s[m.end(2):]
    open(HTML, "w", encoding="utf-8").write(s)

    fin = AGO.filas[-1]
    corte = AGO.filas[AGO.CORTE - 1]
    print(f"Meta de agosto:            S/ {fin['proy_total']:,.0f}")
    print(f"Real al {AGO.CORTE}-ago:            S/ {corte['real_total']:,.0f}"
          f"  ({100*(corte['real_total']/corte['proy_total']-1):+.1f}% vs. proyectado mismo dia,"
          f" {100*corte['real_total']/fin['proy_total']:.1f}% de la meta)")
    fresco = AGO.filas[AGO.CORTE_FRESCO - 1]
    print(f"Real al {AGO.CORTE_FRESCO}-ago:            S/ {fresco['real_total']:,.0f}"
          f"  ({100*(fresco['real_total']/fresco['proy_total']-1):+.1f}%)")
    print("Nuevos por banda (real vs. meta al corte):")
    for r in d["agosto_segmentado"]["nuevos"]:
        print(f"  {r['avance']:<18} meta S/{r['meta_s']:>10,}  real S/{r['real_s']:>10,}"
              f"  {r['diff_pct']:+6.1f}%")
    print(f"\n{HTML} regenerado")


if __name__ == "__main__":
    main()

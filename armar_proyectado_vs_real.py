"""
Regenera los bloques de datos del artifact `proyectado_vs_real.html` desde
las series diarias del backtest oficial (datos_backtest_unificado/).

Existe porque el artifact tiene los graficos como SVG inline calculado a
mano: si los numeros del backtest cambian y el SVG no, el grafico miente.
Reemplaza por anclas explicitas, no reescribe el archivo entero -- el
diseno y el texto se editan a mano.

Geometria (la del artifact original, replicada exacto):
  viewBox 0 0 1000 286, el area cierra en y=260
  y = 260 * (1 - valor / max_real)      <- ambas series usan el MISMO
  x = 1000 * i / (n-1)                     maximo, el del real
  dstrip i: left = 100*i/n, width = 100/n
"""
import csv
import re

HTML = "proyectado_vs_real.html"
DIR = "datos_backtest_unificado"
MES_NOM = {"202605": "may", "202607": "jul"}


def serie(periodo):
    with open(f"{DIR}/serie_diaria_{periodo}.csv") as f:
        return list(csv.DictReader(f))


def bloque_grafico(periodo):
    filas = serie(periodo)
    n = len(filas)
    proy = [float(r["proy_total"]) for r in filas]
    real = [float(r["real_total"]) for r in filas]
    vmax = max(real)
    y = lambda v: 260 * (1 - v / vmax)
    x = lambda i: 1000 * i / (n - 1)
    pts = lambda s: " L ".join(f"{x(i):.2f},{y(v):.2f}" for i, v in enumerate(s))
    area = f"M {pts(real)} L 1000,260 L 0,260 Z"
    tips = "".join(
        f'<div class="dstrip2" style="left:{100*i/n:.4f}%;width:{100/n:.4f}%" '
        f'data-tip="{MES_NOM[periodo]} {i+1:02d} &middot; proy S/{proy[i]:,.0f} '
        f'&middot; real S/{real[i]:,.0f}"></div>'
        for i in range(n))
    return (
        '      <div class="bt-chart-wrap">\n'
        '        <svg viewBox="0 0 1000 286" preserveAspectRatio="none" class="bt-svg">\n'
        f'          <path d="{area}" class="bt-real-area"/>\n'
        f'          <path d="M {pts(proy)}" class="bt-proy-line"/>\n'
        f'          <path d="M {pts(real)}" class="bt-real-line"/>\n'
        '        </svg>\n'
        f'        <div class="dstrips2">{tips}</div>\n'
        '      </div>'
    )


def tabla_componentes(periodo):
    f = serie(periodo)[-1]
    v = {k: float(f[k]) for k in
         ("proy_stock", "proy_nuevos", "proy_total", "real_stock", "real_nuevos", "real_total")}
    def fila(etq, p, r, clase_total=""):
        e = 100 * (p - r) / r
        cls = "neg" if e < 0 else "pos"
        tr = f'<tr class="{clase_total}">' if clase_total else "<tr>"
        return (f'          {tr}<td>{etq}</td><td>S/{p:,.0f}</td>'
                f'<td>S/{r:,.0f}</td><td class="{cls}">{e:+.1f}%</td></tr>')
    return "\n".join([
        fila("Stock", v["proy_stock"], v["real_stock"]),
        fila("Nuevos (incluye el día 0)", v["proy_nuevos"], v["real_nuevos"]),
        fila("Total", v["proy_total"], v["real_total"], "total"),
    ])


def resumen(periodo):
    f = serie(periodo)[-1]
    p, r = float(f["proy_total"]), float(f["real_total"])
    return p, r, 100 * (p - r) / r, len(serie(periodo))


def reemplazar(html, ini, fin, nuevo, etiqueta):
    """Reemplaza lo que hay entre `ini` y `fin` (exclusivo) por `nuevo`."""
    i = html.index(ini)
    j = html.index(fin, i)
    return html[:i] + nuevo + html[j:], etiqueta


def main():
    html = open(HTML, encoding="utf-8").read()

    for periodo in ("202607", "202605"):
        # el bloque de grafico de ese mes: desde su <div class="bt-chart-wrap">
        # hasta el </div></div><div class="bt-legend"> que lo cierra
        nom = "Julio 2026" if periodo == "202607" else "Mayo 2026"
        anc = html.index(f'<span class="m-name">{nom}</span>')
        ini = html.index('      <div class="bt-chart-wrap">', anc)
        fin = html.index('    </div>\n    <div class="bt-legend">', ini)
        html = html[:ini] + bloque_grafico(periodo) + "\n" + html[fin:]

        # tabla de componentes: el <tbody> que sigue al grafico
        anc = html.index(f'<span class="m-name">{nom}</span>')
        ini = html.index("        <tbody>\n", anc) + len("        <tbody>\n")
        fin = html.index("        </tbody>", ini)
        html = html[:ini] + tabla_componentes(periodo) + "\n" + html[fin:]

        # encabezado del mes
        p, r, e, n = resumen(periodo)
        anc = html.index(f'<span class="m-name">{nom}</span>')
        ini = html.index('<span class="m-error', anc)
        fin = html.index("</span>", ini) + len("</span>")
        cls = "neg" if e < 0 else "pos"
        html = html[:ini] + f'<span class="m-error {cls}">{e:+.1f}%</span>' + html[fin:]

        ini = html.index('<p class="month-sub">', anc)
        fin = html.index("</p>", ini) + len("</p>")
        html = (html[:ini] + f'<p class="month-sub">Proyectado S/{p:,.0f} · '
                f'Real S/{r:,.0f} · {n} días</p>' + html[fin:])
        print(f"  {nom}: proy S/{p:,.0f} real S/{r:,.0f} error {e:+.1f}%")

    open(HTML, "w", encoding="utf-8").write(html)
    print(f"{HTML} regenerado")


if __name__ == "__main__":
    main()

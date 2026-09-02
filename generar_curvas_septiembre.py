"""
Genera las curvas de PRODUCCION de SEPTIEMBRE 2026 para los DOS enfoques,
desde las matrices crudas extendidas a 202607 (`datos_tarea19/`).

    datos_capital_asegurado/curva_sep_nuevos_dow_seg.csv   alfa,     nuevos
    datos_capital_asegurado/factor_dia_mes_sep.csv         alfa,     factor 18f
    datos_tarea19/curva_sep_nuevos_rebaje.csv              recupero, nuevos
    datos_tarea19/factor_dia_mes_sep_rebaje.csv            recupero, factor 18f
    datos_tarea19/curva_sep_stock_rebaje.csv               recupero, stock
    datos_tarea19/factor_dia_mes_sep_stock_rebaje.csv      recupero, stock

VENTANA DE NUEVOS: **[202508, 202607]**, 12 meses rodantes terminando en el
ultimo mes COMPLETAMENTE OBSERVADO al 1-sep. Una cohorte necesita 31 dias de
seguimiento: al 1-sep las entradas de julio recien terminan de observarse
(seguimiento hasta el 31-ago) y las de agosto todavia no. Mismo criterio con
el que se fijo la meta de agosto sobre [202507, 202606] -- ver
`generar_curvas_produccion.py` y el protocolo en `CLAUDE.md`.

VENTANA DE STOCK: **NO se toca** -- sigue FIJA en 202504-202606, igual que
produccion desde tarea 17 Fase 4. 18g probo rodarla y EMPEORA las metricas
diarias (corr. 0.848->0.820); extender solo su extremo derecho a 202607 seria
un cambio no medido, asi que tampoco se hace. El alfa reusa tal cual los
archivos que ya existen (`curva_unificada_stock_seg_v3.csv` +
`factor_dia_mes_stock.csv`); el recupero recalibra su curva de stock de rebaje
sobre esa MISMA ventana fija. Es lo que sigue debiendo tarea 18c.

POR QUE ARCHIVOS NUEVOS Y NO SOBREESCRIBIR: los de agosto
(`curva_unificada_nuevos_dow_seg.csv`, `factor_dia_mes.csv`) son los que
reproducen la meta de agosto ya publicada y cerrada. Se dejan intactos.
"""
import csv
import os

import curvas_crudas as CC
import curvas_crudas_stock as CS

DIR_CA = "datos_capital_asegurado"
DIR_19 = "datos_tarea19"
VENTANA_NUEVOS = ("202508", "202607")
VENTANA_STOCK = ("202504", "202606")   # FIJA, sin rodar (18g/18c)


def _escribir_factor(ruta, f_dm, grupos, detalle):
    with open(ruta, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["grupo", "factor", "dias"])
        for g in grupos:
            w.writerow([g, round(f_dm.get(g, 1.0), 6), detalle[g]])


def _escribir_curva_nuevos(ruta, curva):
    with open(ruta, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["avance_band", "dow_venc", "dia", "pct_capital_asegurado_acum"])
        for k in sorted(curva, key=lambda k: (k[0], k[1])):
            for d in sorted(curva[k]):
                w.writerow([k[0], k[1], d, round(curva[k][d], 3)])


def nuevos(matriz, ruta_c, ruta_f, etiqueta):
    base, acts = CC.cargar_matriz(matriz)
    curva, f_dm = CC.calibrar(base, acts, *VENTANA_NUEVOS, con_dow=True, con_f=True,
                              granularidad="estructural")
    _escribir_curva_nuevos(ruta_c, curva)
    _escribir_factor(ruta_f, f_dm, ("quincena", "fin de mes", "resto"),
                     {"quincena": "15,16", "fin de mes": "30,31", "resto": "el resto"})
    print(f"{etiqueta} NUEVOS -- ventana {VENTANA_NUEVOS[0]}-{VENTANA_NUEVOS[1]} (12 meses rodantes)")
    print(f"  {ruta_c}: {len(curva)} segmentos")
    print(f"  {ruta_f}: " + "  ".join(f"{g}={f_dm.get(g,1.0):.4f}"
                                      for g in ("quincena", "fin de mes", "resto")))
    return curva


def stock(matriz, ruta_c, ruta_f, etiqueta):
    base, acts = CS.cargar_matriz(matriz)
    curva, f_dm = CS.calibrar(base, acts, *VENTANA_STOCK, con_f=True, modo_cierre="real")
    with open(ruta_c, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["tramo", "avance_band", "dia", "pct_capital_asegurado_acum"])
        for k in sorted(curva):
            for d in sorted(curva[k]):
                w.writerow([k[0], k[1], d, round(curva[k][d], 3)])
    _escribir_factor(ruta_f, f_dm, ("quincena", "cierre", "resto"),
                     {"quincena": "15,16", "cierre": "ultimo dia real del mes",
                      "resto": "el resto"})
    print(f"{etiqueta} STOCK -- ventana FIJA {VENTANA_STOCK[0]}-{VENTANA_STOCK[1]} (18g/18c)")
    print(f"  {ruta_c}: {len(curva)} segmentos")
    print(f"  {ruta_f}: " + "  ".join(f"{g}={f_dm.get(g,1.0):.4f}"
                                      for g in ("quincena", "cierre", "resto")))


if __name__ == "__main__":
    os.makedirs(DIR_CA, exist_ok=True)
    os.makedirs(DIR_19, exist_ok=True)

    print("=== ENFOQUE ALFA (capital asegurado) ===")
    nuevos(f"{DIR_19}/curva_cruda_nuevos.csv",
           f"{DIR_CA}/curva_sep_nuevos_dow_seg.csv",
           f"{DIR_CA}/factor_dia_mes_sep.csv", "alfa")
    print("  stock: se reusan curva_unificada_stock_seg_v3.csv + factor_dia_mes_stock.csv")
    print("         (ventana fija, sin cambios -- ver docstring)")

    print("\n=== RECUPERO OFICIAL (rebaje) ===")
    nuevos(f"{DIR_19}/curva_cruda_nuevos_rebaje.csv",
           f"{DIR_19}/curva_sep_nuevos_rebaje.csv",
           f"{DIR_19}/factor_dia_mes_sep_rebaje.csv", "recupero")
    stock(f"{DIR_19}/curva_cruda_stock_rebaje.csv",
          f"{DIR_19}/curva_sep_stock_rebaje.csv",
          f"{DIR_19}/factor_dia_mes_sep_stock_rebaje.csv", "recupero")

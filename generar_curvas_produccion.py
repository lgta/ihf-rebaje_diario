"""
Genera las curvas de PRODUCCION del Enfoque alfa desde las matrices
crudas, y las escribe en datos_capital_asegurado/.

    curva_unificada_nuevos_dow_seg.csv   (avance_band, dow_venc) x dia  (motor v2, W3)
    factor_dia_mes.csv                   quincena / fin de mes / resto (motor v2, W3)
    curva_unificada_stock_seg_v3.csv     (tramo, avance_band) x dia    (motor v3, 18g)
    factor_dia_mes_stock.csv             quincena / cierre / resto    (motor v3, 18g)

VENTANA DE CALIBRACION DE NUEVOS: 12 meses rodantes terminando en el
ultimo mes COMPLETAMENTE OBSERVADO al momento de fijar la meta. Para la
meta de agosto-2026 eso es **[202507, 202606]**: una cohorte necesita 31
dias de seguimiento, asi que al 1-ago las entradas de junio recien
terminaban de observarse (seguimiento hasta el 31-jul) y las de julio
todavia no. Calibrar con julio adentro seria usar datos que la meta no
podia tener -- el mismo ajuste ex-post que `CLAUDE.md` prohibe.

El protocolo (12 meses rodantes, ver PENDIENTES.md tarea 18c) sale de
medir la historia usable: antes de 202501 la cartera es <20% de la actual
y la dispersion de la curva se duplica; estirar la ventana a 15-18 meses
mete esos meses y empeora la calibracion en vez de mejorarla
(`tarea18_ventana_calibracion.sql`).

VENTANA DE STOCK: FIJA, 202504-202606 -- la misma que usa produccion
desde tarea 17 Fase 4, NO rodada. Probado en 18g (`backtest_tarea18g.py`,
`analisis_tarea18g_cierre_real.md`): rodar la ventana de stock 12 meses
EMPEORA las metricas diarias (correlacion 0.848->0.820, MAE +10%) porque
stock es el componente de menor masa/mayor varianza muestral -- no sale
gratis como para nuevos. Tarea 18c queda abierta para stock.

**`curva_unificada_stock_seg.csv` (SIN el sufijo `_v3`) y
`curva_unificada_nuevos_dow_seg.csv` / `factor_dia_mes.csv` NO se tocan
si ya existen y este script no cambia su ventana** -- son los archivos
que lee `meta_agosto_capital_asegurado.py`, y la meta de agosto ya esta
fija y publicada. La curva de stock v3 (con el factor de cierre real de
18g) se escribe APARTE, en `curva_unificada_stock_seg_v3.csv`, para que
adoptarla no mueva un numero ya publicado -- la usan el backtest oficial
y, en su momento, la meta de septiembre.
"""
import csv
import os

import curvas_crudas as CC
import curvas_crudas_stock as CS

DIR = "datos_capital_asegurado"
VENTANA_NUEVOS = ("202507", "202606")
VENTANA_STOCK = ("202504", "202606")


def _escribir_factor(ruta, f_dm, grupos, detalle):
    with open(ruta, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["grupo", "factor", "dias"])
        for g in grupos:
            w.writerow([g, round(f_dm.get(g, 1.0), 6), detalle[g]])


def generar_nuevos():
    base, acts = CC.cargar_matriz()
    curva, f_dm = CC.calibrar(base, acts, *VENTANA_NUEVOS, con_dow=True, con_f=True)

    os.makedirs(DIR, exist_ok=True)
    ruta_c = f"{DIR}/curva_unificada_nuevos_dow_seg.csv"
    with open(ruta_c, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["avance_band", "dow_venc", "dia", "pct_capital_asegurado_acum"])
        for (banda, dow) in sorted(curva, key=lambda k: (k[0], k[1])):
            for d in sorted(curva[(banda, dow)]):
                w.writerow([banda, dow, d, round(curva[(banda, dow)][d], 3)])

    ruta_f = f"{DIR}/factor_dia_mes.csv"
    _escribir_factor(ruta_f, f_dm, ("quincena", "fin de mes", "resto"),
                      {"quincena": "15,16", "fin de mes": "30,31", "resto": "el resto"})

    print(f"NUEVOS -- ventana de calibracion: {VENTANA_NUEVOS[0]} a {VENTANA_NUEVOS[1]} (12 meses)")
    print(f"  {ruta_c}: {len(curva)} segmentos (4 bandas x 6 dias de semana)")
    print(f"  {ruta_f}: " + "  ".join(f"{g}={f_dm.get(g,1.0):.4f}"
                                      for g in ("quincena", "fin de mes", "resto")))
    print("\nDia 0 de la curva por dia de semana del vencimiento (ponderado):")
    NOM = {1: "lunes", 2: "martes", 3: "miercoles", 4: "jueves", 5: "viernes", 6: "sabado"}
    ENT = {1: "martes", 2: "miercoles", 3: "jueves", 4: "viernes", 5: "sabado", 6: "domingo"}
    bandas = sorted({k[0] for k in curva})
    print("  " + " " * 30 + "  ".join(f"{b[:12]:>12}" for b in bandas))
    for dw in sorted({k[1] for k in curva}):
        print(f"  venc {NOM[dw]:<10} entra {ENT[dw]:<9} "
              + "  ".join(f"{curva[(b, dw)].get(0, 0.0):>11.2f}%" for b in bandas))


def generar_stock_v3():
    base, acts = CS.cargar_matriz()
    curva, f_dm = CS.calibrar(base, acts, *VENTANA_STOCK, con_f=True, modo_cierre="real")

    os.makedirs(DIR, exist_ok=True)
    ruta_c = f"{DIR}/curva_unificada_stock_seg_v3.csv"
    with open(ruta_c, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["tramo", "avance_band", "dia", "pct_capital_asegurado_acum"])
        for (tramo, banda) in sorted(curva):
            for d in sorted(curva[(tramo, banda)]):
                w.writerow([tramo, banda, d, round(curva[(tramo, banda)][d], 3)])

    ruta_f = f"{DIR}/factor_dia_mes_stock.csv"
    _escribir_factor(ruta_f, f_dm, ("quincena", "cierre", "resto"),
                      {"quincena": "15,16", "cierre": "ultimo dia real del mes",
                       "resto": "el resto"})

    print(f"\nSTOCK v3 (18g) -- ventana de calibracion FIJA: {VENTANA_STOCK[0]} a {VENTANA_STOCK[1]}"
          f" (sin rodar -- 18c probado y descartado, ver analisis_tarea18g_cierre_real.md)")
    print(f"  {ruta_c}: {len(curva)} segmentos (3 tramos x 4 bandas)")
    print(f"  {ruta_f}: " + "  ".join(f"{g}={f_dm.get(g,1.0):.4f}"
                                      for g in ("quincena", "cierre", "resto")))


if __name__ == "__main__":
    generar_nuevos()
    generar_stock_v3()

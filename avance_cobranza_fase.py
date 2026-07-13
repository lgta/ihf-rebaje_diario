"""
Avance de julio 2026 por fase de cobranza (Temprana/Especializada/Recovery),
usando la asignacion REAL del negocio (dts_asignaciones_cobranza) en vez de
la poblacion inferida via dayslate. "Rebaje" = capital ASEGURADO (enfoque
alfa: saldo completo del credito si mostro >=1 dia de pago), no el recupero
oficial -- ver avance_cobranza_fase.md para la explicacion completa.

Dia 1 = 2026-07-02 (la tabla de asignaciones no tiene 1-jul, ver el .md).
Dia objetivo = 2026-07-12 (dia 11 desde la asignacion, ultima fecha con
datos en dts_mambu_loans_hist a la fecha de esta corrida).

Insumos:
  avance_cobranza_fase.sql -> datos_avance_fase/avance_fase_extraccion.csv
    (una fila por credito de la cohorte del 2-jul)
  datos_capital_asegurado/curva_asegurado_stock_seg.csv y
  datos_capital_asegurado/curva_asegurado_nuevos_seg.csv (curvas ya
    calibradas del enfoque alfa, reutilizadas tal cual)
"""
import csv
from datetime import date

DIR_ASEG = "datos_capital_asegurado"
DIR_FASE = "datos_avance_fase"

curva_stock = {}
with open(f"{DIR_ASEG}/curva_asegurado_stock_seg.csv") as f:
    for row in csv.DictReader(f):
        key = (row["tramo"], row["avance_band"])
        curva_stock.setdefault(key, {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

curva_nuevos = {}
with open(f"{DIR_ASEG}/curva_asegurado_nuevos_seg.csv") as f:
    for row in csv.DictReader(f):
        curva_nuevos.setdefault(row["avance_band"], {})[int(row["dia"])] = float(row["pct_capital_asegurado_acum"])

def lookup(curva, d):
    if d <= 0 or not curva:
        return None
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else None

DIA_OBJETIVO = 11  # 2-jul = dia1 ... 12-jul = dia11
FECHA_OBJETIVO = date(2026, 7, 12)

filas = []
with open(f"{DIR_FASE}/avance_fase_extraccion.csv") as f:
    for row in csv.DictReader(f):
        filas.append(row)

grupos = {}
for r in filas:
    fase = r["fase_estrategia"] or "(sin fase)"
    # segmento simplificado a 2 categorias: nuevo (mora_jun=0) / stock (mora_jun>0, cualquier profundidad)
    seg = "nuevo" if r["segmento"] == "nuevo" else "stock"
    # sub-tramo (1-8/9-15/16-30) solo para Temprana-stock -- es el unico caso donde
    # tramo_jun (tramo fijo al cierre de junio, igual criterio que el resto del proyecto)
    # tiene cobertura real; "nuevo" entra siempre con mora 1-2 dias (trivial, no aporta)
    # y Especializada/Recovery casi no tienen saldo dentro de 1-30 (ver cobertura de curva).
    subtramo = r["tramo_jun"] if (fase == "TEMPRANA" and seg == "stock" and r["tramo_jun"]) else None
    key = (fase, seg, subtramo)
    g = grupos.setdefault(key, {
        "cuentas": 0, "asignacion": 0.0, "asignacion_con_curva": 0.0, "meta_s": 0.0,
        "real_s": 0.0,
    })
    saldo = float(r["saldo_dia1"])
    g["cuentas"] += 1
    g["asignacion"] += saldo

    pct_meta = None
    if seg == "stock" and r["tramo_jun"]:
        pct_meta = lookup(curva_stock.get((r["tramo_jun"], r["avance_band"]), {}), DIA_OBJETIVO)
    elif seg == "nuevo" and r["fecha_entrada"]:
        fecha_entrada = date(int(r["fecha_entrada"][:4]), int(r["fecha_entrada"][4:6]), int(r["fecha_entrada"][6:8]))
        dias_desde_entrada = (FECHA_OBJETIVO - fecha_entrada).days
        pct_meta = lookup(curva_nuevos.get(r["avance_band"], {}), dias_desde_entrada)
    # sin tramo_jun/fecha_entrada (mora 31+ a cierre de junio, o sin curva) -> sin curva calibrada

    if pct_meta is not None:
        g["meta_s"] += saldo * pct_meta / 100.0
        g["asignacion_con_curva"] += saldo

    if r["fecha_primer_pago"]:
        g["real_s"] += saldo

orden_fase = {"TEMPRANA": 0, "ESPECIALIZADA": 1, "RECOVERY": 2, "(sin fase)": 3}
orden_seg = {"nuevo": 0, "stock": 1}

if __name__ == "__main__":
    print(f"{'COBRANZA':<14} {'Segmento':<20} {'Cuentas':>8} {'Asignacion S/':>14} {'Cobertura curva':>16} {'Meta CapAseg %':>15} {'Meta CapAseg S/':>16} {'Real CapAseg S/':>16} {'Real CapAseg %':>15} {'Real-Meta pp':>13}")
    for (fase, seg, subtramo), g in sorted(grupos.items(), key=lambda kv: (orden_fase.get(kv[0][0], 9), orden_seg.get(kv[0][1], 9), kv[0][2] or "")):
        if subtramo:
            seg_label = f"{seg} ({subtramo[3:]})"
        elif fase == "TEMPRANA" and seg == "stock":
            seg_label = "stock (31+, arrastre)"
        else:
            seg_label = seg
        asignacion = g["asignacion"]
        real_pct = 100 * g["real_s"] / asignacion if asignacion else 0
        cobertura = 100 * g["asignacion_con_curva"] / asignacion if asignacion else 0
        if g["asignacion_con_curva"] > 0:
            meta_pct_sobre_cubierto = 100 * g["meta_s"] / g["asignacion_con_curva"]
            meta_s_str = f"{g['meta_s']:,.0f}"
            meta_pct_str = f"{meta_pct_sobre_cubierto:.1f}%"
            diff_str = f"{real_pct - meta_pct_sobre_cubierto:+.1f}"
        else:
            meta_s_str = "N/D"
            meta_pct_str = "N/D"
            diff_str = "N/D"
        print(f"{fase:<14} {seg_label:<20} {g['cuentas']:>8} {asignacion:>14,.0f} {cobertura:>15.1f}% {meta_pct_str:>15} {meta_s_str:>16} {g['real_s']:>16,.0f} {real_pct:>14.1f}% {diff_str:>13}")

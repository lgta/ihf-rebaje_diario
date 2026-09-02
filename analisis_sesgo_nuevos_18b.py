"""
TAREA 18b -- por que "nuevos" subestima en los 7 meses de test, sin excepcion,
y por que febrero es ademas el unico mes donde STOCK tambien falla fuerte.

No usa Athena -- todo sale de los CSV que ya produjo el walk-forward de 18a/18f
(datos_tarea18a/) y de la matriz cruda (datos_tarea18a/curva_cruda.csv). Dos
hallazgos independientes, cada uno reproducible por separado:

  (1) P_ENTRADA (21.9918%) se calibro por CONTEO DE CREDITOS
      (tarea17_fase4_tasa.sql: `count(*)`, `sum(case when ... then 1 else 0)`,
      el propio comentario del archivo dice "Salida en creditos (no soles)")
      pero se aplica en produccion (`motor_unificado.proyectar`) multiplicando
      el SALDO EN SOLES del calendario. Como el exceso de entrada a mora esta
      concentrado en creditos de saldo mas alto (ya medido en
      analisis_volumen_efectividad_agosto.md para agosto), la tasa por conteo
      SUBESTIMA la tasa real ponderada por soles -- que es la que el modelo
      necesitaria. Este script mide esa tasa real ponderada por soles, mes a
      mes, con la MISMA matriz cruda que arma la curva de produccion, y prueba
      contrafactualmente cuanto del error de "nuevos" desaparece si se usa la
      tasa real de cada mes en vez de la constante fija.

  (2) Por que febrero (el unico mes de 28 dias del test) es tambien el unico
      mes donde STOCK falla fuerte (-11.0%, contra -4.5%..+5.3% del resto):
      el factor de dia del mes (18f) y la curva de stock indexan por NUMERO
      de dia calendario, y el grupo "fin de mes" son literalmente los dias
      30/31 -- que febrero nunca alcanza. El verdadero pago de fin de mes de
      febrero cae en su propio ultimo dia (28), pero el modelo lo trata como
      un dia "resto" cualquiera. Este script mide que fraccion del gap total
      de stock en cada mes esta concentrada en el ultimo dia.

Principio de CLAUDE.md aplicado: esto es diagnostico, no ajuste. No cambia
P_ENTRADA ni ninguna curva -- solo cuantifica el mecanismo para que la
decision de si vale la pena corregirlo (y como) sea del usuario.
"""
import csv
import collections
import statistics as st

import curvas_crudas as CC
from motor_unificado import cargar_curva_stock, segmentar_calendario, proyectar, acumular_real

DIR_18A = "datos_tarea18a"
DIR_OUT = "datos_backtest_unificado"
MESES = [("202601", 31), ("202602", 28), ("202603", 31), ("202604", 30),
         ("202605", 31), ("202606", 30), ("202607", 31)]
MESES_CALIBRACION = 12
P_ENTRADA_FIJO = 75621 / 343860


def leer(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def ventana(periodo, meses=MESES_CALIBRACION):
    y, m = int(periodo[:4]), int(periodo[4:])
    fin_y, fin_m = (y, m - 1) if m > 1 else (y - 1, 12)
    ini = fin_y * 12 + (fin_m - 1) - (meses - 1)
    return f"{ini // 12:04d}{ini % 12 + 1:02d}", f"{fin_y:04d}{fin_m:02d}"


def parte1_tasa_real_ponderada_por_soles():
    print("=" * 100)
    print("(1) TASA DE ENTRADA PONDERADA POR SOLES vs. P_ENTRADA (calibrada por conteo de creditos)")
    print("=" * 100)

    curva_stock = cargar_curva_stock()
    stock_pob = collections.defaultdict(dict)
    for r in leer(f"{DIR_18A}/stock_pob_7m.csv"):
        stock_pob[r["periodo_meta"]][(r["tramo"], r["avance_band"])] = float(r["saldo_total"])
    calendario = collections.defaultdict(lambda: collections.defaultdict(dict))
    for r in leer(f"{DIR_18A}/calendario_7m.csv"):
        calendario[r["periodo"]][int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo_en_riesgo"])
    real_stock, real_nuevos = collections.defaultdict(dict), collections.defaultdict(dict)
    for r in leer(f"{DIR_18A}/real_stock_7m.csv"):
        real_stock[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])
    for r in leer(f"{DIR_18A}/real_nuevos_7m.csv"):
        real_nuevos[r["periodo_meta"]][int(r["dia"])] = float(r["saldo_activado_dia"])

    base_raw, acts_raw = CC.cargar_matriz()

    calendario_total = collections.defaultdict(float)
    for r in leer(f"{DIR_18A}/calendario_7m.csv"):
        calendario_total[r["periodo"]] += float(r["saldo_en_riesgo"])
    entrada_total = collections.defaultdict(float)
    for r in leer(f"{DIR_18A}/curva_cruda.csv"):
        if r["tipo"] == "base":
            entrada_total[r["fecha_entrada"][:6]] += float(r["saldo"])

    hdr = (f"{'periodo':<8} {'tasa_real (soles)':>18} {'err_nuevos fijo':>16} "
           f"{'err_nuevos c/tasa real':>23} {'%% de la magnitud explicada':>28}")
    print(hdr)
    print("-" * len(hdr))
    tasas, errs_fijo = [], []
    reducciones = []
    for periodo, n in MESES:
        if entrada_total.get(periodo, 0) == 0:
            print(f"{periodo:<8}  -- sin datos de entrada real en la matriz cruda "
                  f"(rango de tarea18f_curva_cruda.sql: 20250101-20260630) --")
            continue
        tasa_real = entrada_total[periodo] / calendario_total[periodo]
        d, h = ventana(periodo)
        curva_n, f_dm = CC.calibrar(base_raw, acts_raw, d, h, con_dow=True, con_f=True)
        seg_cal = segmentar_calendario(calendario[periodo], periodo)
        rn = acumular_real(real_nuevos[periodo], n)[-1]

        f_fijo = proyectar(stock_pob[periodo], seg_cal, curva_stock, curva_n, n,
                            p_entrada=P_ENTRADA_FIJO, f_dm=f_dm)
        err_fijo = 100 * (f_fijo[-1]["proy_nuevos"] - rn) / rn

        f_real = proyectar(stock_pob[periodo], seg_cal, curva_stock, curva_n, n,
                            p_entrada=tasa_real, f_dm=f_dm)
        err_real = 100 * (f_real[-1]["proy_nuevos"] - rn) / rn

        reduccion = 100 * (abs(err_fijo) - abs(err_real)) / abs(err_fijo)
        tasas.append(tasa_real)
        errs_fijo.append(err_fijo)
        reducciones.append(reduccion)
        print(f"{periodo:<8} {100*tasa_real:>17.2f}% {err_fijo:>+15.1f}% "
              f"{err_real:>+22.1f}% {reduccion:>27.1f}%")

    print(f"\nP_ENTRADA fijo (produccion) = {100*P_ENTRADA_FIJO:.4f}%  -- calibrado POR CONTEO DE"
          f" CREDITOS (tarea17_fase4_tasa.sql)")
    print(f"Tasa real ponderada por SOLES, ene-jun: {min(100*t for t in tasas):.2f}%-"
          f"{max(100*t for t in tasas):.2f}% (siempre por encima de la fija)")
    print(f"Correlacion (err_nuevos con tasa fija) vs (tasa real del mes): "
          f"{st.correlation(errs_fijo, [100*t for t in tasas]):.3f}")
    print(f"Reduccion media de |error| al usar la tasa real en vez de la fija: "
          f"{sum(reducciones)/len(reducciones):.1f}%  (mediana {st.median(reducciones):.1f}%)")


def parte2_dia_28_febrero():
    print()
    print("=" * 100)
    print("(2) POR QUE FEBRERO TAMBIEN FALLA EN STOCK: el gap se concentra en el ultimo dia")
    print("=" * 100)
    hdr = (f"{'periodo':<8} {'n_dias':>6} {'gap_stock_total':>16} {'gap_ultimo_dia':>16} "
           f"{'%% del gap en el ultimo dia':>28}")
    print(hdr)
    print("-" * len(hdr))
    for periodo, n in MESES:
        rows = list(csv.DictReader(open(f"{DIR_OUT}/serie_diaria_{periodo}.csv")))
        last, prev = rows[-1], rows[-2]
        gap_total = float(last["real_stock"]) - float(last["proy_stock"])
        gap_ultimo = ((float(last["real_stock"]) - float(prev["real_stock"]))
                       - (float(last["proy_stock"]) - float(prev["proy_stock"])))
        pct = 100 * gap_ultimo / gap_total if gap_total else float("nan")
        marca = "  <-- unico mes de 28 dias" if n == 28 else ""
        print(f"{periodo:<8} {n:>6} {gap_total:>16,.0f} {gap_ultimo:>16,.0f} {pct:>27.1f}%{marca}")

    print("\nRatio real/proyectado del INCREMENTO DIARIO de stock, ultimos dias de cada mes:")
    for periodo, n in MESES:
        rows = list(csv.DictReader(open(f"{DIR_OUT}/serie_diaria_{periodo}.csv")))
        tramo = rows[-4:]
        vals = []
        for i, r in enumerate(tramo):
            idx = len(rows) - 4 + i
            prev = rows[idx - 1] if idx > 0 else {"proy_stock": "0", "real_stock": "0"}
            inc_p = float(r["proy_stock"]) - float(prev["proy_stock"])
            inc_r = float(r["real_stock"]) - float(prev["real_stock"])
            vals.append(f"d{r['dia']}={inc_r/inc_p if inc_p else float('nan'):.2f}")
        print(f"  {periodo} (n={n}): " + "  ".join(vals))


if __name__ == "__main__":
    parte1_tasa_real_ponderada_por_soles()
    parte2_dia_28_febrero()

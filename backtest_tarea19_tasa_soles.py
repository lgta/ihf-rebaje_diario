"""
TAREA 19 -- DECISION DE 18b LLEVADA A PRUEBA: P_ENTRADA por CONTEO vs. por
SOLES en el Enfoque alfa, sobre el backtest oficial de 7 meses.

CONTEXTO. `analisis_sesgo_nuevos_18b.md` midio que ~78% de la magnitud del
sesgo de "nuevos" (subestima en los 7 meses sin excepcion) viene de mezclar
dos definiciones: `P_ENTRADA = 21.9918%` se calibra CONTANDO creditos, pero
`motor_unificado.proyectar()` la aplica multiplicando el SALDO EN SOLES del
calendario. La tasa real ponderada por soles corre 24-27% (r = -0.93 con el
error). Recupero Oficial ya corrigio esto en 18e (tasa por soles ~25.2%);
el Enfoque alfa no, porque agosto estaba en curso y no se cambia el motor de
un mes a mitad de camino. Agosto cerro -- septiembre es la primera meta que
puede nacer con la definicion consistente.

POR QUE LA TASA DE 18e SIRVE TAL CUAL PARA ESTE ENFOQUE. La definicion de
"entrada" es LA MISMA en los dos motores (dias_atraso_cuota 0->1, calendario
elegible = entrada dentro del mes, excluye stock); lo que difiere aguas abajo
es la CURVA (activacion vs. rebaje), no el universo. Verificado con datos:
sobre la ventana [202508,202605] la query de soles reproduce el P_ENTRADA del
alfa en creditos -- 75,613/343,788 = 21.9941% contra 75,621/343,860 =
21.9918% (8 creditos de diferencia, por los filtros `amountfinanced > 0` y el
join de saldo al vencimiento). Misma poblacion, dos unidades.

DISENO DE LA PRUEBA -- 3 variantes, para no confundir dos cambios en uno:
  A. fija por conteo   21.9918%      <- produccion hoy (v3)
  B. rodante por conteo [M-12,M-1]   <- aisla el efecto de RODAR la tasa
  C. rodante por soles  [M-12,M-1]   <- la propuesta (B->C = efecto de la
                                        DEFINICION, que es lo que se decide)
Sin B, el salto A->C mezclaria "rodar" con "cambiar de unidad" y no se sabria
cual pesa.

QUE METRICA MIRA QUE (CLAUDE.md). Esto es un cambio de NIVEL, no de forma:
multiplica el componente "nuevos" por un escalar. La correlacion de
incrementos diarios es invariante a escala, asi que NO se mueve y no puede
arbitrar nada aca -- se reporta igual, para dejar constancia de que no se
degrada. El MAE del incremento diario si se mueve (tiene unidades). Y el
error de cierre es el numero de negocio.

Y EL MOTIVO DE ADOPCION NO ES QUE EL ERROR BAJE. Se adopta -- si se adopta --
porque tasa y curva quedan calibradas sobre la misma definicion (Principio de
modelado, `CLAUDE.md`; bug 10 es el caso donde ignorarlo salio caro). Que el
error de cierre baje es consecuencia esperada, no la justificacion: si
subiera, el criterio seguiria siendo el mismo.

Insumos: los del backtest oficial (`backtest_capital_asegurado_unificado.py`)
mas `datos_tarea19/tasa_soles.csv` (tarea19_tasa_soles.sql, 202501-202607).
"""
import collections
import csv
import statistics

import curvas_crudas as CC
from motor_unificado import (P_ENTRADA, cargar_curva_stock,
                             cargar_factor_dia_mes_stock, segmentar_calendario,
                             proyectar, acumular_real)

DIR_18A = "datos_tarea18a"
DIR_19 = "datos_tarea19"
MESES_CALIBRACION = 12

MESES = [("202601", 31, "Enero 2026"), ("202602", 28, "Febrero 2026"),
         ("202603", 31, "Marzo 2026"), ("202604", 30, "Abril 2026"),
         ("202605", 31, "Mayo 2026"), ("202606", 30, "Junio 2026"),
         ("202607", 31, "Julio 2026")]


def leer(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def ventana(periodo, meses=MESES_CALIBRACION):
    """[M-meses, M-1] como ('YYYYMM','YYYYMM'). Nunca ve el mes M."""
    y, m = int(periodo[:4]), int(periodo[4:])
    fin_y, fin_m = (y, m - 1) if m > 1 else (y - 1, 12)
    ini = fin_y * 12 + (fin_m - 1) - (meses - 1)
    return f"{ini // 12:04d}{ini % 12 + 1:02d}", f"{fin_y:04d}{fin_m:02d}"


curva_stock = cargar_curva_stock("datos_capital_asegurado/curva_unificada_stock_seg_v3.csv")
f_dm_stock = cargar_factor_dia_mes_stock()

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

# periodo -> (elegibles_creditos, entran_creditos, elegibles_soles, entran_soles)
tasa_mes = {}
for r in leer(f"{DIR_19}/tasa_soles.csv"):
    tasa_mes[r["periodo"]] = (float(r["elegibles_creditos"]), float(r["entran_creditos"]),
                              float(r["elegibles_soles"]), float(r["entran_soles"]))


def tasa_rodante(periodo, unidad):
    """unidad: 'creditos' (indices 0,1) o 'soles' (indices 2,3)."""
    d, h = ventana(periodo)
    i = 0 if unidad == "creditos" else 2
    elig = sum(v[i] for p, v in tasa_mes.items() if d <= p <= h)
    ent = sum(v[i + 1] for p, v in tasa_mes.items() if d <= p <= h)
    return ent / elig


base_raw, acts_raw = CC.cargar_matriz()
_cache = {}


def curva_de(periodo):
    if periodo not in _cache:
        d, h = ventana(periodo)
        _cache[periodo] = CC.calibrar(base_raw, acts_raw, d, h, con_dow=True, con_f=True)
    return _cache[periodo]


def correr(periodo, n_dias, p_entrada):
    curva_n, f_dm = curva_de(periodo)
    filas = proyectar(stock_pob[periodo],
                      segmentar_calendario(calendario[periodo], periodo),
                      curva_stock, curva_n, n_dias, p_entrada=p_entrada,
                      f_dm=f_dm, f_dm_stock=f_dm_stock)
    rs = acumular_real(real_stock[periodo], n_dias)
    rn = acumular_real(real_nuevos[periodo], n_dias)
    for i, fila in enumerate(filas):
        fila["real_stock"] = rs[i]
        fila["real_nuevos"] = rn[i]
        fila["real_total"] = rs[i] + rn[i]
    return filas


def metricas(filas, n):
    f = filas[-1]
    inc = lambda s: [s[0]] + [s[i] - s[i - 1] for i in range(1, n)]
    pn = inc([x["proy_nuevos"] for x in filas])
    rn = inc([x["real_nuevos"] for x in filas])
    return {
        "err": 100 * (f["proy_total"] - f["real_total"]) / f["real_total"],
        "err_n": 100 * (f["proy_nuevos"] - f["real_nuevos"]) / f["real_nuevos"],
        "corr": statistics.correlation(pn, rn),
        "mae": sum(abs(a - b) for a, b in zip(pn, rn)) / n,
        "proy": f["proy_total"],
        "real": f["real_total"],
    }


VARIANTES = [
    ("A. fija conteo",    lambda p: P_ENTRADA),
    ("B. rodante conteo", lambda p: tasa_rodante(p, "creditos")),
    ("C. rodante soles",  lambda p: tasa_rodante(p, "soles")),
]

if __name__ == "__main__":
    print("=" * 118)
    print("TAREA 19 -- P_ENTRADA POR CONTEO vs. POR SOLES (decision de 18b), backtest oficial de 7 meses")
    print("=" * 118)
    print()

    res = {}
    for nombre, f_tasa in VARIANTES:
        res[nombre] = {}
        for periodo, n, _ in MESES:
            res[nombre][periodo] = (metricas(correr(periodo, n, f_tasa(periodo)), n),
                                    f_tasa(periodo))

    print("ERROR DE CIERRE POR MES (proyectado vs. real)")
    hdr = f"{'Mes':<14} | " + " | ".join(f"{v[0]:>26}" for v in VARIANTES)
    print(hdr)
    print(f"{'':14} | " + " | ".join(f"{'tasa':>8} {'err tot':>8} {'err nuev':>8}"
                                     for _ in VARIANTES))
    print("-" * len(hdr))
    for periodo, n, nombre in MESES:
        linea = f"{nombre:<14} | "
        celdas = []
        for v, _ in VARIANTES:
            m, t = res[v][periodo]
            celdas.append(f"{100*t:>7.2f}% {m['err']:>+7.1f}% {m['err_n']:>+7.1f}%")
        print(linea + " | ".join(celdas))

    print("-" * len(hdr))
    linea = f"{'MAGNITUD MEDIA':<14} | "
    celdas = []
    for v, _ in VARIANTES:
        ms = [res[v][p][0] for p, _, _ in MESES]
        celdas.append(f"{'':>8} {sum(abs(m['err']) for m in ms)/7:>7.2f}% "
                      f"{sum(abs(m['err_n']) for m in ms)/7:>7.2f}%")
    print(linea + " | ".join(celdas))

    print()
    print("METRICAS DIARIAS DEL COMPONENTE 'NUEVOS' (correlacion de incrementos, MAE en S/)")
    hdr2 = f"{'Mes':<14} | " + " | ".join(f"{v[0]:>20}" for v in VARIANTES)
    print(hdr2)
    print(f"{'':14} | " + " | ".join(f"{'corr':>8} {'MAE':>11}" for _ in VARIANTES))
    print("-" * len(hdr2))
    for periodo, n, nombre in MESES:
        celdas = [f"{res[v][periodo][0]['corr']:>8.3f} {res[v][periodo][0]['mae']:>11,.0f}"
                  for v, _ in VARIANTES]
        print(f"{nombre:<14} | " + " | ".join(celdas))
    print("-" * len(hdr2))
    celdas = []
    for v, _ in VARIANTES:
        ms = [res[v][p][0] for p, _, _ in MESES]
        celdas.append(f"{sum(m['corr'] for m in ms)/7:>8.3f} {sum(m['mae'] for m in ms)/7:>11,.0f}")
    print(f"{'MEDIA':<14} | " + " | ".join(celdas))

    print()
    print("COMO LEER ESTO:")
    print("- A->B aisla el efecto de RODAR la tasa; B->C, el de cambiar de CONTEO a SOLES.")
    print("  El segundo es el que esta en discusion (Principio de modelado, CLAUDE.md).")
    print("- La correlacion diaria es invariante a escala: cambiar la tasa NO la mueve.")
    print("  Se imprime para dejar constancia de que no se degrada, no para arbitrar.")
    print("- El motivo de adopcion es que tasa y curva queden en la MISMA definicion, no")
    print("  que el error baje (principio de interpretacion del error, CLAUDE.md).")

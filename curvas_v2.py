"""
TAREA 24 -- lectura de las matrices de la recalibracion v2 (`tarea24_v2_*.sql`,
`datos_tarea24/`) con los filtros de cada variante, en el MISMO formato que ya
consumen `curvas_crudas.calibrar`, `curvas_crudas_stock.calibrar` y
`motor_unificado.proyectar`. No toca esos modulos: solo arma (base, acts),
poblaciones, calendarios, tasas y reales.

Las matrices traen las dos definiciones de antiguo en la misma foto de Mambu:
  v1 = dias_atraso_cuota 1-30 al CIERRE del mes anterior (produccion hasta hoy)
  v2 = dias_atraso_cuota 1-30 el DIA 1 del mes (decision del usuario 2026-09-13)
Filtrada como v1, cada matriz reproduce su equivalente de `datos_tarea19/` a
<= 1.2% (re-expresion de Mambu): es el control de que las queries nuevas estan
bien.

Parametros de cada variante:
  definicion  'v1' | 'v2'
  medida      'act' (Enfoque alfa, activacion) | 'reb' (Recupero oficial, rebaje)
  arrastre    'fuera'  = los creditos con flg_arrastre_dni se sacan de la
                         poblacion, de la curva, del numerador de la tasa y del
                         real (como la vista: no son TEMPRANA)
              'dentro' = no se distingue (lo que hacia produccion)
  reeng       False = fuera (produccion) | True = incluidos marcados (bug 25,
              decision pendiente del usuario)
"""
import collections
import csv
import datetime as dt

MS = "datos_tarea24/v2_matriz_stock.csv"
MN = "datos_tarea24/v2_matriz_nuevos.csv"
CT = "datos_tarea24/v2_calendario_tasa.csv"

# Tramo propio de la cohorte que entra en mora el dia 1 (stock v2, variante S1).
TRAMO_D1 = "a0. entra el dia 1"

_cache = {}


def _leer(path):
    if path not in _cache:
        with open(path) as f:
            _cache[path] = list(csv.DictReader(f))
    return _cache[path]


def _fecha(s):
    return dt.date(int(s[:4]), int(s[4:6]), int(s[6:8]))


def _pasa(r, arrastre, reeng):
    if not reeng and r["reeng"] == "1":
        return False
    if arrastre == "fuera" and r["arrastre"] == "1":
        return False
    return True


# ---------------------------------------------------------------------------
# STOCK
# ---------------------------------------------------------------------------
def stock_matriz(definicion, medida, arrastre="fuera", reeng=False, seg_d1=False, solo_d1=None):
    """(base, acts) al grano (periodo_meta, tramo, avance_band) -- el formato de
    `curvas_crudas_stock.cargar_matriz`.

    seg_d1  True: la cohorte d1 (entro en mora el dia 1) va con tramo TRAMO_D1.
    solo_d1 None: todo el stock | False: sin la cohorte d1 | True: solo la d1.
    """
    base = collections.defaultdict(float)
    acts = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in _leer(MS):
        if r["definicion"] != definicion or not _pasa(r, arrastre, reeng):
            continue
        if solo_d1 is not None and (r["d1"] == "1") != solo_d1:
            continue
        tramo = TRAMO_D1 if (seg_d1 and r["d1"] == "1") else r["tramo"]
        k = (r["periodo_meta"], tramo, r["avance_band"])
        if r["tipo"] == "base":
            base[k] += float(r["saldo"])
        elif r["tipo"] == medida:
            acts[k][int(r["dia"])] += float(r["saldo"])
    return dict(base), {k: dict(v) for k, v in acts.items()}


def poblacion(base, periodo):
    """{(tramo, avance_band): saldo} del mes -- lo que `proyectar` recibe como stock."""
    return {(t, b): s for (p, t, b), s in base.items() if p == periodo}


def real_por_dia(acts, periodo):
    """{dia: saldo activado (o rebajado) ese dia} sumando todos los segmentos del mes."""
    out = collections.defaultdict(float)
    for (p, _t, _b), dias in acts.items():
        if p == periodo:
            for d, s in dias.items():
                out[d] += s
    return dict(out)


def cohorte_d1(base, periodo):
    """{avance_band: saldo} de la cohorte d1 del mes (base de stock_matriz(solo_d1=True))."""
    out = collections.defaultdict(float)
    for (p, _t, b), s in base.items():
        if p == periodo:
            out[b] += s
    return dict(out)


# ---------------------------------------------------------------------------
# NUEVOS
# ---------------------------------------------------------------------------
def _es_nuevo(r, definicion, para_curva):
    """v1: la curva usa TODAS las entradas (produccion no excluia el stock) y el
    real excluye el stock v1 (tarea19_real_nuevos_8m.sql).
    v2: curva y real sin el stock v2 y sin las entradas del dia 1 -- una sola
    definicion de nuevo en todo el motor."""
    if definicion == "v1":
        return para_curva or r["st_v1"] == "0"
    return r["st_v2"] == "0" and r["fecha_entrada"][6:] != "01"


def nuevos_matriz(definicion, medida, arrastre="fuera", reeng=False):
    """(base, acts) al grano (fecha_entrada, avance_band) -- el formato de
    `curvas_crudas.cargar_matriz`.

    OJO: las entradas de 202608 tienen el seguimiento truncado al 1-sep (ver
    tarea24_v2_matriz_nuevos.sql): ninguna ventana de calibracion puede
    incluirlas."""
    base = collections.defaultdict(float)
    acts = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in _leer(MN):
        if not _pasa(r, arrastre, reeng) or not _es_nuevo(r, definicion, para_curva=True):
            continue
        k = (_fecha(r["fecha_entrada"]), r["avance_band"])
        if r["tipo"] == "base":
            base[k] += float(r["saldo"])
        elif r["tipo"] == medida:
            acts[k][int(r["dia"])] += float(r["saldo"])
    return dict(base), {k: dict(v) for k, v in acts.items()}


def nuevos_real(definicion, medida, arrastre="fuera", reeng=False):
    """{periodo: {dia: saldo}} -- lo que activa (o rebaja) DENTRO del mes cada
    cohorte que entra en el mes."""
    out = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in _leer(MN):
        if r["tipo"] != medida or not _pasa(r, arrastre, reeng):
            continue
        if not _es_nuevo(r, definicion, para_curva=False):
            continue
        fe = _fecha(r["fecha_entrada"])
        fp = fe + dt.timedelta(days=int(r["dia"]))
        if fp.month == fe.month:
            out[fe.strftime("%Y%m")][fp.day] += float(r["saldo"])
    return {p: dict(v) for p, v in out.items()}


# ---------------------------------------------------------------------------
# CALENDARIO Y TASA -- salen de la misma query, asi que comparten poblacion
# ---------------------------------------------------------------------------
def _en_calendario(r, definicion, reeng, todas_las_cuotas):
    if not reeng and r["reeng"] == "1":
        return False
    if definicion == "v1":
        return r["st_v1"] == "0" and (todas_las_cuotas or r["orden"] == "1")
    return r["st_v2"] == "0" and r["orden_d2"] == "1"


def calendario(definicion, periodo, reeng=False, todas_las_cuotas=False):
    """{dia_entrada: {avance_band: saldo al vencimiento}} (medido, para backtest).

    todas_las_cuotas (solo v1): True = como calendario_8m, sumando las dos
    cuotas del credito que entra el dia 1 y el 31 (asi se publico, bug 23);
    False = una cuota por credito, la misma base que la tasa. En v2 no hace
    falta: la cuota que entra el dia 1 no es calendario, queda una sola."""
    cal = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in _leer(CT):
        if r["periodo"] == periodo and _en_calendario(r, definicion, reeng, todas_las_cuotas):
            cal[int(r["dia_entrada"])][r["avance_band"]] += float(r["saldo"])
    return {d: dict(v) for d, v in cal.items()}


def tasa_mensual(definicion, arrastre="fuera", reeng=False):
    """{periodo: (elegibles_soles, entran_soles)}. Con arrastre='fuera' el
    numerador cuenta solo a los que entran SIN arrastre: la tasa pasa a ser
    P(entrar en mora como TEMPRANA), aplicada a todo el calendario."""
    out = collections.defaultdict(lambda: [0.0, 0.0])
    for r in _leer(CT):
        if not _en_calendario(r, definicion, reeng, todas_las_cuotas=False):
            continue
        s = float(r["saldo"])
        out[r["periodo"]][0] += s
        if r["entra"] == "1" and not (arrastre == "fuera" and r["arrastre"] == "1"):
            out[r["periodo"]][1] += s
    return {p: tuple(v) for p, v in out.items()}


def tasa(tm, desde, hasta):
    e = sum(v[0] for p, v in tm.items() if desde <= p <= hasta)
    n = sum(v[1] for p, v in tm.items() if desde <= p <= hasta)
    return n / e


def ventana(periodo, meses=12):
    """[M-meses, M-1] como ('YYYYMM', 'YYYYMM'). Nunca ve el mes M."""
    y, m = int(periodo[:4]), int(periodo[4:])
    fin_y, fin_m = (y, m - 1) if m > 1 else (y - 1, 12)
    ini = fin_y * 12 + (fin_m - 1) - (meses - 1)
    return f"{ini // 12:04d}{ini % 12 + 1:02d}", f"{fin_y:04d}{fin_m:02d}"

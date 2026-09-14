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
  reeng       False = fuera | True = incluidos marcados (bug 25; la produccion los
              incluye desde el 2026-09-13, motor_v2.REENG)
  ancla       solo calendario y tasa (bug 28): False = saldo al vencimiento | True =
              saldo en la ultima foto del mes anterior, el que la meta conoce el dia 1
              (la produccion calibra asi la tasa desde el 2026-09-13, motor_v2.TASA_ANCLADA)
"""
import collections
import csv
import datetime as dt

# Matrices VIGENTES. Al extenderlas en el ciclo mensual, actualizar la ruta y, para la de
# nuevos, hasta que dia llegan sus fotos: una cohorte necesita 31 dias de seguimiento, y
# `motor_v2.curvas` se niega a calibrar una ventana que la matriz no cubre.
MS = "datos_tarea24/v2_matriz_stock.csv"
MN = "datos_tarea24/v2_matriz_nuevos.csv"
FOTOS_NUEVOS_HASTA = "20260901"
# Calendario y tasa con el saldo anclado (tarea25_calendario_tasa.sql). Completa hasta
# CALENDARIO_HASTA; trae ademas 202609 PARCIAL (entradas hasta el 12-sep) para validar
# septiembre, y `tasa` se niega a calibrar con un periodo posterior a CALENDARIO_HASTA.
CT = "datos_tarea25/v2_calendario_tasa.csv"
CALENDARIO_HASTA = "202608"

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
def _en_calendario(r, definicion, reeng, todas_las_cuotas, ancla=False):
    if not reeng and r["reeng"] == "1":
        return False
    if ancla and r["tiene_ancla"] != "1":
        return False
    if definicion == "v1":
        return r["st_v1"] == "0" and (todas_las_cuotas or r["orden"] == "1")
    return r["st_v2"] == "0" and r["orden_d2"] == "1"


def calendario(definicion, periodo, reeng=False, todas_las_cuotas=False, ancla=False):
    """{dia_entrada: {avance_band: saldo}} para el backtest.

    ancla False: saldo al VENCIMIENTO y banda con ese saldo (el calendario medido,
                 el de todos los backtests hasta tarea 24).
          True:  saldo en la ULTIMA FOTO DEL MES ANTERIOR y banda con ese saldo, solo
                 los que la tienen con saldo > 0 -- el calendario que la meta conoce el
                 dia 1 (bug 28).
    todas_las_cuotas (solo v1): True = como calendario_8m, sumando las dos
    cuotas del credito que entra el dia 1 y el 31 (asi se publico, bug 23);
    False = una cuota por credito, la misma base que la tasa. En v2 no hace
    falta: la cuota que entra el dia 1 no es calendario, queda una sola."""
    col, banda = ("saldo_ancla", "avance_band_anc") if ancla else ("saldo", "avance_band")
    cal = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in _leer(CT):
        if r["periodo"] == periodo and _en_calendario(r, definicion, reeng, todas_las_cuotas, ancla):
            cal[int(r["dia_entrada"])][r[banda]] += float(r[col])
    return {d: dict(v) for d, v in cal.items()}


def tasa_mensual(definicion, arrastre="fuera", reeng=False, ancla=False, dias=None):
    """{periodo: (elegibles_soles, entran_soles)}. Con arrastre='fuera' el
    numerador cuenta solo a los que entran SIN arrastre: la tasa pasa a ser
    P(entrar en mora como TEMPRANA), aplicada a todo el calendario.

    ancla True (bug 28): elegibles = saldo ANCLADO (ultima foto del mes anterior),
    el que la meta multiplica por la tasa; entran = el mismo saldo de entrada de
    siempre, a lo que se aplica la curva. Los dos sobre la poblacion que la meta ve
    el dia 1 (tiene_ancla = 1).
    dias (desde, hasta): solo las cuotas con entrada en esos dias del mes (diagnostico,
    para comparar un mes en curso con los mismos dias de los anteriores)."""
    out = collections.defaultdict(lambda: [0.0, 0.0])
    for r in _leer(CT):
        if dias and not dias[0] <= int(r["dia_entrada"]) <= dias[1]:
            continue
        if not _en_calendario(r, definicion, reeng, todas_las_cuotas=False, ancla=ancla):
            continue
        s = float(r["saldo"])
        out[r["periodo"]][0] += float(r["saldo_ancla"]) if ancla else s
        if r["entra"] == "1" and not (arrastre == "fuera" and r["arrastre"] == "1"):
            out[r["periodo"]][1] += s
    return {p: tuple(v) for p, v in out.items()}


def tasa(tm, desde, hasta):
    if hasta > CALENDARIO_HASTA:
        raise SystemExit(f"La matriz de calendario/tasa ({CT}) esta completa hasta {CALENDARIO_HASTA} "
                         f"y la ventana pide hasta {hasta}. Extenderla un periodo (PENDIENTES tarea 25).")
    e = sum(v[0] for p, v in tm.items() if desde <= p <= hasta)
    n = sum(v[1] for p, v in tm.items() if desde <= p <= hasta)
    return n / e


def ventana(periodo, meses=12):
    """[M-meses, M-1] como ('YYYYMM', 'YYYYMM'). Nunca ve el mes M."""
    y, m = int(periodo[:4]), int(periodo[4:])
    fin_y, fin_m = (y, m - 1) if m > 1 else (y - 1, 12)
    ini = fin_y * 12 + (fin_m - 1) - (meses - 1)
    return f"{ini // 12:04d}{ini % 12 + 1:02d}", f"{fin_y:04d}{fin_m:02d}"

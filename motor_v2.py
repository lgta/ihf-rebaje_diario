"""
MOTOR v2 -- ADOPTADO 2026-09-13 (decision del usuario, tarea 24). Primera meta: OCTUBRE 2026.

Antiguo = en mora 1-30 EL DIA 1 del mes, la definicion de vw_seguimiento_diario_cohorte_tramo
(cuadre de septiembre contra la vista: +0.5%). Reemplaza al motor unificado v3
(`motor_unificado.py` + `meta_septiembre_*.py`), que queda como registro de la meta de
septiembre. Reusa de `motor_unificado.py` solo el proyector (`proyectar`), que no cambio.

Reglas de produccion (DECISIONES.md, 2026-09-13):
  stock       dias_atraso_cuota 1-30 el dia 1, saldo de la ultima foto del mes anterior, tramo
              por la mora del dia 1. Curva con ventana FIJA 202504-202606 y factor de cierre real.
  cohorte d1  los que entran en mora el mismo dia 1 (0-53% del stock segun el mes, siguen a las
              cuotas que vencen el 30): se proyectan con la curva de NUEVOS (banda x dia de
              semana del vencimiento, factor por dia del mes) sobre su saldo real, sin tasa --
              variante S2, la que gano en metricas diarias (backtest_tarea24_v1_v2.py).
  nuevos      calendario desde el dia 2, una cuota por credito (la primera con entrada desde el
              dia 2), sin el stock del mes, con el saldo de la ultima foto del mes anterior; tasa
              por SOLES sobre esa misma poblacion y con ese mismo saldo ANCLADO como denominador
              (TASA_ANCLADA, bug 28); curva por banda x dia de semana con factor de quincena y fin
              de mes. Curva y tasa ruedan [M-13, M-2]: 12 meses hasta el ultimo mes completamente
              observado el dia 1.
  arrastre    FUERA: el credito cuyo DNI tiene otro con mas de 30 dias se cobra en ESPECIALIZADA,
              como en la vista. Se marca (flg_arrastre_dni), no se borra.
  reenganches INCLUIDOS en la calibracion (REENG, bug 25): los creditos que despues tuvieron un
              reenganche son parte de la historia de cada mes; el salto de saldo del dia del
              reenganche no cuenta como pago.
REENG y TASA_ANCLADA son decisiones del usuario del 2026-09-13 (noche). En False reproducen el motor
como se valido esa tarde (backtest_tarea24_v1_v2.py; meta de septiembre al 1-sep S/19,814,433).

Los dos enfoques comparten todo menos la medida: 'act' (capital asegurado, activacion) o
'reb' (recupero oficial, rebaje). Las curvas salen de las matrices de `curvas_v2.py`.
"""
import calendar
import collections
import csv
import datetime as dt

import curvas_crudas as CC
import curvas_crudas_stock as CS
import curvas_v2 as V
from motor_unificado import dow_venc, proyectar, segmentar_calendario

FIJA_STOCK = ("202504", "202606")
MODO_D1 = "S2"
ARRASTRE = "fuera"
REENG = True           # decision del usuario 2026-09-13 (bug 25)
TASA_ANCLADA = True    # decision del usuario 2026-09-13 (bug 28)

_insumos = {}


def dias_del_mes(periodo):
    return calendar.monthrange(int(periodo[:4]), int(periodo[4:]))[1]


def ventana_meta(periodo):
    """[M-13, M-2]: los 12 meses que terminan en el ultimo mes COMPLETAMENTE observado el dia 1
    de M -- una cohorte necesita 31 dias de seguimiento (CLAUDE.md). Para septiembre 2026 da
    [202508, 202607], la de la meta publicada. OJO: el backtest usa [M-12, M-1]
    (`curvas_v2.ventana`), que no es prospectivo."""
    y, m = int(periodo[:4]), int(periodo[4:])
    return V.ventana(f"{y:04d}{m - 1:02d}" if m > 1 else f"{y - 1:04d}12")


def _exigir_seguimiento(ventana):
    """La ultima cohorte de la ventana necesita 31 dias de fotos. Si la matriz de nuevos no
    llega, calibrar daria una curva truncada (mas baja) sin avisar."""
    fin = ventana[1]
    hace_falta = dt.date(int(fin[:4]), int(fin[4:]), dias_del_mes(fin)) + dt.timedelta(days=31)
    if hace_falta.strftime("%Y%m%d") > V.FOTOS_NUEVOS_HASTA:
        raise SystemExit(
            f"La matriz de nuevos ({V.MN}) tiene fotos hasta {V.FOTOS_NUEVOS_HASTA} y la ventana "
            f"{ventana[0]}-{ventana[1]} necesita hasta {hace_falta:%Y%m%d}. Re-correr la matriz de "
            f"nuevos con las fotos corridas y actualizar curvas_v2.MN / FOTOS_NUEVOS_HASTA.")


def curvas(periodo, medida, definicion="v2", modo=MODO_D1, arrastre=ARRASTRE, reeng=REENG,
           ancla=TASA_ANCLADA):
    """Curvas y tasa para la meta de `periodo`: nuevos (curva y tasa) en `ventana_meta`, stock en
    FIJA_STOCK. En S2 la curva de stock se calibra sin la cohorte d1. Con `ancla` la tasa divide
    por el saldo de la ultima foto del mes anterior -- el mismo con el que la meta arma el
    calendario (bug 28) --; sin `ancla`, por el saldo al vencimiento."""
    ventana = ventana_meta(periodo)
    _exigir_seguimiento(ventana)
    base_s, acts_s = V.stock_matriz(definicion, medida, arrastre, reeng, seg_d1=(modo == "S1"),
                                    solo_d1=(False if modo == "S2" else None))
    curva_s, f_s = CS.calibrar(base_s, acts_s, *FIJA_STOCK, con_f=True, modo_cierre="real")
    base_n, acts_n = V.nuevos_matriz(definicion, medida, arrastre, reeng)
    curva_n, f_n = CC.calibrar(base_n, acts_n, *ventana, con_dow=True, con_f=True,
                               granularidad="estructural")
    p = V.tasa(V.tasa_mensual(definicion, arrastre, reeng, ancla=ancla), *ventana)
    return curva_s, f_s, curva_n, f_n, p


def proyectar_mes(c, periodo, stock, cal, d1_por_banda=None):
    """Serie diaria del mes con las curvas `c` de `curvas()`. `d1_por_banda` es la cohorte que
    entro en mora el dia 1 (S2): curva de NUEVOS sobre su saldo real, sin tasa, sumada al stock."""
    curva_s, f_s, curva_n, f_n, p = c
    n = dias_del_mes(periodo)
    filas = proyectar(stock, segmentar_calendario(cal, periodo), curva_s, curva_n, n,
                      p_entrada=p, f_dm=f_n, f_dm_stock=f_s)
    if d1_por_banda:
        dw = dow_venc(periodo, 1)
        extra = proyectar({}, {1: {(b, dw): s for b, s in d1_por_banda.items()}}, {}, curva_n, n,
                          p_entrada=1.0, f_dm=f_n)
        for fila, e in zip(filas, extra):
            fila["proy_stock"] += e["proy_nuevos"]
            fila["proy_total"] += e["proy_nuevos"]
    return filas


def por_banda(stock):
    """{(tramo, banda): saldo} -> {banda: saldo}."""
    out = collections.defaultdict(float)
    for (_t, b), s in stock.items():
        out[b] += s
    return dict(out)


def leer_insumos(path, definicion="v2", arrastre=ARRASTRE, reeng=REENG, seg_d1=False, solo_d1=None):
    """Insumos del mes desde la salida de la query de insumos (`tarea24_v2_septiembre_al_1.sql`
    y sus sucesoras): ({(tramo, banda): saldo}, {dia_entrada: {banda: saldo}}).

    Universo del dia 1: con reeng=False entra quien tiene reeng = 0 o refin_post = 1 -- el que
    tuvo su reenganche despues del dia 1 todavia era el ultimo de su cadena ese dia."""
    if path not in _insumos:
        with open(path) as f:
            _insumos[path] = list(csv.DictReader(f))
    stock = collections.defaultdict(float)
    cal = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in _insumos[path]:
        if r.get("bloque", "insumo") != "insumo" or r["definicion"] != definicion:
            continue
        if not reeng and r["reeng"] == "1" and r.get("refin_post", "0") == "0":
            continue
        if r["componente"] == "stock":
            if arrastre == "fuera" and r["arrastre"] == "1":
                continue
            if solo_d1 is not None and (r["d1"] == "1") != solo_d1:
                continue
            tramo = V.TRAMO_D1 if (seg_d1 and r["d1"] == "1") else r["tramo"]
            stock[(tramo, r["avance_band"])] += float(r["saldo"])
        else:
            cal[int(r["dia"])][r["avance_band"]] += float(r["saldo"])
    return dict(stock), {d: dict(v) for d, v in cal.items()}


def meta(periodo, medida, insumos, definicion="v2", modo=MODO_D1, arrastre=ARRASTRE, reeng=REENG,
         ancla=TASA_ANCLADA):
    """(serie diaria, tasa) de la meta del mes."""
    c = curvas(periodo, medida, definicion, modo, arrastre, reeng, ancla)
    stock, cal = leer_insumos(insumos, definicion, arrastre, reeng, seg_d1=(modo == "S1"),
                              solo_d1=(False if modo == "S2" else None))
    d1 = None
    if modo == "S2":
        d1 = por_banda(leer_insumos(insumos, definicion, arrastre, reeng, solo_d1=True)[0])
    return proyectar_mes(c, periodo, stock, cal, d1), c[4]

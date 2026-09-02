"""
Construccion de curvas de "nuevos" desde la MATRIZ CRUDA
(`tarea18f_curva_cruda.sql` -> `datos_tarea18a/curva_cruda.csv`).

La matriz cruda tiene el grano minimo -- (fecha_entrada, avance_band,
dia_primer_pago) -> saldo -- asi que desde aca se arma CUALQUIER curva sin
volver a consultar Athena:

  - por avance_band                        (= la curva de produccion)
  - x dia de semana del vencimiento        (= tarea 18a, V4)
  - con factor por dia del mes DE PAGO     (= tarea 18f)
  - sobre cualquier VENTANA RODANTE        (filtrando fecha_entrada)

Esa ultima propiedad es la que hace barato el walk-forward: recalibrar
[M-12, M-1] para cada mes de test cuesta 0 corridas adicionales.

VALIDACION (correr `python curvas_crudas.py`): reconstruida sobre la
ventana de produccion (20250301-20260531), la curva sale a 0.03pp de
`datos_tarea17_fase4/curva_nuevos.csv` en dia 0 y dia 30, y el
denominador a 0.04%. La diferencia residual es un fix propio: la Q-B de
produccion agrupa `primer_pago` por (id_loan, avance_band, saldo_entrada)
y por eso COLAPSA los casos en que un mismo credito entra en mora dos
veces con la misma banda y el mismo saldo. Aca `fecha_entrada` viaja en
el grano, asi que cada episodio cuenta como la cohorte distinta que es.
Impacto medido: 0.01-0.04% del saldo, 0.09pp en el dia 30. No amerita
re-publicar nada, pero queda anotado.

18f -- EL FACTOR POR DIA DEL MES. El modelo es multiplicativo sobre el
INCREMENTO diario (no sobre el acumulado):

    activacion(E, b, k) = base(E, b) x p(k | b, dow) x f(dia_del_mes(E + k))

donde E es la fecha de entrada y k los dias desde la entrada. La curva
indexada por k es ciega a en que parte del mes esta cobrando: la cohorte
que entro el 2 cruza la quincena en su dia 13 y la que entro el 14 en su
dia 1. `f` es lo que recupera esa dimension.

Se ajusta por IPF (dos factores multiplicativos, alternando) y se
normaliza a media ponderada 1, asi que REDISTRIBUYE masa dentro del mes
en vez de agregarla: el total de 31 dias de la cohorte queda intacto,
que es lo que `P_ENTRADA x curva` significa.

`f` se calibra SOLO sobre la ventana historica, nunca contra el residuo
del backtest -- eso seria el ajuste ex-post que `CLAUDE.md` prohibe. Los
meses de test sirven para ver si `f` se sostiene fuera de muestra, no
para construirlo.
"""
import csv
import collections
import datetime as dt

RAW = "datos_tarea18a/curva_cruda.csv"


def _fecha(s):
    return dt.date(int(s[:4]), int(s[4:6]), int(s[6:8]))


def cargar_matriz(path=RAW):
    """(base, activaciones) al grano (fecha_entrada, banda).

    base : {(fecha date, banda): saldo de la cohorte}
    acts : {(fecha date, banda): {k: saldo activado ese k}}
    """
    base, acts = {}, collections.defaultdict(dict)
    for r in csv.DictReader(open(path)):
        f = _fecha(r["fecha_entrada"])
        b, s = r["avance_band"], float(r["saldo"])
        if r["tipo"] == "base":
            base[(f, b)] = base.get((f, b), 0.0) + s
        else:
            acts[(f, b)][int(r["dia"])] = acts[(f, b)].get(int(r["dia"]), 0.0) + s
    return base, dict(acts)


K_MAX = 31

# Agrupacion ESTRUCTURAL del dia del mes. No es una eleccion libre: son
# los dias de pago de planilla en Peru (quincena y fin de mes), y son los
# unicos que se REPRODUCEN al calibrar en dos mitades disjuntas de la
# ventana -- dia 15: 1.140 / 1.195; dias 30-31: 1.18-1.20 en ambas. El
# resto de los dias correlaciona solo +0.51 entre mitades, o sea un `f`
# con un parametro por dia estaria ajustando ruido.
#
# El dia 29 NO entra: sale bajo (0.959 / 0.953) en las dos mitades, asi
# que esto no es "los ultimos dias del mes" sino la FECHA de pago -- el
# 30 y el 31 como numero de dia, no como posicion relativa al cierre.
#
# CORRECCION 2026-08-26 (tarea 18b/18g, repregunta del usuario): esta
# lectura de "dia 29 bajo => es fecha fija, no cercania a cierre" resulto
# ser un artefacto de que dia 29 CASI NUNCA es el ultimo dia real del mes
# en la ventana (no hay febrero bisiesto en 20250101-20260630) -- nunca es
# el caso que se queria medir. Reagrupando por DIAS-PARA-FIN-DE-MES real
# (granularidad="real" abajo) en vez de numero de dia fijo, sobre toda la
# ventana: dpf=0 (ultimo dia real, sea 28/30/31) da 4.536% de tasa de
# activacion contra 2.786% de baseline (+63%); dpf=1 (penultimo) da 2.827%,
# practicamente en baseline. El efecto es un pico angosto en el CIERRE
# REAL, no en el numero de dia 30/31 -- ver `analisis_sesgo_nuevos_18b.md`.
GRUPOS_DM = {15: "quincena", 16: "quincena", 30: "fin de mes", 31: "fin de mes"}


def _dias_en_mes(fecha):
    import calendar as _cal
    return _cal.monthrange(fecha.year, fecha.month)[1]


def _grupo_dm(dm, granularidad):
    """dm: NUMERO de dia del mes -- compatibilidad con llamadas existentes
    (`motor_unificado.grupo_dia_mes`, `backtest_tarea18f.proyectar_f`), que
    llaman esto durante la PROYECCION, donde `dm` ya es el dia que se esta
    proyectando dentro de un mes de largo conocido y no hace falta la fecha
    completa para el esquema fijo. Para "real" hace falta la fecha entera
    (para saber cuantos dias tiene ESE mes) -- ver `_grupo_dm_real`."""
    if granularidad == "dia":
        return dm
    return GRUPOS_DM.get(dm, "resto")


def _grupo_dm_real(fecha_pago):
    """granularidad="real" (18g): el grupo depende de si `fecha_pago` es el
    ULTIMO DIA REAL de SU mes, no de un numero de dia fijo -- por eso, a
    diferencia de `_grupo_dm`, esta si necesita la fecha completa."""
    dm = fecha_pago.day
    if dm in (15, 16):
        return "quincena"
    return "cierre" if dm == _dias_en_mes(fecha_pago) else "resto"


def calibrar(base, acts, desde, hasta, con_dow=True, con_f=False,
             granularidad="estructural", iteraciones=6):
    """Devuelve (curva_acumulada, f_por_dia_del_mes).

    curva: clave -> {k: % acumulado}. La clave es (banda, dow_venc) si
    con_dow, si no `banda` -- las mismas claves que espera
    `motor_unificado.proyectar`.
    f: {grupo_de_dia_del_mes: factor}, todo 1.0 si con_f=False.
    granularidad="estructural" (produccion, W3): "quincena"/"fin de mes"
    (dia calendario 30/31 fijo)/"resto". "real" (18g): "quincena"/"cierre"
    (el ultimo dia REAL de cada mes, sea 28/29/30/31)/"resto". "dia": el
    numero de dia (31 parametros, sobreajusta -- ver el comentario de
    GRUPOS_DM).

    OJO CON EL DENOMINADOR: para cada (clave, k) el denominador es el
    saldo de TODAS las cohortes de esa clave en la ventana, activen o no
    en ese k -- igual que `saldo_entrada_total` en la Q-B de produccion.
    Sumar solo las cohortes con activacion infla la curva por encima de
    100% (se vio en la primera version de este archivo).
    """
    cohortes = [(f, b, (f - dt.timedelta(days=1)).weekday() + 1, s)
                for (f, b), s in base.items()
                if desde <= f.strftime("%Y%m") <= hasta]
    clave = (lambda b, dw: (b, dw)) if con_dow else (lambda b, dw: b)

    # celda = (clave, k, grupo_dia_del_mes_de_pago, observado, expuesto)
    celdas = []
    for f, b, dw, s in cohortes:
        kl, a = clave(b, dw), acts.get((f, b), {})
        for k in range(0, K_MAX + 1):
            fecha_pago = f + dt.timedelta(days=k)
            grupo = (_grupo_dm_real(fecha_pago) if granularidad == "real"
                     else _grupo_dm(fecha_pago.day, granularidad))
            celdas.append((kl, k, grupo, a.get(k, 0.0), s))

    f_dm = collections.defaultdict(lambda: 1.0)
    p = {}
    for _ in range(iteraciones if con_f else 1):
        num_p, den_p = collections.defaultdict(float), collections.defaultdict(float)
        for kl, k, dm, obs, expo in celdas:
            num_p[(kl, k)] += obs
            den_p[(kl, k)] += expo * f_dm[dm]
        p = {kk: num_p[kk] / den_p[kk] for kk in num_p if den_p[kk] > 0}
        if not con_f:
            break
        num_f, den_f = collections.defaultdict(float), collections.defaultdict(float)
        for kl, k, dm, obs, expo in celdas:
            num_f[dm] += obs
            den_f[dm] += expo * p.get((kl, k), 0.0)
        bruto = {dm: num_f[dm] / den_f[dm] for dm in num_f if den_f[dm] > 0}
        media = (sum(bruto[dm] * den_f[dm] for dm in bruto)
                 / sum(den_f[dm] for dm in bruto))
        f_dm = collections.defaultdict(lambda: 1.0,
                                       {dm: v / media for dm, v in bruto.items()})

    curva = collections.defaultdict(dict)
    for (kl, k), v in p.items():
        curva[kl][k] = 100.0 * v
    for kl in curva:                              # incremento -> acumulado
        ac = 0.0
        for k in sorted(curva[kl]):
            ac += curva[kl][k]
            curva[kl][k] = ac
    return dict(curva), dict(f_dm)


if __name__ == "__main__":
    from motor_unificado import lookup
    base, acts = cargar_matriz()
    print("VALIDACION contra la curva de produccion (ventana 20250301-20260531)\n")
    curva, _ = calibrar(base, acts, "202503", "202605", con_dow=False)
    prod, pden = collections.defaultdict(dict), {}
    for r in csv.DictReader(open("datos_tarea17_fase4/curva_nuevos.csv")):
        prod[r["avance_band"]][int(r["dia"])] = float(r["pct_capital_asegurado_acum"])
        pden[r["avance_band"]] = float(r["saldo_entrada_total"])
    print(f"{'banda':<18} {'d0 crudo':>9} {'d0 prod':>9} {'d30 crudo':>10} {'d30 prod':>10}")
    for b in sorted(prod):
        print(f"{b:<18} {lookup(curva[b], 0, True):>8.3f}% {prod[b][0]:>8.3f}% "
              f"{lookup(curva[b], 30, True):>9.3f}% {lookup(prod[b], 30):>9.3f}%")

    print("\nFACTOR f POR DIA DEL MES DE PAGO (ventana de produccion, con dow)")
    _, f_dm = calibrar(base, acts, "202503", "202605", con_dow=True, con_f=True)
    for blk in range(0, 31, 10):
        dias = [d for d in range(blk + 1, min(blk + 11, 32))]
        print("  dia  " + " ".join(f"{d:>6}" for d in dias))
        print("  f    " + " ".join(f"{f_dm.get(d, 1.0):>6.3f}" for d in dias))

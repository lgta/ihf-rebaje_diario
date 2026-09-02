"""
MOTOR UNIFICADO del Enfoque alfa ("capital asegurado") -- tarea 17 Fase 4,
adoptado en produccion 2026-08-25 a pedido del usuario.

v3 (2026-08-26 continuacion, tarea 18g, adoptada a pedido del usuario).
FACTOR DE CIERRE REAL PARA STOCK: `proyectar()` acepta un nuevo parametro
opcional `f_dm_stock` que multiplica el INCREMENTO DIARIO de stock, igual
mecanismo que `f_dm` ya hacia para nuevos desde 18f pero con un grupo
distinto -- "cierre" es el ULTIMO DIA REAL del mes que se esta
proyectando (`d == n_dias`), no un numero de dia fijo. Motivo (ver
`analisis_sesgo_nuevos_18b.md` y `analisis_tarea18g_cierre_real.md`):
reagrupando la activacion por dias-para-fin-de-mes real en vez de dia
calendario fijo, el pico de pago vive SOLO en el ultimo dia real (+63%
sobre baseline en nuevos, medido en 20250101-20260630) -- por eso febrero
(el unico mes de 28 dias del backtest) es tambien el unico mes donde
STOCK falla fuerte: su cierre real (dia 28) nunca caia en el grupo
"fin de mes" (dias 30/31 fijos). Walk-forward de 7 meses
(`backtest_tarea18g.py`): correlacion diaria de stock 0.841->0.848, MAE
27.3K->26.7K; en febrero especificamente, error de stock -11.0%->-8.3% y
correlacion 0.818->0.856 (mejora real, no resuelve el mes del todo).
Probar ADEMAS rodar la ventana de calibracion de stock (que cerraria
tarea 18c) EMPEORA las metricas diarias (corr. 0.848->0.820) -- se
prueba pero NO se adopta; stock sigue con ventana FIJA 202504-202606
(la misma de siempre), tarea 18c queda abierta.

**El reindex analogo para NUEVOS (18g) se documenta pero NO se adopta en
esta pasada** -- su impacto medido es marginal (corr. 0.886->0.888,
practicamente ruido, el grupo fijo {30,31} ya capturaba casi toda la
senal) y cambiar el esquema de agrupacion compartido de nuevos tocaria
tambien el calculo ya publicado de la meta de agosto. Se deja para una
pasada separada, deliberada, cuando no haya un mes en curso que proteger.

**La meta de agosto vigente (`meta_agosto_capital_asegurado.py`,
`datos_capital_asegurado/curva_unificada_stock_seg.csv`,
`curva_unificada_nuevos_dow_seg.csv`, `factor_dia_mes.csv`) NO se toca --
sigue leyendo exactamente los mismos archivos que ya tenia.** La curva de
stock v3 (con el factor de cierre) se escribe aparte, en
`curva_unificada_stock_seg_v3.csv` + `factor_dia_mes_stock.csv`, y solo
el backtest oficial y la futura meta de septiembre la usan.

v2 (2026-08-26, tarea 18a + 18f, variante W3, adoptada a pedido del
usuario). Dos refinamientos de la curva de NUEVOS, decididos con un
walk-forward de 7 meses y calibracion rodante de 12 meses sin leak
(`backtest_tarea18f.py`):

  A. La curva se segmenta ademas por el DIA DE LA SEMANA DEL VENCIMIENTO,
     abierto a los 6 dias que existen -- ninguna cuota vence domingo, ver
     BUGS.md bug 21. El dia 0 de la curva va de 18.7% (venc. sabado, que
     entra domingo) a 42.0% (venc. martes, que entra miercoles); antes se
     le aplicaba a TODOS los dias el promedio ponderado, 34.3%, que no
     corresponde a ninguno.

  B. Un FACTOR MULTIPLICATIVO POR DIA DEL MES sobre el incremento diario:
     quincena (15-16) y dias 30-31 cobran mas que el resto. Son 2
     parametros, no 31 -- con uno por dia sobreajusta (correlacion entre
     mitades disjuntas de la ventana: solo +0.51). Se normaliza a media
     ponderada 1, asi que REDISTRIBUYE masa dentro del mes en vez de
     agregarla.

Efecto medido en los 7 meses de test: la correlacion entre incrementos
diarios proyectados y reales sube de 0.611 a 0.886 y el error absoluto
medio del incremento diario cae 41% (S/124K -> S/73K), mejorando mes a
mes sin excepcion. El error de FIN DE MES casi no se mueve (10.43% ->
10.55%) y no es el arbitro de esta decision: la diferencia pareada entre
variantes tiene un desvio 10x mas grande que su media, o sea harian falta
~1,050 meses para resolverla. Ver PENDIENTES.md tareas 18a/18c/18f.

Las curvas se calibran desde la MATRIZ CRUDA (`curvas_crudas.py`), no
desde una query por segmentacion.

Reemplaza la arquitectura de 3 componentes (stock + nuevos + capa fantasma,
calibrada con `dayslate`) por 2 componentes calibrados con
`dts_cobranza_creditos_calendario_diario.dias_atraso_cuota`.

QUE CAMBIA (ver BUGS.md bug 16, Fase 4, para el detalle y los numeros):

  1. UNA tasa de entrada en vez de dos. P_ENTRADA = 21.9918%
     (75,621/343,860, ago25-may26) reemplaza a P_NO_PAGA_DIA0 = 13.38%
     (dayslate) + P_FANTASMA = 8.6163% (dias_atraso_cuota). La suma de las
     dos era 21.9963% -- 0.005pp de diferencia: la masa siempre estuvo
     bien, lo que estaba mal era el reparto.

  2. UNA curva de nuevos que arranca en el DIA 0. La ex-poblacion fantasma
     (la que entra en mora y se resuelve antes de que `dayslate` la vea)
     ES el dia 0 de esta curva, no un termino aditivo con tasa plana. La
     tasa plana era CIEGA a `avance_band`; la activacion real del dia 0 no
     lo es: 36.97% (avance <10%) a 30.61% (avance 70%+) del capital de
     entrada.

  3. UN calendario indexado por DIA DE ENTRADA (= fechavencimiento + 1) en
     vez de dos (el de nuevos por vencimiento + el de fantasma
     frontier-adjusted). El indice de la curva pasa a ser
     `d - dia_entrada`, sin correcciones.

  4. Stock SIN el parche `dia1_entrantes` de bug 12: esa cohorte entra por
     el calendario con dia_entrada = 1, que es lo que es. Al cierre del mes
     anterior tiene atraso 0, asi que no es stock -- sin solape ni hueco.

POR QUE ESTO ELIMINA 4 CLASES DE BUG POR CONSTRUCCION:
  - bug 12 (dia1_entrantes): ya no hace falta el parche.
  - bug 14/17 (hueco de frontera de mes): incluido en dia_entrada = 1.
  - bug 18 (indice de la curva corrido 1 dia): el indice no tiene offset.
  - bug 20 (denominador de abril inconsistente): solo existia porque habia
    dos calendarios que mantener sincronizados.

NOTA SOBRE EL ERROR DEL BACKTEST: el modelo unificado da un error ~1pp
PEOR que la arquitectura anterior (7.22% vs 6.20% de magnitud media, una
vez corregido bug 20). Se adopta igual, por el "Principio de interpretacion
del error" de CLAUDE.md: el cambio SI cambia quien entra al universo y como
se mide, asi que se corrige aunque el error suba -- mismo criterio con el
que se adopto bug 18. El parche plano estaba enmascarando el sesgo de
"nuevos" por ser sistematicamente generoso; el unificado lo deja expuesto,
con signo constante en los 4 meses (senal de negocio a explicar, no defecto
del modelo).
"""
import csv
import datetime as dt

# Tasa unificada de entrada a mora. tarea17_fase4_tasa.sql, ventana
# ago-2025 a may-2026 (la MISMA que usaba P_NO_PAGA_DIA0, para que el
# numero sea comparable). Sin deriva mensual: rango 20.39%-23.82%.
P_ENTRADA = 75621 / 343860  # 21.9918%

DIR_CURVAS = "datos_capital_asegurado"
AVANCES = ["a. avance <10%", "b. avance 10-40%", "c. avance 40-70%", "d. avance 70%+"]
TRAMOS = ["a. 1-8", "b. 9-15", "c. 16-30"]


def cargar_curva_stock(path=f"{DIR_CURVAS}/curva_unificada_stock_seg.csv"):
    """Curva de stock: (tramo, avance_band) -> {dia del mes: % acumulado}."""
    curva = {}
    with open(path) as f:
        for r in csv.DictReader(f):
            curva.setdefault((r["tramo"], r["avance_band"]), {})[int(r["dia"])] = float(
                r["pct_capital_asegurado_acum"])
    return curva


# Agrupacion del dia del mes para el factor de 18f. Son los dias de pago
# de planilla; el 29 NO entra (sale bajo en todas las ventanas medidas),
# asi que el efecto es de FECHA de pago, no de "ultimos dias del mes".
GRUPOS_DIA_MES = {15: "quincena", 16: "quincena", 30: "fin de mes", 31: "fin de mes"}


def grupo_dia_mes(d):
    return GRUPOS_DIA_MES.get(d, "resto")


def grupo_dia_mes_stock(d, n_dias):
    """Agrupacion de dia-del-mes PARA STOCK (v3, tarea 18g) -- "cierre" es
    el ULTIMO DIA REAL del mes que se esta proyectando (`d == n_dias`), no
    un numero de dia fijo como `grupo_dia_mes`. En una proyeccion `n_dias`
    ya es el largo real del mes, asi que no hace falta calendario: el
    chequeo es un entero contra otro. Ver `analisis_sesgo_nuevos_18b.md`
    seccion 2 para por que esto, y no {30,31} fijo, es lo que corresponde.
    """
    if d in (15, 16):
        return "quincena"
    if d == n_dias:
        return "cierre"
    return "resto"


def dow_venc(periodo, dia_entrada):
    """Dia de la semana del VENCIMIENTO, 1=lunes .. 7=domingo (como Presto).

    El calendario se indexa por dia de ENTRADA y la entrada es siempre
    vencimiento + 1, asi que el dia de semana sale de la fecha sin
    consultar nada. Verificado: reproduce exacto el mix mensual medido en
    BUGS.md bug 16 Fase 4 (30.1 / 36.5 / 27.0 / 23.3%).
    """
    f = dt.date(int(periodo[:4]), int(periodo[4:]), dia_entrada)
    return (f - dt.timedelta(days=1)).weekday() + 1


def segmentar_calendario(calendario, periodo):
    """{dia_entrada: {banda: saldo}} -> {dia_entrada: {(banda, dow): saldo}}.

    Las claves resultantes son las que usa la curva de nuevos de v2.
    """
    return {de: {(b, dow_venc(periodo, de)): s for b, s in porbanda.items()}
            for de, porbanda in calendario.items()}


def cargar_curva_nuevos(path=f"{DIR_CURVAS}/curva_unificada_nuevos_dow_seg.csv"):
    """Curva de nuevos v2: (avance_band, dow_venc) -> {dias desde entrada: % acum}.

    OJO: esta curva esta definida DESDE EL DIA 0 (el dia de entrada mismo).
    El dia 0 no es cero -- va de 18.7% (venc. sabado) a 42.0% (venc. martes)
    segun banda y dia de semana, y es exactamente la poblacion que antes
    modelaba la capa fantasma con una tasa plana.

    La version v1 sin dia de semana queda en curva_unificada_nuevos_seg.csv
    como referencia historica.
    """
    curva = {}
    with open(path) as f:
        for r in csv.DictReader(f):
            k = (r["avance_band"], int(r["dow_venc"]))
            curva.setdefault(k, {})[int(r["dia"])] = float(r["pct_capital_asegurado_acum"])
    return curva


def cargar_factor_dia_mes(path=f"{DIR_CURVAS}/factor_dia_mes.csv"):
    """{grupo: factor} de 18f. Normalizado a media ponderada 1."""
    with open(path) as f:
        return {r["grupo"]: float(r["factor"]) for r in csv.DictReader(f)}


def cargar_factor_dia_mes_stock(path=f"{DIR_CURVAS}/factor_dia_mes_stock.csv"):
    """{grupo: factor} de stock (v3, tarea 18g) -- "quincena"/"cierre"/
    "resto", ver `grupo_dia_mes_stock`. Normalizado a media ponderada 1."""
    with open(path) as f:
        return {r["grupo"]: float(r["factor"]) for r in csv.DictReader(f)}


def lookup(curva, d, desde_dia0=False):
    """% acumulado de la curva en el dia d (escalon: usa el ultimo dia <= d).

    desde_dia0=True para la curva de NUEVOS (definida desde el dia 0).
    desde_dia0=False para la de STOCK (definida desde el dia 1 del mes).
    """
    minimo = 0 if desde_dia0 else 1
    if d < minimo or not curva:
        return 0.0
    if d in curva:
        return curva[d]
    keys = [k for k in curva if k <= d]
    return curva[max(keys)] if keys else 0.0


def _incrementos(curva):
    """Curva acumulada -> incremento por dia. Sumar los incrementos hasta d
    da exactamente `lookup(curva, d)`, tambien con dias faltantes."""
    inc, prev = {}, 0.0
    for k in sorted(curva):
        inc[k] = curva[k] - prev
        prev = curva[k]
    return inc


def proyectar(stock, calendario, curva_stock, curva_nuevos, n_dias,
              p_entrada=P_ENTRADA, f_dm=None, f_dm_stock=None):
    """Serie diaria acumulada de capital asegurado proyectado.

    stock       : {(tramo, avance_band): saldo} al cierre del mes anterior.
    calendario  : {dia_entrada: {seg: saldo_en_riesgo}}, con `seg` la misma
                  clave que usa `curva_nuevos` -- (avance_band, dow_venc) en
                  v2, ver `segmentar_calendario`.
                  dia_entrada = day(fechavencimiento + 1 dia), de 1 a n_dias.
    f_dm        : {grupo_de_dia_del_mes: factor}, de `cargar_factor_dia_mes`.
                  None = todos 1.0, que reproduce v1 al centimo.
    f_dm_stock  : {grupo_de_dia_del_mes: factor} PARA STOCK (v3, tarea 18g),
                  de `cargar_factor_dia_mes_stock`. None = todos 1.0, que
                  reproduce v2 al centimo (backward compatible).

    Los dos factores se aplican al INCREMENTO del dia, no al acumulado. En
    una proyeccion el dia del mes DEL PAGO es simplemente `d` -- todo lo
    que se proyecta cae dentro del mes -- asi que no hace falta arrastrar
    la fecha de entrada de cada cohorte. `f_dm` usa `grupo_dia_mes` (dia
    fijo 30/31); `f_dm_stock` usa `grupo_dia_mes_stock` (cierre = ultimo
    dia REAL de este mes, `d == n_dias`) -- son grupos distintos a
    proposito, ver el docstring del modulo.

    Devuelve [{dia, proy_stock, proy_nuevos, proy_total}, ...].
    """
    f_dm = f_dm or {}
    inc_nuevos = {seg: _incrementos(c) for seg, c in curva_nuevos.items()}
    inc_stock = {
        seg: _incrementos({d: lookup(curva_stock.get(seg, {}), d) for d in range(1, n_dias + 1)})
        for seg in stock
    }
    filas, acum_nuevos, acum_stock = [], 0.0, 0.0
    for d in range(1, n_dias + 1):
        fac = f_dm.get(grupo_dia_mes(d), 1.0)
        for dia_entrada in range(1, d + 1):
            for seg, saldo in calendario.get(dia_entrada, {}).items():
                pct = inc_nuevos.get(seg, {}).get(d - dia_entrada, 0.0)
                acum_nuevos += saldo * p_entrada * pct / 100.0 * fac

        fac_stock = f_dm_stock.get(grupo_dia_mes_stock(d, n_dias), 1.0) if f_dm_stock else 1.0
        acum_stock += sum(
            stock[seg] * inc_stock[seg].get(d, 0.0) / 100.0 * fac_stock
            for seg in stock
        )

        filas.append({
            "dia": d,
            "proy_stock": acum_stock,
            "proy_nuevos": acum_nuevos,
            "proy_total": acum_stock + acum_nuevos,
        })
    return filas


def acumular_real(por_dia, n_dias):
    """{dia: saldo activado ese dia} -> lista acumulada de largo n_dias."""
    acum, total = [], 0.0
    for d in range(1, n_dias + 1):
        total += por_dia.get(d, 0.0)
        acum.append(total)
    return acum

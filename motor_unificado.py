"""
MOTOR UNIFICADO del Enfoque alfa ("capital asegurado") -- tarea 17 Fase 4,
adoptado en produccion 2026-08-25 a pedido del usuario.

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


def cargar_curva_nuevos(path=f"{DIR_CURVAS}/curva_unificada_nuevos_seg.csv"):
    """Curva de nuevos: avance_band -> {dias desde la entrada: % acumulado}.

    OJO: esta curva esta definida DESDE EL DIA 0 (el dia de entrada mismo).
    El dia 0 no es cero -- es 30.6%-37.0% segun la banda, y es exactamente
    la poblacion que antes modelaba la capa fantasma con una tasa plana.
    """
    curva = {}
    with open(path) as f:
        for r in csv.DictReader(f):
            curva.setdefault(r["avance_band"], {})[int(r["dia"])] = float(
                r["pct_capital_asegurado_acum"])
    return curva


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


def proyectar(stock, calendario, curva_stock, curva_nuevos, n_dias, p_entrada=P_ENTRADA):
    """Serie diaria acumulada de capital asegurado proyectado.

    stock       : {(tramo, avance_band): saldo} al cierre del mes anterior.
    calendario  : {dia_entrada: {avance_band: saldo_en_riesgo}}.
                  dia_entrada = day(fechavencimiento + 1 dia), de 1 a n_dias.
    Devuelve [{dia, proy_stock, proy_nuevos, proy_total}, ...].
    """
    filas = []
    for d in range(1, n_dias + 1):
        proy_stock = sum(
            saldo * lookup(curva_stock.get(k, {}), d) / 100.0
            for k, saldo in stock.items()
        )
        proy_nuevos = 0.0
        for dia_entrada in range(1, d + 1):
            for avance, saldo in calendario.get(dia_entrada, {}).items():
                pct = lookup(curva_nuevos.get(avance, {}), d - dia_entrada, desde_dia0=True)
                proy_nuevos += saldo * p_entrada * pct / 100.0
        filas.append({
            "dia": d,
            "proy_stock": proy_stock,
            "proy_nuevos": proy_nuevos,
            "proy_total": proy_stock + proy_nuevos,
        })
    return filas


def acumular_real(por_dia, n_dias):
    """{dia: saldo activado ese dia} -> lista acumulada de largo n_dias."""
    acum, total = [], 0.0
    for d in range(1, n_dias + 1):
        total += por_dia.get(d, 0.0)
        acum.append(total)
    return acum

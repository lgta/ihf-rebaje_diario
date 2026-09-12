"""
VARIANTE "PRIMERA ENTRADA" de la meta de septiembre 2026 (Enfoque alfa).

NO REEMPLAZA a `meta_septiembre_capital_asegurado.py`. Es una SEGUNDA version
del universo, pedida por el usuario el 2026-09-02, para poder compararla
contra la vigente. La meta publicada de septiembre sigue siendo S/20,477,271.

--------------------------------------------------------------------------
LA PREGUNTA QUE LA ORIGINA
--------------------------------------------------------------------------
La gestion de cobranza congela el atributo antiguo/nuevo al INICIO del mes.
Entonces un credito que arranca el mes en mora (ANTIGUO), paga, y vuelve a
vencer dentro del mismo mes, "reentra" -- y su capital podria estar
contandose dos veces: una en el stock y otra en el calendario.

Son DOS solapamientos distintos y conviene no confundirlos:

  (A) STOCK x CALENDARIO -- YA ESTABA RESUELTO.
      `tarea19_meta_septiembre_insumos.sql` excluye del calendario a todo
      credito que este en el stock (`not in (select id_loan from
      stock_agosto)`), y lo hace para el mes COMPLETO, no solo hasta la
      fecha en que pago. Medido en tarea21_diagnostico_doble_entrada.sql:
      son 2,205 creditos y S/3,703,671 de septiembre -- el 92% de los
      creditos del stock tiene ademas un vencimiento en el mes. O sea que
      la exclusion no es cosmetica: sin ella el doble conteo seria enorme.
      Coincide ademas con el atributo congelado: el credito es antiguo todo
      el mes, y su reentrada ya vive dentro de la curva de stock, que se
      calibra justamente sobre esa poblacion.

  (B) CALENDARIO x CALENDARIO -- ESTO ES LO QUE AGREGA ESTA VARIANTE.
      Un credito que NO esta en el stock pero vence DOS VECES dentro del
      mes aparece dos veces en el calendario, con su saldo completo cada
      vez. La query de insumos no deduplica por credito-mes. Es el mismo
      principio que (A) un nivel mas abajo: solo la PRIMERA entrada cuenta.

--------------------------------------------------------------------------
CUANTO MUEVE, Y POR QUE IGUAL VALE LA PENA
--------------------------------------------------------------------------
En septiembre 2026, (B) son S/6,545.67 -- el 0.0073% del calendario. Nada.
La variante da practicamente la misma meta, y ESE es el resultado: para
septiembre, el doble conteo no es un problema.

Pero el tamano depende del mes, y septiembre se salva por casualidad de
calendario, no por diseno. El calendario se indexa por ENTRADA
(= vencimiento + 1), asi que su ventana va del ULTIMO dia del mes anterior
al PENULTIMO del mes. Cuando el mes anterior es corto, esa ventana atrapa
dos vencimientos mensuales del mismo credito:

    202603 (despues de un febrero de 28 dias)   calendario +12.7%
    202607 (despues de un junio de 30 dias)     calendario +12.9%
    202609 (despues de un agosto de 31 dias)    calendario  +0.0%

Medido contra `tasa_soles.csv`, que si deduplica. Ver PENDIENTES.md tarea 21.

Y hay una segunda razon, independiente del tamano: `P_ENTRADA` (la tasa por
soles) SI deduplica a un vencimiento por credito-mes, pero hoy se aplica
sobre un calendario que NO deduplica. Tasa y universo no comparten
definicion -- exactamente lo que prohibe el "principio de modelado" de
CLAUDE.md. Esta variante los alinea. Es la mitad de PENDIENTES.md tarea 20.

--------------------------------------------------------------------------
LO QUE ESTA VARIANTE **NO** ARREGLA -- decirlo, no esconderlo
--------------------------------------------------------------------------
La CURVA de nuevos sigue calibrada sobre la matriz cruda
(`curva_cruda_nuevos.csv`), que cuenta cada evento de entrada y no
deduplica por credito-mes. Para ser consistente de punta a punta habria que
recalibrarla sobre entradas deduplicadas: una corrida mas de Athena,
anotada en PENDIENTES.md tarea 21. La curva es una FORMA (% del capital
entrado que ya activo), asi que el efecto esperado es de segundo orden --
pero no es cero, y mientras no se mida no se puede afirmar que sea chico.

--------------------------------------------------------------------------
COMO COMPARA CONTRA LA META VIGENTE, SIN RUIDO
--------------------------------------------------------------------------
`dts_mambu_loans_hist` se re-expresa para dias pasados: los mismos insumos
corridos el 1-sep y el 2-sep difieren ~-0.3%. Si se comparara esta variante
contra el CSV del 1-sep, ese -0.3% se confundiria con el efecto del metodo
(que es -0.0073%) y lo taparia 40 veces.

Por eso `tarea21_insumos_primera_entrada.sql` emite los DOS calendarios en
la MISMA corrida: `calendario` (rn_venc = 1) y `calendario_extra`
(rn_venc > 1). Este script proyecta los dos y los compara sobre una sola
foto de datos, que es la unica comparacion que aisla el metodo.
"""
import collections
import csv

from motor_unificado import (cargar_curva_stock, cargar_curva_nuevos,
                             cargar_factor_dia_mes, cargar_factor_dia_mes_stock,
                             segmentar_calendario, proyectar)

DIR_19 = "datos_tarea19"
DIR_21 = "datos_tarea21"
DIR_CA = "datos_capital_asegurado"
PERIODO = "202609"
N_DIAS = 30
VENTANA = ("202508", "202607")   # identica a la meta vigente


def leer(p):
    with open(p) as f:
        return list(csv.DictReader(f))


def tasa_soles_rodante():
    """La MISMA tasa que usa la meta vigente. No se recalibra: el cambio de
    esta variante es de UNIVERSO, no de tasa, y mezclar los dos haria
    imposible atribuir la diferencia."""
    e = n = 0.0
    for r in leer(f"{DIR_19}/tasa_soles.csv"):
        if VENTANA[0] <= r["periodo"] <= VENTANA[1]:
            e += float(r["elegibles_soles"])
            n += float(r["entran_soles"])
    return n / e


P_ENT = tasa_soles_rodante()

# Curvas y factores: EXACTAMENTE los de la meta vigente.
curva_stock = cargar_curva_stock(f"{DIR_CA}/curva_unificada_stock_seg_v3.csv")
f_dm_stock = cargar_factor_dia_mes_stock()
curva_nuevos = cargar_curva_nuevos(f"{DIR_CA}/curva_sep_nuevos_dow_seg.csv")
factor_dia_mes = cargar_factor_dia_mes(f"{DIR_CA}/factor_dia_mes_sep.csv")

# --- insumos de la MISMA corrida, para que la comparacion aisle el metodo ---
stock = {}
cal_1ra = collections.defaultdict(dict)     # rn_venc = 1
cal_extra = collections.defaultdict(dict)   # rn_venc > 1
for r in leer(f"{DIR_21}/meta_septiembre_primera_entrada_insumos.csv"):
    saldo = float(r["saldo"])
    if r["tipo"] == "stock":
        stock[(r["tramo"], r["avance_band"])] = saldo
    elif r["tipo"] == "calendario":
        cal_1ra[int(r["dia_entrada"])][r["avance_band"]] = saldo
    elif r["tipo"] == "calendario_extra":
        cal_extra[int(r["dia_entrada"])][r["avance_band"]] = saldo

# el calendario del metodo VIGENTE es la suma de los dos
cal_vig = collections.defaultdict(dict)
for fuente in (cal_1ra, cal_extra):
    for dia, porbanda in fuente.items():
        for b, s in porbanda.items():
            cal_vig[dia][b] = cal_vig[dia].get(b, 0.0) + s


def proyectar_con(calendario):
    return proyectar(stock, segmentar_calendario(calendario, PERIODO),
                     curva_stock, curva_nuevos, N_DIAS,
                     p_entrada=P_ENT, f_dm=factor_dia_mes, f_dm_stock=f_dm_stock)


VARIANTES = {
    "vigente (todo vencimiento)": cal_vig,
    "primera entrada": cal_1ra,
}
RES = {k: proyectar_con(v) for k, v in VARIANTES.items()}

filas = RES["primera entrada"]
for i, fila in enumerate(filas):
    fila["fecha"] = f"2026-09-{i+1:02d}"


def _cal_total(c):
    return sum(s for pb in c.values() for s in pb.values())


if __name__ == "__main__":
    print("=" * 78)
    print("VARIANTE 'PRIMERA ENTRADA' -- septiembre 2026, Enfoque alfa")
    print("=" * 78)
    print("NO reemplaza la meta vigente (S/20,477,271). Es una segunda version del")
    print("universo: cada credito cuenta UNA sola vez, por su primera entrada en mora.")
    print()
    print("--- EL UNIVERSO, LOS DOS SOLAPAMIENTOS ---")
    print(f"  (A) stock x calendario   ya estaba excluido   S/ 3,703,671  (2,205 creditos)")
    print(f"      -> el 92% de los creditos del stock tiene ademas un vencimiento en el mes")
    print(f"  (B) 2do vencimiento del mismo credito         S/ {_cal_total(cal_extra):>9,.0f}"
          f"  ({sum(1 for pb in cal_extra.values() for _ in pb)} grupos)")
    print(f"      -> esto es lo que agrega esta variante")
    print()
    print("--- INSUMOS (misma corrida de Athena, sin ruido de re-expresion) ---")
    print(f"  stock al 1-sep                    S/ {sum(stock.values()):>13,.2f}")
    print(f"  calendario, metodo vigente        S/ {_cal_total(cal_vig):>13,.2f}")
    print(f"  calendario, primera entrada       S/ {_cal_total(cal_1ra):>13,.2f}")
    print(f"  efecto del metodo                 S/ {_cal_total(cal_1ra)-_cal_total(cal_vig):>13,.2f}"
          f"   ({100*(_cal_total(cal_1ra)/_cal_total(cal_vig)-1):+.4f}%)")
    print(f"  tasa de entrada (la misma en las dos)  {100*P_ENT:.4f}%")
    print()
    print("--- PROYECCION ---")
    print(f"  {'variante':<28} {'stock':>13} {'nuevos':>15} {'total':>15}")
    for k, f in RES.items():
        u = f[-1]
        print(f"  {k:<28} {u['proy_stock']:>13,.0f} {u['proy_nuevos']:>15,.0f} {u['proy_total']:>15,.0f}")
    a = RES["vigente (todo vencimiento)"][-1]["proy_total"]
    b = RES["primera entrada"][-1]["proy_total"]
    print(f"  {'diferencia':<28} {'':>13} {'':>15} {b-a:>15,.0f}   ({100*(b/a-1):+.4f}%)")
    print()
    print("--- CONTRA LA META PUBLICADA ---")
    print(f"  meta publicada el 1-sep                        S/ 20,477,271")
    print(f"  variante primera entrada (datos del 2-sep)     S/ {b:>12,.0f}"
          f"   ({100*(b/20477271-1):+.2f}%)")
    print("  OJO: esa diferencia es casi toda RE-EXPRESION de dts_mambu_loans_hist")
    print("  entre el 1-sep y el 2-sep, no el cambio de metodo. El efecto del metodo")
    print(f"  es el {100*(b/a-1):+.4f}% de arriba, medido sobre una sola foto.")
    print()
    print("--- LECTURA ---")
    print("  Para septiembre el doble conteo (B) es despreciable y la variante no")
    print("  cambia la meta. Eso NO significa que la correccion sobre: el tamano")
    print("  depende del mes -- en 202603 y 202607 el calendario corre +12.7% y")
    print("  +12.9% sobre el universo deduplicado -- y ademas alinea la definicion")
    print("  del universo con la de P_ENTRADA, que ya deduplicaba.")
    print()
    print("  PENDIENTE para consistencia completa: la curva de nuevos sigue")
    print("  calibrada sobre entradas SIN deduplicar. Ver PENDIENTES.md tarea 21.")

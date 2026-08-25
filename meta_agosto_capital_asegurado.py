"""
Meta de capital asegurado de agosto 2026 (Enfoque alfa), anclada al cierre
REAL de julio.

v7 (2026-08-25, tarea 17 Fase 4) -- MOTOR UNIFICADO. La capa fantasma se
elimina: ya no hay 3 componentes (stock + nuevos + fantasma) sino 2
(stock + nuevos), calibrados con `dias_atraso_cuota` en vez de `dayslate`.
Ver motor_unificado.py y BUGS.md bug 16 (Fase 4). Lo que desaparece de este
archivo respecto de v6:
  - P_NO_PAGA_DIA0 = 13.38% y P_FANTASMA = 8.6163%  ->  P_ENTRADA = 21.9918%
  - la constante hardcodeada CUOTAS_31JUL_FANTASMA (S/140,194): esa cohorte
    ahora entra por el calendario con dia_entrada = 1, medida (S/139,950,
    0.17% de diferencia contra el hardcode -- confirma la cohorte por una
    via independiente).
  - las constantes REAL_*_A_HOY: el real ahora viene por dia desde
    datos_tarea17_fase4/real_agosto.csv, asi que el corte se puede mover sin
    re-correr ninguna query.

CONVENCION DEL CALENDARIO PROSPECTIVO (distinta de la de los backtests, y es
inherente, no un descuido): el saldo en riesgo de cada cuota esta anclado al
CIERRE DE JULIO, porque una meta fijada al inicio del mes no puede conocer el
saldo al vencimiento futuro. Los 4 backtests de meses cerrados si usan el
saldo del dia del vencimiento. `status = 'ACTIVE'` solamente para el
calendario prospectivo, per CLAUDE.md.

Historial de versiones anteriores (arquitectura con capa fantasma): v2/v3
agregaron la capa fantasma y el fix de frontera de mes (bug 14); v4/v5
refrescaron el corte a 20 y 21-ago; v6 recalibro P_FANTASMA a 8.6163% con
`dias_atraso_cuota` (tarea 17 Fase 3). Ver git para esas versiones.

Insumos:
  datos_tarea17_fase4/meta_agosto_insumos.csv : stock + calendario (Q-G/Q-H,
      tarea17_fase4_meta_agosto_insumos.sql)
  datos_tarea17_fase4/real_agosto.csv         : real activado por dia
      (Q-I, tarea17_fase4_real_agosto.sql, datos hasta 25-ago)
  datos_capital_asegurado/curva_unificada_{stock,nuevos}_seg.csv
"""
import collections
import csv

from motor_unificado import (P_ENTRADA, cargar_curva_stock, cargar_curva_nuevos,
                             proyectar, acumular_real)

DIR_F4 = "datos_tarea17_fase4"
N_DIAS = 31
# Corte de tracking. 21-ago es el mismo corte del ultimo numero publicado
# (v6), para que la comparacion antes/despues aisle el cambio de modelo y no
# mezcle un refresco de fecha. CORTE_FRESCO es el ultimo dia completo con
# datos (hoy es 25-ago; la foto de Mambu de hoy todavia corre).
CORTE = 21
CORTE_FRESCO = 24

curva_stock = cargar_curva_stock()
curva_nuevos = cargar_curva_nuevos()

stock_agosto = {}
calendario_agosto = collections.defaultdict(dict)
with open(f"{DIR_F4}/meta_agosto_insumos.csv") as f:
    for r in csv.DictReader(f):
        if r["tipo"] == "stock":
            stock_agosto[(r["tramo"], r["avance_band"])] = float(r["saldo"])
        else:
            calendario_agosto[int(r["dia_entrada"])][r["avance_band"]] = float(r["saldo"])

real_por_dia = collections.defaultdict(dict)
with open(f"{DIR_F4}/real_agosto.csv") as f:
    for r in csv.DictReader(f):
        real_por_dia[r["componente"]][int(r["dia"])] = float(r["saldo_activado_dia"])

filas = proyectar(stock_agosto, calendario_agosto, curva_stock, curva_nuevos, N_DIAS)
real_stock_acum = acumular_real(real_por_dia["stock"], N_DIAS)
real_nuevos_acum = acumular_real(real_por_dia["nuevos"], N_DIAS)
for i, fila in enumerate(filas):
    fila["fecha"] = f"2026-08-{i+1:02d}"
    fila["real_stock"] = real_stock_acum[i]
    fila["real_nuevos"] = real_nuevos_acum[i]
    fila["real_total"] = real_stock_acum[i] + real_nuevos_acum[i]

if __name__ == "__main__":
    saldo_stock_inicial = sum(stock_agosto.values())
    saldo_cal = sum(sum(v.values()) for v in calendario_agosto.values())
    print(f"Stock al 1 de agosto (dias_atraso_cuota 1-30 al cierre de julio): S/ {saldo_stock_inicial:,.0f}")
    print(f"Calendario de agosto (por dia de entrada, excluye stock):         S/ {saldo_cal:,.0f}")
    print(f"P_ENTRADA = {100*P_ENTRADA:.4f}%\n")

    print(f"{'dia':>3} {'fecha':>11} | {'proy_total':>11} | {'real_total':>11}")
    for r in filas:
        marca = ""
        if r["dia"] == CORTE:
            marca = "  <- corte comparable (21-ago)"
        elif r["dia"] == CORTE_FRESCO:
            marca = "  <- ultimo dia con datos"
        real = f"{r['real_total']:>11,.0f}" if r["dia"] <= CORTE_FRESCO else " " * 11
        print(f"{r['dia']:>3} {r['fecha']:>11} | {r['proy_total']:>11,.0f} | {real}{marca}")

    fin = filas[-1]
    print(f"\n=== META DE AGOSTO 2026 -- ENFOQUE ALFA, MOTOR UNIFICADO (sin capa fantasma) ===")
    print(f"Meta total del mes (proyectada al cierre):  S/ {fin['proy_total']:,.0f}")
    print(f"  stock:  S/ {fin['proy_stock']:,.0f}")
    print(f"  nuevos: S/ {fin['proy_nuevos']:,.0f}   (incluye el dia 0, que antes era la capa fantasma)")
    print(f"\nMeta anterior (v6, con capa fantasma):     S/ 16,257,325")
    print(f"Diferencia:                                 {100*(fin['proy_total']/16257325-1):+.1f}%")

    for corte, etiqueta in [(CORTE, "corte comparable"), (CORTE_FRESCO, "ultimo dia con datos")]:
        r = filas[corte - 1]
        print(f"\n--- Avance al {corte}-ago ({etiqueta}) ---")
        print(f"Real acumulado:                    S/ {r['real_total']:,.0f}"
              f"   (stock S/ {r['real_stock']:,.0f} + nuevos S/ {r['real_nuevos']:,.0f})")
        print(f"Proyectado al mismo dia:           S/ {r['proy_total']:,.0f}")
        print(f"Real vs. proyectado al mismo dia:  {100*(r['real_total']/r['proy_total']-1):+.1f}%")
        print(f"Avance sobre la meta del mes:      {100*r['real_total']/fin['proy_total']:.1f}%")
        print(f"Lo que resta del mes:              S/ {fin['proy_total']-r['real_total']:,.0f}")

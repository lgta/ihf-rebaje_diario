"""
META DEL MES CON EL MOTOR v2 (adoptado 2026-09-13), los dos enfoques.

    python meta_v2.py <periodo> <insumos.csv>
    python meta_v2.py 202610 datos_tarea25/insumos_octubre.csv

<insumos.csv> es la salida de la query de insumos del mes (`tarea25_insumos_octubre.sql` para
octubre; mismo formato que `tarea24_v2_septiembre_al_1.sql`). Las reglas viven en
`motor_v2.py`; este script solo imprime la meta y guarda la serie diaria junto a los insumos.

CONTROL: `python meta_v2.py 202609 datos_tarea24/v2_septiembre_al_1.csv` da la meta de septiembre
al 1-sep con el motor adoptado (reenganches incluidos, tasa anclada): S/17,504,932 alfa y
S/3,338,715 recupero, la fila de referencia de `meta_septiembre_v2_dia1.py`. Con REENG y
TASA_ANCLADA en False da la de antes de esas dos decisiones (S/19,815,529 con la matriz de
calendario de tarea 25; S/19,814,433 con la de tarea 24). Ese control vale con la matriz de nuevos de
tarea 24 (fotos hasta el 1-sep); con la de tarea 25 (fotos hasta el 1-oct, vigente desde el 1-oct) da
S/17,509,399 / S/3,341,199 (+0.03%): fotos de septiembre re-expresadas por fecha valor (bug 26).
"""
import csv
import os
import sys

import motor_v2 as MV

HITOS = (5, 10, 15, 20, 25)


def main(periodo, insumos):
    n = MV.dias_del_mes(periodo)
    stock, cal = MV.leer_insumos(insumos)
    d1 = sum(MV.leer_insumos(insumos, solo_d1=True)[0].values())
    salida = []
    print("=" * 96)
    print(f"META {periodo} -- MOTOR v2 (antiguo = en mora el dia 1; cohorte d1 con curva de nuevos;")
    print(f"arrastre por DNI fuera; reenganches {'incluidos' if MV.REENG else 'fuera'} de la calibracion;")
    print(f"tasa de entrada {'ANCLADA al cierre del mes anterior (bug 28)' if MV.TASA_ANCLADA else 'sobre el saldo al vencimiento'})")
    print("=" * 96)
    print(f"Stock el dia 1: S/ {sum(stock.values()):,.0f}   (de eso, entro en mora el mismo dia 1: S/ {d1:,.0f})")
    print(f"Calendario desde el dia 2: S/ {sum(sum(v.values()) for v in cal.values()):,.0f}\n")
    for medida, titulo in (("act", "CAPITAL ASEGURADO (Enfoque alfa)"), ("reb", "RECUPERO OFICIAL (rebaje)")):
        filas, p = MV.meta(periodo, medida, insumos)
        u = filas[-1]
        print(f"{titulo}")
        print(f"  META DEL MES: S/ {u['proy_total']:,.0f}   (stock S/ {u['proy_stock']:,.0f} + "
              f"nuevos S/ {u['proy_nuevos']:,.0f})   tasa de entrada {100*p:.2f}%")
        print("  acumulado esperado: " + "   ".join(
            f"dia {d}: S/ {filas[d-1]['proy_total']:,.0f}" for d in HITOS + (n,)))
        print()
        for fila in filas:
            salida.append({"medida": medida, "dia": fila["dia"],
                           "proy_stock": round(fila["proy_stock"], 2),
                           "proy_nuevos": round(fila["proy_nuevos"], 2),
                           "proy_total": round(fila["proy_total"], 2)})
    ruta = os.path.join(os.path.dirname(insumos), f"meta_v2_{periodo}.csv")
    with open(ruta, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(salida[0].keys()))
        w.writeheader()
        w.writerows(salida)
    print(f"Serie diaria en {ruta} (local, no se versiona)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])

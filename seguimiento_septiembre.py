"""
SEGUIMIENTO DE SEPTIEMBRE 2026 CONTRA LA META PUBLICADA el 1-sep, los dos
enfoques. Pendiente desde el 1-sep (handoff 2026-09-13, punto 2).

La meta NO se recalcula: se leen las series diarias que ya producen
`meta_septiembre_capital_asegurado.py` y `meta_septiembre_recupero.py` (las
mismas que se publicaron) y se comparan contra el real de
`tarea19_real_septiembre.sql`, medido con la MISMA definicion que la meta (v1:
stock = mora 1-30 al cierre de agosto).

Dos numeros, como pide CLAUDE.md -- nunca uno solo:
  - AVANCE contra la trayectoria de la meta: real acumulado / proyectado
    acumulado al mismo dia. Responde la pregunta del mes: si el caveat de ~10%
    (la activacion real cae -0.46pp/mes, tarea 19) se esta materializando, este
    cociente deberia correr cerca de 0.90.
  - CORRELACION de incrementos diarios proyectado vs. real: si la ejecucion
    sigue la FORMA esperada, aunque el nivel este corrido.

El corte es el PENULTIMO dia con foto (la foto del dia en curso todavia esta
corriendo): con los datos al 13-sep, el ultimo dia completo es el 12. Medido en
tarea24_frescura.sql: el 13 tiene 3 filas mas que el 12, contra ~300-400 de
crecimiento diario normal.
"""
import csv
import statistics
import sys

import meta_septiembre_capital_asegurado as ALFA
import meta_septiembre_recupero as RECUPERO

REAL = "datos_tarea19/real_septiembre.csv"
SALIDA = "datos_tarea19/seguimiento_septiembre.csv"
ULTIMO_DIA = int(sys.argv[1]) if len(sys.argv) > 1 else 12

real = {"alfa": {"stock": {}, "nuevos": {}}, "recupero": {"stock": {}, "nuevos": {}}}
pob = {}
with open(REAL) as f:
    for r in csv.DictReader(f):
        d = int(r["dia"])
        real["alfa"][r["componente"]][d] = float(r["saldo_activado_dia"])
        real["recupero"][r["componente"]][d] = float(r["rebaje_dia"])
        pob[r["componente"]] = (int(r["creditos_pob"]), float(r["saldo_pob"]))


def acum(por_dia, n):
    out, t = [], 0.0
    for d in range(1, n + 1):
        t += por_dia.get(d, 0.0)
        out.append(t)
    return out


def inc(serie):
    return [serie[0]] + [serie[i] - serie[i - 1] for i in range(1, len(serie))]


def serie(enfoque, filas):
    n = ULTIMO_DIA
    rs, rn = acum(real[enfoque]["stock"], n), acum(real[enfoque]["nuevos"], n)
    out = []
    for i in range(n):
        p = filas[i]
        out.append({"enfoque": enfoque, "dia": i + 1,
                    "proy_stock": p["proy_stock"], "proy_nuevos": p["proy_nuevos"],
                    "proy_total": p["proy_total"],
                    "real_stock": rs[i], "real_nuevos": rn[i], "real_total": rs[i] + rn[i]})
    return out


def reporte(nombre, s, meta_mes):
    n = len(s)
    u = s[-1]
    print("=" * 96)
    print(f"{nombre} -- meta publicada S/ {meta_mes:,.0f}  |  real al {n:02d}-sep (ultimo dia completo)")
    print("=" * 96)
    print(f"{'dia':>3} | {'proy acum':>12} {'real acum':>12} {'real/proy':>10} | "
          f"{'proy dia':>10} {'real dia':>10} | {'real stock':>11} {'real nuevos':>12}")
    pt, rt = [x["proy_total"] for x in s], [x["real_total"] for x in s]
    ip, ir = inc(pt), inc(rt)
    for i, x in enumerate(s):
        print(f"{x['dia']:>3} | {x['proy_total']:>12,.0f} {x['real_total']:>12,.0f} "
              f"{x['real_total']/x['proy_total']:>10.3f} | {ip[i]:>10,.0f} {ir[i]:>10,.0f} | "
              f"{x['real_stock']:>11,.0f} {x['real_nuevos']:>12,.0f}")
    print()
    for comp in ("stock", "nuevos", "total"):
        p = [x[f"proy_{comp}"] for x in s]
        r = [x[f"real_{comp}"] for x in s]
        c = statistics.correlation(inc(p), inc(r))
        mae = sum(abs(a - b) for a, b in zip(inc(p), inc(r))) / n
        print(f"  {comp:<7} real/proy al dia {n}: {r[-1]/p[-1]:.3f} ({100*(r[-1]/p[-1]-1):+.1f}%)"
              f"   corr. incrementos diarios {c:.3f}   MAE diario S/ {mae:,.0f}")
    print(f"  avance del mes: real = {100*u['real_total']/meta_mes:.1f}% de la meta del mes; "
          f"la trayectoria de la meta esperaba {100*u['proy_total']/meta_mes:.1f}% a esta fecha")
    print()


def descomposicion(s_alfa):
    """¿La brecha de nuevos es de VOLUMEN (entra menos de lo que la tasa espera)
    o de ACTIVACION (el que entra paga menos)? Entradas reales por dia de
    tarea24_v2_septiembre.sql (bloque real_pob, definicion v1, sin reenganches:
    la misma poblacion que la meta).

    OJO: el calendario de la meta tiene el saldo anclado al CIERRE de agosto y
    la entrada real se mide con el saldo del dia anterior a la entrada, que ya
    descuenta la amortizacion de septiembre (addendum de
    analisis_tarea19_activacion_decreciente.md: +8.2% en agosto). Parte de la
    brecha de volumen es eso, no menos gente entrando."""
    n = ULTIMO_DIA
    ent = {}
    with open("datos_tarea24/v2_septiembre.csv") as f:
        for r in csv.DictReader(f):
            if r["bloque"] == "real_pob" and r["definicion"] == "v1" and r["reeng"] == "0":
                ent[int(r["dia"])] = ent.get(int(r["dia"]), 0.0) + float(r["saldo"])
    tasa = ALFA.TASAS[ALFA.MODO_TASA]
    esp = {d: tasa * sum(ALFA.calendario_sep.get(d, {}).values()) for d in range(1, n + 1)}
    e_real, e_esp = sum(ent.get(d, 0.0) for d in range(1, n + 1)), sum(esp.values())
    a_real, a_proy = s_alfa[-1]["real_nuevos"], s_alfa[-1]["proy_nuevos"]
    print("=" * 96)
    print(f"DESCOMPOSICION DE LA BRECHA DE NUEVOS (Enfoque alfa), dias 1-{n}")
    print("=" * 96)
    print(f"  saldo que ENTRO en mora     real S/ {e_real:>12,.0f}   esperado (calendario x {100*tasa:.2f}%)"
          f" S/ {e_esp:>12,.0f}   {100*(e_real/e_esp-1):+.1f}%")
    print(f"  activado de nuevos          real S/ {a_real:>12,.0f}   proyectado"
          f"                    S/ {a_proy:>12,.0f}   {100*(a_real/a_proy-1):+.1f}%")
    print(f"  activado por sol que entro  real {a_real/e_real:>8.3f}          proyectado"
          f"                        {a_proy/e_esp:>8.3f}      {100*((a_real/e_real)/(a_proy/e_esp)-1):+.1f}%")
    print("  (volumen x conversion = brecha; el volumen incluye la amortizacion no descontada del ancla)")
    print()


if __name__ == "__main__":
    s_alfa = serie("alfa", ALFA.filas)
    s_rec = serie("recupero", RECUPERO.filas)
    print(f"Poblacion v1 medida hoy: stock {pob['stock'][0]:,} creditos / S/ {pob['stock'][1]:,.0f}"
          f"   (la meta uso S/ {sum(ALFA.stock_sep.values()):,.0f} el 1-sep)")
    print(f"                         nuevos {pob['nuevos'][0]:,} entradas al dia de corte de la query"
          f" / S/ {pob['nuevos'][1]:,.0f}\n")
    reporte("CAPITAL ASEGURADO (Enfoque alfa)", s_alfa, ALFA.filas[-1]["proy_total"])
    reporte("RECUPERO OFICIAL (rebaje)", s_rec, RECUPERO.filas[-1]["proy_total"])
    descomposicion(s_alfa)

    with open(SALIDA, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(s_alfa[0].keys()))
        w.writeheader()
        for x in s_alfa + s_rec:
            w.writerow({k: (round(v, 2) if isinstance(v, float) else v) for k, v in x.items()})
    print(f"Serie escrita en {SALIDA}")

#!/usr/bin/env python3
"""Copia plantilla/ a un proyecto y rellena los marcadores {{ASI}} con un JSON de valores.

Uso:
  python rellenar_plantilla.py --valores valores.json --destino /ruta/al/proyecto

Reglas de los marcadores (ver cuestionario.md):
  - Valor texto: se sustituye tal cual.
  - Valor lista: la línea que lo contiene se repite una vez por elemento (lista vacía = la línea desaparece).
    Sirve para rutas de propiedad.tsv, bullets de las fichas y líneas de .gitignore.
  - ROLES (lista): en el texto se escribe separada por espacios; además, cada línea con {{ROL}} se repite por rol.
  - FECHA_DESPLIEGUE: si no viene, la hora actual en ZONA_HORARIA.
  - MOTOR_EXTRA: "godot", "unity" o "" -> copia extras/<motor>/* a tools/hooks/ (pre-commit-motor.sh, etc.).
Fichas: solo se copian las de roles en ROLES; un rol sin ficha la recibe de plantilla_ficha.md con {{COMPLETAR}}.
Memorias: una memoria_<rol>.md por rol. propiedad.tsv pierde las filas de roles que no estén en ROLES.
No sobrescribe archivos que ya existan en el destino.
Al final lista los marcadores que quedan sin rellenar (los {{COMPLETAR}} los rellena la sesión a mano).
Solo biblioteca estándar.
"""

import argparse
import datetime
import json
import os
import re
import shutil
import stat
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
MARCADOR = re.compile(r"\{\{([A-Z_]+)(?::[^}]*)?\}\}")
ROLES_OBLIGATORIOS = ["coordinador", "arquitecto-sistemas", "auditor-calidad"]


def ahora_en(zona):
    try:
        from zoneinfo import ZoneInfo
        return datetime.datetime.now(ZoneInfo(zona)).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return datetime.datetime.now().strftime("%Y-%m-%d %H:%M")


def rellenar_texto(texto, valores, roles):
    salida = []
    for linea in texto.split("\n"):
        lineas = [linea.replace("{{ROL}}", r) for r in roles] if "{{ROL}}" in linea else [linea]
        for l in lineas:
            listas = [m for m in MARCADOR.findall(l) if isinstance(valores.get(m), list) and m != "ROLES"]
            if len(set(listas)) > 1:
                raise SystemExit(f"Una línea no puede llevar dos marcadores de lista: {l!r}")
            variantes = [l.replace("{{%s}}" % listas[0], str(v)) for v in valores[listas[0]]] if listas else [l]
            for v in variantes:
                for clave, valor in valores.items():
                    if isinstance(valor, str):
                        v = v.replace("{{%s}}" % clave, valor)
                v = v.replace("{{ROLES}}", " ".join(roles))
                salida.append(v)
    return "\n".join(salida)


def copiar(origen, destino, texto, informe):
    if os.path.exists(destino):
        informe["existentes"].append(destino)
        return
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    with open(destino, "w", encoding="utf-8", newline="\n") as f:
        f.write(texto)
    modo = os.stat(origen).st_mode
    if modo & stat.S_IXUSR:
        os.chmod(destino, modo | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    informe["creados"].append(destino)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--valores", required=True)
    ap.add_argument("--destino", required=True)
    ap.add_argument("--plantilla", default=os.path.join(AQUI, "plantilla"))
    args = ap.parse_args(argv)

    with open(args.valores, encoding="utf-8") as f:
        valores = json.load(f)
    roles = valores.get("ROLES") or []
    falta = [r for r in ROLES_OBLIGATORIOS if r not in roles]
    if falta or any(not re.fullmatch(r"[a-z][a-z0-9-]*", r) for r in roles):
        raise SystemExit(f"ROLES debe incluir {ROLES_OBLIGATORIOS} y usar minúsculas y guiones (faltan: {falta})")
    valores.setdefault("FECHA_DESPLIEGUE", ahora_en(valores.get("ZONA_HORARIA", "UTC")))

    destino = os.path.abspath(args.destino)
    informe = {"creados": [], "existentes": []}
    dir_roles = os.path.join("docs", "direccion", "roles")
    fichas = {}

    for raiz, _, archivos in os.walk(args.plantilla):
        for nombre in sorted(archivos):
            origen = os.path.join(raiz, nombre)
            rel = os.path.relpath(origen, args.plantilla)
            with open(origen, encoding="utf-8") as f:
                texto = f.read()
            if os.path.dirname(rel) == dir_roles:
                if nombre in ("plantilla_ficha.md", "memoria_ROL.md"):
                    fichas[nombre] = (origen, texto)
                    continue
                rol = nombre[:-3]
                if nombre not in ("plantilla_encargo.md", "plantilla_memoria.md") and rol not in roles:
                    continue  # ficha de un rol que este proyecto no usa
            texto = rellenar_texto(texto, valores, roles)
            if nombre == "propiedad.tsv":  # fuera las rutas de roles que este proyecto no usa
                texto = "\n".join(l for l in texto.split("\n")
                                  if l.startswith("#") or "\t" not in l or l.split("\t")[1] in roles + ["*"])
            copiar(origen, os.path.join(destino, rel), texto, informe)

    for rol in roles:
        ficha = os.path.join(destino, dir_roles, f"{rol}.md")
        if not os.path.exists(ficha) and not os.path.exists(os.path.join(args.plantilla, dir_roles, f"{rol}.md")):
            origen, texto = fichas["plantilla_ficha.md"]
            texto = "\n".join(l for l in texto.split("\n") if not l.startswith("> "))
            copiar(origen, ficha, rellenar_texto(texto.replace("{{ROL}}", rol), valores, roles), informe)
        origen, texto = fichas["memoria_ROL.md"]
        copiar(origen, os.path.join(destino, dir_roles, f"memoria_{rol}.md"),
               rellenar_texto(texto.replace("{{ROL}}", rol), valores, roles), informe)

    extra = valores.get("MOTOR_EXTRA", "")
    if extra:
        dir_extra = os.path.join(AQUI, "extras", extra)
        if not os.path.isdir(dir_extra):
            raise SystemExit(f"MOTOR_EXTRA desconocido: {extra!r} (hay: {sorted(os.listdir(os.path.join(AQUI, 'extras')))})")
        for nombre in sorted(os.listdir(dir_extra)):
            origen = os.path.join(dir_extra, nombre)
            with open(origen, encoding="utf-8") as f:
                copiar(origen, os.path.join(destino, "tools", "hooks", nombre), rellenar_texto(f.read(), valores, roles), informe)

    pendientes = []
    for ruta in informe["creados"]:
        with open(ruta, encoding="utf-8") as f:
            for n, linea in enumerate(f, 1):
                for m in MARCADOR.findall(linea):
                    pendientes.append(f"{os.path.relpath(ruta, destino)}:{n}: {{{{{m}}}}}")
    print(f"Creados {len(informe['creados'])} archivo(s) en {destino}")
    for ruta in informe["existentes"]:
        print(f"  YA EXISTÍA (no se toca, fusiónalo a mano): {os.path.relpath(ruta, destino)}")
    if pendientes:
        print("Marcadores sin rellenar (rellénalos a mano):")
        for p in pendientes:
            print("  " + p)
    return 0


if __name__ == "__main__":
    sys.exit(main())

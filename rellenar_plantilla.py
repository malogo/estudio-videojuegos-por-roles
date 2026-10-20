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
  - NIVEL_AUTONOMIA: "bajo", "medio" o "alto"; MAX_RECHAZOS: entero >= 1. Si faltan (valores.json de antes),
    se usan "medio" y "3" con un aviso.
Bloques condicionales (en todos los archivos de plantilla/ y de extras/, antes de los marcadores):
  {{#SI NIVEL_AUTONOMIA=medio,alto}}
  ... líneas que solo van si la clave (de texto) vale una de las opciones; pueden llevar otros marcadores ...
  {{#FIN}}
  Cada marcador de bloque va solo en su línea y desaparece al rellenar. Sin anidar. Bloque sin cerrar, {{#FIN}}
  suelto, bloques anidados o clave inexistente o que no sea texto: error.
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
BLOQUE_SI = re.compile(r"^\s*\{\{#SI ([A-Z_]+)=([^}]*)\}\}\s*$")
BLOQUE_FIN = re.compile(r"^\s*\{\{#FIN\}\}\s*$")
NIVELES = ["bajo", "medio", "alto"]
# Claves nuevas con valor por defecto: un valores.json de antes sigue valiendo (actualizar.md)
DEFECTOS = {"NIVEL_AUTONOMIA": "medio", "MAX_RECHAZOS": "3"}


def ahora_en(zona):
    try:
        from zoneinfo import ZoneInfo
        return datetime.datetime.now(ZoneInfo(zona)).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return datetime.datetime.now().strftime("%Y-%m-%d %H:%M")


def aplicar_bloques(texto, valores, nombre):
    """Quita los bloques {{#SI CLAVE=a,b}} ... {{#FIN}} cuya clave no vale a ni b, y las líneas de los marcadores."""
    salida, abierto, dentro = [], 0, True
    for n, linea in enumerate(texto.split("\n"), 1):
        m = BLOQUE_SI.match(linea)
        if m:
            if abierto:
                raise SystemExit(f"{nombre}:{n}: bloque {{{{#SI}}}} dentro de otro (abierto en la línea {abierto}); no se admiten anidados")
            clave, opciones = m.group(1), [o.strip() for o in m.group(2).split(",")]
            if not isinstance(valores.get(clave), str):
                raise SystemExit(f"{nombre}:{n}: la clave {clave} del bloque {{{{#SI}}}} no existe en valores.json o no es texto")
            abierto, dentro = n, valores[clave] in opciones
        elif BLOQUE_FIN.match(linea):
            if not abierto:
                raise SystemExit(f"{nombre}:{n}: {{{{#FIN}}}} sin su {{{{#SI ...}}}}")
            abierto, dentro = 0, True
        elif "{{#" in linea:
            raise SystemExit(f"{nombre}:{n}: marcador de bloque mal escrito o fuera de su propia línea: {linea.strip()!r}")
        elif dentro:
            salida.append(linea)
    if abierto:
        raise SystemExit(f"{nombre}:{abierto}: bloque {{{{#SI}}}} sin cerrar con {{{{#FIN}}}}")
    return "\n".join(salida)


def validar_claves(valores):
    """Pone los valores por defecto de las claves nuevas (con aviso) y comprueba las que tienen opciones fijas."""
    for clave, defecto in DEFECTOS.items():
        if clave not in valores:
            print(f"AVISO: valores.json no tiene {clave}; se usa {defecto!r} (cuestionario.md)", file=sys.stderr)
            valores[clave] = defecto
    if valores["NIVEL_AUTONOMIA"] not in NIVELES:
        raise SystemExit(f"NIVEL_AUTONOMIA debe ser uno de {NIVELES} (es {valores['NIVEL_AUTONOMIA']!r})")
    rechazos = valores["MAX_RECHAZOS"]
    if isinstance(rechazos, bool) or not re.fullmatch(r"[1-9][0-9]*", str(rechazos)):
        raise SystemExit(f"MAX_RECHAZOS debe ser un entero mayor o igual que 1 (es {rechazos!r})")
    valores["MAX_RECHAZOS"] = str(rechazos)


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
    validar_claves(valores)
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
                texto = aplicar_bloques(f.read(), valores, rel)
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
                texto = aplicar_bloques(f.read(), valores, os.path.join("extras", extra, nombre))
            copiar(origen, os.path.join(destino, "tools", "hooks", nombre), rellenar_texto(texto, valores, roles), informe)

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

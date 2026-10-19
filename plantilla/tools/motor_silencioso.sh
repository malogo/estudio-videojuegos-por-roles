#!/usr/bin/env bash
# Uso: ./tools/motor_silencioso.sh <rol> [argumentos del motor...]
# Única forma permitida de lanzar el motor ({{MOTOR}}): siempre sin sonido ni ventanas que suenen,
# y con el candado PID "motor" (una sola sesión a la vez usa la caché del proyecto).
# Funciona desde cualquier carpeta: añade la ruta del proyecto si no se pasa ya.
# El ejecutable sale de $MOTOR_BIN o, si no está, del valor por defecto de abajo.

set -euo pipefail

ROLE_NAME="${1:?Especifica tu nombre de rol como primer argumento}"
shift 1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOTOR_BIN="${MOTOR_BIN:-{{BINARIO_MOTOR}}}"
# Argumentos que garantizan "sin sonido" y sin interfaz (ver cuestionario.md, pregunta del motor).
ARGS_SILENCIO=({{ARGS_MOTOR_SILENCIOSO}})
# Opción que indica la carpeta del proyecto ("" si el motor la recibe de otra forma).
ARG_RUTA="{{ARG_RUTA_PROYECTO}}"

EXTRA=()
if [[ -n "$ARG_RUTA" && " $* " != *" $ARG_RUTA "* ]]; then
    EXTRA=("$ARG_RUTA" "$ROOT")
fi

"$ROOT/tools/locks/with_lock.sh" motor "$ROLE_NAME" \
    "$MOTOR_BIN" "${ARGS_SILENCIO[@]}" "${EXTRA[@]}" "$@"

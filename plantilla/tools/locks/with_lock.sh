#!/usr/bin/env bash
# Uso: ./tools/locks/with_lock.sh <nombre_candado> <nombre_rol> <comando...>
# Ejemplo (build): ./tools/locks/with_lock.sh {{CANDADO_BUILD}} arquitecto-sistemas {{COMANDO_BUILD_EJEMPLO}}
# Para el motor NO uses esto directamente: ./tools/motor_silencioso.sh <rol> ... ya toma el candado "motor".
#
# - Creación atómica del candado (noclobber): dos sesiones a la vez no pueden quedárselo las dos.
# - Si el PID dueño ya no existe, el candado es huérfano y se reclama.
# - Si está ocupado sale con código 75, sin bucle de espera.
# - Nunca borra un candado que no sea suyo.

set -euo pipefail

LOCK_NAME="${1:?Falta nombre del candado (ej. motor o {{CANDADO_BUILD}})}"
ROLE_NAME="${2:?Falta nombre fijo del rol}"
shift 2
[[ $# -gt 0 ]] || { echo "Falta el comando a ejecutar con el candado." >&2; exit 64; }

LOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="${LOCK_DIR}/${LOCK_NAME}.lock"
MY_PID=$$
MY_INFO="${ROLE_NAME}:${MY_PID}:$(date +%s)"

adquirir() {
    ( set -o noclobber; printf '%s\n' "$MY_INFO" > "$LOCK_FILE" ) 2>/dev/null
}

ocupado() {
    echo "[LOCK OCUPADO] '${LOCK_NAME}' está en uso por '${1:-desconocido}' (PID: ${2:-?}). Saliendo sin bucle (código 75)." >&2
    exit 75
}

if ! adquirir; then
    CONTENIDO="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    EXISTING_OWNER="$(cut -d':' -f1 <<< "$CONTENIDO")"
    EXISTING_PID="$(cut -d':' -f2 <<< "$CONTENIDO")"

    if [[ -z "$CONTENIDO" ]]; then
        # Otra sesión lo acaba de crear y aún no ha escrito; solo es huérfano si es antiguo
        EDAD=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || date +%s) ))
        (( EDAD > 10 )) || ocupado "otra sesión" "?"
    elif [[ "$EXISTING_PID" =~ ^[0-9]+$ ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
        ocupado "$EXISTING_OWNER" "$EXISTING_PID"
    fi

    # Huérfano: apartarlo de forma atómica y comprobar que apartamos el que leímos
    APARTADO="${LOCK_DIR}/${LOCK_NAME}.huerfano.${MY_PID}.lock"
    if mv "$LOCK_FILE" "$APARTADO" 2>/dev/null; then
        if [[ "$(cat "$APARTADO" 2>/dev/null || true)" != "$CONTENIDO" ]]; then
            # Otra sesión lo reclamó entre medias: devolverle su candado
            mv -n "$APARTADO" "$LOCK_FILE" 2>/dev/null || true
            rm -f "$APARTADO"
            ocupado "otra sesión" "?"
        fi
        rm -f "$APARTADO"
        echo "[LOCK HUÉRFANO] El PID ${EXISTING_PID:-?} (${EXISTING_OWNER:-?}) ya no existe. Reclamando candado." >&2
    fi
    adquirir || ocupado "otra sesión" "?"
fi

# Limpiar solo si el candado sigue siendo nuestro al salir
cleanup() {
    if [[ -f "$LOCK_FILE" ]]; then
        CURRENT_PID="$(cut -d':' -f2 "$LOCK_FILE" 2>/dev/null || true)"
        if [[ "$CURRENT_PID" == "$MY_PID" ]]; then
            rm -f "$LOCK_FILE"
        fi
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Ejecutar el comando protegido
"$@"

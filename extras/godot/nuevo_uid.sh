#!/usr/bin/env bash
# Escribe <archivo.gd>.uid sin abrir Godot (p. ej. en la nube). Con Godot a mano es mejor importar:
#   ./tools/run_godot_silent.sh <rol> --headless --import
# Uso: ./tools/hooks/nuevo_uid.sh <archivo.gd> [...]
# Formato de Godot 4.4+ (core/io/resource_uid.cpp de 4.7.2-stable): id aleatorio de 63 bits
# (id & 0x7FFFFFFFFFFFFFFF) escrito en base 34 con las cifras "a".."y" y "0".."8", la más significativa
# primero, tras "uid://"; el archivo es esa línea más "\n" (FileAccess::store_line).
# No sobrescribe un .uid existente y no repite un uid que ya esté en el repo.

set -uo pipefail

CIFRAS="abcdefghijklmnopqrstuvwxy012345678"

uid_aleatorio() {
    local n s="" c
    n="$(od -An -N8 -td8 /dev/urandom | tr -d ' ')" || return 1
    n=$(( n & 0x7FFFFFFFFFFFFFFF ))
    while :; do
        c=$(( n % 34 ))
        s="${CIFRAS:c:1}$s"
        n=$(( n / 34 ))
        (( n )) || break
    done
    printf 'uid://%s' "$s"
}

(( $# )) || { echo "Uso: $0 <archivo.gd> [...]" >&2; exit 1; }
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ESTADO=0
for GD in "$@"; do
    if [[ "$GD" != *.gd || ! -f "$GD" ]]; then
        echo "[nuevo_uid] '$GD' no es un archivo .gd existente." >&2
        ESTADO=1; continue
    fi
    if [[ -e "$GD.uid" ]]; then
        echo "[nuevo_uid] '$GD.uid' ya existe; no se toca." >&2
        continue
    fi
    for _ in 1 2 3 4 5; do
        UID_NUEVO="$(uid_aleatorio)" || { ESTADO=1; break; }
        grep -rqxF --include='*.uid' -- "$UID_NUEVO" "$RAIZ" 2>/dev/null || break
        UID_NUEVO=""
    done
    if [[ -z "${UID_NUEVO:-}" ]]; then
        echo "[nuevo_uid] No se pudo generar un uid libre para '$GD'." >&2
        ESTADO=1; continue
    fi
    printf '%s\n' "$UID_NUEVO" > "$GD.uid" && echo "$GD.uid: $UID_NUEVO"
done
exit "$ESTADO"

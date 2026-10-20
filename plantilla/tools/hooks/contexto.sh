# shellcheck shell=bash
# Tamaño del contexto de cada sesión (normas §7). Lo apunta linea_estado.sh (la línea de estado de Claude Code, la
# única que recibe context_window) y lo usan aviso_contexto.sh (hook UserPromptSubmit) e inicio_sesion.sh (SessionStart).
# Se guarda dentro de .git (nunca se commitea), un archivo por sesión: con varias ventanas en la misma carpeta, un
# solo archivo daría a cada una el contexto de otra.
# Uso: source tools/hooks/propiedad.sh; source tools/hooks/contexto.sh
#      guardar_contexto <session_id> <tokens> [<tamaño de la ventana>]
#      leer_contexto <session_id>          # "tokens tamaño"; falla si no hay dato
#      umbrales_contexto <tamaño>          # "vaciar aviso": 250k y 150k, o el 80 % y el 50 % de una ventana menor
#      olvidar_contexto <session_id>       # tras /clear o /compact el dato viejo ya no vale

VACIAR_TOKENS=250000
AVISO_TOKENS=150000

archivo_contexto() {
    local comun s
    comun="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    s="$(_id_limpio "$1")"
    [[ -n "$s" ]] || return 1
    printf '%s/claude_contexto/%s' "$comun" "$s"
}

guardar_contexto() {
    local f
    [[ "$2" =~ ^[0-9]+$ ]] || return 1
    f="$(archivo_contexto "$1")" || return 1
    mkdir -p "${f%/*}" && printf '%s %s\n' "$2" "${3:-}" > "$f"
}

leer_contexto() {
    local f t z
    f="$(archivo_contexto "$1")" && [[ -f "$f" ]] || return 1
    read -r t z < "$f" || return 1
    [[ "$t" =~ ^[0-9]+$ ]] || return 1
    printf '%s %s' "$t" "${z:-0}"
}

umbrales_contexto() {
    local z="${1:-0}" v="$VACIAR_TOKENS" a="$AVISO_TOKENS"
    [[ "$z" =~ ^[0-9]+$ ]] || z=0
    if (( z > 0 && z * 80 / 100 < v )); then v=$(( z * 80 / 100 )); a=$(( z * 50 / 100 )); fi
    printf '%s %s' "$v" "$a"
}

olvidar_contexto() {
    local f
    f="$(archivo_contexto "$1")" || return 0
    rm -f "$f" "$f.avisado"
}

#!/usr/bin/env bash
# Hook PreToolUse de Claude Code (registrado en .claude/settings.json para Bash y PowerShell).
# Se aplica también a los subagentes. Lee el JSON de la llamada por stdin y bloquea
# (código 2 + motivo por stderr) las órdenes prohibidas por docs/direccion/normas_comunes.md.
# Además registra el rol de la sesión cuando la orden es "./tools/hooks/fijar_rol.sh <rol>" o
# "./tools/hooks/arranque_rol.sh <rol>" (el hook es quien conoce session_id/agent_id; lo usa
# guard_propiedad.sh para Edit|Write).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=reglas_comando.sh
source "$HOOKS_DIR/reglas_comando.sh"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"
# shellcheck source=leer_json.sh
source "$HOOKS_DIR/leer_json.sh"

ENTRADA="$(cat)"
ORDEN="" RUTA="" SESION="" AGENTE=""
if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then
    echo "[pre_tool_guard] Sin python ni node: no se pueden comprobar las normas de órdenes." >&2
    exit 0
fi
{ IFS= read -r -d '' ORDEN; IFS= read -r -d '' RUTA; IFS= read -r -d '' SESION; IFS= read -r -d '' AGENTE; } \
    < <(printf '%s' "$ENTRADA" | campos_hook)
ORDEN="${ORDEN//$'\r'/}"
[[ -z "$ORDEN" ]] && exit 0

if ! MOTIVO="$(motivo_bloqueo_linea "$ORDEN")"; then
    echo "[BLOQUEADO POR NORMA] $MOTIVO" >&2
    exit 2
fi

# Solo cuenta fijar_rol.sh o arranque_rol.sh en posición de orden (no "chmod +x fijar_rol.sh"); un rol
# inválido no se registra y el propio script ya lo rechaza.
while IFS= read -r SEG; do
    SEG="${SEG%%$'\002'*}"
    read -ra TOK <<< "$SEG"
    TOK=("${TOK[@]//$'\037'/ }")
    for (( k = 0; k < ${#TOK[@]}; k++ )); do
        case "${TOK[k]}" in *=*|bash|sh|exec|command|env) continue ;; esac
        break
    done
    case "$(_basename_cmd "${TOK[k]:-}")" in fijar_rol.sh|arranque_rol.sh) ;; *) continue ;; esac
    ROL="${TOK[k+1]:-}"
    if rol_valido "$ROL"; then
        guardar_rol_sesion "$ROL" "$SESION" "$AGENTE" \
            || echo "[pre_tool_guard] No se pudo registrar el rol '$ROL' de esta sesión." >&2
    fi
done < <(segmentos_orden "$ORDEN")
exit 0

#!/usr/bin/env bash
# Hook PreToolUse de Claude Code (registrado en .claude/settings.json para Bash y PowerShell).
# Se aplica también a los subagentes. Lee el JSON de la llamada por stdin y bloquea
# (código 2 + motivo por stderr) las órdenes prohibidas por docs/direccion/normas_comunes.md.
# Además registra el rol de la sesión cuando la orden es "./tools/hooks/fijar_rol.sh <rol>" o
# "./tools/hooks/arranque_rol.sh <rol>" (el hook es quien conoce session_id/agent_id; lo usa
# guard_propiedad.sh para Edit|Write).
# Con el rol ya declarado, bloquea actuar en nombre de otro rol por despiste: git commit -m "<otro rol>: ...",
# entregar.sh, archivar_tablon.sh o motor_silencioso.sh con un rol que no es el de la sesión.
# Con DESPACHADOR=1 (sesiones que lanza tools/despachador.sh) bloquea también publicar, fusionar o cambiar de rama y
# lanzar otro despachador (reglas de reglas_comando.sh).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=reglas_comando.sh
source "$HOOKS_DIR/reglas_comando.sh"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"
# shellcheck source=leer_json.sh
source "$HOOKS_DIR/leer_json.sh"

ENTRADA="$(cat)"
ORDEN="" SESION="" AGENTE="" LEIDO=""
{ IFS= read -r -d '' ORDEN; IFS= read -r -d '' _; IFS= read -r -d '' SESION; IFS= read -r -d '' AGENTE
  IFS= read -r -d '' LEIDO; } < <(printf '%s' "$ENTRADA" | campos_hook)
[[ "$LEIDO" == OK ]] || bloquear_sin_json pre_tool_guard
ORDEN="${ORDEN//$'\r'/}"
[[ -z "$ORDEN" ]] && exit 0

if ! MOTIVO="$(motivo_bloqueo_linea "$ORDEN")"; then
    echo "[BLOQUEADO POR NORMA] $MOTIVO" >&2
    exit 2
fi

# Rol del mensaje de "git [opciones] commit ... -m '<rol>: ...'" (vacío si no hay -m o no empieza por un rol).
rol_del_commit() {
    local -a t=("$@")
    local n=${#t[@]} i=0 msg="" x
    while (( i < n )); do
        case "${t[i]}" in
            -C|-c|--git-dir|--work-tree|--namespace) i=$((i + 2)) ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
        esac
    done
    [[ "${t[i]:-}" == commit ]] || return 0
    for (( i = i + 1; i < n; i++ )); do
        x="${t[i]}"
        case "$x" in
            --) break ;;
            -m|--message) msg="${t[i+1]:-}"; break ;;
            --message=*) msg="${x#--message=}"; break ;;
            --*) ;;
            -*m*) msg="${x#*m}"; [[ -z "$msg" ]] && msg="${t[i+1]:-}"; break ;;  # -m"x", -qm "x"
        esac
    done
    [[ "$msg" == *:* ]] && rol_valido "${msg%%:*}" && printf '%s' "${msg%%:*}"
    return 0
}

# Solo cuenta fijar_rol.sh o arranque_rol.sh en posición de orden (no "chmod +x fijar_rol.sh"); un rol
# inválido no se registra y el propio script ya lo rechaza. Los segmentos se recorren en orden: en
# "fijar_rol.sh X && entregar.sh X" vale el rol recién fijado. Nada se registra si la orden se bloquea.
DECLARADO="$(rol_de_sesion "$SESION" "$AGENTE")"
REGISTRAR=()
while IFS= read -r SEG; do
    SEG="${SEG%%$'\002'*}"
    read -ra TOK <<< "$SEG"
    TOK=("${TOK[@]//$'\037'/ }")
    for (( k = 0; k < ${#TOK[@]}; k++ )); do
        case "${TOK[k]}" in *=*|bash|sh|exec|command|env) continue ;; esac
        break
    done
    BASE="$(_basename_cmd "${TOK[k]:-}")"
    case "$BASE" in
        fijar_rol.sh|arranque_rol.sh)
            ROL="${TOK[k+1]:-}"
            if rol_valido "$ROL"; then REGISTRAR+=("$ROL"); DECLARADO="$ROL"; fi
            continue ;;
        entregar.sh|archivar_tablon.sh|motor_silencioso.sh) ROL="${TOK[k+1]:-}" ;;
        git|git.exe|git_guard.sh) ROL="$(rol_del_commit "${TOK[@]:k+1}")" ;;
        *) continue ;;
    esac
    if [[ -n "$DECLARADO" && -n "$ROL" && "$ROL" != "$DECLARADO" ]] && rol_valido "$ROL"; then
        echo "[BLOQUEADO POR NORMA] Esta sesión es '$DECLARADO' y la orden actúa como '$ROL' ($BASE)." >&2
        echo "  Usa tu rol. Si de verdad has cambiado de rol: ./tools/hooks/fijar_rol.sh $ROL (y sigue sus normas)." >&2
        exit 2
    fi
done < <(segmentos_orden "$ORDEN")
for ROL in ${REGISTRAR[@]+"${REGISTRAR[@]}"}; do
    guardar_rol_sesion "$ROL" "$SESION" "$AGENTE" \
        || echo "[pre_tool_guard] No se pudo registrar el rol '$ROL' de esta sesión." >&2
done
exit 0

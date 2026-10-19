#!/usr/bin/env bash
# Línea de estado de Claude Code (statusLine en .claude/settings.json): "<rol> · contexto 123k/1000k (12 %)".
# Además apunta el contexto de la sesión (context_window.total_input_tokens: lo que ocupa ahora, no un acumulado)
# para que aviso_contexto.sh avise de vaciar (normas §7). Solo informa: sale siempre con 0.
# Si ya usas tu propia línea de estado, llama a este script desde ella con el mismo JSON por la entrada.

(( BASH_VERSINFO[0] >= 4 )) || { echo "guardas: hace falta bash 4+"; exit 0; }
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"
# shellcheck source=leer_json.sh
source "$HOOKS_DIR/leer_json.sh"
# shellcheck source=contexto.sh
source "$HOOKS_DIR/contexto.sh"

SESION="" TOKENS="" TAMANO="" LEIDO=""
{ IFS= read -r -d '' SESION; IFS= read -r -d '' TOKENS; IFS= read -r -d '' TAMANO; IFS= read -r -d '' LEIDO; } \
    < <(campos_json session_id context_window.total_input_tokens context_window.context_window_size)
[[ "$LEIDO" == OK ]] || { echo "guardas: no se pudo leer el estado"; exit 0; }

ROL="$(rol_de_sesion "$SESION" "")"
TEXTO="${ROL:-sin rol}"
if [[ "$TOKENS" =~ ^[0-9]+$ ]]; then
    guardar_contexto "$SESION" "$TOKENS" "$TAMANO"
    read -r VACIAR _ <<< "$(umbrales_contexto "$TAMANO")"
    TEXTO+=" · contexto $(( TOKENS / 1000 ))k"
    [[ "$TAMANO" =~ ^[1-9][0-9]*$ ]] && TEXTO+="/$(( TAMANO / 1000 ))k ($(( TOKENS * 100 / TAMANO )) %)"
    (( TOKENS >= VACIAR )) && TEXTO+=" · toca vaciar (memoria y /clear)"
fi
printf '%s\n' "$TEXTO"
exit 0

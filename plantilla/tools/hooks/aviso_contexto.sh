#!/usr/bin/env bash
# Hook UserPromptSubmit de Claude Code (registrado en .claude/settings.json): al llegar cada mensaje (también los que
# manda otra sesión, como el "Tienes trabajo en el tablón" del coordinador) avisa al modelo, en su contexto, de que
# toca volcar la memoria y vaciar (normas §7). El tamaño lo apunta linea_estado.sh; sin ese dato no dice nada.
# - Desde 250k tokens (o el 80 % de una ventana menor): aviso en cada mensaje.
# - Desde 150k (o el 50 %): una sola vez, para quien vaya a parar más de 1 h.
# Solo informa: sale siempre con 0 (un 2 aquí borraría el mensaje de la persona).

(( BASH_VERSINFO[0] >= 4 )) || exit 0
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"
# shellcheck source=leer_json.sh
source "$HOOKS_DIR/leer_json.sh"
# shellcheck source=contexto.sh
source "$HOOKS_DIR/contexto.sh"

SESION="" LEIDO=""
{ IFS= read -r -d '' SESION; IFS= read -r -d '' LEIDO; } < <(campos_json session_id)
[[ "$LEIDO" == OK ]] || exit 0
DATO="$(leer_contexto "$SESION")" || exit 0
read -r TOKENS TAMANO <<< "$DATO"
read -r VACIAR AVISO <<< "$(umbrales_contexto "$TAMANO")"
MARCA="$(archivo_contexto "$SESION").avisado"
ROL="$(rol_de_sesion "$SESION" "")"
MEMORIA="docs/direccion/roles/memoria_${ROL:-<rol>}.md"

if (( TOKENS >= VACIAR )); then
    echo "[AVISO DE VACIADO] El contexto de esta sesión va por $(( TOKENS / 1000 ))k tokens (límite $(( VACIAR / 1000 ))k, normas §7)."
    if [[ "$ROL" == coordinador ]]; then
        echo "  Al acabar lo que tienes entre manos: pon al día $MEMORIA y avisa a la persona responsable para que te vacíe (no te vacíes tú)."
    else
        echo "  Al acabar lo que tienes entre manos: vuelca tu estado en $MEMORIA (con su «Último vaciado» exacto),"
        echo "  commitéala (git commit -m \"${ROL:-<rol>}: memoria\" -- $MEMORIA) y pide que vacíen la sesión (/clear)."
    fi
elif (( TOKENS >= AVISO )); then
    if [[ ! -e "$MARCA" ]]; then
        echo "[INFO CONTEXTO] El contexto de esta sesión va por $(( TOKENS / 1000 ))k tokens: si vas a parar más de 1 h, vuelca tu memoria ($MEMORIA) y pide vaciar ahora."
        : > "$MARCA"
    fi
else
    rm -f "$MARCA"
fi
exit 0

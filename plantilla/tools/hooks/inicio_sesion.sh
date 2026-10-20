#!/usr/bin/env bash
# Hook SessionStart de Claude Code (registrado en .claude/settings.json). Lo que imprime entra en el contexto del modelo:
# - Si las guardas ya tienen un rol registrado para esta sesión (tras /compact, al reanudar...), se lo recuerda, con
#   su memoria: la conversación resumida puede haber perdido quién es y dónde se quedó.
# - Si no, le recuerda que no toque nada hasta saber su rol.
# Tras /clear o /compact olvida el tamaño de contexto apuntado (linea_estado.sh lo vuelve a apuntar).
# Solo informa: sale siempre con 0.

if (( BASH_VERSINFO[0] < 4 )); then
    echo "[inicio_sesion] Las guardas del proyecto necesitan bash 4 o posterior y este es $BASH_VERSION: bloquearán las órdenes"
    echo "  y las ediciones. Díselo a la persona responsable (macOS: brew install bash, y que vaya antes que /bin en el PATH)."
    exit 0
fi
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"
# shellcheck source=leer_json.sh
source "$HOOKS_DIR/leer_json.sh"
# shellcheck source=contexto.sh
source "$HOOKS_DIR/contexto.sh"

SESION="" FUENTE="" LEIDO=""
{ IFS= read -r -d '' SESION; IFS= read -r -d '' FUENTE; IFS= read -r -d '' LEIDO; } < <(campos_json session_id source)
[[ "$LEIDO" == OK ]] || exit 0
[[ "$FUENTE" == clear || "$FUENTE" == compact ]] && olvidar_contexto "$SESION"

ROL="$(rol_de_sesion "$SESION" "")"
if [[ -n "$ROL" ]]; then
    echo "[inicio_sesion] Las guardas tienen registrado para esta sesión el rol '$ROL'."
    case "$FUENTE" in
        clear) echo "  Si el mensaje te asigna otro rol, arranca con ./tools/hooks/arranque_rol.sh <rol>; si no, con ./tools/hooks/arranque_rol.sh $ROL." ;;
        *) echo "  Si no recuerdas tu punto de corte, relee tu memoria (docs/direccion/roles/memoria_$ROL.md) o ejecuta ./tools/hooks/arranque_rol.sh $ROL." ;;
    esac
else
    echo "[inicio_sesion] Esta sesión aún no tiene rol: si el mensaje no te lo dice, pregúntalo antes de tocar nada; luego ./tools/hooks/arranque_rol.sh <rol>."
fi
exit 0

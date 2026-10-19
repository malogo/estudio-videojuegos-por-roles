#!/usr/bin/env bash
# Declara el rol de esta sesión de Claude Code para la guarda de propiedad de Edit|Write.
# Uso (una vez al arrancar, y los subagentes con el rol de origen): ./tools/hooks/fijar_rol.sh <rol>
# El registro real lo hace el hook PreToolUse (pre_tool_guard.sh), que es quien conoce el session_id;
# este script solo valida el rol y muestra el resultado. Fuera de Claude Code usa CLAUDE_ROL=<rol>.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"

ROL="${1:-}"
if ! rol_valido "$ROL"; then
    echo "Uso: $0 <rol>   Roles válidos: ${ROLES_VALIDOS[*]}" >&2
    exit 1
fi
echo "Rol declarado para esta sesión: $ROL (Edit|Write solo en sus rutas de tools/hooks/propiedad.tsv)."

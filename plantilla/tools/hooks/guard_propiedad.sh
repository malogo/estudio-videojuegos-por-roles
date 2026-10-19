#!/usr/bin/env bash
# Hook PreToolUse de Claude Code para Edit|Write|MultiEdit|NotebookEdit (registrado en .claude/settings.json).
# Bloquea (código 2) la edición de archivos del repo que no son del rol de la sesión según propiedad.tsv.
# El rol sale de $CLAUDE_ROL o de "./tools/hooks/fijar_rol.sh <rol>" (registrado por pre_tool_guard.sh).
# El tablón no se edita a mano: las filas se añaden con entregar.sh y se archivan con archivar_tablon.sh.
# Límite: no ve las escrituras hechas desde Bash (sed -i, >, cp...); para eso está el hook commit-msg.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$HOOKS_DIR/../.." && pwd -P)"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"
# shellcheck source=leer_json.sh
source "$HOOKS_DIR/leer_json.sh"

ENTRADA="$(cat)"
RUTA="" SESION="" AGENTE="" LEIDO=""
{ IFS= read -r -d '' _; IFS= read -r -d '' RUTA; IFS= read -r -d '' SESION; IFS= read -r -d '' AGENTE
  IFS= read -r -d '' LEIDO; } < <(printf '%s' "$ENTRADA" | campos_hook)
[[ "$LEIDO" == OK ]] || bloquear_sin_json guard_propiedad
[[ -z "$RUTA" ]] && exit 0

# Ruta relativa a la raíz del repo (Windows: C:\... -> /c/...). Fuera del repo o en .git/ no se vigila.
command -v cygpath >/dev/null 2>&1 && RUTA="$(cygpath -u "$RUTA")"
[[ "$RUTA" != /* ]] && RUTA="$RAIZ/$RUTA"
RUTA="$(realpath -m "$RUTA" 2>/dev/null || printf '%s' "$RUTA")"
[[ "$RUTA" != "$RAIZ"/* ]] && exit 0
REL="${RUTA#"$RAIZ"/}"
[[ "$REL" == .git/* ]] && exit 0

DUENO="$(dueno_de_ruta "$REL")"
ROL="$(rol_de_sesion "$SESION" "$AGENTE")"
# El tablón solo se amplía con entregar.sh (fila con hora real y commit atómico) y se archiva con archivar_tablon.sh.
if [[ "$REL" == docs/direccion/tablon.md ]]; then
    echo "[BLOQUEADO POR NORMA] El tablón no se edita a mano: usa ./tools/hooks/entregar.sh <rol> \"<qué>\" \"<ruta o commit>\" <destino> [-- <rutas>]." >&2
    [[ "$ROL" == coordinador ]] && echo "  Para archivarlo: ./tools/hooks/archivar_tablon.sh coordinador" >&2
    exit 2
fi
[[ "$DUENO" == "*" ]] && exit 0

if [[ -z "$ROL" ]]; then
    echo "[BLOQUEADO POR NORMA] Declara antes tu rol: ./tools/hooks/fijar_rol.sh <rol> (subagentes: el rol de origen del encargo)." >&2
    exit 2
fi
if [[ -z "$DUENO" ]]; then
    echo "[BLOQUEADO POR NORMA] '$REL' no tiene dueño en tools/hooks/propiedad.tsv. Pide por tablón a arquitecto-sistemas que la asigne." >&2
    exit 2
fi
if [[ "$DUENO" != "$ROL" ]]; then
    echo "[BLOQUEADO POR NORMA] '$REL' es de '$DUENO', no de '$ROL'. Pide el cambio por tablón a su dueño." >&2
    exit 2
fi
exit 0

#!/usr/bin/env bash
# Intercepta órdenes destructivas en árbol compartido antes de llamar al binario real de git.
# Uso: ./tools/hooks/git_guard.sh <args de git...>   (o como alias/shim llamado "git" en el PATH)
# Las reglas están en tools/hooks/reglas_comando.sh (las mismas que aplica el hook PreToolUse).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=reglas_comando.sh
source "$HOOKS_DIR/reglas_comando.sh"

if ! MOTIVO="$(motivo_bloqueo_git "$@")"; then
    echo "[BLOQUEADO POR NORMA] $MOTIVO" >&2
    exit 1
fi

# Buscar el git real saltándose este script (evita recursión si se instala como shim "git")
YO="$(realpath "${BASH_SOURCE[0]}")"
while IFS= read -r CANDIDATO; do
    if [[ "$(realpath "$CANDIDATO")" != "$YO" ]]; then
        exec "$CANDIDATO" "$@"
    fi
done < <(type -ap git git.exe 2>/dev/null)

echo "[git_guard] No se encuentra el binario real de git en el PATH." >&2
exit 127

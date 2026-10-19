#!/usr/bin/env bash
# Arranque de sesión en un paso: declara el rol (como fijar_rol.sh) e imprime lo que hay que leer.
# Uso: ./tools/hooks/arranque_rol.sh <rol>
# Imprime la ficha docs/direccion/roles/<rol>.md, la memoria docs/direccion/roles/memoria_<rol>.md y solo
# las filas del tablón (y de docs/direccion/entregas_nube/*.txt aún sin volcar) que acaban en "| <rol>"
# con hora igual o posterior al "**Último vaciado:**" de esa memoria (fecha sin hora = 00:00; misma
# minuta incluida para no perder filas). Fecha ilegible o sin memoria: todas las filas, con un aviso.
# El registro real del rol lo hace el hook PreToolUse (pre_tool_guard.sh), que detecta esta orden igual
# que "fijar_rol.sh <rol>". Fuera de Claude Code usa CLAUDE_ROL=<rol>.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$HOOKS_DIR/../.." && pwd)"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"

ROL="${1:-}"
if ! rol_valido "$ROL"; then
    echo "Uso: $0 <rol>   Roles válidos: ${ROLES_VALIDOS[*]}" >&2
    exit 1
fi

# Los hooks de git del proyecto (normas §11): se activan si aún no lo están.
if [[ "$(git -C "$RAIZ" config core.hooksPath 2>/dev/null)" != tools/hooks ]]; then
    git -C "$RAIZ" config core.hooksPath tools/hooks && echo "Activados los hooks de git: core.hooksPath = tools/hooks"
fi
"$HOOKS_DIR/fijar_rol.sh" "$ROL" || exit 1

FICHA="docs/direccion/roles/$ROL.md"
MEMORIA="docs/direccion/roles/memoria_$ROL.md"
TABLON="docs/direccion/tablon.md"

mostrar() {  # mostrar <título> <ruta relativa>
    echo
    echo "===== $1: $2"
    if [[ -f "$RAIZ/$2" ]]; then tr -d '\r' < "$RAIZ/$2"; else echo "(no existe)"; fi
}
mostrar Ficha "$FICHA"
mostrar Memoria "$MEMORIA"

DESDE="" AVISO=""
if [[ ! -f "$RAIZ/$MEMORIA" ]]; then
    AVISO="no hay memoria ($MEMORIA)"
elif ! DESDE="$(ultimo_vaciado "$RAIZ/$MEMORIA")"; then
    LINEA="$(tr -d '\r' < "$RAIZ/$MEMORIA" | grep -m1 'Último vaciado:' || true)"
    AVISO="'Último vaciado' ilegible en $MEMORIA (${LINEA:-sin esa línea})"
fi
echo
if [[ -n "$DESDE" ]]; then
    echo "===== Tablón: filas hacia $ROL desde el último vaciado ($DESDE)"
else
    echo "===== Tablón: TODAS las filas hacia $ROL"
    echo "AVISO: $AVISO; se muestran todas."
fi
N=0
for F in "$RAIZ/$TABLON" "$RAIZ"/docs/direccion/entregas_nube/*.txt; do
    [[ -f "$F" ]] || continue
    while IFS= read -r FILA; do
        FILA="${FILA%$'\r'}"
        [[ "$FILA" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2})\ \| ]] || continue
        # Comparación de texto: el formato fijo "YYYY-MM-DD HH:MM" ordena igual que el tiempo
        [[ -n "$DESDE" && "${BASH_REMATCH[1]}" < "$DESDE" ]] && continue
        [[ "$F" == */entregas_nube/* ]] && FILA="$FILA   [sin volcar: ${F#"$RAIZ"/}]"
        echo "$FILA"
        N=$((N + 1))
    done < <(grep -E "\| *$ROL[[:space:]]*\$" "$F" || true)
done
echo "($N fila(s))"
if [[ "$ROL" == coordinador && -f "$RAIZ/$TABLON" ]]; then
    FILAS_TABLON=$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \|' "$RAIZ/$TABLON")
    (( FILAS_TABLON > 200 )) && echo "AVISO: el tablón tiene $FILAS_TABLON filas (>200). Archívalo: ./tools/hooks/archivar_tablon.sh coordinador"
fi
exit 0

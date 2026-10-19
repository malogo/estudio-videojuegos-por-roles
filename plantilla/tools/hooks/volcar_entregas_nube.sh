#!/usr/bin/env bash
# Vuelca al tablón las filas que las sesiones en la nube dejan en docs/direccion/entregas_nube/<lote>.txt.
# Uso (coordinador, tras fusionar uno o varios PR de la nube): ./tools/hooks/volcar_entregas_nube.sh
# Añade al final de docs/direccion/tablon.md las filas de todos los .txt, ordenadas por hora (las que ya
# estén en el tablón no se repiten), hace "git rm" de los .txt y deja todo en el índice para commitear
# por rutas. Idempotente: sin .txt no hace nada. Si alguna fila tiene formato incorrecto no toca nada.

set -uo pipefail

RAIZ="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1
cd "$RAIZ" || exit 1
TABLON="docs/direccion/tablon.md"
ENTREGAS="docs/direccion/entregas_nube"
FORMATO='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| [^|]+ \| [^|]+ \| [^|]+ \| [^|]+$'

mapfile -t TXT < <(git ls-files -- "$ENTREGAS/*.txt")
if (( ! ${#TXT[@]} )); then
    echo "Nada que volcar: no hay archivos en $ENTREGAS/."
    exit 0
fi

FILAS=() MALAS=()
for F in "${TXT[@]}"; do
    [[ -f "$F" ]] || { MALAS+=("  $F: está en el índice pero no en el árbol de trabajo"); continue; }
    while IFS= read -r FILA || [[ -n "$FILA" ]]; do
        FILA="${FILA%$'\r'}"
        [[ -z "${FILA// /}" || "$FILA" == \#* ]] && continue
        if [[ "$FILA" =~ $FORMATO ]]; then FILAS+=("$FILA"); else MALAS+=("  $F: $FILA"); fi
    done < "$F"
done
if (( ${#MALAS[@]} )); then
    echo "[volcar_entregas_nube] No se vuelca nada: hay filas con formato incorrecto." >&2
    printf '%s\n' "${MALAS[@]}" >&2
    echo "  Formato: YYYY-MM-DD HH:MM | origen | qué se entregó | ruta o commit | destino" >&2
    exit 1
fi

# Final de línea en el tablón antes de añadir (si el último byte no es "\n")
[[ -s "$TABLON" && "$(tail -c1 "$TABLON" | od -An -c | tr -d ' ')" != '\n' ]] && printf '\n' >> "$TABLON"
NUEVAS=0 REPETIDAS=0
while IFS= read -r FILA; do
    [[ -z "$FILA" ]] && continue
    if tr -d '\r' < "$TABLON" | grep -qxF -- "$FILA"; then
        REPETIDAS=$((REPETIDAS + 1))
    else
        printf '%s\n' "$FILA" >> "$TABLON"
        NUEVAS=$((NUEVAS + 1))
    fi
done < <(printf '%s\n' "${FILAS[@]}" | sort -s -k1,2)

git add -- "$TABLON" && git rm -q -- "${TXT[@]}" || exit 1
echo "Volcadas $NUEVAS fila(s) al tablón (ya estaban: $REPETIDAS) desde ${#TXT[@]} archivo(s); quedan en el índice."
echo "Commitea por rutas:"
echo "  git commit -m \"coordinador: vuelca entregas de la nube\" -- $TABLON ${TXT[*]}"

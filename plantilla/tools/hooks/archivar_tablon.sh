#!/usr/bin/env bash
# Archiva las filas viejas del tablón (lo usa coordinador cuando pasa de ~200 filas; lo avisan arranque_rol.sh y la auditoría).
# Uso: ./tools/hooks/archivar_tablon.sh coordinador [--simular] [--dejar N]
#   --simular  solo dice qué movería, sin tocar nada
#   --dejar N  filas que se quedan siempre en el tablón (50 por defecto)
#
# Mueve a docs/direccion/archivo/tablon_<fecha>.md las filas anteriores al "Último vaciado" MÁS ANTIGUO de todas las
# memorias (docs/direccion/roles/memoria_<rol>.md): así ningún rol pierde filas que aún no ha leído con arranque_rol.sh.
# Las N últimas filas, la cabecera y las líneas que no son filas se quedan. Si una memoria falta o su fecha no se puede
# leer, no archiva nada (ese rol vería todas las filas): arréglala antes.
# Toma el candado "git" (espera hasta 60 s) y hace su propio commit ("coordinador: archiva ...") solo con el tablón y el
# archivo. Si el tablón tiene cambios sin commitear (una entrega a medias), no toca nada: reinténtalo luego.
# Códigos: 0 archivado o nada que archivar, 1 error o commit rechazado, 64 uso incorrecto, 75 ocupado o tablón a medias.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"

TABLON="docs/direccion/tablon.md"
DIR_ARCHIVO="docs/direccion/archivo"
ARGS=("$@")

uso() { echo "Uso: $0 coordinador [--simular] [--dejar N]" >&2; [[ -n "${1:-}" ]] && echo "  $1" >&2; exit 64; }
[[ "${1:-}" == coordinador ]] || uso "Solo coordinador archiva el tablón (normas §3)."
shift
SIMULAR=0 DEJAR=50
while (( $# )); do
    case "$1" in
        --simular) SIMULAR=1; shift ;;
        --dejar) [[ "${2:-}" =~ ^[0-9]+$ ]] || uso "--dejar necesita un número."; DEJAR="$2"; shift 2 ;;
        *) uso "Argumento desconocido: '$1'." ;;
    esac
done

if (( ! SIMULAR )) && [[ "${_ARCHIVAR_CON_CANDADO:-}" != 1 ]]; then
    _ARCHIVAR_CON_CANDADO=1 ESPERA_CANDADO="${ESPERA_CANDADO:-60}" \
        exec "$HOOKS_DIR/../locks/with_lock.sh" git coordinador "$HOOKS_DIR/archivar_tablon.sh" "${ARGS[@]}"
fi

RAIZ="$(git -C "$HOOKS_DIR" rev-parse --show-toplevel)" || exit 1
cd "$RAIZ" || exit 1
[[ -f "$TABLON" ]] || { echo "[archivar] No existe $TABLON." >&2; exit 1; }

# --- Corte: el "Último vaciado" más antiguo de todas las memorias ---------------------------------
CORTE="" QUIEN=""
for ROL in "${ROLES_VALIDOS[@]}"; do
    MEMORIA="docs/direccion/roles/memoria_$ROL.md"
    if ! DESDE="$(ultimo_vaciado "$MEMORIA")"; then
        echo "[archivar] '$MEMORIA' no existe o su 'Último vaciado' no se puede leer: $ROL vería todo el tablón." >&2
        echo "  No se archiva nada. Pide a $ROL que actualice su memoria (o arréglala si es tuya)." >&2
        exit 1
    fi
    if [[ -z "$CORTE" || "$DESDE" < "$CORTE" ]]; then CORTE="$DESDE"; QUIEN="$ROL"; fi
done

# --- Qué filas se mueven -----------------------------------------------------------------------
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
# Comparación de texto: el formato fijo "YYYY-MM-DD HH:MM" ordena igual que el tiempo (como arranque_rol.sh)
tr -d '\r' < "$TABLON" | awk -v corte="$CORTE" -v dejar="$DEJAR" -v quedan="$TMP/quedan" -v movidas="$TMP/movidas" '
    { linea[NR] = $0; if ($0 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9] \|/) fila[NR] = ++n }
    END {
        for (i = 1; i <= NR; i++) {
            if ((i in fila) && fila[i] <= n - dejar && substr(linea[i], 1, 16) < corte) print linea[i] > movidas
            else print linea[i] > quedan
        }
    }'
touch "$TMP/movidas" "$TMP/quedan"
N_MOVER=$(wc -l < "$TMP/movidas" | tr -d ' ')
N_FILAS=$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \|' "$TMP/quedan" "$TMP/movidas" | awk -F: '{ s += $NF } END { print s }')
if (( N_MOVER == 0 )); then
    echo "[archivar] Nada que archivar: $N_FILAS filas; se dejan siempre las $DEJAR últimas y ninguna anterior es"
    echo "  previa a $CORTE (último vaciado de $QUIEN, el más antiguo). Si el tablón sigue grande, pide a $QUIEN que vacíe su memoria."
    exit 0
fi
FECHA="$(date +%Y-%m-%d)"
ARCHIVO="$DIR_ARCHIVO/tablon_$FECHA.md"
if (( SIMULAR )); then
    echo "[archivar] Simulación: se moverían $N_MOVER de $N_FILAS filas (anteriores a $CORTE, último vaciado de $QUIEN) a $ARCHIVO."
    echo "  Primera: $(head -n1 "$TMP/movidas")"
    echo "  Última:  $(tail -n1 "$TMP/movidas")"
    exit 0
fi

if ! git diff --quiet HEAD -- "$TABLON" 2>/dev/null; then
    echo "[archivar] '$TABLON' tiene cambios sin commitear (una entrega a medias). No se toca nada: reinténtalo luego (código 75)." >&2
    exit 75
fi

# --- Escritura y commit propio (solo el tablón y el archivo) ------------------------------------
cp -p -- "$TABLON" "$TMP/copia_tablon"
EXISTIA=0
[[ -f "$ARCHIVO" ]] && { EXISTIA=1; cp -p -- "$ARCHIVO" "$TMP/copia_archivo"; }
mkdir -p "$DIR_ARCHIVO"
if (( ! EXISTIA )); then
    {
        echo "# Archivo del tablón ($FECHA)"
        echo "# Filas movidas por tools/hooks/archivar_tablon.sh. Formato: YYYY-MM-DD HH:MM | origen | qué se entregó | ruta o commit | destino"
        echo
    } > "$ARCHIVO"
fi
cat "$TMP/movidas" >> "$ARCHIVO"
cat "$TMP/quedan" > "$TABLON"

MENSAJE="coordinador: archiva $N_MOVER filas del tablón (anteriores a $CORTE) en $ARCHIVO"
if ! git add -- "$ARCHIVO" || ! git commit -q -m "$MENSAJE" -- "$TABLON" "$ARCHIVO"; then
    cp -p -- "$TMP/copia_tablon" "$TABLON"
    if (( EXISTIA )); then cp -p -- "$TMP/copia_archivo" "$ARCHIVO"; else git rm -q --cached -- "$ARCHIVO" 2>/dev/null; rm -f -- "$ARCHIVO"; fi
    echo "[archivar] Commit rechazado (motivo arriba). El tablón queda como estaba." >&2
    exit 1
fi
echo "Archivado: $(git log -1 --format='%h %s')"
echo "  Quedan $((N_FILAS - N_MOVER)) filas en el tablón (corte: último vaciado de $QUIEN)."

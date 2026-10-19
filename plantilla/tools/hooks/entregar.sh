#!/usr/bin/env bash
# Entrega en una sola orden: añade tu fila al tablón con la hora real y la commitea junto a tus rutas.
# Uso: ./tools/hooks/entregar.sh <rol> "<qué>" "<ruta o commit>" <destino> [--cuerpo "<línea>"]... [--nube <lote>] [-- <rutas>...]
#   <destino>      un rol o "persona responsable"
#   --cuerpo       línea para el cuerpo del mensaje de commit (p. ej. "encargo: agente-ejecutor-lote | high | a la primera: sí")
#   --nube <lote>  sesiones en la nube: la fila va a docs/direccion/entregas_nube/<lote>.txt en lugar del tablón
#   -- <rutas>     tus archivos de la entrega (los nuevos también). Sin rutas: solo la fila (encargos, avisos).
# Ejemplo: ./tools/hooks/entregar.sh arquitecto-sistemas "Lote A1: estructura base" "core/" auditor-calidad -- core/partida.gd
#
# - Toma el candado "git" (espera hasta 60 s: un commit dura segundos), así las entregas no se pisan.
# - El commit ("<rol>: <qué>") lleva exactamente tus rutas y tu fila: si hay filas de otra sesión sin commitear en el
#   tablón, se avisa y se quedan fuera (siguen en el archivo para que su dueño las commitee).
# - Si el commit falla (lo rechaza un hook), el tablón queda como estaba y se ve el motivo.
# - Nunca borra .git/index.lock: si sigue ahí, explica cómo comprobar si es un resto.
# Códigos: 0 entregado, 1 commit rechazado, 64 uso incorrecto, 75 ocupado (candado "git" o index.lock).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=propiedad.sh
source "$HOOKS_DIR/propiedad.sh"

TABLON="docs/direccion/tablon.md"
ENTREGAS="docs/direccion/entregas_nube"
ZONA="{{ZONA_HORARIA}}"
ARGS=("$@")

uso() {
    echo "Uso: $0 <rol> \"<qué>\" \"<ruta o commit>\" <destino> [--cuerpo \"<línea>\"]... [--nube <lote>] [-- <rutas>...]" >&2
    [[ -n "${1:-}" ]] && echo "  $1" >&2
    exit 64
}

(( $# >= 4 )) || uso "Faltan argumentos."
recortar() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
ROL="$1"; QUE="$(recortar "$2")"; REF="$(recortar "$3")"; DESTINO="$(recortar "$4")"
shift 4
CUERPO=() RUTAS=() LOTE=""
while (( $# )); do
    case "$1" in
        --cuerpo) [[ $# -ge 2 ]] || uso "Falta la línea de --cuerpo."; CUERPO+=("$2"); shift 2 ;;
        --nube) [[ $# -ge 2 ]] || uso "Falta el lote de --nube."; LOTE="$2"; shift 2 ;;
        --) shift; RUTAS=("$@"); break ;;
        *) uso "Argumento desconocido: '$1' (las rutas van detrás de --)." ;;
    esac
done

# --- 1. Validación (antes de tomar el candado) -----------------------------------------------
rol_valido "$ROL" || uso "Rol no válido: '$ROL'. Roles: ${ROLES_VALIDOS[*]}"
[[ "$DESTINO" == "persona responsable" || "$DESTINO" == "persona-responsable" ]] || rol_valido "$DESTINO" \
    || uso "Destino no válido: '$DESTINO' (un rol o \"persona responsable\")."
for CAMPO in "$QUE" "$REF"; do
    [[ -n "$CAMPO" ]] || uso "<qué> y <ruta o commit> no pueden ir vacíos."
    [[ "$CAMPO" != *'|'* && "$CAMPO" != *$'\n'* && "$CAMPO" != *$'\r'* ]] \
        || uso "Los campos no pueden llevar '|' ni saltos de línea: '$CAMPO'"
done
for LINEA in ${CUERPO[@]+"${CUERPO[@]}"}; do
    [[ "$LINEA" != *$'\n'* ]] || uso "Cada --cuerpo es una sola línea."
done
[[ -z "$LOTE" || "$LOTE" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || uso "Lote no válido: '$LOTE' (letras, cifras, '.', '-' y '_')."

# --- 2. Candado "git": el resto se hace dentro --------------------------------------------------
if [[ "${_ENTREGAR_CON_CANDADO:-}" != 1 ]]; then
    _ENTREGAR_CON_CANDADO=1 ESPERA_CANDADO="${ESPERA_CANDADO:-60}" \
        exec "$HOOKS_DIR/../locks/with_lock.sh" git "$ROL" "$HOOKS_DIR/entregar.sh" "${ARGS[@]}"
fi

RAIZ="$(git -C "$HOOKS_DIR" rev-parse --show-toplevel)" || exit 1
cd "$RAIZ" || exit 1
ARCHIVO="$TABLON"
[[ -n "$LOTE" ]] && ARCHIVO="$ENTREGAS/$LOTE.txt"

# .git/index.lock: casi siempre es otro git en marcha que acaba en milisegundos; se espera hasta 3 s
INDEX_LOCK="$(git rev-parse --git-path index.lock)"
for (( i = 0; i < 6; i++ )); do [[ -e "$INDEX_LOCK" ]] || break; sleep 0.5; done
if [[ -e "$INDEX_LOCK" ]]; then
    echo "[entregar] Existe '$INDEX_LOCK': otro git está en marcha o quedó a medias. No se entrega nada (código 75)." >&2
    echo "  Comprueba que no hay ningún git en marcha (ps -ef | grep git; en Windows, el Administrador de tareas)." >&2
    echo "  Si no lo hay, es un resto: avisa a la persona responsable para que lo borre (rm -f '$INDEX_LOCK')." >&2
    exit 75
fi

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

# --- 3. Fila con la hora real (zona del equipo si el sistema la conoce, como la valida pre-commit) --
if [[ -e "/usr/share/zoneinfo/$ZONA" ]]; then HORA="$(TZ="$ZONA" date "+%Y-%m-%d %H:%M")"
else HORA="$(date "+%Y-%m-%d %H:%M")"; fi
FILA="$HORA | $ROL | $QUE | $REF | $DESTINO"

# Filas de otras sesiones aún sin commitear: se avisan y se quedan fuera de este commit
HAY_HEAD=1
git rev-parse -q --verify HEAD >/dev/null || HAY_HEAD=0
if (( HAY_HEAD )) && git cat-file -e "HEAD:$ARCHIVO" 2>/dev/null; then
    AJENAS="$(git diff HEAD -U0 -- "$ARCHIVO" | grep '^+[^+]' | sed 's/^+/  /' || true)"
    if [[ -n "$AJENAS" ]]; then
        echo "[entregar] Aviso: '$ARCHIVO' tiene filas sin commitear que no van en tu commit (son de otra sesión):" >&2
        printf '%s\n' "$AJENAS" >&2
    fi
fi

# --- 4. Commit con un índice propio: HEAD + tus rutas + (versión de HEAD del archivo + tu fila) -----
# Así no entra nada que otra sesión tenga en el índice compartido ni filas ajenas del árbol de trabajo.
export GIT_INDEX_FILE="$TMP/index"
if (( HAY_HEAD )); then git read-tree HEAD; else git read-tree --empty; fi || exit 1
if (( ${#RUTAS[@]} )) && ! git add -- "${RUTAS[@]}"; then
    echo "[entregar] No se pueden añadir las rutas (¿alguna mal escrita o ignorada?). No se ha entregado nada." >&2
    exit 1
fi
{
    if (( HAY_HEAD )) && git cat-file -e "HEAD:$ARCHIVO" 2>/dev/null; then
        git show "HEAD:$ARCHIVO" > "$TMP/base"
        [[ -s "$TMP/base" && "$(tail -c1 "$TMP/base" | od -An -c | tr -d ' ')" != '\n' ]] && echo >> "$TMP/base"
        cat "$TMP/base"
    fi
    printf '%s\n' "$FILA"
} > "$TMP/nuevo"
BLOB="$(git hash-object -w -- "$TMP/nuevo")" && git update-index --add --cacheinfo "100644,$BLOB,$ARCHIVO" || exit 1

# Árbol de trabajo: la fila al final (se guarda copia para dejarlo como estaba si el commit falla)
EXISTIA=0
if [[ -f "$ARCHIVO" ]]; then
    EXISTIA=1
    cp -p -- "$ARCHIVO" "$TMP/copia"
    [[ -s "$ARCHIVO" && "$(tail -c1 "$ARCHIVO" | od -An -c | tr -d ' ')" != '\n' ]] && echo >> "$ARCHIVO"
else
    mkdir -p "$(dirname "$ARCHIVO")"
fi
printf '%s\n' "$FILA" >> "$ARCHIVO"

{
    printf '%s: %s\n' "$ROL" "$QUE"
    if (( ${#CUERPO[@]} )); then printf '\n'; printf '%s\n' "${CUERPO[@]}"; fi
} > "$TMP/mensaje"
if ! git commit -q -F "$TMP/mensaje"; then
    if (( EXISTIA )); then cp -p -- "$TMP/copia" "$ARCHIVO"; else rm -f -- "$ARCHIVO"; fi
    echo "[entregar] Commit rechazado (motivo arriba). '$ARCHIVO' queda como estaba; no se ha entregado nada." >&2
    exit 1
fi
unset GIT_INDEX_FILE

# --- 5. El índice compartido pasa a reflejar el commit en tus rutas y en el archivo de la fila ----
REVISAR=("$ARCHIVO" ${RUTAS[@]+"${RUTAS[@]}"})
for (( i = 0; i < 5; i++ )); do
    git reset -q -- "${REVISAR[@]}" 2>/dev/null && break
    sleep 0.5
done
(( i < 5 )) || echo "[entregar] Aviso: no se pudo poner al día el índice; ejecuta: git reset -q -- ${REVISAR[*]}" >&2
echo "Entregado: $(git log -1 --format='%h %s')"
echo "  $FILA"

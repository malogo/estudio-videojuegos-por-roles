#!/usr/bin/env bash
# Uso: ./tools/motor_silencioso.sh <rol> [argumentos del motor...]
# Única forma permitida de lanzar el motor ({{MOTOR}}): siempre sin sonido ni ventanas que suenen,
# y con el candado "motor" (una sola sesión a la vez usa la caché del proyecto).
# Funciona desde cualquier carpeta: añade la ruta del proyecto si no se pasa ya.
# El ejecutable sale de $MOTOR_BIN o, si no está, del valor por defecto de abajo.
#
# La salida del motor no llena el contexto: va entera a .motor_logs/<fecha>_<rol>_<pid>.log (se guardan los 30
# últimos) y aquí solo se imprime un resumen de 25 líneas como mucho: código del motor, errores únicos (los 15
# primeros), errores por dueño (rutas res://, Assets/ o relativas que existan, según tools/hooks/propiedad.tsv)
# y la ruta del log. MOTOR_SALIDA=completa imprime además el log entero (para personas).
# Error = línea que casa con el patrón del motor (MOTOR_REGEX_ERRORES lo cambia) y con ninguno de
# tools/auditoria/ruido_motor.txt (lo decide auditor-calidad). Las líneas sangradas que siguen (p. ej. "at: ...")
# se unen a la anterior para saber de qué archivo es el error.
# Código de salida: el del motor si no es 0; 65 si el motor dio 0 pero hay errores; 75 si el candado está ocupado.

set -uo pipefail

ROLE_NAME="${1:?Especifica tu nombre de rol como primer argumento}"
shift 1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOTOR_BIN="${MOTOR_BIN:-{{BINARIO_MOTOR}}}"
# Argumentos que garantizan "sin sonido" y sin interfaz (ver cuestionario.md, pregunta del motor).
ARGS_SILENCIO=({{ARGS_MOTOR_SILENCIOSO}})
# Opción que indica la carpeta del proyecto ("" si el motor la recibe de otra forma).
ARG_RUTA="{{ARG_RUTA_PROYECTO}}"
# Patrón (ERE) de las líneas de error del motor (cuestionario.md, B11). Vacío = no se buscan errores.
REGEX_DEFECTO='{{REGEX_ERRORES_MOTOR}}'
REGEX="${MOTOR_REGEX_ERRORES-$REGEX_DEFECTO}"
RUIDO="$ROOT/tools/auditoria/ruido_motor.txt"
LOG_DIR="$ROOT/.motor_logs"
MAX_LOGS=30
MAX_LINEAS=25
MAX_ERRORES=15

EXTRA=()
if [[ -n "$ARG_RUTA" && " $* " != *" $ARG_RUTA "* ]]; then
    EXTRA=("$ARG_RUTA" "$ROOT")
fi

mkdir -p "$LOG_DIR" || exit 1
LOG="$LOG_DIR/$(date +%Y-%m-%d_%H%M%S)_${ROLE_NAME//[^A-Za-z0-9_-]/}_$$.log"
LOG_REL="${LOG#"$ROOT"/}"

"$ROOT/tools/locks/with_lock.sh" motor "$ROLE_NAME" \
    "$MOTOR_BIN" ${ARGS_SILENCIO[@]+"${ARGS_SILENCIO[@]}"} ${EXTRA[@]+"${EXTRA[@]}"} "$@" > "$LOG" 2>&1
CODIGO=$?

# Candado ocupado: el motor no llegó a arrancar
if (( CODIGO == 75 )) && head -n1 "$LOG" | grep -q '^\[LOCK OCUPADO\]'; then
    grep -E '^\[LOCK|^  ' "$LOG" >&2
    rm -f "$LOG"
    exit 75
fi

# Solo se guardan los últimos MAX_LOGS (el nombre empieza por la fecha: orden alfabético = cronológico)
LOGS=("$LOG_DIR"/*.log)
(( ${#LOGS[@]} > MAX_LOGS )) && rm -f "${LOGS[@]:0:${#LOGS[@]}-MAX_LOGS}"

[[ "${MOTOR_SALIDA:-}" == completa ]] && cat "$LOG"

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

# Log normalizado: sin \r ni colores ANSI, y cada línea sangrada (hasta 3) unida a la anterior con " · "
awk -v esc="$(printf '\033')" '
    { sub(/\r$/, ""); gsub(esc "\\[[0-9;]*[A-Za-z]", "") }
    /^[ \t]/ && hay && n < 3 { t = $0; sub(/^[ \t]+/, "", t); linea = linea " · " t; n++; next }
    { if (hay) print linea; linea = $0; hay = 1; n = 0 }
    END { if (hay) print linea }' "$LOG" > "$TMP/unido"

# Patrones de ruido: primer campo (separado por tabulador) de cada línea que no sea comentario
: > "$TMP/ruido"
[[ -f "$RUIDO" ]] && tr -d '\r' < "$RUIDO" | grep -vE '^[[:space:]]*(#|$)' | cut -f1 > "$TMP/ruido"

AVISO=""
: > "$TMP/errores"
SILENCIADOS=0
if [[ -n "$REGEX" ]]; then
    grep -E -- "$REGEX" /dev/null 2>/dev/null; (( $? == 2 )) && AVISO="patrón de errores no válido: '$REGEX' (cuestionario.md, B11)"
    if [[ -z "$AVISO" ]]; then
        grep -E -- "$REGEX" "$TMP/unido" | awk '!visto[$0]++' > "$TMP/todos"
        if [[ -s "$TMP/ruido" ]]; then
            grep -v -E -f "$TMP/ruido" "$TMP/todos" > "$TMP/errores" 2>/dev/null
            (( $? == 2 )) && { AVISO="hay un patrón no válido en tools/auditoria/ruido_motor.txt"; cp "$TMP/todos" "$TMP/errores"; }
        else
            cp "$TMP/todos" "$TMP/errores"
        fi
        SILENCIADOS=$(( $(wc -l < "$TMP/todos") - $(wc -l < "$TMP/errores") ))
    fi
fi
N_ERRORES=$(wc -l < "$TMP/errores" | tr -d ' ')

# Errores por dueño: rutas res://..., Assets/..., Packages/... o relativas que existan
# shellcheck source=hooks/propiedad.sh
source "$ROOT/tools/hooks/propiedad.sh"
declare -A DUENO_DE=() ERR_DUENO=() RUTAS_DUENO=() VISTO=()
ORDEN_DUENOS=()
while IFS=: read -r NUM TOKEN; do
    while [[ "$TOKEN" == *. ]]; do TOKEN="${TOKEN%.}"; done  # punto final de la frase
    case "$TOKEN" in
        res://*) RUTA="${TOKEN#res://}" ;;
        Assets/*|Packages/*) RUTA="$TOKEN" ;;
        *) [[ -e "$ROOT/$TOKEN" ]] || continue; RUTA="$TOKEN" ;;
    esac
    [[ -z "$RUTA" ]] && continue
    [[ -n "${DUENO_DE[$RUTA]+x}" ]] || DUENO_DE[$RUTA]="$(dueno_de_ruta "$RUTA")"
    D="${DUENO_DE[$RUTA]}"
    [[ -z "$D" || "$D" == "*" ]] && D="sin dueño"
    [[ -n "${ERR_DUENO[$D]+x}" ]] || { ORDEN_DUENOS+=("$D"); ERR_DUENO[$D]=0; RUTAS_DUENO[$D]=""; }
    if [[ -z "${VISTO[$D:$NUM]+x}" ]]; then VISTO[$D:$NUM]=1; C="${ERR_DUENO[$D]}"; ERR_DUENO[$D]=$(( C + 1 )); fi
    [[ ", ${RUTAS_DUENO[$D]}, " == *", $RUTA, "* ]] || RUTAS_DUENO[$D]+="${RUTAS_DUENO[$D]:+, }$RUTA"
done < <(awk -v r="$ROOT/" '{ while ((i = index($0, r)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(r)); print }' \
             "$TMP/errores" | grep -noE '(res://)?[A-Za-z0-9_.@-]+(/[A-Za-z0-9_.@-]+)+')

# --- Resumen (como mucho MAX_LINEAS líneas) ------------------------------------------------------
if (( CODIGO != 0 )); then FINAL=$CODIGO; EXPLICA="el motor salió con $CODIGO"
elif (( N_ERRORES > 0 )); then FINAL=65; EXPLICA="el motor salió con 0 pero hay errores en el log"
else FINAL=0; EXPLICA="sin errores"; fi

{
    grep '^\[LOCK' "$LOG" | head -n1
    printf '[motor] %s · código del motor: %s · errores: %s' "$ROLE_NAME" "$CODIGO" "$N_ERRORES"
    (( SILENCIADOS > 0 )) && printf ' (+%s silenciados por tools/auditoria/ruido_motor.txt)' "$SILENCIADOS"
    printf ' · log: %s\n' "$LOG_REL"
    [[ -n "$AVISO" ]] && echo "[motor] AVISO: $AVISO"
    if (( N_ERRORES > 0 )); then
        if (( N_ERRORES > MAX_ERRORES )); then echo "[motor] Errores (los $MAX_ERRORES primeros de $N_ERRORES):"
        else echo "[motor] Errores:"; fi
        head -n "$MAX_ERRORES" "$TMP/errores" | cut -c1-200 | sed 's/^/  /'
        if (( ${#ORDEN_DUENOS[@]} )); then
            echo "[motor] Errores por dueño (avísale por tablón si no eres tú):"
            for D in "${ORDEN_DUENOS[@]:0:5}"; do
                R="${RUTAS_DUENO[$D]}"
                (( ${#R} > 120 )) && R="${R:0:117}..."
                echo "  $D: ${ERR_DUENO[$D]} · $R"
            done
        fi
    elif (( CODIGO != 0 )); then
        echo "[motor] Últimas líneas del log:"
        tail -n 8 "$TMP/unido" | cut -c1-200 | sed 's/^/  /'
    fi
    echo "[motor] Resultado: $FINAL ($EXPLICA). Log entero: MOTOR_SALIDA=completa, o grep/tail sobre el log."
} | head -n "$MAX_LINEAS"

exit "$FINAL"

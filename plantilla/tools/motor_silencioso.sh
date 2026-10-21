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
# Efectos colaterales: compara `git status` antes y después; si cambian archivos versionables (p. ej. .uid o .meta
# nuevos en carpetas de otro rol), el resumen los lista por dueño. Pueden venir de otra sesión que trabajaba a la vez.
# No cambia el código de salida. Lo de otro dueño no se revierte ni se commitea: se le avisa con entregar.sh.
# Tope de tiempo: MOTOR_TIEMPO_MAX segundos (300 por defecto). Si el motor sigue en marcha, se para con todo lo que
# lanzó (tools/hooks/procesos.sh: un motor colgado retendría el candado "motor") y el resumen lo avisa. Pasa, p. ej.,
# con Godot y `--headless --quit` sin escena principal: escribe «Can't run project: no main scene defined» y no acaba.
# Código de salida: el del motor si no es 0; 65 si el motor dio 0 pero hay errores; 75 si el candado está ocupado;
# 124 si se pasó de MOTOR_TIEMPO_MAX; 127 si no se encuentra el ejecutable; 64 si MOTOR_TIEMPO_MAX no es válido.

set -uo pipefail

ROLE_NAME="${1:?Especifica tu nombre de rol como primer argumento}"
shift 1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Dueños de las rutas (y comprobación de bash 4+: abajo se usan arrays asociativos)
# shellcheck source=hooks/propiedad.sh
source "$ROOT/tools/hooks/propiedad.sh"
# shellcheck source=hooks/procesos.sh
source "$ROOT/tools/hooks/procesos.sh"
MOTOR_BIN="${MOTOR_BIN:-{{BINARIO_MOTOR}}}"
TIEMPO_MAX="${MOTOR_TIEMPO_MAX:-300}"
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
MAX_COLATERALES=10

[[ "$TIEMPO_MAX" =~ ^[1-9][0-9]*$ ]] \
    || { echo "[motor] MOTOR_TIEMPO_MAX debe ser un entero >= 1 (segundos; hay '$TIEMPO_MAX')." >&2; exit 64; }
# Sin el ejecutable no hay nada que lanzar (en Windows no suele estar en el PATH: ruta completa, cuestionario.md B3)
if [[ -n "$MOTOR_BIN" ]] && ! command -v "$MOTOR_BIN" > /dev/null 2>&1; then
    echo "[motor] No se encuentra el ejecutable del motor «$MOTOR_BIN» (ni en el PATH ni como ruta). Pon su ruta completa en MOTOR_BIN o en el valor por defecto de tools/motor_silencioso.sh (lo cuida arquitecto-sistemas)." >&2
    echo "[motor] Resultado: 127 (sin ejecutable del motor)."
    exit 127
fi

EXTRA=()
if [[ -n "$ARG_RUTA" && " $* " != *" $ARG_RUTA "* ]]; then
    EXTRA=("$ARG_RUTA" "$ROOT")
fi

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

# Foto de los archivos versionables con cambios (estado + fecha de modificación). Sin git: no se compara.
# Las rutas son relativas a la raíz del repositorio, como en propiedad.tsv. Una por línea: "<XY> <fecha> <ruta>".
# Los logs y los candados no cuentan aunque falten en .gitignore.
# PROPIOS = carpeta del proyecto dentro del repositorio ("" o "sub/"). Se pide a git: en Git Bash ROOT es /c/... y
# --show-toplevel da C:/..., así que quitar un prefijo del otro no vale.
RAIZ_GIT="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || RAIZ_GIT=""
PROPIOS="$(git -C "$ROOT" rev-parse --show-prefix 2>/dev/null)" || PROPIOS=""
if stat -c %Y / >/dev/null 2>&1; then STAT_FMT=(-c '%Y %n'); else STAT_FMT=(-f '%m %N'); fi
foto_git() {
    local salida="$1" entrada estado ruta
    local -a estados=() rutas=()
    [[ -n "$RAIZ_GIT" ]] || { : > "$salida"; return 0; }
    while IFS= read -r -d '' entrada; do
        estado="${entrada:0:2}"; ruta="${entrada:3}"
        [[ "$estado" == R* || "$estado" == C* ]] && IFS= read -r -d '' _  # ruta de origen del renombrado
        [[ "$ruta" == "${PROPIOS}.motor_logs/"* || "$ruta" == "${PROPIOS}tools/locks/"*.lock ]] && continue
        estados+=("$estado"); rutas+=("$ruta")
    done < <(git -C "$RAIZ_GIT" status --porcelain -z --untracked-files=all 2>/dev/null)
    declare -A fecha=()
    local f r
    if (( ${#rutas[@]} )); then
        while IFS=' ' read -r f r; do fecha[$r]="$f"; done \
            < <(cd "$RAIZ_GIT" && printf '%s\0' "${rutas[@]}" | xargs -0 stat "${STAT_FMT[@]}" -- 2>/dev/null)
    fi
    for i in "${!rutas[@]}"; do
        printf '%s %s %s\n' "${estados[i]// /_}" "${fecha[${rutas[i]}]:--}" "${rutas[i]}"
    done | sort > "$salida"
}
foto_git "$TMP/antes"

mkdir -p "$LOG_DIR" || exit 1
LOG="$LOG_DIR/$(date +%Y-%m-%d_%H%M%S)_${ROLE_NAME//[^A-Za-z0-9_-]/}_$$.log"
LOG_REL="${LOG#"$ROOT"/}"

# En segundo plano para vigilar el tiempo ("<&0" conserva la entrada estándar). Sin control de trabajos, un comando en
# segundo plano ignora INT: las señales que lleguen aquí paran el árbol del motor.
"$ROOT/tools/locks/with_lock.sh" motor "$ROLE_NAME" \
    "$MOTOR_BIN" ${ARGS_SILENCIO[@]+"${ARGS_SILENCIO[@]}"} ${EXTRA[@]+"${EXTRA[@]}"} "$@" > "$LOG" 2>&1 <&0 &
PID_MOTOR=$!
T0=$SECONDS AGOTADO=0 SENAL=0
trap 'SENAL=130' INT
trap 'SENAL=143' TERM
trap 'SENAL=129' HUP
while proceso_vivo "$PID_MOTOR"; do
    (( SENAL )) && { parar_arbol "$PID_MOTOR" 10; break; }
    if (( SECONDS - T0 >= TIEMPO_MAX )); then AGOTADO=1; parar_arbol "$PID_MOTOR" 10; break; fi
    if (( SECONDS - T0 < 2 )); then sleep 0.1; else sleep 0.5; fi
done
wait "$PID_MOTOR"
CODIGO=$?
trap - INT TERM HUP
(( AGOTADO )) && CODIGO=124
(( SENAL )) && CODIGO=$SENAL

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

# Efectos colaterales: archivos versionables que aparecen o cambian (estado o fecha) entre las dos fotos
foto_git "$TMP/despues"
declare -A COL_DUENO=() COL_RUTAS=()
ORDEN_COL=()
N_COL=0
while IFS=' ' read -r _ _ RUTA; do
    [[ -z "$RUTA" ]] && continue
    N_COL=$(( N_COL + 1 ))
    D="$(dueno_de_ruta "$RUTA")"
    [[ -z "$D" || "$D" == "*" ]] && D="sin dueño"
    [[ -n "${COL_DUENO[$D]+x}" ]] || { ORDEN_COL+=("$D"); COL_DUENO[$D]=0; COL_RUTAS[$D]=""; }
    C="${COL_DUENO[$D]}"; COL_DUENO[$D]=$(( C + 1 ))
    (( N_COL <= MAX_COLATERALES )) && COL_RUTAS[$D]+="${COL_RUTAS[$D]:+, }$RUTA"
done < <(comm -13 "$TMP/antes" "$TMP/despues")

# --- Resumen (como mucho MAX_LINEAS líneas; la última siempre es el resultado) -------------------
if (( AGOTADO )); then FINAL=124; EXPLICA="tiempo agotado: el motor seguía en marcha a los $TIEMPO_MAX s y se ha parado"
elif (( SENAL )); then FINAL=$SENAL; EXPLICA="interrumpido: el motor se ha parado"
elif (( CODIGO != 0 )); then FINAL=$CODIGO; EXPLICA="el motor salió con $CODIGO"
elif (( N_ERRORES > 0 )); then FINAL=65; EXPLICA="el motor salió con 0 pero hay errores en el log"
else FINAL=0; EXPLICA="sin errores"; fi

{
    grep '^\[LOCK' "$LOG" | head -n1
    printf '[motor] %s · código del motor: %s · errores: %s' "$ROLE_NAME" "$CODIGO" "$N_ERRORES"
    (( SILENCIADOS > 0 )) && printf ' (+%s silenciados por tools/auditoria/ruido_motor.txt)' "$SILENCIADOS"
    printf ' · log: %s\n' "$LOG_REL"
    [[ -n "$AVISO" ]] && echo "[motor] AVISO: $AVISO"
    (( AGOTADO )) && echo "[motor] AVISO: pasó de MOTOR_TIEMPO_MAX ($TIEMPO_MAX s) y se ha parado con todo lo que lanzó. ¿Se quedó esperando? (p. ej. Godot con --quit sin escena principal: para scripts, --headless --import o --script)"
    if (( N_COL > 0 )); then
        echo "[motor] El motor ha creado/cambiado $N_COL archivo(s) versionable(s) (o lo hizo otra sesión a la vez):"
        for D in "${ORDEN_COL[@]:0:4}"; do
            R="${COL_RUTAS[$D]:-...}"
            (( ${#R} > 120 )) && R="${R:0:117}..."
            if [[ "$D" == "$ROLE_NAME" ]]; then T=" (tuyos: commitéalos con tu entrega)"
            else T=" (no los reviertas ni commitees: avísale con entregar.sh)"; fi
            echo "  $D: ${COL_DUENO[$D]}$T · $R"
        done
    fi
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
} | head -n $(( MAX_LINEAS - 1 ))
echo "[motor] Resultado: $FINAL ($EXPLICA). Log entero: MOTOR_SALIDA=completa, o grep/tail sobre el log."

exit "$FINAL"

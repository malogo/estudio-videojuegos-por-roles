#!/usr/bin/env bash
# Uso: ./tools/locks/with_lock.sh <nombre_candado> <nombre_rol> <comando...>
#      ./tools/locks/with_lock.sh --estado <nombre_candado>   (diagnóstico; lo usa la auditoría)
# Ejemplo (build): ./tools/locks/with_lock.sh {{CANDADO_BUILD}} arquitecto-sistemas {{COMANDO_BUILD_EJEMPLO}}
# Para el motor NO uses esto directamente: ./tools/motor_silencioso.sh <rol> ... ya toma el candado "motor".
#
# - Si está ocupado sale con código 75, sin bucle de espera (ESPERA_CANDADO=<s> espera como mucho esos segundos).
# - Devuelve el código de salida del comando.
# - El candado dura mientras viva el comando, aunque este envoltorio muera (kill -9, sesión cerrada).
# - Dos modos (CANDADO_MODO=auto|flock|pid; auto = flock si existe la orden):
#   flock: el núcleo da el candado y lo suelta solo cuando mueren el envoltorio y el comando (que hereda el
#          descriptor; CANDADO_HEREDA=0 se lo cierra al comando). El archivo solo guarda datos de diagnóstico
#          y nunca se borra (borrarlo abriría carreras entre inodos).
#   pid:   plan B sin flock (Git Bash en Windows, macOS sin Homebrew). Creación atómica del archivo (noclobber);
#          cuenta como vivo si vive el envoltorio o el comando. Un PID que ya no existe, o que es de un proceso
#          que arrancó después del candado (PID reciclado), es huérfano y se reclama. Si no se puede saber cuándo
#          arrancó y el candado tiene más de CANDADO_MAX_HORAS (6), avisa de "probable huérfano"; nunca lo roba solo.
# - Formato del archivo: rol:pid_envoltorio:epoch:pid_comando.

set -uo pipefail

LOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESTADO_SOLO=0
if [[ "${1:-}" == --estado ]]; then
    ESTADO_SOLO=1
    shift
fi
LOCK_NAME="${1:?Falta nombre del candado (ej. motor o {{CANDADO_BUILD}})}"
if [[ ! "$LOCK_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    echo "Nombre de candado no válido: '$LOCK_NAME' (letras, cifras, '-' y '_')." >&2
    exit 64
fi
LOCK_FILE="${LOCK_DIR}/${LOCK_NAME}.lock"
MAX_EDAD=$(( ${CANDADO_MAX_HORAS:-6} * 3600 ))
ESPERA="${ESPERA_CANDADO:-0}"
[[ "$ESPERA" =~ ^[0-9]+$ ]] || ESPERA=0

MODO="${CANDADO_MODO:-auto}"
case "$MODO" in
    auto) if command -v flock >/dev/null 2>&1; then MODO=flock; else MODO=pid; fi ;;
    flock) command -v flock >/dev/null 2>&1 || { echo "CANDADO_MODO=flock pero no existe la orden flock." >&2; exit 64; } ;;
    pid) ;;
    *) echo "CANDADO_MODO desconocido: '$MODO' (auto, flock o pid)." >&2; exit 64 ;;
esac

# --- Utilidades ------------------------------------------------------------------------------
# Vivo = existe y no es un zombi (un zombi sin recoger no tiene el candado; kill -0 lo daría por vivo).
vivo() {
    [[ "$1" =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null || return 1
    local st
    st="$(ps -o stat= -p "$1" 2>/dev/null)" || return 0
    [[ "${st// /}" != Z* ]]
}

# Segundos que lleva vivo un PID (ps -o etime= vale en Linux y macOS; el ps de Git Bash no lo admite).
segundos_vivo() {
    local t
    t="$(ps -o etime= -p "$1" 2>/dev/null)" || return 1
    t="${t//[[:space:]]/}"
    [[ "$t" =~ ^(([0-9]+)-)?(([0-9]+):)?([0-9]+):([0-9]+)$ ]] || return 1
    echo $(( 10#${BASH_REMATCH[2]:-0} * 86400 + 10#${BASH_REMATCH[4]:-0} * 3600 \
           + 10#${BASH_REMATCH[5]} * 60 + 10#${BASH_REMATCH[6]} ))
}

# Fecha de modificación (GNU/Git Bash: stat -c; macOS/BSD: stat -f)
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || date +%s; }

INFO_ROL="" INFO_PID="" INFO_EPOCH="" INFO_HIJO="" INFO_TXT=""
leer_info() {
    INFO_TXT="$(head -n1 "$LOCK_FILE" 2>/dev/null | tr -d '\r' || true)"
    IFS=: read -r INFO_ROL INFO_PID INFO_EPOCH INFO_HIJO _ <<< "$INFO_TXT"
}

# Estado de los datos leídos (modo pid): vivo | huerfano | dudoso (vivo, sin saber si es el dueño, y viejo)
estado_info() {
    local ahora p s sin_saber=0
    ahora=$(date +%s)
    for p in "$INFO_PID" "$INFO_HIJO"; do
        vivo "$p" || continue
        if s="$(segundos_vivo "$p")" && [[ "$INFO_EPOCH" =~ ^[0-9]+$ ]]; then
            # Arrancó antes de escribirse el candado (con 5 s de margen): es el dueño. Si no, PID reciclado.
            (( ahora - s <= INFO_EPOCH + 5 )) && { echo vivo; return; }
        else
            sin_saber=1
        fi
    done
    if (( sin_saber )); then
        if [[ "$INFO_EPOCH" =~ ^[0-9]+$ ]] && (( ahora - INFO_EPOCH > MAX_EDAD )); then echo dudoso; else echo vivo; fi
    else
        echo huerfano
    fi
}

describir() {
    printf "'%s' (PID: %s%s)" "${INFO_ROL:-desconocido}" "${INFO_PID:-?}" "${INFO_HIJO:+, comando: $INFO_HIJO}"
}

ocupado() {
    local espera=""
    (( ESPERA > 0 )) && espera=" tras esperar ${ESPERA} s"
    echo "[LOCK OCUPADO] '${LOCK_NAME}' está en uso por $(describir)${espera}. Saliendo sin bucle (código 75)." >&2
    exit 75
}

dudoso() {
    echo "[LOCK OCUPADO] '${LOCK_NAME}': probable huérfano de $(describir), con más de $(( MAX_EDAD / 3600 )) h." >&2
    echo "  Ese PID sigue vivo, pero no se puede saber si es el mismo proceso. Compruébalo con: ps -p ${INFO_PID:-?}${INFO_HIJO:+ -p $INFO_HIJO}" >&2
    echo "  Si no es el motor ni la build: rm -f tools/locks/${LOCK_NAME}.lock   (código 75)" >&2
    exit 75
}

# --- Modo flock: ¿está cogido? (se prueba a cogerlo y se suelta) -----------------------------
flock_ocupado() {
    [[ -e "$LOCK_FILE" ]] || return 1
    ( exec 8<"$LOCK_FILE" && flock -n 8 ) 2>/dev/null && return 1
    return 0
}

# --- --estado: "estado|rol|pid|pid_comando|edad_s|modo" (estado: libre, ocupado, huerfano, dudoso)
if (( ESTADO_SOLO )); then
    EST=libre
    if [[ -e "$LOCK_FILE" ]]; then
        leer_info
        if [[ "$MODO" == flock ]]; then
            flock_ocupado && EST=ocupado
        elif [[ -z "$INFO_TXT" ]]; then
            (( $(date +%s) - $(mtime "$LOCK_FILE") > 10 )) && EST=huerfano || EST=ocupado
        else
            EST="$(estado_info)"
            [[ "$EST" == vivo ]] && EST=ocupado
        fi
    fi
    EDAD=""
    [[ "$INFO_EPOCH" =~ ^[0-9]+$ ]] && EDAD=$(( $(date +%s) - INFO_EPOCH ))
    printf '%s|%s|%s|%s|%s|%s\n' "$EST" "$INFO_ROL" "$INFO_PID" "$INFO_HIJO" "$EDAD" "$MODO"
    exit 0
fi

ROLE_NAME="${2:?Falta nombre fijo del rol}"
shift 2
[[ $# -gt 0 ]] || { echo "Falta el comando a ejecutar con el candado." >&2; exit 64; }
MY_PID=$$

# --- Adquisición -------------------------------------------------------------------------------
if [[ "$MODO" == flock ]]; then
    exec 9>>"$LOCK_FILE" || { echo "No se puede abrir $LOCK_FILE." >&2; exit 1; }
    if (( ESPERA > 0 )); then flock -w "$ESPERA" 9; else flock -n 9; fi || { leer_info; ocupado; }
    escribir_info() { printf '%s:%s:%s:%s\n' "$ROLE_NAME" "$MY_PID" "$(date +%s)" "${1:-}" > "$LOCK_FILE"; }
else
    crear() { ( set -o noclobber; printf '%s:%s:%s:\n' "$ROLE_NAME" "$MY_PID" "$(date +%s)" > "$LOCK_FILE" ) 2>/dev/null; }
    # 0 = adquirido; 1 = ocupado (deja INFO_* con el dueño); sale con 75 si es un probable huérfano.
    intentar() {
        crear && return 0
        leer_info
        if [[ -z "$INFO_TXT" ]]; then
            # Otra sesión lo acaba de crear y aún no ha escrito; solo es huérfano si es antiguo
            (( $(date +%s) - $(mtime "$LOCK_FILE") > 10 )) || return 1
        else
            case "$(estado_info)" in
                vivo) return 1 ;;
                dudoso) dudoso ;;
            esac
        fi
        # Huérfano: apartarlo de forma atómica y comprobar que apartamos el que leímos
        local apartado="${LOCK_DIR}/${LOCK_NAME}.huerfano.${MY_PID}.lock"
        if mv "$LOCK_FILE" "$apartado" 2>/dev/null; then
            if [[ "$(head -n1 "$apartado" 2>/dev/null | tr -d '\r' || true)" != "$INFO_TXT" ]]; then
                # Otra sesión lo reclamó entre medias: devolverle su candado
                mv -n "$apartado" "$LOCK_FILE" 2>/dev/null || true
                rm -f "$apartado"
                return 1
            fi
            rm -f "$apartado"
            echo "[LOCK HUÉRFANO] Ni el PID ${INFO_PID:-?} ni el comando ${INFO_HIJO:-?} (${INFO_ROL:-?}) siguen vivos. Reclamando candado." >&2
        fi
        crear || { leer_info; return 1; }
    }
    LIMITE=$(( $(date +%s) + ESPERA ))
    until intentar; do
        (( $(date +%s) < LIMITE )) || ocupado
        sleep 0.5
    done
    # Reescritura atómica (mv) para que nadie lea el archivo a medias
    escribir_info() {
        local tmp="${LOCK_DIR}/${LOCK_NAME}.escribiendo.${MY_PID}.lock"
        printf '%s:%s:%s:%s\n' "$ROLE_NAME" "$MY_PID" "$(date +%s)" "${1:-}" > "$tmp" && mv -f "$tmp" "$LOCK_FILE"
    }
fi

# --- Ejecución ---------------------------------------------------------------------------------
HIJO=""
# Al salir: se suelta el candado solo si el comando ya no vive (si sigue, el candado sigue siendo suyo).
limpiar() {
    [[ -n "$HIJO" ]] && vivo "$HIJO" && return
    if [[ "$MODO" == flock ]]; then
        : > "$LOCK_FILE"
    else
        leer_info
        [[ "$INFO_PID" == "$MY_PID" ]] && rm -f "$LOCK_FILE"
    fi
}
# INT/TERM/HUP se pasan al comando como TERM (sin control de trabajos, un comando en segundo plano ignora
# INT) y se le esperan hasta 10 s.
terminar() {
    if [[ -n "$HIJO" ]] && vivo "$HIJO"; then
        kill -TERM "$HIJO" 2>/dev/null
        local i
        for (( i = 0; i < 20; i++ )); do vivo "$HIJO" || break; sleep 0.5; done
    fi
    exit "$1"
}
trap limpiar EXIT
trap 'terminar 130' INT
trap 'terminar 143' TERM
trap 'terminar 129' HUP

# En segundo plano para conocer su PID; "<&0" conserva la entrada estándar (si no, sería /dev/null).
if [[ "$MODO" == flock && "${CANDADO_HEREDA:-1}" == 0 ]]; then
    "$@" 9>&- <&0 &
else
    "$@" <&0 &
fi
HIJO=$!
escribir_info "$HIJO"
wait "$HIJO"

#!/usr/bin/env bash
# Auditoría de proceso (DUEÑO: auditor-calidad). Bash puro, sin motor.
# Uso: ./tools/auditoria/auditoria_proceso.sh [--raiz DIR] [--ahora "YYYY-MM-DD HH:MM"] [--informe RUTA]
#                                               [--excepciones RUTA]
#   --raiz     repositorio a auditar (por defecto, el que contiene este script)
#   --ahora    hora de referencia (por defecto, la actual en {{ZONA_HORARIA}}); útil para pruebas
#   --informe  ruta del informe (por defecto, <raiz>/docs/calidad/auditoria_proceso_<fecha>.md)
#   --excepciones  commits que la comprobación 2 no revisa (por defecto,
#                  <raiz>/tools/auditoria/excepciones_proceso.txt; puede no existir)
#
# Revisa:
# 1. Filas del tablón con formato "YYYY-MM-DD HH:MM | origen | qué | ruta | destino" y roles válidos; más de 200 filas
#    (toca archivarlo con tools/hooks/archivar_tablon.sh).
# 2. Commits de las últimas 24 h que tocan rutas de otro dueño (según docs/direccion/roles/<rol>.md),
#    salvo los listados en el archivo de excepciones.
# 3. Candados tools/locks/*.lock: huérfanos (modo pid: ni el envoltorio ni el comando siguen vivos), probables
#    huérfanos (PID vivo sin poder saber si es el dueño), ocupados más de CANDADO_MAX_HORAS (6) y restos de un
#    reclamo interrumpido. En modo flock un archivo con datos viejos no es hallazgo: solo cuenta si está cogido.
# 4. Lotes del plan nocturno cuyo estado no coincide con el tablón.
# 5. Entradas de pendientes_manana.md abiertas hace más de 3 días.
# Sale con 0 si no hay hallazgos, 1 si los hay y 2 si no puede auditar.

set -uo pipefail
# Zona del equipo como regla POSIX: Git Bash para Windows no trae base de zonas y con un nombre
# como "Europe/Madrid" caería a UTC (informe con la hora mal).
TZ_EQUIPO="{{ZONA_HORARIA_POSIX}}"
export TZ="${AUDITORIA_TZ:-$TZ_EQUIPO}"
export LC_ALL=C.UTF-8 2>/dev/null || true

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AHORA_TXT=""
INFORME=""
EXCEPCIONES=""
while (( $# )); do
    case "$1" in
        --raiz) RAIZ="${2:?Falta DIR}"; shift 2 ;;
        --ahora) AHORA_TXT="${2:?Falta fecha}"; shift 2 ;;
        --informe) INFORME="${2:?Falta ruta}"; shift 2 ;;
        --excepciones) EXCEPCIONES="${2:?Falta ruta}"; shift 2 ;;
        *) echo "Opción desconocida: $1" >&2; exit 2 ;;
    esac
done
RAIZ="$(cd "$RAIZ" && pwd)" || exit 2
if [[ -n "$AHORA_TXT" ]]; then
    AHORA=$(date -d "$AHORA_TXT" +%s 2>/dev/null) || { echo "--ahora inválido: $AHORA_TXT" >&2; exit 2; }
else
    AHORA=$(date +%s)
fi
FECHA=$(date -d "@$AHORA" +%Y-%m-%d)
INFORME="${INFORME:-$RAIZ/docs/calidad/auditoria_proceso_${FECHA}.md}"
EXCEPCIONES="${EXCEPCIONES:-$RAIZ/tools/auditoria/excepciones_proceso.txt}"

TABLON="$RAIZ/docs/direccion/tablon.md"
PLAN="$RAIZ/docs/direccion/plan_nocturno.md"
PENDIENTES="$RAIZ/docs/direccion/pendientes_manana.md"
FICHAS="$RAIZ/docs/direccion/roles"
# shellcheck source=../hooks/propiedad.sh
source "$RAIZ/tools/hooks/propiedad.sh"
ROLES=("${ROLES_VALIDOS[@]}")
DESTINOS_EXTRA=("persona responsable" "persona-responsable")

for f in "$TABLON" "$PLAN" "$PENDIENTES"; do
    [[ -f "$f" ]] || { echo "No existe $f" >&2; exit 2; }
done

declare -A HALLAZGOS=()
TOTAL=0
anotar() { # anotar <sección 1-5> <texto>
    HALLAZGOS[$1]+="- $2"$'\n'
    TOTAL=$((TOTAL + 1))
}
recortar() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
es_rol() { local r; for r in "${ROLES[@]}"; do [[ "$1" == "$r" ]] && return 0; done; return 1; }
es_destino() { local d; es_rol "$1" && return 0; for d in "${DESTINOS_EXTRA[@]}"; do [[ "$1" == "$d" ]] && return 0; done; return 1; }
leer() { tr -d '\r' < "$1"; }

# --- 1. Formato del tablón -------------------------------------------------------------
N=0 N_FILAS=0
while IFS= read -r LINEA; do
    N=$((N + 1))
    [[ -z "${LINEA// /}" || "$LINEA" == \#* ]] && continue
    N_FILAS=$((N_FILAS + 1))
    if [[ ! "$LINEA" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2})\ \|\ ([^|]+)\ \|\ ([^|]+)\ \|\ ([^|]+)\ \|\ ([^|]+)$ ]]; then
        anotar 1 "línea $N: formato incorrecto → \`${LINEA:0:120}\`"
        continue
    fi
    HORA="${BASH_REMATCH[1]}"; ORIGEN="$(recortar "${BASH_REMATCH[2]}")"; DESTINO="$(recortar "${BASH_REMATCH[5]}")"
    date -d "$HORA" +%s >/dev/null 2>&1 || anotar 1 "línea $N: fecha/hora inexistente \`$HORA\`"
    es_rol "$ORIGEN" || anotar 1 "línea $N: origen no es un rol válido \`$ORIGEN\`"
    es_destino "$DESTINO" || anotar 1 "línea $N: destino no es un rol válido \`$DESTINO\`"
done < <(leer "$TABLON")
(( N_FILAS > 200 )) && anotar 1 "el tablón tiene $N_FILAS filas (>200): coordinador debe archivarlo con \`./tools/hooks/archivar_tablon.sh coordinador\`"

# --- 2. Commits fuera de dueño (últimas 24 h) ------------------------------------------
# Patrones de cada rol: rutas entre comillas invertidas de la sección "Dueño Exclusivo" de su ficha.
# res:// se quita, <x> y ** pasan a *, y un nombre sin "/" vale en cualquier carpeta.
declare -A PATRONES=()
for ROL in "${ROLES[@]}"; do
    FICHA="$FICHAS/$ROL.md"
    [[ -f "$FICHA" ]] || { anotar 2 "falta la ficha \`docs/direccion/roles/$ROL.md\`; no se puede comprobar su propiedad"; continue; }
    while IFS= read -r P; do
        P="${P#res://}"; P="${P//\*\*/*}"; P="$(sed -E 's/<[^>]*>/*/g' <<< "$P")"
        [[ "$P" == */* || "$P" == *.* ]] || continue
        PATRONES[$ROL]+="$P"$'\n'
    done < <(leer "$FICHA" | awk '/^## /{d=/Dueño/} d' | grep -o '`[^`]*`' | tr -d '`')
done
duenos_de() { # imprime los roles cuyos patrones casan con la ruta
    local ruta="$1" rol p
    for rol in "${ROLES[@]}"; do
        while IFS= read -r p; do
            [[ -z "$p" ]] && continue
            # shellcheck disable=SC2053
            if [[ "$ruta" == $p || ( "$p" != */* && "${ruta##*/}" == $p ) ]]; then echo "$rol"; break; fi
        done <<< "${PATRONES[$rol]:-}"
    done
}
# Excepciones: primer campo de cada línea (sin comentarios), hash de al menos 7 caracteres.
EXCEPTUADOS=()
if [[ -f "$EXCEPCIONES" ]]; then
    while read -r E _; do
        E="${E%%#*}"
        [[ -z "$E" ]] && continue
        if [[ "$E" =~ ^[0-9a-fA-F]{7,40}$ ]]; then EXCEPTUADOS+=("${E,,}")
        else anotar 2 "excepción ilegible en \`${EXCEPCIONES#"$RAIZ"/}\`: \`$E\`"; fi
    done < <(leer "$EXCEPCIONES")
fi
exceptuado() { local e; for e in "${EXCEPTUADOS[@]}"; do [[ "$1" == "$e"* ]] && return 0; done; return 1; }
if git -C "$RAIZ" rev-parse --git-dir >/dev/null 2>&1; then
    DESDE=$((AHORA - 86400))
    HASH=""; AUTOR=""; ASUNTO=""
    while IFS= read -r LINEA; do
        if [[ "$LINEA" == $'\x1e'* ]]; then
            IFS=$'\x1f' read -r HASH FECHA_C ASUNTO <<< "${LINEA#$'\x1e'}"
            AUTOR=""
            if (( FECHA_C < DESDE || FECHA_C > AHORA )) || exceptuado "$HASH"; then HASH=""; continue; fi
            AUTOR="${ASUNTO%%:*}"
            if [[ "$ASUNTO" != *:* ]] || ! es_rol "$AUTOR"; then
                anotar 2 "commit ${HASH:0:7} sin rol válido en el mensaje: \`${ASUNTO:0:80}\`"
                HASH=""
            fi
            continue
        fi
        [[ -z "$HASH" || -z "$LINEA" ]] && continue
        [[ "$LINEA" == "docs/direccion/tablon.md" ]] && continue
        DUENOS="$(duenos_de "$LINEA")"
        [[ -z "$DUENOS" ]] && continue
        grep -qx "$AUTOR" <<< "$DUENOS" || anotar 2 "commit ${HASH:0:7} (\`$AUTOR\`) toca \`$LINEA\`, de $(paste -sd, <<< "$DUENOS")"
    done < <(git -C "$RAIZ" log HEAD --no-merges --format=$'%x1e%H%x1f%ct%x1f%s' --name-only -n 500 2>/dev/null)
else
    anotar 2 "\`$RAIZ\` no es un repositorio git; no se pueden revisar commits"
fi

# --- 3. Candados -------------------------------------------------------------------------
# El estado lo da el propio with_lock.sh --estado (misma lógica que al adquirir): "estado|rol|pid|comando|edad_s|modo".
MAX_H="${CANDADO_MAX_HORAS:-6}"
for LOCK in "$RAIZ"/tools/locks/*.lock; do
    [[ -e "$LOCK" ]] || continue
    REL="${LOCK#"$RAIZ"/}"
    NOMBRE="$(basename "$LOCK" .lock)"
    if [[ "$NOMBRE" == *.* ]]; then
        # <candado>.huerfano.<pid>.lock o <candado>.escribiendo.<pid>.lock: si su PID ya no vive, es un resto
        P="${NOMBRE##*.}"
        if [[ ! "$P" =~ ^[0-9]+$ ]] || ! kill -0 "$P" 2>/dev/null; then
            anotar 3 "\`$REL\` es un resto de una sesión interrumpida; se puede borrar"
        fi
        continue
    fi
    IFS='|' read -r EST L_ROL L_PID L_HIJO L_EDAD L_MODO < <("$RAIZ/tools/locks/with_lock.sh" --estado "$NOMBRE" 2>/dev/null || echo "error")
    QUIEN="\`${L_ROL:-?}\` (PID ${L_PID:-?}${L_HIJO:+, comando $L_HIJO})"
    case "$EST" in
        libre) ;;
        huerfano) anotar 3 "\`$REL\` huérfano ($L_MODO): $QUIEN ya no existe" ;;
        dudoso) anotar 3 "\`$REL\` probable huérfano ($L_MODO): $QUIEN sigue vivo pero no se sabe si es el dueño" ;;
        ocupado)
            [[ "$L_EDAD" =~ ^[0-9]+$ ]] && (( L_EDAD > MAX_H * 3600 )) \
                && anotar 3 "\`$REL\` ocupado por $QUIEN desde hace $(( L_EDAD / 3600 )) h (más de $MAX_H h)" ;;
        *) anotar 3 "\`$REL\` ilegible (contenido: \`$(head -c 60 "$LOCK" | tr -d '\r\n')\`)" ;;
    esac
done

# --- 4. Plan nocturno frente al tablón ---------------------------------------------------
TABLON_TXT="$(leer "$TABLON" | grep -E '^[0-9]{4}-' || true)"
while IFS= read -r LINEA; do
    IFS='|' read -r _ _ ROL LOTE _ _ ESTADO _ <<< "$LINEA"
    ROL="$(recortar "$ROL")"; ESTADO="$(recortar "${ESTADO,,}")"
    [[ "$LOTE" =~ \*\*([A-Za-z]+[0-9]+)\*\* ]] || continue
    ID="${BASH_REMATCH[1]}"
    # Entrega = fila cuyo origen es el rol del lote y cuyo "qué" empieza por el lote
    # ("Lote A1 ...", "A1: ...", "N4/A2: ..."); una simple mención ("Aviso: ... A1") no cuenta.
    ENTREGAS="$(awk -F' [|] ' -v r="$ROL" -v id="$ID" '$2==r {
        q = $3; sub(/^Lote /, "", q)
        if (match(q, /^[A-Za-z]+[0-9]+(\/[A-Za-z]+[0-9]+)*/)) {
            n = split(substr(q, 1, RLENGTH), l, "/")
            for (i = 1; i <= n; i++) if (l[i] == id) { print; break }
        }
    }' <<< "$TABLON_TXT" || true)"
    MENCIONES="$(grep -Ew "$ID" <<< "$TABLON_TXT" || true)"
    case "$ESTADO" in
        hecho|entregado|terminado|completado|cerrado|validado)
            [[ -n "$ENTREGAS" ]] || anotar 4 "lote $ID ($ROL) marcado \`$ESTADO\` pero no hay fila de entrega de \`$ROL\` en el tablón" ;;
        pendiente)
            [[ -z "$ENTREGAS" ]] || anotar 4 "lote $ID ($ROL) sigue \`pendiente\` pero el tablón ya tiene su entrega: \`$(head -n1 <<< "$ENTREGAS" | cut -c1-90)\`" ;;
        "en curso"|en_curso|bloqueado|rechazado) ;;
        *) anotar 4 "lote $ID ($ROL) con estado desconocido \`$ESTADO\`" ;;
    esac
    [[ -n "$MENCIONES" ]] || anotar 4 "lote $ID ($ROL) está en el plan pero no aparece en el tablón"
done < <(leer "$PLAN" | grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|')

# --- 5. Pendientes abiertos hace más de 3 días ------------------------------------------
LIMITE=$((AHORA - 3 * 86400))
ENTRADA=""; N=0; NE=0
cerrar_entrada() {
    [[ -z "$ENTRADA" ]] && return
    local marca
    marca=$(date -d "${ENTRADA:0:16}" +%s 2>/dev/null || echo "$AHORA")
    (( marca < LIMITE )) && anotar 5 "línea $NE abierta desde ${ENTRADA:0:16}: \`$(cut -d'|' -f3 <<< "$ENTRADA" | cut -c2-90)\`"
    ENTRADA=""
}
while IFS= read -r LINEA; do
    N=$((N + 1))
    if [[ "$LINEA" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2} ]]; then
        cerrar_entrada; ENTRADA="$LINEA"; NE=$N
    elif [[ "$LINEA" =~ ^[[:space:]]*-\>[[:space:]]*RESUELTO ]]; then
        ENTRADA=""
    fi
done < <(leer "$PENDIENTES")
cerrar_entrada

# --- Informe -----------------------------------------------------------------------------
TITULOS=(""
    "1. Formato y tamaño del tablón"
    "2. Commits fuera de dueño (últimas 24 h)"
    "3. Candados huérfanos u ocupados demasiado tiempo"
    "4. Plan nocturno frente al tablón"
    "5. Pendientes abiertos más de 3 días")
mkdir -p "$(dirname "$INFORME")"
{
    echo "# Auditoría de proceso — $FECHA"
    echo "Generado por \`tools/auditoria/auditoria_proceso.sh\` (auditor-calidad) a las $(date -d "@$AHORA" '+%Y-%m-%d %H:%M') sobre \`$(git -C "$RAIZ" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')\` @ \`$(git -C "$RAIZ" rev-parse --short HEAD 2>/dev/null || echo '?')\`."
    echo
    echo "**Resultado:** $( (( TOTAL == 0 )) && echo 'OK, sin hallazgos' || echo "$TOTAL hallazgo(s)")"
    echo
    echo "| Comprobación | Hallazgos |"
    echo "|---|---|"
    for i in 1 2 3 4 5; do
        echo "| ${TITULOS[$i]} | $(grep -c '^- ' <<< "${HALLAZGOS[$i]:-}") |"
    done
    for i in 1 2 3 4 5; do
        echo
        echo "## ${TITULOS[$i]}"
        if [[ -n "${HALLAZGOS[$i]:-}" ]]; then printf '%s' "${HALLAZGOS[$i]}"; else echo "Sin hallazgos."; fi
    done
} > "$INFORME"

echo "Auditoría de proceso: $TOTAL hallazgo(s). Informe: $INFORME"
for i in 1 2 3 4 5; do
    echo "  ${TITULOS[$i]}: $(grep -c '^- ' <<< "${HALLAZGOS[$i]:-}")"
done
(( TOTAL == 0 ))

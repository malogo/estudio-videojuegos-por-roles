#!/usr/bin/env bash
# Despachador del nivel de autonomía `alto` (DUEÑO: arquitecto-sistemas; normas §9). Lo lanza la persona responsable
# desde su terminal, nunca una sesión de Claude.
# Uso: ./tools/despachador.sh [--ronda N] [--simular]
#   --ronda N   empieza por la ronda N (por defecto, la primera con lotes `pendiente` o `en curso`) y sigue hasta la última
#   --simular   hace las comprobaciones y dice qué lote lanzaría, sin lanzar sesiones, crear la rama ni commitear nada
#
# Encadena las rondas de docs/direccion/plan_nocturno.md de lote en lote. Cada lote es un ciclo: una sesión nueva de
# `claude -p` con el rol del lote (CLAUDE_ROL fijado desde fuera y DESPACHADOR=1, que activa las reglas de
# reglas_comando.sh) y, si entrega, otra de auditor-calidad. Según las filas que cada sesión AÑADE al tablón:
# - entrega ("Lote <id>: ..." o "<id>: ..." del rol) y "Validado <id>" de auditor-calidad: `hecho`;
# - "Rechazo <id>" de auditor-calidad, o ninguna fila: otro intento (el lote sigue `en curso`);
# - "Duda <id>: <pregunta>" del rol, o el tope de intentos (§4 de la especificación; 3 si no se lee): `bloqueado`, con
#   su entrada en pendientes_manana.md; lo que va "tras" él pasa a `bloqueado` por dependencia.
# Intentos usados = filas "Rechazo <id>" de auditor-calidad + "Fallo <id>" de coordinador en el tablón (así se reanuda).
# El estado del plan lo cambia este script como coordinador, con entregar.sh: filas "Encargo <id> (ronda N, intento K)"
# y "Fallo <id>: <motivo>" hacia el rol, "Estado <id>: hecho|bloqueado (...)" y "Pausa (ronda N): ...; sigue <id>"
# hacia la persona responsable.
# - Rama: crea autonomo/<YYYY-MM-DD-HHMM> desde {{RAMA_PRINCIPAL}} o reanuda la autonomo/... en la que está. Nunca hace
#   push ni merge: al acabar, la persona revisa la rama y decide.
# - Antes de cada ronda: árbol limpio y tools/auditoria/preparacion_ronda.sh N con 0.
# - Topes: la Cuota "<n> USD por ronda" de la cabecera del plan (coste estimado que da claude; cada sesión recibe lo
#   que queda con --max-budget-usd), DESPACHADOR_MAX_TURNOS y DESPACHADOR_TIEMPO_MAX por sesión. Un lote cuyo candado
#   del motor o de la build está ocupado se pospone al final de la ronda; si sigue ocupado, cuenta como intento fallido.
# - Parada: crea .parar en la raíz desde tu terminal (el lote en marcha acaba su ciclo); para seguir, bórralo y relanza.
# - Tras cada sesión, lo que quede sin commitear en rutas de su rol se copia a .despachador_logs/<ejecución>/sobras/ y
#   se deshace; lo de otros dueños se queda y va al resumen.
# - Registro en .despachador_logs/<ejecución>/ (se guardan las 10 últimas): salida JSON y stderr de cada sesión,
#   resumen.md e informe de la auditoría de proceso. En la terminal, una línea por sesión y el resumen.
# Variables: DESPACHADOR_CLAUDE (orden de claude; las pruebas usan tools/hooks/tests/claude_falso.sh),
#   DESPACHADOR_MAX_TURNOS (80), DESPACHADOR_TIEMPO_MAX (3600 s; luego TERM y, a los 30 s, KILL),
#   DESPACHADOR_MODELO (--model, opcional).
# Al arrancar comprueba que `claude --help` lista las opciones que usa (--max-turns no sale en la ayuda: no se mira).
# Códigos: 0 terminado (no queda nada lanzable; lo bloqueado va al resumen), 1 parado antes de acabar (cuota, .parar,
#   puerta de la ronda, árbol sucio al empezar una ronda o un commit del estado que falla), 2 no arranca (nivel, claude,
#   hooks, .gitignore, árbol sucio, cuota, .parar o rama), 64 uso incorrecto, 75 ya hay otro despachador en marcha.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGS=("$@")
uso() {
    echo "Uso: $0 [--ronda N] [--simular]" >&2
    [[ -n "${1:-}" ]] && echo "  $1" >&2
    exit 64
}
RONDA_INICIO="" SIMULAR=0
while (( $# )); do
    case "$1" in
        --ronda) [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || uso "--ronda necesita un entero >= 1."; RONDA_INICIO="$2"; shift 2 ;;
        --simular) SIMULAR=1; shift ;;
        *) uso "Argumento desconocido: '$1'." ;;
    esac
done
CLAUDE="${DESPACHADOR_CLAUDE:-claude}"
MAX_TURNOS="${DESPACHADOR_MAX_TURNOS:-80}"
TIEMPO_MAX="${DESPACHADOR_TIEMPO_MAX:-3600}"
MODELO="${DESPACHADOR_MODELO:-}"
[[ "$MAX_TURNOS" =~ ^[1-9][0-9]*$ ]] || uso "DESPACHADOR_MAX_TURNOS debe ser un entero >= 1 (hay '$MAX_TURNOS')."
[[ "$TIEMPO_MAX" =~ ^[1-9][0-9]*$ ]] || uso "DESPACHADOR_TIEMPO_MAX debe ser un entero >= 1 (segundos; hay '$TIEMPO_MAX')."

cd "$ROOT" || exit 2
# Roles, dueños de las rutas (y comprobación de bash 4+) y lectura de JSON
# shellcheck source=hooks/propiedad.sh
source tools/hooks/propiedad.sh
# shellcheck source=hooks/leer_json.sh
source tools/hooks/leer_json.sh

# --- Uno a la vez: todo corre dentro del candado "despachador" (otro despachador sale con 75) ---
if [[ "${_DESPACHADOR_CON_CANDADO:-}" != 1 ]]; then
    _DESPACHADOR_CON_CANDADO=1 exec "$ROOT/tools/locks/with_lock.sh" despachador coordinador \
        "$ROOT/tools/despachador.sh" ${ARGS[@]+"${ARGS[@]}"}
fi
unset _DESPACHADOR_CON_CANDADO

RAMA_PRINCIPAL="{{RAMA_PRINCIPAL}}"
ZONA="{{ZONA_HORARIA}}"
CANDADOS=(motor "{{CANDADO_BUILD}}")
ESPEC=docs/direccion/especificaciones.md
PLAN=docs/direccion/plan_nocturno.md
TABLON=docs/direccion/tablon.md
PENDIENTES=docs/direccion/pendientes_manana.md
ENTREGAR=./tools/hooks/entregar.sh
PUERTA=./tools/auditoria/preparacion_ronda.sh
LOGS_RAIZ=.despachador_logs
MAX_EJECUCIONES=10
# Permisos de cada sesión (ADR, §3.2): sin nadie que apruebe, la barrera son los hooks del proyecto
PERMITIDAS="Bash Read Grep Glob Edit Write NotebookEdit Agent(agente-ejecutor-lote) Agent(agente-ejecutor-mecanico) Agent(agente-buscador-lectura)"
PROHIBIDAS="WebFetch WebSearch Bash(./tools/despachador.sh*) Agent(Explore) Agent(general-purpose) Agent(Plan) Agent(claude)"
TERMINADO='^(hecho|entregado|validado|terminado|completado|cerrado)$'

# --- Utilidades ------------------------------------------------------------------------------
leer() { tr -d '\r' < "$1"; }
recortar() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
dice() { echo "[despachador] $*"; }
no_arranca() { echo "[despachador] No arranca: $*" >&2; exit 2; }
hora() {
    if [[ -e "/usr/share/zoneinfo/$ZONA" ]]; then TZ="$ZONA" date "${1:-+%Y-%m-%d %H:%M}"
    else date "${1:-+%Y-%m-%d %H:%M}"; fi
}
sin_barras() { local s="${1//|//}"; s="${s//$'\n'/ }"; printf '%s' "${s:0:${2:-160}}"; }
# Cuentas con decimales (bash solo tiene enteros); LC_ALL=C para que el separador decimal sea el punto
sumar() { LC_ALL=C awk -v a="$1" -v b="$2" 'BEGIN { printf "%.4f", a + b }'; }
quedan() { LC_ALL=C awk -v c="$CUOTA" -v g="$1" 'BEGIN { r = int((c - g) * 100 + 1e-6) / 100; printf "%.2f", (r > 0 ? r : 0) }'; }
positivo() { LC_ALL=C awk -v x="$1" 'BEGIN { exit !(x > 0) }'; }
usd() { LC_ALL=C awk -v x="$1" 'BEGIN { printf "%.2f", x }'; }

# --- Plan: lotes en su orden (L_ORDEN) y, por id, rol, ronda, ids de "tras X", texto, criterio, comando y estado ---
declare -A L_ROL=() L_RONDA=() L_TRAS=() L_TEXTO=() L_CRITERIO=() L_COMANDO=() L_ESTADO=()
L_ORDEN=()
cargar_plan() {
    local linea rol lote crit com est id
    L_ORDEN=(); L_ROL=(); L_RONDA=(); L_TRAS=(); L_TEXTO=(); L_CRITERIO=(); L_COMANDO=(); L_ESTADO=()
    while IFS= read -r linea; do
        linea="${linea//\\|/$'\x1f'}"   # "\|" escapado dentro de una celda
        IFS='|' read -r _ _ rol lote crit com est _ <<< "$linea"
        [[ "$lote" =~ \*\*([A-Za-z]+[0-9]+)\*\* ]] || continue
        id="${BASH_REMATCH[1]}"
        [[ -n "${L_ROL[$id]+x}" ]] && continue   # id repetido: vale la primera fila
        L_ORDEN+=("$id")
        L_ROL[$id]="$(recortar "$rol")"
        L_RONDA[$id]=""
        [[ "$lote" =~ \(ronda[[:space:]]+([0-9]+) ]] && L_RONDA[$id]="${BASH_REMATCH[1]}"
        L_TRAS[$id]=""
        [[ "$lote" =~ tras[[:space:]]+([^\)]*) ]] \
            && L_TRAS[$id]="$(grep -oE '[A-Za-z]+[0-9]+' <<< "${BASH_REMATCH[1]}" | tr '\n' ' ')"
        lote="${lote//\*\*/}"
        L_TEXTO[$id]="$(recortar "${lote//$'\x1f'//}")"
        L_CRITERIO[$id]="$(recortar "${crit//$'\x1f'/|}")"
        L_COMANDO[$id]="$(recortar "${com//$'\x1f'/|}")"
        est="$(recortar "${est,,}")"
        [[ "$est" == en_curso ]] && est="en curso"
        L_ESTADO[$id]="$est"
    done < <(leer "$PLAN" | grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|')
}
activo() { [[ "${L_ESTADO[$1]}" == pendiente || "${L_ESTADO[$1]}" == "en curso" ]]; }
# Lotes que van "tras" <id> (separados por espacios)
dependientes() {
    local x d out=""
    for x in "${L_ORDEN[@]}"; do for d in ${L_TRAS[$x]}; do [[ "$d" == "$1" ]] && out+=" $x"; done; done
    printf '%s' "${out# }"
}

# poner_estado <id> <estado>: cambia la celda Estado de la fila del lote (conserva CRLF y los "\|" de las celdas)
poner_estado() {
    local id="$1" est="$2" linea t cr hecho=0 tmp="$PLAN.despachador.$$"
    local -a c
    while IFS= read -r linea || [[ -n "$linea" ]]; do
        cr=""
        [[ "$linea" == *$'\r' ]] && { cr=$'\r'; linea="${linea%$'\r'}"; }
        if (( ! hecho )) && [[ "$linea" =~ ^\|[[:space:]]*[0-9]+[[:space:]]*\| ]]; then
            t="${linea//\\|/$'\x1f'}"
            IFS='|' read -r -a c <<< "$t"
            if (( ${#c[@]} >= 7 )) && [[ "${c[3]}" =~ \*\*([A-Za-z]+[0-9]+)\*\* && "${BASH_REMATCH[1]}" == "$id" ]]; then
                c[6]=" $est "
                t="$(IFS='|'; printf '%s' "${c[*]}")"
                [[ "$linea" == *'|' ]] && t+='|'
                linea="${t//$'\x1f'/\\|}"
                hecho=1
            fi
        fi
        printf '%s%s\n' "$linea" "$cr"
    done < "$PLAN" > "$tmp" && mv -f "$tmp" "$PLAN"
    L_ESTADO[$id]="$est"
}

# fila <qué> <destino> [rutas...]: fila de coordinador (con el plan como referencia) y commit de las rutas.
# Si falla, el despachador para: no sigue con el estado sin commitear.
fila() {
    local que destino="$2"
    que="$(sin_barras "$1" 200)"
    shift 2
    if "$ENTREGAR" coordinador "$que" "$PLAN" "$destino" ${1+-- "$@"} > /dev/null; then return 0; fi
    PARADA="no se pudo commitear «$que» (motivo arriba)"
    terminar 1
}

# pendiente <rol que pregunta> <pregunta> <opciones> <bloquea a>: entrada en pendientes_manana.md (sin commitear)
pendiente() {
    if [[ ! -f "$PENDIENTES" ]]; then
        printf '# Pendientes para la Persona Responsable (DUEÑO: coordinador)\n\n## Abiertos\n' > "$PENDIENTES"
    elif [[ -s "$PENDIENTES" && "$(tail -c1 "$PENDIENTES" | od -An -c | tr -d ' ')" != '\n' ]]; then
        echo >> "$PENDIENTES"
    fi
    printf '%s | %s | %s | %s | %s\n' "$(hora)" "$1" "$(sin_barras "$2" 300)" "$(sin_barras "$3")" "$(sin_barras "$4")" >> "$PENDIENTES"
}

# bloquear <id> <motivo> [<rol que pregunta> <pregunta> <opciones>]: estado `bloqueado` (con su pendiente si se da)
bloquear() {
    local id="$1" motivo="$2" deps
    poner_estado "$id" bloqueado
    deps="$(dependientes "$id")"
    if [[ -n "${3:-}" ]]; then
        pendiente "$3" "$4" "$5" "$id${deps:+ y lo que va tras él ($deps)}"
        fila "Estado $id: bloqueado ($motivo)" "persona responsable" "$PLAN" "$PENDIENTES"
    else
        fila "Estado $id: bloqueado ($motivo)" "persona responsable" "$PLAN"
    fi
    BLOQUEADOS+=("$id: $motivo")
    dice "  $id bloqueado: $motivo"
}

fallo() {  # fallo <id> <motivo>: intento fallido (cuenta para el tope; el estado no cambia)
    fila "Fallo $1: $2" "${L_ROL[$1]}"
    dice "  Fallo $1: $2"
}

pausar() {  # pausar <ronda> <motivo> <lote que sigue> [rutas...]: fila de pausa; luego, terminar 1
    local n="$1" motivo="$2" sigue="$3"
    shift 3
    PARADA="$motivo"
    fila "Pausa (ronda $n): $motivo; sigue ${sigue:-nada}" "persona responsable" "$@"
}

# --- Tablón: solo cuentan las filas que añade cada sesión -------------------------------------
lineas_tablon() { wc -l < "$TABLON" | tr -d ' '; }
huella_tablon() { head -n "$1" "$TABLON" | cksum; }
# Filas añadidas desde <líneas> (falla si cambió lo que ya había: la sesión cuenta como fallida)
filas_nuevas() {
    [[ "$(huella_tablon "$1")" == "$2" ]] || return 1
    tail -n "+$(( $1 + 1 ))" "$TABLON" | tr -d '\r' | grep -E '^[0-9]{4}-' || true
}
filas_tablon() { leer "$TABLON" | grep -E '^[0-9]{4}-' || true; }
# Entregas del lote <id> de <rol> (stdin): «qué» que empieza por el lote ("Lote A1: ...", "A1: ...", "N4/A1: ..."),
# la misma regla que auditoria_proceso.sh §4
filas_entrega() {
    awk -F' [|] ' -v r="$1" -v id="$2" '$2==r {
        q = $3; sub(/^Lote /, "", q)
        if (match(q, /^[A-Za-z]+[0-9]+(\/[A-Za-z]+[0-9]+)*/)) {
            n = split(substr(q, 1, RLENGTH), l, "/")
            for (i = 1; i <= n; i++) if (l[i] == id) { print; break }
        }
    }'
}
# Filas de <origen> (stdin) cuyo «qué» empieza por <prefijo> seguido de algo que no es letra ni cifra
filas_con() {
    awk -F' [|] ' -v r="$1" -v p="$2" '$2==r && index($3, p) == 1 { c = substr($3, length(p) + 1, 1); if (c !~ /[A-Za-z0-9]/) print }'
}
que_de() { awk -F' [|] ' '{ print $3 }' <<< "$1"; }
intentos_usados() {
    local t
    t="$(filas_tablon)"
    echo $(( $(filas_con auditor-calidad "Rechazo $1" <<< "$t" | grep -c .) + $(filas_con coordinador "Fallo $1" <<< "$t" | grep -c .) ))
}
# Motivo del último rechazo o fallo del lote (para el prompt del intento siguiente)
ultimo_motivo() {
    filas_tablon | awk -F' [|] ' -v r="Rechazo $1" -v f="Fallo $1" '
        ($2=="auditor-calidad" && index($3, r) == 1) { m = "auditor-calidad lo rechazó: " substr($3, length(r) + 3) }
        ($2=="coordinador" && index($3, f) == 1) { m = "falló: " substr($3, length(f) + 3) }
        END { print m }'
}

# --- Sesiones -------------------------------------------------------------------------------
prompt_rol() {  # <id> <intento>
    local id="$1" k="$2" r="${L_ROL[$1]}" m
    printf 'Eres %s. Tienes trabajo en el tablón: lote %s de la ronda %s (docs/direccion/plan_nocturno.md), intento %s.\n' \
        "$r" "$id" "${L_RONDA[$id]}" "$k"
    printf 'Lote: %s\nCriterio de hecho: %s\nComando de comprobación: %s\n' "${L_TEXTO[$id]}" "${L_CRITERIO[$id]}" "${L_COMANDO[$id]}"
    printf 'Trabajas sin nadie delante (nivel alto, normas §9). Empieza con ./tools/hooks/arranque_rol.sh %s, haz el lote, pasa su comando de comprobación y entrégalo con ./tools/hooks/entregar.sh %s "Lote %s: <resumen>" "<ruta o commit>" auditor-calidad -- <rutas>.\n' "$r" "$r" "$id"
    printf 'Si te surge una duda que §4 de la especificación no resuelve (compras, licencias o NDA, cambiar la visión o el alcance), entrega ./tools/hooks/entregar.sh %s "Duda %s: <pregunta>" "<ruta>" coordinador y termina. Nada de push, merge ni cambios de rama.\n' "$r" "$id"
    m="$(ultimo_motivo "$id")"
    [[ -n "$m" ]] && printf 'Intento anterior: %s\n' "$m"
}
prompt_auditor() {  # <id> <intento> <fila de la entrega>
    local id="$1" k="$2" r="${L_ROL[$1]}" ref
    ref="$(awk -F' [|] ' '{ print $4 }' <<< "$3")"
    printf 'Eres auditor-calidad. Tienes trabajo en el tablón: revisa el lote %s de la ronda %s (dueño: %s), intento %s. Entrega: «%s» (%s).\n' \
        "$id" "${L_RONDA[$id]}" "$r" "$k" "$(que_de "$3")" "$ref"
    printf 'Lote: %s\nCriterio de hecho: %s\nComando de comprobación: %s\n' "${L_TEXTO[$id]}" "${L_CRITERIO[$id]}" "${L_COMANDO[$id]}"
    printf 'Trabajas sin nadie delante (nivel alto, normas §9). Empieza con ./tools/hooks/arranque_rol.sh auditor-calidad, comprueba el criterio de hecho y pasa el comando de comprobación.\n'
    printf 'Si está bien: ./tools/hooks/entregar.sh auditor-calidad "Validado %s: <qué comprobaste>" "<commit>" coordinador. Si no: ./tools/hooks/entregar.sh auditor-calidad "Rechazo %s: <motivo>" "<ruta o commit>" %s. Solo una de las dos. Nada de push, merge ni cambios de rama.\n' "$id" "$id" "$r"
}

# sesion <rol> <prompt> <nombre> <tope USD>: lanza claude -p con el rol fijado y espera (vigilando el tiempo).
# Deja S_CODIGO, S_COSTE (el tope si no se sabe), S_TURNOS, S_TIPO, S_SEGUNDOS, S_AGOTADO y T_LINEAS/T_HUELLA (tablón
# antes de la sesión).
SESION_PID=""
sesion() {
    local rol="$1" prompt="$2" nombre="$3" tope="$4" pid t0 i coste="" tipo="" turnos="" leido=""
    local json="$LOGS/$nombre.json" err="$LOGS/$nombre.err"
    local -a a=(-p "$prompt" --permission-mode dontAsk --allowedTools "$PERMITIDAS" --disallowedTools "$PROHIBIDAS"
        --max-turns "$MAX_TURNOS" --max-budget-usd "$tope" --output-format json --no-session-persistence)
    [[ -n "$MODELO" ]] && a+=(--model "$MODELO")
    T_LINEAS="$(lineas_tablon)"
    T_HUELLA="$(huella_tablon "$T_LINEAS")"
    t0=$SECONDS S_AGOTADO=0
    CLAUDE_ROL="$rol" DESPACHADOR=1 "$CLAUDE" "${a[@]}" < /dev/null > "$json" 2> "$err" &
    pid=$!
    SESION_PID=$pid
    while kill -0 "$pid" 2>/dev/null; do
        if (( SECONDS - t0 >= TIEMPO_MAX )); then
            S_AGOTADO=1
            kill -TERM "$pid" 2>/dev/null
            for (( i = 0; i < 30; i++ )); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
            kill -KILL "$pid" 2>/dev/null
            break
        fi
        if (( SECONDS - t0 < 5 )); then sleep 0.2; else sleep 1; fi
    done
    wait "$pid"
    S_CODIGO=$?
    SESION_PID=""
    S_SEGUNDOS=$(( SECONDS - t0 ))
    { IFS= read -r -d '' coste; IFS= read -r -d '' tipo; IFS= read -r -d '' turnos; IFS= read -r -d '' leido; } \
        < <(campos_json total_cost_usd subtype num_turns < "$json" 2>/dev/null)
    [[ "$leido" == OK && "$coste" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || coste="$tope"
    S_COSTE="$coste" S_TIPO="$tipo" S_TURNOS="${turnos:-?}"
    GASTO="$(sumar "$GASTO" "$S_COSTE")"
}
# Por qué una sesión no dejó la fila esperada
motivo_sesion() {
    local m="$1"
    (( S_AGOTADO )) && m+="; tiempo agotado ($TIEMPO_MAX s)"
    [[ -n "$S_TIPO" && "$S_TIPO" != success ]] && m+="; $S_TIPO"
    (( S_CODIGO )) && m+="; código $S_CODIGO"
    printf '%s' "$m"
}
linea_sesion() {  # <id> <rol> <intento> <resultado>
    dice "$1 $2 intento $3: $4 · $S_TURNOS turnos · $(usd "$S_COSTE") USD · $(( (S_SEGUNDOS + 30) / 60 )) min"
}

# limpiar <rol> <sesión>: lo que quede sin commitear o sin seguimiento en rutas de <rol> se copia a sobras/<sesión>/
# y se deshace (con historia, vuelve a HEAD; nuevo, se borra). Lo de otros dueños se apunta en OTROS.
limpiar() {
    local rol="$1" dest="$LOGS/sobras/$2" e x ruta dueno n=0
    local -a rutas=()
    while IFS= read -r -d '' e; do
        x="${e:0:2}"
        rutas+=("${e:3}")
        if [[ "$x" == *R* || "$x" == *C* ]]; then IFS= read -r -d '' e && rutas+=("$e"); fi   # y la ruta de origen
    done < <(git status --porcelain -z --untracked-files=all)
    for ruta in ${rutas[@]+"${rutas[@]}"}; do
        dueno="$(dueno_de_ruta "$ruta")"
        if [[ "$dueno" != "$rol" ]]; then
            OTROS+=("$ruta (de ${dueno:-nadie}; tras $2)")
            continue
        fi
        if [[ -e "$ruta" ]]; then mkdir -p "$dest/$(dirname "$ruta")" && cp -p -- "$ruta" "$dest/$ruta"; fi
        if git cat-file -e "HEAD:$ruta" 2>/dev/null; then
            git restore --source=HEAD --staged --worktree -- "$ruta"
        else
            git rm -q --cached --ignore-unmatch -- "$ruta" > /dev/null
            rm -f -- "$ruta"
        fi
        n=$((n + 1))
    done
    (( n )) && dice "  $n archivo(s) sin commitear de $rol tras la sesión: copiados en ${dest#"$ROOT"/} y deshechos."
    return 0
}

# --- Un lote: ciclos (sesión del rol y, si entrega, de auditor-calidad) hasta hecho o bloqueado -------------
# Devuelve 0 para seguir con otro lote; para la ejecución (terminar 1) por cuota o .parar.
lote() {
    local id="$1" rol="${L_ROL[$1]}" n="${L_RONDA[$1]}" usados k tope nuevas entrega duda veredicto v nombre
    while :; do
        usados="$(intentos_usados "$id")"
        if (( usados >= MAX_INTENTOS )); then
            bloquear "$id" "$usados intentos sin validar, tope $MAX_INTENTOS" coordinador \
                "Lote $id bloqueado tras $usados intentos sin validar (tope $MAX_INTENTOS). Último: $(ultimo_motivo "$id")" \
                "rehacerlo con otro enfoque, cambiar su criterio o su comando en el plan, o sacarlo de la ronda"
            return 0
        fi
        if [[ -e .parar ]]; then pausar "$n" "parada con .parar" "$id"; terminar 1; fi
        tope="$(quedan "$GASTO")"
        if ! positivo "$tope"; then pausar "$n" "cuota de la ronda agotada ($(usd "$GASTO") de $CUOTA USD, estimado)" "$id"; terminar 1; fi
        k=$(( usados + 1 ))
        poner_estado "$id" "en curso"
        fila "Encargo $id (ronda $n, intento $k): ${L_TEXTO[$id]}" "$rol" "$PLAN"
        nombre="r${n}_${id}_${rol}_${k}"
        sesion "$rol" "$(prompt_rol "$id" "$k")" "$nombre" "$tope"
        entrega="" duda=""
        if nuevas="$(filas_nuevas "$T_LINEAS" "$T_HUELLA")"; then
            duda="$(filas_con "$rol" "Duda $id" <<< "$nuevas" | tail -n1)"
            entrega="$(filas_entrega "$rol" "$id" <<< "$nuevas" | tail -n1)"
        else
            S_TIPO="${S_TIPO:+$S_TIPO; }cambió el principio del tablón"
        fi
        if [[ -n "$duda" ]]; then linea_sesion "$id" "$rol" "$k" duda
        elif [[ -n "$entrega" ]]; then linea_sesion "$id" "$rol" "$k" entrega
        else linea_sesion "$id" "$rol" "$k" "$(motivo_sesion "sin fila")"; fi
        limpiar "$rol" "$nombre"
        if [[ -n "$duda" ]]; then
            v="$(que_de "$duda")"
            bloquear "$id" "duda de $rol" "$rol" "${v#"Duda $id"}" "responderla y pasar el lote a pendiente para relanzarlo"
            return 0
        fi
        if [[ -z "$entrega" ]]; then
            fallo "$id" "$(motivo_sesion "la sesión de $rol no dejó entrega ni duda")"
            continue
        fi
        # auditor-calidad: sin fila, se repite una vez
        veredicto=""
        for v in 1 2; do
            tope="$(quedan "$GASTO")"
            if ! positivo "$tope"; then pausar "$n" "cuota de la ronda agotada ($(usd "$GASTO") de $CUOTA USD, estimado) antes de revisar $id" "$id"; terminar 1; fi
            nombre="r${n}_${id}_auditor-calidad_${k}"
            (( v == 2 )) && nombre+="_b"
            sesion auditor-calidad "$(prompt_auditor "$id" "$k" "$entrega")" "$nombre" "$tope"
            nuevas=""
            filas_nuevas "$T_LINEAS" "$T_HUELLA" > /dev/null && nuevas="$(filas_nuevas "$T_LINEAS" "$T_HUELLA")"
            if [[ -n "$(filas_con auditor-calidad "Rechazo $id" <<< "$nuevas")" ]]; then veredicto=rechazo
            elif [[ -n "$(filas_con auditor-calidad "Validado $id" <<< "$nuevas")" ]]; then veredicto=validado; fi
            linea_sesion "$id" auditor-calidad "$k" "${veredicto:-$(motivo_sesion "sin fila")}"
            limpiar auditor-calidad "$nombre"
            [[ -n "$veredicto" ]] && break
        done
        case "$veredicto" in
            validado)
                poner_estado "$id" hecho
                fila "Estado $id: hecho" "persona responsable" "$PLAN"
                HECHOS+=("$id")
                return 0 ;;
            rechazo) ;;   # cuenta como intento: el bucle decide si hay otro
            *) fallo "$id" "auditor-calidad no dejó «Validado $id» ni «Rechazo $id» (2 sesiones)" ;;
        esac
    done
}

# --- Elección del siguiente lote de la ronda ----------------------------------------------------
# elegir <ronda>: ELEGIDO = primer lote `pendiente` o `en curso` con sus "tras X" terminados (los pospuestos, al
# final). Devuelve 2 si ha bloqueado un lote por dependencia (hay que releer el plan).
declare -A POSPUESTO=() ATASCADO=()
elegir() {
    local n="$1" id d bloq espera
    local -a listos=()
    ELEGIDO=""
    for id in "${L_ORDEN[@]}"; do
        [[ "${L_RONDA[$id]}" == "$n" && -z "${ATASCADO[$id]:-}" ]] && activo "$id" || continue
        bloq="" espera=0
        for d in ${L_TRAS[$id]}; do
            case "${L_ESTADO[$d]:-}" in
                bloqueado|rechazado) bloq="$d" ;;
                *) [[ "${L_ESTADO[$d]:-}" =~ $TERMINADO ]] || espera=1 ;;
            esac
        done
        if [[ -n "$bloq" ]]; then
            if (( SIMULAR )); then dice "Pasaría a bloqueado: $id (va tras $bloq, que está bloqueado)."; continue; fi
            bloquear "$id" "va tras $bloq, que está bloqueado"
            return 2
        fi
        (( espera )) || listos+=("$id")
    done
    for id in ${listos[@]+"${listos[@]}"}; do [[ -z "${POSPUESTO[$id]:-}" ]] && { ELEGIDO="$id"; return 0; }; done
    ELEGIDO="${listos[0]:-}"
    return 0
}
candado_ocupado() {  # imprime el primer candado (motor o build) ocupado
    local c e
    for c in "${CANDADOS[@]}"; do
        e="$(./tools/locks/with_lock.sh --estado "$c" 2>/dev/null)"
        [[ "${e%%|*}" == ocupado || "${e%%|*}" == dudoso ]] && { echo "$c"; return 0; }
    done
    return 1
}

# --- Resumen y salida -------------------------------------------------------------------------
LOGS="" PARADA="" GASTO=0 RAMA=""
HECHOS=() BLOQUEADOS=() OTROS=() SIN_LANZAR=() COSTES=()
lista() { if (( $# )); then printf '%s' "$1"; shift; (( $# )) && printf ', %s' "$@"; else printf 'ninguno'; fi; }
terminar() {
    local cod="$1" r a
    trap - INT TERM HUP
    if [[ -n "$LOGS" ]]; then
        r="$LOGS/resumen.md"
        a="$(./tools/auditoria/auditoria_proceso.sh --informe "$LOGS/auditoria_proceso.md" 2>&1 | head -n1)"
        a="${a#Auditoría de proceso: }"
        a="${a%% Informe*}"
        {
            printf '# Despachador: ejecución %s\n\n' "${LOGS##*/}"
            printf -- '- Rama: `%s` (desde `%s`)\n' "$RAMA" "$RAMA_PRINCIPAL"
            if (( cod == 0 )); then printf -- '- Resultado: terminado (no queda nada lanzable)\n'
            else printf -- '- Resultado: parado: %s\n' "$PARADA"; fi
            printf -- '- Coste estimado por ronda: %s\n' "$(lista ${COSTES[@]+"${COSTES[@]}"})"
            printf -- '- Hechos: %s\n' "$(lista ${HECHOS[@]+"${HECHOS[@]}"})"
            printf -- '- Bloqueados: %s\n' "$(lista ${BLOQUEADOS[@]+"${BLOQUEADOS[@]}"})"
            printf -- '- Sin lanzar: %s\n' "$(lista ${SIN_LANZAR[@]+"${SIN_LANZAR[@]}"})"
            printf -- '- Sin commitear en rutas de otros dueños: %s\n' "$(lista ${OTROS[@]+"${OTROS[@]}"})"
            printf -- '- Auditoría de proceso: %s (informe: `%s`)\n' "$a" "$LOGS_RAIZ/${LOGS##*/}/auditoria_proceso.md"
            printf -- '- Para revisar: `git log --oneline %s..%s`\n\n' "$RAMA_PRINCIPAL" "$RAMA"
            git log --oneline "$RAMA_PRINCIPAL..$RAMA" 2>/dev/null | head -n 30 | sed 's/^/    /'
        } > "$r"
        echo
        sed -n '3,12p' "$r"
        echo "Resumen completo: $LOGS_RAIZ/${LOGS##*/}/resumen.md"
    fi
    exit "$cod"
}
interrumpir() {
    [[ -n "$SESION_PID" ]] && kill -TERM "$SESION_PID" 2>/dev/null
    PARADA="interrumpido (señal); la sesión en marcha se ha parado y puede haber dejado cambios sin commitear"
    terminar "$1"
}

# --- Arranque ---------------------------------------------------------------------------------
[[ -f "$ESPEC" && -f "$PLAN" && -f "$TABLON" ]] || no_arranca "falta $ESPEC, $PLAN o $TABLON."
NIVEL="$(leer "$ESPEC" | sed -nE 's/^\*\*Nivel de autonomía:\*\*[[:space:]]*`([^`]*)`.*/\1/p' | head -n1)"
[[ "$NIVEL" == alto ]] || no_arranca "el nivel de autonomía es «${NIVEL:-ilegible}» ($ESPEC); el despachador es solo para el nivel alto (normas §9)."
AYUDA="$("$CLAUDE" --help 2>&1)" || no_arranca "no funciona «$CLAUDE --help» (¿está instalado claude? DESPACHADOR_CLAUDE cambia la orden)."
FALTAN=()
for O in --permission-mode --allowedTools --disallowedTools --max-budget-usd --output-format --no-session-persistence \
         ${MODELO:+--model}; do
    grep -q -- "$O" <<< "$AYUDA" || FALTAN+=("$O")
done
(( ${#FALTAN[@]} == 0 )) || no_arranca "«$CLAUDE --help» no tiene ${FALTAN[*]}: actualiza claude (sin ellas no hay topes ni permisos)."
[[ "$(git config core.hooksPath)" == tools/hooks ]] \
    || no_arranca "core.hooksPath no es tools/hooks (git config core.hooksPath tools/hooks): sin los hooks de git no hay guardas."
git check-ignore -q .parar && git check-ignore -q "$LOGS_RAIZ/x" \
    || no_arranca ".gitignore no ignora .parar y $LOGS_RAIZ/ (añádelos: actualizar.md)."
[[ -e .parar ]] && no_arranca "existe .parar: bórralo (rm .parar) para lanzar el despachador."
SUCIO="$(git status --porcelain --untracked-files=all)"
[[ -z "$SUCIO" ]] || no_arranca "el árbol no está limpio (cambios o archivos sin seguimiento; git status):"$'\n'"$(head -n 5 <<< "$SUCIO")"
C="$(leer "$PLAN" | sed -nE 's/.*\*\*Cuota:\*\*[[:space:]]*(.*)$/\1/p' | head -n1)"
C="$(recortar "$C")"
[[ "${C,,}" =~ ^([0-9]+([.,][0-9]+)?)[[:space:]]*usd[[:space:]]+por[[:space:]]+ronda ]] \
    || no_arranca "la Cuota de la cabecera del plan no tiene la forma «<n> USD por ronda» («${C:-vacía}»)."
CUOTA="${BASH_REMATCH[1]/,/.}"
positivo "$CUOTA" || no_arranca "la Cuota es 0 USD por ronda."
MAX_INTENTOS="$(leer "$ESPEC" | sed -nE 's/.*antes de `bloqueado`:[[:space:]]*([0-9]+).*/\1/p' | head -n1)"
[[ "$MAX_INTENTOS" =~ ^[1-9][0-9]*$ ]] || MAX_INTENTOS=3
RAMA="$(git symbolic-ref -q --short HEAD)" || no_arranca "HEAD no está en una rama."
NUEVA=""
if [[ "$RAMA" == "$RAMA_PRINCIPAL" ]]; then
    NUEVA="autonomo/$(hora +%Y-%m-%d-%H%M)"
    git show-ref -q --verify "refs/heads/$NUEVA" && no_arranca "ya existe la rama $NUEVA: espera un minuto o reanúdala (git switch $NUEVA)."
elif [[ "$RAMA" != autonomo/* ]]; then
    no_arranca "la rama es '$RAMA': lanza el despachador desde $RAMA_PRINCIPAL (crea autonomo/<fecha>) o desde una autonomo/... para reanudarla."
fi

cargar_plan
RONDAS=()
mapfile -t RONDAS < <(for id in "${L_ORDEN[@]}"; do [[ -n "${L_RONDA[$id]}" ]] && echo "${L_RONDA[$id]}"; done | sort -n -u)
# Primera ronda con lotes por hacer (desde --ronda, si se da)
primera_ronda() {
    local n id
    for n in ${RONDAS[@]+"${RONDAS[@]}"}; do
        [[ -n "$RONDA_INICIO" ]] && (( n < RONDA_INICIO )) && continue
        for id in "${L_ORDEN[@]}"; do [[ "${L_RONDA[$id]}" == "$n" ]] && activo "$id" && { echo "$n"; return 0; }; done
    done
    return 1
}

if (( SIMULAR )); then
    if [[ -n "$NUEVA" ]]; then dice "Crearía la rama $NUEVA desde $RAMA_PRINCIPAL."; else dice "Reanudaría la rama $RAMA."; fi
    N="$(primera_ronda)" || { dice "No hay lotes \`pendiente\` ni \`en curso\`${RONDA_INICIO:+ desde la ronda $RONDA_INICIO}: nada que lanzar."; exit 0; }
    "$PUERTA" "$N" || exit 1
    elegir "$N"
    [[ -n "$ELEGIDO" ]] || { dice "Ronda $N: ningún lote tiene sus dependencias terminadas."; exit 0; }
    C="$(candado_ocupado)" && dice "El candado «$C» está ocupado ahora: $ELEGIDO se pospondría."
    dice "Lanzaría $ELEGIDO (${L_ROL[$ELEGIDO]}), ronda $N, intento $(( $(intentos_usados "$ELEGIDO") + 1 )) de $MAX_INTENTOS;" \
        "cuota $CUOTA USD por ronda, $MAX_TURNOS turnos y $TIEMPO_MAX s por sesión."
    exit 0
fi

if [[ -n "$NUEVA" ]]; then
    git checkout -q -b "$NUEVA" || no_arranca "no se pudo crear la rama $NUEVA."
    RAMA="$NUEVA"
    dice "Rama $RAMA creada desde $RAMA_PRINCIPAL."
else
    dice "Reanudando la rama $RAMA."
fi
LOGS="$ROOT/$LOGS_RAIZ/$(hora +%Y-%m-%d_%H%M%S)_$$"
mkdir -p "$LOGS" || no_arranca "no se puede crear $LOGS."
mapfile -t VIEJAS < <(find "$LOGS_RAIZ" -mindepth 1 -maxdepth 1 -type d | sort)
for (( i = 0; i < ${#VIEJAS[@]} - MAX_EJECUCIONES; i++ )); do rm -rf -- "${VIEJAS[i]}"; done
trap 'interrumpir 130' INT
trap 'interrumpir 143' TERM
trap 'interrumpir 129' HUP

# --- Rondas -----------------------------------------------------------------------------------
for N in ${RONDAS[@]+"${RONDAS[@]}"}; do
    [[ -n "$RONDA_INICIO" ]] && (( N < RONDA_INICIO )) && continue
    cargar_plan
    HAY=0
    for id in "${L_ORDEN[@]}"; do [[ "${L_RONDA[$id]}" == "$N" ]] && activo "$id" && { HAY=1; break; }; done
    (( HAY )) || continue
    SUCIO="$(git status --porcelain --untracked-files=all)"
    if [[ -n "$SUCIO" ]]; then
        PARADA="árbol sucio al empezar la ronda $N: $(head -n 3 <<< "$SUCIO" | tr '\n' ' ')"
        terminar 1
    fi
    if ! SALIDA="$("$PUERTA" "$N" 2>&1)"; then
        FALTA="$(grep -m1 '^- ' <<< "$SALIDA" || head -n1 <<< "$SALIDA")"
        FALTA="${FALTA#- }"
        pendiente coordinador "Ronda $N sin lanzar: preparacion_ronda.sh $N no sale con 0 ($FALTA)" \
            "completar la especificación o el plan y relanzar ./tools/despachador.sh" "ronda $N"
        SIGUE=""
        for id in "${L_ORDEN[@]}"; do [[ "${L_RONDA[$id]}" == "$N" ]] && activo "$id" && { SIGUE="$id"; break; }; done
        pausar "$N" "la puerta de la ronda no está lista: $FALTA" "$SIGUE" "$PENDIENTES"
        terminar 1
    fi
    dice "Ronda $N: lista. Cuota $CUOTA USD (estimado), $MAX_INTENTOS intentos por lote."
    GASTO=0 POSPUESTO=() ATASCADO=()
    while :; do
        cargar_plan
        elegir "$N"
        (( $? == 2 )) && continue
        [[ -n "$ELEGIDO" ]] || break
        if C="$(candado_ocupado)"; then
            if [[ -z "${POSPUESTO[$ELEGIDO]:-}" ]]; then
                POSPUESTO[$ELEGIDO]=1
                dice "$ELEGIDO pospuesto al final de la ronda: el candado «$C» está ocupado."
                continue
            fi
            fallo "$ELEGIDO" "el candado «$C» seguía ocupado; no se lanzó la sesión"
            ATASCADO[$ELEGIDO]="candado $C ocupado"
            continue
        fi
        lote "$ELEGIDO"
    done
    COSTES+=("ronda $N: $(usd "$GASTO") de $CUOTA USD")
    cargar_plan
    for id in "${L_ORDEN[@]}"; do
        [[ "${L_RONDA[$id]}" == "$N" ]] && activo "$id" || continue
        SIN_LANZAR+=("$id (${ATASCADO[$id]:-va tras ${L_TRAS[$id]% }, sin terminar})")
    done
    # Una ronda con lotes sin lanzar no deja pasar a la siguiente: las rondas van en orden
    (( ${#SIN_LANZAR[@]} == 0 )) || break
done
terminar 0

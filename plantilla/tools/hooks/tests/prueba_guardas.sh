#!/usr/bin/env bash
# Prueba rápida de las guardas del sistema (commit-msg, pre-commit, pre_tool_guard.sh, guard_propiedad.sh,
# with_lock.sh en sus dos modos). Trabaja en un repo temporal con una copia de tools/: no toca el proyecto.
# Sin la orden flock (Git Bash, macOS sin Homebrew) se omiten las pruebas del modo flock.
# Uso: ./tools/hooks/tests/prueba_guardas.sh      (sale con 0 si todo pasa)

set -uo pipefail

RAIZ_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FALLOS=0 TOTAL=0

ok()   { TOTAL=$((TOTAL + 1)); echo "  OK    $1"; }
mal()  { TOTAL=$((TOTAL + 1)); FALLOS=$((FALLOS + 1)); echo "  FALLO $1"; sed 's/^/        /' "$TMP/salida" 2>/dev/null; }
espera_ok()    { local d="$1"; shift; if "$@" >"$TMP/salida" 2>&1; then ok "$d"; else mal "$d"; fi; }
espera_rechazo() {  # $2 = texto que debe salir en el mensaje de la guarda
    local d="$1" texto="$2"; shift 2
    if "$@" >"$TMP/salida" 2>&1; then mal "$d (se esperaba rechazo)"
    elif grep -q -- "$texto" "$TMP/salida"; then ok "$d"
    else mal "$d (rechazado por otro motivo)"; fi
}
espera_codigo() {  # $2 = código de salida esperado, $3 = texto que debe salir ("" = cualquiera)
    local d="$1" cod="$2" texto="$3" r; shift 3
    "$@" >"$TMP/salida" 2>&1; r=$?
    if (( r != cod )); then mal "$d (código $r, se esperaba $cod)"
    elif [[ -n "$texto" ]] && ! grep -q -- "$texto" "$TMP/salida"; then mal "$d (falta '$texto' en la salida)"
    else ok "$d"; fi
}
fila() { printf '%s | %s | prueba | ruta | auditor-calidad\n' "$(date "+%Y-%m-%d %H:%M")" "$1" >> docs/direccion/tablon.md; }

R="$TMP/repo"
mkdir -p "$R" && cd "$R" || exit 1
git init -q .
git config user.name prueba && git config user.email prueba@example.invalid
mkdir -p docs/direccion
cp -r "$RAIZ_SRC/tools" .
rm -f tools/locks/*.lock
printf '# tablón\n' > docs/direccion/tablon.md
echo plan > docs/direccion/plan_nocturno.md
git add -- tools docs && git commit -q -m "coordinador: base"
git config core.hooksPath tools/hooks

json_edit() { printf '{"session_id":"S1","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }
json_bash() { printf '{"session_id":"S1","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
edit()  { json_edit "$1" | env -u CLAUDE_ROL bash tools/hooks/guard_propiedad.sh; }
orden() { json_bash "$1" | env -u CLAUDE_ROL bash tools/hooks/pre_tool_guard.sh; }

echo "== Órdenes (hook PreToolUse)"
espera_rechazo "git add -A bloqueado" "Prohibido" orden "git add -A"
espera_rechazo "git add . bloqueado" "Prohibido" orden "git add ."
espera_rechazo "git commit -am bloqueado" "Prohibido" orden "git commit -am x"
espera_rechazo "git stash bloqueado" "Prohibido" orden "git stash"
espera_rechazo "git reset --hard bloqueado" "Prohibido" orden "cd /tmp && git reset --hard"
espera_ok "git commit por rutas permitido" orden "git commit -m 'x' -- docs/a.md"

echo "== Propiedad al editar (hook PreToolUse de Edit|Write)"
espera_rechazo "Edit sin rol declarado bloqueado" "Declara antes tu rol" edit "$R/docs/direccion/plan_nocturno.md"
espera_ok "arranque_rol.sh coordinador registra el rol" orden "./tools/hooks/fijar_rol.sh coordinador"
espera_ok "coordinador edita su plan" edit "$R/docs/direccion/plan_nocturno.md"
espera_rechazo "coordinador NO edita un hook (de arquitecto-sistemas)" "no de 'coordinador'" edit "$R/tools/hooks/pre-commit"
espera_rechazo "ruta sin dueño bloqueada" "no tiene dueño" edit "$R/sin_dueno/x.txt"
espera_ok "el tablón es de todos" edit "$R/docs/direccion/tablon.md"

echo "== Commits (pre-commit y commit-msg)"
echo cambio >> docs/direccion/plan_nocturno.md
espera_rechazo "commit sin fila del tablón rechazado" "debe ir en el mismo commit" \
    git commit -m "coordinador: plan" -- docs/direccion/plan_nocturno.md
fila coordinador
espera_rechazo "commit sin prefijo de rol rechazado" "debe empezar por" \
    git commit -m "plan" -- docs/direccion/plan_nocturno.md docs/direccion/tablon.md
espera_ok "commit propio con su fila aceptado" \
    git commit -m "coordinador: plan" -- docs/direccion/plan_nocturno.md docs/direccion/tablon.md
echo "# cambio" >> tools/hooks/pre-commit; fila coordinador
espera_rechazo "commit de ruta ajena rechazado" "no es dueño" \
    git commit -m "coordinador: toca un hook" -- tools/hooks/pre-commit docs/direccion/tablon.md
printf '%s | coordinador | prueba | ruta | auditor-calidad\n' "2000-01-01 00:00" >> docs/direccion/tablon.md
espera_rechazo "fila con hora inventada rechazada" "hora real" \
    git commit -m "arquitecto-sistemas: hook" -- tools/hooks/pre-commit docs/direccion/tablon.md

echo "== Candados"
CL=./tools/locks/with_lock.sh
# PID del comando que ejecuta el candado <nombre> (lo apunta with_lock.sh tras lanzarlo)
pid_comando() {
    local i h
    for (( i = 0; i < 50; i++ )); do
        h="$(cut -d: -f4 "tools/locks/$1.lock" 2>/dev/null)"
        [[ "$h" =~ ^[0-9]+$ ]] && { echo "$h"; return 0; }
        sleep 0.1
    done
    return 1
}
# Espera (máx. 5 s) a que un PID muera; un zombi sin recoger cuenta como muerto
esperar_muerte() {
    local i
    for (( i = 0; i < 50; i++ )); do
        kill -0 "$1" 2>/dev/null || return 0
        [[ "$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')" == Z* ]] && return 0
        sleep 0.1
    done
}
for MODO in pid flock; do
    if [[ "$MODO" == flock ]] && ! command -v flock >/dev/null 2>&1; then
        echo "  --    sin la orden flock: se omiten las pruebas del modo flock"
        continue
    fi
    export CANDADO_MODO="$MODO"
    L="c_$MODO"
    $CL "${L}1" arquitecto-sistemas sleep 1 & W=$!
    pid_comando "${L}1" >/dev/null
    espera_codigo "[$MODO] candado ocupado sale con aviso (código 75)" 75 "LOCK OCUPADO" $CL "${L}1" coordinador true
    wait "$W"
    espera_ok "[$MODO] candado libre ejecuta la orden" $CL "${L}1" coordinador true
    espera_codigo "[$MODO] devuelve el código del comando" 3 "" $CL "${L}1" coordinador bash -c 'exit 3'

    # 20 a la vez: nunca dos dentro (mkdir es atómico: si falla, había otro dentro)
    rm -rf "$TMP/dentro" "$TMP/doble" "$TMP/entraron"
    for _ in $(seq 20); do
        # shellcheck disable=SC2016
        $CL "${L}2" coordinador bash -c 'mkdir "$1" 2>/dev/null || echo x >> "$2"; echo x >> "$3"; sleep 1; rmdir "$1"' \
            _ "$TMP/dentro" "$TMP/doble" "$TMP/entraron" >/dev/null 2>&1 &
    done
    wait
    if [[ ! -s "$TMP/doble" && -s "$TMP/entraron" ]]; then ok "[$MODO] 20 a la vez: uno dentro ($(wc -l < "$TMP/entraron" | tr -d ' ') en total, nunca dos)"
    else : > "$TMP/salida"; mal "[$MODO] 20 a la vez: dos dentro a la vez o ninguno"; fi

    # kill -9 al envoltorio con el comando vivo: el candado dura lo que dure el comando
    $CL "${L}3" arquitecto-sistemas sleep 1.5 & W=$!
    H="$(pid_comando "${L}3")"
    kill -9 "$W"; wait "$W" 2>/dev/null
    espera_codigo "[$MODO] kill -9 al envoltorio: ocupado mientras viva el comando" 75 "LOCK OCUPADO" $CL "${L}3" coordinador true
    esperar_muerte "$H"
    espera_ok "[$MODO] ... y libre cuando el comando acaba" $CL "${L}3" coordinador true

    # PID de otro proceso vivo que arrancó después del candado (PID reciclado)
    sleep 5 & A=$!
    echo "otro:$A:$(( $(date +%s) - 86400 )):" > "tools/locks/${L}4.lock"
    if [[ "$MODO" == pid ]]; then
        if [[ "$(ps -o etime= -p $$ 2>/dev/null)" =~ [0-9]+:[0-9]+ ]]; then
            espera_codigo "[pid] PID reciclado (arrancó después del candado): huérfano reclamado" 0 "LOCK HUÉRFANO" \
                $CL "${L}4" coordinador true
        else  # ps sin "-o etime" (Git Bash): no se puede saber; candado viejo -> probable huérfano, no se roba
            espera_codigo "[pid] PID vivo en candado viejo sin poder saber su arranque: probable huérfano" 75 \
                "probable huérfano" $CL "${L}4" coordinador true
        fi
        echo "otro:$$:$(date +%s):" > "tools/locks/${L}5.lock"
        espera_codigo "[pid] PID vivo y anterior al candado: ocupado" 75 "LOCK OCUPADO" $CL "${L}5" coordinador true
        sleep 0 & P=$!; wait "$P"
        echo "otro:$P:$(date +%s):" > "tools/locks/${L}5.lock"
        espera_codigo "[pid] --estado de un candado con PID muerto: huérfano" 0 "^huerfano|" $CL --estado "${L}5"
    else
        espera_codigo "[flock] archivo con PID ajeno vivo pero sin flock: se adquiere" 0 "" $CL "${L}4" coordinador true
    fi
    kill "$A" 2>/dev/null; wait "$A" 2>/dev/null

    $CL "${L}6" arquitecto-sistemas sleep 1 & W=$!
    pid_comando "${L}6" >/dev/null
    espera_ok "[$MODO] ESPERA_CANDADO=3 espera a que se libere y entra" env ESPERA_CANDADO=3 $CL "${L}6" coordinador true
    wait "$W"
done
unset CANDADO_MODO

echo "== Resultado: $((TOTAL - FALLOS))/$TOTAL pruebas OK"
(( FALLOS == 0 ))

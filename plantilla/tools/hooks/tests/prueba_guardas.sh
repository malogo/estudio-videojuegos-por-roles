#!/usr/bin/env bash
# Prueba rápida de las guardas del sistema (commit-msg, pre-commit, pre_tool_guard.sh, guard_propiedad.sh,
# entregar.sh, with_lock.sh en sus dos modos y motor_silencioso.sh con un motor falso). Trabaja en un repo temporal con una copia de tools/: no toca el proyecto.
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
espera_rechazo "echo >> al tablón bloqueado" "entregar.sh" orden "echo x >> docs/direccion/tablon.md"
espera_rechazo "printf >tablón (sin espacio) bloqueado" "entregar.sh" orden "cd docs/direccion && printf x>tablon.md"
espera_rechazo "tee -a al tablón bloqueado" "entregar.sh" orden "echo x | tee -a docs/direccion/tablon.md"
espera_ok "leer el tablón permitido" orden "grep coordinador docs/direccion/tablon.md > /tmp/x"

echo "== Propiedad al editar (hook PreToolUse de Edit|Write)"
espera_rechazo "Edit sin rol declarado bloqueado" "Declara antes tu rol" edit "$R/docs/direccion/plan_nocturno.md"
espera_ok "arranque_rol.sh coordinador registra el rol" orden "./tools/hooks/fijar_rol.sh coordinador"
espera_ok "coordinador edita su plan" edit "$R/docs/direccion/plan_nocturno.md"
espera_rechazo "coordinador NO edita un hook (de arquitecto-sistemas)" "no de 'coordinador'" edit "$R/tools/hooks/pre-commit"
espera_rechazo "ruta sin dueño bloqueada" "no tiene dueño" edit "$R/sin_dueno/x.txt"
espera_rechazo "ni coordinador edita el tablón a mano (lo archiva un script)" "archivar_tablon.sh" edit "$R/docs/direccion/tablon.md"
espera_ok "fijar_rol.sh auditor-calidad" orden "./tools/hooks/fijar_rol.sh auditor-calidad"
espera_rechazo "otro rol NO edita el tablón a mano" "entregar.sh" edit "$R/docs/direccion/tablon.md"
espera_ok "fijar_rol.sh coordinador" orden "./tools/hooks/fijar_rol.sh coordinador"
espera_rechazo "commit como otro rol bloqueado (sesión coordinador)" "actúa como 'auditor-calidad'" \
    orden "git commit -m 'auditor-calidad: x' -- docs/a.md"
espera_rechazo "... también con -qm y git -C" "actúa como" orden "git -C . commit -qm 'auditor-calidad: x' -- docs/a.md"
espera_rechazo "entregar.sh como otro rol bloqueado" "actúa como" orden "./tools/hooks/entregar.sh auditor-calidad x y coordinador"
espera_rechazo "motor_silencioso.sh como otro rol bloqueado" "actúa como" orden "./tools/motor_silencioso.sh arquitecto-sistemas --import"
espera_ok "commit con el rol propio permitido" orden "git commit -m 'coordinador: x' -- docs/a.md"
espera_rechazo "orden bloqueada: no registra el rol que fijaba" "actúa como" \
    orden "./tools/hooks/fijar_rol.sh auditor-calidad && git commit -m 'arquitecto-sistemas: x' -- a"
espera_ok "... la sesión sigue siendo coordinador" orden "./tools/hooks/entregar.sh coordinador x y auditor-calidad"
espera_ok "fijar el rol y entregar como él en la misma orden" \
    orden "./tools/hooks/fijar_rol.sh auditor-calidad && ./tools/hooks/entregar.sh auditor-calidad x y coordinador"
espera_ok "fijar_rol.sh coordinador" orden "./tools/hooks/fijar_rol.sh coordinador"

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

echo "== Entregas (entregar.sh y origen de las filas)"
git checkout -q HEAD -- docs/direccion/tablon.md tools/hooks/pre-commit
EN=./tools/hooks/entregar.sh
filas_commit() { git show --format= -U0 HEAD -- "${1:-docs/direccion/tablon.md}" | grep -c '^+[0-9]'; }
espera_codigo "campo con '|' rechazado" 64 "no pueden llevar" $EN coordinador "a | b" "ruta" auditor-calidad
espera_codigo "destino inválido rechazado" 64 "Destino no válido" $EN coordinador "x" "ruta" nadie
# Escenario reproducido: A deja su fila sin commitear y B entrega
fila auditor-calidad
echo "plan B" >> docs/direccion/plan_nocturno.md
espera_codigo "B entrega con una fila ajena pendiente: entra y avisa" 0 "sin commitear" \
    $EN coordinador "plan nuevo" docs/direccion/plan_nocturno.md auditor-calidad -- docs/direccion/plan_nocturno.md
if [[ "$(filas_commit)" == 1 ]] && git show --format= HEAD -- docs/direccion/tablon.md | grep -q '^+.* | coordinador | plan nuevo |' \
    && git diff -U0 -- docs/direccion/tablon.md | grep -q '^+.* | auditor-calidad | prueba |'; then
    ok "... su commit lleva solo su fila; la de A sigue pendiente en el árbol"
else mal "el commit de B se llevó filas ajenas o perdió la de A"; fi
if [[ -z "$(git diff --cached --name-only)" ]]; then ok "... y el índice compartido queda limpio"
else git diff --cached --name-only > "$TMP/salida"; mal "el índice compartido quedó con cambios"; fi
espera_ok "A commitea después su fila sin problema" git commit -m "auditor-calidad: aviso" -- docs/direccion/tablon.md
fila auditor-calidad
espera_rechazo "commit con fila de otro origen rechazado" "origen no es" \
    git commit -m "coordinador: aviso" -- docs/direccion/tablon.md
git checkout -q HEAD -- docs/direccion/tablon.md
cp docs/direccion/tablon.md "$TMP/tablon"
echo "# cambio" >> tools/hooks/pre-commit
espera_codigo "entrega rechazada por un hook (ruta ajena)" 1 "no es dueño" \
    $EN coordinador "toca un hook" tools/hooks/pre-commit arquitecto-sistemas -- tools/hooks/pre-commit
if cmp -s docs/direccion/tablon.md "$TMP/tablon"; then ok "... y el tablón queda como estaba"; else mal "el tablón no se restauró"; fi
git checkout -q HEAD -- tools/hooks/pre-commit
echo nuevo > tools/auditoria/nuevo.txt
espera_codigo "archivo nuevo entregado con --cuerpo" 0 "Entregado" $EN auditor-calidad "informe" tools/auditoria/nuevo.txt \
    coordinador --cuerpo "encargo: agente-ejecutor-lote | high | a la primera: sí" -- tools/auditoria/nuevo.txt
if git ls-files --error-unmatch tools/auditoria/nuevo.txt >/dev/null 2>&1 && git log -1 --format=%b | grep -q "^encargo:"; then
    ok "... el archivo y el cuerpo van en el commit"; else mal "falta el archivo nuevo o el cuerpo en el commit"; fi
espera_codigo "--nube escribe en entregas_nube/<lote>.txt" 0 "Entregado" $EN coordinador "desde la nube" x coordinador --nube L7
if [[ "$(filas_commit docs/direccion/entregas_nube/L7.txt)" == 1 ]] && ! git show --format= --name-only HEAD | grep -q tablon.md; then
    ok "... y no toca el tablón"; else mal "--nube tocó el tablón o no dejó su fila"; fi
$EN auditor-calidad "lote de la nube" x coordinador --nube L8 >/dev/null 2>&1
./tools/hooks/volcar_entregas_nube.sh >/dev/null 2>&1
espera_ok "volcado de entregas_nube por coordinador aceptado (filas de otro origen)" git commit -m "coordinador: vuelca" \
    -- docs/direccion/tablon.md docs/direccion/entregas_nube/L7.txt docs/direccion/entregas_nube/L8.txt
ANTES=$(git rev-list --count HEAD)
$EN coordinador "a la vez 1" x auditor-calidad >"$TMP/e1" 2>&1 & E1=$!
$EN auditor-calidad "a la vez 2" x coordinador >"$TMP/e2" 2>&1 & E2=$!
wait "$E1"; R1=$?; wait "$E2"; R2=$?
if (( R1 == 0 && R2 == 0 )) && (( $(git rev-list --count HEAD) == ANTES + 2 )) && git diff --quiet HEAD -- docs/direccion/tablon.md; then
    ok "dos entregas a la vez: entran las dos, una detrás de otra"
else cat "$TMP/e1" "$TMP/e2" > "$TMP/salida"; mal "dos entregas a la vez (códigos $R1 y $R2)"; fi
: > "$(git rev-parse --git-path index.lock)"
espera_codigo ".git/index.lock que no se va: no entrega y no lo borra" 75 "index.lock" $EN coordinador "x" x auditor-calidad
if [[ -e "$(git rev-parse --git-path index.lock)" ]]; then ok "... y el index.lock sigue ahí"; else mal "entregar.sh borró index.lock"; fi
rm -f "$(git rev-parse --git-path index.lock)"

echo "== Archivado del tablón (archivar_tablon.sh)"
AR=./tools/hooks/archivar_tablon.sh
mapfile -t ROLES_P < <(bash -c 'source tools/hooks/propiedad.sh; printf "%s\n" "${ROLES_VALIDOS[@]}"')
memorias() {  # memorias <vaciado de todos> [<rol> <vaciado propio>]
    local r v
    for r in "${ROLES_P[@]}"; do
        v="$1"; [[ "$r" == "${2:-}" ]] && v="$3"
        printf '# Memoria\n**Último vaciado:** %s | **Último commit:** `x`\n' "$v" > "docs/direccion/roles/memoria_$r.md"
    done
}
mkdir -p docs/direccion/roles
git checkout -q HEAD -- docs/direccion/tablon.md
T=docs/direccion/tablon.md
{ grep '^#' $T; for d in "2000-01-01 00:00" "2000-01-02 00:00" "2000-01-03 10:00" "2000-01-04 00:00"; do
    printf '%s | coordinador | viejo %s | x | auditor-calidad\n' "$d" "${d:8:2}"; done; grep -vE '^(#|$)' $T; } > "$TMP/viejo"
# Las filas viejas no pasan la hora real de pre-commit: se meten en HEAD sin hooks (solo para preparar la prueba)
cp "$TMP/viejo" $T
git commit -q --no-verify -m "coordinador: filas viejas" -- docs/direccion/tablon.md
N_ANTES=$(grep -cE '^[0-9]{4}-' docs/direccion/tablon.md)
memorias "2000-01-05 00:00" auditor-calidad "2000-01-03 12:00"
espera_codigo "solo coordinador archiva" 64 "Solo coordinador" $AR auditor-calidad
espera_codigo "--simular: 3 filas anteriores al vaciado más antiguo" 0 "se moverían 3 de $N_ANTES" $AR coordinador --simular --dejar 2
printf 'sin fecha\n' > "docs/direccion/roles/memoria_${ROLES_P[1]}.md"
espera_codigo "memoria ilegible: no archiva nada" 1 "no se puede leer" $AR coordinador --dejar 2
memorias "2000-01-05 00:00" auditor-calidad "2000-01-03 12:00"
fila coordinador
espera_codigo "tablón con una entrega a medias: no toca nada" 75 "sin commitear" $AR coordinador --dejar 2
git checkout -q HEAD -- docs/direccion/tablon.md
espera_codigo "archiva las 3 filas viejas con su propio commit" 0 "Archivado" $AR coordinador --dejar 2
ARCH="docs/direccion/archivo/tablon_$(date +%Y-%m-%d).md"
if ! grep -q "viejo 0[123]" docs/direccion/tablon.md && grep -q "viejo 04" docs/direccion/tablon.md \
    && [[ "$(grep -c '^2000' "$ARCH")" == 3 ]] && git diff --quiet HEAD -- docs/direccion/tablon.md "$ARCH" \
    && git log -1 --format=%s | grep -q "^coordinador: archiva 3 filas"; then
    ok "... la fila del 04 (posterior al corte) se queda; el archivo y el commit llevan las otras"
else git log -1 --stat > "$TMP/salida"; mal "archivado incorrecto"; fi
memorias "2999-01-01 00:00"
espera_codigo "con todos al día se dejan las N últimas" 0 "Archivado" $AR coordinador --dejar 2
if [[ "$(grep -cE '^[0-9]{4}-' docs/direccion/tablon.md)" == 2 && "$(grep -c '^2000' "$ARCH")" == 4 ]]; then
    ok "... quedan 2 filas y el archivo del día se amplía"; else mal "no se dejaron las 2 últimas"; fi
espera_codigo "nada más que archivar -> 0" 0 "Nada que archivar" $AR coordinador --dejar 2
rm -f docs/direccion/roles/memoria_*.md

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

echo "== Motor (motor_silencioso.sh con tools/hooks/tests/motor_falso.sh)"
export MOTOR_BIN="$R/tools/hooks/tests/motor_falso.sh"
MS=./tools/motor_silencioso.sh
espera_codigo "patrón de errores del despliegue válido; sin errores -> 0" 0 "Resultado: 0" \
    env MOTOR_FALSO_TEXTO="todo bien" $MS auditor-calidad
if grep -q "AVISO" "$TMP/salida"; then mal "el patrón de errores del despliegue da aviso"; fi
export MOTOR_REGEX_ERRORES='^(USER )?(SCRIPT )?ERROR:'
ERRORES_GODOT='SCRIPT ERROR: Parse Error: Identifier "x" not declared in the current scope.
   at: GDScript::reload (res://tools/motor_silencioso.sh:3)
ERROR: Failed loading resource: docs/direccion/plan_nocturno.md.'
espera_codigo "SCRIPT ERROR con el motor en 0 -> 65" 65 "Resultado: 65" env MOTOR_FALSO_TEXTO="$ERRORES_GODOT" $MS auditor-calidad
if grep -q "arquitecto-sistemas: 1 · tools/motor_silencioso.sh" "$TMP/salida" \
    && grep -q "coordinador: 1 · docs/direccion/plan_nocturno.md" "$TMP/salida"; then
    ok "... atribuido a arquitecto-sistemas (res://, en la línea at:) y a coordinador (ruta relativa)"
else mal "errores mal atribuidos a su dueño"; fi
cp tools/auditoria/ruido_motor.txt "$TMP/ruido"
printf '^SCRIPT ERROR: Parse Error\tprueba\n^ERROR: Failed loading resource: docs/\tprueba\n' >> tools/auditoria/ruido_motor.txt
espera_codigo "mismos errores listados en ruido_motor.txt -> 0" 0 "2 silenciados" env MOTOR_FALSO_TEXTO="$ERRORES_GODOT" $MS auditor-calidad
cp "$TMP/ruido" tools/auditoria/ruido_motor.txt
espera_codigo "motor que sale con 2 -> 2" 2 "Resultado: 2" env MOTOR_FALSO_CODIGO=2 $MS auditor-calidad
espera_codigo "5.000 líneas de error -> 65 con resumen corto" 65 "15 primeros de 5000" env MOTOR_FALSO_LINEAS=5000 $MS auditor-calidad
if (( $(wc -l < "$TMP/salida") <= 25 )); then ok "... y el resumen cabe en 25 líneas ($(wc -l < "$TMP/salida" | tr -d ' '))"
else mal "el resumen pasa de 25 líneas"; fi
echo previo > tools/hooks/previo.uid  # cambio de antes de lanzar el motor: no es suyo
espera_codigo "el motor crea archivos versionables -> mismo código (0)" 0 "creado/cambiado 3 archivo" \
    env MOTOR_FALSO_CREA="tools/hooks/x.gd.uid tools/hooks/y.gd.uid tools/auditoria/ruido_motor.txt" $MS auditor-calidad
if grep -q "arquitecto-sistemas: 2 (no los reviertas" "$TMP/salida" && grep -q "auditor-calidad: 1 (tuyos" "$TMP/salida" \
    && ! grep -q "previo.uid" "$TMP/salida" && ! grep -q "^  .*motor_logs" "$TMP/salida"; then
    ok "... listados por dueño (ajenos y tuyos), sin lo previo ni los logs"
else mal "efectos colaterales mal listados"; fi
espera_codigo "sin efectos colaterales no se avisa" 0 "Resultado: 0" $MS auditor-calidad
if grep -q "creado/cambiado" "$TMP/salida"; then mal "avisa de efectos colaterales que no hay"; fi
rm -f tools/hooks/x.gd.uid tools/hooks/y.gd.uid tools/hooks/previo.uid; git checkout -q -- tools/auditoria/ruido_motor.txt
$CL motor arquitecto-sistemas sleep 1 & W=$!
pid_comando motor >/dev/null
espera_codigo "candado del motor ocupado -> 75" 75 "LOCK OCUPADO" $MS auditor-calidad
wait "$W"
for i in $(seq 40); do : > ".motor_logs/2000-01-01_0000$(printf '%02d' "$i")_viejo.log"; done
$MS auditor-calidad >/dev/null 2>&1
N_LOGS=$(find .motor_logs -name '*.log' | wc -l | tr -d ' ')
if (( N_LOGS == 30 )); then ok "se guardan los 30 últimos logs"; else : > "$TMP/salida"; mal "se guardan $N_LOGS logs (se esperaban 30)"; fi
unset MOTOR_BIN MOTOR_REGEX_ERRORES

echo "== Resultado: $((TOTAL - FALLOS))/$TOTAL pruebas OK"
(( FALLOS == 0 ))

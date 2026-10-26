#!/usr/bin/env bash
# Prueba rápida de las guardas del sistema (commit-msg, pre-commit, pre_tool_guard.sh, guard_propiedad.sh,
# entregar.sh, with_lock.sh en sus dos modos y motor_silencioso.sh con un motor falso). Trabaja en un repo temporal con una copia de tools/: no toca el proyecto.
# Sin la orden flock (Git Bash, macOS sin Homebrew) se omiten las pruebas del modo flock.
# Uso: ./tools/hooks/tests/prueba_guardas.sh      (sale con 0 si todo pasa)

set -uo pipefail

RAIZ_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=../requisitos.sh
source "$RAIZ_SRC/tools/hooks/requisitos.sh"
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
orden() { json_bash "$1" | env -u CLAUDE_ROL -u DESPACHADOR bash tools/hooks/pre_tool_guard.sh; }
orden_despachador() { json_bash "$1" | env -u CLAUDE_ROL DESPACHADOR=1 bash tools/hooks/pre_tool_guard.sh; }  # sesión del despachador

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
espera_rechazo "git commit --amend bloqueado (el último commit puede ser de otra sesión)" "amend" orden "git commit --amend --no-edit"
espera_rechazo "... también abreviado (--amen)" "amend" orden "git commit --amen -m x"
espera_rechazo "--no-verify abreviado (--no-veri) bloqueado" "no-verify" orden "git commit --no-veri -m x -- a"
espera_rechazo "git reset --har (abreviatura de --hard) bloqueado" "hard" orden "git reset --har"
espera_rechazo "git reset HEAD~1 (mueve la rama) bloqueado" "mueve la rama" orden "git reset HEAD~1"
espera_rechazo "... también con -- sin rutas detrás" "mueve la rama" orden "git reset HEAD~1 --"
espera_rechazo "git reset --soft bloqueado" "soft" orden "git reset --soft HEAD~1"
espera_rechazo "git checkout de una carpeta bloqueado" "todo lo que abarca" orden "git checkout HEAD -- docs/"
espera_rechazo "git restore de una carpeta bloqueado" "todo lo que abarca" orden "git restore -s HEAD -- tools"
espera_rechazo "git restore con comodín bloqueado" "todo lo que abarca" orden "git restore 'tools/*.sh'"
espera_rechazo "git checkout -f bloqueado" "descarta los cambios" orden "git checkout -f main"
espera_rechazo "git switch --discard-changes bloqueado" "descarta los cambios" orden "git switch --discard-changes main"
espera_ok "git reset -- <ruta> (sacar del índice) permitido" orden "git reset -- docs/a.md"
espera_ok "git reset <archivo> permitido" orden "git reset docs/direccion/tablon.md"
espera_ok "git checkout HEAD -- <archivo> permitido" orden "git checkout HEAD -- docs/direccion/plan_nocturno.md"
espera_ok "git restore --staged <carpeta> (solo el índice) permitido" orden "git restore --staged docs/"
espera_ok "git checkout -b <rama> permitido" orden "git checkout -b nueva"
# Lanzadores del motor de este despliegue (su ejecutable por defecto en motor_silencioso.sh), si tiene motor que vigilar
BIN_MOTOR="$(sed -n 's/^MOTOR_BIN="\${MOTOR_BIN:-\(.*\)}"$/\1/p' tools/motor_silencioso.sh)"
# shellcheck disable=SC2016
if [[ -n "$BIN_MOTOR" ]] && bash -c 'source tools/hooks/reglas_comando.sh; _es_motor "$1"' _ "$BIN_MOTOR"; then
    espera_rechazo "flatpak run del motor bloqueado" "motor" orden "flatpak run org.ejemplo.$BIN_MOTOR --path ."
    espera_rechazo "open -a del motor (macOS) bloqueado" "motor" orden "open -a /Applications/$BIN_MOTOR.app --args --path ."
fi
espera_ok "flatpak run de otro programa permitido" orden "flatpak run org.gimp.GIMP"
# .parar (interruptor de parada del despachador): solo lo crea o lo borra la persona responsable
espera_rechazo "rm .parar bloqueado" ".parar" orden "rm -f ./.parar"
espera_rechazo "touch .parar bloqueado" ".parar" orden "touch .parar"
espera_rechazo "mv .parar bloqueado" ".parar" orden "mv .parar /tmp/x"
espera_rechazo "echo > .parar bloqueado" ".parar" orden "echo x > .parar"
espera_rechazo "tee .parar bloqueado" ".parar" orden "echo x | tee .parar"
espera_ok "leer .parar permitido" orden "cat .parar"
# Sesiones del despachador (DESPACHADOR=1): sin publicar, fusionar ni cambiar de rama, ni otro despachador
espera_ok "git push sin DESPACHADOR no lo bloquea esta regla" orden "git push origin x"
espera_rechazo "git push con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "git push origin x"
espera_rechazo "git -C . push tras cd con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "cd docs && git -C .. push"
espera_rechazo "git pull con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "git pull"
espera_rechazo "git merge con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "git merge main"
espera_rechazo "git rebase con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "git rebase main"
espera_rechazo "git switch con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "git switch main"
espera_rechazo "git checkout -qb con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "git checkout -qb nueva"
espera_rechazo "git checkout --orphan con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "git checkout --orphan nueva"
espera_ok "git checkout HEAD -- <archivo> con DESPACHADOR=1 permitido" orden_despachador "git checkout HEAD -- docs/direccion/plan_nocturno.md"
espera_rechazo "git branch <nueva> con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "git branch nueva"
espera_rechazo "git branch -D con DESPACHADOR=1 bloqueado" "DESPACHADOR=1" orden_despachador "git branch -D x"
espera_ok "git branch --show-current con DESPACHADOR=1 permitido" orden_despachador "git branch --show-current"
espera_ok "git branch -a -v con DESPACHADOR=1 permitido" orden_despachador "git branch -a -v"
espera_ok "git branch --list <patrón> con DESPACHADOR=1 permitido" orden_despachador "git branch --list autonomo/*"
espera_rechazo "lanzar el despachador con DESPACHADOR=1 bloqueado" "despachador" orden_despachador "./tools/despachador.sh --simular"
espera_rechazo "bash tools/despachador.sh con DESPACHADOR=1 bloqueado" "despachador" orden_despachador "bash tools/despachador.sh"
espera_ok "leer el despachador con DESPACHADOR=1 permitido" orden_despachador "grep ronda tools/despachador.sh"

echo "== Propiedad al editar (hook PreToolUse de Edit|Write)"
espera_rechazo "Edit sin rol declarado bloqueado" "Declara antes tu rol" edit "$R/docs/direccion/plan_nocturno.md"
espera_ok "arranque_rol.sh coordinador registra el rol" orden "./tools/hooks/fijar_rol.sh coordinador"
espera_ok "coordinador edita su plan" edit "$R/docs/direccion/plan_nocturno.md"
espera_rechazo "coordinador NO edita un hook (de arquitecto-sistemas)" "no de 'coordinador'" edit "$R/tools/hooks/pre-commit"
espera_rechazo "ruta sin dueño bloqueada" "no tiene dueño" edit "$R/sin_dueno/x.txt"
espera_rechazo "ruta con .. que sale de una carpeta propia: cuenta su destino real" "no de 'coordinador'" \
    edit "$R/docs/direccion/archivo/../../../tools/hooks/pre-commit"
mkdir -p "$TMP/sin_realpath" && printf '#!/bin/sh\nexit 1\n' > "$TMP/sin_realpath/realpath" && chmod +x "$TMP/sin_realpath/realpath"
espera_rechazo "... también sin realpath -m (macOS)" "no de 'coordinador'" \
    env PATH="$TMP/sin_realpath:$PATH" bash -c "$(declare -f json_edit edit); edit '$R/docs/direccion/archivo/../../../tools/hooks/pre-commit'"
espera_rechazo "Edit dentro de .git bloqueado (core.hooksPath)" "dentro de .git" edit "$R/.git/config"
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
mkdir -p docs/direccion/roles
printf '# Memoria\n**Último vaciado:** 2000-01-01 00:00\n' > docs/direccion/roles/memoria_coordinador.md
printf '# Memoria\n**Último vaciado:** 2000-01-01 00:00\n' > docs/direccion/roles/memoria_auditor-calidad.md
git add -- docs/direccion/roles/memoria_coordinador.md docs/direccion/roles/memoria_auditor-calidad.md
espera_ok "commit de la propia memoria sin fila del tablón aceptado" \
    git commit -m "coordinador: memoria" -- docs/direccion/roles/memoria_coordinador.md
espera_rechazo "... pero no la memoria de otro rol" "no es dueño" \
    git commit -m "coordinador: memoria ajena" -- docs/direccion/roles/memoria_auditor-calidad.md
git rm -q --cached -- docs/direccion/roles/memoria_auditor-calidad.md

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

echo "== Saltarse los hooks de git (hook PreToolUse)"
espera_rechazo "git commit -n bloqueado" "no-verify" orden "git commit -n -m x -- a"
espera_rechazo "git commit --no-verify bloqueado" "no-verify" orden "git commit --no-verify -m x -- a"
espera_rechazo "git -c core.hooksPath=... bloqueado" "core.hooksPath" orden "git -c core.hooksPath=/dev/null commit -m x -- a"
espera_rechazo "git -c core.hooksPath (sin valor) bloqueado" "core.hooksPath" orden "git -c core.hooksPath commit -m x -- a"
espera_rechazo "git config core.hooksPath '' bloqueado" "core.hooksPath" orden "git config core.hooksPath ''"
espera_rechazo "GIT_CONFIG_COUNT=... delante bloqueado" "GIT_CONFIG_COUNT" orden "GIT_CONFIG_COUNT=1 git commit -m x -- a"
espera_ok "GIT_CONFIG_NOSYSTEM=1 delante permitido" orden "GIT_CONFIG_NOSYSTEM=1 git status"
espera_ok "git config core.hooksPath tools/hooks permitido" orden "git config core.hooksPath tools/hooks"
espera_ok "git config --get core.hooksPath permitido" orden "git config --get core.hooksPath"
espera_rechazo "export GIT_CONFIG_COUNT=... bloqueado" "GIT_CONFIG_COUNT" \
    orden "export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null; git commit -m x -- a"
espera_rechazo "\$env:GIT_CONFIG_COUNT (PowerShell) bloqueado" "GIT_CONFIG_COUNT" orden '$Env:GIT_CONFIG_COUNT = 1'
espera_ok "export PATH=... permitido" orden "export PATH=/x:/y"
espera_rechazo "git config include.path bloqueado" "include.path" orden "git config include.path /tmp/x.cfg"
espera_rechazo "git config core.hooksPath get (el valor \"get\" no es leer) bloqueado" "core.hooksPath" orden "git config core.hooksPath get"
espera_rechazo "git -c include.path=... bloqueado" "core.hooksPath" orden "git -c include.path=/tmp/x commit -m x -- a"
espera_rechazo ">> .git/config bloqueado" "configuración de git" orden "echo x >> .git/config"
espera_rechazo "tee .git/config bloqueado" "configuración de git" orden "echo x | tee -a .git/config"

echo "== Guardas que fallan cerradas (sin python ni node que funcionen)"
mkdir -p "$TMP/roto"
for b in python python3 node; do printf '#!/bin/sh\nexit 1\n' > "$TMP/roto/$b"; chmod +x "$TMP/roto/$b"; done
espera_rechazo "Edit bloqueado si no se puede leer la llamada" "No se pudo leer" \
    env PATH="$TMP/roto:$PATH" bash -c "$(declare -f json_edit edit); edit '$R/docs/direccion/plan_nocturno.md'"
espera_rechazo "Bash bloqueado si no se puede leer la llamada" "No se pudo leer" \
    env PATH="$TMP/roto:$PATH" bash -c "$(declare -f json_bash orden); orden 'ls'"
espera_ok "orden con tildes permitida (JSON en UTF-8)" orden "echo canción y añadido"

echo "== Contexto (línea de estado, aviso al llegar cada mensaje e inicio de sesión)"
json_estado() { printf '{"session_id":"%s","context_window":{"total_input_tokens":%s,"context_window_size":%s}}' "$1" "$2" "${3:-1000000}"; }
estado() { json_estado "$@" | env -u CLAUDE_ROL bash tools/hooks/linea_estado.sh; }
aviso()  { printf '{"session_id":"%s","prompt":"hola"}' "$1" | env -u CLAUDE_ROL bash tools/hooks/aviso_contexto.sh; }
inicio() { printf '{"session_id":"%s","source":"%s"}' "$1" "$2" | env -u CLAUDE_ROL bash tools/hooks/inicio_sesion.sh; }
sin_salida() { local d="$1"; shift; if "$@" >"$TMP/salida" 2>&1 && [[ ! -s "$TMP/salida" ]]; then ok "$d"; else mal "$d"; fi; }
espera_codigo "línea de estado: rol y contexto" 0 "coordinador · contexto 260k/1000k (26 %)" estado S1 260000
espera_codigo "desde 250k: aviso de vaciado en el siguiente mensaje" 0 "AVISO DE VACIADO" aviso S1
if grep -q "no te vacíes tú" "$TMP/salida"; then ok "... y al coordinador le dice que no se vacíe solo"; else mal "aviso sin la excepción del coordinador"; fi
estado S1 160000 >/dev/null
espera_codigo "desde 150k: aviso informativo" 0 "INFO CONTEXTO" aviso S1
sin_salida "... una sola vez" aviso S1
estado S1 1000 >/dev/null
sin_salida "con poco contexto no avisa" aviso S1
sin_salida "sesión sin dato de contexto: no avisa ni falla" aviso S-sin-dato
estado S2 170000 200000 >/dev/null
espera_codigo "ventana de 200k: el aviso de vaciado salta al 80 %" 0 "AVISO DE VACIADO" aviso S2
espera_codigo "inicio tras /compact: recuerda el rol registrado" 0 "rol 'coordinador'" inicio S1 compact
estado S1 260000 >/dev/null; inicio S1 clear >/dev/null
sin_salida "... y tras /clear olvida el contexto apuntado" aviso S1
espera_codigo "inicio de una sesión sin rol: que lo pregunte" 0 "aún no tiene rol" inicio S-nueva startup
espera_codigo "sin python ni node: el aviso no bloquea el mensaje (sale con 0)" 0 "" \
    env PATH="$TMP/roto:$PATH" bash -c "$(declare -f aviso); aviso S1"
espera_codigo "... ni la línea de estado" 0 "" env PATH="$TMP/roto:$PATH" bash -c "$(declare -f json_estado estado); estado S1 1"

echo "== Permisos y finales de línea en git (proyecto real; sin +x o con CRLF los hooks no funcionan)"
if git -C "$RAIZ_SRC" rev-parse --git-dir >/dev/null 2>&1 && [[ -n "$(git -C "$RAIZ_SRC" ls-files -- tools)" ]]; then
    SIN_X=()
    while read -r MODO _ _ RUTA; do
        [[ "$(head -c2 "$RAIZ_SRC/$RUTA" 2>/dev/null)" == '#!' && "$MODO" != 100755 ]] && SIN_X+=("$RUTA")
    done < <(git -C "$RAIZ_SRC" ls-files -s -- tools)
    printf '%s\n' "${SIN_X[@]}" > "$TMP/salida"
    if (( ${#SIN_X[@]} == 0 )); then ok "los scripts de tools/ tienen +x en git"
    else mal "scripts sin +x en git (arregla con: git update-index --chmod=+x -- <ruta>)"; fi
    SIN_LF=()
    while IFS= read -r RUTA; do
        [[ "$(git -C "$RAIZ_SRC" check-attr eol -- "$RUTA" | sed 's/.*: //')" == lf ]] || SIN_LF+=("$RUTA")
    done < <(git -C "$RAIZ_SRC" ls-files -- 'tools/*.sh' tools/hooks/pre-commit tools/hooks/commit-msg)
    printf '%s\n' "${SIN_LF[@]}" > "$TMP/salida"
    if (( ${#SIN_LF[@]} == 0 )); then ok "los scripts van con eol=lf (.gitattributes): CRLF rompería bash en Windows"
    else mal "scripts sin eol=lf en .gitattributes (copia el .gitattributes de la plantilla)"; fi
else
    echo "  (se omite: tools/ aún no está en git)"
fi

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
# arbol_motor_parado <descripción>: el nieto del motor falso colgado (PID en $TMP/nieto) ya no vive y el candado
# "motor" no está ocupado (un motor huérfano lo retendría y los lotes siguientes acabarían en 75)
arbol_motor_parado() {
    local n e
    n="$(cat "$TMP/nieto" 2>/dev/null)"
    [[ -n "$n" ]] && esperar_muerte "$n"
    e="$(./tools/locks/with_lock.sh --estado motor 2>/dev/null)"
    if [[ -n "$n" ]] && ! kill -0 "$n" 2>/dev/null && [[ "${e%%|*}" != ocupado && "${e%%|*}" != dudoso ]]; then ok "$1"
    else echo "nieto: ${n:-no llegó a arrancar}; candado motor: $e" > "$TMP/salida"; mal "$1"; fi
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

    # kill -9 al envoltorio con el comando vivo: el candado dura lo que dure el comando. Comando largo que se mata
    # tras comprobarlo: con "sleep 1.5", en Git Bash el comando ya había acabado al llegar a la comprobación.
    $CL "${L}3" arquitecto-sistemas sleep 30 & W=$!
    H="$(pid_comando "${L}3")"
    kill -9 "$W"; wait "$W" 2>/dev/null
    espera_codigo "[$MODO] kill -9 al envoltorio: ocupado mientras viva el comando" 75 "LOCK OCUPADO" $CL "${L}3" coordinador true
    kill "$H" 2>/dev/null
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
# Comando largo que se mata al acabar: motor_silencioso.sh tarda más de 1 s en llegar al candado en Git Bash
$CL motor arquitecto-sistemas sleep 30 & W=$!
H="$(pid_comando motor)"
espera_codigo "candado del motor ocupado -> 75" 75 "LOCK OCUPADO" $MS auditor-calidad
kill "$H" 2>/dev/null; wait "$W" 2>/dev/null
# Motor que no acaba (Godot con --quit sin escena principal): tope de tiempo, y se para con su nieto
rm -f "$TMP/nieto"
espera_codigo "motor que no acaba (MOTOR_TIEMPO_MAX=3) -> 124 con aviso" 124 "pasó de MOTOR_TIEMPO_MAX (3 s)" \
    env MOTOR_TIEMPO_MAX=3 MOTOR_FALSO_TEXTO="Can't run project: no main scene defined" MOTOR_FALSO_SEGUNDOS=120 \
    MOTOR_FALSO_NIETO="$TMP/nieto" $MS auditor-calidad
arbol_motor_parado "... parado con todo su árbol (nieto muerto, candado motor libre)"
# Un proceso detenido (SIGTTIN al leer la terminal desde otro grupo) no atiende TERM hasta que sigue: parar_arbol manda CONT
PARADO="$( source tools/hooks/procesos.sh; set -m; sleep 60 > /dev/null 2>&1 & P=$!; set +m; kill -STOP "$P"
           t=$SECONDS; parar_arbol "$P" 10; wait "$P" 2>/dev/null
           if proceso_vivo "$P"; then v=vivo; kill -KILL "$P" 2>/dev/null; else v=muerto; fi
           echo "$(( SECONDS - t )) $v" )"
if [[ "$PARADO" =~ ^[0-4]\ muerto$ ]]; then ok "parar_arbol con un proceso detenido -> no agota la espera"
else echo "tiempo y estado tras parar_arbol: '$PARADO' (se esperaba menos de 5 s y muerto)" > "$TMP/salida"; mal "parar_arbol con un proceso detenido -> no agota la espera"; fi
espera_codigo "MOTOR_TIEMPO_MAX no válido -> 64" 64 "MOTOR_TIEMPO_MAX" env MOTOR_TIEMPO_MAX=0 $MS auditor-calidad
espera_codigo "ejecutable del motor inexistente -> 127 con aviso" 127 "No se encuentra el ejecutable" \
    env MOTOR_BIN="$TMP/no_existe/motor" $MS auditor-calidad
for i in $(seq 40); do : > ".motor_logs/2000-01-01_0000$(printf '%02d' "$i")_viejo.log"; done
$MS auditor-calidad >/dev/null 2>&1
N_LOGS=$(find .motor_logs -name '*.log' | wc -l | tr -d ' ')
if (( N_LOGS == 30 )); then ok "se guardan los 30 últimos logs"; else : > "$TMP/salida"; mal "se guardan $N_LOGS logs (se esperaban 30)"; fi
unset MOTOR_BIN MOTOR_REGEX_ERRORES

echo "== Preparación de rondas (preparacion_ronda.sh) y su parte de la auditoría"
# Especificación y plan sintéticos en otro repo temporal (sin tocar el proyecto)
mkdir -p "$TMP/ronda/docs/direccion" && cd "$TMP/ronda" || exit 1
git init -q . && cp -r "$RAIZ_SRC/tools" . && rm -f tools/locks/*.lock
PR=./tools/auditoria/preparacion_ronda.sh
CONTRATO_SALTO=$'### Contrato: salto (ronda 1)\n- señal saltado(altura) · arquitecto-sistemas · coordinador'
espec() {  # espec <nivel> <§2> <primera línea de §4> [<§3> [<tope de rechazos>]]
    printf '# Especificación\n**Nivel de autonomía:** `%s`\n\n## 1. Visión General\n- Juego de prueba.\n\n## 2. Mecánicas y Sistemas\n%s\n\n## 3. Arquitectura Técnica y Contratos entre Roles\n%s\n\n## 4. Criterios de Desempate y Topes\n%s\n- Rechazos de `auditor-calidad` por lote antes de `bloqueado`: %s.\n\n## 5. Estructura de Carpetas por Dueño\n- propiedad.tsv\n' \
        "$1" "$2" "${4:-$CONTRATO_SALTO}" "$3" "${5:-3}" > docs/direccion/especificaciones.md
}
plan() {  # plan <cuota> <filas...>
    { printf '# Plan\n**Ventana:** x | **Cuota:** %s\n\n| # | Rol | Lote | Criterio de hecho | Comando de comprobación | Estado |\n|---|---|---|---|---|---|\n' "$1"
      shift; printf '%s\n' "$@"; } > docs/direccion/plan_nocturno.md
}
lote() {  # lote <id> <ronda y dependencias> <comando> [estado]
    printf '| 1 | arquitecto-sistemas | **%s** (%s). Lote de prueba. | Pasa sus tests. | `%s` | %s |' "$1" "$2" "$3" "${4:-pendiente}"
}
SALTO=$'### Salto (ronda 1)\n- Altura: 3 casillas; sin doble salto.'
SALTO_POR=$'### Salto (ronda 1)\n- (POR ESCRIBIR: altura y casos borde)'
MENU_POR=$'### Menú (ronda 2)\n- (POR ESCRIBIR: opciones)'
DESEMPATE="- Prioridad: simplicidad > rendimiento > flexibilidad."
espec bajo "$SALTO_POR" "- Prioridad: (POR ESCRIBIR: x)"
plan "a decidir" "$(lote A1 "ronda 1" ./tests/salto.sh)"
espera_codigo "[bajo] lote con criterio y comando: lista" 0 "lista para lanzar" $PR 1 --raiz .
plan "a decidir" "$(lote A1 "ronda 1" "./tools/motor_silencioso.sh arquitecto-sistemas ...")"
espera_codigo "[bajo] comando con '...': no lista" 1 "comando" $PR 1
espec medio "$SALTO" "$DESEMPATE"
plan "a decidir" "$(lote A1 "ronda 1" ./tests/salto.sh)"
espera_codigo "[medio] ronda 1 con su sistema escrito: lista" 0 "lista para lanzar" $PR 1
espec medio "$SALTO_POR" "$DESEMPATE"
espera_codigo "[medio] apartado (ronda 1) con «POR ESCRIBIR»: no lista" 1 "ronda 1 con «POR ESCRIBIR»" $PR 1
espec medio "$SALTO"$'\n'"$MENU_POR" "$DESEMPATE"
espera_codigo "[medio] un apartado (ronda 2) pendiente no impide la ronda 1" 0 "lista para lanzar" $PR 1
espec medio "$SALTO" "$DESEMPATE"
plan "a decidir" "$(lote A1 "ronda 1, contrato: Salto" ./tests/salto.sh)"
espera_codigo "contrato: con otras mayúsculas y sin su (ronda M), firmado: lista" 0 "lista para lanzar" $PR 1
plan "a decidir" "$(lote A1 "ronda 1, contrato: menú" ./tests/salto.sh)"
espera_codigo "contrato: sin apartado en §3: no lista" 1 "no tiene apartado «### Contrato: menú»" $PR 1
espec medio "$SALTO" "$DESEMPATE" $'### Contrato: salto (ronda 1)\n- (POR ESCRIBIR: señales)'
plan "a decidir" "$(lote A1 "ronda 1, contrato: salto" ./tests/salto.sh)"
espera_codigo "contrato: sin firmar: no lista" 1 "sin firmar" $PR 1
espec alto "$SALTO" "- Prioridad: (POR ESCRIBIR: x)"
plan "100 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)" "$(lote B1 "ronda 2, tras A1" ./tests/menu.sh)"
espera_codigo "[alto] §4 con «POR ESCRIBIR»: no lista" 1 "(§4)" $PR 1
espec alto "$SALTO" "$DESEMPATE"
plan "100 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)" "$(lote B1 "ronda 2, tras Z9" ./tests/menu.sh)"
espera_codigo "[alto] «tras Z9» que no existe: no lista" 1 "Z9" $PR 1
plan "a decidir" "$(lote A1 "ronda 1" ./tests/salto.sh)" "$(lote B1 "ronda 2, tras A1" ./tests/menu.sh)"
espera_codigo "[alto] cuota «a decidir»: no lista" 1 "Cuota" $PR 1
plan "100 euros por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)" "$(lote B1 "ronda 2, tras A1" ./tests/menu.sh)"
espera_codigo "[alto] cuota sin «USD por ronda»: no lista" 1 "USD por ronda" $PR 1
plan "12,5 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)" "$(lote B1 "ronda 2, tras A1" ./tests/menu.sh)"
espera_codigo "[alto] todo completo (cuota con decimales): lista" 0 "lista para lanzar" $PR 1
espec altisimo "$SALTO" "$DESEMPATE"
espera_codigo "nivel ilegible -> 2" 2 "ilegible" $PR 1
espera_codigo "sin número de ronda -> 64" 64 "Uso" $PR
# Auditoría: ronda en curso sin preparar, tope de rechazos y nivel distinto en normas
printf '# Pendientes\n' > docs/direccion/pendientes_manana.md
mkdir -p docs/direccion/roles
for r in "${ROLES_P[@]}"; do printf '# Ficha\n## Dueño Exclusivo de Archivos\n- `%s/**`\n' "$r" > "docs/direccion/roles/$r.md"; done
normas() { printf '# Normas\n## 9. Nivel de autonomía (`%s`), escalado y rondas\n' "$1" > docs/direccion/normas_comunes.md; }
rechazo() { printf '%s | auditor-calidad | Rechazo A1: %s | tests/ | arquitecto-sistemas\n' "$(date "+%Y-%m-%d %H:%M")" "$1"; }
auditar() { bash tools/auditoria/auditoria_proceso.sh --raiz . --informe "$TMP/informe.md" --excepciones "$TMP/sin_excepciones"; }
en_informe() {  # en_informe <descripción> <texto>
    if grep -q -- "$2" "$TMP/informe.md"; then ok "$1"; else cp "$TMP/informe.md" "$TMP/salida"; mal "$1"; fi
}
normas medio
printf '# tablón\n%s | coordinador | Lote A1: salto | plan | arquitecto-sistemas\n' "$(date "+%Y-%m-%d %H:%M")" > docs/direccion/tablon.md
espec medio "$SALTO_POR" "$DESEMPATE"
plan "a decidir" "$(lote A1 "ronda 1" ./tests/salto.sh "en curso")"
espera_codigo "auditoría: ronda en curso sin preparar -> hallazgo en la sección 6" 1 "6. Rondas en curso y nivel de autonomía: 1" auditar
en_informe "... que nombra la ronda y su primera falta" "ronda 1 tiene lotes \`en curso\` sin estar preparada"
espec medio "$SALTO" "$DESEMPATE"
{ rechazo uno; rechazo dos; rechazo tres; } >> docs/direccion/tablon.md
espera_codigo "auditoría: 3 rechazos de un lote no bloqueado -> hallazgo en la sección 4" 1 "4. Plan nocturno frente al tablón: 1" auditar
en_informe "... con el número de rechazos y el tope" "lleva 3 rechazos de auditor-calidad (tope 3)"
plan "a decidir" "$(lote A1 "ronda 1" ./tests/salto.sh bloqueado)" "$(lote B1 "ronda 2" ./tests/menu.sh)"
espera_codigo "... y ninguno si el lote ya está bloqueado (ni por B1, pendiente y aún fuera del tablón)" 0 \
    "4. Plan nocturno frente al tablón: 0" auditar
normas alto
espera_codigo "auditoría: nivel distinto en la especificación y en normas §9 -> hallazgo" 1 "6. Rondas en curso y nivel de autonomía: 1" auditar
en_informe "... que dice los dos niveles" "(\`medio\`) no coincide con el de la cabecera de §9 de las normas (\`alto\`)"
cd "$R" || exit 1

echo "== Despachador del nivel alto (tools/despachador.sh con tools/hooks/tests/claude_falso.sh)"
# Un repo temporal por escenario, en nivel alto y en la rama principal; el guion dice qué hace cada sesión falsa
RP="$(sed -n 's/^RAMA_PRINCIPAL="\(.*\)"$/\1/p' tools/despachador.sh)"
export DESPACHADOR_CLAUDE=./tools/hooks/tests/claude_falso.sh
export MOTOR_BIN="$R/tools/hooks/tests/motor_falso.sh"   # el despachador no arranca sin el ejecutable del motor
DP=./tools/despachador.sh
escenario() {  # escenario <nombre> <tope de intentos> <cuota> <filas del plan...>
    local d="$TMP/desp_$1" t="$2" c="$3"
    shift 3
    mkdir -p "$d/docs/direccion/roles" && cd "$d" || exit 1
    git init -q . && git symbolic-ref HEAD "refs/heads/$RP"
    git config user.name prueba && git config user.email prueba@example.invalid
    cp -r "$RAIZ_SRC/tools" . && rm -f tools/locks/*.lock
    cp "$RAIZ_SRC/.gitignore" .
    espec alto "$SALTO"$'\n'$'### Menú (ronda 2)\n- Tres opciones.' "$DESEMPATE" "$CONTRATO_SALTO" "$t"
    plan "$c" "$@"
    normas alto
    printf '# tablón\n' > docs/direccion/tablon.md
    printf '# Pendientes\n\n## Abiertos\n' > docs/direccion/pendientes_manana.md
    for r in "${ROLES_P[@]}"; do printf '# Ficha\n## Dueño Exclusivo de Archivos\n- `%s/**`\n' "$r" > "docs/direccion/roles/$r.md"; done
    git add -- . && git commit -q -m "coordinador: base"
    git config core.hooksPath tools/hooks
    export CLAUDE_FALSO_GUION="$d.guion" CLAUDE_FALSO_ARGS="$d.args"
    rm -f "$CLAUDE_FALSO_GUION" "$CLAUDE_FALSO_GUION.n" "$CLAUDE_FALSO_ARGS"
}
guion() { printf '%s\n' "$@" >> "$CLAUDE_FALSO_GUION"; }
sesiones() { cat "$CLAUDE_FALSO_GUION.n" 2>/dev/null || echo 0; }
estado_de() { grep -F "**$1**" docs/direccion/plan_nocturno.md | awk -F'|' '{ gsub(/^ +| +$/, "", $7); print $7 }'; }
espera_estado() {  # espera_estado <descripción> <lote> <estado>
    local e; e="$(estado_de "$2")"
    if [[ "$e" == "$3" ]]; then ok "$1"; else echo "estado de $2: '$e' (se esperaba '$3')" > "$TMP/salida"; mal "$1"; fi
}
espera_en() {  # espera_en <descripción> <archivo> <texto fijo>
    if grep -qF -- "$3" "$2"; then ok "$1"; else { echo "falta «$3» en $2:"; cat "$2"; } > "$TMP/salida" 2>&1; mal "$1"; fi
}
arbol_limpio() { [[ -z "$(git status --porcelain --untracked-files=all)" ]]; }

escenario hecho 3 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)" "$(lote B1 "ronda 2, tras A1" ./tests/menu.sh)"
BASE="$(git rev-parse HEAD)"
guion "arquitecto-sistemas entrega" "auditor-calidad valida" "arquitecto-sistemas entrega" "auditor-calidad valida"
espera_codigo "dos rondas con lotes validados -> 0" 0 "Hechos: A1, B1" $DP
espera_estado "... A1 hecho en el plan" A1 hecho
espera_estado "... y B1 (ronda 2, tras A1) también" B1 hecho
RAMA_D="$(git symbolic-ref --short HEAD)"
if [[ "$RAMA_D" == autonomo/* && "$(git rev-parse "$RP")" == "$BASE" ]]; then ok "... en una rama autonomo/... sin tocar $RP"
else echo "rama $RAMA_D; $RP en $(git rev-parse "$RP")" > "$TMP/salida"; mal "... en una rama autonomo/... sin tocar $RP"; fi
L1="$(head -n1 "$CLAUDE_FALSO_ARGS")"
if [[ "$L1" == "CLAUDE_ROL=arquitecto-sistemas DESPACHADOR=1 "* && "$L1" == *"[--permission-mode] [dontAsk]"* \
      && "$L1" == *"[--max-turns] [80]"* && "$L1" == *"[--max-budget-usd] [10.00]"* && "$L1" == *"[--output-format] [json]"* \
      && "$L1" == *"[--no-session-persistence]"* && "$L1" == *"Agent(agente-ejecutor-lote)"* \
      && "$L1" == *"Bash(./tools/despachador.sh*)"* && "$L1" != *bypass* && "$L1" != *--bare* && "$L1" == *"GIT_TERMINAL_PROMPT=0"* ]]; then
    ok "... con el rol fijado (CLAUDE_ROL), DESPACHADOR=1, GIT_TERMINAL_PROMPT=0 y las opciones de claude del ADR"
else echo "$L1" > "$TMP/salida"; mal "... con el rol fijado (CLAUDE_ROL), DESPACHADOR=1, GIT_TERMINAL_PROMPT=0 y las opciones de claude del ADR"; fi
if sed -n 2p "$CLAUDE_FALSO_ARGS" | grep -q "^CLAUDE_ROL=auditor-calidad " && [[ "$(sesiones)" == 4 ]]; then
    ok "... una sesión del rol y otra de auditor-calidad por lote"
else cp "$CLAUDE_FALSO_ARGS" "$TMP/salida"; mal "... una sesión del rol y otra de auditor-calidad por lote"; fi
espera_en "... con su fila Encargo en el tablón" docs/direccion/tablon.md "| coordinador | Encargo A1 (ronda 1, intento 1): A1 (ronda 1). Lote de prueba. |"
espera_en "... y su fila Estado hacia la persona responsable" docs/direccion/tablon.md "| coordinador | Estado B1: hecho | docs/direccion/plan_nocturno.md | persona responsable"
if arbol_limpio; then ok "... y el árbol limpio al acabar"; else git status --short > "$TMP/salida"; mal "... y el árbol limpio al acabar"; fi
espera_en "... con resumen en .despachador_logs" "$(ls -d .despachador_logs/*/ | tail -n1)resumen.md" "Para revisar: \`git log --oneline $RP..$RAMA_D\`"

escenario rechazo 2 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
guion "arquitecto-sistemas entrega" "auditor-calidad rechaza" "arquitecto-sistemas entrega" "auditor-calidad rechaza"
espera_codigo "rechazado hasta el tope (2) -> 0 y bloqueado" 0 "Bloqueados: A1" $DP
espera_estado "... A1 bloqueado en el plan" A1 bloqueado
espera_en "... con su entrada en pendientes_manana.md" docs/direccion/pendientes_manana.md "Lote A1 bloqueado tras 2 intentos sin validar (tope 2)"
if grep -q "intento 2.*auditor-calidad lo rechazó: no cumple el criterio" "$CLAUDE_FALSO_ARGS"; then ok "... y el segundo intento lleva el motivo del rechazo"
else cp "$CLAUDE_FALSO_ARGS" "$TMP/salida"; mal "... y el segundo intento lleva el motivo del rechazo"; fi
N_PEND=0
for C in $(git rev-list HEAD -- docs/direccion/plan_nocturno.md); do
    git show "$C:docs/direccion/plan_nocturno.md" | grep -F '**A1**' | grep -q '| pendiente |' && N_PEND=$((N_PEND + 1))
done
if (( N_PEND == 1 )); then ok "... sin volver nunca a pendiente entre intentos (sigue en curso)"
else git log --oneline > "$TMP/salida"; mal "... sin volver nunca a pendiente entre intentos (sigue en curso)"; fi

escenario sucio 1 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
guion "arquitecto-sistemas sucio"
espera_codigo "sesión sin fila que deja archivos sin commitear -> Fallo y bloqueado (tope 1)" 0 "Bloqueados: A1" $DP
espera_en "... con su fila Fallo" docs/direccion/tablon.md "| coordinador | Fallo A1: la sesión de arquitecto-sistemas no dejó entrega ni duda"
S="$(ls -d .despachador_logs/*/ | tail -n1)sobras/r1_A1_arquitecto-sistemas_1"
if [[ -f "$S/tools/hooks/sobra_falsa.txt" && -f "$S/tools/hooks/tests/motor_falso.sh" ]] && arbol_limpio \
    && [[ ! -e tools/hooks/sobra_falsa.txt ]] && git diff --quiet HEAD -- tools/hooks/tests/motor_falso.sh; then
    ok "... sus sobras copiadas en sobras/ y deshechas (árbol limpio)"
else { git status --short; ls -R .despachador_logs; } > "$TMP/salida" 2>&1; mal "... sus sobras copiadas en sobras/ y deshechas (árbol limpio)"; fi

escenario duda 3 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)" "$(lote A2 "ronda 1, tras A1" ./tests/menu.sh)"
guion "arquitecto-sistemas duda"
espera_codigo "duda -> 0, lote bloqueado" 0 "Bloqueados: A1: duda de arquitecto-sistemas, A2" $DP
espera_estado "... A1 bloqueado" A1 bloqueado
espera_estado "... y A2 (tras A1) bloqueado por dependencia" A2 bloqueado
espera_en "... con la pregunta en pendientes_manana.md" docs/direccion/pendientes_manana.md "¿cuántas casillas sube el salto? (falsa)"

escenario parar 3 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)" "$(lote B1 "ronda 2, tras A1" ./tests/menu.sh)"
guion "arquitecto-sistemas entrega+parar" "auditor-calidad valida"
espera_codigo ".parar durante un lote -> acaba su ciclo y sale con 1" 1 "parado: parada con .parar" $DP
espera_estado "... A1 hecho" A1 hecho
espera_estado "... y B1 sin lanzar (pendiente)" B1 pendiente
espera_en "... con la pausa en el tablón" docs/direccion/tablon.md "| coordinador | Pausa (ronda 2): parada con .parar; sigue B1 |"
RAMA_D="$(git symbolic-ref --short HEAD)"
espera_codigo "con .parar no arranca -> 2" 2 "existe .parar" $DP
rm -f .parar
guion "arquitecto-sistemas entrega" "auditor-calidad valida"
espera_codigo "sin .parar se reanuda -> 0" 0 "Reanudando la rama $RAMA_D" $DP
espera_estado "... B1 hecho en la misma rama" B1 hecho
if [[ "$(git branch --list 'autonomo/*' | wc -l | tr -d ' ')" == 1 ]]; then ok "... sin crear otra rama"; else git branch > "$TMP/salida"; mal "... sin crear otra rama"; fi

escenario cuota 3 "1 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)" "$(lote A2 "ronda 1" ./tests/menu.sh)"
guion "arquitecto-sistemas entrega 0.7" "auditor-calidad valida 0.5"
espera_codigo "cuota de 1 USD con sesiones de 0.7 y 0.5 -> pausa y 1" 1 "cuota de la ronda agotada" $DP
if sed -n 2p "$CLAUDE_FALSO_ARGS" | grep -qF "[--max-budget-usd] [0.30]"; then ok "... auditor-calidad recibió lo que quedaba (0.30 USD)"
else cp "$CLAUDE_FALSO_ARGS" "$TMP/salida"; mal "... auditor-calidad recibió lo que quedaba (0.30 USD)"; fi
espera_estado "... A1 hecho" A1 hecho
espera_estado "... y A2 sin lanzar" A2 pendiente
espera_en "... con la pausa en el tablón" docs/direccion/tablon.md "Pausa (ronda 1): cuota de la ronda agotada (1.20 de 1 USD, estimado); sigue A2"

escenario tiempo 1 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
guion "arquitecto-sistemas lento"
espera_codigo "sesión que pasa de DESPACHADOR_TIEMPO_MAX -> se mata y cuenta como fallo" 0 "Bloqueados: A1" env DESPACHADOR_TIEMPO_MAX=2 $DP
espera_en "... Fallo por tiempo agotado" docs/direccion/tablon.md "tiempo agotado (2 s)"

escenario colgado 1 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
guion "arquitecto-sistemas colgado"
rm -f "$TMP/nieto"
espera_codigo "sesión con el motor colgado que pasa de DESPACHADOR_TIEMPO_MAX -> Fallo" 0 "Bloqueados: A1" \
    env DESPACHADOR_TIEMPO_MAX=8 MOTOR_FALSO_NIETO="$TMP/nieto" $DP
arbol_motor_parado "... y se mata el árbol entero de la sesión (motor y nieto parados, candado motor libre)"

escenario interrumpir 3 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
guion "arquitecto-sistemas colgado"
rm -f "$TMP/nieto"
MOTOR_FALSO_NIETO="$TMP/nieto" $DP > "$TMP/interrumpido" 2>&1 & W=$!
for (( i = 0; i < 300; i++ )); do [[ -s "$TMP/nieto" ]] && break; sleep 0.1; done   # el motor colgado ya está en marcha
H="$(pid_comando despachador)"
kill -TERM "$H" 2>/dev/null
wait "$W"; RI=$?
cp "$TMP/interrumpido" "$TMP/salida"
if (( RI == 143 )) && grep -q "parado: interrumpido" "$TMP/salida"; then ok "TERM al despachador con un motor colgado -> 143"
else mal "TERM al despachador con un motor colgado -> 143 (código $RI)"; fi
arbol_motor_parado "... sin dejar vivo nada de la sesión (motor y nieto parados, candado motor libre)"
S="$(ls -d .despachador_logs/*/ | tail -n1)sobras/r1_A1_arquitecto-sistemas_1"
if [[ -f "$S/tools/hooks/sobra_falsa.txt" ]] && arbol_limpio; then ok "... con sus sobras copiadas en sobras/ y deshechas (árbol limpio)"
else { git status --short; ls -R .despachador_logs; } > "$TMP/salida" 2>&1; mal "... con sus sobras copiadas en sobras/ y deshechas (árbol limpio)"; fi
guion "arquitecto-sistemas entrega" "auditor-calidad valida"
espera_codigo "... y el siguiente arranque reanuda la rama y acaba el lote -> 0" 0 "Hechos: A1" $DP

escenario interrumpir_sordo 3 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
guion "arquitecto-sistemas sordo"
# Ctrl+C real: la señal llega al with_lock.sh de fuera (el despachador hace exec hacia él) y este se la pasa al de dentro. La
# terminal no puede volver hasta que el despachador acabe: la sesión sorda a TERM solo muere con el KILL de parar_arbol.
# (CANDADO_ESPERA_SENAL=7 en el entorno de quien lanza: el despachador pone el suyo y no debe dejar pasar ninguno a la sesión)
CANDADO_ESPERA_SENAL=7 $DP > "$TMP/interrumpido" 2>&1 & W=$!
H="$(pid_comando despachador)"
for (( i = 0; i < 300; i++ )); do [[ -s "$CLAUDE_FALSO_ARGS" ]] && break; sleep 0.1; done   # la sesión sorda ya está en marcha
sleep 1
kill -TERM "$W" 2>/dev/null
wait "$W"
if ! kill -0 "$H" 2>/dev/null; then ok "TERM al with_lock.sh de fuera con una sesión sorda a TERM -> el despachador de dentro ya no vive al volver"
else echo "el despachador $H sigue vivo al volver with_lock.sh" > "$TMP/salida"; mal "TERM al with_lock.sh de fuera con una sesión sorda a TERM -> el despachador de dentro ya no vive al volver"; kill -9 "$H" 2>/dev/null; fi
espera_en "... y su resumen dice que se interrumpió" "$(ls -d .despachador_logs/*/ | tail -n1)resumen.md" "parado: interrumpido"
if [[ -s "$CLAUDE_FALSO_ARGS" && ! -e "$CLAUDE_FALSO_ARGS.env" ]]; then ok "... y CANDADO_ESPERA_SENAL no llegó a la sesión"
else cat "$CLAUDE_FALSO_ARGS.env" > "$TMP/salida" 2>&1; mal "... y CANDADO_ESPERA_SENAL no llegó a la sesión"; fi
espera_codigo "... y relanzar en seguida no da 75" 0 "Lanzaría A1" $DP --simular

escenario bloqueo 3 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
guion "arquitecto-sistemas bloqueo" "arquitecto-sistemas entrega" "auditor-calidad valida"
espera_codigo "sesión que deja un .git/index.lock suyo -> se quita y el lote sigue" 0 "Hechos: A1" $DP
S="$(ls -d .despachador_logs/*/ | tail -n1)sobras/r1_A1_arquitecto-sistemas_1"
if [[ ! -e .git/index.lock && -f "$S/tools/hooks/sobra_falsa.txt" ]] && arbol_limpio; then
    ok "... sin index.lock, con su sobra en sobras/ y el árbol limpio"
else { git status --short; ls -a .git | grep lock; ls -R .despachador_logs; } > "$TMP/salida" 2>&1; mal "... sin index.lock, con su sobra en sobras/ y el árbol limpio"; fi

escenario bloqueo_viejo 3 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
guion "arquitecto-sistemas bloqueo_viejo"
espera_codigo "un .git/index.lock anterior a la sesión -> para y lo dice" 1 "index.lock no es de la sesión" $DP
if [[ -e .git/index.lock ]]; then ok "... y no lo borra (no es de la sesión)"; else mal "... y no lo borra (no es de la sesión)"; fi
rm -f .git/index.lock

escenario candado 3 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
$CL motor arquitecto-sistemas sleep 30 & W=$!
H="$(pid_comando motor)"
espera_codigo "candado del motor ocupado -> se pospone y luego Fallo sin lanzar sesión" 0 "Sin lanzar: A1 (candado motor ocupado)" $DP
if [[ "$(sesiones)" == 0 ]]; then ok "... sin lanzar ninguna sesión"; else mal "... sin lanzar ninguna sesión"; fi
espera_en "... con su fila Fallo" docs/direccion/tablon.md "Fallo A1: el candado «motor» seguía ocupado"
$CL despachador coordinador sleep 30 & W2=$!
H2="$(pid_comando despachador)"
espera_codigo "segundo despachador -> 75" 75 "LOCK OCUPADO" $DP
kill "$H" "$H2" 2>/dev/null; wait "$W" "$W2" 2>/dev/null

escenario simular 3 "10 USD por ronda" "$(lote A1 "ronda 1" ./tests/salto.sh)"
BASE="$(git rev-parse HEAD)"
espera_codigo "--simular -> 0 y dice qué lanzaría" 0 "Lanzaría A1 (arquitecto-sistemas), ronda 1, intento 1 de 3" $DP --simular
if [[ "$(git rev-parse HEAD)" == "$BASE" && "$(git symbolic-ref --short HEAD)" == "$RP" && "$(sesiones)" == 0 ]] && arbol_limpio \
    && [[ ! -e .despachador_logs ]]; then ok "... sin commits, sin rama, sin sesiones y sin registro"
else { git log --oneline; git status --short; } > "$TMP/salida"; mal "... sin commits, sin rama, sin sesiones y sin registro"; fi
echo "x" > docs/direccion/notas.md
espera_codigo "árbol sucio al arrancar -> 2" 2 "no está limpio" $DP
rm -f docs/direccion/notas.md
espera_codigo "claude sin las opciones que usa -> 2" 2 "no tiene --permission-mode" env DESPACHADOR_CLAUDE=true $DP
espera_codigo "ejecutable del motor inexistente -> 2" 2 "no se encuentra el ejecutable del motor" \
    env MOTOR_BIN="$TMP/no_existe/motor" $DP --simular
espec medio "$SALTO" "$DESEMPATE"
espera_codigo "nivel medio -> 2" 2 "solo para el nivel alto" $DP --simular
espera_codigo "argumento desconocido -> 64" 64 "Uso" $DP --rapido
unset DESPACHADOR_CLAUDE CLAUDE_FALSO_GUION CLAUDE_FALSO_ARGS MOTOR_BIN
cd "$R" || exit 1

echo "== Resultado: $((TOTAL - FALLOS))/$TOTAL pruebas OK"
(( FALLOS == 0 ))

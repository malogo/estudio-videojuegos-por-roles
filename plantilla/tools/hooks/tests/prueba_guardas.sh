#!/usr/bin/env bash
# Prueba rápida de las guardas del sistema (commit-msg, pre-commit, pre_tool_guard.sh, guard_propiedad.sh,
# with_lock.sh). Trabaja en un repo temporal con una copia de tools/: no toca el proyecto.
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
echo "otro:$$:$(date +%s)" > tools/locks/prueba.lock
espera_rechazo "candado ocupado sale con aviso (código 75)" "LOCK OCUPADO" ./tools/locks/with_lock.sh prueba coordinador true
rm -f tools/locks/prueba.lock
espera_ok "candado libre ejecuta la orden" ./tools/locks/with_lock.sh prueba coordinador true

echo "== Resultado: $((TOTAL - FALLOS))/$TOTAL pruebas OK"
(( FALLOS == 0 ))

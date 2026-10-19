# shellcheck shell=bash
# Lectura del JSON que Claude Code pasa por stdin a los hooks PreToolUse.
# Uso: source tools/hooks/leer_json.sh
#      { IFS= read -r -d '' ORDEN; IFS= read -r -d '' RUTA; IFS= read -r -d '' SESION; IFS= read -r -d '' AGENTE
#        IFS= read -r -d '' LEIDO; } < <(printf '%s' "$ENTRADA" | campos_hook)
#      [[ "$LEIDO" == OK ]] || bloquear_sin_json "<nombre del hook>"
# Imprime separados por NUL: tool_input.command, tool_input.file_path (o notebook_path), session_id, agent_id
# y, solo si el JSON se pudo leer, un quinto campo "OK". Sin él la guarda no sabe qué se va a ejecutar y
# bloquea (falla cerrada): un python roto (p. ej. el alias de la Microsoft Store) no la desactiva en silencio.
# El JSON se lee y se escribe como UTF-8 (rutas y órdenes con tildes) sea cual sea la codificación del sistema.

campos_hook() {
    local py='import sys, json
d = json.loads(sys.stdin.buffer.read().decode("utf-8")); t = d.get("tool_input") or {}
for v in (t.get("command"), t.get("file_path") or t.get("notebook_path"), d.get("session_id"), d.get("agent_id"), "OK"):
    sys.stdout.buffer.write((str(v or "") + "\0").encode("utf-8"))'
    if command -v python >/dev/null 2>&1 && python -c 'import json' >/dev/null 2>&1; then
        python -c "$py" 2>/dev/null
    elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then
        python3 -c "$py" 2>/dev/null
    elif command -v node >/dev/null 2>&1 && node -e '' >/dev/null 2>&1; then
        node -e 'let s="";process.stdin.setEncoding("utf8");process.stdin.on("data",c=>s+=c).on("end",()=>{let d;try{d=JSON.parse(s)}catch(e){process.exit(1)}
const t=d.tool_input||{};for(const v of [t.command,t.file_path||t.notebook_path,d.session_id,d.agent_id,"OK"])process.stdout.write(String(v||"")+"\0")})'
    else
        return 1
    fi
}

# Mensaje y código 2 (bloqueo) cuando no se pudo leer el JSON del hook.
bloquear_sin_json() {
    echo "[BLOQUEADO POR NORMA] [$1] No se pudo leer la llamada (hace falta python 3 o node que funcionen)." >&2
    echo "  Instala Python 3 (en Windows, desactiva los alias de la Microsoft Store para python.exe) y vuelve a intentarlo." >&2
    echo "  Si las guardas no te dejan arreglarlo, pídelo a la persona responsable: no las desactives tú." >&2
    exit 2
}

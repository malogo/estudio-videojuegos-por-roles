# shellcheck shell=bash
# Lectura del JSON que Claude Code pasa por stdin a los hooks PreToolUse.
# Uso: source tools/hooks/leer_json.sh
#      { IFS= read -r -d '' ORDEN; IFS= read -r -d '' RUTA; IFS= read -r -d '' SESION; IFS= read -r -d '' AGENTE; } \
#          < <(printf '%s' "$ENTRADA" | campos_hook)
# Imprime separados por NUL: tool_input.command, tool_input.file_path (o notebook_path), session_id, agent_id.
# Devuelve 1 si no hay python ni node.

campos_hook() {
    local py='import sys, json
d = json.load(sys.stdin); t = d.get("tool_input") or {}
for v in (t.get("command"), t.get("file_path") or t.get("notebook_path"), d.get("session_id"), d.get("agent_id")):
    sys.stdout.write(str(v or "") + "\0")'
    if command -v python >/dev/null 2>&1 && python -c 'import json' >/dev/null 2>&1; then
        python -c "$py" 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "$py" 2>/dev/null
    elif command -v node >/dev/null 2>&1; then
        node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{let d={};try{d=JSON.parse(s)}catch(e){}
const t=d.tool_input||{};for(const v of [t.command,t.file_path||t.notebook_path,d.session_id,d.agent_id])process.stdout.write(String(v||"")+"\0")})'
    else
        return 1
    fi
}

# shellcheck shell=bash
# Lectura del JSON que Claude Code pasa por stdin a los hooks (y a la línea de estado).
# Uso: source tools/hooks/leer_json.sh
#      { IFS= read -r -d '' ORDEN; IFS= read -r -d '' RUTA; IFS= read -r -d '' SESION; IFS= read -r -d '' AGENTE
#        IFS= read -r -d '' LEIDO; } < <(printf '%s' "$ENTRADA" | campos_hook)
#      [[ "$LEIDO" == OK ]] || bloquear_sin_json "<nombre del hook>"
# campos_hook imprime separados por NUL: tool_input.command, tool_input.file_path (o notebook_path), session_id,
# agent_id y, solo si el JSON se pudo leer, un quinto campo "OK". Sin él la guarda no sabe qué se va a ejecutar y
# bloquea (falla cerrada): un python roto (p. ej. el alias de la Microsoft Store) no la desactiva en silencio.
# campos_json <ruta> ... hace lo mismo con los campos que se le pidan ("session_id", "context_window.total_input_tokens").
# El JSON se lee y se escribe como UTF-8 (rutas y órdenes con tildes) sea cual sea la codificación del sistema.

# Intérprete que lee JSON: python, python3 o node, el primero que funcione (falla si no hay ninguno).
_interprete_json() {
    local i
    for i in python python3; do
        command -v "$i" >/dev/null 2>&1 && "$i" -c 'import json' >/dev/null 2>&1 && { printf '%s' "$i"; return 0; }
    done
    command -v node >/dev/null 2>&1 && node -e '' >/dev/null 2>&1 && { printf node; return 0; }
    return 1
}

campos_hook() {
    campos_json tool_input.command tool_input.file_path:tool_input.notebook_path session_id agent_id
}

# Campos del JSON de stdin (rutas con puntos; "a:b" = el primero de los dos que no esté vacío), más "OK" al final.
campos_json() {
    local int
    int="$(_interprete_json)" || return 1
    if [[ "$int" == node ]]; then
        node -e 'let s="";process.stdin.setEncoding("utf8");process.stdin.on("data",c=>s+=c).on("end",()=>{let d;try{d=JSON.parse(s)}catch(e){process.exit(1)}
const campo=r=>{let v=d;for(const k of r.split(".")){v=(v&&typeof v==="object")?v[k]:undefined}return (v===undefined||v===null)?"":String(v)};
for(const r of process.argv.slice(1)){let v="";for(const a of r.split(":")){v=campo(a);if(v)break}process.stdout.write(v+"\0")}process.stdout.write("OK\0")})' "$@"
    else
        "$int" -c 'import sys, json
d = json.loads(sys.stdin.buffer.read().decode("utf-8"))
def campo(r):
    v = d
    for k in r.split("."):
        v = v.get(k) if isinstance(v, dict) else None
    return "" if v is None else str(v)
for r in sys.argv[1:]:
    v = next((x for x in map(campo, r.split(":")) if x), "")
    sys.stdout.buffer.write((v + "\0").encode("utf-8"))
sys.stdout.buffer.write(b"OK\0")' "$@" 2>/dev/null
    fi
}

# Mensaje y código 2 (bloqueo) cuando no se pudo leer el JSON del hook.
bloquear_sin_json() {
    echo "[BLOQUEADO POR NORMA] [$1] No se pudo leer la llamada (hace falta python 3 o node que funcionen)." >&2
    echo "  Instala Python 3 (en Windows, desactiva los alias de la Microsoft Store para python.exe) y vuelve a intentarlo." >&2
    echo "  Si las guardas no te dejan arreglarlo, pídelo a la persona responsable: no las desactives tú." >&2
    exit 2
}

# shellcheck shell=bash
# Consulta de propiedad de archivos. Fuente única para commit-msg, guard_propiedad.sh y fijar_rol.sh.
# Uso: source tools/hooks/propiedad.sh
#      dueno=$(dueno_de_ruta "src/core/partida.cs")   # "" si no tiene dueño, "*" si es de todos
#      rol_valido "arquitecto-sistemas" && echo sí
#      rol=$(rol_de_sesion "<session_id>" "<agent_id>")       # rol declarado con fijar_rol.sh (o $CLAUDE_ROL)
#      desde=$(ultimo_vaciado docs/direccion/roles/memoria_<rol>.md)   # "YYYY-MM-DD HH:MM"; falla si no se puede leer

PROPIEDAD_TSV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/propiedad.tsv"
# Roles del proyecto (cada uno con su ficha docs/direccion/roles/<rol>.md). Los tres primeros son obligatorios.
ROLES_VALIDOS=({{ROLES}})
_PROP_REGEX=()
_PROP_ROL=()

# "src/**" -> ^src/.*$ ; "**/.gitkeep" -> ^(.*/)?\.gitkeep$ ; "roles/*.md" -> ^roles/[^/]*\.md$
_patron_a_regex() {
    local p="$1" r="" i c
    for (( i = 0; i < ${#p}; i++ )); do
        c="${p:i:1}"
        if [[ "$c" == '*' && "${p:i+1:1}" == '*' ]]; then
            if [[ "${p:i+2:1}" == / ]]; then r+='(.*/)?'; i=$((i + 2)); else r+='.*'; i=$((i + 1)); fi
        else
            case "$c" in
                '*') r+='[^/]*' ;;
                '?') r+='[^/]' ;;
                .|^|$|+|'('|')'|'{'|'}'|'|'|'['|']'|\\) r+="\\$c" ;;
                *) r+="$c" ;;
            esac
        fi
    done
    printf '^%s$' "$r"
}

_cargar_propiedad() {
    (( ${#_PROP_REGEX[@]} )) && return 0
    local patron rol
    while IFS=$'\t' read -r patron rol; do
        patron="${patron%$'\r'}"; rol="${rol%$'\r'}"
        [[ -z "$patron" || "$patron" == \#* || -z "$rol" ]] && continue
        _PROP_REGEX+=("$(_patron_a_regex "$patron")")
        _PROP_ROL+=("$rol")
    done < "$PROPIEDAD_TSV"
}

dueno_de_ruta() {
    _cargar_propiedad
    local ruta="${1#./}" i
    for i in "${!_PROP_REGEX[@]}"; do
        if [[ "$ruta" =~ ${_PROP_REGEX[i]} ]]; then
            printf '%s' "${_PROP_ROL[i]}"
            return 0
        fi
    done
    return 0
}

rol_valido() {
    local r
    for r in "${ROLES_VALIDOS[@]}"; do [[ "$1" == "$r" ]] && return 0; done
    return 1
}

# Carpeta donde se guardan los roles declarados por sesión (dentro de .git: nunca se commitea).
dir_roles_sesion() {
    local comun
    comun="$(git -C "$(dirname "$PROPIEDAD_TSV")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    printf '%s/claude_roles' "$comun"
}

_id_limpio() { printf '%s' "${1//[^A-Za-z0-9_-]/}"; }

# Prioridad: $CLAUDE_ROL > rol del subagente > rol de la sesión. Vacío si no se ha declarado.
rol_de_sesion() {
    if [[ -n "${CLAUDE_ROL:-}" ]]; then printf '%s' "$CLAUDE_ROL"; return 0; fi
    local dir s a f
    dir="$(dir_roles_sesion)" || return 0
    s="$(_id_limpio "$1")"; a="$(_id_limpio "${2:-}")"
    [[ -z "$s" ]] && return 0
    for f in ${a:+"$dir/${s}__${a}"} "$dir/$s"; do
        if [[ -f "$f" ]]; then tr -d '[:space:]' < "$f"; return 0; fi
    done
    return 0
}

guardar_rol_sesion() {
    local rol="$1" dir s a
    dir="$(dir_roles_sesion)" || return 1
    s="$(_id_limpio "$2")"; a="$(_id_limpio "${3:-}")"
    [[ -z "$s" ]] && return 1
    mkdir -p "$dir" && printf '%s\n' "$rol" > "$dir/${s}${a:+__$a}"
}

# "**Último vaciado:** 2026-10-18 22:17 (...)" -> "2026-10-18 22:17"; sin hora -> 00:00.
# Lo usan arranque_rol.sh (qué filas del tablón enseñar) y archivar_tablon.sh (qué filas ya leyó todo el mundo).
# Sale con 1 (y sin imprimir nada) si la memoria no existe o la fecha no se puede leer.
ultimo_vaciado() {
    local linea fecha hora
    [[ -f "$1" ]] || return 1
    linea="$(tr -d '\r' < "$1" | grep -m1 'Último vaciado:' || true)"
    [[ "$linea" =~ Último\ vaciado:\*{0,2}[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2})([[:space:]]+([0-9]{1,2}:[0-9]{2}))? ]] || return 1
    fecha="${BASH_REMATCH[1]}" hora="${BASH_REMATCH[3]:-00:00}"
    (( ${#hora} == 4 )) && hora="0$hora"
    date -d "$fecha $hora" +%s >/dev/null 2>&1 || return 1
    printf '%s %s' "$fecha" "$hora"
}

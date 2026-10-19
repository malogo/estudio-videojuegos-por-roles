# shellcheck shell=bash
# Reglas comunes de órdenes prohibidas. Fuente única para git_guard.sh y pre_tool_guard.sh.
# Uso: source tools/hooks/reglas_comando.sh
#      motivo=$(motivo_bloqueo_linea "<orden completa>") || echo "BLOQUEADO: $motivo"
#      motivo=$(motivo_bloqueo_git <args de git...>)       || echo "BLOQUEADO: $motivo"
# Devuelven 1 e imprimen el motivo si la orden está prohibida; 0 si está permitida.

# shellcheck source=requisitos.sh
source "$(dirname "${BASH_SOURCE[0]}")/requisitos.sh"

_basename_cmd() {
    local b="${1##*/}"
    b="${b##*\\}"
    printf '%s' "${b,,}"
}

# Ejecutables del motor ({{MOTOR}}), en minúsculas y sin ruta, o la variable que apunta a él usada como
# orden ($MOTOR_BIN, ${MOTOR_BIN}, $env:MOTOR_BIN). Solo se lanza con ./tools/motor_silencioso.sh.
# Proyecto sin motor que vigilar: deja la expresión en '^$' (no casa con nada).
_RE_MOTOR='{{REGEX_BINARIO_MOTOR}}'
_es_motor() {
    local b
    b="$(_basename_cmd "$1")"
    [[ "$b" =~ $_RE_MOTOR || "$b" == '$motor_bin' || "$b" == '${motor_bin}' || "$b" == '$env:motor_bin' ]]
}

# Programa que abre un lanzador, para reconocer el motor también así: "flatpak run [opciones] org.godotengine.Godot"
# -> Godot, "snap run godot-4" -> godot-4, "open -a /Applications/Godot.app" (macOS) -> Godot. Vacío si no lo es.
_app_lanzada() {
    local -a t=("$@")
    local b i
    b="$(_basename_cmd "${t[0]:-}")"
    case "$b" in
        flatpak|snap)
            [[ "${t[1]:-}" == run ]] || return 0
            for (( i = 2; i < ${#t[@]}; i++ )); do [[ "${t[i]}" == -* ]] || break; done
            b="${t[i]:-}"
            [[ "$b" == *.*.* ]] && b="${b##*.}"
            printf '%s' "$b" ;;
        open)
            for (( i = 1; i < ${#t[@]}; i++ )); do
                if [[ "${t[i]}" == -a ]]; then b="${t[i+1]:-}"; b="${b%/}"; printf '%s' "${b%.app}"; return 0; fi
            done ;;
    esac
}

# ¿$1 es la opción larga $2 o una abreviatura suya? git acepta abreviaturas sin ambigüedad (--amen = --amend,
# --no-veri = --no-verify, reset --har = --hard); las ambiguas ya las rechaza git, así que bloquearlas no quita nada.
_opcion() { local x="${1%%=*}"; [[ "$x" == --?* && "$2" == "$x"* ]]; }

# Claves de configuración que desactivan los hooks del proyecto: core.hooksPath y los archivos incluidos
# (include.path, includeIf.<condición>.path), que pueden traer otro core.hooksPath.
_clave_salta_hooks() {
    local k="${1,,}"
    k="${k%%=*}"
    [[ "$k" == core.hookspath || "$k" == include.path || "$k" == includeif.*.path ]]
}

# ¿"git reset <x>" sin rutas movería la rama? Sí si <x> no es una ruta y es (o parece) un commit distinto de HEAD.
_mueve_head() {
    local x="$1" c
    [[ "$x" == HEAD || "$x" == @ || -e "$x" ]] && return 1
    if c="$(git rev-parse -q --verify "$x^{commit}" 2>/dev/null)"; then
        [[ "$c" != "$(git rev-parse -q --verify HEAD 2>/dev/null)" ]]
        return
    fi
    # No se pudo resolver desde aquí (otra carpeta...): basta con que tenga forma de commit
    [[ "$x" =~ [~^]|@\{ || "$x" =~ ^[0-9a-fA-F]{7,40}$ ]]
}

# ¿Una ruta de checkout/restore que abarca más que archivos concretos? (".", magia ":/", comodines, carpetas)
_ruta_amplia() {
    local p="$1"
    [[ "$p" == . || "$p" == */ || "$p" == :* || "$p" == *[\*\?\[]* || -d "$p" ]]
}

# Recibe los argumentos que van detrás de "git".
motivo_bloqueo_git() {
    local -a t=("$@")
    local n=${#t[@]} i=0
    # Saltar opciones globales (git -C dir, -c clave=valor, --no-pager...). Cambiar core.hooksPath al
    # vuelo (-c / --config-env) desactivaría pre-commit y commit-msg.
    while (( i < n )); do
        case "${t[i]}" in
            -c|--config-env)
                if _clave_salta_hooks "${t[i+1]:-}"; then
                    echo "Prohibido cambiar core.hooksPath al vuelo (git ${t[i]} ${t[i+1]}): desactiva los hooks del proyecto."
                    return 1
                fi
                i=$((i + 2)) ;;
            --config-env=*)
                if _clave_salta_hooks "${t[i]#--config-env=}"; then
                    echo "Prohibido cambiar core.hooksPath al vuelo (${t[i]}): desactiva los hooks del proyecto."
                    return 1
                fi
                i=$((i + 1)) ;;
            -C|--git-dir|--work-tree|--namespace) i=$((i + 2)) ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
        esac
    done
    local sub="${t[i]:-}"
    local -a a=("${t[@]:i+1}") pos=()
    local x f j c m

    case "$sub" in
        stash)
            echo "Prohibido 'git stash' en árbol compartido. Usa commits por rutas."
            return 1 ;;
        add)
            for x in "${a[@]}"; do
                if [[ "$x" == -A || "$x" == . || "$x" == ./ || "$x" == :/ || "$x" == '*' ]] \
                    || _opcion "$x" --all || _opcion "$x" --no-ignore-removal; then
                    echo "Prohibido 'git add $x'. Usa 'git commit -m \"...\" -- <rutas exactas>'."
                    return 1
                fi
            done ;;
        commit)
            for x in "${a[@]}"; do
                case "$x" in
                    --) break ;;
                    --*)
                        if _opcion "$x" --all; then
                            echo "Prohibido 'git commit $x' (--all). Usa 'git commit -m \"...\" -- <rutas exactas>'."
                            return 1
                        fi
                        if _opcion "$x" --no-verify; then
                            echo "Prohibido 'git commit $x' (--no-verify): se salta pre-commit y commit-msg. Si un hook te bloquea, corrige la causa."
                            return 1
                        fi
                        if _opcion "$x" --amend; then
                            echo "Prohibido 'git commit $x' (--amend) en árbol compartido: el último commit puede ser de otra sesión y te lo quedarías. Haz un commit nuevo."
                            return 1
                        fi ;;
                    -*)
                        # Grupos de opciones cortas: -a, -am, -n, -sn... (tras m/F/c/C/t va un valor)
                        f="${x#-}"
                        for (( j = 0; j < ${#f}; j++ )); do
                            c="${f:j:1}"
                            if [[ "$c" == a ]]; then
                                echo "Prohibido 'git commit -a' ($x). Usa 'git commit -m \"...\" -- <rutas exactas>'."
                                return 1
                            fi
                            if [[ "$c" == n ]]; then
                                echo "Prohibido 'git commit -n' ($x, --no-verify): se salta pre-commit y commit-msg."
                                return 1
                            fi
                            [[ "$c" == [mFcCt] ]] && break
                        done ;;
                esac
            done ;;
        config)
            # Escribir o quitar core.hooksPath desactiva los hooks (solo vale el valor del proyecto); un archivo
            # incluido podría traer otro. Leer sí se puede.
            # (get/list solo cuentan como subórdenes: en "git config core.hooksPath get", "get" es el valor)
            case " ${a[*],,} " in *" --get "*|*" --get-all "*|*" --get-regexp "*|*" --list "*|*" -l "*) return 0 ;; esac
            for x in "${a[@]}"; do
                [[ "$x" == -* ]] && continue
                [[ "${x,,}" == get || "${x,,}" == list ]] && return 0
                break
            done
            for (( j = 0; j < ${#a[@]}; j++ )); do
                _clave_salta_hooks "${a[j]}" || continue
                if [[ "${a[j],,}" != core.hookspath ]]; then
                    echo "Prohibido 'git config ${a[j]}': un archivo incluido puede cambiar core.hooksPath y saltarse los hooks."
                    return 1
                fi
                if [[ "${a[j+1]:-}" != tools/hooks ]] || [[ " ${a[*],,} " == *" --unset"* ]]; then
                    echo "Prohibido cambiar core.hooksPath: los hooks del proyecto van en tools/hooks."
                    return 1
                fi
            done ;;
        reset)
            for x in "${a[@]}"; do
                [[ "$x" == -- ]] && break
                for m in --hard --merge --keep --soft; do
                    if _opcion "$x" "$m"; then
                        echo "Prohibido 'git reset $x' ($m) en árbol compartido: borra cambios o deshace commits de otras sesiones."
                        return 1
                    fi
                done
            done
            # Sin rutas, "git reset <commit>" mueve la rama (también con un "--" sin nada detrás): deshace commits
            # que pueden ser de otra sesión
            for (( j = 0; j < ${#a[@]}; j++ )); do
                x="${a[j]}"
                if [[ "$x" == -- ]]; then (( j + 1 < ${#a[@]} )) && pos=(); break; fi
                [[ "$x" == -* ]] || pos+=("$x")
            done
            if (( ${#pos[@]} == 1 )) && _mueve_head "${pos[0]}"; then
                echo "Prohibido 'git reset ${pos[0]}' en árbol compartido: mueve la rama y deshace commits que pueden ser de otra sesión. Para sacar rutas del índice: git reset -- <rutas>."
                return 1
            fi ;;
        checkout|restore|switch)
            # -f / --discard-changes descartan los cambios de todo el árbol; una carpeta, "." o un comodín, los de
            # todos los archivos que abarcan (también los de otras sesiones). "restore --staged" solo toca el índice.
            local fuerza="" amplia="" staged=0 worktree=0 sep=0 valor=0
            for x in "${a[@]}"; do
                if (( valor )); then valor=0; continue; fi
                if (( ! sep )); then
                    case "$x" in
                        --) sep=1; continue ;;
                        --*)
                            { _opcion "$x" --force || _opcion "$x" --discard-changes; } && fuerza="$x"
                            _opcion "$x" --staged && staged=1
                            _opcion "$x" --worktree && worktree=1
                            [[ "$x" != *=* ]] && { _opcion "$x" --source || _opcion "$x" --orphan; } && valor=1
                            continue ;;
                        -?*)
                            f="${x#-}"
                            for (( j = 0; j < ${#f}; j++ )); do
                                c="${f:j:1}"
                                case "$c" in
                                    f) fuerza="$x" ;;
                                    S) staged=1 ;;
                                    W) worktree=1 ;;
                                    [bBcCs]) (( j + 1 == ${#f} )) && valor=1; break ;;  # llevan valor
                                esac
                            done
                            continue ;;
                    esac
                fi
                [[ -z "$amplia" ]] && _ruta_amplia "$x" && amplia="$x"
            done
            if [[ -n "$fuerza" && "$sub" != restore ]]; then
                echo "Prohibido 'git $sub $fuerza' en árbol compartido: descarta los cambios de otras sesiones."
                return 1
            fi
            [[ "$sub" == switch ]] && return 0
            [[ "$sub" == restore ]] && (( staged && ! worktree )) && return 0
            if [[ -n "$amplia" ]]; then
                echo "Prohibido 'git $sub ... $amplia': descarta los cambios de todo lo que abarca, también los de otras sesiones. Restaura solo tus archivos, uno a uno."
                return 1
            fi ;;
        clean)
            for x in "${a[@]}"; do
                if _opcion "$x" --force || [[ "$x" == -[!-]* && "$x" == *f* ]]; then
                    echo "Prohibido 'git clean -f' en árbol compartido."
                    return 1
                fi
            done ;;
    esac
    return 0
}

# Parte una línea de órdenes en segmentos (una orden simple por línea de salida) como lo haría la shell:
# corta por ; & | ( ) ` $( y saltos de línea, pero no dentro de comillas, tras \ ni en comentarios.
# Dentro de comillas los blancos salen como \037 (una palabra entre comillas sigue siendo un solo token) y
# las comillas desaparecen. El cuerpo de un heredoc no es orden: va detrás de su segmento tras \002, con
# los saltos de línea como \036 (quien llama decide si se ejecuta, p. ej. "bash <<EOF").
_AWK_SEGMENTOS='
function brk() { if (cur !~ /^[ \t]*$/) { nseg++; seg[nseg] = cur } cur = ""; ini = 1 }
function push(qq, bt) { sp++; pila[sp] = qq; pilab[sp] = bt }
function blanco(x) { return (x == " " || x == "\t" || x == "\n") }
{ s = s $0 "\n" }
END {
    SP = "\037"; NL = "\036"; BD = "\002"
    n = split(s, c, ""); cur = ""; q = ""; sp = 0; np = 0; ini = 1
    for (i = 1; i <= n; i++) {
        ch = c[i]
        if (q == "\047") { if (ch == "\047") q = ""; else cur = cur (blanco(ch) ? SP : ch); continue }
        if (q == "\"") {
            if (ch == "\\" && i < n) {
                nx = c[i + 1]
                if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { cur = cur nx; i++; continue }
                if (nx == "\n") { i++; continue }
            }
            if (ch == "\"") { q = ""; continue }
            if (ch == "$" && c[i + 1] == "(") { push(q, 0); q = ""; i++; brk(); continue }
            if (ch == "`") { push(q, 1); q = ""; brk(); continue }
            cur = cur (blanco(ch) ? SP : ch); continue
        }
        if (ch == "\\") { if (i < n) { i++; if (c[i] != "\n") cur = cur c[i] } ini = 0; continue }
        if (ch == "\047" || ch == "\"") { q = ch; ini = 0; continue }
        if (ch == "#" && ini) { while (i < n && c[i + 1] != "\n") i++; continue }
        if (ch == "<" && c[i + 1] == "<" && c[i + 2] == "<") { cur = cur "<<<"; i += 2; ini = 1; continue }
        if (ch == "<" && c[i + 1] == "<") {
            j = i + 2; dash = 0; d = ""
            if (c[j] == "-") { dash = 1; j++ }
            while (c[j] == " " || c[j] == "\t") j++
            while (j <= n && c[j] !~ /[ \t\n;&|<>()]/) {
                if (c[j] == "\047" || c[j] == "\"") { qd = c[j++]; while (j <= n && c[j] != qd) d = d c[j++]; j++; continue }
                if (c[j] == "\\") j++
                d = d c[j++]
            }
            # Sin palabra o numérica (p. ej. $((1<<2))): no es heredoc.
            if (d != "" && d !~ /^[0-9]+$/) { np++; hd[np] = d; hdd[np] = dash; hds[np] = nseg + 1; i = j - 1 }
            else { cur = cur "<<"; i++ }
            ini = 1; continue
        }
        if (ch == "$" && c[i + 1] == "(") { push("", 0); i++; brk(); continue }
        if (ch == "`") { if (sp > 0 && pilab[sp]) { q = pila[sp]; sp--; brk(); continue } push(q, 1); brk(); continue }
        if (ch == "(") { push("", 0); brk(); continue }
        if (ch == ")") { brk(); if (sp > 0 && !pilab[sp]) { q = pila[sp]; sp-- } continue }
        if (ch == ";" || ch == "&" || ch == "|") { brk(); continue }
        if (ch == "\n") {
            brk()
            for (k = 1; k <= np; k++) {
                b = ""
                while (i < n) {
                    l = ""; j = i + 1
                    while (j <= n && c[j] != "\n") l = l c[j++]
                    i = j; cmp = l
                    if (hdd[k]) sub(/^\t+/, "", cmp)
                    if (cmp == hd[k]) break
                    b = b l NL
                }
                cuerpo[hds[k]] = cuerpo[hds[k]] b
            }
            np = 0; continue
        }
        cur = cur ch; ini = (ch == " " || ch == "\t")
    }
    brk()
    for (j = 1; j <= nseg; j++) printf "%s%s\n", seg[j], ((j in cuerpo) ? BD cuerpo[j] : "")
}'

# Imprime los segmentos de una línea de órdenes (formato en _AWK_SEGMENTOS).
segmentos_orden() { printf '%s' "$1" | LC_ALL=C awk "$_AWK_SEGMENTOS"; }

_es_shell() { [[ "$1" =~ ^(ba|z|da|k)?sh(\.exe)?$ ]]; }

# Archivos que no se escriben desde la terminal: imprime "tablon" (docs/direccion/tablon.md) o "gitconfig"
# (.git/config o config.worktree, que pueden cambiar core.hooksPath).
_protegido() {
    local p="${1//\\//}"
    if [[ "${p##*/}" == tablon.md ]]; then echo tablon; return 0; fi
    [[ "$p" =~ (^|/)\.git/(worktrees/[^/]+/)?config(\.worktree)?$ ]] && { echo gitconfig; return 0; }
    return 1
}
# ¿Alguno de estos tokens escribe en un archivo protegido? Redirecciones (>, >>, >|, 2>, con o sin espacio) y tee.
# Imprime el tipo (ver _protegido).
_escribe_protegido() {
    local -a t=("$@")
    local i x dest
    for (( i = 0; i < ${#t[@]}; i++ )); do
        x="${t[i]}"
        [[ "$x" == *'>'* ]] || continue
        dest="${x##*>}"
        dest="${dest#|}"
        [[ -z "$dest" ]] && dest="${t[i+1]:-}"
        _protegido "$dest" && return 0
    done
    if [[ "$(_basename_cmd "${t[0]:-}")" == tee ]]; then
        for x in "${t[@]:1}"; do _protegido "$x" && return 0; done
    fi
    return 1
}

# Variables de entorno con las que git lee otra configuración (y con ella otro core.hooksPath).
# GIT_CONFIG_NOSYSTEM sí se permite: solo deja de leer la del sistema.
_es_var_config_git() {
    local v="$1"
    [[ "${v,,}" == '$env:'* ]] && v="${v:5}"
    case "${v^^}" in
        GIT_CONFIG|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*|GIT_CONFIG_PARAMETERS|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM) return 0 ;;
    esac
    return 1
}

# Recibe una línea de órdenes completa (puede llevar &&, ;, |, comillas, heredocs o varias líneas).
# Revisa también lo que de verdad se ejecuta dentro: bash -c "...", eval ... y heredocs pasados a una shell.
motivo_bloqueo_linea() {
    local linea="$1" prof="${2:-0}" seg cuerpo pendiente=""
    (( prof > 5 )) && return 0
    local -a tok
    while IFS= read -r seg; do
        cuerpo=""
        if [[ "$seg" == *$'\002'* ]]; then
            cuerpo="${seg#*$'\002'}"
            cuerpo="${cuerpo//$'\036'/$'\n'}"
            seg="${seg%%$'\002'*}"
        fi
        read -ra tok <<< "$seg"
        tok=("${tok[@]//$'\037'/ }")
        local k=0 n=${#tok[@]}
        # Saltar prefijos: VAR=valor, &, exec, env, command...
        while (( k < n )); do
            case "${tok[k]}" in
                *=*)
                    if _es_var_config_git "${tok[k]%%=*}"; then
                        # Configuración de git por entorno o en otro archivo: puede cambiar core.hooksPath
                        echo "Prohibido '${tok[k]%%=*}=...' delante de una orden: puede saltarse los hooks del proyecto."
                        return 1
                    fi
                    k=$((k + 1)) ;;
                '&'|'!'|'{'|exec|command|env|sudo|nohup|time|then|do|else) k=$((k + 1)) ;;
                *) break ;;
            esac
        done
        (( k < n )) || continue
        local cmd="${tok[k]}" base protegido x
        base="$(_basename_cmd "$cmd")"
        # export/declare GIT_CONFIG_*=... (o $env:GIT_CONFIG_COUNT = 1 en PowerShell) sirve para todas las órdenes siguientes
        if [[ "$base" == export || "$base" == declare || "$base" == typeset || "$base" == readonly || "$base" == local \
            || "${cmd,,}" == '$env:'* ]]; then
            for x in "${tok[@]:k}"; do
                if _es_var_config_git "${x%%=*}"; then
                    echo "Prohibido '${x%%=*}' en el entorno: git leería otra configuración y podría saltarse los hooks del proyecto."
                    return 1
                fi
            done
        fi
        if protegido="$(_escribe_protegido "${tok[@]:k}" || _escribe_protegido "${tok[@]:0:k}")"; then
            if [[ "$protegido" == gitconfig ]]; then
                echo "Prohibido escribir en la configuración de git desde la terminal: podría cambiar core.hooksPath y saltarse los hooks del proyecto."
            else
                echo "Prohibido escribir en el tablón desde la terminal. Usa ./tools/hooks/entregar.sh <rol> \"<qué>\" \"<ruta o commit>\" <destino> [-- <rutas>] (pone la hora real y commitea tu fila con tus rutas)."
            fi
            return 1
        elif [[ "$base" == git || "$base" == git.exe || "$base" == git_guard.sh ]]; then
            motivo_bloqueo_git "${tok[@]:k+1}" || return 1
        elif _es_motor "$cmd" || { x="$(_app_lanzada "${tok[@]:k}")"; [[ -n "$x" ]] && _es_motor "$x"; }; then
            echo "Prohibido lanzar el motor directamente. Usa ./tools/motor_silencioso.sh <rol> ... (sin sonido y con candado)."
            return 1
        elif [[ "$base" == with_lock.sh ]] && _es_motor "${tok[k+3]:-}"; then
            echo "Prohibido lanzar el motor con with_lock.sh: se salta el modo sin sonido. Usa ./tools/motor_silencioso.sh <rol> ..."
            return 1
        elif [[ "$base" == eval ]]; then
            motivo_bloqueo_linea "${tok[*]:k+1}" $((prof + 1)) || return 1
        elif _es_shell "$base"; then
            # bash -c "...": se revisa la cadena. bash a secas (lee de la entrada): su heredoc o, si no
            # tiene, los de órdenes anteriores (cat <<EOF | bash). bash script.sh no lee la entrada.
            local x c_opt="" posicional=0
            for (( x = k + 1; x < n; x++ )); do
                if [[ "${tok[x]}" =~ ^-[a-zA-Z]*c[a-zA-Z]*$ ]]; then c_opt="${tok[x+1]:-}"; break; fi
                [[ "${tok[x]}" == -* || "${tok[x]}" == *[\<\>]* ]] || { posicional=1; break; }
            done
            if [[ -n "$c_opt" ]]; then
                motivo_bloqueo_linea "$c_opt" $((prof + 1)) || return 1
            elif (( ! posicional )) && [[ -n "${cuerpo:-$pendiente}" ]]; then
                motivo_bloqueo_linea "${cuerpo:-$pendiente}" $((prof + 1)) || return 1
            fi
        elif [[ -n "$cuerpo" ]]; then
            pendiente+="$cuerpo"$'\n'
        fi
    done < <(segmentos_orden "$linea")
    return 0
}

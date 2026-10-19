# shellcheck shell=bash
# Reglas comunes de órdenes prohibidas. Fuente única para git_guard.sh y pre_tool_guard.sh.
# Uso: source tools/hooks/reglas_comando.sh
#      motivo=$(motivo_bloqueo_linea "<orden completa>") || echo "BLOQUEADO: $motivo"
#      motivo=$(motivo_bloqueo_git <args de git...>)       || echo "BLOQUEADO: $motivo"
# Devuelven 1 e imprimen el motivo si la orden está prohibida; 0 si está permitida.

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

# Recibe los argumentos que van detrás de "git".
motivo_bloqueo_git() {
    local -a t=("$@")
    local n=${#t[@]} i=0
    # Saltar opciones globales (git -C dir, -c clave=valor, --no-pager...)
    while (( i < n )); do
        case "${t[i]}" in
            -C|-c|--git-dir|--work-tree|--namespace) i=$((i + 2)) ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
        esac
    done
    local sub="${t[i]:-}"
    local -a a=("${t[@]:i+1}")
    local x f j c

    case "$sub" in
        stash)
            echo "Prohibido 'git stash' en árbol compartido. Usa commits por rutas."
            return 1 ;;
        add)
            for x in "${a[@]}"; do
                case "$x" in
                    -A|--all|--no-ignore-removal|.|./|:/|'*')
                        echo "Prohibido 'git add $x'. Usa 'git commit -m \"...\" -- <rutas exactas>'."
                        return 1 ;;
                esac
            done ;;
        commit)
            for x in "${a[@]}"; do
                case "$x" in
                    --) break ;;
                    --all)
                        echo "Prohibido 'git commit --all'. Usa 'git commit -m \"...\" -- <rutas exactas>'."
                        return 1 ;;
                    --*) ;;
                    -*)
                        # Grupos de opciones cortas: -a, -am, -sa... (tras m/F/c/C/t va un valor)
                        f="${x#-}"
                        for (( j = 0; j < ${#f}; j++ )); do
                            c="${f:j:1}"
                            if [[ "$c" == a ]]; then
                                echo "Prohibido 'git commit -a' ($x). Usa 'git commit -m \"...\" -- <rutas exactas>'."
                                return 1
                            fi
                            [[ "$c" == [mFcCt] ]] && break
                        done ;;
                esac
            done ;;
        reset)
            for x in "${a[@]}"; do
                if [[ "$x" == --hard || "$x" == --merge || "$x" == --keep ]]; then
                    echo "Prohibido 'git reset $x' en árbol compartido: borra cambios de otras sesiones."
                    return 1
                fi
            done ;;
        checkout|restore)
            for x in "${a[@]}"; do
                if [[ "$x" == . || "$x" == ./ || "$x" == :/ || "$x" == '*' ]]; then
                    echo "Prohibido 'git $sub ... $x': descarta cambios de otras sesiones. Restaura solo tus rutas."
                    return 1
                fi
            done ;;
        clean)
            for x in "${a[@]}"; do
                if [[ "$x" == --force || ( "$x" == -[!-]* && "$x" == *f* ) ]]; then
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
                *=*|'&'|'!'|'{'|exec|command|env|sudo|nohup|time|then|do|else) k=$((k + 1)) ;;
                *) break ;;
            esac
        done
        (( k < n )) || continue
        local cmd="${tok[k]}" base
        base="$(_basename_cmd "$cmd")"
        if [[ "$base" == git || "$base" == git.exe || "$base" == git_guard.sh ]]; then
            motivo_bloqueo_git "${tok[@]:k+1}" || return 1
        elif _es_motor "$cmd"; then
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

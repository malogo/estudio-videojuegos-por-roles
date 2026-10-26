# shellcheck shell=bash
# Parar un árbol de procesos entero (DUEÑO: arquitecto-sistemas). Lo usan tools/despachador.sh (sesiones de claude) y
# tools/motor_silencioso.sh (tope de tiempo del motor): matar solo el proceso directo deja vivos a los nietos, p. ej.
# un motor colgado que retiene el candado "motor" mientras viva (with_lock.sh) y deja los lotes siguientes en 75.
# Uso: source tools/hooks/procesos.sh
#      proceso_vivo <pid>
#      parar_arbol <pid> <segundos> [<marca>]
#   TERM a <pid> y a su árbol (y CONT, por si alguno está detenido); lo que siga vivo a los <segundos>, KILL. No hace `wait`:
#   eso queda para quien lo lanzó.
#   El árbol se apunta ANTES de enviar nada (al morir un padre, sus hijos pierden el enlace) y suma:
#   - los descendientes por PPID (`ps -A -o pid,ppid,pgid`; en Git Bash, el `ps` de Cygwin, que sigue los exec);
#   - su grupo de procesos, si <pid> lo encabeza (lanzado con `set -m`): ahí siguen los huérfanos que ya perdieron el PPID;
#   - los procesos con <marca> ("NOMBRE=valor" exacto) en su entorno (/proc/<pid>/environ: Linux y Git Bash). En Windows
#     es lo que alcanza al Git Bash que abre un `claude` nativo: no es hijo de Cygwin ni está en su grupo;
#   - en Git Bash, `taskkill //T //F` del PID de Windows de <pid> (/proc/<pid>/winpid): los hijos nativos de un proceso
#     nativo. Solo de <pid>: en Cygwin los PPID de Windows no siguen los exec y pueden apuntar a PIDs ya reutilizados.

# "pid ppid pgid winpid" por proceso (winpid "-" fuera de Git Bash)
_tabla_procesos() {
    if [[ -r "/proc/$$/winpid" ]]; then
        # ps de Cygwin: PID PPID PGID WINPID ..., a veces con una letra de estado delante
        ps 2>/dev/null | awk 'NR > 1 { i = ($1 ~ /^[0-9]+$/) ? 1 : 2; print $i, $(i + 1), $(i + 2), $(i + 3) }'
    else
        ps -A -o pid= -o ppid= -o pgid= 2>/dev/null | awk '{ print $1, $2, $3, "-" }'
    fi
}

# _arbol <pid> [<marca>]: "pid winpid" de <pid>, su grupo, los que llevan <marca> y los descendientes de todos ellos
_arbol() {
    local raiz="$1" marca="${2:-}" f
    local -a semillas=("$raiz")
    if [[ -n "$marca" && -d "/proc/$$" ]]; then
        while IFS= read -r f; do f="${f#/proc/}"; semillas+=("${f%/environ}"); done \
            < <(grep -lzxF -- "$marca" /proc/[0-9]*/environ 2>/dev/null)
    fi
    _tabla_procesos | awk -v s="${semillas[*]}" -v r="$raiz" -v yo="$$" '
        { pid[NR] = $1; padre[NR] = $2; grupo[NR] = $3; win[$1] = $4 }
        END {
            n = split(s, l, " ")
            for (i = 1; i <= n; i++) dentro[l[i]] = 1
            for (i = 1; i <= NR; i++) if (grupo[i] == r) dentro[pid[i]] = 1
            do {
                mas = 0
                for (i = 1; i <= NR; i++) if (!(pid[i] in dentro) && (padre[i] in dentro)) { dentro[pid[i]] = 1; mas = 1 }
            } while (mas)
            delete dentro[yo]
            for (p in dentro) if (p in win) print p, win[p]
        }'
}

# proceso_vivo <pid>: responde a kill -0 y no es un zombi sin recoger (en Linux y macOS kill -0 lo daría por vivo; en
# Cygwin un zombi ya no responde)
proceso_vivo() {
    kill -0 "$1" 2>/dev/null || return 1
    [[ -r "/proc/$$/winpid" ]] && return 0
    [[ "$(ps -o stat= -p "$1" 2>/dev/null)" != *Z* ]]
}

parar_arbol() {
    local raiz="$1" seg="$2" marca="${3:-}" p w i vivo
    local -a pids=()
    while read -r p w; do pids+=("$p"); done < <(_arbol "$raiz" "$marca")
    if [[ -r "/proc/$raiz/winpid" ]] && command -v taskkill >/dev/null 2>&1; then
        w="$(cat "/proc/$raiz/winpid" 2>/dev/null)"
        [[ "$w" =~ ^[0-9]+$ ]] && taskkill //T //F //PID "$w" >/dev/null 2>&1
    fi
    (( ${#pids[@]} )) || return 0
    kill -TERM "${pids[@]}" 2>/dev/null
    # Un proceso detenido (SIGTTIN al leer la terminal desde otro grupo, SIGSTOP) no atiende TERM hasta que sigue; sin esto
    # esperaría los <segundos> enteros y moriría con KILL. En Git Bash (Cygwin) TERM ya lo despierta; en Linux y macOS no.
    kill -CONT "${pids[@]}" 2>/dev/null
    for (( i = 0; i < seg * 5; i++ )); do
        vivo=0
        for p in "${pids[@]}"; do proceso_vivo "$p" && { vivo=1; break; }; done
        (( vivo )) || return 0
        sleep 0.2
    done
    # Lo que siga vivo, y lo que haya aparecido entretanto en su grupo o con su marca
    while read -r p w; do pids+=("$p"); done < <(_arbol "$raiz" "$marca")
    kill -KILL "${pids[@]}" 2>/dev/null
    return 0
}

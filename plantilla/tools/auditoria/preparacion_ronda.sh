#!/usr/bin/env bash
# Puerta antes de lanzar una ronda (DUEÑO: auditor-calidad). Bash puro, sin motor.
# Uso: ./tools/auditoria/preparacion_ronda.sh <N> [--raiz DIR]
#   <N>     ronda que se quiere lanzar (entero >= 1)
#   --raiz  repositorio que se comprueba (por defecto, el que contiene este script)
#
# Comprueba la FORMA, no la calidad: que la especificación y el plan tengan escrito lo que pide el nivel de autonomía
# (línea "**Nivel de autonomía:** `<nivel>`" de docs/direccion/especificaciones.md). Lo que falta por decidir se
# marca siempre "(POR ESCRIBIR: …)".
# 1. Todos los niveles: plan_nocturno.md tiene algún lote "(ronda N)" en la columna Lote y al menos uno `pendiente` o
#    `en curso`; cada uno con rol válido, criterio de hecho, comando de comprobación sin "...", "<…>" ni
#    "(POR ESCRIBIR" y un estado conocido. En `bajo`, si no hay lotes de la ronda, lo dice y sale con 0 (se lanza
#    lote a lote).
# 2. `medio` y `alto`: §1 de la especificación sin "(POR ESCRIBIR"; en §2 y §3, cada apartado "### … (ronda M)" con
#    M <= N sin "(POR ESCRIBIR", y al menos un apartado de §2 con M <= N.
# 3. `alto`: §1-§4 enteras sin "(POR ESCRIBIR"; la comprobación 1 para los lotes de todas las rondas (cada uno con su
#    "(ronda M)"); cada "tras X" de la columna Lote apunta a un lote que existe; la Cuota de la cabecera del plan
#    definida (ni "a decidir" ni "(POR ESCRIBIR").
# Columnas del plan: | # | Rol | Lote | Criterio de hecho | Comando de comprobación | Estado |. Un "|" dentro de una
# celda va escapado ("\|"); mejor aún, el comando en un script de tests.
# Sale con 0 si la ronda está lista, 1 si no (imprime lo que falta, como mucho 20 líneas), 2 si no se puede
# comprobar (falta un archivo o el nivel es ilegible) y 64 si se usa mal.

set -uo pipefail
# Locale UTF-8 para recortar textos con tildes por caracteres (no bytes). macOS no tiene C.UTF-8.
LOCALE_UTF8=C.UTF-8
if command -v locale >/dev/null 2>&1; then
    LOCALE_UTF8="$(locale -a 2>/dev/null | grep -ixE 'c\.utf-?8|en_US\.utf-?8' | head -n1 || true)"
fi
[[ -n "$LOCALE_UTF8" ]] && export LC_ALL="$LOCALE_UTF8"

uso() { echo "Uso: $0 <N> [--raiz DIR]   (N = ronda que se quiere lanzar, entero >= 1)" >&2; exit 64; }
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RONDA=""
while (( $# )); do
    case "$1" in
        --raiz) [[ -n "${2:-}" ]] || uso; RAIZ="$2"; shift 2 ;;
        [0-9]*) [[ -z "$RONDA" && "$1" =~ ^[1-9][0-9]*$ ]] || uso; RONDA="$1"; shift ;;
        *) uso ;;
    esac
done
[[ -n "$RONDA" ]] || uso
RAIZ="$(cd "$RAIZ" 2>/dev/null && pwd)" || { echo "No existe la carpeta de --raiz" >&2; exit 2; }
# Roles del proyecto (ROLES_VALIDOS)
# shellcheck source=../hooks/propiedad.sh
source "$RAIZ/tools/hooks/propiedad.sh"

ESPEC="$RAIZ/docs/direccion/especificaciones.md"
PLAN="$RAIZ/docs/direccion/plan_nocturno.md"
for f in "$ESPEC" "$PLAN"; do
    [[ -f "$f" ]] || { echo "No existe ${f#"$RAIZ"/}: no se puede comprobar la ronda" >&2; exit 2; }
done
leer() { tr -d '\r' < "$1"; }
recortar() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
es_rol() { local r; for r in "${ROLES_VALIDOS[@]}"; do [[ "$1" == "$r" ]] && return 0; done; return 1; }

NIVEL="$(leer "$ESPEC" | sed -nE 's/^\*\*Nivel de autonomía:\*\*[[:space:]]*`([^`]*)`.*/\1/p' | head -n1)"
case "$NIVEL" in
    bajo|medio|alto) ;;
    *) echo "Nivel de autonomía ilegible en docs/direccion/especificaciones.md (se espera la línea" \
            "**Nivel de autonomía:** \`bajo|medio|alto\`; hay: '${NIVEL:-nada}')" >&2; exit 2 ;;
esac

FALTAS=()
falta() { FALTAS+=("$1"); }
MARCA='(POR ESCRIBIR'
HUECO='<[^<>]+>'   # "<ruta>", "<rol dueño>"... (en una variable: escrito en el [[ =~ ]], "\<" sería un ancla de palabra)

# --- Plan: lotes ---------------------------------------------------------------------------
# Un lote = fila "| <n> | ..." con su id en negrita en la columna Lote (**A1**). Se recorren todas para saber qué ids
# existen ("tras X"); se comprueban las de la ronda N (en alto, todas).
declare -A EXISTE=()
FILAS=()
while IFS= read -r LINEA; do
    LINEA="${LINEA//\\|/$'\x1f'}"   # "\|" escapado dentro de una celda
    IFS='|' read -r _ _ ROL LOTE CRITERIO COMANDO ESTADO _ <<< "$LINEA"
    [[ "$LOTE" =~ \*\*([A-Za-z]+[0-9]+)\*\* ]] || continue
    EXISTE[${BASH_REMATCH[1]}]=1
    FILAS+=("$LINEA")
done < <(leer "$PLAN" | grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|')

N_RONDA=0 N_ACTIVOS=0
for LINEA in "${FILAS[@]}"; do
    IFS='|' read -r _ _ ROL LOTE CRITERIO COMANDO ESTADO _ <<< "$LINEA"
    [[ "$LOTE" =~ \*\*([A-Za-z]+[0-9]+)\*\* ]]
    ID="${BASH_REMATCH[1]}"
    M=""
    [[ "$LOTE" =~ \(ronda[[:space:]]+([0-9]+) ]] && M="${BASH_REMATCH[1]}"
    if [[ "$M" != "$RONDA" ]]; then
        [[ "$NIVEL" == alto ]] || continue
        [[ -n "$M" ]] || { falta "plan: lote $ID sin «(ronda M)» en la columna Lote (en nivel alto se planifican todas las rondas)"; continue; }
    fi
    ROL="$(recortar "$ROL")"; ESTADO="$(recortar "${ESTADO,,}")"
    CRITERIO="$(recortar "${CRITERIO//$'\x1f'/|}")"; COMANDO="$(recortar "${COMANDO//$'\x1f'/|}")"
    COMANDO_SIN="$(recortar "${COMANDO//\`/}")"
    es_rol "$ROL" || falta "plan: lote $ID con rol no válido «$ROL»"
    [[ -n "${CRITERIO//\`/}" && "$CRITERIO" != *"$MARCA"* ]] || falta "plan: lote $ID sin criterio de hecho"
    if [[ -z "$COMANDO_SIN" ]]; then
        falta "plan: lote $ID sin comando de comprobación"
    elif [[ "$COMANDO" == *...* || "$COMANDO" =~ $HUECO || "$COMANDO" == *"$MARCA"* ]]; then
        falta "plan: lote $ID con el comando de comprobación sin completar: ${COMANDO:0:80}"
    fi
    if [[ "$LOTE" =~ tras[[:space:]]+([^\)]*) ]]; then
        for DEP in $(grep -oE '[A-Za-z]+[0-9]+' <<< "${BASH_REMATCH[1]}"); do
            [[ "$NIVEL" == alto && -z "${EXISTE[$DEP]:-}" ]] && falta "plan: lote $ID va «tras $DEP», que no existe en el plan"
        done
    fi
    [[ "$M" == "$RONDA" ]] || continue
    N_RONDA=$((N_RONDA + 1))
    case "$ESTADO" in
        pendiente|"en curso"|en_curso) N_ACTIVOS=$((N_ACTIVOS + 1)) ;;
        hecho|entregado|terminado|completado|cerrado|validado|bloqueado|rechazado) ;;
        *) falta "plan: lote $ID con estado desconocido «$ESTADO»" ;;
    esac
done
if (( N_RONDA == 0 )); then
    if [[ "$NIVEL" == bajo ]]; then
        echo "Ronda $RONDA (nivel bajo): no hay lotes «(ronda $RONDA)» en el plan; en nivel bajo se lanza lote a lote."
        exit 0
    fi
    falta "plan: no hay ningún lote «(ronda $RONDA)» en la columna Lote de docs/direccion/plan_nocturno.md"
elif (( N_ACTIVOS == 0 )); then
    falta "plan: la ronda $RONDA no tiene lotes \`pendiente\` ni \`en curso\`"
fi

# --- Especificación ------------------------------------------------------------------------
if [[ "$NIVEL" != bajo ]]; then
    SEC=0 APARTADO="" M="" N_SISTEMAS=0 N=0
    declare -A VISTO=()   # una falta por apartado (o por sección, fuera de apartados): la de su primera línea
    while IFS= read -r LINEA; do
        N=$((N + 1))
        if [[ "$LINEA" =~ ^##[[:space:]]+([0-9]+)\. ]]; then
            SEC="${BASH_REMATCH[1]}"; APARTADO=""; M=""
            continue
        fi
        (( SEC >= 1 )) || continue
        if [[ "$LINEA" =~ ^###[[:space:]] ]]; then
            APARTADO="$(recortar "${LINEA#\#\#\#}")"; M=""
            [[ "$LINEA" =~ \(ronda[[:space:]]+([0-9]+)\) ]] && M="${BASH_REMATCH[1]}"
            (( SEC == 2 )) && [[ -n "$M" ]] && (( M <= RONDA )) && N_SISTEMAS=$((N_SISTEMAS + 1))
        fi
        [[ "$LINEA" == *"$MARCA"* && -z "${VISTO["$SEC|$APARTADO"]:-}" ]] || continue
        VISTO["$SEC|$APARTADO"]=1
        DONDE="especificaciones.md:$N (§$SEC${APARTADO:+, «${APARTADO:0:50}»})"
        if [[ "$NIVEL" == alto ]] && (( SEC <= 4 )); then
            falta "$DONDE: queda «POR ESCRIBIR» (nivel alto: §1-§4 enteras antes de la ronda 1)"
        elif (( SEC == 1 )); then
            falta "$DONDE: la visión general tiene «POR ESCRIBIR»"
        elif (( SEC == 2 || SEC == 3 )) && [[ -n "$M" ]] && (( M <= RONDA )); then
            falta "$DONDE: apartado de la ronda $M con «POR ESCRIBIR»"
        fi
    done < <(leer "$ESPEC")
    (( N_SISTEMAS > 0 )) || falta "especificaciones.md: §2 no tiene ningún apartado «### <sistema> (ronda M)» con M <= $RONDA"
fi

# --- Plan: cuota (alto) --------------------------------------------------------------------
if [[ "$NIVEL" == alto ]]; then
    CUOTA="$(leer "$PLAN" | sed -nE 's/.*\*\*Cuota:\*\*[[:space:]]*(.*)$/\1/p' | head -n1)"
    CUOTA="$(recortar "$CUOTA")"
    if [[ -z "$CUOTA" || "${CUOTA,,}" == *"a decidir"* || "$CUOTA" == *"$MARCA"* ]]; then
        falta "plan: la Cuota de la cabecera no está definida («${CUOTA:-vacía}»); en nivel alto es obligatoria"
    fi
fi

# --- Resultado -----------------------------------------------------------------------------
if (( ${#FALTAS[@]} == 0 )); then
    echo "Ronda $RONDA (nivel $NIVEL): lista para lanzar."
    exit 0
fi
echo "Ronda $RONDA (nivel $NIVEL): NO está lista. Falta (${#FALTAS[@]}):"
MAX=17
for (( i = 0; i < ${#FALTAS[@]} && i < MAX; i++ )); do echo "- ${FALTAS[i]}"; done
(( ${#FALTAS[@]} > MAX )) && echo "… y $(( ${#FALTAS[@]} - MAX )) más."
echo "Lo que no se pueda completar ahora va a docs/direccion/pendientes_manana.md (normas §9)."
exit 1

#!/usr/bin/env bash
# Claude falso para las pruebas del despachador (DESPACHADOR_CLAUDE=tools/hooks/tests/claude_falso.sh): no necesita
# claude ni red. Con --help imprime las opciones que comprueba tools/despachador.sh.
# Sigue el guion $CLAUDE_FALSO_GUION, una línea por sesión: "<rol esperado> <acción>[+parar] [coste en USD]" (el
# contador va en "$CLAUDE_FALSO_GUION.n"). Si el rol no es $CLAUDE_ROL o se acaba el guion, sale con 3.
# Acciones: entrega (fila "Lote <id>: ..." hacia auditor-calidad), valida y rechaza (filas "Validado <id>" hacia
# coordinador y "Rechazo <id>" hacia el dueño), duda ("Duda <id>: ..." hacia coordinador), nada, sucio (deja sin
# commitear un archivo nuevo y otro cambiado en tools/hooks/, sin entregar), lento (tarda 30 s), colgado (deja la sobra
# de "sucio" y lanza tools/motor_silencioso.sh con un motor falso que no acaba: retiene el candado "motor" mientras
# viva), sordo (deja la sobra de "sucio" e ignora TERM, ella y sus hijos: solo muere con KILL) y turnos (sale con 1 y
# subtype error_max_turns). "+parar" crea .parar al acabar.
# El lote sale del prompt ("lote <id>") y el dueño, de "dueño: <rol>". Si existe $CLAUDE_FALSO_ARGS, apunta en él una
# línea por sesión con CLAUDE_ROL, DESPACHADOR y los argumentos ([uno] [otro]); y si en su entorno hay CANDADO_ESPERA_SENAL
# (no debe llegar: es solo del candado del despachador), lo apunta en "$CLAUDE_FALSO_ARGS.env".
# Imprime el JSON de --output-format json.

set -uo pipefail

if [[ "${1:-}" == --help ]]; then
    echo "Usage: claude [options] [prompt]"
    for o in "-p, --print" --permission-mode --allowedTools --disallowedTools --max-budget-usd --output-format \
             --no-session-persistence --model; do
        echo "  $o"
    done
    exit 0
fi
ARGS=("$@") PROMPT=""
for (( i = 0; i < ${#ARGS[@]}; i++ )); do [[ "${ARGS[i]}" == -p ]] && PROMPT="${ARGS[i+1]:-}"; done
if [[ -n "${CLAUDE_FALSO_ARGS:-}" ]]; then
    { printf 'CLAUDE_ROL=%s DESPACHADOR=%s' "${CLAUDE_ROL:-}" "${DESPACHADOR:-}"
      for a in "${ARGS[@]}"; do printf ' [%s]' "${a//$'\n'/ }"; done
      echo; } >> "$CLAUDE_FALSO_ARGS"
fi

[[ -n "${CANDADO_ESPERA_SENAL:-}" && -n "${CLAUDE_FALSO_ARGS:-}" ]] && echo "CANDADO_ESPERA_SENAL=$CANDADO_ESPERA_SENAL" >> "$CLAUDE_FALSO_ARGS.env"

GUION="${CLAUDE_FALSO_GUION:?Falta CLAUDE_FALSO_GUION}"
N=$(( $(cat "$GUION.n" 2>/dev/null || echo 0) + 1 ))
echo "$N" > "$GUION.n"
json() {  # json <subtype> <is_error> <coste> <texto>
    printf '{"type":"result","subtype":"%s","is_error":%s,"num_turns":3,"total_cost_usd":%s,"session_id":"falso-%s","result":"%s"}\n' \
        "$1" "$2" "$3" "$N" "$4"
}
LINEA="$(sed -n "${N}p" "$GUION")"
if [[ -z "$LINEA" ]]; then
    echo "claude falso: el guion no tiene sesión $N" >&2
    json error_during_execution true 0 "sin guion"; exit 3
fi
read -r ROL ACCION COSTE _ <<< "$LINEA"
COSTE="${COSTE:-0.1}"
if [[ "$ROL" != "${CLAUDE_ROL:-}" ]]; then
    echo "claude falso: la sesión $N esperaba el rol $ROL y CLAUDE_ROL es '${CLAUDE_ROL:-}'" >&2
    json error_during_execution true "$COSTE" "rol inesperado"; exit 3
fi
PARAR=0
[[ "$ACCION" == *+parar ]] && { PARAR=1; ACCION="${ACCION%+parar}"; }
ID="$(grep -oE 'lote [A-Za-z]+[0-9]+' <<< "$PROMPT" | head -n1)"; ID="${ID#lote }"
DUENO="$(grep -oE 'dueño: [a-z-]+' <<< "$PROMPT" | head -n1)"; DUENO="${DUENO#dueño: }"
E=./tools/hooks/entregar.sh
R=0 TIPO=success
case "$ACCION" in
    entrega) "$E" "$ROL" "Lote $ID: entrega falsa" "tools/" auditor-calidad > /dev/null || R=1 ;;
    valida) "$E" auditor-calidad "Validado $ID: comprobado (falso)" HEAD coordinador > /dev/null || R=1 ;;
    rechaza) "$E" auditor-calidad "Rechazo $ID: no cumple el criterio (falso)" HEAD "$DUENO" > /dev/null || R=1 ;;
    duda) "$E" "$ROL" "Duda $ID: ¿cuántas casillas sube el salto? (falsa)" docs/ coordinador > /dev/null || R=1 ;;
    nada) ;;
    sucio) echo sobra > tools/hooks/sobra_falsa.txt; echo "# sobra falsa" >> tools/hooks/tests/motor_falso.sh ;;
    lento) exec sleep 30 ;;
    colgado) echo sobra > tools/hooks/sobra_falsa.txt
             MOTOR_FALSO_TEXTO="motor colgado" MOTOR_FALSO_SEGUNDOS=120 ./tools/motor_silencioso.sh "$ROL" > /dev/null 2>&1 ;;
    sordo) echo sobra > tools/hooks/sobra_falsa.txt; trap '' TERM; sleep 60 ;;
    turnos) R=1 TIPO=error_max_turns ;;
    *) echo "claude falso: acción desconocida '$ACCION'" >&2; R=3 TIPO=error_during_execution ;;
esac
(( PARAR )) && touch .parar
if (( R )); then json "$TIPO" true "$COSTE" "$ACCION $ID"; else json "$TIPO" false "$COSTE" "$ACCION $ID"; fi
exit "$R"

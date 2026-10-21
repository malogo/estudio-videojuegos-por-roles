#!/usr/bin/env bash
# Motor falso para prueba_guardas.sh (MOTOR_BIN=tools/hooks/tests/motor_falso.sh): no necesita el motor real.
# Imprime $MOTOR_FALSO_TEXTO, luego $MOTOR_FALSO_LINEAS líneas de error numeradas, crea (o toca) los archivos de
# $MOTOR_FALSO_CREA (rutas relativas a la carpeta actual, separadas por espacios), espera $MOTOR_FALSO_SEGUNDOS con un
# `sleep` hijo (un motor colgado con un nieto, como un Godot que no acaba; su PID, en $MOTOR_FALSO_NIETO si se da) y
# sale con $MOTOR_FALSO_CODIGO.
# Ignora los argumentos (los silenciosos y la ruta del proyecto que añade motor_silencioso.sh).

set -uo pipefail

[[ -n "${MOTOR_FALSO_TEXTO:-}" ]] && printf '%s\n' "$MOTOR_FALSO_TEXTO"
for (( i = 1; i <= ${MOTOR_FALSO_LINEAS:-0}; i++ )); do
    echo "ERROR: fallo número $i en res://tools/motor_silencioso.sh:$i"
done
for f in ${MOTOR_FALSO_CREA:-}; do mkdir -p "$(dirname "$f")" && echo "uid://falso" >> "$f"; done
# El nieto en segundo plano (si se mata al motor, sigue vivo); su PID va a $MOTOR_FALSO_NIETO si se da
if [[ -n "${MOTOR_FALSO_SEGUNDOS:-}" ]]; then
    sleep "$MOTOR_FALSO_SEGUNDOS" &
    [[ -n "${MOTOR_FALSO_NIETO:-}" ]] && echo "$!" > "$MOTOR_FALSO_NIETO"
    wait "$!"
fi
exit "${MOTOR_FALSO_CODIGO:-0}"

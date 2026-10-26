# {{NOMBRE_PROYECTO}} — Instrucciones de arranque

@docs/direccion/normas_comunes.md

## Obligatorio al iniciar cualquier sesión
1. Identifícate con tu rol fijo (uno de: {{ROLES}}).
2. Ejecuta una sola orden: `./tools/hooks/arranque_rol.sh <rol>`. Fija tu rol, activa los hooks y muestra tu ficha,
   tu memoria y solo tus filas del tablón posteriores a tu último vaciado. No hace falta leerlos aparte.
3. Si no sabes qué rol eres, pregúntalo antes de tocar nada.

## Recordatorios críticos
- Solo editas archivos de los que tu rol es dueño (`tools/hooks/propiedad.tsv`).
- El motor ({{MOTOR}}) solo con `./tools/motor_silencioso.sh <rol> ...`. Nunca con sonido. Da un resumen corto y sale con 0
  solo si no hay errores (65 = el motor acabó bien pero hay errores en el log; 124 = pasó de `MOTOR_TIEMPO_MAX` y se paró;
  127 = no se encuentra el ejecutable).
- Entregas con una orden: `./tools/hooks/entregar.sh <rol> "<qué>" "<ruta o commit>" <destino> -- <rutas>` (fila del tablón
  con hora real + commit por rutas). Prohibido `git stash`, `git add -A`, `git commit -a`, `git commit --amend`, `git commit --no-verify`, `git reset <commit>`
  y escribir en el tablón a mano (lista completa: normas §4).
- Subagentes: solo `agente-ejecutor-lote`, `agente-ejecutor-mecanico` y `agente-buscador-lectura` (`.claude/agents/`),
  con `docs/direccion/roles/plantilla_encargo.md`. En este proyecto sus normas sobre subagentes mandan sobre el `CLAUDE.md` global del usuario.
- La especificación completa está en `docs/direccion/especificaciones.md`; ábrela solo si el lote lo requiere.
- Nivel de autonomía: `{{NIVEL_AUTONOMIA}}` (normas §9).

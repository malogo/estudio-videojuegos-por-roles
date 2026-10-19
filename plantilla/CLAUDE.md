# {{NOMBRE_PROYECTO}} — Instrucciones de arranque

@docs/direccion/normas_comunes.md

## Obligatorio al iniciar cualquier sesión
1. Identifícate con tu rol fijo (uno de: {{ROLES}}).
2. Ejecuta una sola orden: `./tools/hooks/arranque_rol.sh <rol>`. Fija tu rol, activa los hooks y muestra tu ficha,
   tu memoria y solo tus filas del tablón posteriores a tu último vaciado. No hace falta leerlos aparte.
3. Si no sabes qué rol eres, pregúntalo antes de tocar nada.

## Recordatorios críticos
- Solo editas archivos de los que tu rol es dueño (`tools/hooks/propiedad.tsv`).
- El motor ({{MOTOR}}) solo con `./tools/motor_silencioso.sh <rol> ...`. Nunca con sonido.
- Commits solo por rutas. Prohibido `git stash`, `git add -A`, `git commit -a`.
- Subagentes: solo `agente-ejecutor-lote`, `agente-ejecutor-mecanico` y `agente-buscador-lectura` (`.claude/agents/`),
  con `docs/direccion/roles/plantilla_encargo.md`. En este proyecto sus normas sobre subagentes mandan sobre el `CLAUDE.md` global del usuario.
- La especificación completa está en `docs/direccion/especificaciones.md`; ábrela solo si el lote lo requiere.

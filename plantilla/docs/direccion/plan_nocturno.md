# Plan Nocturno (DUEÑO: coordinador)
{{#SI NIVEL_AUTONOMIA=bajo}}
**Ventana:** sin ventana fija; cada lote lo lanza la persona responsable | **Cuota:** {{CUOTA}}
{{#FIN}}
{{#SI NIVEL_AUTONOMIA=medio}}
**Ventana:** sin ventana fija; las rondas las lanza `coordinador` cuando lo pide la persona responsable | **Cuota:** {{CUOTA}}
{{#FIN}}
{{#SI NIVEL_AUTONOMIA=alto}}
**Ventana:** sin ventana fija; las rondas se encadenan sin esperar a la persona responsable (normas §9) | **Cuota:** {{CUOTA}}
{{#FIN}}

## Reglas de la ronda
- Solo se trabaja en lotes ya decididos aquí; nada de alcance nuevo (eso va a `pendientes_manana.md`).
- Máximo de sesiones simultáneas: {{MAX_SESIONES}}, y nunca dos sobre la misma tanda o el mismo candado.
- Si un candado está ocupado (código 75), el rol pasa al siguiente lote de su cola.
- Cada lote termina con `./tools/hooks/entregar.sh` (commit por rutas + entrada en el tablón) hacia `auditor-calidad`.
- Si se agota la cuota: el coordinador declara la pausa en el tablón (qué sigue, qué espera).
- Una ronda no empieza hasta que sus dependencias (columna Lote, "tras X") están commiteadas y
  `./tools/auditoria/preparacion_ronda.sh <N>` sale con 0.

## Lotes
| # | Rol | Lote | Criterio de hecho | Comando de comprobación | Estado |
|---|-----|------|-------------------|-------------------------|--------|
| 1 | arquitecto-sistemas | **A1** (ronda 1). Estructura base del proyecto en el motor. | El proyecto abre sin errores con el wrapper. | `./tools/motor_silencioso.sh arquitecto-sistemas ...` | pendiente |

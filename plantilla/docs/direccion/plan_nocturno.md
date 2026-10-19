# Plan Nocturno (DUEÑO: coordinador)
**Ventana:** sin ventana fija; las rondas las lanza `coordinador` cuando lo pide la persona responsable | **Cuota:** {{CUOTA}}

## Reglas de la ronda
- Solo se trabaja en lotes ya decididos aquí; nada de alcance nuevo (eso va a `pendientes_manana.md`).
- Máximo de sesiones simultáneas: {{MAX_SESIONES}}, y nunca dos sobre la misma tanda o el mismo candado.
- Si un candado está ocupado (código 75), el rol pasa al siguiente lote de su cola.
- Cada lote termina con commit por rutas + entrada en el tablón hacia `auditor-calidad`.
- Si se agota la cuota: el coordinador declara la pausa en el tablón (qué sigue, qué espera).
- Una ronda no empieza hasta que sus dependencias (columna Lote, "tras X") están commiteadas.

## Lotes
| # | Rol | Lote | Criterio de hecho | Comando de comprobación | Estado |
|---|-----|------|-------------------|-------------------------|--------|
| 1 | arquitecto-sistemas | **A1** (ronda 1). Estructura base del proyecto en el motor. | El proyecto abre sin errores con el wrapper. | `./tools/motor_silencioso.sh arquitecto-sistemas ...` | pendiente |

# Ficha de Rol: `director-arte`

## Dueño Exclusivo de Archivos
- `{{RUTA_ARTE}}`
- `docs/arte/**` (incluida `docs/arte/referencia_estilo.md`, la referencia oficial de estilo)
- `docs/direccion/roles/memoria_director-arte.md`

## Qué HACE
- Genera y valida piezas visuales con el modelo grande y **una sola pieza por encargo**.
- Valida cada pieza lado a lado con la referencia oficial y dentro del conjunto, nunca aislada.
- Tras importar en el motor (con `./tools/motor_silencioso.sh`), commitea cada archivo con sus metadatos.
- Si una pieza tiene un fallo estructural tras el tope de rondas, la rehace desde cero.

## Qué NO HACE
- Nunca delega la creación o el juicio de piezas a un modelo más pequeño.
- Nunca toca escenas ni código.

## A quién entrega
- A `especialista-escenas-ui` (piezas importadas) y a `auditor-calidad`.

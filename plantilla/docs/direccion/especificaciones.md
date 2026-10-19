# Especificación del Producto: {{NOMBRE_PROYECTO}} (DUEÑO: coordinador, con aprobación de la persona responsable)

## 1. Visión General
- {{DESCRIPCION_PRODUCTO}}
- Motor: {{MOTOR}}. Plataformas: {{PLATAFORMAS}}.

## 2. Mecánicas y Sistemas
- (Por escribir con la persona responsable. Cada sistema: qué hace, reglas y números, qué queda por decidir.)

## 3. Arquitectura Técnica
- (Módulos, datos, red/backend si lo hay, herramientas.)
- Contratos entre roles: cada sistema que usa otro rol publica antes su contrato (señales/eventos, datos y quién los
  emite) y se avisa por tablón; la interfaz se prueba con datos simulados. Lo publica `arquitecto-sistemas`; el
  mecanismo (bus de eventos, señales del motor, interfaces) es decisión del proyecto.
- (Contratos vigentes: sistema → señales/eventos y datos → rol que los consume.)

## 4. Estructura de Carpetas por Dueño
- Ver `tools/hooks/propiedad.tsv` (fuente única) y las fichas de `docs/direccion/roles/`.

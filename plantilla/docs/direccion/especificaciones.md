# Especificación del Producto: {{NOMBRE_PROYECTO}} (DUEÑO: coordinador, con aprobación de la persona responsable)
**Nivel de autonomía:** `{{NIVEL_AUTONOMIA}}` (cambiarlo: normas §9 y actualizar.md)
> Lo que falta por decidir se marca siempre `(POR ESCRIBIR: …)`: es lo que busca `./tools/auditoria/preparacion_ronda.sh <N>`
> antes de lanzar una ronda. En nivel `medio`, los apartados `(ronda M)` con M ≤ N deben estar escritos; en `alto`, todo §1-§4.

## 1. Visión General
- {{DESCRIPCION_PRODUCTO}}
- Motor: {{MOTOR}}. Plataformas: {{PLATAFORMAS}}.

## 2. Mecánicas y Sistemas
Un apartado por sistema: `### <Sistema> (ronda N)` — qué hace, reglas y números, estados y casos borde.
### (POR ESCRIBIR: primer sistema) (ronda 1)
- (POR ESCRIBIR: reglas, números, estados y casos borde)

## 3. Arquitectura Técnica y Contratos entre Roles
- Contratos entre roles: cada sistema que usa otro rol publica antes su contrato (señales/eventos, datos y quién los
  emite) y se avisa por tablón; la interfaz se prueba con datos simulados. Lo publica `arquitecto-sistemas`; el
  mecanismo (bus de eventos, señales del motor, interfaces) es decisión del proyecto.
- Un contrato está «firmado» cuando a su apartado `### Contrato:` no le queda ningún marcador «POR ESCRIBIR».

Un apartado por contrato: `### Contrato: <sistema> (ronda N)` — señales/eventos y datos · rol emisor · rol consumidor.
### Contrato: (POR ESCRIBIR: sistema) (ronda 1)
- (POR ESCRIBIR: señales/eventos y tipos de datos · emisor · consumidor)

## 4. Criterios de Desempate y Topes (obligatoria en nivel `alto`)
- Prioridad ante dudas técnicas que no cambian la visión ni cuestan dinero: (POR ESCRIBIR: p. ej. simplicidad > rendimiento > flexibilidad)
- Rechazos de `auditor-calidad` por lote antes de `bloqueado`: {{MAX_RECHAZOS}}.
- Qué se escala siempre a la persona: compras, licencias/NDA, cambios de alcance o de visión.

## 5. Estructura de Carpetas por Dueño
- Ver `tools/hooks/propiedad.tsv` (fuente única) y las fichas de `docs/direccion/roles/`.

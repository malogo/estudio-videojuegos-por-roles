# Plantilla de Encargo a Subagente (DUEÑO: coordinador)
> Obligatoria en todo encargo a `agente-ejecutor-lote` o `agente-ejecutor-mecanico` (`.claude/agents/`).
> Los campos 1-6 coinciden con el PASO 0 de esos agentes: si falta uno o está vacío, el agente responde
> `ENCARGO RECHAZADO: falta <campo(s)>` y no hace nada. Los dos últimos solo los usa quien encarga.
> `agente-buscador-lectura` (solo lectura) no exige plantilla, pero mantiene el tope de 10 líneas.

```
1. Rol de origen: <uno de: {{ROLES}}>
2. Archivos exactos: <rutas, una por línea; solo del rol de origen>
3. Cambio pedido: <qué cambiar; en agente-ejecutor-mecanico, con el patrón a aplicar>
4. Criterio de hecho: <condición comprobable>
5. Comando de comprobación: <comando exacto; el motor solo con ./tools/motor_silencioso.sh <rol> ... (hecho = sale con 0)>
6. Tope de informe: 10 líneas
Agente: <agente-ejecutor-lote (high, código que exige diseño) | agente-ejecutor-mecanico (medium, patrón dado)>
Esfuerzo: <high | medium> (el fijado en el agente elegido)
```

## Registro en el commit del lote
Una línea por encargo en el cuerpo del commit, para medir coste y fallos
(con `./tools/hooks/entregar.sh ... --cuerpo "<línea>" -- <rutas>`):
`encargo: <agente> | <esfuerzo> | a la primera: <sí|no>`

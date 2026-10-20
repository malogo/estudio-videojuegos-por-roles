# Plan: niveles de autonomía (bajo, medio, alto)

Plan de acción autosuficiente para una sesión nueva (tras `/clear`): no hace falta el historial de la conversación.
Fecha: 2026-10-20. Rama: `claude/compassionate-lamport-aockgh` (parte de `10b745a`, CI verde en las 6 combinaciones).
Este archivo se borra cuando el plan esté hecho (como `propuestas/plan_endurecimiento.md`, quitado en `a81ff80`).

**Frase de arranque para la sesión nueva** (esfuerzo recomendado: alto):

> Lee `propuestas/plan_autonomia.md` y ejecútalo desde la fase 0. Un commit por fase, push a la rama y CI verde antes
> de pasar a la siguiente. Para al terminar la fase 7 y enséñame el borrador del ADR (fase 8). No implementes nada
> del nivel alto (fase 9) hasta que yo lo apruebe.

---

## 0. De dónde sale y qué se ha decidido

Propuesta externa: 3 niveles de autonomía, con la regla «cuanto menos intervenga la persona responsable durante la
ejecución, más detalle hace falta por adelantado» (especificación, contratos entre roles, criterios de comprobación).
El principio es correcto y se adopta. La redacción original tenía fallos, comprobados contra el código:

| # | Fallo de la propuesta original | Decisión |
|---|---|---|
| 1 | Metía la comprobación de detalle en `auditoria_proceso.sh`: en el paso 10 de `desplegar.md` la especificación siempre está «(Por escribir)» (la escribe después el coordinador con la persona) y el despliegue por defecto (`medio`, A2 «(por describir)») dejaría de dar 0 hallazgos. | La puerta va en un script propio, `tools/auditoria/preparacion_ronda.sh <N>`, que se pasa **antes de lanzar una ronda**. La auditoría solo la usa para rondas **en curso**. |
| 2 | El hallazgo iba en la sección 4 de la auditoría, y el informe recorre las secciones 1 a 5 a fuego (`auditoria_proceso.sh`, bucles `for i in 1 2 3 4 5`). | Sección 6 nueva, con su título y los bucles a 1-6. |
| 3 | Los patrones (`(Por escribir`, `(por describir)`) no cazan «(Módulos, datos…)» ni «(Contratos vigentes…)». | Un único marcador en toda la especificación: `(POR ESCRIBIR: …)`. |
| 4 | E0 iba en el bloque E, pero el despliegue pregunta A→F (`desplegar.md`, paso 3) y A2 dependía de E0. | Es la pregunta **A0**, la primera de todas. |
| 5 | En nivel alto pedía la especificación completa en A2 (`DESCRIPCION_PRODUCTO`), que se copia en `normas_comunes.md` §10, cargada en todas las sesiones. | A2 sigue siendo 1-2 frases en todos los niveles. El detalle va en `especificaciones.md` §2-§4 y lo exige la puerta, no el cuestionario. |
| 6 | `rellenar_plantilla.py` solo sustituye textos y listas: los tres niveles acabarían escritos en la §9 de todas las sesiones. | Bloques condicionales en `rellenar_plantilla.py` (fase 1). |
| 7 | Contradecía cuatro sitios que dicen que las rondas solo las lanza la persona: `plan_nocturno.md:2`, `roles/coordinador.md:17`, `normas_comunes.md` §9 y readme 6.2/6.6. | Se condicionan por nivel (fase 4). |
| 8 | El nivel alto (despachador) estaba en una frase: cómo se despierta a cada rol, permisos sin nadie delante, rama/merge, tope de gasto, parada. | Se diseña aparte en un ADR (fase 8). Se implementa solo si la persona lo aprueba (fase 9). |
| 9 | El aviso de contexto (`aviso_contexto.sh`) depende de la línea de estado, que no existe en `claude -p`. | En nivel alto, una sesión nueva por lote: no hay contexto que vigilar. |
| 10 | «Contrato firmado» sin definir; «3 intentos» escrito a fuego dentro de una sección «(por definir)». | Contrato = apartado `### Contrato: …` de §3 sin `(POR ESCRIBIR`. Tope = clave `MAX_RECHAZOS` (3 por defecto). |

**Decisiones ya tomadas (no reabrir):**
- Clave `NIVEL_AUTONOMIA` ∈ `bajo` | `medio` | `alto`; por defecto `medio` (= cómo funciona hoy el sistema).
- Clave `MAX_RECHAZOS` (entero ≥ 1; por defecto 3): rechazos de `auditor-calidad` por lote antes de `bloqueado`.
- Fuente única del nivel en un proyecto desplegado: la línea `**Nivel de autonomía:** \`<nivel>\`` de
  `docs/direccion/especificaciones.md` (la cambia `coordinador` con aprobación de la persona). La auditoría avisa
  si no coincide con el nivel escrito en la cabecera de la §9 de las normas.
- La puerta es determinista y comprueba **forma**, no calidad: que no queden marcadores, que cada lote tenga
  criterio y comando ejecutables. Lo dice así el readme (límites).
- Nada del nivel alto fusiona en la rama principal ni hace push: trabaja en una rama propia y la persona fusiona.

**Fuera de alcance:** sandbox por rol, pasar normas a skills, agent teams (siguen siendo experimentales y no aplican
los hooks de las fichas de agente). Ya se descartaron en la auditoría.

---

## 1. Matriz de niveles (lo que se implementa)

| Dimensión | `bajo` (control paso a paso) | `medio` (rondas supervisadas; por defecto) | `alto` (flujo desatendido) |
|---|---|---|---|
| Quién lanza el trabajo | La persona, lote a lote. Copia los avisos entre ventanas y hace `/clear`. | La persona pide «lanza la ronda N»; el coordinador despierta a los roles hasta que `auditor-calidad` cierra la ronda. | El despachador (fase 9) encadena lotes y rondas; la persona revisa la rama al final. |
| Especificación antes de empezar | Basta §1. Lo demás se completa lote a lote. | Antes de la ronda N: los apartados de §2 y §3 marcados `(ronda M)` con M ≤ N, sin `(POR ESCRIBIR`. | Antes de la ronda 1: §1-§4 enteras sin `(POR ESCRIBIR`, incluida §4 (desempate y topes). |
| Plan nocturno | El lote que se va a lanzar, con criterio y comando. | Todos los lotes de la ronda N, con criterio y comando. | Todas las rondas, con criterio, comando y dependencias («tras X») que existen. Cuota definida. |
| Dudas | Se pregunta al momento o va a `pendientes_manana.md` y se para. | A `pendientes_manana.md`, el lote pasa a `bloqueado` y el rol sigue con su cola. | Lo técnico interno lo decide `arquitecto-sistemas`/`coordinador` con §4 y lo apunta en su memoria. Solo se escala lo que implica compras, licencias/NDA o cambiar la visión. |
| Rechazos de `auditor-calidad` | Sin tope automático (decide la persona). | Tope `MAX_RECHAZOS`; después, `bloqueado` y aviso a la persona. | Igual, sin esperar a nadie: `bloqueado` y siguiente lote. |
| Contexto | La persona hace `/clear` tras cada lote. | `aviso_contexto.sh` avisa a 150k/250k; vuelco de memoria y `/clear`. | Una sesión nueva por lote (no depende de la línea de estado). |

---

## 2. Fases

Una fase = un commit (mensaje en español, como los anteriores: `Autonomía, fase N: …`). Tras cada commit: push y
esperar al CI (las 6 combinaciones). Si algo falla, se arregla antes de seguir.

### Fase 0 — Preparación (sin cambios)
1. `git status` limpio en `claude/compassionate-lamport-aockgh`; `git pull`.
2. Recrear los ayudantes de prueba en el scratchpad (sección 4 de este plan) y comprobar que el estado de partida
   está verde: `prueba_guardas.sh` → **149/149** en Godot y en Unity, y `shellcheck` limpio.
3. Leer, sin resumirlos aquí: `rellenar_plantilla.py`, `cuestionario.md`, `desplegar.md`, `actualizar.md`,
   `plantilla/docs/direccion/{especificaciones,normas_comunes,plan_nocturno}.md`, `roles/{coordinador,auditor-calidad}.md`,
   `plantilla/tools/auditoria/auditoria_proceso.sh`, `plantilla/tools/hooks/tests/prueba_guardas.sh` y
   `.github/workflows/prueba_plantilla.yml`.

### Fase 1 — Bloques condicionales en `rellenar_plantilla.py`
**Sintaxis** (líneas que solo contienen el marcador; se quitan al rellenar):
```
{{#SI NIVEL_AUTONOMIA=medio,alto}}
… líneas que solo van en esos niveles (pueden llevar otros marcadores) …
{{#FIN}}
```
- Se aplican antes de `rellenar_texto`, en todos los archivos de `plantilla/` y de `extras/`.
- Errores claros (`SystemExit`): bloque sin cerrar, `{{#FIN}}` suelto, bloques anidados (no se admiten), clave
  inexistente o que no sea texto.
- `{{#` no casa con `MARCADOR` (`[A-Z_]+` tras `{{`), así que no sale como «marcador sin rellenar»; si quedara alguno
  por error, el `grep "{{"` del CI lo caza.
- Validación al cargar `valores.json`: `NIVEL_AUTONOMIA` en `bajo|medio|alto` y `MAX_RECHAZOS` entero ≥ 1. Si faltan
  (proyectos de antes), `medio` y `3`, con un aviso impreso (lo necesita `actualizar.md`).
- Docstring del script: documentar la sintaxis.
- Ejemplos: `ejemplo_valores_godot_pc.json` y `ejemplo_valores_unity_pc.json` con `"NIVEL_AUTONOMIA": "medio"` y
  `"MAX_RECHAZOS": "3"`.

**Hecho cuando:** desplegar con los 3 niveles da solo el texto de ese nivel y ningún `{{`; un bloque sin cerrar da error.

### Fase 2 — Cuestionario y despliegue
- `cuestionario.md`, bloque A, fila nueva **A0** (la primera): «¿Qué nivel de autonomía quieres?», opciones `bajo` /
  `medio` / `alto` con una línea de qué implica cada uno (columna «Especificación antes de empezar» de la matriz),
  por defecto `medio`, clave `NIVEL_AUTONOMIA` · normas §9, `especificaciones.md`, plan, ficha de coordinador.
  Nota: en `medio` y `alto` el siguiente paso tras desplegar es escribir la especificación con el coordinador.
- A2 sin cambios de fondo (1-2 frases en todos los niveles). Su valor por defecto pasa a
  «(POR ESCRIBIR: descripción en 1-2 frases)» para que la puerta lo vea.
- Bloque E, fila nueva **E7**: «¿Cuántos rechazos de `auditor-calidad` por lote antes de bloquearlo?», por defecto
  3, clave `MAX_RECHAZOS` · `especificaciones.md` §4, normas §9, ficha de `auditor-calidad`.
- `desplegar.md`: paso 3 empieza por A0; paso 11 (cierre): en `medio`/`alto`, decir a la persona que la primera
  tarea del coordinador es la especificación y que `./tools/auditoria/preparacion_ronda.sh 1` dice lo que falta.
  El paso 10 no cambia (sigue esperando 0 hallazgos).

### Fase 3 — Plantilla de `especificaciones.md`
Estructura nueva (§3 conserva su número: la ficha de `arquitecto-sistemas` cita «`especificaciones.md` §3»):
```
# Especificación del Producto: {{NOMBRE_PROYECTO}} (DUEÑO: coordinador, con aprobación de la persona responsable)
**Nivel de autonomía:** `{{NIVEL_AUTONOMIA}}` (cambiarlo: normas §9 y actualizar.md)

## 1. Visión General
- {{DESCRIPCION_PRODUCTO}}
- Motor: {{MOTOR}}. Plataformas: {{PLATAFORMAS}}.

## 2. Mecánicas y Sistemas
Un apartado por sistema: `### <Sistema> (ronda N)` — qué hace, reglas y números, estados y casos borde.
### (POR ESCRIBIR: primer sistema) (ronda 1)
- (POR ESCRIBIR: reglas, números, estados y casos borde)

## 3. Arquitectura Técnica y Contratos entre Roles
- (texto actual sobre contratos, sin cambios)
Un apartado por contrato: `### Contrato: <sistema> (ronda N)` — señales/eventos y datos · rol emisor · rol consumidor.
### Contrato: (POR ESCRIBIR: sistema) (ronda 1)
- (POR ESCRIBIR: señales/eventos y tipos de datos · emisor · consumidor)

## 4. Criterios de Desempate y Topes (obligatoria en nivel `alto`)
- Prioridad ante dudas técnicas que no cambian la visión ni cuestan dinero: (POR ESCRIBIR: p. ej. simplicidad > rendimiento > flexibilidad)
- Rechazos de `auditor-calidad` por lote antes de `bloqueado`: {{MAX_RECHAZOS}}.
- Qué se escala siempre a la persona: compras, licencias/NDA, cambios de alcance o de visión.

## 5. Estructura de Carpetas por Dueño
- Ver `tools/hooks/propiedad.tsv` (fuente única) y las fichas de `docs/direccion/roles/`.
```
- Un contrato «firmado» = su apartado `### Contrato:` sin `(POR ESCRIBIR`. Normas §9 (nivel alto): ningún lote que
  consuma un contrato pasa a `en curso` si su contrato no está firmado.

### Fase 4 — Normas, fichas y plan por nivel
Con bloques `{{#SI …}}`:
- `normas_comunes.md` §9 → «## 9. Nivel de autonomía (`{{NIVEL_AUTONOMIA}}`), escalado y rondas», con el texto
  del nivel (columnas de la matriz). Comunes a todos: «no inventes decisiones de producto»; antes de lanzar la ronda N,
  `./tools/auditoria/preparacion_ronda.sh N` debe salir con 0 (si no, no se lanza y lo que falta va a
  `pendientes_manana.md`). Se mantiene el resto de líneas actuales de §9 que sigan valiendo.
- `normas_comunes.md` §8: tope `{{MAX_RECHAZOS}}` y formato de la fila de rechazo (abajo).
- `plan_nocturno.md` línea 2 (**Ventana**) y `roles/coordinador.md` línea 17: quién lanza las rondas, según el nivel.
- `roles/auditor-calidad.md`: un rechazo se anota siempre así (para contarlos de forma determinista):
  `./tools/hooks/entregar.sh auditor-calidad "Rechazo <lote>: <motivo>" "<ruta o commit>" <rol dueño>`.
- `CLAUDE.md`: una línea en «Recordatorios críticos»: «Nivel de autonomía: `{{NIVEL_AUTONOMIA}}` (normas §9)».
- Prosa de §10 y del resto: sin cambios.

### Fase 5 — Puerta `tools/auditoria/preparacion_ronda.sh`
Dueño `auditor-calidad` (ya cubierto por `tools/auditoria/**`). Estilo y estructura como `auditoria_proceso.sh`
(bash 4+, `source tools/hooks/propiedad.sh`, `--raiz DIR` para pruebas, comentarios de cabecera con uso y códigos).

`./tools/auditoria/preparacion_ronda.sh <N> [--raiz DIR]` → 0 lista · 1 no lista (imprime lo que falta, como mucho
20 líneas) · 2 no se puede comprobar (falta un archivo, nivel ilegible) · 64 uso incorrecto.

Lee el nivel de la línea `**Nivel de autonomía:**` de la especificación. Comprueba:
1. **Todos los niveles** — en `plan_nocturno.md` hay al menos un lote cuya columna «Lote» lleva `(ronda N)`, y cada
   uno tiene rol válido, criterio de hecho no vacío, comando de comprobación no vacío y sin `...`, `<…>` ni
   `(POR ESCRIBIR`, y estado `pendiente` o `en curso`. Columnas: `| # | Rol | Lote | Criterio | Comando | Estado |`
   (las mismas que ya lee `auditoria_proceso.sh` §4). Un comando con tubería debe ir escapado (`\|`) o, mejor, en un
   script de tests: documentarlo en la cabecera del plan.
2. **`medio` y `alto`** — §1 sin `(POR ESCRIBIR`; en §2 y §3, cada apartado `### … (ronda M)` con M ≤ N sin
   `(POR ESCRIBIR`, y al menos un apartado de §2 con M ≤ N.
3. **`alto`** — §1-§4 enteras sin `(POR ESCRIBIR` (todo el hito); la comprobación 1 para los lotes de **todas** las
   rondas; cada «tras X» de la columna Lote apunta a un lote que existe; la **Cuota** de la cabecera del plan
   definida (ni «a decidir» ni `(POR ESCRIBIR`).
4. **`bajo`** — solo la comprobación 1 (informa y sale con 0 si no hay lotes de esa ronda: en bajo se lanza lote a lote).

`auditoria_proceso.sh`:
- Sección **6** «Rondas en curso y nivel de autonomía»: por cada ronda con algún lote `en curso`, ejecuta la puerta;
  si sale con 1, un hallazgo con su primera falta. Además, un hallazgo si el nivel de la especificación no coincide
  con el de la cabecera de §9 de las normas. Títulos y bucles a 1-6.
- Sección 4, nuevo: un lote con `MAX_RECHAZOS` o más filas `| auditor-calidad | Rechazo <lote>` que no esté
  `bloqueado` (ni `hecho`/`entregado`) es hallazgo. El tope sale de §4 de la especificación (si no se puede leer, 3).
- En el despliegue (paso 10) no hay rondas en curso: sigue dando 0 hallazgos.

### Fase 6 — Pruebas y CI
`prueba_guardas.sh`, sección nueva «== Preparación de rondas (preparacion_ronda.sh)», con especificación y plan
sintéticos en el repo temporal (sin tocar el proyecto):
- `bajo`: lote con criterio y comando → 0; lote con `...` en el comando → 1 («comando»).
- `medio`: ronda 1 con su sistema escrito → 0; con `(POR ESCRIBIR` en un apartado `(ronda 1)` → 1; un apartado
  `(ronda 2)` pendiente no impide la ronda 1 → 0.
- `alto`: §4 con `(POR ESCRIBIR` → 1; «tras Z9» inexistente → 1; cuota «a decidir» → 1; todo completo → 0.
- Nivel ilegible → 2; sin argumento → 64.
- Auditoría con `--raiz`, `--informe` en `$TMP` y `--excepciones`: ronda en curso sin preparar → hallazgo en §6;
  3 rechazos de un lote no bloqueado → hallazgo en §4; niveles distintos en especificación y normas → hallazgo.

CI (`.github/workflows/prueba_plantilla.yml`), solo en Linux: paso «Los tres niveles de autonomía» que despliega
Godot con `NIVEL_AUTONOMIA` = `bajo`, `medio` y `alto` (copia de `ejemplo_valores_godot_pc.json` modificada con
python), y en cada uno comprueba: sin `{{`; la cabecera de §9 dice el nivel y no aparece el texto de los otros dos;
`preparacion_ronda.sh 1` sale con 1 en los tres niveles recién desplegados (el comando del lote A1 de la plantilla
lleva `...`) y en `medio`/`alto` además nombra la especificación; la auditoría sigue dando 0 hallazgos. Un valor
inválido (`"altisimo"`) hace fallar `rellenar_plantilla.py`.

**Hecho cuando:** CI verde en las 6 combinaciones más el paso nuevo.

### Fase 7 — Documentación
- `readme.txt`: §2 (una línea: niveles de autonomía), §3 (pieza «Nivel de autonomía»), §4 (mapa: `preparacion_ronda.sh`),
  §6.1 (en `medio`/`alto`, lo primero con el coordinador es la especificación), §6.6 (quién lanza las rondas según el
  nivel), §8 (límite: la puerta comprueba forma, no calidad; el nivel alto necesita el despachador de la fase 9).
- `actualizar.md`: «Avisos de esta versión»: claves nuevas (sin ellas, `medio` y `3`), bloques condicionales, marcador
  único `(POR ESCRIBIR: …)` (cambiar los «(Por escribir…)» viejos de la especificación del proyecto), fila de rechazo
  del auditor, y cómo **cambiar de nivel** en un proyecto ya desplegado: rellenar a `/tmp` con el nivel nuevo y
  fusionar §9, la ficha de coordinador, la línea 2 del plan y la línea del nivel de la especificación.
- Al acabar la fase: parar y enseñar a la persona el resultado y el plan de la fase 8.

### Fase 8 — ADR del despachador (nivel alto). Solo diseño · esfuerzo xhigh
`propuestas/adr_despachador.md` (formato ADR: contexto, opciones, decisión, consecuencias). Antes de escribirlo,
**verificar en la documentación actual de Claude Code** (code.claude.com/docs; no de memoria): opciones de `claude -p`
(`--permission-mode`, `--allowedTools`, `--max-turns`, `--model`, `--output-format json` y si da coste/uso), si los
hooks de `.claude/settings.json` se ejecutan en `-p`, y el estado de agent teams.

Debe decidir y justificar:
1. **Mecanismo.** Opciones: (a) `tools/despachador.sh` que lanza una sesión `claude -p` nueva por lote con
   «Eres <rol>. Tienes trabajo en el tablón…»; (b) el coordinador en una sesión interactiva que despierta a los demás
   con mensajes entre sesiones y `/loop`; (c) agent teams (experimental; necesita sesión interactiva). Recomendación de
   partida: (a), porque es determinista, se puede probar con un `claude` falso (como `motor_falso.sh`) y cada lote
   empieza con el contexto limpio.
2. **Permisos.** Sin nadie que apruebe, las guardas son la única barrera: qué modo de permisos y qué herramientas se
   permiten; recordar el límite conocido (las escrituras desde la terminal solo se detectan al hacer commit).
3. **Rama y fusión.** Trabaja en `autonomo/<fecha>` creada desde la rama principal; nunca push ni merge; al acabar,
   resumen para la persona.
4. **Topes y parada.** Gasto por ronda (de `CUOTA` y, si `-p` lo da, del coste real), `MAX_RECHAZOS`, máximo de turnos
   por lote, interruptor de parada (archivo `.parar` en `.gitignore` que se mira antes de cada lote), candado
   `despachador` con `with_lock.sh`, y qué pasa si el candado del motor está ocupado (75: otro lote o esperar).
5. **Estado del plan.** Quién marca `en curso`/`hecho`/`bloqueado` (una sesión `coordinador` entre lotes, o el propio
   script con `entregar.sh coordinador`), y cómo se detecta un lote que vuelve sin fila en el tablón (cuenta como fallo).
6. **Dudas.** Lo que va a `pendientes_manana.md` bloquea solo ese lote; el resto sigue.
7. **Registro.** `.despachador_logs/` (en `.gitignore`), resumen corto por lote (como `motor_silencioso.sh`).
8. **Pruebas.** `tools/hooks/tests/claude_falso.sh` y casos: lote ok, rechazo hasta el tope, parada con `.parar`,
   tope de gasto, candado ocupado.

Al acabar: commit del ADR, resumen de la decisión a la persona y pregunta explícita de aprobación.
**No se pasa a la fase 9 sin su aprobación.**

### Fase 9 — Implementar el despachador (solo con el ADR aprobado) · esfuerzo xhigh
- `plantilla/tools/despachador.sh` (dueño `arquitecto-sistemas`: fila nueva en `propiedad.tsv` y en su ficha), según el ADR.
- `.gitignore`: `.parar`, `.despachador_logs/`. Reglas de `reglas_comando.sh` si el ADR lo pide (p. ej. que una sesión
  no borre `.parar`).
- Pruebas con `claude_falso.sh` en `prueba_guardas.sh`; CI verde en las 6 combinaciones.
- Normas §9 (nivel alto), readme §6 y `actualizar.md`: cómo arrancarlo y pararlo.
- Al terminar todo: borrar este archivo (`propuestas/plan_autonomia.md`) en el último commit, como se hizo con el plan
  anterior.

---

## 3. Reglas de trabajo (para la sesión que ejecute el plan)

- Todo en español, con la densidad de comentarios y el estilo del código que rodea cada cambio (cabeceras con uso y
  códigos de salida; nombres en español; `set -uo pipefail`; bash 4+).
- Cada cambio de comportamiento con su prueba en `prueba_guardas.sh`; nada se da por hecho sin pasarla en **Godot y
  Unity**, `shellcheck -x -S warning` limpio y los pasos 7 a 10 de `desplegar.md` limpios (sección 4).
- No romper la interfaz existente: `entregar.sh`, `motor_silencioso.sh`, `with_lock.sh`, formato del tablón, nombres
  de rol, códigos 64/65/75.
- Los proyectos ya desplegados deben poder actualizarse con `actualizar.md` (claves nuevas con valor por defecto).
- Commits: mensaje en español, sin identificadores de modelo, con las líneas de atribución de la sesión. Push a
  `claude/compassionate-lamport-aockgh`. No abrir PR salvo que la persona lo pida.
- Si una fase descubre un fallo ajeno al plan, se arregla solo si es pequeño y se cuenta en el mensaje de commit;
  si no, se apunta para la persona.

---

## 4. Ayudantes de prueba (recrear en el scratchpad en la fase 0)

`desplegar.sh <motor> <destino>` — despliega como `desplegar.md` (pasos 4 y 7):
```bash
#!/usr/bin/env bash
set -e
M="$1"; D="$2"; REPO="${REPO:-/home/user/estudio-videojuegos-por-roles}"   # raíz de este repositorio
rm -rf "$D"; mkdir -p "$D"
python3 "$REPO/rellenar_plantilla.py" --valores "${VALORES:-$REPO/ejemplo_valores_${M}_pc.json}" --destino "$D" >/dev/null
cd "$D"; git init -q -b main .; git config user.name p; git config user.email p@e.invalid
git add -- CLAUDE.md .gitignore .gitattributes .claude docs tools
git add --chmod=+x -- $(grep -l '^#!' $(git ls-files -- tools))
git commit -q -m "coordinador: despliegue"
```
(`REPO=<ruta>` si el repositorio está en otra carpeta; `VALORES=<json>` para probar otro nivel.)

Comprobación completa de un despliegue (pasos 8 a 10 de `desplegar.md`, como el CI):
```bash
./tools/hooks/tests/prueba_guardas.sh | tail -1          # «Resultado: N/N pruebas OK»
./tools/hooks/arranque_rol.sh coordinador > /dev/null
./tools/hooks/entregar.sh coordinador "Despliegue inicial del sistema; primer lote A1 en el plan" docs/direccion/plan_nocturno.md arquitecto-sistemas
printf '# Commits que la comprobación 2 no revisa (hash y motivo)\n%s despliegue inicial\n' "$(git rev-list --max-parents=0 HEAD)" > tools/auditoria/excepciones_proceso.txt
./tools/hooks/entregar.sh auditor-calidad "Excepción del commit de despliegue" tools/auditoria/excepciones_proceso.txt coordinador -- tools/auditoria/excepciones_proceso.txt
./tools/auditoria/auditoria_proceso.sh                    # «0 hallazgo(s)»
git status --short | grep -v '^?? docs/calidad/'          # nada
shellcheck -x -S warning $(find tools -name '*.sh') tools/hooks/pre-commit tools/hooks/commit-msg
```
macOS (BSD `date`, bash de Homebrew y bash 3.2) y Windows (Git Bash, `core.autocrlf`) los cubre el CI: mirar sus
seis trabajos tras cada push.

---

## 5. Estado al pausar la fase 9 (2026-10-20, para retomar tras `/compact`)

**Frase para retomar:**
> Lee la sección 5 de `propuestas/plan_autonomia.md` y `propuestas/adr_despachador.md` (aprobado) y sigue la fase 9
> desde 9.3. Un commit por paso, push y CI verde (6 combinaciones) antes del siguiente; borra este plan en el último commit.

**Hecho (CI verde salvo el último, recién subido):** fases 0-8 (`34e16ef`…`7bd1728`), `bedf886` (prueba de candado sin
tiempos), 9.1 `32eff1b` (ADR aprobado con las respuestas y ajustes de la persona) y 9.2 `3a388dc` (`contrato:` y cuota
`<n> USD por ronda` en la puerta; auditoría §4 sin hallazgo para un `pendiente` fuera del tablón). 171/171 pruebas.

### 9.3 `reglas_comando.sh` (código escrito y probado a mano, sin pruebas automáticas; quitado del árbol)
Aplicar con `git apply` el parche de abajo (raíz del repo). Reglas: `.parar` no se toca nunca desde una sesión
(`rm|unlink|mv|cp|touch|truncate|ln|install`, redirecciones, `tee`); con `DESPACHADOR=1`, bloquea `git
push|pull|merge|rebase|switch`, `git checkout -b|-B|--orphan` (también agrupado, `-qb`), `git branch` salvo listar
(`git branch`, `-a -v`, `--show-current`, `--list <patrón>`) y lanzar `despachador.sh` (también `bash tools/despachador.sh`).
Falta: sección de pruebas en `prueba_guardas.sh` con `orden "..."` (permite/bloquea con y sin `DESPACHADOR=1`; ojo, `orden`
hace `env -u CLAUDE_ROL`, pasar `DESPACHADOR=1` delante: `DESPACHADOR=1 bash -c ...` o exportar y desexportar), casos:
`rm .parar`, `echo x > .parar`, `cat .parar` (permitido), `git push` (solo con 1), `git checkout HEAD -- f` y
`git branch --show-current` (permitidos con 1), `git branch nueva`, `bash tools/despachador.sh`, `cd x && git -C . push`.
Cabecera de `pre_tool_guard.sh`: mencionar `DESPACHADOR=1`. Commit «Autonomía, fase 9: reglas de .parar y del despachador».

```diff
diff --git a/plantilla/tools/hooks/reglas_comando.sh b/plantilla/tools/hooks/reglas_comando.sh
index 2ee22e8..2d7f639 100644
--- a/plantilla/tools/hooks/reglas_comando.sh
+++ b/plantilla/tools/hooks/reglas_comando.sh
@@ -4,6 +4,9 @@
 #      motivo=$(motivo_bloqueo_linea "<orden completa>") || echo "BLOQUEADO: $motivo"
 #      motivo=$(motivo_bloqueo_git <args de git...>)       || echo "BLOQUEADO: $motivo"
 # Devuelven 1 e imprimen el motivo si la orden está prohibida; 0 si está permitida.
+# Con DESPACHADOR=1 en el entorno (sesiones que lanza tools/despachador.sh) se prohíbe además publicar, fusionar o
+# cambiar de rama (git push, pull, merge, rebase, switch, checkout -b, branch salvo para listar) y lanzar otro
+# despachador: la sesión trabaja en la rama autonomo/... que creó él y la fusión la decide la persona responsable.
 
 # shellcheck source=requisitos.sh
 source "$(dirname "${BASH_SOURCE[0]}")/requisitos.sh"
@@ -74,6 +77,34 @@ _ruta_amplia() {
     [[ "$p" == . || "$p" == */ || "$p" == :* || "$p" == *[\*\?\[]* || -d "$p" ]]
 }
 
+# Con DESPACHADOR=1: imprime el motivo y devuelve 1 si la suborden <sub> [args...] publica, fusiona o cambia de rama.
+_git_despachador() {
+    local sub="$1" x lista=0 cambia=""
+    shift
+    case "$sub" in
+        push|pull|merge|rebase|switch) cambia="git $sub" ;;
+        checkout)
+            for x in "$@"; do
+                [[ "$x" == -- ]] && break
+                if [[ "$x" =~ ^-[a-zA-Z]*[bB] ]] || _opcion "$x" --orphan; then cambia="git checkout $x"; break; fi
+            done ;;
+        branch)
+            # Listar sí (git branch, -a, -v, --show-current, --list <patrón>); crear, borrar, renombrar o mover, no
+            for x in "$@"; do [[ "$x" == -l || "$x" == --list ]] && lista=1; done
+            for x in "$@"; do
+                case "$x" in
+                    -d|-D|--delete|-m|-M|--move|-c|-C|--copy|-f|--force|-u|--set-upstream-to*|--unset-upstream|--edit-description|-t|--track*|--no-track)
+                        cambia="git branch $x"; break ;;
+                    -*) ;;
+                    *) (( lista )) || { cambia="git branch $x"; break; } ;;
+                esac
+            done ;;
+    esac
+    [[ -z "$cambia" ]] && return 0
+    echo "Prohibido '$cambia' en una sesión del despachador (DESPACHADOR=1): se trabaja en la rama autonomo/... que creó él; publicar, fusionar y cambiar de rama lo decide la persona responsable."
+    return 1
+}
+
 # Recibe los argumentos que van detrás de "git".
 motivo_bloqueo_git() {
     local -a t=("$@")
@@ -103,6 +134,9 @@ motivo_bloqueo_git() {
     local -a a=("${t[@]:i+1}") pos=()
     local x f j c m
 
+    if [[ "${DESPACHADOR:-}" == 1 ]] && ! _git_despachador "$sub" "${a[@]}"; then
+        return 1
+    fi
     case "$sub" in
         stash)
             echo "Prohibido 'git stash' en árbol compartido. Usa commits por rutas."
@@ -320,11 +354,13 @@ segmentos_orden() { printf '%s' "$1" | LC_ALL=C awk "$_AWK_SEGMENTOS"; }
 
 _es_shell() { [[ "$1" =~ ^(ba|z|da|k)?sh(\.exe)?$ ]]; }
 
-# Archivos que no se escriben desde la terminal: imprime "tablon" (docs/direccion/tablon.md) o "gitconfig"
-# (.git/config o config.worktree, que pueden cambiar core.hooksPath).
+# Archivos que no se escriben desde la terminal: imprime "tablon" (docs/direccion/tablon.md), "gitconfig"
+# (.git/config o config.worktree, que pueden cambiar core.hooksPath) o "parar" (.parar, el interruptor de parada del
+# despachador: solo lo crea o lo borra la persona responsable desde su terminal).
 _protegido() {
     local p="${1//\\//}"
     if [[ "${p##*/}" == tablon.md ]]; then echo tablon; return 0; fi
+    if [[ "${p%/}" == .parar || "${p%/}" == */.parar ]]; then echo parar; return 0; fi
     [[ "$p" =~ (^|/)\.git/(worktrees/[^/]+/)?config(\.worktree)?$ ]] && { echo gitconfig; return 0; }
     return 1
 }
@@ -401,8 +437,27 @@ motivo_bloqueo_linea() {
                 fi
             done
         fi
+        # Órdenes que crean, borran, mueven o copian archivos: .parar no se toca desde una sesión
+        if [[ "$base" =~ ^(rm|unlink|mv|cp|touch|truncate|ln|install)(\.exe)?$ ]]; then
+            for x in "${tok[@]:k+1}"; do
+                if [[ "$(_protegido "$x")" == parar ]]; then
+                    echo "Prohibido tocar .parar desde una sesión ($base): es el interruptor de parada del despachador y solo lo crea o lo borra la persona responsable."
+                    return 1
+                fi
+            done
+        fi
+        if [[ "${DESPACHADOR:-}" == 1 ]]; then
+            x="$base"
+            _es_shell "$base" && x="$(_basename_cmd "${tok[k+1]:-}")"
+            if [[ "$x" == despachador.sh ]]; then
+                echo "Prohibido lanzar el despachador desde una de sus sesiones (DESPACHADOR=1): lo lanza la persona responsable desde su terminal."
+                return 1
+            fi
+        fi
         if protegido="$(_escribe_protegido "${tok[@]:k}" || _escribe_protegido "${tok[@]:0:k}")"; then
-            if [[ "$protegido" == gitconfig ]]; then
+            if [[ "$protegido" == parar ]]; then
+                echo "Prohibido escribir en .parar desde la terminal: es el interruptor de parada del despachador y solo lo crea o lo borra la persona responsable."
+            elif [[ "$protegido" == gitconfig ]]; then
                 echo "Prohibido escribir en la configuración de git desde la terminal: podría cambiar core.hooksPath y saltarse los hooks del proyecto."
             else
                 echo "Prohibido escribir en el tablón desde la terminal. Usa ./tools/hooks/entregar.sh <rol> \"<qué>\" \"<ruta o commit>\" <destino> [-- <rutas>] (pone la hora real y commitea tu fila con tus rutas)."
```

### 9.4 `tools/despachador.sh` + `tools/hooks/tests/claude_falso.sh` (por hacer; diseño en el ADR §3)
Decisiones de implementación ya tomadas (coherentes con el ADR):
- Cabecera con uso, opciones y códigos: 0 terminó (nada más lanzable; los bloqueados van al resumen), 1 paró antes
  (cuota, `.parar`, puerta no lista, árbol sucio al empezar ronda), 2 no arranca (nivel no `alto`, `claude --help` sin
  `--permission-mode --allowedTools --disallowedTools --max-turns --max-budget-usd --output-format --no-session-persistence`,
  `core.hooksPath` ≠ `tools/hooks`, árbol sucio, cuota ilegible, rama que no es `RAMA_PRINCIPAL` ni `autonomo/*`), 64 uso,
  75 otro despachador. `RAMA_PRINCIPAL="{{RAMA_PRINCIPAL}}"`, zona `{{ZONA_HORARIA}}` como `entregar.sh`.
- Todo dentro de `with_lock.sh despachador coordinador "$0" ...` (variable interna como `_ENTREGAR_CON_CANDADO`).
- Variables: `DESPACHADOR_CLAUDE` (defecto `claude`), `DESPACHADOR_MAX_TURNOS` 80, `DESPACHADOR_TIEMPO_MAX` 3600 s,
  `DESPACHADOR_MODELO` (opcional). Vigilante: claude en segundo plano, bucle `kill -0` cada 1 s, TERM y a los 30 s KILL.
- Sesión: `CLAUDE_ROL=<rol> DESPACHADOR=1 "$CLAUDE" -p "<prompt>" --permission-mode dontAsk --allowedTools "Bash Read Grep
  Glob Edit Write NotebookEdit Agent(agente-ejecutor-lote) Agent(agente-ejecutor-mecanico) Agent(agente-buscador-lectura)"
  --disallowedTools "WebFetch WebSearch Bash(./tools/despachador.sh*) Agent(Explore) Agent(general-purpose) Agent(Plan)
  Agent(claude)" --max-turns N --max-budget-usd <resto de la cuota, 2 decimales> --output-format json
  --no-session-persistence < /dev/null > r<N>_<ID>_<rol>_<k>.json 2> ….err`. JSON con `campos_json` de `leer_json.sh`
  (`total_cost_usd subtype num_turns is_error`); si falta el coste, se suma el tope entero de esa sesión.
- Prompt del rol: «Eres <rol>. Tienes trabajo en el tablón: lote <ID> de la ronda <N> (plan_nocturno.md), intento K.
  Trabajas sin nadie delante (nivel alto, normas §9): ./tools/hooks/arranque_rol.sh <rol>, haz el lote, pasa su comando
  de comprobación y entrégalo con ./tools/hooks/entregar.sh <rol> "Lote <ID>: <resumen>" "<ruta o commit>" auditor-calidad
  -- <rutas>. Duda que §4 no resuelve: entregar.sh <rol> "Duda <ID>: <pregunta>" x coordinador y termina. Sin push, merge
  ni cambios de rama.» + en reintentos «auditor-calidad lo rechazó: <motivo de la última fila Rechazo>».
- Prompt del auditor: «Eres auditor-calidad. Revisa el lote <ID> (ronda N; dueño: <rol>) … Si está bien:
  entregar.sh auditor-calidad "Validado <ID>: <qué comprobaste>" "<commit>" coordinador; si no: "Rechazo <ID>: <motivo>"
  hacia <rol>. Solo una de las dos.»
- Filas nuevas: guardar `wc -l` del tablón antes; después `tail -n +$((N+1))`; si `head -n N` cambió, fallo. Entrega =
  origen el rol y «qué» que empieza por el lote (regla awk de `auditoria_proceso.sh` §4); duda = `Duda <ID>`; auditor =
  `Validado <ID>` / `Rechazo <ID>` (si hay los dos, manda el rechazo; en el rol, si hay entrega y duda, manda la duda).
  Auditor sin fila: se repite una vez; si tampoco, `Fallo`.
- Intentos = filas `Rechazo <ID>` de auditor-calidad + filas `Fallo <ID>` de coordinador en el tablón (reanudable). Con
  `MAX_RECHAZOS` (de §4 de la especificación, como la auditoría) → `bloqueado` + entrada en `pendientes_manana.md`
  (formato `fecha | rol | pregunta | opciones | bloquea a`). Entre intentos el lote sigue `en curso`.
- Estado del plan: editar la celda Estado de la fila con `**ID**` (proteger `\|` como hace la puerta) y entregar como
  coordinador: `Encargo <ID> (ronda N, intento K): <texto>` → rol (pasa a `en curso`), `Fallo <ID>: <motivo>` → rol,
  `Estado <ID>: hecho|bloqueado (<motivo>)` → persona-responsable, `Pausa (ronda N): <motivo>; sigue <ID>` → persona-responsable.
- Dependencias «tras X»: terminadas = `hecho|entregado|validado|terminado|completado|cerrado`; dependencia `bloqueado` →
  `bloqueado` por dependencia. Ronda cerrada cuando no queda `pendiente|en curso` lanzable; ciclos se quedan y van al resumen.
- Candado del motor o de la build (`with_lock.sh --estado motor|{{CANDADO_BUILD}}` = ocupado/dudoso): posponer el lote
  una vez al final de la ronda; si sigue, `Fallo` sin lanzar sesión.
- Limpieza tras cada sesión (`git status --porcelain -z --untracked-files=all`): rutas cuyo `dueno_de_ruta` es el rol
  de la sesión → copia en `.despachador_logs/<ejecución>/sobras/<sesión>/`, y `git restore --source=HEAD --staged
  --worktree` (con historia) o `rm -f` (nuevas). Lo de otros dueños: al resumen; árbol sucio al empezar ronda → para.
- Registro: `.despachador_logs/<YYYY-MM-DD_HHMM>_<pid>/`, 10 últimas; `resumen.md` (rama, rondas, hechos, bloqueados con
  motivo, coste por ronda, motivo de parada, auditoría con `--informe` dentro de la carpeta, `git log --oneline
  RAMA_PRINCIPAL..<rama>`); una línea por sesión en la terminal.
- `claude_falso.sh`: `--help` imprime las opciones; guion `CLAUDE_FALSO_GUION` (una línea por sesión:
  `<rol esperado> <acción>[+parar] [coste]`, contador en un archivo junto al guion; rol distinto de `CLAUDE_ROL` → error);
  acciones `entrega`, `valida`, `rechaza`, `duda`, `nada`, `sucio` (crea `tools/hooks/sobra_falsa.txt` sin commitear y no
  entrega), `lento` (sleep 30), `turnos` (sale 1 con `subtype error_max_turns`); `+parar` hace `touch .parar` al acabar.
  Saca el ID del prompt (`lote ([A-Za-z]+[0-9]+)`) y el dueño (`dueño: ([a-z-]+)`); apunta argumentos y `CLAUDE_ROL`/
  `DESPACHADOR` en `CLAUDE_FALSO_ARGS`. Imprime `{"type":"result","subtype":…,"is_error":…,"num_turns":3,
  "total_cost_usd":<coste>,"session_id":"falso-<n>","result":"…"}`.
- Pruebas (sección nueva de `prueba_guardas.sh`, un repo temporal por escenario, `MAX_RECHAZOS` 2 o 1 en §4 para ir
  rápido): lote hecho (opciones de claude, `CLAUDE_ROL`, `DESPACHADOR=1`, rama `autonomo/*`, plan `hecho`); rechazo hasta
  el tope (`bloqueado`, pendiente, nunca `pendiente` entre intentos); sesión `sucio` (sobras limpiadas y copiadas, árbol
  limpio); duda (bloqueado y su dependiente también); `+parar` (sale 1, B1 sigue pendiente; quitar `.parar` y relanzar
  reanuda en la misma rama); cuota 1 USD con costes 0.7+0.5 (pausa, `--max-budget-usd 0.30` al auditor);
  `DESPACHADOR_TIEMPO_MAX=2` con `lento`; candado del motor ocupado; segundo despachador (75); nivel `medio` (2);
  `--simular` sin commits ni rama.
- También: fila `tools/despachador.sh	arquitecto-sistemas` en `propiedad.tsv` y en la ficha de arquitecto-sistemas;
  `.gitignore` con `.parar` y `.despachador_logs/`; shellcheck; CI (no hace falta paso nuevo: van en `prueba_guardas.sh`).

### 9.5 Documentación y cierre (por hacer)
Normas §9 (bloque `alto`: cómo se arranca y se para el despachador, cuota `<n> USD por ronda`, filas `Duda`/`Validado`),
ficha de auditor-calidad (`Validado <lote>` hacia coordinador), cuestionario E4 (formato de cuota en `alto`),
`readme.txt` §4 (mapa), §6.6 y §8 (quitar «está en diseño»), `actualizar.md` (avisos: despachador, reglas nuevas,
`.gitignore`, cuota en USD, `contrato:`, auditoría §4) y borrar este archivo en el último commit.

**Ayudantes de prueba** (scratchpad `/tmp/claude-0/-home-user-estudio-videojuegos-por-roles/df3d345d-80cf-5083-b180-56ad68aa629d/scratchpad`):
`desplegar.sh <motor> <destino>`, `comprobar.sh <despliegue>` (pasos 8-10 + shellcheck), `arbol.sh <destino> <rutas…>`
(HEAD + rutas del árbol) y `fase9_3_prueba_reglas_manual.sh`. Si se perdieron, recrearlos con la sección 4.


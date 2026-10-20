# ADR: despachador del nivel de autonomía `alto`

Fecha: 2026-10-20 · Estado: **aprobado** por la persona responsable el 2026-10-20, con las respuestas y ajustes de §5.
Origen: fase 8 del plan de niveles de autonomía; se implementa en la fase 9 (`plantilla/tools/despachador.sh`).

## 1. Contexto

Tras las fases 1 a 7, el nivel `alto` ya existe en las normas: antes de la ronda 1 la especificación está entera
(§1-§4, con criterios de desempate), el plan tiene todas las rondas con criterio, comando y dependencias, y
`preparacion_ronda.sh` lo comprueba. Pero quien encadena las rondas sigue siendo la ventana del coordinador:
alguien tiene que tener las sesiones abiertas, pasar avisos y hacer `/clear`. El objetivo es un flujo **realmente
desatendido**: lanzar una orden, irse, y volver a una rama con el trabajo hecho, lo bloqueado anotado y un resumen.

Restricciones que ya fija el plan: nada fusiona en la rama principal ni hace push; una sesión nueva por lote (no hay
línea de estado en `claude -p`, así que `aviso_contexto.sh` no sirve); se respeta la interfaz existente
(`entregar.sh`, `with_lock.sh`, `motor_silencioso.sh`, tablón, nombres de rol, códigos 64/65/75).

### Hechos comprobados en la documentación actual de Claude Code (code.claude.com/docs, 2026-10-20)

| Hecho | Página |
|---|---|
| `--permission-mode` admite `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`. `dontAsk` es para «CI y scripts cerrados»; `bypassPermissions`, solo para contenedores o VM aislados (y no funciona como root). | cli-reference, permission-modes |
| En `-p`, una herramienta que necesita permiso y no lo tiene **se deniega y la sesión sigue** (no hay a quién preguntar). | headless, permission-modes |
| `--allowedTools` / `--disallowedTools` aceptan reglas como `Bash(git diff *)` (equivale a `Bash(git diff:*)`). Una regla con alcance en `--disallowedTools` deja la herramienta y deniega solo lo que casa. | headless, permissions |
| Existen `--max-turns` (sale con error al llegar) y `--max-budget-usd` (para al llegar al gasto **estimado**; puede pasarse en una respuesta). | cli-reference, agent-sdk/agent-loop |
| `--output-format json` da `result`, `session_id` y `total_cost_usd` (estimación del cliente, no facturación). `num_turns`, `is_error` y `subtype` (`success`, `error_max_turns`, `error_max_budget_usd`, …) solo están documentados para el SDK: el script los usa si vienen y no depende de ellos. | headless, agent-sdk/cost-tracking |
| Sale con 0 si va bien y distinto de 0 si falla; el código concreto de cada fallo **no está documentado** (SIGTERM: 143). | headless |
| **Los hooks de `.claude/settings.json` se ejecutan en `-p`** (salvo con `--bare`), también dentro de subagentes; PreToolUse con salida 2 bloquea. | headless, hooks, sub-agents |
| En una carpeta nunca marcada como de confianza, `-p` **no usa** `permissions.allow` del `.claude/settings.json` del proyecto: la lista de permitidos va por `--allowedTools`. Los hooks de la cabecera de un subagente tampoco corren (los nuestros no tienen). | permissions, sub-agents |
| `--bare` (recomendado para scripts; será el defecto de `-p` en el futuro) **no carga los hooks del proyecto**. | headless |
| Agent teams: experimental, desactivado por defecto, y **en `-p` no crea compañeros**. | agent-teams |
| Mensajes entre sesiones: `-p` abre buzón, pero los entrantes caducan a los 5 min si no se acepta `crossSessionInbound`. `/loop` solo corre con la sesión abierta y ociosa. | cross-session-messaging, scheduled-tasks |
| El sandbox cubre solo las órdenes de terminal (no las herramientas de archivos ni los hooks) y no existe en Windows nativo. | sandboxing |

## 2. Opciones

**(a) `tools/despachador.sh`: una sesión `claude -p` nueva por lote.** Un script bash lee el plan, elige el
siguiente lote, lanza `claude -p "Eres <rol>. Tienes trabajo en el tablón: lote <id>…"` y, al volver, lee el tablón.
- A favor: determinista (el orden, los topes y el estado los decide bash, no un modelo); se puede probar con un
  `claude` falso como `motor_falso.sh`; cada lote empieza con el contexto limpio; funciona con los hooks actuales.
- En contra: no hay conversación entre roles durante el lote (todo pasa por el tablón, que ya es la norma); cada
  sesión paga su arranque (leer normas, ficha y memoria).

**(b) El coordinador en una sesión interactiva que despierta a los demás con mensajes entre sesiones y `/loop`.**
- En contra: necesita las ventanas abiertas (no es desatendido de verdad); los mensajes caducan a los 5 min; el
  orden y los topes los decide el modelo; no se puede probar sin sesiones reales; el contexto del coordinador crece
  toda la noche.

**(c) Agent teams.**
- En contra: experimental, solo interactivo (en `-p` no crea compañeros) y sin garantía documentada de que los
  hooks del proyecto se apliquen a los compañeros. Ya se descartó en la auditoría.

## 3. Decisión

**Opción (a).** Detalle por punto:

### 3.1 Mecanismo
`./tools/despachador.sh [--ronda N] [--simular]` (dueño `arquitecto-sistemas`), lanzado por la persona desde una
terminal (no desde una sesión de Claude). Sin `--ronda`, empieza por la primera ronda con lotes por hacer y sigue
hasta la última; `--simular` comprueba todo y dice qué lote lanzaría, sin lanzar ni commitear nada.
1. Al arrancar comprueba: nivel `alto`, `claude --help` con todas las opciones que usa, `core.hooksPath` en
   `tools/hooks`, árbol limpio (sin cambios ni archivos sin seguimiento), cuota legible (§3.4), que no hay `.parar` y
   que la rama es `RAMA_PRINCIPAL` (crea `autonomo/<YYYY-MM-DD-HHMM>`) o una `autonomo/…` (la reanuda). Si algo
   falla, no arranca (código 2).
2. Al empezar cada ronda: árbol limpio y `preparacion_ronda.sh N` con 0. Si la puerta no sale bien, para y apunta la
   primera falta en `pendientes_manana.md`.
3. Lotes **de uno en uno** (aprobado: sin paralelismo en la primera versión). Se lanza el primer lote `pendiente` o
   `en curso` de la ronda cuyas dependencias («tras X») estén terminadas; un lote cuya dependencia está `bloqueado`
   pasa a `bloqueado` por dependencia. Un lote es un ciclo: sesión del rol y, si entregó, sesión de `auditor-calidad`.
   Según su fila: `hecho`, otro intento (el lote sigue `en curso`) o `bloqueado`.
4. Al cerrar la ronda (ningún lote por hacer), pasa a la siguiente o termina con el resumen.

Invocación de cada sesión (los topes, configurables por variables de entorno `DESPACHADOR_*`):
```
CLAUDE_ROL=<rol> DESPACHADOR=1 claude -p "<prompt del lote>" \
  --permission-mode dontAsk --allowedTools <§3.2> --disallowedTools <§3.2> \
  --max-turns 80 --max-budget-usd <lo que queda de la cuota de la ronda> \
  --output-format json --no-session-persistence [--model $DESPACHADOR_MODELO]
```
`CLAUDE_ROL` lo pone el despachador: `rol_de_sesion` (`propiedad.sh`) lo antepone a lo que la sesión declare, así
que el rol queda fijado **desde fuera** y una sesión no puede «fijarse» otro. `DESPACHADOR=1` activa las reglas de
§3.3 en `reglas_comando.sh`. Nunca `--bare` (no cargaría los hooks).

### 3.2 Permisos (aprobado: lista abierta)
Sin nadie que apruebe, las guardas son la única barrera:
- Modo `dontAsk`. **Nunca** `bypassPermissions` ni `--dangerously-skip-permissions`.
- `--allowedTools` (la carpeta puede no ser «de confianza» para `-p`, así que no se confía en `permissions.allow`):
  `Bash`, `Read`, `Grep`, `Glob`, `Edit`, `Write`, `NotebookEdit` y los tres agentes del proyecto
  (`Agent(agente-ejecutor-lote)`, `Agent(agente-ejecutor-mecanico)`, `Agent(agente-buscador-lectura)`). `Bash` va
  entero porque las normas piden `grep`/`tail` y crear tests y carpetas pide las utilidades estándar.
- `--disallowedTools`: `WebFetch`, `WebSearch`, `Bash(./tools/despachador.sh*)` y los agentes genéricos (lo mismo que
  el `deny` de `settings.json`, repetido por si no se aplica sin confianza).
- Lo que vale de verdad son los hooks PreToolUse de siempre (`pre_tool_guard.sh` con `reglas_comando.sh`, y
  `guard_propiedad.sh`), también en subagentes, más las reglas nuevas de §3.3.
- **Límite conocido** (readme §8): lo que se escribe con órdenes de terminal en archivos ajenos solo se detecta al
  hacer commit. Con `Bash` abierto ese hueco es el mismo que en una sesión interactiva; lo cubren `commit-msg`, la
  limpieza tras cada sesión (§3.6) y la auditoría.

### 3.3 Rama y fusión (aprobado: misma carpeta)
- Rama `autonomo/<YYYY-MM-DD-HHMM>` desde `RAMA_PRINCIPAL`, en la carpeta del proyecto (sin worktree: una sola caché
  del motor). Mientras corre no debe haber otras sesiones abiertas en la carpeta.
- Reglas nuevas de `reglas_comando.sh`:
  - Siempre: nada escribe, borra, mueve ni copia `.parar` desde la terminal (`rm`, `touch`, `mv`, `cp`, `ln`,
    `truncate`, `unlink`, redirecciones y `tee`); con Edit/Write ya estaba bloqueado (no tiene dueño).
  - Con `DESPACHADOR=1`: `git push`, `git pull`, `git merge`, `git rebase`, `git switch`, `git checkout -b|-B|--orphan`,
    `git branch` salvo para listar, y lanzar otro despachador.
- Al acabar: `.despachador_logs/<ejecución>/resumen.md` y en la terminal: lotes hechos, bloqueados (con motivo), coste
  estimado por ronda, motivo de la parada, resultado de la auditoría y la orden para revisar
  (`git log --oneline RAMA_PRINCIPAL..autonomo/…`). La persona fusiona.

### 3.4 Topes y parada
| Tope | De dónde sale | Qué pasa al llegar |
|---|---|---|
| Gasto por ronda | `**Cuota:** <n> USD por ronda` en la cabecera del plan (`<n>` entero o decimal, con punto o coma). En `alto`, la puerta exige este formato. | No se lanza otra sesión; pausa declarada en el tablón (normas §9) y resumen. Sale con 1. |
| Gasto por sesión | `--max-budget-usd` = lo que queda de la cuota de la ronda | La sesión para: cuenta como intento fallido. |
| Coste real | `total_cost_usd` de cada salida JSON (estimación). Si falta, se cuenta la sesión con todo lo que le quedaba (conservador). | — |
| Intentos | `MAX_RECHAZOS` de §4 de la especificación (3 si no se lee) | Lote `bloqueado` + entrada en `pendientes_manana.md`; se sigue. |
| Turnos | `--max-turns`, 80 por defecto (aprobado) | Intento fallido. |
| Tiempo | vigilante propio en bash (no `timeout`, que no está en macOS sin coreutils): 60 min por sesión (aprobado) | SIGTERM y, a los 30 s, SIGKILL: intento fallido. |
| Parada | archivo `.parar` en la raíz (en `.gitignore`), mirado antes de cada lote | El lote en marcha termina su ciclo; no se lanza otro; fila de parada y resumen. Sale con 1. |
| Uno a la vez | todo el despachador corre dentro de `with_lock.sh despachador coordinador …` | Un segundo despachador sale con 75. |
| Candado ocupado | antes de lanzar un lote, `with_lock.sh --estado` del motor y de la build | El lote se pospone una vez al final de la ronda; si sigue ocupado, intento fallido sin lanzar sesión. |

Intentos de un lote = filas `Rechazo <lote>` de `auditor-calidad` + filas `Fallo <lote>` del despachador en el
tablón. Se cuentan del tablón, así que una ejecución interrumpida se reanuda sin perder la cuenta.

### 3.5 Estado del plan y filas del tablón
- El estado lo cambia **el propio script**, como `coordinador` y solo de forma mecánica: edita la columna Estado y
  entrega con `entregar.sh coordinador "<qué>" docs/direccion/plan_nocturno.md <destino> -- <plan> [pendientes]`.
  Filas del despachador (todas con origen `coordinador`, para no confundirse con entregas):
  `Encargo <lote> (ronda N, intento K): <texto del lote>` hacia el rol al lanzarlo (el lote pasa a `en curso`),
  `Fallo <lote>: <motivo>` hacia el rol, `Estado <lote>: hecho|bloqueado (<motivo>)` y
  `Pausa (ronda N): <motivo>; sigue <lote>` hacia la persona responsable.
- **Solo cuentan las filas nuevas de cada sesión** (aprobado): antes de lanzarla se guarda el número de líneas del
  tablón y después solo se miran las añadidas (si el principio del tablón cambió, la sesión cuenta como fallida). Así
  no vale una entrega, una duda o un `Validado`/`Rechazo` de un intento anterior del mismo lote.
- Fila del rol: entrega = origen el rol y «qué» que empieza por el lote (la regla de la auditoría §4: `Lote A1: …`,
  `A1: …`); duda = `Duda <lote>: <pregunta>`. Si hay las dos, manda la duda. Ninguna: intento fallido (`Fallo`).
- Fila del auditor: `Validado <lote>: …` hacia `coordinador` o `Rechazo <lote>: …` hacia el dueño (normas §8). Si hay
  las dos, manda el rechazo. Ninguna: se repite la sesión del auditor una vez; si tampoco, `Fallo` del lote.
- **Mientras le queden intentos, el lote sigue `en curso`** (aprobado): no vuelve a `pendiente`, porque la auditoría
  §4 marca un `pendiente` que ya tiene entrega en el tablón.
- **Auditoría §4** (aprobado): un lote `pendiente` que aún no aparece en el tablón deja de ser hallazgo; en `alto` se
  planifican todas las rondas desde el principio y, tras una parada, los que no se lanzaron siguen así.
- **Contratos** (aprobado): en la columna Lote, `contrato: <sistema>` (puede haber varios). `preparacion_ronda.sh`
  comprueba que en §3 haya un apartado `### Contrato: <sistema>` (sin distinguir mayúsculas y sin el `(ronda M)` final)
  y que no tenga `(POR ESCRIBIR`. Como el despachador no lanza una ronda sin su puerta, un lote con un contrato sin
  firmar no pasa a `en curso`.
- Al acabar, `auditoria_proceso.sh` (informe dentro de `.despachador_logs/`, para no ensuciar el árbol) va en el resumen.

### 3.6 Árbol limpio tras cada sesión (aprobado)
Tras cada sesión, lo que quede sin commitear o sin seguimiento **en rutas de su rol** (`propiedad.tsv`) se copia a
`.despachador_logs/<ejecución>/sobras/<sesión>/` y se deshace (los archivos con historia vuelven a `HEAD`, los nuevos se
borran). Así una sesión fallida (turnos, cuota, tiempo, error) no contamina `motor_silencioso.sh` en los lotes
siguientes ni deja el árbol sucio para la ronda siguiente. Lo que quede en rutas de **otros** dueños (p. ej. metadatos
que genera el motor) no se toca: va al resumen y, si sigue al empezar la ronda siguiente, el despachador para.

### 3.7 Dudas
- Una sesión con una duda que no resuelve con §4 de la especificación entrega `Duda <lote>: <pregunta>` hacia
  `coordinador` y termina. El script marca el lote `bloqueado`, copia la pregunta a `pendientes_manana.md` (como
  `coordinador`) y sigue. Los lotes que van «tras» él quedan `bloqueado` por dependencia.
- Solo se escala lo que implica compras, licencias/NDA o cambiar la visión o el alcance (normas §9); lo técnico se
  decide con §4 y se apunta en la memoria del rol.

### 3.8 Registro
`.despachador_logs/` (en `.gitignore`; se guardan las 10 últimas ejecuciones): por sesión, la salida JSON y el stderr
(`r<N>_<lote>_<rol>_<k>.json` y `.err`); por ejecución, `resumen.md`, `sobras/` y el informe de la auditoría. En la
terminal, una línea por sesión: `A1 arquitecto-sistemas intento 1: entrega · 23 turnos · 0.84 USD · 6 min`.

### 3.9 Pruebas
`tools/hooks/tests/claude_falso.sh` (sustituye a `claude` con `DESPACHADOR_CLAUDE=…`): sigue un guion de una línea por
sesión (rol esperado, acción y coste) y entrega, valida, rechaza, deja una duda, no deja nada, deja archivos sin
commitear, tarda o sale con error, e imprime un JSON con `result`, `session_id`, `total_cost_usd` y `subtype`. Casos en
`prueba_guardas.sh`: lote hecho (con las opciones de `claude` y el rol fijado); rechazo hasta el tope (`bloqueado` y
pendiente, y `en curso` entre intentos); sesión sin fila con sobras (limpiadas y guardadas); duda (bloqueado y su
dependiente también); parada con `.parar` y reanudación en la misma rama; tope de gasto; tiempo agotado; candado del
motor ocupado; segundo despachador (75); nivel que no es `alto`; `--simular` sin efectos. En el CI, las 6 combinaciones.

## 4. Consecuencias

- **A favor**: trabajo nocturno sin ventanas abiertas, con topes duros y parada; el orden y el estado son
  deterministas y probados; reutiliza tablón, entregas, guardas y puerta; el rol lo fija el proceso padre; el estado
  vive en el tablón y el plan, así que se puede reanudar.
- **En contra / riesgos**:
  - Depende de opciones de `claude -p` que cambian rápido (`--max-budget-usd`, `dontAsk`, el defecto de `--bare`): el
    script comprueba al arrancar que `claude --help` las tiene y, si no, no arranca.
  - El coste es una estimación del cliente: el tope real puede pasarse en una respuesta por sesión.
  - Sin paralelismo, una ronda tarda la suma de sus lotes.
  - Con `Bash` abierto, la barrera son los hooks; las escrituras por terminal en archivos ajenos se ven al commitear
    (límite ya conocido) y la limpieza solo deshace lo del rol de la sesión.
- **Qué cambia en la fase 9**: `tools/despachador.sh` y `tools/hooks/tests/claude_falso.sh` (fila en `propiedad.tsv` y
  en la ficha de arquitecto-sistemas), `.gitignore` (`.parar`, `.despachador_logs/`), reglas de `reglas_comando.sh`
  (§3.3), puerta (cuota en USD y `contrato:`), auditoría §4 (pendiente sin tablón), normas §9 (alto), ficha de
  auditor (`Validado <lote>`), readme §6/§8 y `actualizar.md`.

## 5. Decisiones de la persona responsable (2026-10-20)
1. Paralelismo: un lote cada vez en la primera versión.
2. Cuota `**Cuota:** <n> USD por ronda` (entero o decimal); topes por defecto de 80 turnos y 60 min por sesión.
3. `Bash` abierto en `--allowedTools`, apoyado en `pre_tool_guard.sh`/`reglas_comando.sh` (reglas nuevas de `.parar` y,
   con `DESPACHADOR=1`, de push/merge/rebase/switch/checkout -b/branch) y en `--disallowedTools` (`WebFetch`,
   `WebSearch`, `Bash(./tools/despachador.sh*)` y agentes genéricos).
4. Rama `autonomo/<YYYY-MM-DD-HHMM>` en la misma carpeta, sin worktree.

Ajustes aprobados a la vez: solo cuentan las filas nuevas de cada sesión; el lote sigue `en curso` entre intentos;
la auditoría §4 no marca un `pendiente` que no está en el tablón; limpieza de las rutas del rol tras una sesión; y la
comprobación de `contrato: <sistema>` en la puerta. Añadido al implementarlo: la limpieza se hace tras **cada** sesión
(no solo las fallidas), con copia en `sobras/`, y `git pull` se bloquea junto con `merge` (es un merge).

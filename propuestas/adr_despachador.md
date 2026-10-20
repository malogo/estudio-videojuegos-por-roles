# ADR: despachador del nivel de autonomía `alto` (BORRADOR, pendiente de aprobación)

Fecha: 2026-10-20 · Estado: **propuesto** · Fase 8 de `propuestas/plan_autonomia.md` (solo diseño).
La fase 9 (implementarlo) no empieza sin la aprobación de la persona responsable.

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
| `--allowedTools` / `--disallowedTools` aceptan reglas como `Bash(git diff *)` (equivale a `Bash(git diff:*)`). | headless, permissions |
| Existen `--max-turns` (sale con error al llegar) y `--max-budget-usd` (para al llegar al gasto **estimado**; puede pasarse en una respuesta). | cli-reference, agent-sdk/agent-loop |
| `--output-format json` da `result`, `session_id` y `total_cost_usd` (estimación del cliente, no facturación). `num_turns`, `is_error` y `subtype` (`success`, `error_max_turns`, `error_max_budget_usd`, …) solo están documentados para el SDK. | headless, agent-sdk/cost-tracking |
| Sale con 0 si va bien y distinto de 0 si falla; el código concreto de cada fallo **no está documentado** (SIGTERM: 143). | headless |
| **Los hooks de `.claude/settings.json` se ejecutan en `-p`** (salvo con `--bare`), también dentro de subagentes; PreToolUse con salida 2 bloquea. | headless, hooks, sub-agents |
| En una carpeta nunca marcada como de confianza, `-p` **no usa** `permissions.allow` del `.claude/settings.json` del proyecto: la lista de permitidos hay que pasarla por `--allowedTools` o `--settings`. Los hooks de la cabecera de un subagente tampoco corren (los nuestros no tienen). | permissions, sub-agents |
| `--bare` (que se recomienda para scripts y será el defecto de `-p` en el futuro) **no carga los hooks del proyecto**. | headless |
| Agent teams: experimental, desactivado por defecto, y **en `-p` no crea compañeros**. | agent-teams |
| Mensajes entre sesiones: `-p` abre buzón, pero los mensajes entrantes caducan a los 5 min si no se acepta `crossSessionInbound`. `/loop` solo corre con la sesión abierta y ociosa. | cross-session-messaging, scheduled-tasks |
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
`./tools/despachador.sh [--ronda N | --todas] [--simular]` (dueño `arquitecto-sistemas`), lanzado por la persona
desde una terminal (no desde una sesión de Claude). Bucle por ronda:
1. Comprueba: árbol limpio, nivel `alto`, `preparacion_ronda.sh N` sale con 0, cuota legible (§3.4) y que no hay
   `.parar`.
2. Por cada lote `pendiente` de la ronda cuyas dependencias («tras X») estén `hecho`: lo marca `en curso` y deja el
   encargo en el tablón como `coordinador` (§3.5); lanza la sesión del rol; al volver, si hay entrega, lanza una
   sesión de `auditor-calidad` para ese lote; según su fila, `hecho`, otro intento o `bloqueado`.
3. Los lotes se lanzan **de uno en uno** en la primera versión (sin paralelismo: evita pisarse en el árbol compartido
   y con los candados; `MAX_SESIONES` se respeta trivialmente). Paralelismo con worktrees: posible ampliación.
4. Al cerrar la ronda (todos `hecho` o `bloqueado`), pasa la puerta de la siguiente y sigue, o para.

Invocación de cada sesión (valores por defecto; todos configurables en la cabecera del script):
```
CLAUDE_ROL=<rol> claude -p "<prompt del lote>" \
  --permission-mode dontAsk --allowedTools <lista §3.2> --disallowedTools <lista §3.2> \
  --max-turns ${DESPACHADOR_MAX_TURNOS:-80} --max-budget-usd <tope por lote, §3.4> \
  --output-format json --no-session-persistence [--model <de la ficha o del plan>]
```
`CLAUDE_ROL` lo pone el despachador: `rol_de_sesion` (propiedad.sh) lo antepone a lo que la sesión declare, así que
el rol queda fijado **desde fuera** y una sesión no puede «fijarse» otro (más fuerte que en interactivo). Nunca `--bare`.

### 3.2 Permisos
Sin nadie que apruebe, las guardas son la única barrera. Decisión:
- Modo `dontAsk`: lo que no esté permitido se deniega en silencio y la sesión sigue. **Nunca** `bypassPermissions` ni
  `--dangerously-skip-permissions`.
- `--allowedTools` (la carpeta puede no ser «de confianza» para `-p`, así que no se confía en `permissions.allow`):
  `Read Grep Glob Edit Write`, `Agent(agente-ejecutor-lote)`, `Agent(agente-ejecutor-mecanico)`,
  `Agent(agente-buscador-lectura)`, `Bash(./tools/*)` (entregar, motor, candados, puerta, auditoría, tests propios),
  `Bash(git status*)`, `Bash(git diff*)`, `Bash(git log*)`, `Bash(git show*)`, `Bash(git commit *)`, `Bash(ls*)`, y
  los prefijos de los **comandos de comprobación** del plan de esa ronda (el script los extrae de la columna; así el
  rol puede pasar su propio criterio).
- `--disallowedTools`: `Bash(git push*)`, `Bash(git merge*)`, `Bash(git rebase*)`, `Bash(git switch*)`,
  `Bash(git checkout -b*)`, `Bash(git branch*)`, `Bash(./tools/despachador.sh*)` (que una sesión no lance otro despachador), `WebFetch`, `WebSearch` y los agentes genéricos (lo mismo que el
  `deny` de `settings.json`, repetido por si no se aplica sin confianza).
- Siguen activos los hooks PreToolUse de siempre (órdenes prohibidas, propiedad, rol), también en subagentes.
- **Límite conocido** (readme §8): lo que se escribe con órdenes de terminal solo se detecta al hacer commit; con
  `Bash` limitado a la lista de arriba el riesgo baja, pero un comando de comprobación permitido puede escribir.
  El sandbox de Claude Code ayudaría en Linux/macOS pero no en Windows y no cubre los hooks: queda fuera (como el
  «sandbox por rol» del plan).

### 3.3 Rama y fusión
- Al empezar: `git switch -c autonomo/<YYYY-MM-DD-HHMM>` desde `RAMA_PRINCIPAL` actualizada y con el árbol limpio.
  Trabaja en la carpeta del proyecto (no en un worktree: evita otra caché del motor; ver readme 6.9).
- Nunca push, merge ni cambio de rama (lo deniegan `--disallowedTools` y, en la fase 9, una regla nueva de
  `reglas_comando.sh` activa cuando `DESPACHADOR=1`).
- Al acabar: `.despachador_logs/<rama>/resumen.md` y en la terminal: lotes hechos, bloqueados (con motivo), coste
  estimado, commits, y la orden para revisar (`git log RAMA_PRINCIPAL..autonomo/…`). La persona fusiona.

### 3.4 Topes y parada
| Tope | De dónde sale | Qué pasa al llegar |
|---|---|---|
| Gasto por ronda | `CUOTA` del plan en formato legible por máquina: `**Cuota:** <n> USD por ronda` (la puerta en `alto` ya exige que esté definida; la fase 9 exige además este formato) | No se lanza otro lote; pausa declarada en el tablón (como hoy, normas §9) y resumen. |
| Gasto por lote | `--max-budget-usd` = lo que queda de la ronda (nunca más) | La sesión para (`error_max_budget_usd`): cuenta como intento fallido. |
| Coste real | `total_cost_usd` de cada salida JSON (estimación). Si falta, se cuenta el lote con el tope por lote entero (conservador). | — |
| Rechazos | `MAX_RECHAZOS` de §4 de la especificación | Lote `bloqueado` + entrada en `pendientes_manana.md`; se sigue. |
| Turnos | `--max-turns` (80 por defecto) | Intento fallido. |
| Tiempo | vigilante propio en bash (no `timeout`, que no está en macOS sin coreutils): 60 min por sesión | SIGTERM (143): intento fallido. |
| Parada | archivo `.parar` en la raíz (en `.gitignore`), mirado antes de cada sesión | Termina la sesión en curso con normalidad, no lanza más y deja el resumen. |
| Uno a la vez | todo el despachador corre dentro de `with_lock.sh despachador coordinador …` | Un segundo despachador sale con 75. |
| Candado ocupado | si una sesión vuelve sin entrega y el log dice 75 (motor o build ocupados) | El lote vuelve al final de la cola de la ronda una vez; la segunda, intento fallido. |

Intentos de un lote = rechazos + sesiones fallidas; con `MAX_RECHAZOS` intentos, `bloqueado`. `.parar` no se puede
crear ni borrar desde una sesión: no tiene dueño en `propiedad.tsv` (Edit/Write ya lo bloquean), `rm` y `touch` no
están en la lista de `Bash` permitida, y aun así la fase 9 añade a `reglas_comando.sh` el `rm`/`>`/`touch` sobre
`.parar` (por si una orden permitida lo intenta).

### 3.5 Estado del plan
- Lo cambia **el propio script**, como `coordinador` y solo de forma mecánica: `en curso` al lanzar, `hecho`,
  `bloqueado`. Edita la columna Estado y entrega con
  `CLAUDE_ROL=coordinador ./tools/hooks/entregar.sh coordinador "Lote A1: en curso" docs/direccion/plan_nocturno.md <rol> -- docs/direccion/plan_nocturno.md`
  (misma fila que hoy deja el coordinador al repartir). No hace falta una sesión `coordinador` entre lotes: no hay nada
  que decidir, y sería coste y no determinismo.
- Lote que vuelve **sin fila de entrega** (origen = su rol y «qué» que empieza por el lote, la misma regla que la
  auditoría §4): intento fallido; el script deja `Fallo A1: la sesión acabó sin entrega (<subtype o código>)`.
- Validación: el auditor deja `Validado <lote>: …` hacia `coordinador` o `Rechazo <lote>: …` hacia el dueño (normas §8).
  Una sesión de auditor que no deja ninguna de las dos: intento fallido del auditor, se repite una vez y luego `bloqueado`.
- Contratos (normas §9, nivel alto): la fase 9 añade a la columna Lote `contrato: <sistema>` y la puerta comprueba que
  ese apartado de §3 esté firmado; el despachador no lanza el lote si no lo está.
- Al acabar, `auditoria_proceso.sh` (sin hallazgos en 4 y 6) va en el resumen.

### 3.6 Dudas
- Una sesión con una duda que no resuelve con §4 de la especificación entrega `Duda <lote>: <pregunta>` hacia
  `coordinador` y termina. El script marca el lote `bloqueado`, copia la pregunta a `pendientes_manana.md` (como
  `coordinador`) y sigue. Los lotes que van «tras» él quedan `bloqueado` por dependencia.
- Solo se escala lo que implica compras, licencias/NDA o cambiar la visión o el alcance (normas §9); lo técnico se
  decide con §4 y se apunta en la memoria del rol.

### 3.7 Registro
`.despachador_logs/` (en `.gitignore`; se guardan las 10 últimas ejecuciones): por sesión, la salida JSON entera y
el stderr (`<ronda>_<lote>_<rol>_<intento>.json`); por ejecución, `resumen.md`. En la terminal, una línea por sesión
(como el resumen de `motor_silencioso.sh`): `A1 arquitecto-sistemas intento 1: entregado · 23 turnos · 0,84 USD · 6 min`.

### 3.8 Pruebas
`tools/hooks/tests/claude_falso.sh` (sustituye a `claude` con `DESPACHADOR_CLAUDE=…`): según variables de entorno,
entrega con `entregar.sh`, rechaza, deja una duda, no deja nada, o sale con `error_max_turns`/`error_max_budget_usd`,
e imprime un JSON con `result`, `session_id`, `total_cost_usd` y `subtype`. Casos en `prueba_guardas.sh`:
lote ok (`hecho`); rechazo hasta el tope (`bloqueado` + pendiente); lote sin fila (fallo); duda (bloqueado y su
dependiente también); parada con `.parar`; tope de gasto (no se lanza el siguiente); segundo despachador (75); rama
`autonomo/…` creada y ningún push; `--simular` no lanza nada. En el CI, las 6 combinaciones.

## 4. Consecuencias

- **A favor**: trabajo nocturno sin ventanas abiertas, con topes duros y parada; el orden y el estado son
  deterministas y probados; reutiliza tablón, entregas, guardas y puerta; el rol lo fija el proceso padre.
- **En contra / riesgos**:
  - Depende de flags de `claude -p` que cambian rápido (`--max-budget-usd`, `dontAsk`, el defecto de `--bare`): el
    script comprueba al arrancar que `claude --help` los tiene y, si no, no arranca.
  - El coste es una estimación del cliente: el tope real puede pasarse en una respuesta por sesión.
  - Sin paralelismo, una ronda tarda la suma de sus lotes.
  - Sin `Bash` libre, algún lote legítimo puede necesitar una orden no listada: la sesión la ve denegada; si no puede
    seguir, deja una duda y el lote queda `bloqueado` (se ve en el resumen y se amplía la lista).
  - Las escrituras por terminal siguen viéndose solo al hacer commit (límite ya conocido).
- **Qué cambia en la fase 9** (si se aprueba): `tools/despachador.sh` y `claude_falso.sh` (fila en `propiedad.tsv` y en
  la ficha de arquitecto-sistemas), `.gitignore` (`.parar`, `.despachador_logs/`), reglas de `reglas_comando.sh`
  (`.parar`; push/merge/cambio de rama con `DESPACHADOR=1`), puerta (formato de cuota y `contrato:`), normas §9 (alto),
  ficha de auditor (`Validado <lote>`), readme §6/§8 y `actualizar.md`.

## 5. Preguntas abiertas para la persona responsable
1. ¿Vale un lote cada vez en la primera versión (sin paralelismo)?
2. ¿Formato de cuota `<n> USD por ronda`? ¿Topes por defecto de 80 turnos y 60 min por sesión?
3. ¿Lista de `Bash` permitida cerrada (más los comandos de comprobación del plan), aunque algún lote se bloquee por
   ello, o más abierta?
4. ¿Rama `autonomo/<fecha>` en la misma carpeta (sin otras sesiones abiertas a la vez) o en un worktree aparte?

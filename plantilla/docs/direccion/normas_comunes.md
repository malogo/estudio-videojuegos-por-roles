# Normas Comunes (se cargan siempre — versión corta de `especificaciones.md`)
> Solo se abre `especificaciones.md` entero si el lote toca diseño de producto o arquitectura.

## 1. Identidad y roles
- Cada sesión arranca con `./tools/hooks/arranque_rol.sh <rol>`: fija el rol (sin él, la guarda de Edit|Write bloquea)
  y muestra su ficha, su `memoria_<rol>.md` y sus filas del tablón desde el último vaciado. `fijar_rol.sh <rol>` solo fija el rol.
  Con el rol fijado, el hook bloquea commits, entregas y motor en nombre de otro rol.
- Nombres fijos de rol: {{ROLES}}.
- `chatEspecialista` = sesión principal de un rol (diseña, decide, valida). `agenteEspecialista` = subagente que ejecuta un lote acotado.
- La persona responsable es la única que decide alcance, normas nuevas, compras y publicación.

## 2. Propiedad de archivos
- Cada archivo tiene un único dueño (ver la ficha de cada rol). Solo el dueño lo edita.
- Si necesitas un cambio en un archivo ajeno, lo pides por tablón al dueño; nunca lo editas tú.
- Propiedad forzada por `tools/hooks/propiedad.tsv`; ruta o carpeta nueva sin dueño: pídelo antes a `arquitecto-sistemas`.
- Cada rol es dueño de su `memoria_<rol>.md`. El tablón lo amplía cualquiera; solo `coordinador` lo archiva.
- Normas, especificación, fichas y `CLAUDE.md`: `coordinador`, con aprobación de la persona responsable.
- `.gitignore`, `.gitattributes`, `.claude/**` y `tools/hooks|locks`: `arquitecto-sistemas`.
- `auditor-calidad` nunca repara archivos ajenos: anota el rechazo y despierta al dueño.

## 3. Tablón (`docs/direccion/tablon.md`)
- Append-only. Formato: `YYYY-MM-DD HH:MM | origen | qué se entregó | ruta o commit | destino`.
- Lectura por rol: la hace `arranque_rol.sh`; para más historia, `grep "| <rol>$" docs/direccion/tablon.md`. No leas el tablón entero.
- Las filas solo se añaden con `./tools/hooks/entregar.sh <rol> "<qué>" "<ruta o commit>" <destino> [-- <rutas>]`:
  pone la hora real y commitea tu fila con tus rutas en una orden. Escribir en el tablón a mano (Edit, `>>`, `tee`) está bloqueado.
- Para despertar a otro rol: entrada en el tablón + mensaje `"Tienes trabajo en el tablón"`.
- Solo `coordinador` archiva el tablón (al pasar de ~200 filas): `./tools/hooks/archivar_tablon.sh coordinador` mueve a
  `docs/direccion/archivo/` las filas que ya leyeron todos los roles (anteriores al «Último vaciado» más antiguo) y deja las 50 últimas.
- El tablón es la única fuente del estado de los lotes; el plan nocturno solo planifica. Estados del plan: `pendiente`, `en curso`, `hecho`, `entregado`, `bloqueado`.

## 4. Git (árbol compartido)
- PROHIBIDO: `git stash`, `git add -A`/`.`, `git commit -a`, `git commit --amend`, `git reset --hard|--soft` y `git reset <commit>`
  (mueve la rama), `git checkout|restore` de `.`, carpetas o comodines, `git checkout|switch -f`, `git clean -f`,
  `git commit -n`/`--no-verify`, cambiar `core.hooksPath` (con `git config`, `git -c`, `GIT_CONFIG_*` o `include.path`) y
  editar nada dentro de `.git/`. Las abreviaturas (`--amen`, `--no-veri`, `--har`) cuentan igual.
- ¿Te equivocaste en un commit? Haz otro commit que lo corrija: el último commit puede ser de otra sesión.
- Commit siempre por rutas, con prefijo `<rol>:` y tu fila del tablón: `./tools/hooks/entregar.sh <rol> "<qué>" "<ruta o commit>" <destino> -- <rutas>`
  (commit `<rol>: <qué>` con tus rutas y solo tu fila; `--cuerpo "<línea>"` para la línea de encargo). Toda fila de un commit
  debe tener como origen el rol del commit: las filas ajenas sin commitear las commitea su dueño.
- Lo impiden automáticamente el hook PreToolUse (`.claude/settings.json`, también en subagentes)
  y los hooks `pre-commit` y `commit-msg` (`git config core.hooksPath tools/hooks`). Si te bloquean, no los esquives.
- Nunca reviertas ni sobrescribas cambios que no son tuyos aunque aparezcan en `git status`.
- Los archivos que el motor acompaña de metadatos (p. ej. `.meta`, `.import`, `.uid`) se commitean junto a ellos.
- Lo que el motor genere en archivos de otro dueño (lo lista `motor_silencioso.sh`) no se revierte ni se commitea:
  se avisa al dueño con `./tools/hooks/entregar.sh <rol> "<qué generó el motor>" "<rutas>" <dueño>` (sin `--`).

## 5. Motor ({{MOTOR}}) y sonido
- PROHIBIDO lanzar el motor directamente. Siempre `./tools/motor_silencioso.sh <rol> ...`
  (fuerza el modo sin sonido y adquiere el candado `motor`, que dura mientras viva el motor).
- Builds: `./tools/locks/with_lock.sh {{CANDADO_BUILD}} <rol> <comando>`.
- Si el candado está ocupado (código 75): no reintentes en bucle; sigue con otra tarea y vuelve después.
  Si avisa de «probable huérfano», comprueba el PID con la orden que da y, si no es el motor ni una build, libéralo como indica.
- `motor_silencioso.sh` guarda la salida entera en `.motor_logs/` y solo enseña un resumen (≤25 líneas, errores por dueño).
  Sale con el código del motor, o con 65 si el motor dio 0 pero hay errores en el log; con 124 si no acabó en
  `MOTOR_TIEMPO_MAX` s (300 por defecto: lo para con todo lo que lanzó), y con 127 si no encuentra el ejecutable
  (`MOTOR_BIN`). No vuelques el log entero al
  contexto: usa `grep`/`tail` sobre él (`MOTOR_SALIDA=completa` es para personas).
- Si el motor crea o cambia archivos versionables, el resumen los lista por dueño (pueden ser de otra sesión que trabajaba
  a la vez). Los tuyos van en tu entrega; los ajenos, ver §4. No cambia el código de salida.
- Un error que crees ruido no se esquiva: se pide por tablón a `auditor-calidad`, único que lo silencia
  (`tools/auditoria/ruido_motor.txt`, con su motivo). Un error en archivos de otro dueño se le avisa por tablón.
- Prohibido reproducir sonido o abrir enlaces de audio/vídeo.
- Nunca commitees cachés del motor ni `tools/locks/*.lock`. Ningún audio o vídeo arranca solo al cargar una escena.
- Buenas prácticas: se sigue la guía oficial del motor ({{GUIA_BUENAS_PRACTICAS}}). Desviarse se justifica en el commit.
- Avisa de lo poco práctico: si algo entorpece el trabajo (flujo, wrapper, hooks, candados, estructura o normas),
  fila en el tablón hacia `coordinador` con el problema y una propuesta. No lo esquives en silencio.

## 6. Subagentes
- Solo agentes propios del proyecto (`.claude/agents/`), nunca genéricos: el subagente no ve estas normas.
  En este proyecto estas normas sobre subagentes mandan sobre el `CLAUDE.md` global del usuario.
- `agente-ejecutor-lote` ({{MODELO_EJECUTOR}}, high): código. `agente-ejecutor-mecanico` ({{MODELO_EJECUTOR}}, medium): patrón.
  `agente-buscador-lectura` ({{MODELO_LECTOR}}): solo lectura.
- Todo encargo sigue `docs/direccion/roles/plantilla_encargo.md` (rol de origen, archivos exactos, cambio, criterio de hecho,
  comando de comprobación, tope de 10 líneas) y deja una línea en el commit del lote: agente, esfuerzo, ¿a la primera?
- Arte: `director-arte` nunca delega la creación ni el juicio de piezas; una sola pieza por encargo.
- La sesión principal valida por resultados (test, captura, `git diff --stat`), no releyendo todo.

## 7. Contexto y memoria
- Al llegar a ~250k tokens (o ~150k si vas a parar más de 1 h): volcar estado en `docs/direccion/roles/memoria_<rol>.md`
  (formato de `plantilla_memoria.md`, con `**Último vaciado:** YYYY-MM-DD HH:MM` exacto: `arranque_rol.sh` filtra el tablón por esa fecha),
  commitearla sola y sin fila del tablón (`git commit -m "<rol>: memoria" -- docs/direccion/roles/memoria_<rol>.md`) y pedir vaciado.
- El aviso llega solo: la línea de estado apunta el contexto de cada sesión y `aviso_contexto.sh` lo recuerda en cada
  mensaje (`[AVISO DE VACIADO]`). Tras `/compact` o `/clear`, `inicio_sesion.sh` te dice el rol que tienes registrado.
- La memoria se deja en un punto limpio de corte: archivo exacto y estado para retomar sin historial.
- `coordinador` nunca se vacía por su cuenta: avisa cuando conviene, deja al día `memoria_coordinador.md` y lo vacía la persona responsable.

## 8. Calidad antes de entregar
- Toda escena o pantalla tocada debe arrancar limpia (`./tools/motor_silencioso.sh <rol> ...` sale con 0) y llevar captura antes de entregarse.
- Toda pieza visual se valida lado a lado con `docs/arte/referencia_estilo.md` y dentro del conjunto, nunca aislada.
- Nada llega a la persona responsable sin pasar por `auditor-calidad`.
- Un fallo visual o de flujo que se repite se convierte en un detector automático en las rutas de tests.
- Tope de rondas de corrección: si persiste un fallo estructural, se rehace desde cero.
- Cada rechazo de `auditor-calidad` se anota siempre igual (así se cuentan):
  `./tools/hooks/entregar.sh auditor-calidad "Rechazo <lote>: <motivo>" "<ruta o commit>" <rol dueño>`.
{{#SI NIVEL_AUTONOMIA=bajo}}
- Rechazos sin tope automático: tras cada uno decide la persona responsable.
{{#FIN}}
{{#SI NIVEL_AUTONOMIA=medio,alto}}
- Tope: con {{MAX_RECHAZOS}} rechazos, el lote pasa a `bloqueado` (§9).
{{#FIN}}

## 9. Nivel de autonomía (`{{NIVEL_AUTONOMIA}}`), escalado y rondas
- El nivel lo fija la línea «Nivel de autonomía» de `especificaciones.md`; lo cambia `coordinador` con aprobación de la persona responsable.
- No inventes decisiones de producto: si la especificación no lo dice, se escala.
- Antes de lanzar la ronda N, `./tools/auditoria/preparacion_ronda.sh N` debe salir con 0. Si no, la ronda no se lanza
  y lo que falta va a `docs/direccion/pendientes_manana.md`.
- El trabajo sin supervisión sigue `docs/direccion/plan_nocturno.md`. Pausas por cuota: `coordinador` las declara en el
  tablón indicando qué sigue y qué espera. No lances todas las sesiones a la vez sobre la misma tanda.
{{#SI NIVEL_AUTONOMIA=bajo}}
- Nivel `bajo` (control paso a paso): la persona responsable lanza cada lote, pasa los avisos entre sesiones y hace
  `/clear` tras cada lote. Basta la §1 de la especificación; lo demás se completa lote a lote.
- Dudas que la especificación no resuelve (y siempre alcance, normas nuevas, compras o publicación): se preguntan al
  momento o van a `pendientes_manana.md` y se para.
{{#FIN}}
{{#SI NIVEL_AUTONOMIA=medio}}
- Nivel `medio` (rondas supervisadas): las rondas las lanza `coordinador` cuando lo pide la persona responsable y despierta
  a los roles hasta que `auditor-calidad` cierra la ronda. Antes de la ronda N, los apartados `(ronda M)` con M ≤ N de
  §2 y §3 de la especificación están escritos y todos los lotes de la ronda tienen criterio y comando en el plan.
- Dudas de alcance, normas nuevas, compras o publicación → `pendientes_manana.md`; el lote pasa a `bloqueado` y el rol
  sigue con su cola.
- Con {{MAX_RECHAZOS}} rechazos de `auditor-calidad`, el lote pasa a `bloqueado` y se avisa a la persona responsable en `pendientes_manana.md`.
{{#FIN}}
{{#SI NIVEL_AUTONOMIA=alto}}
- Nivel `alto` (flujo desatendido): las rondas las encadena `./tools/despachador.sh`, que lanza la persona responsable
  desde su terminal (nunca una sesión): una sesión nueva de `claude -p` por lote, con el rol fijado, y otra de
  `auditor-calidad` si entrega; cada ronda, solo si su puerta sale con 0. Trabaja en una rama `autonomo/<fecha>` sin
  push ni merge: la persona responsable la revisa al final y la fusiona. Mientras corre, no hay otras sesiones en la carpeta.
- Se para con un archivo `.parar` en la raíz, que solo crea o borra la persona responsable desde su terminal: el lote en
  marcha acaba su ciclo y no se lanza otro. Para seguir, se borra y se relanza el despachador (reanuda la rama).
- Antes de la ronda 1, §1-§4 de la especificación enteras sin marcadores «POR ESCRIBIR», y todas las rondas del plan con
  criterio, comando y dependencias («tras X») que existen; la cuota, como `**Cuota:** <n> USD por ronda` en la cabecera
  del plan (coste estimado de las sesiones: al agotarse, el despachador declara la pausa en el tablón y para).
- Ningún lote que consuma un contrato de §3 pasa a `en curso` si su contrato no está firmado.
- En una sesión del despachador: el lote se entrega con `./tools/hooks/entregar.sh <rol> "Lote <id>: <resumen>" "<ruta o
  commit>" auditor-calidad -- <rutas>` y `auditor-calidad` deja una sola fila: `"Validado <id>: <qué comprobaste>"` hacia
  `coordinador` o la de rechazo (§8). Sin push, merge ni cambios de rama (las guardas los bloquean).
- Dudas técnicas internas: las decide el rol con los criterios de §4 de la especificación (las de gestión, como
  `coordinador`) y las apunta en su memoria. Solo se escala lo que implica compras, licencias/NDA o cambiar la visión o
  el alcance: fila `"Duda <id>: <pregunta>"` hacia `coordinador` y se termina la sesión; el despachador pasa el lote a
  `bloqueado` (y lo que va tras él), copia la pregunta en `pendientes_manana.md` y sigue.
- Con {{MAX_RECHAZOS}} intentos sin validar (rechazos de `auditor-calidad` o sesiones sin entrega), el despachador pasa el
  lote a `bloqueado` sin esperar a nadie (queda anotado en `pendientes_manana.md`) y sigue con el siguiente.
- Contexto: cada lote empieza en una sesión nueva; no se arrastra contexto entre lotes.
{{#FIN}}

## 10. Producto (recordatorio mínimo)
- {{MOTOR}}; plataformas: {{PLATAFORMAS}}.
- {{DESCRIPCION_PRODUCTO}}

## 11. Sesiones en la nube
- Al empezar: `./tools/hooks/arranque_rol.sh <rol>` (activa los hooks y fija el rol). Trabaja en la rama automática de la sesión, partiendo de `{{RAMA_PRINCIPAL}}` actualizada, y abre PR hacia `{{RAMA_PRINCIPAL}}`.
- Merge solo la persona responsable (o `coordinador` si así lo pide). Horas siempre en `{{ZONA_HORARIA}}` (`entregar.sh` ya la usa).
- La fila de la entrega va en `docs/direccion/entregas_nube/<lote>.txt`, en el commit de la entrega:
  `./tools/hooks/entregar.sh <rol> "<qué>" "<ruta o commit>" <destino> --nube <lote> -- <rutas>`; la nube no edita `tablon.md`. Tras fusionar, `coordinador` ejecuta `./tools/hooks/volcar_entregas_nube.sh` y commitea por rutas.
- No pueden avisar a otros roles: la persona responsable pega el resultado al coordinador.

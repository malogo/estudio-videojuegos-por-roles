# Normas Comunes (se cargan siempre — versión corta de `especificaciones.md`)
> Solo se abre `especificaciones.md` entero si el lote toca diseño de producto o arquitectura.

## 1. Identidad y roles
- Cada sesión arranca con `./tools/hooks/arranque_rol.sh <rol>`: fija el rol (sin él, la guarda de Edit|Write bloquea)
  y muestra su ficha, su `memoria_<rol>.md` y sus filas del tablón desde el último vaciado. `fijar_rol.sh <rol>` solo fija el rol.
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
- La hora de cada fila sale de `date "+%Y-%m-%d %H:%M"`; nunca se escribe a mano.
- Para despertar a otro rol: entrada en el tablón + mensaje `"Tienes trabajo en el tablón"`.
- Solo `coordinador` archiva el tablón (al llegar a ~200 líneas).
- El tablón es la única fuente del estado de los lotes; el plan nocturno solo planifica. Estados del plan: `pendiente`, `en curso`, `hecho`, `entregado`, `bloqueado`.

## 4. Git (árbol compartido)
- PROHIBIDO: `git stash`, `git add -A`/`.`, `git commit -a`, `git reset --hard`, `git checkout|restore .`, `git clean -f`.
- Commit siempre por rutas, con prefijo `<rol>:` y tu fila del tablón: `git commit -m "<rol>: <qué>" -- <rutas> docs/direccion/tablon.md`.
- Lo impiden automáticamente el hook PreToolUse (`.claude/settings.json`, también en subagentes)
  y los hooks `pre-commit` y `commit-msg` (`git config core.hooksPath tools/hooks`). Si te bloquean, no los esquives.
- Nunca reviertas ni sobrescribas cambios que no son tuyos aunque aparezcan en `git status`.
- Los archivos que el motor acompaña de metadatos (p. ej. `.meta`, `.import`, `.uid`) se commitean junto a ellos.

## 5. Motor ({{MOTOR}}) y sonido
- PROHIBIDO lanzar el motor directamente. Siempre `./tools/motor_silencioso.sh <rol> ...`
  (fuerza el modo sin sonido y adquiere el candado `motor`, que dura mientras viva el motor).
- Builds: `./tools/locks/with_lock.sh {{CANDADO_BUILD}} <rol> <comando>`.
- Si el candado está ocupado (código 75): no reintentes en bucle; sigue con otra tarea y vuelve después.
  Si avisa de «probable huérfano», comprueba el PID con la orden que da y, si no es el motor ni una build, libéralo como indica.
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
  commitear por ruta y pedir vaciado.
- La memoria se deja en un punto limpio de corte: archivo exacto y estado para retomar sin historial.
- `coordinador` nunca se vacía por su cuenta: avisa cuando conviene, deja al día `memoria_coordinador.md` y lo vacía la persona responsable.

## 8. Calidad antes de entregar
- Toda escena o pantalla tocada debe arrancar limpia en modo sin interfaz y llevar captura antes de entregarse.
- Toda pieza visual se valida lado a lado con `docs/arte/referencia_estilo.md` y dentro del conjunto, nunca aislada.
- Nada llega a la persona responsable sin pasar por `auditor-calidad`.
- Un fallo visual o de flujo que se repite se convierte en un detector automático en las rutas de tests.
- Tope de rondas de corrección: si persiste un fallo estructural, se rehace desde cero.

## 9. Escalado y trabajo nocturno
- Dudas de alcance, normas nuevas, compras o publicación → `docs/direccion/pendientes_manana.md` y seguir con otra cosa.
- No inventes decisiones de producto: si la especificación no lo dice, se escala.
- El trabajo sin supervisión sigue `docs/direccion/plan_nocturno.md`. Las rondas las lanza `coordinador` cuando lo pide la persona responsable.
- Pausas por cuota: `coordinador` las declara en el tablón indicando qué sigue y qué espera.
- No lances todas las sesiones a la vez sobre la misma tanda.

## 10. Producto (recordatorio mínimo)
- {{MOTOR}}; plataformas: {{PLATAFORMAS}}.
- {{DESCRIPCION_PRODUCTO}}

## 11. Sesiones en la nube
- Al empezar: `./tools/hooks/arranque_rol.sh <rol>` (activa los hooks y fija el rol). Trabaja en la rama automática de la sesión, partiendo de `{{RAMA_PRINCIPAL}}` actualizada, y abre PR hacia `{{RAMA_PRINCIPAL}}`.
- Merge solo la persona responsable (o `coordinador` si así lo pide). Horas siempre con `TZ={{ZONA_HORARIA}} date "+%Y-%m-%d %H:%M"`.
- La fila de la entrega va en `docs/direccion/entregas_nube/<lote>.txt` (mismo formato que el tablón), en el commit de la entrega;
  la nube no edita `tablon.md`. Tras fusionar, `coordinador` ejecuta `./tools/hooks/volcar_entregas_nube.sh` y commitea por rutas.
- No pueden avisar a otros roles: la persona responsable pega el resultado al coordinador.

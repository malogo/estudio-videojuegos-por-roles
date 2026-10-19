# Plan de endurecimiento: candados, motor y tablón

Revisión de un análisis externo sobre la plantilla (5 "vulnerabilidades" y 5 recomendaciones), contrastado con
el código real y con reproducciones. Criterio de priorización pedido: **coste, calidad y velocidad**.
Fecha: 2026-10-19. Rama: `claude/festive-heisenberg-wshksl`. Este archivo se puede borrar cuando el plan esté hecho.

---

## 0. Veredicto por punto

| # | Punto del análisis | ¿Aplica? | Evidencia (reproducida en un despliegue Godot de la plantilla) | Decisión |
|---|---|---|---|---|
| 1 | `with_lock.sh`: TOCTOU y PID reciclado | **En parte** | La adquisición **ya es atómica** (`noclobber` = `O_EXCL`): 40 intentos simultáneos → entra 1. Pero hay dos fallos reales: (a) si el envoltorio muere con `kill -9`, **el motor hijo sigue vivo y una segunda sesión toma el candado y arranca otro motor a la vez** (reproducido); (b) un candado con un PID reciclado por otro proceso bloquea con 75 indefinidamente (reproducido). | `flock` cuando exista + plan B mejorado. **P0** |
| 2 | Índice de git compartido | **En parte** | `git add -A/.`, `commit -a`, `stash`… ya están bloqueados y `commit-msg` rechaza rutas ajenas. Pero el tablón (archivo de todos) **sí produce commits cruzados**: si A añade su fila y aún no ha commiteado, el commit por rutas de B se lleva la fila de A (anunciando una entrega que no existe) y después el commit de A falla en `pre-commit` (reproducido). Los choques con `.git/index.lock` son transitorios (reintento). | Entrega atómica de la fila + commit con candado `git`. **P0** |
| 3 | El motor escribe fuera de la jurisdicción del rol | **En parte** | `.godot/` está en `.gitignore` y no cuenta para la propiedad. En Godot 4.7.2 `--import` creó `.gd.uid` en carpetas de otro rol; `--editor --quit` **no** reescribió `project.godot`. En Unity es esperable más (`.meta`, `ProjectSettings/`, `packages-lock.json`); a verificar. Lo del InputMap en `project.godot` es **por diseño** (se pide por tablón). | Aviso determinista de lo que cambió el motor, agrupado por dueño. **P1** |
| 4 | `tablon.md` crece y gasta tokens | **Casi no** | `arranque_rol.sh` ya muestra solo las filas dirigidas al rol desde su último vaciado; las normas prohíben leer el tablón entero; el formato es una línea validada por regex en `pre-commit` y en la auditoría; `plan_nocturno.md` ya hace de "estado actual". Lo que falta: el archivado a ~200 líneas es manual (lo hace el LLM a mano). | Script de archivado + aviso de tamaño. JSONL **no**. **P1** |
| 5 | El motor devuelve 0 con errores | **Sí** | Godot 4.7.2: `--headless --import` con un recurso inexistente y una escena rota → **exit 0**; ejecutar una escena con textura inexistente y un `SCRIPT ERROR` en tiempo de ejecución → **exit 0**. `motor_silencioso.sh` solo propaga el código del motor. | Log a archivo + resumen + detección de errores. **P0** |
| R3 | `pre-commit` con `AGENT_ROLE` | **No** | Ya existe y es más fuerte: `propiedad.tsv` + `commit-msg` + guarda de Edit/Write. La propuesta es más débil (sin variable = sin control; regex amplias). | Descartar. |
| R5 | EventBus / contratos | **Solo como guía** | Es arquitectura del juego, no del sistema de trabajo; depende del motor y la decide `arquitecto-sistemas` con la persona responsable. | Dos líneas de guía en la ficha y en la especificación. **P3** |

Hallazgos propios (no estaban en el análisis):
- `extras/godot/nuevo_uid.sh` cita `./tools/run_godot_silent.sh`, que no existe (es `./tools/motor_silencioso.sh`).
- `commit-msg` se fía del rol escrito en el mensaje: una sesión despistada puede commitear como otro rol si las rutas son de ese rol. El hook PreToolUse conoce el rol declarado de la sesión y puede compararlo.
- `with_lock.sh` usa `stat -c` (solo GNU).

---

## 1. Principios del plan (coste, calidad, velocidad)

- **Coste de tokens primero**: lo que más gasta hoy es la salida cruda del motor en el contexto y los reintentos de commit
  por fallos de formato/hora. Se ataca eso antes que lo cosmético.
- **Sin cambiar la interfaz**: `with_lock.sh <candado> <rol> <orden...>`, `motor_silencioso.sh <rol> ...`, código 75,
  formato del tablón y nombres de rol se quedan igual. Los proyectos ya desplegados pueden copiar los archivos nuevos.
- **Sin dependencias obligatorias nuevas**: `flock` se usa si está; si no, plan B. Requisitos siguen siendo git, bash y Python 3.
- **Cada cambio con su prueba** en `tools/hooks/tests/prueba_guardas.sh` (hoy 19/19 OK) y con un motor falso,
  para que la batería siga tardando segundos y no necesite Godot/Unity.
- **No esperar en bucle por defecto** (norma §5): ocupado → 75 y a otra cosa. Solo las secciones críticas cortas (commit)
  esperan unos segundos, porque un reintento del LLM cuesta más que esperar.

---

## 2. Fases

Estimaciones de esfuerzo orientativas (trabajo del agente, con pruebas). Una fase = un commit.

### Fase 0 — Verificaciones previas (≈30 min, sin cambios de código)
1. ¿Trae `flock` Git para Windows? ¿Y macOS (no de serie; `brew install flock`)? Decide si el plan B es crítico o residual.
2. Unity (si hay licencia/binario a mano): qué archivos versionados toca `-batchmode -nographics -quit`, si `-logFile -`
   saca el log por la salida estándar en Windows, y si algún proceso que deja vivo (p. ej. el cliente de licencias)
   hereda el descriptor del candado (`lsof tools/locks/motor.lock` tras salir).
3. Godot: ya verificado con 4.7.2 (códigos de salida y `.uid`). Repetir solo si cambia la versión objetivo.

### Fase 1 — Candado robusto · P0 · ≈2-3 h
**Archivos:** `plantilla/tools/locks/with_lock.sh`, `plantilla/tools/auditoria/auditoria_proceso.sh` (§3),
`plantilla/.gitignore` (comentario), `normas_comunes.md` §5 ("candado PID" → "candado"), `readme.txt` §2/§8, pruebas.

**Diseño:**
- **Modo `flock`** (si `command -v flock`): `exec 9>>"$LOCK_FILE"`; `flock -n 9` (o `flock -w "$ESPERA_CANDADO" 9`).
  Tras adquirirlo se escribe `rol:pid:epoch:pid_hijo` en el archivo (diagnóstico para el mensaje "ocupado por…").
  El hijo **hereda el descriptor**: el candado dura mientras viva el motor aunque el envoltorio muera (arregla 1a)
  y el núcleo lo suelta solo si todo muere (arregla 1b). Al salir se vacía el archivo; **no se borra** (borrar un
  archivo de `flock` abre carreras de inodo).
  Interruptor `CANDADO_HEREDA=0` (cerrar el descriptor al hijo) por si en la Fase 0 se ve que un motor deja procesos
  residentes que lo retendrían.
- **Plan B** (sin `flock`, o forzado con `CANDADO_MODO=pid` para las pruebas): el mecanismo actual (`noclobber` + PID)
  más: el comando se lanza en segundo plano, se apunta su PID y el candado cuenta como vivo si vive el envoltorio
  **o** el hijo (arregla 1a); INT/TERM se reenvían al hijo. Para el PID reciclado: si el proceso con ese PID empezó
  después de crearse el candado (`ps -o etimes=` cuando exista) se trata como huérfano; si no se puede saber y el
  candado tiene más de `CANDADO_MAX_HORAS` (6 por defecto), el mensaje dice "probable huérfano" con la orden exacta
  para liberarlo (nunca se roba solo). `stat -c` → alternativa portable.
- `ESPERA_CANDADO=<s>` opcional (0 por defecto: se mantiene la norma de no esperar).
- Auditoría §3: en modo `flock` un archivo con datos viejos no es hallazgo; sí lo es un candado ocupado más de
  `CANDADO_MAX_HORAS`. En plan B, como hoy, más el PID del hijo.

**Pruebas nuevas:** 20 adquisiciones simultáneas → 1 dentro; `kill -9` al envoltorio con el hijo vivo → la segunda
sesión recibe 75 hasta que el hijo acaba; archivo con PID ajeno vivo pero sin `flock` → se adquiere; lo mismo con
`CANDADO_MODO=pid` (huérfano reclamado, hijo vivo → 75); `ESPERA_CANDADO=2` espera y entra.

**Coste/calidad/velocidad:** ~150 líneas; elimina la corrupción de caché por dos motores a la vez y los bloqueos
permanentes; adquirir con `flock` es más rápido que hoy (sin `cat`/`kill -0`).

### Fase 2 — Motor con veredicto determinista y salida corta · P0 · ≈2-3 h
**Archivos:** `plantilla/tools/motor_silencioso.sh`, nuevo `plantilla/tools/auditoria/ruido_motor.txt`
(dueño `auditor-calidad`, vacío por defecto), `.gitignore` (+ `.motor_logs/`), `cuestionario.md` (B11 y B5 de Unity),
`ejemplo_valores_unity_pc.json`, `normas_comunes.md` §5/§8, ficha de `auditor-calidad`, `plantilla_encargo.md`, pruebas.

**Diseño:**
- Salida estándar y de error del motor → `.motor_logs/<fecha>_<rol>.log` (se guardan los 30 últimos).
- Errores = líneas que casan con `{{REGEX_ERRORES_MOTOR}}` menos las que casan con alguna ERE de `ruido_motor.txt`
  (cada una con su motivo). Valores por defecto en el cuestionario:
  Godot `^(USER )?(SCRIPT )?ERROR:` · Unity `error CS[0-9]+|Scripts have compiler errors|Exception:` · Unreal `Error:`.
  En Unity se añade `-logFile -` a los argumentos silenciosos para poder capturar el log.
- Resumen de **≤25 líneas**: código del motor, nº de errores (únicos), las 15 primeras líneas únicas recortadas,
  **errores por dueño** (rutas `res://…`, `Assets/…` o relativas que existan → `dueno_de_ruta`) y la ruta del log.
  `MOTOR_SALIDA=completa` imprime el log entero (para personas).
- Código de salida: el del motor si no es 0; **65** si el motor dio 0 pero hay errores; 75 si el candado está ocupado.
- "Arranca limpia" (normas §8 y puerta del auditor) pasa a significar `motor_silencioso.sh` → 0. El silenciado de ruido
  lo decide el auditor, no el rol que produce el error.

**Pruebas nuevas** (motor falso `MOTOR_BIN=tools/hooks/tests/motor_falso.sh`): `SCRIPT ERROR … res://core/a.gd` con
exit 0 → 65 y atribuido a `arquitecto-sistemas`; mismo error listado en `ruido_motor.txt` → 0; motor con exit 2 → 2;
5.000 líneas de log → salida ≤25 líneas.

**Coste/calidad/velocidad:** es la mejora que más ahorra: un import o una build de Unity vuelca de cientos a miles de
líneas (miles a decenas de miles de tokens por ejecución) que hoy entran enteras en el contexto; pasan a ~300 tokens.
Elimina los falsos "arranca limpio". Añade milisegundos (`grep` sobre el log).

### Fase 3 — Entregas atómicas al tablón · P0 · ≈3 h
**Archivos:** nuevo `plantilla/tools/hooks/entregar.sh`, `commit-msg`, `guard_propiedad.sh`, `reglas_comando.sh`,
`pre-commit` (mensaje de ayuda), `normas_comunes.md` §3/§4/§11, `CLAUDE.md`, `readme.txt` §6.2, `desplegar.md` §9, pruebas.

**Diseño:**
- `./tools/hooks/entregar.sh <rol> "<qué>" "<ruta o commit>" <destino> [--cuerpo "<línea>"]... [--nube <lote>] [-- <rutas>...]`
  1. Valida rol, destino (rol o "persona responsable") y que los campos no lleven `|` ni saltos de línea.
  2. Toma el candado `git` con `ESPERA_CANDADO=60` (un commit dura segundos).
  3. Comprueba que `tablon.md` no tiene cambios sin commitear; si los tiene, aborta y enseña esas filas (son de otro).
  4. Añade la fila con la hora real (`TZ={{ZONA_HORARIA}} date`) y hace `git commit -m "<rol>: <qué>" -- <rutas> tablon.md`.
  5. Si el commit falla, deja el tablón como estaba y muestra el motivo del hook.
  Con `--nube <lote>` escribe en `entregas_nube/<lote>.txt` en vez del tablón. Sin rutas sirve para encargos del
  coordinador y para commits de memoria.
- `commit-msg`: toda fila añadida al tablón o a `entregas_nube/` debe tener `origen` = rol del commit (salvo merges y
  las filas que se vuelcan desde `entregas_nube`). Es la red de seguridad que hace imposible el commit cruzado.
- `guard_propiedad.sh` bloquea Edit/Write sobre `tablon.md` y `reglas_comando.sh` bloquea `>>`/`>`/`tee` hacia
  `tablon.md` en Bash, con el mensaje "usa ./tools/hooks/entregar.sh". Los scripts del sistema (`volcar_entregas_nube.sh`,
  archivado) no pasan por esas guardas.
- `.git/index.lock` huérfano: `entregar.sh` lo detecta y explica cómo comprobarlo; nunca lo borra solo.

**Pruebas nuevas:** el escenario reproducido (A añade fila sin commitear, B entrega) → `>>` de A bloqueado; B entrega
solo su fila; commit con fila de otro origen → rechazado por `commit-msg`; commit fallido → tablón restaurado;
dos `entregar.sh` a la vez → ambos entran, uno detrás de otro.

**Coste/calidad/velocidad:** una sola orden por entrega en lugar de `date` + `echo` + `commit` y sus reintentos por
formato u hora (menos turnos y tokens); el tablón deja de mentir sobre entregas; serializa los commits y evita casi
todos los choques de `index.lock`.

### Fase 4 — Efectos colaterales del motor · P1 · ≈1,5 h
**Archivos:** `plantilla/tools/motor_silencioso.sh`, `normas_comunes.md` §4/§5, pruebas.
- Foto de `git status --porcelain -z --untracked-files=all` (más la fecha de modificación de lo ya modificado) antes
  y después de ejecutar el motor. Si cambian archivos versionables, se añade al resumen: "el motor ha creado/cambiado
  N archivos: `<dueño>`: rutas (≤10)", indicando que pueden venir de otra sesión que trabajaba a la vez.
- Norma: lo que el motor genere en archivos de otro dueño no se revierte ni se commitea; se avisa al dueño con
  `entregar.sh` (sin rutas). No cambia el código de salida.
- Prueba con el motor falso que crea `core/x.gd.uid` ejecutado por `especialista-escenas-ui`.
- **Coste/velocidad:** `git status` tarda milisegundos en un proyecto mediano y ~1-2 s en uno grande de Unity,
  poco frente a lo que tarda el motor.

### Fase 5 — Mantenimiento del tablón · P1 · ≈1,5 h
**Archivos:** nuevo `plantilla/tools/hooks/archivar_tablon.sh` (lo usa `coordinador`), `propiedad.tsv`
(+ `docs/direccion/archivo/**` → coordinador), `auditoria_proceso.sh` (nueva comprobación: tablón > 200 filas),
`arranque_rol.sh` (aviso al coordinador), ficha de `coordinador`, normas §3, pruebas.
- Mueve a `docs/direccion/archivo/tablon_<fecha>.md` las filas anteriores al **"Último vaciado" más antiguo** de todas
  las memorias (así ningún rol pierde filas que aún no ha leído) y deja siempre las 50 últimas. Commit propio con candado `git`.
- **Descartado**: JSONL y `estado_actual.md`. El tablón ya es una línea por evento validada por regex, legible por la
  persona y por 4 scripts (pre-commit, arranque, auditoría y volcado); JSONL repetiría las claves en cada fila (más tokens), rompería esos scripts y no ganaría
  nada; `plan_nocturno.md` ya es el estado actual.

### Fase 6 — Extras baratos · P2 · ≈2 h
1. `pre_tool_guard.sh`: bloquear `git commit -m "<rol>: …"` y `entregar.sh <rol>` cuando `<rol>` ≠ rol declarado por la
   sesión (el hook ya lo conoce). Cierra el hueco de commitear como otro rol por despiste. Con pruebas.
2. `extras/godot/nuevo_uid.sh`: corregir la referencia a `run_godot_silent.sh` → `motor_silencioso.sh`.
3. `actualizar.md`: cómo llevar estos cambios a un proyecto ya desplegado (lista de archivos y pasos).
4. Opcional: GitHub Actions en este repositorio que despliegue la plantilla con valores de Godot y de Unity y pase
   `prueba_guardas.sh` + `shellcheck` (~1 min por ejecución). Evita regresiones de la plantilla.

### Fase 7 — Solo documentación · P3 · ≈30 min
- **Contratos entre roles**: en la ficha de `arquitecto-sistemas` y en `especificaciones.md` §3, "antes de implementar
  un sistema que usa otro rol, publica su contrato (eventos/señales y datos) y avísalo por tablón; la interfaz se prueba
  con datos simulados". Sin imponer un EventBus: depende del motor y es decisión del proyecto.
- **Modo worktree** (más de 2 sesiones a la vez): `readme.txt` §6/§8. Cada sesión en su `git worktree` y su rama,
  con entregas en `entregas_nube/` y fusión por el coordinador (el flujo de la nube, que ya existe). Los hooks ya
  funcionan con worktrees (`--git-common-dir`) y los candados quedan por worktree (correcto: cada uno tiene su caché).
  Coste a advertir: una caché del motor por worktree (reimportar en Godot; en Unity, regenerar `Library/` puede llevar
  mucho tiempo y espacio) y más fusiones. Por eso **no** es el modo por defecto.

---

## 3. Lo que no se hará (y por qué)

| Propuesta del análisis | Motivo |
|---|---|
| Candados en `/tmp/estudio_agentes_<nombre>.lock` | Chocan entre proyectos del mismo equipo y entre worktrees; `tools/locks/` es por proyecto. |
| `with_lock.sh` sin argumento de rol | Rompe `motor_silencioso.sh`, la regla de `reglas_comando.sh`, las normas y los mensajes de "ocupado por". |
| Espera de 120 s por defecto | Contradice la norma §5 (75 y a otra cosa) y deja al agente parado dentro de la llamada. Solo como opción. |
| `cat` del log completo del motor | Llena el contexto: justo lo contrario de lo que se busca. |
| `pre-commit` con `AGENT_ROLE` | Más débil que lo que hay (sin variable no controla nada). |
| Worktrees por defecto | Coste de caché y fusiones no justificado con 2 sesiones como máximo; queda como modo documentado. |
| JSONL + `estado_actual.md` | Ver Fase 5. |
| Patrón `Condition .* is true` aparte | En Godot ya sale como `ERROR: Condition …` y lo recoge el patrón general; el ruido benigno va a `ruido_motor.txt`. |

---

## 4. Criterio de hecho global

- `prueba_guardas.sh` en verde en un despliegue Godot y en uno Unity (hoy 19 pruebas; tras el plan, ~40) y en menos de ~30 s.
- `grep -rn "{{" CLAUDE.md docs tools .claude` vacío tras desplegar con `ejemplo_valores_unity_pc.json` y con unos valores de Godot.
- Los tres escenarios reproducidos (dos motores a la vez, PID reciclado, fila cruzada en el tablón) son pruebas que
  fallaban antes y pasan después.
- Smoke test manual con Godot 4.7.2 real: escena con recurso inexistente → `motor_silencioso.sh` sale con 65 y
  atribuye el error al dueño del archivo.

## 5. Orden y entrega

Fases 0 → 1 → 2 → 3 (P0, ≈8 h) en commits separados en `claude/festive-heisenberg-wshksl`; después 4-5 (P1) y 6-7
si se aprueban. PR solo cuando lo pida la persona responsable.

Riesgos: (1) el plan B (sin `flock`) solo mitiga el PID reciclado con heurística; (2) el código 65 puede romper
órdenes encadenadas que hoy pasan "en falso", que es justo lo que se busca, pero hay que avisarlo en `actualizar.md`;
(3) el patrón de errores de Unity/Unreal necesita afinarse con logs reales (para eso está `ruido_motor.txt`).

---

## Anexo — Reproducciones (plantilla desplegada con valores de Godot; Godot 4.7.2-stable para Linux)

```
B) 40 with_lock.sh simultáneos sobre el mismo candado      -> procesos dentro a la vez: 1
C) kill -9 al envoltorio con el "motor" (hijo) vivo        -> [LOCK HUÉRFANO] ... Reclamando candado.
                                                              motor 2 arrancó mientras el 1 sigue vivo
D) motor.lock con PID de otro proceso vivo (de hace 24 h)  -> [LOCK OCUPADO] ... (código 75)
E) mismo caso C con flock (hijo hereda el descriptor)      -> sigue ocupado mientras vive el hijo; libre al morir
A) A añade su fila sin commitear; B commitea por rutas     -> el commit de B incluye la fila de A;
                                                              después A: [ERROR PRE-COMMIT] La fila ... debe ir en el mismo commit
Godot --headless --import con recurso inexistente          -> EXIT=0 (ERROR: Failed loading resource ...)
Godot escena con textura inexistente + SCRIPT ERROR        -> EXIT=0
Godot --import en proyecto con .gd sin .uid                 -> crea systems/*.gd.uid (carpeta de otro rol)
Godot --editor --quit                                       -> solo cambia .godot/ (ignorado); project.godot intacto
```

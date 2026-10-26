# Cuestionario de despliegue

La sesión de despliegue hace estas preguntas **por bloques**, enseña siempre el valor por defecto y no inventa
respuestas: si la persona no sabe, se usa el defecto y se anota en `docs/direccion/pendientes_manana.md`.
Cada respuesta acaba en una clave de `valores.json` (ver `ejemplo_valores_unity_pc.json` y `ejemplo_valores_godot_pc.json`), que rellena los
marcadores `{{ASI}}` de `plantilla/`. Una clave con lista repite la línea por elemento (lista vacía = línea fuera).

## Bloque A — Proyecto

| # | Pregunta | Opciones | Por defecto | Clave · archivos que cambia |
|---|---|---|---|---|
| A0 | ¿Qué nivel de autonomía quieres? Cuanto menos intervengas durante el trabajo, más hay que dejar escrito antes. | `bajo`: control paso a paso; basta la visión general (§1 de la especificación) y lo demás se completa lote a lote · `medio`: rondas supervisadas; antes de la ronda N, sus sistemas y contratos escritos · `alto`: flujo desatendido con `tools/despachador.sh` (una sesión `claude -p` por lote, en una rama aparte); antes de la ronda 1, la especificación entera (§1-§4, con criterios de desempate) y la cuota en USD | `medio` | `NIVEL_AUTONOMIA` · normas §9, especificaciones.md, plan_nocturno.md, ficha de coordinador. En `medio` y `alto`, lo primero tras desplegar es escribir la especificación con el coordinador |
| A1 | ¿Cómo se llama el proyecto? | texto libre | nombre de la carpeta | `NOMBRE_PROYECTO` · CLAUDE.md, especificaciones.md |
| A2 | Describe el juego en 1-2 frases (género, modo de juego, modelo de negocio). | texto libre | «(POR ESCRIBIR: descripción en 1-2 frases)» | `DESCRIPCION_PRODUCTO` · normas §10, especificaciones.md |
| A3 | ¿En qué plataformas saldrá? | PC (Windows/macOS/Linux), móvil (Android/iOS), consola, web; varias | PC | `PLATAFORMAS` · normas §10. En consola: ver bloque D (SDK y NDA) |
| A4 | ¿Idioma de trabajo de las sesiones y documentos? | español, otro | español | sin clave: si es otro, la sesión traduce todos los archivos tras rellenar |
| A5 | ¿Carpeta vacía o proyecto que ya existe? | vacía / existente | vacía | si existe: ver paso 6 de desplegar.md (dar dueño a lo que ya hay) |

## Bloque B — Motor y herramientas

| # | Pregunta | Opciones | Por defecto | Clave · archivos que cambia |
|---|---|---|---|---|
| B1 | ¿Motor y versión exacta? | Godot 4.x, Unity 6, Unreal 5.x, otro (propio, web, etc.) | Godot 4 (última estable) | `MOTOR`, `MOTOR_EXTRA` (`godot`, `unity` o vacío) · CLAUDE.md, normas §5, agentes, hooks |
| B2 | ¿Lenguaje principal? | GDScript, C#, C++, Blueprints + C++, TypeScript… | según motor | `LENGUAJE` · ficha de arquitecto-sistemas |
| B3 | ¿Cuál es el ejecutable del motor? En Windows, su **ruta completa** con barras `/` (no suele estar en el PATH de Git Bash); en Linux y macOS, el nombre si está en el PATH. Compruébalo antes: `command -v "<valor>"` debe encontrarlo | Godot `godot` · Godot en Windows `C:/Godot/Godot_v4.7.2-stable_win64_console.exe` (la versión `_console` saca la salida por la terminal) · `Unity` (en Windows, `C:/Program Files/Unity/Hub/Editor/<versión>/Editor/Unity.exe`) · `UnrealEditor-Cmd` | según motor | `BINARIO_MOTOR` · tools/motor_silencioso.sh (también lo comprueban `desplegar.md`, paso 10, y `tools/despachador.sh`, que no arranca sin él) |
| B4 | Patrón para reconocer el ejecutable (para prohibir lanzarlo a pelo; vale también tras `flatpak run`, `snap run` y `open -a`) | Godot `^godot(4\|sharp\|[._-]v?[0-9].*)?(\.exe)?$\|^godot_v[0-9]` · Unity `^unity(\.exe)?$` · Unreal `^unrealeditor(-cmd)?(\.exe)?$` · sin motor `^$` | según motor | `REGEX_BINARIO_MOTOR` · tools/hooks/reglas_comando.sh |
| B5 | Argumentos que lo lanzan sin sonido ni ventana | Godot `--audio-driver Dummy` (`--headless` no se fuerza porque las capturas necesitan ventana: se pasa al llamarlo para importar, tests y exportar) · Unity `-batchmode -nographics -logFile -` (`-logFile -` saca el log por la salida para poder revisarlo) · Unreal `-nosound -unattended -nullrhi` | según motor | `ARGS_MOTOR_SILENCIOSO` · tools/motor_silencioso.sh |
| B6 | Opción que indica la carpeta del proyecto | Godot `--path` · Unity `-projectPath` · Unreal: vacío (el `.uproject` va como primer argumento) | según motor | `ARG_RUTA_PROYECTO` · tools/motor_silencioso.sh |
| B7 | Archivos de configuración del motor (los cuida arquitecto-sistemas) | Godot `project.godot`, `export_presets.cfg` · Unity `ProjectSettings/**`, `Packages/manifest.json` · Unreal `Config/**`, `*.uproject` | según motor | `CONFIG_MOTOR` (lista) · propiedad.tsv, ficha de arquitecto |
| B8 | Qué genera el motor y no se commitea | Godot `.godot/` · Unity `Library/`, `Temp/`, `Obj/`, `Build/`, `Logs/`, `UserSettings/` · Unreal `Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/` | según motor | `IGNORAR_MOTOR` (lista) · .gitignore |
| B9 | Guía oficial de buenas prácticas del motor | URL | la del motor | `GUIA_BUENAS_PRACTICAS` · normas §5 |
| B10 | ¿Cómo se hace una build y cómo se llama su candado? | comando + nombre corto (`build_pc`, `android_build`…) | `build` | `CANDADO_BUILD`, `COMANDO_BUILD_EJEMPLO` · normas §5, with_lock.sh |
| B11 | Patrón (ERE) de las líneas de error en la salida del motor (el motor puede salir con 0 aunque haya errores) | Godot `^(USER )?(SCRIPT )?ERROR:` · Unity `error CS[0-9]+\|Scripts have compiler errors\|Exception:` · Unreal `Error:` · sin motor: vacío | según motor | `REGEX_ERRORES_MOTOR` · tools/motor_silencioso.sh (el ruido benigno lo silencia auditor-calidad en `tools/auditoria/ruido_motor.txt`) |

## Bloque C — Equipo y carpetas

| # | Pregunta | Opciones | Por defecto | Clave · archivos que cambia |
|---|---|---|---|---|
| C1 | ¿Qué roles hacen falta? `coordinador`, `arquitecto-sistemas` y `auditor-calidad` son obligatorios. | + `especialista-escenas-ui`, `director-arte`, y extras: `disenador-sonido`, `especialista-backend`, `especialista-red`, `disenador-niveles`… | los 5 clásicos | `ROLES` (lista) · propiedad.sh, CLAUDE.md, normas, agentes, fichas y memorias |
| C2 | Carpetas de código base y sistemas (arquitecto-sistemas) | patrones `carpeta/**` | Godot `core/**`, `systems/**` · Unity `Assets/Scripts/**` · Unreal `Source/**` | `RUTA_NUCLEO` (lista) |
| C3 | Carpetas de escenas, niveles e interfaz (especialista-escenas-ui) | patrones | Godot `scenes/**` · Unity `Assets/Scenes/**`, `Assets/Prefabs/**`, `Assets/UI/**` · Unreal `Content/Maps/**`, `Content/UI/**` | `RUTA_ESCENAS` (lista) |
| C4 | Carpetas de arte (director-arte) | patrones | Godot `assets/sprites/**` · Unity `Assets/Art/**` · Unreal `Content/Art/**` | `RUTA_ARTE` (lista) |
| C5 | Carpetas de tests (auditor-calidad) | patrones | `tests/**` · Unity `Assets/Tests/**` | `RUTA_TESTS` (lista) |
| C6 | Para cada rol extra: ¿de qué carpetas es dueño, qué hace y a quién entrega? | texto | — | ficha generada con `{{COMPLETAR}}` + filas nuevas en propiedad.tsv (sección «Roles extra») |

En Unity, cada carpeta de `Assets/` lleva también su `.meta` (`Assets/Art.meta`): añádelo a la lista del mismo dueño.

## Bloque D — Arte, sonido, backend y red

| # | Pregunta | Opciones | Por defecto | Qué cambia |
|---|---|---|---|---|
| D1 | ¿Hay arte generado con IA, de artistas o ambos? | IA / artistas / ambos / sin arte | ambos | sin arte: quitar `director-arte` de ROLES y la línea de arte de normas §6 |
| D2 | ¿Hay sonido o música? | sí / no | sí | con mucho sonido: rol extra `disenador-sonido`. La norma «nunca reproducir sonido» se queda siempre |
| D3 | ¿Hay backend o servidor (Supabase, Firebase, servidor propio…)? | sí / no | no | sí: rol extra `especialista-backend` o carpeta para arquitecto-sistemas; norma de secretos (bloque F) |
| D4 | ¿Multijugador en red? | sí / no | no | sí: rol extra `especialista-red` y lote de pruebas de red en el plan |
| D5 | ¿Consola (SDK bajo NDA)? | sí / no | no | sí: el SDK y su documentación nunca entran en el repo ni en la nube; anotar en normas §9 |

## Bloque E — Sesiones, modelos y presupuesto

| # | Pregunta | Opciones | Por defecto | Clave · archivos que cambia |
|---|---|---|---|---|
| E1 | ¿Qué modelo usan los subagentes que ejecutan código? | `sonnet`, `opus`, `haiku` (alias de Claude Code) | `sonnet` | `MODELO_EJECUTOR` · agentes, normas §6 |
| E2 | ¿Y el subagente de solo lectura? | `haiku`, `sonnet` | `haiku` | `MODELO_LECTOR` · agente-buscador-lectura, normas §6 |
| E3 | ¿Cuántas sesiones a la vez como máximo? | 1-4 | 2 | `MAX_SESIONES` · plan_nocturno.md |
| E4 | ¿Presupuesto o cuota por ronda o por lote? | texto; en nivel `alto`, `<n> USD por ronda` (entero o decimal: lo exige la puerta y es el tope de gasto del despachador) | «a decidir» | `CUOTA` · plan_nocturno.md |
| E5 | ¿Se trabajará con sesiones en la nube (Claude Code en la web)? | sí / no | sí | no: se puede quitar la §11 de normas (los hooks siguen igual) |
| E6 | ¿Zona horaria del equipo? | nombre IANA + regla POSIX | `Europe/Madrid` y `CET-1CEST,M3.5.0,M10.5.0/3` | `ZONA_HORARIA`, `ZONA_HORARIA_POSIX` · pre-commit, auditoría, normas §11 |
| E7 | ¿Cuántos rechazos de `auditor-calidad` por lote antes de bloquearlo? | entero ≥ 1 | 3 | `MAX_RECHAZOS` · especificaciones.md §4, normas §9, ficha de auditor-calidad |

## Bloque F — Versiones, tests y seguridad

| # | Pregunta | Opciones | Por defecto | Clave · archivos que cambia |
|---|---|---|---|---|
| F1 | ¿Dónde está el repositorio? | GitHub, GitLab, Bitbucket, solo local | GitHub | sin clave; la nube necesita GitHub |
| F2 | ¿Nombre de la rama principal? | `main`, `master`… | `main` | `RAMA_PRINCIPAL` · normas §11 |
| F3 | ¿Archivos grandes (texturas, audio, `.uasset`)? | Git LFS sí / no | sí en Unreal y Unity | si sí: reglas de LFS en `.gitattributes` (las añade arquitecto-sistemas tras el despliegue, debajo de las de finales de línea) |
| F4 | ¿Cómo se ejecutan los tests sin ventana? | comando | Godot `--headless --script …` · Unity `-runTests -testPlatform EditMode` · Unreal `-ExecCmds="Automation RunTests …"` | primer lote del plan para auditor-calidad |
| F5 | ¿Hay claves o secretos (API, firma de builds)? | sí / no | no | sí: nunca en el repo; `.gitignore` + variables de entorno; anotar en normas §4 |
| F6 | ¿Shell del equipo? | Linux/macOS (bash), Windows (Git Bash) | según SO | Windows: Git Bash y Python obligatorios (los hooks son bash); `python` en lugar de `python3`. macOS: `brew install bash` (los hooks necesitan bash 4+) |

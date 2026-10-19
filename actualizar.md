# Actualizar un proyecto ya desplegado (instrucciones para una sesión de chat)

Para llevar una versión nueva de la plantilla a un proyecto que ya usa el sistema. `<PLANTILLA>` es la carpeta de
este archivo y `valores.json` el del despliegue original (si se perdió, rehazlo con `cuestionario.md`: basta con
copiar los valores de `tools/hooks/propiedad.tsv`, `tools/motor_silencioso.sh` y `CLAUDE.md` del proyecto).
Hazlo con todas las demás sesiones paradas y el árbol limpio (`git status`).

## 1. Desplegar la versión nueva aparte
```bash
python3 <PLANTILLA>/rellenar_plantilla.py --valores <ruta>/valores.json --destino /tmp/plantilla_nueva
```
Si el script avisa de marcadores nuevos sin valor (p. ej. `REGEX_ERRORES_MOTOR`), añádelos a `valores.json`
(`cuestionario.md`, B11) y repite. Compara con el proyecto: `diff -ru /tmp/plantilla_nueva/tools tools` (y lo mismo
con `docs/direccion`, `CLAUDE.md`, `.claude` y `.gitignore`).

## 2. Copiar o fusionar, por dueño
Cada grupo lo cambia y lo entrega su dueño: declara antes ese rol (`./tools/hooks/fijar_rol.sh <dueño>`) y entrega
con `./tools/hooks/entregar.sh <dueño> "Actualiza la plantilla: <qué>" "<rutas>" persona-responsable -- <rutas>`.

| Dueño | Qué | Cómo |
|---|---|---|
| `arquitecto-sistemas` | `tools/hooks/*` (scripts, `pre-commit`, `commit-msg`, `tests/`), `tools/locks/with_lock.sh`, `tools/motor_silencioso.sh` | Copiar tal cual (`cp`), salvo que el proyecto los haya cambiado: entonces fusionar. |
| `arquitecto-sistemas` | `tools/hooks/propiedad.tsv`, `.gitignore`, `.claude/` | Fusionar a mano: llevan rutas propias del proyecto. |
| `auditor-calidad` | `tools/auditoria/auditoria_proceso.sh` | Copiar. `ruido_motor.txt` y `excepciones_proceso.txt` se conservan (crea `ruido_motor.txt` si no existe). |
| `coordinador` | `CLAUDE.md`, `docs/direccion/normas_comunes.md`, fichas, `plantilla_encargo.md` | Fusionar a mano, con aprobación de la persona responsable (normas §2). El tablón no se toca: su cabecera vieja sigue valiendo. |

Copia primero lo de `arquitecto-sistemas`: los hooks nuevos son los que validan las entregas siguientes.

## 3. Comprobar
- `./tools/hooks/tests/prueba_guardas.sh` en verde.
- `grep -rn "{{" CLAUDE.md docs tools .claude` solo enseña `{{COMPLETAR}}` ya conocidos (o nada).
- Una ejecución real del motor: `./tools/motor_silencioso.sh arquitecto-sistemas <argumentos de siempre>`.

## 4. Avisos de esta versión (endurecimiento de candados, motor y tablón)
- **Código 65 del motor**: `motor_silencioso.sh` sale con 65 si el motor dio 0 pero el log tiene errores. Órdenes
  encadenadas (`... && ...`) que antes pasaban «en falso» ahora paran: es lo buscado. Si el error es ruido benigno,
  lo silencia `auditor-calidad` en `tools/auditoria/ruido_motor.txt`. La salida del motor ya no entra en el contexto:
  va a `.motor_logs/` (añádelo a `.gitignore`). En Unity, `ARGS_MOTOR_SILENCIOSO` debe llevar `-logFile -`.
- **Entregas**: el tablón ya no se edita a mano (ni con Edit ni con `>>`/`tee`), tampoco `coordinador`. Las filas se
  añaden con `entregar.sh` y se archivan con `archivar_tablon.sh coordinador` (`propiedad.tsv` necesita la línea
  `docs/direccion/archivo/**	coordinador`). El archivado lee el «Último vaciado» de todas las memorias: si alguna
  no lo tiene legible, no archiva.
- **Rol de la sesión**: con el rol declarado, el hook bloquea `git commit -m "<otro rol>: ..."`, `entregar.sh`,
  `archivar_tablon.sh` y `motor_silencioso.sh` con otro rol.
- **Candados**: usan `flock` si existe; si no (Git Bash, macOS sin `brew install flock`), el plan B por PID. Los
  `tools/locks/*.lock` viejos se pueden borrar con todas las sesiones paradas.
- **Efectos colaterales**: el resumen del motor lista los archivos versionables que ha creado o cambiado (p. ej.
  `.uid` o `.meta` en carpetas de otro rol). No se revierten ni se commitean: se avisa al dueño.

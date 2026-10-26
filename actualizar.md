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
| `arquitecto-sistemas` | `tools/hooks/*` (scripts, `pre-commit`, `commit-msg`, `tests/`), `tools/locks/with_lock.sh`, `tools/motor_silencioso.sh`, `tools/despachador.sh` | Copiar tal cual (`cp`), salvo que el proyecto los haya cambiado: entonces fusionar. |
| `arquitecto-sistemas` | `tools/hooks/propiedad.tsv`, `.gitignore`, `.gitattributes`, `.claude/` | Fusionar a mano: llevan rutas propias del proyecto (si no había `.gitattributes`, cópialo). |
| `auditor-calidad` | `tools/auditoria/auditoria_proceso.sh`, `tools/auditoria/preparacion_ronda.sh` | Copiar. `ruido_motor.txt` y `excepciones_proceso.txt` se conservan (crea `ruido_motor.txt` si no existe). |
| `coordinador` | `CLAUDE.md`, `docs/direccion/normas_comunes.md`, `especificaciones.md`, cabecera de `plan_nocturno.md`, fichas, `plantilla_encargo.md` | Fusionar a mano, con aprobación de la persona responsable (normas §2). El tablón no se toca: su cabecera vieja sigue valiendo. |

Copia primero lo de `arquitecto-sistemas`: los hooks nuevos son los que validan las entregas siguientes.

## 3. Comprobar
- `./tools/hooks/tests/prueba_guardas.sh` en verde.
- `grep -rn "{{" CLAUDE.md docs tools .claude` solo enseña `{{COMPLETAR}}` ya conocidos (o nada).
- Una ejecución real del motor: `./tools/motor_silencioso.sh arquitecto-sistemas <argumentos de siempre>`.

## 4. Avisos de esta versión (niveles de autonomía y despachador)
- **Claves nuevas** `NIVEL_AUTONOMIA` (`bajo`, `medio` o `alto`) y `MAX_RECHAZOS` (`cuestionario.md`, A0 y E7). Si
  `valores.json` no las tiene, `rellenar_plantilla.py` usa `medio` y `3` y lo avisa: añádelas con lo que decida la persona.
- **Bloques condicionales**: la plantilla lleva `{{#SI NIVEL_AUTONOMIA=…}}` … `{{#FIN}}` y el rellenado deja solo el texto
  del nivel elegido; en `/tmp/plantilla_nueva` ya no aparecen.
- **Marcador único** `(POR ESCRIBIR: …)` para lo que falta por decidir. En la especificación del proyecto, cambia los
  «(Por escribir…)», «(Módulos, datos…)» y «(Contratos vigentes…)» viejos por apartados con ese marcador (o escríbelos
  ya) y sigue la estructura nueva: línea del nivel bajo el título, §2 con un apartado `### <Sistema> (ronda N)` por
  sistema, §3 con un apartado `### Contrato: <sistema> (ronda N)` por contrato, §4 «Criterios de Desempate y Topes» y
  §5 la estructura de carpetas.
- **Puerta de ronda** `tools/auditoria/preparacion_ronda.sh <N>`: se pasa antes de lanzar cada ronda (normas §9). La
  auditoría tiene una sección 6: rondas `en curso` que no pasan la puerta, y nivel de la especificación distinto del de
  la cabecera de normas §9 (fusiona los dos a la vez).
- **Fila de rechazo** del auditor, siempre `./tools/hooks/entregar.sh auditor-calidad "Rechazo <lote>: <motivo>" ...`
  (normas §8): fuera del nivel `bajo`, la auditoría marca los lotes con `MAX_RECHAZOS` rechazos o más que no estén `bloqueado`.
- **Despachador del nivel alto** `tools/despachador.sh` (y `tools/hooks/tests/claude_falso.sh` para sus pruebas): se
  copia. En `propiedad.tsv`, la línea `tools/despachador.sh	arquitecto-sistemas` (y en la ficha de arquitecto-sistemas);
  en `.gitignore`, `.parar` y `.despachador_logs/` (sin ellas no arranca). En nivel `alto`, fusiona normas §9 y las
  fichas de `coordinador` y `auditor-calidad`: las rondas ya no las encadena la ventana del coordinador, sino el
  despachador, que lanza la persona responsable desde su terminal (`README.md`, 6.6).
- **Reglas nuevas de órdenes**: `.parar` no se crea, borra ni mueve desde la terminal de una sesión; en las sesiones
  del despachador (`DESPACHADOR=1`) se bloquean `git push`, `pull`, `merge`, `rebase`, `switch`, `checkout -b` y crear o
  borrar ramas.
- **Cuota en USD**: en nivel `alto` la puerta exige `**Cuota:** <n> USD por ronda` en la cabecera del plan (entero o
  decimal); es el tope de gasto del despachador.
- **Contratos**: un lote con `contrato: <sistema>` en la columna Lote no pasa la puerta hasta que §3 de la
  especificación tiene su apartado `### Contrato: <sistema>` sin «POR ESCRIBIR».
- **Auditoría §4**: un lote `pendiente` que aún no aparece en el tablón ya no es hallazgo (en `alto` se planifican todas
  las rondas desde el principio).
- **Cambiar de nivel** en un proyecto ya desplegado (lo decide la persona responsable; lo hace `coordinador`): rellena a
  `/tmp` con el nivel nuevo en `valores.json` y fusiona normas §8 y §9, las fichas de `coordinador` y `auditor-calidad`,
  la línea 2 (**Ventana**) del plan, la línea del nivel de la especificación y la de `CLAUDE.md`. Después,
  `./tools/auditoria/auditoria_proceso.sh` sin hallazgos en la sección 6 y `preparacion_ronda.sh <N>` de la próxima ronda.

## 5. Avisos de la versión anterior (historia compartida, portabilidad y contexto)
- **Más órdenes bloqueadas**: `git commit --amend`, `git reset <commit>` y `--soft` (mueven la rama), `git checkout|restore`
  de carpetas o comodines, `git checkout|switch -f`, `export GIT_CONFIG_*`, `git config include.path` y escribir en
  `.git/config` (también con Edit). Las abreviaturas que git acepta (`--amen`, `--no-veri`, `reset --har`) cuentan igual:
  antes `--no-veri` y `--har` se colaban. Para corregir un commit, otro commit.
- **Memorias sin fila**: un commit que solo toca memorias de rol ya no necesita fila del tablón
  (`git commit -m "<rol>: memoria" -- docs/direccion/roles/memoria_<rol>.md`); commit-msg sigue exigiendo que sea la tuya.
- **Aviso de contexto**: `.claude_context_tokens` no lo escribía nadie y se quita (también de `.gitignore`). Ahora la
  línea de estado (`linea_estado.sh`, en `.claude/settings.json`) apunta el contexto de cada sesión y el hook
  `UserPromptSubmit` (`aviso_contexto.sh`) avisa al modelo; el hook `SessionStart` (`inicio_sesion.sh`) le recuerda su
  rol tras `/compact` o `/clear`. Al fusionar `.claude/settings.json` añade `statusLine`, `SessionStart` y
  `UserPromptSubmit`, y quita `MultiEdit` del matcher (ya no existe esa herramienta).
- **macOS y Windows**: las fechas ya no dependen de `date -d` (GNU) y los scripts exigen bash 4+ con un mensaje claro
  (macOS: `brew install bash`). Copia `.gitattributes`: sin él, un clon en Windows con `core.autocrlf` deja los scripts
  en CRLF y bash no los entiende. Si en algún equipo ya están en CRLF: con el árbol limpio y las sesiones paradas, la
  persona responsable los vuelve a sacar desde su terminal (`rm -rf tools && git checkout HEAD -- tools`).

## 6. Avisos de versiones anteriores (endurecimiento de candados, motor y tablón)
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

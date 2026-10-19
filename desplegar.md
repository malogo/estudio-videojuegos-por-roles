# Despliegue del sistema de trabajo (instrucciones para la sesión de chat)

Las sigue la sesión de Claude Code que la persona abre en la carpeta del proyecto tras pegar la frase de arranque
(`readme.txt`, sección 5). `<PLANTILLA>` es la carpeta donde está este archivo. Hasta el paso 9 la sesión no tiene
rol: es «la sesión de despliegue». No toques nada del proyecto antes del paso 4.

## 1. Comprobar el entorno (sin preguntar)
- `git --version`, `bash --version`, `python3 --version` (o `python --version` en Windows) y `ls -la` de la carpeta.
- En Windows hace falta Git Bash (los hooks son bash). Si falta algo, dilo y para.
- Si la carpeta ya es un repositorio: `git status` debe estar limpio; trabaja en una rama nueva (`git switch -c sistema-roles`).

## 2. Leer antes de preguntar
- `<PLANTILLA>/readme.txt` (secciones 1 a 4) y `<PLANTILLA>/cuestionario.md`. No hace falta leer `plantilla/` entera.

## 3. Hacer el cuestionario
- Un bloque cada vez (A, B, C, D, E, F), con el valor por defecto a la vista. Si la persona no sabe: defecto.
- Si el motor ya está en la carpeta, deduce lo que puedas (versión, carpetas) y pide solo confirmación.
- Escribe las respuestas en `valores.json` **fuera del proyecto** (p. ej. junto a la plantilla), con el formato de
  `<PLANTILLA>/ejemplo_valores_unity_pc.json`. Enséñaselo a la persona antes de seguir.

## 4. Rellenar la plantilla
```bash
python3 <PLANTILLA>/rellenar_plantilla.py --valores <ruta>/valores.json --destino .
```
- Copia `plantilla/` al proyecto, rellena los marcadores, crea fichas y memorias por rol, quita de `propiedad.tsv`
  los roles que no se usan y copia `extras/<motor>/` a `tools/hooks/` si `MOTOR_EXTRA` lo pide.
- Nunca sobrescribe: lo que «YA EXISTÍA» (p. ej. un `.gitignore` o un `CLAUDE.md` previos) se fusiona a mano.

## 5. Completar lo que el script no sabe
- Cada `{{COMPLETAR}}` que liste el script (fichas de roles extra) se rellena con las respuestas de C6, y sus rutas
  se añaden a `tools/hooks/propiedad.tsv` en la sección «Roles extra».
- Busca menciones a roles que no existen: `grep -rn "director-arte\|especialista-escenas-ui" CLAUDE.md docs .claude`
  y ajusta la prosa (p. ej. la línea de arte de normas §6 si no hay `director-arte`).
- Motor sin carpeta en `extras/`: si tiene metadatos que deben ir con cada archivo (como `.meta` o `.uid`), escribe
  `tools/hooks/pre-commit-motor.sh` copiando la forma de `extras/unity/pre-commit-motor.sh`. Si no, no hace falta.

## 6. Proyecto que ya existía
- Toda ruta del proyecto que no case con `propiedad.tsv` no tiene dueño y sus commits se rechazarán.
  Lista las carpetas actuales y asigna cada una a un rol en `propiedad.tsv` (pregunta a la persona si dudas).

## 7. Primer commit (antes de activar los hooks)
```bash
git init -b <RAMA_PRINCIPAL>          # solo si no era un repositorio
git add -- CLAUDE.md .gitignore .claude docs tools
git commit -m "coordinador: despliegue inicial del sistema de trabajo"
```
- Rutas explícitas, nunca `git add -A` ni `git add .` (si el hook ya está cargado, los bloquea igualmente).

## 8. Activar los hooks y fijar el rol
```bash
./tools/hooks/arranque_rol.sh coordinador
```
- Activa `core.hooksPath = tools/hooks` y declara el rol `coordinador` para esta sesión.

## 9. Primera fila del tablón y excepción de auditoría
```bash
echo "$(TZ=<ZONA_HORARIA> date '+%Y-%m-%d %H:%M') | coordinador | Despliegue inicial del sistema; primer lote A1 en el plan | docs/direccion/plan_nocturno.md | arquitecto-sistemas" >> docs/direccion/tablon.md
git commit -m "coordinador: primera fila del tablón" -- docs/direccion/tablon.md
```
El commit inicial toca archivos de todos los roles, así que la auditoría lo marcaría. Se exceptúa con el rol del auditor:
```bash
./tools/hooks/fijar_rol.sh auditor-calidad
printf '# Commits que la comprobación 2 no revisa (hash y motivo)\n%s despliegue inicial\n' "$(git rev-list --max-parents=0 HEAD)" > tools/auditoria/excepciones_proceso.txt
git add -- tools/auditoria/excepciones_proceso.txt
echo "$(TZ=<ZONA_HORARIA> date '+%Y-%m-%d %H:%M') | auditor-calidad | Excepción del commit de despliegue | tools/auditoria/excepciones_proceso.txt | coordinador" >> docs/direccion/tablon.md
git commit -m "auditor-calidad: excepción del despliegue" -- tools/auditoria/excepciones_proceso.txt docs/direccion/tablon.md
./tools/hooks/fijar_rol.sh coordinador
```
(Proyecto que ya existía: añade también al archivo de excepciones los commits anteriores de las últimas 24 h.)

## 10. Comprobación final (todo debe salir bien)
```bash
./tools/hooks/tests/prueba_guardas.sh        # «Resultado: N/N pruebas OK»
./tools/auditoria/auditoria_proceso.sh       # «0 hallazgo(s)» (crea docs/calidad/auditoria_proceso_<fecha>.md)
grep -rn "{{" CLAUDE.md docs tools .claude   # sin resultados
git status --short                           # limpio salvo el informe de auditoría
```
- El informe de auditoría lo commitea `auditor-calidad` en su primera sesión (o bórralo).
- Si algo falla, arréglalo antes de seguir; no desactives ningún hook.

## 11. Cierre
- Explica a la persona, en pocas líneas: qué se creó, el resultado de la comprobación y qué hacer ahora.
- **Hay que cerrar esta sesión y abrir otra**: Claude Code carga `CLAUDE.md` y los hooks de `.claude/settings.json`
  al arrancar. La primera sesión nueva es la del coordinador (`readme.txt`, sección 6).
- Si hay remoto (GitHub…), sube la rama solo si la persona lo pide.

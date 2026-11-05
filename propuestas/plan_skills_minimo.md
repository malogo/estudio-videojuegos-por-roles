# Plan: captura y skills de motor (versión mínima)

Fecha: 2026-10-28 · Base: `main` en `803eb07` · Estado: **aprobado** por la persona responsable el 2026-11-05, con
D1 y D2 como se proponían (§6).
Sustituye a la versión larga (`plan_skills.md`, 725 líneas, fuera del repo): de ella se queda la idea (el oficio del
motor que no está en fichas ni normas) y se quita el andamiaje (§5 dice qué y por qué).

**Frase de arranque para una sesión nueva** (esfuerzo recomendado: alto):

> Lee `propuestas/plan_skills_minimo.md` y haz el paso 2 (§3). Rama nueva desde `main`, un commit por apartado y CI
> verde. Prueba la captura a mano en `C:\Users\34618\Proyectos\PruebaPlantilla` antes de dar el paso por hecho. El
> paso 3 no se empieza sin su disparador (§4).

---

## 0. Resumen

| Paso | Qué | Cuándo |
|---|---|---|
| 1 | Una ronda real cerrada en PruebaPlantilla | Requisito: queda fuera de este plan |
| 2 | Herramienta de captura para Godot (`captura.sh` + `captura.gd`) | Ya: es un hueco conocido y no depende del paso 1 |
| 3 | Skills de motor: la tubería y el primer skill | Solo cuando el paso 1 o las rondas siguientes dejen un fallo de motor que se repite |

- La captura es una **herramienta**, no un skill: normas §8 la exige y hoy nada la saca.
- Los skills entran **por fallos vistos**, de uno en uno y sin infraestructura de propiedad, guardas ni medición.
- Unity, cuando se despliegue un proyecto Unity (mismos nombres y otro contenido en `extras/unity/`).

---

## 1. Por qué la versión mínima

- **No hay datos.** A 2026-10-28, PruebaPlantilla tiene 9 commits, 0 `Validado` y 0 `Rechazo`. A1 se cortó por la
  infraestructura (un Godot colgado retuvo el candado `motor`), no por no saber hacer el lote. Los «`.tscn` rotos» y
  los «`.meta` perdidos» que justificaban la versión larga todavía no se han visto.
- **Leer un skill no es peligroso.** Un skill es texto: lo que un rol no puede hacer ya lo paran las guardas de
  edición, git y motor. Y `Read` no tiene guarda (`settings.json` solo tiene matchers para `Bash|PowerShell` y
  `Edit|Write|NotebookEdit`), así que una guarda sobre `Skill` se esquivaría leyendo el `SKILL.md`.
- **La captura sí falta ya.** Normas §8, la ficha de `especialista-escenas-ui` y la de `auditor-calidad` la piden;
  `plan_nocturno.md` solo avisa de que no sirve `--headless`. Cualquier lote de escena en nivel alto depende de ella.

---

## 2. Requisito previo (paso 1, fuera de este plan)

La ronda 1 de PruebaPlantilla cerrada por `auditor-calidad` en nivel alto, con al menos un `Validado`. Lo que salga de
esa ronda es la materia prima del paso 3: filas `Rechazo`, «Descartado» de las memorias (§2), motivos de `bloqueado`
en `pendientes_manana.md` y los logs de `.despachador_logs/` y `.motor_logs/`.

---

## 3. Paso 2: herramienta de captura (Godot)

### 3.1 Piezas

**`extras/godot/captura.sh`** → `tools/hooks/captura.sh` (dueño `arquitecto-sistemas` por `tools/hooks/**`, como
`nuevo_uid.sh`).

- Uso: `./tools/hooks/captura.sh <rol> <res://escena.tscn> <nombre>`.
- Borra `.motor_logs/capturas/<rol>_<nombre>.png` si existe (si no, una imagen vieja daría por buena una captura que
  no se hizo).
- Lanza `./tools/motor_silencioso.sh <rol> --script <captura.gd> -- <escena> <png>`, sin `--headless`. Así hereda el
  candado `motor`, el silencio, `MOTOR_TIEMPO_MAX` y el resumen de errores, sin duplicar nada.
- Sale con el código de `motor_silencioso.sh`, o con 1 si el motor salió con 0 pero no hay PNG o está vacío. Si todo
  va bien, escribe la ruta del PNG (las imágenes se miran con `Read`).
- Las capturas van a `.motor_logs/capturas/`: ya está en `.gitignore`, no tiene dueño que asignar y Godot no importa
  las carpetas que empiezan por punto.

**`extras/godot/captura.gd`** → `tools/hooks/captura.gd`.

- `extends SceneTree`. Lee la escena y la ruta del PNG de `OS.get_cmdline_user_args()`.
- Carga e instancia la escena bajo `root`, espera a que se dibuje (unos fotogramas y `RenderingServer.frame_post_draw`)
  y guarda `root.get_texture().get_image()` con `save_png`.
- `quit(0)` si guardó; `quit(1)` con un mensaje claro si no carga la escena o no puede guardar.

### 3.2 Por verificar al empezar (Godot 4.7.2 en Windows, en PruebaPlantilla)

1. **Si Godot crea `captura.gd.uid` en `tools/hooks/`.** Sería un archivo de `arquitecto-sistemas` que aparece en la
   sesión de otro rol (y `motor_silencioso.sh` lo listaría como ajeno). Si lo crea, se elige una de estas dos:
   - `plantilla/tools/.gdignore` y el script por ruta absoluta. Es la preferida: además, Godot deja de escanear
     `tools/`. Hay que comprobar que `--script` carga un `.gd` dentro de una carpeta ignorada.
   - El despliegue deja el `.uid` hecho, con el mismo formato que `nuevo_uid.sh`.
2. **Cuántos fotogramas hacen falta** para que la imagen no salga negra o a medio dibujar.
3. **Que una escena que falla al cargar** sale con código distinto de 0 y su error aparece en el resumen.

### 3.3 Textos que cambian

- **`normas_comunes.md` §8**, tras la línea de la captura y dentro de `{{#SI MOTOR_EXTRA=godot}}`: una línea con la
  orden y dónde queda la imagen.
- **`plan_nocturno.md:25`** (bloque de Godot): «Las capturas, con `./tools/hooks/captura.sh`».
- **Ficha de `especialista-escenas-ui`, línea 17**: «captura de validación en el commit» cambia según la decisión D1.
- **`README.md` §4**: una fila en la tabla de `tools/hooks/`, junto a `nuevo_uid.sh` (*solo Godot*).
- **`rellenar_plantilla.py:13`** (docstring): añadir `captura.sh` y `captura.gd` al ejemplo de lo que se copia.

### 3.4 Pruebas

- **`prueba_guardas.sh`**, con `motor_falso.sh`:
  - sin argumentos, sale con error de uso;
  - el motor sale con 0 y no deja PNG → 1;
  - el motor deja el PNG (`MOTOR_FALSO_CREA`) → 0 y escribe su ruta;
  - un PNG viejo no da por buena una captura nueva.
- **CI**: tras desplegar Godot, existen `tools/hooks/captura.sh` y `captura.gd`; tras desplegar Unity, no.
- **A mano** en PruebaPlantilla: una escena real, el PNG se abre con `Read` y se ve la escena. El CI no tiene pantalla
  ni Godot, así que esta prueba no la sustituye nada.

**Hecho cuando:** CI en verde en Linux, macOS y Windows, y una captura real en PruebaPlantilla que se ve bien.

---

## 4. Paso 3: skills de motor (solo con disparador)

### 4.1 Disparador

Un fallo de motor que **se repite** (dos veces o más en rechazos, en memorias o en `bloqueado`) y que una regla escrita
habría evitado: un `.tscn` editado a mano que no carga, un `.uid` que no se commitea, un import mal hecho... Sin eso,
no se escribe ninguno.

### 4.2 Tubería (una vez, con el primer skill)

1. **`rellenar_plantilla.py`**, bucle de extras (línea 181): una carpeta `skills/` en `extras/<motor>/` se recorre y se
   copia a `.claude/skills/` con los mismos `aplicar_bloques` y `rellenar_texto`; cualquier otra carpeta da un error
   claro. Hoy una carpeta ahí rompe el despliegue (`open` de una carpeta).
2. **`despachador.sh:102`**: en `PERMITIDAS`, un `Skill(<nombre>)` por cada carpeta de `.claude/skills/`, generado al
   arrancar. No vale `Skill` a secas: en `--permission-mode dontAsk` se deniega lo que no está permitido, y con la
   lista explícita los skills de usuario y de plugins quedan fuera de las sesiones desatendidas sin guarda nueva (D2).
3. **CI**: tras desplegar Godot existe `.claude/skills/<nombre>/SKILL.md`; tras desplegar Unity, no.
4. **`README.md`**: §4, `.claude/skills/` en el mapa; §8, «un skill se carga si el modelo lo decide (o con
   `/nombre`): lo que tiene que pasar siempre va en normas y guardas».

**Propiedad: nada nuevo.** `.claude/**` ya es de `arquitecto-sistemas` en `propiedad.tsv`, las mejoras se le piden por
tablón (normas §2) y `actualizar.md` ya dice «fusionar a mano» para `.claude/`.

**Por verificar** en una sesión real del despachador: que `Skill(<nombre>)` en `--allowedTools` permite ese skill y
deniega los demás.

### 4.3 Cómo es cada skill

- **Nombre neutro y contenido del motor** (`motor-escenas`, no `godot-escenas`): el mismo nombre sirve el día que
  haya `extras/unity/skills/`, y una ficha o un encargo pueden nombrarlo sin saber el motor.
- **Primer candidato, si el disparador lo confirma:** `motor-escenas` (Godot), con
  `paths: "**/*.tscn, **/*.tres, project.godot"`:
  - formato de `.tscn` y `.tres` para editar a mano sin romper (cabecera, `ext_resource`/`sub_resource` con `id`,
    `parent`);
  - `.uid` e `.import` siempre con su archivo;
  - cuándo no editar a mano e importar con `--headless --import`, y `nuevo_uid.sh` cuando no hay motor;
  - comprobado contra la documentación oficial de Godot 4.7.
- **Reglas:**
  - cuerpo ≤ 150 líneas y descripción ≤ 400 caracteres, con lo esencial al principio;
  - no repite normas: remite por número («ver normas §4»), y si las contradice, mandan las normas;
  - escrito a partir de los fallos vistos, no de lo que podría fallar.
- **Subagentes:** siguen sin la herramienta `Skill`. Solo si el fallo lo comete un ejecutor, se le precarga ese skill
  con `skills:` en su frontmatter (dentro de `{{#SI MOTOR_EXTRA=godot}}`).

### 4.4 Prueba y permanencia

- **Activación:** una sesión del rol con una tarea típica sin nombrar el skill, y otra del despachador. Si no se carga,
  se ajusta la descripción.
- **Se queda** si el fallo que lo motivó no vuelve en las rondas siguientes. Si no se carga nunca, o el fallo sigue
  aunque se cargue, se reescribe o se quita. Sin línea base ni estadística: con tan pocos lotes serían ruido.

---

## 5. Qué se descarta de la versión larga

| Pieza | Por qué fuera |
|---|---|
| `guard_skill.sh`, prefijos de dueño, «Solo para», filas nuevas en `propiedad.tsv` | Cargar un skill es leer texto; los efectos ya los paran las guardas, y `Read` esquivaría la guarda. |
| Registro de uso y medición (≥ 3 y ≥ 10 lotes, línea base, un skill cada vez) | Sin lotes no hay cifras; la propia versión larga admitía que serían ruido. |
| `comun-vaciar-memoria` | Repite normas §7, que ya se carga siempre. |
| Skills de coordinador y auditor (lotes, revisión, ronda, especificación, contrato) | Ningún fallo los pide. La forma de los veredictos ya la fijan normas §8-§9 y el encargo del despachador. |
| `director-arte-producir-pieza` | Depende de una decisión sin tomar: con qué se produce el arte. |
| `validar_skills.py`, pregunta nueva del cuestionario, rechazo de prefijos ambiguos, binarios en extras, `arranque_rol.sh` listando skills | Preparan casos que hoy no existen. |
| `motor-*-captura` como skill | Pasa a herramienta (paso 2): es una orden, no un oficio. |

Si algún día hacen falta, la versión larga sigue siendo una buena referencia para recuperarlas.

---

## 6. Decisiones (para la persona responsable)

- **D1. ¿Se commitean las capturas?** Propuesta: **no**. Van a `.motor_logs/capturas/` (ignorado) y el auditor saca la
  suya, como ya dice su ficha. La línea 17 de la ficha de escenas-ui pasa a «ruta de la escena; la captura la saca
  también el auditor». Alternativa: una carpeta versionada por rol, que obliga a darle dueño en `propiedad.tsv` y
  engorda el repo con PNG. → **Aprobado: no** (2026-11-05).
- **D2. ¿Skills de usuario y de plugins en el despachador?** Propuesta: **no**, con la lista explícita de §4.2. Un skill
  pensado para una persona delante (por ejemplo, uno que hace preguntas antes de empezar) gasta un lote entero en una
  sesión desatendida. En sesiones interactivas los decide la persona y no se tocan. → **Aprobado: no**, solo los del
  proyecto (2026-11-05).

---

## 7. Archivos que toca

```text
Paso 2 (captura)
extras/godot/captura.sh                            (nuevo)  §3.1
extras/godot/captura.gd                            (nuevo)  §3.1
plantilla/tools/.gdignore                          (quizá)  §3.2
plantilla/docs/direccion/normas_comunes.md                  §3.3
plantilla/docs/direccion/plan_nocturno.md                   §3.3
plantilla/docs/direccion/roles/especialista-escenas-ui.md   §3.3 (según D1)
plantilla/tools/hooks/tests/prueba_guardas.sh               §3.4
.github/workflows/prueba_plantilla.yml                      §3.4
README.md, rellenar_plantilla.py (docstring)                §3.3

Paso 3 (skills, solo con disparador)
rellenar_plantilla.py                                       §4.2
plantilla/tools/despachador.sh                              §4.2
.github/workflows/prueba_plantilla.yml                      §4.2
README.md                                                   §4.2
extras/godot/skills/<nombre>/SKILL.md              (nuevo)  §4.3
```

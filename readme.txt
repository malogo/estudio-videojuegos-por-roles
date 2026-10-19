SISTEMA DE TRABAJO POR ROLES CON SESIONES DE CLAUDE CODE
Plantilla para montarlo en cualquier proyecto de videojuego
(PC, móvil, consola o web; Godot, Unity, Unreal u otro motor)
===============================================================


1. QUÉ ES
---------
Es una forma de organizar a varias sesiones de chat de Claude Code (una "sesión" es una
ventana de conversación con Claude trabajando sobre la carpeta del proyecto) para que
trabajen en el mismo juego sin pisarse, sin olvidar lo hecho y sin que nada llegue a la
persona responsable sin revisar.

La idea es la de un pequeño estudio:
- Cada sesión tiene UN ROL fijo, como un puesto de trabajo: coordinador, arquitecto de
  sistemas, especialista de escenas e interfaz, director de arte, auditor de calidad... y
  los que haga falta añadir (sonido, backend, red...).
- Cada archivo del proyecto tiene UN SOLO DUEÑO. Solo su rol puede cambiarlo. Si otro rol
  necesita un cambio, se lo pide.
- Los roles se comunican por un TABLÓN: un archivo de texto donde cada uno apunta, en una
  línea con fecha y hora, qué ha entregado y a quién va dirigido. Nunca se borra nada.
- La persona responsable decide el alcance, las normas nuevas, las compras y la
  publicación. Las sesiones nunca deciden eso por su cuenta: lo dejan apuntado.


2. POR QUÉ FUNCIONA
-------------------
- Propiedad de archivos FORZADA, no solo escrita: unos "hooks" (pequeños programas que se
  ejecutan solos antes de cada acción) impiden que una sesión edite o guarde archivos que
  no son de su rol, o que use órdenes peligrosas para un proyecto compartido (por ejemplo
  "git add -A", que mete en el mismo paquete el trabajo a medias de todos).
- Tablón append-only: como solo se añaden líneas, no hay conflictos ni se pierde historia.
  Cada rol lee solo las líneas dirigidas a él.
- Memoria por rol: las sesiones de chat se llenan y hay que "vaciarlas" (empezar de cero).
  Antes de vaciarse, cada rol escribe en su archivo de memoria qué decidió, qué descartó y
  dónde se quedó. La sesión nueva lo lee y sigue sin perder el hilo.
- Coordinador: un rol que no programa. Reparte el trabajo en lotes pequeños, planifica las
  rondas y apunta las dudas para la persona responsable.
- Rondas (plan nocturno): el coordinador deja escrito qué lotes se hacen, en qué orden y
  cómo se comprueba cada uno. Así varias sesiones pueden trabajar solas (de noche, por
  ejemplo) sin inventar nada.
- Subagentes baratos: para tareas acotadas, la sesión principal encarga el trabajo a un
  "subagente" con un modelo más pequeño y barato, siempre con una ficha de encargo
  completa (qué archivos, qué cambio, cómo se comprueba). Luego valida el resultado.
- Auditor de calidad: nada llega a la persona responsable sin que el auditor lo pruebe.
  Además revisa el propio proceso (que el tablón esté bien escrito, que nadie haya tocado
  archivos ajenos, que no haya candados olvidados...).
- Motor sin sonido y con candado: el motor del juego solo se abre en modo silencioso y de
  uno en uno (un "candado" impide que dos sesiones lo usen a la vez y estropeen la caché).
- Sesiones en la nube: también se puede encargar trabajo a sesiones de Claude Code en la
  web. Trabajan en su propia rama, abren una propuesta de cambio (PR) y dejan su línea del
  tablón en un archivo aparte; al aceptarla, el coordinador la pasa al tablón.


3. LAS PIEZAS, EN UNA LÍNEA CADA UNA
------------------------------------
Rol .............. puesto fijo de una sesión (coordinador, arquitecto-sistemas, ...).
Ficha de rol ..... qué archivos son suyos, qué hace, qué no hace y a quién entrega.
Tablón ........... lista de entregas y avisos entre roles, con fecha y hora.
Memoria .......... resumen que cada rol deja antes de vaciar su sesión.
Plan nocturno .... lista de lotes de la ronda, con su comprobación y su estado.
Pendientes ....... preguntas que esperan decisión de la persona responsable.
Lote ............. trabajo pequeño y comprobable que se encarga a un rol.
Encargo .......... ficha para mandar un lote a un subagente.
Hooks ............ guardas automáticas que bloquean lo prohibido.
Candado .......... impide que dos sesiones usen el motor o hagan una build a la vez.


4. MAPA DE CARPETAS (lo que crea el despliegue en el proyecto)
--------------------------------------------------------------
CLAUDE.md                          Lo primero que lee cada sesión: cómo arrancar con su rol.
.gitignore                         Archivos que nunca se guardan (cachés del motor, candados).
.claude/settings.json              Activa los hooks y prohíbe los subagentes genéricos.
.claude/agents/                    Los 3 subagentes del proyecto:
   agente-ejecutor-lote.md            código que exige pensar (modelo medio).
   agente-ejecutor-mecanico.md        cambios repetitivos con un patrón (modelo medio).
   agente-buscador-lectura.md         buscar y resumir, sin tocar nada (modelo pequeño).
docs/direccion/
   normas_comunes.md               Las normas de todos, en 11 apartados cortos.
   especificaciones.md             Qué es el juego (lo escribe el coordinador con la persona).
   tablon.md                       El tablón.
   plan_nocturno.md                Los lotes de la ronda.
   pendientes_manana.md            Las dudas para la persona responsable.
   entregas_nube/                  Líneas del tablón que dejan las sesiones en la nube.
   roles/<rol>.md                  Una ficha por rol.
   roles/memoria_<rol>.md          Una memoria por rol.
   roles/plantilla_encargo.md      Ficha de encargo a subagentes.
   roles/plantilla_memoria.md      Formato de las memorias.
tools/hooks/                       Las guardas:
   arranque_rol.sh                 Orden de arranque de cada sesión (fija el rol y enseña lo suyo).
   fijar_rol.sh                    Cambia el rol declarado (lo usan los subagentes).
   propiedad.tsv                   LA TABLA de qué carpeta es de qué rol.
   propiedad.sh                    Lee esa tabla; aquí está la lista de roles válidos.
   pre_tool_guard.sh               Bloquea órdenes prohibidas antes de ejecutarlas.
   guard_propiedad.sh              Bloquea editar archivos de otro rol.
   reglas_comando.sh               Las reglas de órdenes prohibidas (git y motor).
   pre-commit                      Al guardar: exige la línea del tablón y que tenga hora real.
   commit-msg                      Al guardar: exige "<rol>: ..." y que todo sea de ese rol.
   pre-commit-motor.sh             (opcional) comprobaciones propias del motor.
   volcar_entregas_nube.sh         Pasa al tablón las líneas de la nube.
   git_guard.sh, leer_json.sh      Piezas auxiliares.
   tests/prueba_guardas.sh         Prueba rápida de que todas las guardas funcionan.
tools/locks/with_lock.sh           Los candados.
tools/motor_silencioso.sh          ÚNICA forma de abrir el motor: sin sonido y con candado.
tools/auditoria/auditoria_proceso.sh  Revisión del proceso que hace el auditor.


5. CÓMO SE DESPLIEGA (desde UNA sesión de chat)
-----------------------------------------------
1. Copia esta carpeta (estructura_proyectos) a un sitio fijo de tu ordenador.
2. Abre Claude Code en la carpeta del juego (vacía o con el proyecto ya empezado).
3. Pega esta frase de arranque, cambiando la ruta por la tuya:

   Despliega aquí el sistema de trabajo por roles. La plantilla está en RUTA/estructura_proyectos: lee su desplegar.md y síguelo paso a paso. Empieza por las preguntas de cuestionario.md, de bloque en bloque, y no toques nada del proyecto hasta tener mis respuestas.

4. Contesta las preguntas (cada una trae un valor por defecto; si dudas, acéptalo).
5. La sesión rellena la plantilla, crea los archivos, activa los hooks, escribe la primera
   línea del tablón y comprueba que todo funciona. Al terminar te dice el resultado.
6. Cierra esa sesión. Desde ahora cada sesión nueva tiene un rol (sección 6).

Requisitos: git, bash (en Windows, Git Bash) y Python 3.


6. USO DIARIO
-------------
Abrir un rol:
  Abre una sesión nueva y escribe, por ejemplo: "Eres coordinador". La sesión ejecuta
  ./tools/hooks/arranque_rol.sh coordinador, que le enseña su ficha, su memoria y solo
  sus líneas nuevas del tablón. Una sesión = un rol; no cambies de rol a mitad.
Empezar: abre primero el coordinador, cuéntale qué quieres y pídele que escriba la
  especificación y el primer plan.
Despertar a otro rol:
  El rol que entrega añade su línea al tablón dirigida al otro. Tú abres (o vuelves a) la
  sesión de ese rol y le dices: "Tienes trabajo en el tablón".
Lanzar una ronda:
  Pide al coordinador "lanza la ronda N". Él marca los lotes en el plan y te dice qué
  sesiones abrir y con qué frase. No abras más sesiones a la vez que las que diga el plan.
Vaciar una sesión (cuando avisa de que está llena, ~250.000 "tokens"):
  Dile "vuelca tu memoria y prepárate para vaciar". Escribe su memoria y la guarda. Luego
  cierras la sesión y abres otra con el mismo rol. El coordinador nunca se vacía solo: te
  avisa y lo vacías tú.
Decisiones:
  Revisa de vez en cuando docs/direccion/pendientes_manana.md y responde a las preguntas.
Trabajar con la nube:
  Pide al coordinador el encargo para la nube; pégalo en una sesión de Claude Code en la
  web con el repositorio conectado. Al terminar abre un PR. Lo revisas y lo aceptas
  (merge); luego dile al coordinador "vuelca las entregas de la nube" y pégale el informe
  del PR (la nube no puede escribir a tus otras sesiones).


7. QUÉ CAMBIA SEGÚN PLATAFORMA Y MOTOR, Y QUÉ ES COMÚN
------------------------------------------------------
Común a todos (no se toca): roles, tablón, memorias, plan, pendientes, encargos,
subagentes, propiedad forzada, reglas de git, candados, auditoría de proceso y nube.

Cambia según el motor (lo pregunta el cuestionario):
- Cómo se llama el programa del motor y con qué opciones va sin sonido ni ventana:
    Godot:  godot --audio-driver Dummy --headless
    Unity:  Unity -batchmode -nographics -projectPath <carpeta>
    Unreal: UnrealEditor-Cmd <proyecto>.uproject -nosound -unattended -nullrhi
- Qué carpetas son de cada rol y qué archivos genera el motor (que no se guardan).
- Metadatos que deben ir siempre con su archivo: Godot (.import, .uid), Unity (.meta).
  Hay comprobaciones listas en extras/godot y extras/unity; para otros motores se escribe
  una parecida si hace falta.
- Cómo se pasan los tests sin ventana.

Cambia según la plataforma:
- Móvil: candado de build (Android/iOS), firma de builds fuera del repositorio.
- Consola: el kit de desarrollo y su documentación (con acuerdo de confidencialidad) nunca
  entran en el repositorio ni en sesiones en la nube.
- Web: suele no haber motor que vigilar (se deja el patrón del motor vacío).
- PC: builds por sistema operativo, cada una con su candado si comparten carpeta.


8. LÍMITES CONOCIDOS
--------------------
- Las guardas son scripts de bash: en Windows hace falta Git Bash.
- La guarda de edición no ve lo que se escribe con órdenes de terminal (copiar, redirigir);
  eso lo para el hook commit-msg al guardar.
- El rol lo declara la propia sesión: el sistema evita despistes, no engaños deliberados.
- La batería completa de pruebas de las guardas del proyecto original no se trae: era
  específica de aquel proyecto. Se incluye tools/hooks/tests/prueba_guardas.sh, más corta.
- En Unreal conviene Git LFS para los .uasset; la plantilla no lo configura sola.


9. QUÉ HAY EN ESTA CARPETA
--------------------------
readme.txt                     Este archivo.
cuestionario.md                Las preguntas del despliegue, con opciones y valor por defecto.
desplegar.md                   Los pasos que sigue la sesión de despliegue.
rellenar_plantilla.py          Copia la plantilla al proyecto y rellena los huecos {{ASI}}.
ejemplo_valores_unity_pc.json  Ejemplo de respuestas (Unity, PC) en el formato que usa el script.
plantilla/                     Todos los archivos genéricos, con huecos {{ASI}}.
extras/godot, extras/unity     Comprobaciones propias de cada motor.

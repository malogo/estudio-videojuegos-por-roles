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
  El candado dura lo que dure el motor, aunque la sesión que lo lanzó se corte a medias.
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
.gitignore                         Archivos que nunca se guardan (cachés y logs del motor, candados).
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
   archivo/                        Líneas viejas del tablón, archivadas por el coordinador.
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
   entregar.sh                     Entrega en una orden: línea del tablón con hora real + guardado.
   pre-commit                      Al guardar: exige la línea del tablón y que tenga hora real.
   commit-msg                      Al guardar: exige "<rol>: ..." y que todo sea de ese rol (también
                                   las líneas del tablón: nadie guarda la línea de otro).
   pre-commit-motor.sh             (opcional) comprobaciones propias del motor.
   volcar_entregas_nube.sh         Pasa al tablón las líneas de la nube.
   archivar_tablon.sh              El coordinador archiva las líneas viejas del tablón (ya leídas por todos).
   git_guard.sh, leer_json.sh      Piezas auxiliares.
   tests/prueba_guardas.sh         Prueba rápida de que todas las guardas funcionan.
   tests/motor_falso.sh            Motor de mentira para esas pruebas (no hace falta el real).
tools/locks/with_lock.sh           Los candados.
tools/motor_silencioso.sh          ÚNICA forma de abrir el motor: sin sonido y con candado. Guarda la
                                   salida en .motor_logs/ y da un resumen corto con los errores y los
                                   archivos que el motor ha creado o cambiado (por dueño).
tools/auditoria/auditoria_proceso.sh  Revisión del proceso que hace el auditor.
tools/auditoria/ruido_motor.txt    Errores del motor que el auditor ha dado por benignos.


5. CÓMO SE DESPLIEGA (desde UNA sesión de chat)
-----------------------------------------------
1. Copia esta carpeta (estructura_proyectos) a un sitio fijo de tu ordenador.
2. Abre Claude Code en la carpeta del juego (vacía o con el proyecto ya empezado).
3. Pega esta frase de arranque, cambiando la ruta por la tuya:

   Despliega aquí el sistema de trabajo por roles. La plantilla está en RUTA/estructura_proyectos: lee su desplegar.md y síguelo paso a paso. Empieza por las preguntas de cuestionario.md, de bloque en bloque, y no toques nada del proyecto hasta tener mis respuestas.

4. Contesta las preguntas (cada una trae un valor por defecto; si dudas, acéptalo).
5. La sesión rellena la plantilla, crea los archivos, activa los hooks, escribe la primera
   línea del tablón y comprueba que todo funciona. Al terminar te dice el resultado.
6. Cierra esa sesión: Claude Code solo carga CLAUDE.md y los hooks al abrir una sesión.
   Desde ahora cada ventana tiene un rol fijo (sección 6).

Requisitos: git, bash (en Windows, Git Bash) y Python 3.


6. CÓMO SE TRABAJA EN EL DÍA A DÍA
---------------------------------
Lo más cómodo es la aplicación de escritorio de Claude (pestaña Code): ahí varias sesiones
del mismo ordenador pueden mandarse mensajes, y el coordinador despierta a los demás sin que
tú copies nada. En una terminal funciona igual, pero los avisos los escribes tú.

6.1 Una ventana fija por rol
  - Abre UNA sesión por rol, todas en la carpeta del juego, y ponle de nombre su rol
    (Coordinador, Arquitecto sistemas, Auditor calidad...). Esas ventanas no se cierran:
    se reutilizan durante todo el proyecto. Una ventana = un rol; nunca cambia de rol.
  - La primera vez escribe en cada una:
        Eres <rol>. Lee tu ficha y no hagas nada más.
    La sesión ejecuta ./tools/hooks/arranque_rol.sh <rol>, lee su ficha, su memoria y sus
    líneas del tablón, y se queda esperando.
  - Elige en cada ventana el modelo y el esfuerzo (la app los deja fijar por sesión). Los
    especialistas casi siempre van bien con esfuerzo medio o alto; el coordinador, alto.
  - Abre primero el coordinador, cuéntale qué juego quieres y pídele la especificación y
    el primer plan. Las demás ventanas pueden esperar hasta que les toque.

6.2 El ciclo de un lote (lo que pasa cada vez)
  1. Pides al coordinador: "lanza la ronda N" (o "encarga X a <rol>").
  2. El coordinador escribe la línea en el tablón dirigida a ese rol (con entregar.sh) y le manda a su
     ventana el aviso "Tienes trabajo en el tablón". (Si la ventana se limpió antes, ver
     6.3: el aviso debe llevar también el rol.) En la terminal, ese aviso lo pegas tú.
     La primera vez, la app puede pedirte en la ventana de destino que aceptes el mensaje.
  3. El especialista trabaja: hace el lote, pasa sus pruebas y lo entrega con una sola
     orden (./tools/hooks/entregar.sh): guarda (commit) solo sus archivos junto con su línea
     del tablón, con la hora real, dirigida al siguiente (auditor o coordinador). Nadie
     escribe el tablón a mano, así una sesión nunca se lleva la línea de otra.
  4. Si la entrega va al auditor, el coordinador lo despierta igual; el auditor prueba y
     acepta o devuelve el lote al dueño. Nada te llega sin pasar por él.
  5. Al acabar, el especialista actualiza su memoria (qué hizo, qué descartó, dónde se
     queda) y la guarda. Avisas al coordinador ("ya acabó X") y él revisa, actualiza el
     plan y te dice qué sigue.
  6. Limpias la ventana del especialista (6.3) y queda lista para el próximo lote.

6.3 Limpiar una ventana: /clear
  - Cuando un especialista termina su lote y ha guardado su memoria, escribe /clear en su
    ventana. La conversación se vacía, pero la ventana conserva su nombre, carpeta, modelo
    y permisos. Así cada lote empieza con poco contexto: va más rápido y gasta menos.
  - Tras un /clear la sesión ya no sabe qué rol es. El siguiente aviso tiene que decirlo:
        Eres <rol>. Tienes trabajo en el tablón.
    Con eso vuelve a arrancar su rol, lee su memoria y solo las líneas nuevas del tablón.
    Dile al coordinador cuándo has limpiado una ventana, para que mande el aviso completo.
  - No hagas /clear mientras le está llegando un mensaje a esa ventana: el mensaje se pierde
    y hay que reenviarlo.
  - Si vienen varios lotes seguidos del mismo tema, puedes no limpiar entre ellos: no
    vuelve a leerlo todo, a cambio de que el contexto crezca.
  - Si una ventana se llena a mitad de un lote (~250.000 "tokens"), dile "vuelca tu memoria
    y prepárate para vaciar"; cuando la haya guardado, /clear y el aviso con el rol.

6.4 El coordinador es la excepción
  - Es la ventana larga: lleva el hilo de todo y habla contigo. Nunca se limpia solo; te
    avisa cuando conviene y mantiene al día su memoria (memoria_coordinador.md).
  - Cuando se alargue, mejor /compact (resume la conversación y sigue) que /clear. Si un día
    lo limpias, pídele antes que actualice su memoria y luego escribe "Eres coordinador".
  - Es quien decide qué ventana despertar y cuándo; tú solo le dices qué quieres y
    contestas sus preguntas.

6.5 Lo que haces tú y lo que hace el coordinador
  Tú: pides rondas o tareas, contestas pendientes_manana.md, limpias ventanas con /clear,
      eliges modelo y esfuerzo, aceptas avisos de la app y decides cada merge y cada compra.
  Coordinador: reparte lotes en el tablón, despierta roles, revisa entregas y PR, pasa la
      auditoría, actualiza plan, pendientes y su memoria, y sube los cambios cuando lo pides.
  Especialistas: hacen su lote, solo en sus archivos, y lo entregan por el tablón.

6.6 Rondas
  Pide al coordinador "lanza la ronda N". Él marca los lotes en el plan y despierta solo las
  ventanas que tocan, sin poner a dos roles sobre los mismos archivos. Las rondas solo se
  lanzan cuando tú lo pides; mientras tanto, las ventanas esperan.

6.7 Decisiones
  Lo que no está en la especificación (alcance, normas nuevas, compras, publicación) nunca
  lo decide una sesión: va a docs/direccion/pendientes_manana.md con una recomendación.
  Revísalo de vez en cuando y contesta allí o al coordinador.

6.8 Sesión en la nube (opcional)
  - Una sesión de Claude Code en la web, con el repositorio conectado, trabaja en su propia
    rama y abre un PR. Se usa para lotes largos que no necesitan tu ordenador.
  - Mantén una sola ventana de nube y límpiala con /clear entre lotes. Por eso cada encargo
    que le llega va completo (rol, normas y criterio de hecho): no recuerda nada.
  - Antes de enviar, el coordinador te dice el esfuerzo recomendado; tú lo fijas en la
    sesión y le confirmas. Si la app tiene Remote Control activo, el coordinador le envía el
    encargo directamente; si no, te lo da y lo pegas tú.
  - La nube no puede escribir a tus otras ventanas: cuando acaba, pega su informe al
    coordinador. Él revisa el PR y, solo si se lo pides, lo fusiona y pasa al tablón la
    línea que dejó la nube (volcar_entregas_nube.sh).


7. QUÉ CAMBIA SEGÚN PLATAFORMA Y MOTOR, Y QUÉ ES COMÚN
------------------------------------------------------
Común a todos (no se toca): roles, tablón, memorias, plan, pendientes, encargos,
subagentes, propiedad forzada, reglas de git, candados, auditoría de proceso y nube.

Cambia según el motor (lo pregunta el cuestionario):
- Cómo se llama el programa del motor y con qué opciones va sin sonido ni ventana:
    Godot:  godot --audio-driver Dummy --headless
    Unity:  Unity -batchmode -nographics -logFile - -projectPath <carpeta>
    Unreal: UnrealEditor-Cmd <proyecto>.uproject -nosound -unattended -nullrhi
- Qué carpetas son de cada rol y qué archivos genera el motor (que no se guardan).
- Metadatos que deben ir siempre con su archivo: Godot (.import, .uid), Unity (.meta).
  Hay comprobaciones listas en extras/godot y extras/unity; para otros motores se escribe
  una parecida si hace falta.
- Cómo se pasan los tests sin ventana.
- Cómo se reconocen los errores en lo que escribe el motor: muchos motores acaban "bien"
  aunque haya errores, así que el envoltorio los busca en la salida.

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
- Candados: con la orden "flock" (Linux) los da el sistema operativo y se sueltan solos. Sin
  ella (Git Bash en Windows, macOS sin "brew install flock") se usa un archivo con el PID: si
  ese PID lo reutiliza otro proceso, en Linux y macOS se detecta por su hora de arranque; en
  Windows no se puede saber y, pasadas 6 horas (CANDADO_MAX_HORAS), el candado avisa de
  "probable huérfano" con la orden para liberarlo a mano. Nunca se roba solo.
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

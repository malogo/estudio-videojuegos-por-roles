# Tablón de Orquestación (Append-Only — Archivar a las 200 líneas)
# Formato: YYYY-MM-DD HH:MM | origen | qué se entregó | ruta o commit | destino
# Lectura por rol: ./tools/hooks/arranque_rol.sh <rol>  (o grep "| nombre-rol$" docs/direccion/tablon.md)
# Escritura: solo con ./tools/hooks/entregar.sh <rol> "<qué>" "<ruta o commit>" <destino> [-- <rutas>]


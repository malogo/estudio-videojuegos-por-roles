# shellcheck shell=bash
# Comprobaciones de Godot 4.4+ para tools/hooks/pre-commit (se incluye con "source").
# Copiar a tools/hooks/pre-commit-motor.sh. Usa ES_MERGE del pre-commit; sale con "exit 1" si algo falla.

# 3. Escenas con reproducción automática de audio/vídeo
while IFS= read -r ESCENA; do
    [[ -z "$ESCENA" ]] && continue
    if git show ":$ESCENA" | grep -qE '^autoplay = true'; then
        echo "[ERROR PRE-COMMIT] '$ESCENA' tiene 'autoplay = true' en un nodo de audio/vídeo. Reprodúcelo desde código bajo control." >&2
        exit 1
    fi
done < <(git diff --cached --name-only --diff-filter=ACMR -- '*.tscn')

# 4. Cada .gd nuevo (o renombrado) entra con su .gd.uid: sin él, Godot 4.4+ le da otro uid en cada
#    equipo y las referencias uid:// se rompen. Bajo una carpeta con .gdignore Godot no importa nada.
#    En los merges no se mira: cada .gd ya pasó esta comprobación en el commit de su rama.
bajo_gdignore() {
    local d="$1"
    while [[ "$d" == */* ]]; do
        d="${d%/*}"
        { [[ -e "$d/.gdignore" ]] || git cat-file -e ":$d/.gdignore" 2>/dev/null; } && return 0
    done
    [[ -e .gdignore ]] || git cat-file -e ":.gdignore" 2>/dev/null
}
SIN_UID=()
while IFS= read -r GD; do
    [[ -z "$GD" ]] && continue
    bajo_gdignore "$GD" && continue
    git cat-file -e ":$GD.uid" 2>/dev/null || SIN_UID+=("$GD")
done < <( (( ES_MERGE )) || git diff --cached --name-only --no-renames --diff-filter=A -- '*.gd')
if (( ${#SIN_UID[@]} )); then
    echo "[ERROR PRE-COMMIT] Estos .gd entran sin su .gd.uid en el mismo commit:" >&2
    printf '  %s\n' "${SIN_UID[@]}" >&2
    echo "Genera los uid importando el proyecto: ./tools/motor_silencioso.sh <rol> --headless --import" >&2
    echo "  (sin Godot, p. ej. en la nube: ./tools/hooks/nuevo_uid.sh <archivo.gd>)" >&2
    echo "y añade cada <archivo.gd>.uid a las rutas del commit: git commit -m \"...\" -- <archivo.gd> <archivo.gd>.uid ..." >&2
    exit 1
fi


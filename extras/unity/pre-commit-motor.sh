# shellcheck shell=bash
# Comprobaciones de Unity para tools/hooks/pre-commit (se incluye con "source").
# Copiar a tools/hooks/pre-commit-motor.sh. Usa ES_MERGE del pre-commit; sale con "exit 1" si algo falla.
# Equivale al ".gd con su .gd.uid" de Godot: en Unity cada archivo o carpeta de Assets/ lleva su .meta
# con el GUID; sin él, cada equipo genera otro GUID y las referencias entre assets se rompen.

if (( ! ES_MERGE )); then
    SIN_META=()
    while IFS= read -r RUTA; do
        [[ -z "$RUTA" || "$RUTA" == *.meta ]] && continue
        git cat-file -e ":$RUTA.meta" 2>/dev/null || SIN_META+=("$RUTA")
    done < <(git diff --cached --name-only --no-renames --diff-filter=A -- 'Assets/*')
    if (( ${#SIN_META[@]} )); then
        echo "[ERROR PRE-COMMIT] Estos archivos de Assets/ entran sin su .meta en el mismo commit:" >&2
        printf '  %s\n' "${SIN_META[@]}" >&2
        echo "Ábrelos con el motor (./tools/motor_silencioso.sh <rol> ...) para que genere el .meta y añádelo a las rutas del commit." >&2
        exit 1
    fi
fi

# Audio que suena solo al cargar la escena (equivalente al "autoplay = true" de Godot).
while IFS= read -r ESCENA; do
    [[ -z "$ESCENA" ]] && continue
    if git show ":$ESCENA" | grep -qE '^[[:space:]]*m_PlayOnAwake: 1'; then
        echo "[ERROR PRE-COMMIT] '$ESCENA' tiene un AudioSource con Play On Awake. Reprodúcelo desde código bajo control." >&2
        exit 1
    fi
done < <(git diff --cached --name-only --diff-filter=ACMR -- '*.unity' '*.prefab')

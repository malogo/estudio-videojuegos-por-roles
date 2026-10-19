# shellcheck shell=bash
# Requisito de las guardas: bash 4 o posterior (arrays asociativos, ${x,,}, mapfile). Linux y Git Bash ya lo traen;
# macOS trae bash 3.2: "brew install bash" y que su carpeta (/opt/homebrew/bin o /usr/local/bin) vaya antes que /bin
# en el PATH. Uso: source tools/hooks/requisitos.sh (lo incluyen propiedad.sh y reglas_comando.sh).
# Sale con 2: en un hook PreToolUse de Claude Code eso bloquea (falla cerrada); en git y en los scripts es un error.

if (( BASH_VERSINFO[0] < 4 )); then
    echo "[requisitos] Las guardas necesitan bash 4 o posterior; este es $BASH_VERSION ($BASH)." >&2
    echo "  macOS: brew install bash, y que su carpeta vaya antes que /bin en el PATH. No desactives las guardas." >&2
    exit 2
fi

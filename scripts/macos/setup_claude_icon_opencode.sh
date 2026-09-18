#!/bin/bash
# ============================================================
# setup_claude_icon_opencode.sh
# Configura Claude Code CLI con icono en Dock
# y OpenCode con mistral-large-2512 via OpenRouter
#
# Uso: bash setup_claude_icon_opencode.sh
# Requiere: OPENROUTER_API_KEY en entorno o en ~/.hermes/config
# ============================================================

set -euo pipefail

# ── Colores ───────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠  $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; exit 1; }

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   ANALYTIC BEACON — MacBook M4 Setup             ║"
echo "║   Claude Code CLI (icono) + OpenCode (Mistral)   ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Obtener clave OpenRouter ──────────────────────────────
# Primero desde env, luego desde config de Hermes
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    HERMES_CONFIG="$HOME/.hermes/config.json"
    if [[ -f "$HERMES_CONFIG" ]]; then
        OR_KEY=$(python3 -c "
import json, sys
with open('$HERMES_CONFIG') as f:
    c = json.load(f)
# Buscar en distintas claves posibles
for k in ['openrouter_api_key','api_key','OPENROUTER_API_KEY']:
    if k in c:
        print(c[k])
        sys.exit(0)
# Buscar en providers
for block in c.get('providers', {}).values():
    if 'apiKey' in block:
        print(block['apiKey'])
        sys.exit(0)
" 2>/dev/null || true)
        if [[ -n "${OR_KEY:-}" ]]; then
            OPENROUTER_API_KEY="$OR_KEY"
            info "Clave OpenRouter leída desde ~/.hermes/config.json"
        fi
    fi
fi

# Si todavía falta, pedir manualmente
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo ""
    warn "No se encontró OPENROUTER_API_KEY automáticamente."
    echo -n "   Pega tu clave OpenRouter (sk-or-v1-...): "
    read -rs OPENROUTER_API_KEY
    echo ""
fi

[[ -z "${OPENROUTER_API_KEY:-}" ]] && fail "Se necesita OPENROUTER_API_KEY para continuar."
log "Clave OpenRouter disponible (${#OPENROUTER_API_KEY} chars)"

# ══════════════════════════════════════════════════════════
# PARTE 1 — CLAUDE CODE CLI: APP BUNDLE CON ICONO EN DOCK
# ══════════════════════════════════════════════════════════
echo ""
info "PARTE 1: Creando Claude Code CLI.app ..."

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
[[ ! -f "$CLAUDE_BIN" ]] && CLAUDE_BIN=$(which claude 2>/dev/null || true)
[[ -z "$CLAUDE_BIN" ]] && fail "No se encontró el binario 'claude'. Instala Claude Code CLI primero."
log "Binario claude: $CLAUDE_BIN"

APP_NAME="Claude Code CLI"
APP_PATH="$HOME/Applications/${APP_NAME}.app"
APPLESCRIPT_TMP="/tmp/claude_cli_launcher.applescript"

# Crear el AppleScript con banner bonito
cat > "$APPLESCRIPT_TMP" << APPLESCRIPT
tell application "Terminal"
    activate
    if (count of windows) is 0 then
        do script ""
    end if
    set newTab to do script "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:\$PATH\"; clear; printf '\\\\033[1;36m\\\\n╔══════════════════════════════════════╗\\\\n║        CLAUDE CODE CLI               ║\\\\n║  Analytic Beacon — MacBook M4        ║\\\\n╚══════════════════════════════════════╝\\\\033[0m\\\\n\\\\n'; claude" in window 1
end tell
APPLESCRIPT

mkdir -p "$HOME/Applications"
rm -rf "$APP_PATH"
osacompile -o "$APP_PATH" "$APPLESCRIPT_TMP"
log "App bundle creado: $APP_PATH"

# ── Copiar icono desde Claude.app del sistema ─────────────
ICON_COPIED=false
for CANDIDATE in \
    "/Applications/Claude.app/Contents/Resources/AppIcon.icns" \
    "/Applications/Claude.app/Contents/Resources/claude.icns" \
    "$HOME/Applications/Claude.app/Contents/Resources/AppIcon.icns"; do
    if [[ -f "$CANDIDATE" ]]; then
        cp "$CANDIDATE" "$APP_PATH/Contents/Resources/applet.icns"
        ICON_COPIED=true
        log "Icono copiado desde: $CANDIDATE"
        break
    fi
done

if [[ "$ICON_COPIED" == false ]]; then
    warn "Claude.app no encontrado. Se usará el icono genérico de AppleScript."
    info "Para cambiar el icono manualmente: clic derecho en la app → Get Info → arrastra tu icono al cuadro."
fi

# Recargar Finder para que detecte el icono
touch "$APP_PATH"

# ── Agregar al Dock ───────────────────────────────────────
info "Agregando al Dock..."

# Verificar si ya está en el Dock
DOCK_PLIST="$HOME/Library/Preferences/com.apple.dock.plist"
if /usr/libexec/PlistBuddy -c "Print persistent-apps" "$DOCK_PLIST" 2>/dev/null | grep -q "Claude Code CLI"; then
    warn "Ya existe una entrada 'Claude Code CLI' en el Dock."
else
    defaults write com.apple.dock persistent-apps -array-add \
        "<dict>
            <key>tile-data</key>
            <dict>
                <key>file-data</key>
                <dict>
                    <key>_CFURLString</key>
                    <string>file://${APP_PATH}</string>
                    <key>_CFURLStringType</key>
                    <integer>15</integer>
                </dict>
                <key>file-label</key>
                <string>Claude Code CLI</string>
            </dict>
        </dict>"
    killall Dock
    log "Agregado al Dock y Dock reiniciado"
fi

# ── También copiar al Desktop por conveniencia ─────────────
if [[ ! -e "$HOME/Desktop/${APP_NAME}.app" ]]; then
    cp -R "$APP_PATH" "$HOME/Desktop/"
    log "Copia también en el Desktop"
fi

# ══════════════════════════════════════════════════════════
# PARTE 2 — OPENCODE: CONFIGURAR mistral-large-2512
# ══════════════════════════════════════════════════════════
echo ""
info "PARTE 2: Configurando OpenCode con mistral-large-2512 via OpenRouter ..."

OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
OPENCODE_CONFIG="$OPENCODE_CONFIG_DIR/config.json"

# Hacer backup del config actual
if [[ -f "$OPENCODE_CONFIG" ]]; then
    BACKUP="${OPENCODE_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$OPENCODE_CONFIG" "$BACKUP"
    info "Backup del config anterior: $BACKUP"
    OLD_MODEL=$(python3 -c "import json; c=json.load(open('$OPENCODE_CONFIG')); print(c.get('model','(none)'))" 2>/dev/null || echo "desconocido")
    info "Modelo anterior: $OLD_MODEL"
fi

mkdir -p "$OPENCODE_CONFIG_DIR"

cat > "$OPENCODE_CONFIG" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "openrouter/mistralai/mistral-large-2512",
  "provider": {
    "openrouter": {
      "name": "OpenRouter",
      "apiKey": "${OPENROUTER_API_KEY}"
    }
  },
  "keybinds": {
    "leader": "ctrl+x"
  },
  "note": "Configurado por Analytic Beacon — mismo modelo que Hermes (mistral-large-2512 via OpenRouter)",
  "configuredAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

log "OpenCode config guardado en: $OPENCODE_CONFIG"

# ── Verificar si opencode está disponible ─────────────────
if command -v opencode &>/dev/null; then
    OC_VERSION=$(opencode --version 2>/dev/null || echo "desconocida")
    log "OpenCode detectado: versión $OC_VERSION"
else
    warn "Binario 'opencode' no encontrado en PATH. Asegúrate de instalarlo si no está."
    info "Instalar: npm install -g opencode-ai  (o el método que usas en tu sistema)"
fi

# ══════════════════════════════════════════════════════════
# RESUMEN FINAL
# ══════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗"
echo -e "║              SETUP COMPLETADO ✅                 ║"
echo -e "╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Claude Code CLI${NC}"
echo    "    App: $APP_PATH"
echo    "    Desktop: ~/Desktop/${APP_NAME}.app"
echo    "    Dock: agregado (reinicio Dock automático)"
echo ""
echo -e "  ${GREEN}OpenCode${NC}"
echo    "    Config: $OPENCODE_CONFIG"
echo    "    Modelo: mistralai/mistral-large-2512"
echo    "    Gateway: OpenRouter"
echo    "    (mismo modelo que Hermes Desktop)"
echo ""
echo -e "  ${YELLOW}Próximos pasos:${NC}"
echo    "  1. Haz clic en 'Claude Code CLI' en el Dock o Desktop para probar"
echo    "  2. Lanza OpenCode (opencode en terminal) — usará Mistral automáticamente"
echo    "  3. Si el icono de Claude no cargó, haz Get Info en la app y arrastra tu .icns"
echo ""

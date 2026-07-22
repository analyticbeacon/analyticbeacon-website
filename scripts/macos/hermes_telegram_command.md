# Comando para enviar a Hermes vía Telegram

Copia y pega este mensaje en el chat de Telegram con Hermes Desktop:

---

```
Ejecuta estos comandos en la MacBook para configurar Claude Code CLI con icono y OpenCode con Mistral:

# 1. CLAUDE CODE CLI — crear app con icono en Desktop y Dock
cat > /tmp/launch_claude.applescript << 'AS'
tell application "Terminal"
    activate
    if (count of windows) is 0 then
        do script ""
    end if
    do script "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:$PATH\"; clear; printf '\\033[1;36m\\n╔══════════════════════════════════════╗\\n║       CLAUDE CODE CLI                ║\\n║   Analytic Beacon — MacBook M4       ║\\n╚══════════════════════════════════════╝\\033[0m\\n\\n'; claude" in window 1
end tell
AS
mkdir -p ~/Applications
osacompile -o ~/Applications/"Claude Code CLI.app" /tmp/launch_claude.applescript
cp ~/Applications/"Claude Code CLI.app" ~/Desktop/ 2>/dev/null || true
ICON="/Applications/Claude.app/Contents/Resources/AppIcon.icns"
[ -f "$ICON" ] && cp "$ICON" ~/Applications/"Claude Code CLI.app/Contents/Resources/applet.icns"
defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file:///Users/francisco/Applications/Claude Code CLI.app</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>'
killall Dock
echo "✅ Claude Code CLI creado en Desktop y Dock"

# 2. OPENCODE — configurar con mistral-large-2512 via OpenRouter
OR_KEY=$(python3 -c "import json; c=json.load(open(open.__class__.__module__.__class__.__name__)); print('')" 2>/dev/null || cat ~/.hermes/config.json 2>/dev/null | python3 -c "import sys,json; c=json.load(sys.stdin); print(c.get('openrouter_api_key','') or c.get('api_key',''))" 2>/dev/null || echo "")
mkdir -p ~/.config/opencode
cat > ~/.config/opencode/config.json << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "openrouter/mistralai/mistral-large-2512",
  "provider": {
    "openrouter": {
      "name": "OpenRouter",
      "apiKey": "$OR_KEY"
    }
  }
}
EOF
echo "✅ OpenCode configurado con mistral-large-2512 via OpenRouter"
echo "✅ Setup completo. Verifica el Dock y abre OpenCode para confirmar."
```

---

## Alternativa: correr el script completo

Si tienes acceso al repo en la MacBook:

```bash
cd ~/Documents/analyticbeacon-website
git pull origin claude/macbook-audit-csnsf9
bash scripts/macos/setup_claude_icon_opencode.sh
```

## Nota sobre la clave OpenRouter

El script busca la clave automáticamente en `~/.hermes/config.json`.  
Si no la encuentra, la pedirá de forma interactiva.  
**No incluir la clave en mensajes de Telegram por seguridad.**

# Remote Desktop Usage Guide

## Connecting to the Remote Desktop

### From Windows
1. Open **Microsoft Remote Desktop** (pre-installed on Windows 10/11)
2. Click **Add PC**
3. Enter the remote server's IP address or hostname
4. Enter your Ubuntu username and password when prompted
5. Click Connect

### From Android Tablet
1. Install **Microsoft Remote Desktop** from Google Play Store
2. Open the app and tap **+** to add a new connection
3. Enter the remote server's IP address
4. Configure display settings for tablet (landscape mode recommended)
5. Connect using your Ubuntu credentials

## Installed Applications

### Visual Studio Code
- Launch: Click "VS Code" desktop shortcut or type `code` in terminal
- Access from menu: Applications > Development > Visual Studio Code

### Claude Code
- Terminal-based AI assistant
- Run: `claude` in terminal
- Requires API key configuration (see below)

### Chromium Browser
- Launch: Click "Chromium" desktop shortcut or type `chromium-browser`
- Access from menu: Applications > Internet > Chromium Web Browser

## API Key Configuration

### For Claude Code with OpenRouter:

1. Get your OpenRouter API key from https://openrouter.ai/

2. Set the environment variable (add to ~/.bashrc for persistence):
   ```bash
   echo 'export OPENROUTER_API_KEY="your_api_key_here"' >> ~/.bashrc
   source ~/.bashrc
   ```

3. Verify configuration:
   ```bash
   claude --version
   ```

### For Claude Code to use minimax2.5 model:

The default model is already configured in OpenRouter CLI settings.
To change models:
```bash
openrouter config set-model <model_name>
```

## Desktop Environment Tips

### GNOME Touch Gestures
- **Switch workspaces**: Three-finger swipe left/right
- **Overview**: Three-finger swipe up
- **App launcher**: Super key (Windows key)

### On-Screen Keyboard
- GNOME includes built-in on-screen keyboard
- Access: Settings > Accessibility > Keyboard > On-Screen Keyboard
- Enable for touch tablet use

### Tablet Optimization
- GNOME is designed for touch; icons and buttons are touch-friendly
- Use tablet in landscape mode for best experience
- Enable "Night Light" in Settings > Display for evening use

## Troubleshooting

### RDP Connection Issues
- Check xrdp status: `systemctl status xrdp`
- Restart xrdp: `sudo systemctl restart xrdp`
- Check firewall: `sudo ufw status` (port 3389 should be allowed)

### Desktop Not Loading
- Check GNOME status: `systemctl status gdm3`
- Restart display manager: `sudo systemctl restart gdm3`

### Claude Code Not Working
- Verify API key: `echo $OPENROUTER_API_KEY`
- Check configuration: `cat ~/.config/claude/settings.json`
- Test OpenRouter: `openrouter status`

## Security Recommendations

1. **Use strong passwords** for your Ubuntu user account
2. **Configure firewall** - only allow RDP from your devices
3. **Use SSH keys** for server access instead of passwords
4. **Keep system updated**: `sudo apt update && sudo apt upgrade`
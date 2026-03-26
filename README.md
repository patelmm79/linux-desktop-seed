# Remote Linux Desktop Deployment

Quick-start guide for deploying a full Linux desktop environment on a remote Ubuntu server.

## Quick Install

```bash
# Upload the script to your server
scp deploy-desktop.sh user@your-server:/tmp/

# Run the deployment script
sudo bash /tmp/deploy-desktop.sh
```

## Post-Installation Setup

### 1. Set Your OpenRouter API Key

```bash
# Add to your ~/.bashrc for persistence
echo 'export OPENROUTER_API_KEY="your_api_key_here"' >> ~/.bashrc
source ~/.bashrc
```

Get your free API key at: https://openrouter.ai/

### 2. Connect via RDP

- **From Windows:** Open Microsoft Remote Desktop → Add PC → Enter server IP
- **From Android:** Install Microsoft Remote Desktop app → Add connection → Enter server IP

Default RDP port: `3389`

Login with your Ubuntu username and password.

## Installed Components

| Component | Description |
|-----------|-------------|
| GNOME Desktop | Modern, tablet-friendly desktop environment |
| xrdp | Remote desktop protocol (RDP) server |
| VS Code | Full-featured code editor |
| Claude Code | AI assistant (configured for OpenRouter) |
| OpenRouter | API provider with minimax2.5 default model |
| Chromium | Web browser |

## Validation

Run the validation script to verify all components:

```bash
sudo bash tests/validate-install.sh
```

## Troubleshooting

See [docs/usage-guide.md](docs/usage-guide.md) for detailed troubleshooting.
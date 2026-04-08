# Token Rotation Policy

This document defines the rotation schedule and procedures for all secrets and API keys used in the desktop-seed deployment.

## Rotation Schedule

| Token | Rotation Frequency | Max Age | Reason |
|-------|-------------------|---------|--------|
| `OPENROUTER_API_KEY` | 90 days | 90 days | API key for AI services |
| `DISCORD_BOT_TOKEN` | 90 days | 90 days | Bot authentication |
| `DISCORD_CVE_WEBHOOK_URL` | 180 days | 180 days | Incoming webhook (lower risk) |

## Rotation Process

### Step 1: Generate New Token

**OpenRouter API Key:**
1. Log into [OpenRouter.ai](https://openrouter.ai)
2. Go to Account → API Keys
3. Create new key with a descriptive name (e.g., "desktop-seed VM 2026-04")
4. Copy the new key

**Discord Bot Token:**
1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Select your application → Bot
3. Click "Reset Token"
4. Copy the new token

**Discord Webhook URL:**
1. Go to Server Settings → Integrations → Webhooks
2. Edit the CVE monitor webhook
3. Click "Regenerate Webhook URL"
4. Copy the new URL

### Step 2: Update Environment File

On the VM:
```bash
# Edit the environment file
sudo nano ~/.config/desktop-seed/.env

# Update the relevant line:
OPENROUTER_API_KEY=sk-or-new-key-here
# or
DISCORD_BOT_TOKEN=NewBotTokenHere
# or
DISCORD_CVE_WEBHOOK_URL=https://discord.com/api/webhooks/...

# Save and exit
```

### Step 3: Restart Services

```bash
# Restart OpenCLAW to pick up new token
sudo systemctl restart openclaw

# Or for full restart including xrdp
sudo reboot
```

### Step 4: Verify

```bash
# Test OpenRouter API works
openclaw --version

# Test Discord bot is online
sudo systemctl status openclaw
```

### Step 5: Revoke Old Token

**OpenRouter:**
1. Go to Account → API Keys
2. Delete the old key

**Discord:**
1. Developer Portal → Bot
2. The old token is automatically invalidated on reset

## Automated Reminders

A cron job runs weekly to check token ages:
- Script: `scripts/check-token-age.sh`
- Schedule: Every Monday at 9 AM
- Action: Sends Discord alert if any token exceeds 80 days

To check manually:
```bash
bash scripts/check-token-age.sh
```

## Emergency Procedures

### Token Compromised - Immediate Rotation

If you suspect a token has been leaked:
1. **Immediately** rotate the token per the steps above
2. Check Discord server/API logs for unauthorized usage
3. Review `/var/log/openclaw/audit.log` for suspicious activity
4. Report to security team if data breach suspected

### Missed Rotation

If a token exceeds max age:
1. Bot/API will stop working
2. Check token-ages.json for which token expired
3. Rotate immediately following the process above
4. Document why rotation was missed in team retrospective

## Token Age Tracking

Token ages are tracked in: `~/.config/desktop-seed/token-ages.json`

This file is created at deploy time and updated on each rotation. Do not manually edit.

## References

- Rotation check script: `scripts/check-token-age.sh`
- Token ages file: `~/.config/desktop-seed/token-ages.json`
- Environment file: `~/.config/desktop-seed/.env`
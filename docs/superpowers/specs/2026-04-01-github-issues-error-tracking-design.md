# Design: GitHub Issues Error Tracking

## Overview

Add GitHub Issues integration to the session-monitor.sh to automatically create issues when critical errors occur. This provides persistent error tracking, pattern analysis over time, and enables Claude Code to analyze and suggest fixes.

## Architecture

```
session-monitor.sh (existing)
       │
       ▼
┌──────────────────┐
│  Error detected  │
└────────┬─────────┘
         │
         ▼ (if critical)
┌──────────────────┐    ┌──────────────┐
│ Create GitHub    │───▶│ Issue #123    │
│ Issue via API    │    │ - Title       │
└──────────────────┘    │ - Body        │
                         │ - Labels      │
                         └──────────────┘
```

## Trigger Events (Critical Errors)

| Event | Severity | Example |
|-------|----------|---------|
| Session crash | [critical] | gnome-shell/Xvnc terminates unexpectedly |
| Memory critical | [critical] | Available memory < 5% |
| Service failure | [critical] | xrdp/xrdp-sesman stops |
| Orphaned processes | [warning] | chansrv not cleaned up |

## Issue Format

**Title:** `[critical] Session crash at 2026-04-01 14:32`

**Body:**
```
## Error Details
- **Type:** Session crash
- **Timestamp:** 2026-04-01 14:32:15 UTC
- **Process:** gnome-shell (PID 2847)
- **Exit Code:** 139 (segfault)

## System State
- Memory: 2.1GB used / 3.8GB available
- Uptime: 4h 23m

## Log Files
- Session log: `/var/log/xrdp/sesman.log.1` (last 50 lines attached)
- Xsession errors: `~/.xsession-errors`

## Analysis Notes
Possible causes: GPU driver issue, memory exhaustion, display server conflict
```

**Labels:** `desktop`, `auto-detected`, `critical`

## GitHub API Integration

```bash
# Using GitHub CLI (gh) - already in deployment
gh issue create \
  --repo "owner/repo" \
  --title "[critical] Session crash at $(date)" \
  --body "$issue_body" \
  --label "desktop,auto-detected,critical"
```

**Configuration:** GitHub token stored in environment variable `GITHUB_TOKEN` on the remote desktop.

## Data Flow

1. **Detection:** session-monitor.sh catches error
2. **Classification:** Map error to severity level
3. **Formatting:** Build issue title + body from error context
4. **Creation:** Call `gh issue create` via SSH or local
5. **Confirmation:** Log issue URL to alert log

## Configuration Variables

```bash
# Environment variables (set on remote)
export GITHUB_TOKEN="ghp_xxxx"           # GitHub personal access token
export GITHUB_REPO="username/desktop-seed" # Target repository
export AUTO_ISSUE_ENABLED=true            # Enable/disable
export ISSUE_SEVERITY_THRESHOLD="warning" # Minimum severity
```

## Testing Approach

1. **Unit test:** Mock `gh` command, verify issue creation
2. **Integration test:** Create test issue on your repo
3. **Verify cleanup:** Close test issues after validation

## Implementation Phases

### Phase 1 (MVP)
- Add `create_github_issue()` function to session-monitor.sh
- Trigger on session crash and memory critical
- Use existing `gh` CLI (already deployed)

### Phase 2 (Enhancements)
- Add labels for categorization
- Deduplicate similar issues within 1 hour
- Add issue # to alert log output

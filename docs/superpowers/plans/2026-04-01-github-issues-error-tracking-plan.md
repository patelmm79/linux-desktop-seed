# GitHub Issues Error Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic GitHub issue creation to session-monitor.sh when critical errors (crashes, memory critical, service failures) are detected.

**Architecture:** Extend the existing `alert()` function to optionally create GitHub issues via `gh issue create`. Configuration via environment variables. Uses existing `gh` CLI already deployed.

**Tech Stack:** Bash, GitHub CLI (`gh`), existing session-monitor.sh

---

## File Structure

**Modify:**
- `scripts/session-monitor.sh` - Add GitHub issue creation on critical alerts

---

## Task 1: Add GitHub Configuration Variables

**Files:**
- Modify: `scripts/session-monitor.sh:19-25` (after existing config section)

- [ ] **Step 1: Read current config section**

Run: Read `scripts/session-monitor.sh` lines 19-25 to see existing variables

- [ ] **Step 2: Add GitHub configuration variables**

After line 25 (after `ORPHAN_CHECK_INTERVAL`), add:

```bash
# === GitHub Issue Configuration ===
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
AUTO_ISSUE_ENABLED="${AUTO_ISSUE_ENABLED:-false}"
ISSUE_SEVERITY_THRESHOLD="${ISSUE_SEVERITY_THRESHOLD:-warning}"
ISSUE_DEDUP_WINDOW=3600  # seconds (1 hour)
LAST_ISSUE_TIME=0
```

- [ ] **Step 3: Commit**

```bash
git add scripts/session-monitor.sh
git commit -m "feat: add GitHub issue configuration variables"
```

---

## Task 2: Create create_github_issue Function

**Files:**
- Modify: `scripts/session-monitor.sh` (after alert function ~line 202)

- [ ] **Step 1: Find alert function location**

Run: Grep for `^alert\(\)` to find exact line number

- [ ] **Step 2: Add create_github_issue function after alert()**

Insert after the `alert()` function (around line 202):

```bash
# === GitHub Issue Creation ===

create_github_issue() {
    local severity="$1"
    local title="$2"
    local body="$3"
    local labels="$4"

    # Check if GitHub integration is enabled
    if [[ "$AUTO_ISSUE_ENABLED" != "true" ]]; then
        return 0
    fi

    # Check required configuration
    if [[ -z "$GITHUB_REPO" ]] || [[ -z "$GITHUB_TOKEN" ]]; then
        return 0
    fi

    # Check severity threshold
    local severity_level=0
    case "$severity" in
        critical) severity_level=3 ;;
        warning) severity_level=2 ;;
        info) severity_level=1 ;;
        *) severity_level=0 ;;
    esac

    local threshold_level=0
    case "$ISSUE_SEVERITY_THRESHOLD" in
        critical) threshold_level=3 ;;
        warning) threshold_level=2 ;;
        info) threshold_level=1 ;;
        *) threshold_level=0 ;;
    esac

    if [[ "$severity_level" -lt "$threshold_level" ]]; then
        return 0
    fi

    # Deduplication: check if similar issue created recently
    local current_time=$(date +%s)
    local time_since_last=$((current_time - LAST_ISSUE_TIME))
    if [[ "$time_since_last" -lt "$ISSUE_DEDUP_WINDOW" ]]; then
        return 0
    fi

    # Update last issue time
    LAST_ISSUE_TIME=$current_time

    # Create issue using gh CLI
    local issue_url
    issue_url=$(gh issue create \
        --repo "$GITHUB_REPO" \
        --title "[$severity] $title" \
        --body "$body" \
        --label "$labels" 2>&1) || {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to create GitHub issue: $issue_url" >> "$ALERT_LOG"
        return 1
    }

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] GitHub issue created: $issue_url" >> "$ALERT_LOG"
    return 0
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/session-monitor.sh
git commit -m "feat: add create_github_issue function"
```

---

## Task 3: Integrate GitHub Issue Creation in Crash Detection

**Files:**
- Modify: `scripts/session-monitor.sh:monitor_crash_logs` function (~line 204)

- [ ] **Step 1: Read monitor_crash_logs function**

Run: Read `scripts/session-monitor.sh` lines 204-218 to see current crash detection

- [ ] **Step 2: Add GitHub issue creation on crash detection**

Replace the `monitor_crash_logs()` function with one that creates GitHub issues:

```bash
monitor_crash_logs() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local has_critical=false

    # Check for recent crash indicators in xrdp logs
    if [ -f /var/log/xrdp/xrdp-sesman.log ]; then
        local recent_errors=$(grep -i "error\|crashed\|exit" /var/log/xrdp/xrdp-sesman.log | tail -5 || true)

        if [ -n "$recent_errors" ]; then
            {
                echo "[$timestamp] === Recent xrdp-sesman Errors ==="
                echo "$recent_errors"
            } >> "$ALERT_LOG" 2>&1

            # Create GitHub issue for crash errors
            if echo "$recent_errors" | grep -qi "crashed\|segfault\|segmentation"; then
                has_critical=true

                local body="## Error Details
- **Type:** Session crash
- **Timestamp:** $timestamp
- **Process:** xrdp-sesman

## Recent Errors
\`\`\`
$recent_errors
\`\`\`

## System State
- Memory: $(free -h | grep Mem | awk '{print $3 " used / " $7 " available"})
- Uptime: $(uptime -p)

## Log Files
- Session log: \`/var/log/xrdp/xrdp-sesman.log\`
- Monitor log: \`$MONITOR_LOG\`

## Analysis Notes
Please check sesman logs for full crash details."

                create_github_issue "critical" "Session crash at $timestamp" "$body" "desktop,auto-detected,critical"
            fi
        fi
    fi
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/session-monitor.sh
git commit -m "feat: create GitHub issue on session crash detection"
```

---

## Task 4: Integrate GitHub Issue Creation in Memory Alert

**Files:**
- Modify: `scripts/session-monitor.sh:alert` function (~line 191)

- [ ] **Step 1: Read alert function and memory check**

Run: Read lines 181-202 to see how HIGH_MEMORY alert is triggered

- [ ] **Step 2: Extend alert function to create GitHub issues**

Replace `alert()` function with version that creates GitHub issues:

```bash
alert() {
    local alert_type=$1
    local message=$2
    local timestamp=$3

    {
        echo "[$timestamp] [$alert_type] $message"
    } >> "$ALERT_LOG" 2>&1

    # Optional: Send to syslog
    logger -t "xrdp-session-monitor" -p warning "$alert_type: $message"

    # Create GitHub issue for critical alerts
    local severity="info"
    case "$alert_type" in
        HIGH_MEMORY|HIGH_CPU|SERVICE_DOWN)
            severity="critical"
            ;;
        CLEANUP_ORPHAN)
            severity="warning"
            ;;
    esac

    if [[ "$severity" == "critical" ]]; then
        local body="## Error Details
- **Type:** $alert_type
- **Timestamp:** $timestamp
- **Message:** $message

## System State
- Memory: $(free -h | grep Mem | awk '{print $3 " used / " $7 " available"})
- CPU Load: $(uptime | awk -F'load average:' '{print $2}')
- Uptime: $(uptime -p)

## Log Files
- Monitor log: \`$MONITOR_LOG\`
- Alert log: \`$ALERT_LOG\`

## Analysis Notes
Check system resources and processes."

        create_github_issue "$severity" "$alert_type at $timestamp" "$body" "desktop,auto-detected,$severity"
    fi
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/session-monitor.sh
git commit -m "feat: create GitHub issue on critical alerts (memory/CPU)"
```

---

## Task 5: Add GitHub Authentication Check to Deployment

**Files:**
- Modify: `deploy-desktop.sh` - add GitHub CLI check and token setup

- [ ] **Step 1: Find where GitHub CLI is installed**

Run: Grep for "gh " or "github" in deploy-desktop.sh

- [ ] **Step 2: Add GitHub authentication guidance function**

After the `setup_monitoring()` function, add:

```bash
# Setup GitHub Issues integration
setup_github_issues() {
    log_info "Setting up GitHub Issues integration..."

    # Check if gh is installed
    if ! command -v gh &> /dev/null; then
        log_warn "GitHub CLI (gh) not installed - GitHub Issues disabled"
        return 0
    fi

    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        log_warn "GitHub not authenticated - run 'gh auth login' to enable issues"
        log_info "  To enable GitHub Issues:"
        log_info "    1. Run: gh auth login"
        log_info "    2. Set environment variables:"
        log_info "       export GITHUB_REPO='username/desktop-seed'"
        log_info "       export AUTO_ISSUE_ENABLED=true"
        return 0
    fi

    log_info "GitHub CLI configured - issues can be enabled via environment variables"
}
```

- [ ] **Step 3: Call setup_github_issues in main**

Find where `setup_monitoring` is called in `main()` and add:
```bash
setup_github_issues
```

- [ ] **Step 4: Commit**

```bash
git add deploy-desktop.sh
git commit -m "feat: add GitHub Issues setup to deployment"
```

---

## Task 6: Test GitHub Issue Creation

**Files:**
- Test: SSH into VM and run test command

- [ ] **Step 1: SSH into test VM and set variables**

```bash
export GITHUB_REPO="your-username/desktop-seed"
export AUTO_ISSUE_ENABLED=true
```

- [ ] **Step 2: Run test issue creation**

```bash
# Create a test issue (will appear as [info] severity)
gh issue create --repo "$GITHUB_REPO" \
  --title "[test] GitHub Issues integration test" \
  --body "This is a test issue to verify the integration works." \
  --label "desktop,auto-detected"
```

- [ ] **Step 3: Verify issue was created**

Check the repo issues list at: https://github.com/YOUR_USERNAME/desktop-seed/issues

- [ ] **Step 4: Close test issue**

```bash
gh issue close 1 --repo "$GITHUB_REPO"
```

- [ ] **Step 5: Commit**

```bash
git commit -m "test: verify GitHub issue creation works"
```

---

## Implementation Complete

After all tasks, the flow will be:

```
session-monitor.sh detects error
         │
         ▼
    alert() called
         │
         ▼
    ┌────┴────┐
    │Critical?│──Yes──▶ create_github_issue()
    └─────────┘
         │
         No
         ▼
    Log to alert.log only
```

---

## Plan Complete

**Saved to:** `docs/superpowers/plans/2026-04-01-github-issues-error-tracking-plan.md`

**Two execution options:**

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

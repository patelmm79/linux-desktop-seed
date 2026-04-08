# Skill Audit Inventory

This document tracks all Claude Code skills in the repository, their dependencies, and security posture.

## Inventory

| Skill ID | File | Category | Hardcoded Values | Secret Dependencies | Permissions | Last Reviewed | Risk Level |
|----------|------|----------|------------------|---------------------|-------------|---------------|------------|
| deploy_repo_to_vm | .claude/skills/deploy-repo-to-vm.json | devops | None (resolved) | OPENROUTER_API_KEY | repo write, Discord send | 2026-04-08 | 🟡 MEDIUM |

## Findings

### Finding 1: Hardcoded Discord Channel ID (RESOLVED)
- **File:** `.claude/skills/deploy-repo-to-vm.json`
- **Issue:** Hardcoded channel ID in environment block
- **Remediation:** Changed to use `${DISCORD_CHANNEL_ID}` env var
- **Status:** RESOLVED

### Finding 2: Hardcoded Discord Channel ID in Script (RESOLVED)
- **File:** `scripts/deploy-repo-to-vm.sh` line 10
- **Issue:** Hardcoded channel ID
- **Remediation:** Changed default to empty, requires `DISCORD_CHANNEL_ID` env var
- **Status:** RESOLVED

## Remediation Backlog

1. ✅ Remove hardcoded channel ID from skill JSON (Finding 1)
2. ⏳ Remove hardcoded channel ID from deploy-repo-to-vm.sh (Finding 2)

## Review Schedule

- Review all skills for hardcoded secrets: Monthly
- Check for new CVEs affecting skills: Weekly
- Rotate secrets: Per token-rotation-policy.md

## Adding New Skills

When adding a new skill:
1. Add entry to this inventory
2. Use environment variables for all sensitive values
3. Document secret dependencies in the entry
4. Include in monthly security review
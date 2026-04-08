---
name: repo-deployment-skill
description: Generic skill to clone GitHub repos to VM and notify Discord
type: reference
---

# Repo Deployment Skill Specification

## Overview

A skill that clones any GitHub repository to the VM and notifies a Discord channel when ready.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `repo` | string | Yes | - | GitHub repository (format: `owner/repo` or full URL) |
| `branch` | string | No | `main` | Branch to clone |
| `discord_channel_id` | string | No | `1491175562348331209` | Discord channel for notifications |

## Directory Structure

```
~/repos/
├── owner/
│   └── repo/
```

Example: `~/repos/patelmm79/dev-nexus-action-agent`

## Behavior

### Idempotency
- If repository already exists at target path, skip clone
- Return "already deployed" message to Discord

### Discord Notification
- Send message on success: `✅ Repository deployed to VM: {repo} ({branch})`
- Send message if already exists: `ℹ️ Repository already deployed: {repo}`
- Send message on error: `❌ Failed to deploy {repo}: {error}`

### Error Handling
- Invalid repository format → error to Discord
- Git clone failure → error to Discord with reason
- Network unavailable → error to Discord

## Implementation

### Skill Manifest
- Skill ID: `deploy_repo_to_vm`
- Category: DevOps
- Input schema: JSON with repo, optional branch

### Discord Integration
- Uses OpenCLAW CLI for Discord notifications
- Command: `openclaw message send --channel discord --target <channel_id> --message "<msg>"`
- Requires OpenCLAW to be installed and configured on the VM
- Channel ID configured at skill level (default: 1491175562348331209)

### Git Operations
- Use `git clone --depth 1` for faster cloning (shallow clone)
- Support both HTTPS and SSH git URLs
- Validate repo exists before attempting clone

## Testing

- Test with patelmm79/dev-nexus-action-agent
- Test idempotency (invoke twice)
- Test error case with invalid repo

## Example Invocation

```json
{
  "skill_id": "deploy_repo_to_vm",
  "input": {
    "repo": "patelmm79/dev-nexus-action-agent",
    "branch": "main"
  }
}
```

## Discord Response Examples

**Success:**
```
✅ Repository deployed to VM: patelmm79/dev-nexus-action-agent (main)
Location: ~/repos/patelmm79/dev-nexus-action-agent
```

**Already Deployed:**
```
ℹ️ Repository already deployed: patelmm79/dev-nexus-action-agent
Location: ~/repos/patelmm79/dev-nexus-action-agent
```

**Error:**
```
❌ Failed to deploy invalid-repo: Repository not found
```
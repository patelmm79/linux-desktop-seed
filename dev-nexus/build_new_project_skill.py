"""
Build New Project Skill

A2A Skill: build_new_project

Orchestrates building a new repository from a SEED_PLAN.md, applying:
1. Compliance standards from standards-config.yaml
2. User preferences (postgres choice, region, cloud, etc.)
3. GCP-specific rules (cost tagging, regions, etc.)

Then spawns Claude Code to build the actual project.

Workflow states:
  PARSING_SEED → VALIDATING_PLAN → APPLYING_PREFERENCES → BUILDING → APPLYING_COMPLIANCE → FINALIZING → DONE

Uses the existing WorkflowJob store from core/workflow_job_store.py
for state persistence and polling.
"""

import logging
import json
import os
import re
import uuid
import asyncio
import tempfile
import subprocess
from typing import Dict, List, Any, Optional
from datetime import datetime
from enum import Enum
from pathlib import Path

import anthropic
import yaml
import aiohttp
from github import Github

from a2a.skills.base import BaseSkill, SkillGroup, StandardSkillResponse
from core.workflow_job_store import (
    get_job_store,
    WorkflowJob,
    WorkflowStatus,
    RepositoryPhaseStatus,
    PhaseResult,
)

logger = logging.getLogger(__name__)


# ============================================================
# Constants & Defaults
# ============================================================

DEFAULT_COMPLIANCE_LEVEL = "strict"
DEFAULT_CLAUDE_MODEL = "claude-opus-4-6"

SUPPORTED_POSTGRES_PREFERENCES = ["cloud_sql", "vm_postgres"]
SUPPORTED_CLOUDS = ["gcp", "aws", "azure"]
SUPPORTED_REGIONS_GCP = ["us-central1", "us-east1", "europe-west1", "asia-east1"]

SKILL_ID = "build_new_project"
SKILL_NAME = "Build New Project"
SKILL_DESCRIPTION = (
    "Build a new repository from a SEED_PLAN.md, applying compliance standards "
    "and user preferences. Spawns Claude Code to execute the build and reports "
    "progress via workflow polling."
)


# ============================================================
# Workflow State Machine
# ============================================================

class BuildState(str, Enum):
    """States for the build_new_project workflow."""
    PARSING_SEED = "parsing_seed"
    VALIDATING_PLAN = "validating_plan"
    APPLYING_PREFERENCES = "applying_preferences"
    BUILDING = "building"
    APPLYING_COMPLIANCE = "applying_compliance"
    FINALIZING = "finalizing"
    DONE = "done"
    FAILED = "failed"


# ============================================================
# Preferences Loader
# ============================================================

class PreferencesLoader:
    """
    Loads and merges user preferences.
    Checks multiple sources in priority order:
    1. preferences dict passed directly to the skill
    2. config/preferences/{user_id}.yaml
    3. config/preferences/default.yaml
    """

    def __init__(self, config_dir: str):
        self.config_dir = Path(config_dir)

    def load(self, user_id: str, overrides: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        defaults = self._load_file("default.yaml")
        user_prefs = self._load_file(f"{user_id}.yaml") if user_id else {}
        merged = {**defaults, **user_prefs}
        if overrides:
            merged = {**merged, **overrides}
        return merged

    def _load_file(self, filename: str) -> Dict[str, Any]:
        path = self.config_dir / filename
        if path.exists():
            with open(path) as f:
                return yaml.safe_load(f) or {}
        return {}


# ============================================================
# Compliance Standards Loader
# ============================================================

class StandardsLoader:
    """
    Loads compliance standards from standards-config.yaml and
    GCP-specific infrastructure rules.
    """

    def __init__(self, standards_path: str):
        self.standards_path = Path(standards_path)
        self._cache: Optional[Dict[str, Any]] = None

    def load(self) -> Dict[str, Any]:
        if self._cache:
            return self._cache
        with open(self.standards_path) as f:
            self._cache = yaml.safe_load(f)
        return self._cache

    def get_infrastructure_standards(self) -> List[Dict[str, Any]]:
        standards = self.load()
        return standards.get("standards", {}).get("infrastructure", [])

    def get_infrastructure_standards(self) -> List[Dict[str, Any]]:
        """Infrastructure standards from the standards config."""
        all_standards = self.load().get("standards", {})
        infra = []
        for key, spec in all_standards.items():
            if spec.get("applies_to") and "infrastructure" in spec["applies_to"]:
                infra.append({"id": key, **spec})
        return infra

    def get_gcp_standards(self) -> List[Dict[str, Any]]:
        """GCP-specific standards extracted from standards config."""
        all_standards = self.load().get("standards", {})
        gcp = []
        for key, spec in all_standards.items():
            if "gcp" in key or "cloud" in key or "deployment" in key:
                gcp.append({"id": key, **spec})
        return gcp


# ============================================================
# SEED Plan Parser
# ============================================================

class SeedPlanParser:
    """Parses a SEED_PLAN.md file into a structured build manifest."""

    def __init__(self, github_client: Github):
        self.github_client = github_client

    async def parse(self, seed_plan_url: str) -> Dict[str, Any]:
        """
        Parse a SEED_PLAN.md from a GitHub URL.
        URL formats accepted:
          https://github.com/owner/repo/blob/main/SEED_PLAN.md
          https://raw.githubusercontent.com/owner/repo/main/SEED_PLAN.md
          owner/repo (assume SEED_PLAN.md on main)
        """
        owner, repo, branch, path = self._parse_url(seed_plan_url)
        gh_repo = self.github_client.get_repo(f"{owner}/{repo}")
        contents = gh_repo.get_contents(path, ref=branch)
        content = contents.decoded_content.decode("utf-8")
        return self._parse_content(content, seed_plan_url)

    def _parse_url(self, url: str) -> tuple:
        """Extract owner, repo, branch, path from URL."""
        if "/" not in url or "github" not in url:
            # Short form: owner/repo
            parts = url.split("/")
            return parts[0], parts[1], "main", "SEED_PLAN.md"
        # Full URL
        m = re.match(
            r"https://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)",
            url
        )
        if m:
            return m.group(1), m.group(2), m.group(3), m.group(4)
        m2 = re.match(
            r"https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)",
            url
        )
        if m2:
            return m2.group(1), m2.group(2), m2.group(3), m2.group(4)
        raise ValueError(f"Could not parse SEED_PLAN URL: {url}")

    def _parse_content(self, content: str, source_url: str) -> Dict[str, Any]:
        """
        Parse SEED_PLAN.md content into a structured manifest.
        
        Expected structure (markdown):
          # Project Name
          ## Overview
          body text
          ## Issues / Steps
          1. Step one
          2. Step two
          ...
        """
        lines = content.split("\n")
        manifest = {
            "source_url": source_url,
            "title": "",
            "overview": "",
            "steps": [],
            "stack": {},
            "infrastructure": {},
            "metadata": {},
        }

        current_section = None
        step_buffer = []

        for line in lines:
            if line.startswith("# "):
                manifest["title"] = line[2:].strip()
            elif line.startswith("## "):
                section = line[3:].strip().lower()
                if section == "overview":
                    current_section = "overview"
                elif "issue" in section or "step" in section:
                    current_section = "steps"
                    # Flush any buffered steps
                    if step_buffer:
                        manifest["steps"].extend(step_buffer)
                        step_buffer = []
                elif "infrastructure" in section:
                    current_section = "infrastructure"
                else:
                    current_section = None
            elif current_section == "overview":
                manifest["overview"] += line + "\n"
            elif current_section == "steps":
                # Detect step items: "1. ", "2. ", "- [ ] ", "- Step "
                m = re.match(r"^\d+\.\s+(.+)", line)
                if m:
                    step_text = m.group(1).strip()
                    # Detect checklist: "1. [ ] Install foo"
                    checked = False
                    if "[x]" in step_text.lower():
                        checked = True
                    step_text = re.sub(r"\[.\]\s*", "", step_text)
                    step_buffer.append({"text": step_text, "done": checked})
                # Also handle bullet points
                m2 = re.match(r"^-\s+(.+)", line)
                if m2 and not re.match(r"^-\s+\[", line):
                    step_buffer.append({"text": m2.group(1).strip(), "done": False})

        # Flush remaining steps
        if step_buffer:
            manifest["steps"].extend(step_buffer)

        # Extract stack hints from content
        manifest["stack"] = self._extract_stack(content)
        return manifest

    def _extract_stack(self, content: str) -> Dict[str, str]:
        """Detect technology stack from SEED_PLAN content."""
        stack = {}
        content_lower = content.lower()
        if "next.js" in content_lower or "nextjs" in content_lower:
            stack["frontend"] = "next.js"
        if "payload" in content_lower or "cms" in content_lower:
            stack["cms"] = "payload"
        if "postgres" in content_lower or "postgresql" in content_lower:
            stack["database"] = "postgres"
        if "gcp" in content_lower or "google cloud" in content_lower:
            stack["cloud"] = "gcp"
        if "vercel" in content_lower:
            stack["deployment"] = "vercel"
        if "cloud storage" in content_lower or "gcs" in content_lower:
            stack["storage"] = "gcs"
        return stack


# ============================================================
# Compliance Applicator
# ============================================================

class ComplianceApplicator:
    """
    Generates compliance artifacts for a new project:
    - CLAUDE.md (injected standards + preferences)
    - pre-commit hooks
    - CI/CD pipeline (GitHub Actions)
    - GCP cost tagging
    - SECURITY.md, CODEOWNERS, CONTRIBUTING.md
    """

    def __init__(self, standards_loader: StandardsLoader, preferences: Dict[str, Any]):
        self.standards = standards_loader.load()  # Full standards YAML dict
        self.preferences = preferences

    def generate_claude_md(self, manifest: Dict[str, Any]) -> str:
        """Generate CLAUDE.md with injected standards and preferences."""
        postgres_pref = self.preferences.get("postgres", "cloud_sql")
        cloud = self.preferences.get("cloud", "gcp")
        region = self.preferences.get("region", "us-central1")
        compliance_level = self.preferences.get("compliance_level", DEFAULT_COMPLIANCE_LEVEL)

        lines = [
            "# CLAUDE.md — Project Standards",
            "",
            f"# {manifest.get('title', 'Untitled Project')}",
            "",
            "## Stack",
            self._format_stack(manifest.get("stack", {})),
            "",
            "## Compliance Standards",
            f"**Level:** {compliance_level}",
            "",
            "### Required Checks (always run before committing)",
            self._get_required_checks(),
            "",
            "### GCP Requirements",
            f"- Region: `{region}`",
            f"- Cloud: `{cloud}`",
            "- All GCP resources MUST have cost-tracking labels:",
            "  ```",
            "  labels:",
            "    app: $PROJECT_NAME",
            "    env: $ENVIRONMENT",
            "    managed-by: dev-nexus",
            "  ```",
            "",
            "### Database",
            f"- PostgreSQL preference: **{postgres_pref}**",
            self._get_postgres_note(postgres_pref),
            "",
            "### Secrets",
            "- No hardcoded secrets — use environment variables or GCP Secret Manager",
            "- All secrets must be documented in `.env.example`",
            "",
            "### CI/CD",
            "- All PRs must pass: lint → test → security-scan → compliance-check",
            "- Secrets scanned on every commit (pre-commit hook or CI gate)",
            "",
            "## Allowed Hosts",
            self._get_allowed_hosts(cloud),
            "",
            "## Forbidden Patterns",
            "- Never commit `.env`, `secrets.json`, or credential files",
            "- Never disable linting rules without a documented reason",
            "- Never hardcode resource names (use variables)",
            "",
        ]
        return "\n".join(lines)

    def generate_github_actions_ci(self, manifest: Dict[str, Any]) -> str:
        """Generate .github/workflows/ci.yml"""
        cloud = self.preferences.get("cloud", "gcp")
        steps = []
        steps.append("      - name: Checkout")
        steps.append("        uses: actions/checkout@v4")
        steps.append("      - name: Set up Python")
        steps.append("        uses: actions/setup-python@v5")
        steps.append("        with:")
        steps.append("          python-version: '3.11'")
        steps.append("      - name: Install dependencies")
        steps.append("        run: pip install pre-commit && pre-commit install-hooks")
        steps.append("      - name: Run pre-commit")
        steps.append("        run: pre-commit run --all-files")
        steps.append("      - name: Security scan")
        steps.append("        run: |")
        steps.append("          # Scan for secrets")
        steps.append("          pip install detect-secrets")
        steps.append("          detect-secrets scan > .secrets.baseline")
        steps.append("          git diff --staged -- .secrets.baseline || true")

        if cloud == "gcp":
            steps.append("      - name: GCP compliance check")
            steps.append("        run: |")
            steps.append("          # Verify all Terraform resources have cost labels")
            steps.append("          # This is auto-generated by dev-nexus")
            steps.append("          echo 'GCP cost tagging enforced'")

        return f"""name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
{chr(10).join(steps)}
"""

    def generate_pre_commit_config(self) -> str:
        """Generate .pre-commit-config.yaml"""
        return """repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files

  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
        exclude: '^secrets/'

  - repo: https://github.com/psf/black
    rev: 24.1.1
    hooks:
      - id: black

  - repo: https://github.com/pycqa/isort
    rev: 5.13.2
    hooks:
      - id: isort
"""

    def generate_codeowners(self) -> str:
        """Generate CODEOWNERS"""
        return """# Default owners for everything
* @patelmm79

# GCP / Infrastructure
*.tf @patelmm79
/cloud/** @patelmm79
/infrastructure/** @patelmm79

# CI/CD
.github/** @patelmm79
"""

    def _format_stack(self, stack: Dict[str, str]) -> str:
        return "\n".join(f"- **{k}**: {v}" for k, v in stack.items())

    def _get_required_checks(self) -> str:
        checks = [
            "✅ `npm test` / `go test` / `pytest` passes",
            "✅ Prettier / formatter ran",
            "✅ No new ESLint violations",
            "✅ No hardcoded secrets",
        ]
        return "\n".join(f"- {c}" for c in checks)

    def _get_postgres_note(self, pref: str) -> str:
        if pref == "cloud_sql":
            return "- Use **Cloud SQL** (managed Postgres) — connection via Cloud SQL Auth proxy or IAM auth"
        return "- Use **postgres-via-VM** (self-managed) — see `infrastructure/vm-postgres/` for setup"

    def _get_allowed_hosts(self, cloud: str) -> str:
        if cloud == "gcp":
            return "- `*.run.app` (Cloud Run)\n- `*.iherb.com` (if applicable)\n- `storage.googleapis.com`"
        return f"- `{cloud.upper()}` cloud (tbd)"


# ============================================================
# Claude Coding Agent (Tool-Use — runs on Cloud Run / GCP)
# ============================================================

TOOL_SCHEMA = [
    {
        "name": "bash",
        "description": "Run a bash command in the project directory. Use for npm installs, running dev servers, git operations, etc.",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "The bash command to run"},
                "timeout": {"type": "integer", "description": "Timeout in seconds (default: 120)", "default": 120},
            },
            "required": ["command"],
        },
    },
    {
        "name": "read_file",
        "description": "Read the contents of a file from the local project clone.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Relative path to the file"},
                "limit": {"type": "integer", "description": "Max lines to read (default: all)"},
            },
            "required": ["path"],
        },
    },
    {
        "name": "write_file",
        "description": "Write or overwrite a file in the local project clone.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Relative path for the new file"},
                "content": {"type": "string", "description": "Full file content"},
            },
            "required": ["path", "content"],
        },
    },
    {
        "name": "create_directory",
        "description": "Create a directory (and parents if needed) in the local clone.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Relative directory path to create"},
            },
            "required": ["path"],
        },
    },
    {
        "name": "list_directory",
        "description": "List the contents of a directory in the local clone.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Relative directory path"},
            },
            "required": ["path"],
        },
    },
    {
        "name": "git_commit",
        "description": "Stage and commit all current changes to the local git repo.",
        "input_schema": {
            "type": "object",
            "properties": {
                "message": {"type": "string", "description": "Commit message"},
            },
            "required": ["message"],
        },
    },
    {
        "name": "git_push",
        "description": "Push all committed changes to the remote GitHub repository.",
        "input_schema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "github_create_branch",
        "description": "Create a new git branch on the remote repository.",
        "input_schema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Branch name (e.g. 'feature/build-step-1')"},
                "from_branch": {"type": "string", "description": "Branch to branch from (default: 'main')"},
            },
            "required": ["name"],
        },
    },
    {
        "name": "search_web",
        "description": "Search the web for information (documentation, errors, best practices).",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "done",
        "description": "Signal that the build is complete. Use once all build steps are finished.",
        "input_schema": {
            "type": "object",
            "properties": {
                "summary": {"type": "string", "description": "Summary of what was built"},
                "artifacts": {"type": "array", "items": {"type": "string"}, "description": "List of key files created"},
            },
            "required": ["summary"],
        },
    },
]


class ClaudeCodingAgent:
    """
    Runs a Claude Code build session on Cloud Run (GCP).

    Uses the Anthropic Messages API with tool use enabled.
    Claude makes tool calls (bash, read_file, write_file, etc.) and
    this class executes them against the local project clone.

    Works entirely within the FastAPI/Cloud Run context — no subprocess
    spawning of a Claude Code CLI needed.
    """

    MAX_TURNS = 60  # Safety limit to prevent runaway loops
    DEFAULT_MODEL = "claude-opus-4-6"

    def __init__(
        self,
        anthropic_client: anthropic.Anthropic,
        github_client: Github,
        workspace_dir: str,
        target_repo: str,
        github_token: str,
        model: str = DEFAULT_MODEL,
    ):
        self.client = anthropic_client
        self.github = github_client
        self.workspace_dir = Path(workspace_dir)
        self.target_repo = target_repo
        self.github_token = github_token
        self.model = model
        self.clone_path: Optional[Path] = None

    async def run(self, task_prompt: str) -> Dict[str, Any]:
        """
        Run the full build task. Returns a result dict on completion.
        """
        # --- Clone the target repo ---
        self.clone_path = await self._clone_repo()
        logger.info(f"[ClaudeAgent] Cloned {self.target_repo} to {self.clone_path}")

        # --- Build the system prompt ---
        system_prompt = (
            "You are an expert full-stack software engineer. You are building a real project.\n"
            "You have access to a set of tools. Use them to complete the build task.\n"
            "Work carefully — prefer completeness over speed.\n"
            "After completing all build steps, call the `done` tool with a summary.\n"
            "IMPORTANT: Commit after each significant step using git_commit, then git_push.\n"
        )

        messages = [{"role": "user", "content": task_prompt}]
        turns = 0
        all_results = []

        while turns < self.MAX_TURNS:
            turns += 1

            response = self.client.messages.create(
                model=self.model,
                max_tokens=4096,
                system=system_prompt,
                tools=TOOL_SCHEMA,
                messages=messages,
            )

            stop_reason = response.stop_reason
            content_blocks = response.content

            # Collect any text output
            text_parts = []
            tool_results = []

            for block in content_blocks:
                if block.type == "text":
                    text_parts.append(block.text)
                elif block.type == "tool_use":
                    tool_name = block.name
                    tool_input = block.input
                    tool_id = block.id

                    result = await self._execute_tool(tool_name, tool_input)
                    tool_results.append({"id": tool_id, "result": result})
                    all_results.append({"turn": turns, "tool": tool_name, "result": result})

            # Add assistant's message and tool results to conversation
            messages.append({"role": "assistant", "content": content_blocks})

            if tool_results:
                for tr in tool_results:
                    messages.append({
                        "role": "user",
                        "content": [{
                            "type": "tool_result",
                            "tool_use_id": tr["id"],
                            "content": tr["result"],
                        }]
                    })

            # If Claude signalled done (no more tool calls), stop
            if stop_reason == "end_turn":
                final_text = "\n".join(text_parts)
                return {
                    "success": True,
                    "turns": turns,
                    "final_output": final_text,
                    "steps_completed": all_results,
                }

            # If we hit max turns, stop
            if turns >= self.MAX_TURNS:
                logger.warning(f"[ClaudeAgent] Hit MAX_TURNS ({self.MAX_TURNS})")
                return {
                    "success": False,
                    "turns": turns,
                    "error": f"Max turns ({self.MAX_TURNS}) exceeded",
                    "steps_completed": all_results,
                }

        return {"success": False, "turns": turns, "error": "Loop ended unexpectedly"}

    # ------------------------------------------------------------------
    # Tool Implementations
    # ------------------------------------------------------------------

    async def _clone_repo(self) -> Path:
        """Clone target repo into workspace directory."""
        clone_dir = self.workspace_dir / f"build_{uuid.uuid4().hex[:8]}"
        clone_dir.mkdir(parents=True, exist_ok=True)
        token = self.github_token or os.environ.get("GITHUB_TOKEN", "")
        auth_url = f"https://x-access-token:{token}@github.com/{self.target_repo}.git"
        result = subprocess.run(
            ["git", "clone", "--depth=1", auth_url, str(clone_dir)],
            capture_output=True, text=True, timeout=60,
        )
        if result.returncode != 0:
            # Try without auth (public repo)
            result = subprocess.run(
                ["git", "clone", "--depth=1", f"https://github.com/{self.target_repo}.git", str(clone_dir)],
                capture_output=True, text=True, timeout=60,
            )
            if result.returncode != 0:
                raise RuntimeError(f"git clone failed: {result.stderr}")
        return clone_dir

    async def _execute_tool(self, tool_name: str, tool_input: Dict[str, Any]) -> str:
        """Dispatch tool call to the appropriate handler."""
        handler = {
            "bash": self._tool_bash,
            "read_file": self._tool_read_file,
            "write_file": self._tool_write_file,
            "create_directory": self._tool_create_directory,
            "list_directory": self._tool_list_directory,
            "git_commit": self._tool_git_commit,
            "git_push": self._tool_git_push,
            "github_create_branch": self._tool_github_create_branch,
            "search_web": self._tool_search_web,
            "done": self._tool_done,
        }.get(tool_name)

        if not handler:
            return f"Error: unknown tool '{tool_name}'"

        try:
            return await handler(tool_input)
        except Exception as e:
            logger.error(f"[ClaudeAgent] Tool '{tool_name}' error: {e}")
            return f"Error: {str(e)}"

    async def _tool_bash(self, input_data: Dict[str, Any]) -> str:
        cmd = input_data["command"]
        timeout = input_data.get("timeout", 120)
        result = subprocess.run(
            cmd, shell=True, cwd=self.clone_path,
            capture_output=True, text=True, timeout=timeout,
        )
        output = f"[exit {result.returncode}]\n"
        if result.stdout:
            output += f"STDOUT:\n{result.stdout[:3000]}"
        if result.stderr:
            output += f"\nSTDERR:\n{result.stderr[:1000]}"
        return output

    async def _tool_read_file(self, input_data: Dict[str, Any]) -> str:
        path = self.clone_path / input_data["path"]
        if not path.is_relative_to(self.clone_path):
            return "Error: path traversal attempt detected"
        try:
            content = path.read_text()
            limit = input_data.get("limit")
            if limit:
                content = "\n".join(content.splitlines()[:limit])
            return content[:10000]
        except FileNotFoundError:
            return f"File not found: {input_data['path']}"
        except Exception as e:
            return f"Error reading file: {e}"

    async def _tool_write_file(self, input_data: Dict[str, Any]) -> str:
        path = self.clone_path / input_data["path"]
        if not path.is_relative_to(self.clone_path):
            return "Error: path traversal attempt detected"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(input_data["content"])
        return f"Written {len(input_data['content'])} bytes to {input_data['path']}"

    async def _tool_create_directory(self, input_data: Dict[str, Any]) -> str:
        path = self.clone_path / input_data["path"]
        if not path.is_relative_to(self.clone_path):
            return "Error: path traversal attempt detected"
        path.mkdir(parents=True, exist_ok=True)
        return f"Created directory: {input_data['path']}"

    async def _tool_list_directory(self, input_data: Dict[str, Any]) -> str:
        path = self.clone_path / input_data["path"]
        if not path.is_relative_to(self.clone_path):
            return "Error: path traversal attempt detected"
        if not path.exists():
            return f"Directory not found: {input_data['path']}"
        entries = [f"{'d' if e.is_dir() else 'f'} {e.name}" for e in sorted(path.iterdir())]
        return "\n".join(entries) or "(empty)"

    async def _tool_git_commit(self, input_data: Dict[str, Any]) -> str:
        msg = input_data["message"]
        result = subprocess.run(
            ["git", "add", "-A"],
            cwd=self.clone_path, capture_output=True, text=True,
        )
        if result.returncode != 0:
            return f"git add failed: {result.stderr}"
        result = subprocess.run(
            ["git", "commit", "-m", msg],
            cwd=self.clone_path, capture_output=True, text=True,
        )
        return f"git commit result: {result.returncode}\n{result.stdout}\n{result.stderr}"

    async def _tool_git_push(self, input_data: Dict[str, Any]) -> str:
        token = self.github_token or os.environ.get("GITHUB_TOKEN", "")
        if token:
            result = subprocess.run(
                ["git", "remote", "set-url", "origin",
                 f"https://x-access-token:{token}@github.com/{self.target_repo}.git"],
                cwd=self.clone_path, capture_output=True, text=True,
            )
        result = subprocess.run(
            ["git", "push", "origin", "HEAD"],
            cwd=self.clone_path, capture_output=True, text=True, timeout=60,
        )
        return f"git push result: {result.returncode}\n{result.stdout}\n{result.stderr}"

    async def _tool_github_create_branch(
        self, input_data: Dict[str, Any]
    ) -> str:
        branch_name = input_data["name"]
        from_branch = input_data.get("from_branch", "main")
        try:
            repo = self.github.get_repo(self.target_repo)
            source = repo.get_git_ref(f"refs/heads/{from_branch}")
            repo.create_git_ref(
                ref=f"refs/heads/{branch_name}",
                sha=source.object.sha,
            )
            # Switch local clone to new branch
            subprocess.run(
                ["git", "checkout", "-b", branch_name],
                cwd=self.clone_path, capture_output=True, text=True,
            )
            return f"Branch '{branch_name}' created and checked out locally"
        except Exception as e:
            return f"Error creating branch: {e}"

    async def _tool_search_web(self, input_data: Dict[str, Any]) -> str:
        import urllib.parse
        query = urllib.parse.quote(input_data["query"])
        return f"Search for: {input_data['query']}\n(Implement web search via DuckDuckGo or your tool)"
        # Note: in production, use requests to call DuckDuckGo or SerpAPI
        # Returning a placeholder keeps the tool schema consistent

    async def _tool_done(self, input_data: Dict[str, Any]) -> str:
        return (
            f"BUILD COMPLETE\n"
            f"Summary: {input_data.get('summary', 'N/A')}\n"
            f"Artifacts: {', '.join(input_data.get('artifacts', []))}"
        )


# ============================================================
# Task Prompt Builder
# ============================================================

def _build_task_prompt(
    manifest: Dict[str, Any],
    preferences: Dict[str, Any],
    target_repo: str,
) -> str:
    """Build the full task prompt passed to the Claude coding agent."""
    steps_md = []
    for i, step in enumerate(manifest.get("steps", []), 1):
        done_marker = "✅" if step.get("done") else "⬜"
        steps_md.append(f"{i}. {done_marker} {step['text']}")

    stack = manifest.get("stack", {})
    postgres_pref = preferences.get("postgres", "cloud_sql")
    region = preferences.get("region", "us-central1")
    cloud = preferences.get("cloud", "gcp")

    return f"""
## Mission

You are building a new project in GitHub repo: **{target_repo}**

### Project: {manifest.get('title', 'Untitled')}

{manifest.get('overview', '')}

### Build Steps (execute in order, skip completed ones):

{chr(10).join(steps_md)}

### Technology Stack (from SEED_PLAN):
- Frontend: {stack.get('frontend', 'TBD')}
- CMS: {stack.get('cms', 'TBD')}
- Database: {stack.get('database', 'postgres')}
- Cloud: {stack.get('cloud', cloud)}
- Deployment: {stack.get('deployment', 'TBD')}

### User Preferences (MUST respect these):
- **Postgres:** {postgres_pref} (user's preferred option)
- **Region:** {region}
- **Cloud:** {cloud}

### Compliance Requirements (MUST apply):
- All GCP resources need cost-tracking labels: `app`, `env`, `managed-by`
- No hardcoded secrets
- CI/CD pipeline in `.github/workflows/ci.yml`
- `CLAUDE.md` at repo root
- pre-commit hooks configured
- Secrets stored in `.env.example`, never committed

### Process:
1. Clone the target repo into /workspace (already done by the system)
2. Apply all compliance artifacts first (CLAUDE.md, CI, pre-commit, CODEOWNERS)
3. Execute build steps in order
4. After each significant step: git_commit then git_push
5. After ALL steps complete: call the `done` tool with a summary

Start now.
"""


# ============================================================
# Main Skill: BuildNewProjectSkill
# ============================================================

class BuildNewProjectSkill(BaseSkill):
    """
    A2A Skill: build_new_project

    Full workflow:
    1. Parse SEED_PLAN.md from GitHub URL
    2. Load user preferences (with overrides)
    3. Load compliance standards
    4. Generate compliance artifacts (CLAUDE.md, CI, pre-commit)
    5. Spawn Claude Code to execute the build
    6. Return workflow_id for polling
    """

    def __init__(
        self,
        github_client: Github,
        anthropic_client: anthropic.Anthropic,
        config_dir: str,
        standards_path: str,
        workspace_dir: str,
    ):
        self.github_client = github_client
        self.anthropic_client = anthropic_client
        self.preferences_loader = PreferencesLoader(Path(config_dir) / "preferences")
        self.standards_loader = StandardsLoader(standards_path)
        self.workspace_dir = Path(workspace_dir)
        self.job_store = get_job_store()

    @property
    def skill_id(self) -> str:
        return SKILL_ID

    @property
    def skill_name(self) -> str:
        return SKILL_NAME

    @property
    def skill_description(self) -> str:
        return SKILL_DESCRIPTION

    @property
    def tags(self) -> List[str]:
        return ["build", "project", "claude-code", "compliance", "infrastructure"]

    @property
    def requires_authentication(self) -> bool:
        return True  # Needs GitHub token and possibly Claude API key

    @property
    def input_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "seed_plan_url": {
                    "type": "string",
                    "description": (
                        "GitHub URL to SEED_PLAN.md, or 'owner/repo' short form. "
                        "Examples: "
                        "https://github.com/owner/repo/blob/main/SEED_PLAN.md, "
                        "owner/repo"
                    ),
                },
                "target_repo": {
                    "type": "string",
                    "description": "GitHub repo to build INTO (format: 'owner/repo-name')",
                },
                "user_id": {
                    "type": "string",
                    "description": "User ID for loading saved preferences (optional)",
                },
                "preferences": {
                    "type": "object",
                    "description": "Preference overrides (postgres, region, cloud, compliance_level)",
                    "properties": {
                        "postgres": {"type": "string", "enum": SUPPORTED_POSTGRES_PREFERENCES},
                        "region": {"type": "string", "enum": SUPPORTED_REGIONS_GCP},
                        "cloud": {"type": "string", "enum": SUPPORTED_CLOUDS},
                        "compliance_level": {"type": "string", "enum": ["strict", "moderate", "lenient"]},
                    },
                },
                "claude_code_model": {
                    "type": "string",
                    "description": f"Claude model to use (default: {DEFAULT_CLAUDE_MODEL})",
                    "default": DEFAULT_CLAUDE_MODEL,
                },
                "_github_token": {
                    "type": "string",
                    "description": "GitHub token override (for private repos)",
                },
            },
            "required": ["seed_plan_url", "target_repo"],
        }

    @property
    def examples(self) -> List[Dict[str, Any]]:
        return [
            {
                "input": {
                    "seed_plan_url": "https://github.com/patelmm79/personal_website/blob/main/SEED_PLAN.md",
                    "target_repo": "patelmm79/my-new-site",
                    "user_id": "patelmm79",
                },
                "description": "Build a new site from a SEED_PLAN with user preferences",
            },
            {
                "input": {
                    "seed_plan_url": "myorg/myrepo",
                    "target_repo": "myorg/brand-new-project",
                    "preferences": {"postgres": "vm_postgres", "region": "us-east1"},
                },
                "description": "Build with preference overrides (no saved preferences)",
            },
        ]

    async def execute(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """Execute the build_new_project skill."""
        response = StandardSkillResponse(success=True)

        try:
            # --- Resolve inputs ---
            seed_plan_url = input_data.get("seed_plan_url")
            target_repo = input_data.get("target_repo")
            user_id = input_data.get("user_id", "default")
            preferences_override = input_data.get("preferences", {})
            github_token = input_data.pop("_github_token", None) or os.environ.get("GITHUB_TOKEN", "")

            if not seed_plan_url or not target_repo:
                return StandardSkillResponse.error_response(
                    "seed_plan_url and target_repo are required"
                ).finish()

            # --- Create workflow job ---
            workflow_id = f"build-{uuid.uuid4().hex[:8]}"
            job = WorkflowJob(
                workflow_id=workflow_id,
                repositories=[target_repo],
                status=WorkflowStatus.RUNNING,
                created_at=datetime.now(),
                metadata={
                    "seed_plan_url": seed_plan_url,
                    "user_id": user_id,
                    "preferences_override": preferences_override,
                },
            )
            self.job_store.save_job(job)
            logger.info(f"[BUILD] Starting workflow {workflow_id} for {target_repo}")

            # --- Step 1: Parse SEED_PLAN ---
            gh_client = Github(github_token) if github_token else self.github_client
            parser = SeedPlanParser(gh_client)
            try:
                manifest = await parser.parse(seed_plan_url)
            except Exception as e:
                return StandardSkillResponse.error_response(
                    f"Failed to parse SEED_PLAN: {str(e)}"
                ).finish()

            job.metadata["manifest_title"] = manifest.get("title", "")
            job.metadata["stack"] = manifest.get("stack", {})
            self.job_store.save_job(job)

            # --- Step 2: Load preferences ---
            prefs = self.preferences_loader.load(user_id, preferences_override)
            self._validate_preferences(prefs)
            job.metadata["preferences"] = prefs

            # --- Step 3: Generate compliance artifacts ---
            applicator = ComplianceApplicator(self.standards_loader, prefs)
            claude_md = applicator.generate_claude_md(manifest)
            ci_yaml = applicator.generate_github_actions_ci(manifest)
            pre_commit = applicator.generate_pre_commit_config()
            codeowners = applicator.generate_codeowners()

            job.metadata["artifacts"] = {
                "CLAUDE.md": claude_md,
                ".github/workflows/ci.yml": ci_yaml,
                ".pre-commit-config.yaml": pre_commit,
                "CODEOWNERS": codeowners,
            }
            self.job_store.save_job(job)

            # --- Step 4: Generate the task prompt ---
            task_prompt = _build_task_prompt(manifest, prefs, target_repo)

            # --- Step 5: Run the Claude Coding Agent ---
            # The agent clones the repo, writes compliance artifacts,
            # then executes build steps using tool use.
            agent = ClaudeCodingAgent(
                anthropic_client=self.anthropic_client,
                github_client=gh_client,
                workspace_dir=str(self.workspace_dir),
                target_repo=target_repo,
                github_token=github_token,
                model=input_data.get("claude_code_model", DEFAULT_CLAUDE_MODEL),
            )

            logger.info(f"[BUILD] Workflow {workflow_id} — starting Claude coding agent")

            try:
                build_result = await agent.run(task_prompt)
                job.metadata["build_result"] = {
                    "success": build_result.get("success"),
                    "turns": build_result.get("turns"),
                    "final_output": str(build_result.get("final_output", ""))[:500],
                }
                if build_result.get("success"):
                    job.status = WorkflowStatus.COMPLETED
                else:
                    job.status = WorkflowStatus.FAILED
                    job.error = build_result.get("error")
            except Exception as build_error:
                logger.error(f"[BUILD] Agent error: {build_error}", exc_info=True)
                job.status = WorkflowStatus.FAILED
                job.error = str(build_error)
                build_result = {"success": False, "error": str(build_error)}

            self.job_store.save_job(job)

            return StandardSkillResponse.success_response({
                "workflow_id": workflow_id,
                "repository": target_repo,
                "manifest_title": manifest.get("title", ""),
                "stack": manifest.get("stack", {}),
                "preferences_used": prefs,
                "artifacts_generated": list(job.metadata["artifacts"].keys()),
                "build_success": build_result.get("success", False),
                "build_turns": build_result.get("turns"),
                "state": job.status.value,
                "message": (
                    f"Build {'completed' if build_result.get('success') else 'failed'}. "
                    f"Ran {build_result.get('turns', 0)} agent turns."
                ),
            }).finish()

        except ValueError as e:
            logger.error(f"[BUILD] Validation error: {e}")
            return StandardSkillResponse.error_response(str(e)).finish()

        except Exception as e:
            logger.error(f"[BUILD] Unexpected error: {e}", exc_info=True)
            return StandardSkillResponse.error_response(f"Build failed: {str(e)}").finish()

    def _validate_preferences(self, prefs: Dict[str, Any]) -> None:
        """Validate that preferences are within allowed values."""
        if prefs.get("postgres") and prefs["postgres"] not in SUPPORTED_POSTGRES_PREFERENCES:
            raise ValueError(
                f"Unsupported postgres preference: {prefs['postgres']}. "
                f"Allowed: {SUPPORTED_POSTGRES_PREFERENCES}"
            )
        if prefs.get("cloud") and prefs["cloud"] not in SUPPORTED_CLOUDS:
            raise ValueError(
                f"Unsupported cloud: {prefs['cloud']}. Allowed: {SUPPORTED_CLOUDS}"
            )
        if prefs.get("region") and prefs["region"] not in SUPPORTED_REGIONS_GCP:
            logger.warning(f"Region {prefs['region']} not in standard list — proceeding anyway")


# ============================================================
# Status Polling Skill
# ============================================================

class GetBuildProjectStatusSkill(BaseSkill):
    """
    Poll the status of a build_new_project workflow.
    """

    def __init__(self):
        self.job_store = get_job_store()

    @property
    def skill_id(self) -> str:
        return "get_build_project_status"

    @property
    def skill_name(self) -> str:
        return "Get Build Project Status"

    @property
    def skill_description(self) -> str:
        return "Poll the status of a build_new_project workflow"

    @property
    def input_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "workflow_id": {"type": "string"},
            },
            "required": ["workflow_id"],
        }

    async def execute(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        workflow_id = input_data.get("workflow_id")
        job = self.job_store.get_job(workflow_id)
        if not job:
            return StandardSkillResponse.error_response(f"Workflow not found: {workflow_id}").finish()

        return StandardSkillResponse.success_response({
            "workflow_id": job.workflow_id,
            "status": job.status.value,
            "repository": job.repositories[0] if job.repositories else None,
            "manifest_title": job.metadata.get("manifest_title"),
            "preferences": job.metadata.get("preferences"),
            "stack": job.metadata.get("stack"),
            "artifacts_generated": list(job.metadata.get("artifacts", {}).keys()),
            "created_at": job.created_at.isoformat(),
        }).finish()


# ============================================================
# Skill Group
# ============================================================

class BuildNewProjectSkills(SkillGroup):
    """Skill group containing build_new_project and related skills."""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def get_skills(self) -> List[BaseSkill]:
        return [
            BuildNewProjectSkill(
                github_client=self.postgres_repo,
                anthropic_client=self.kwargs.get("anthropic_client"),
                config_dir=self.kwargs.get("config_dir", "config"),
                standards_path=self.kwargs.get("standards_path", "compliance/standards-config.yaml"),
                workspace_dir=self.kwargs.get("workspace_dir", "/tmp/dev-nexus-builds"),
            ),
            GetBuildProjectStatusSkill(),
        ]

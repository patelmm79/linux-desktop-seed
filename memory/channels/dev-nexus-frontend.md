# Channel: #dev-nexus-frontend

## Channel Info
- **Discord channel:** `#dev-nexus-frontend` (ID: 1488649282792980550)
- **Guild:** 1485047825967480862
- **User:** no_decaf_milan (Discord ID: 1162240440322502656)
- **First session:** 2026-04-02

## Project: dev-nexus-frontend
Pattern Discovery Agent System frontend — React + TypeScript app connecting to FastAPI A2A backend.

**Tech stack:** React 18, TypeScript, Vite, TanStack Query, MUI, Recharts, react-force-graph-2d, Zustand, React Router

**License:** GNU General Public License v3.0

**Repo:** `~/GithubProjects/dev-nexus-frontend/` (local), `patelmm79/dev-nexus-frontend` (GitHub)

**Backend repo:** `~/GithubProjects/dev-nexus/` — FastAPI A2A server

## Current State (as of 2026-04-02)
- Working tree clean, no uncommitted changes
- Backend not running locally (localhost:8080)
- No active cron jobs or background tasks for this project

## Recent Work (from git log)
Last 8 commits (2026-03-25 to 2026-04-02):
- **05972e3** Readiness Dashboard: dropdown of tracked repos + custom entry toggle
- **2fb5aa4** Broaden Readiness Dashboard to assess any GitHub repository
- **04cc753** Add Readiness Dashboard link to Repositories page header
- **4e690a3** Fix TypeScript errors, data contract mismatches, and chunk size
- **acdd979** feat: user preferences + API keys tabs in Configuration
- **6168d4c** feat: wire Promote button end-to-end
- **25a268e** feat: readiness dashboard — concept list, detail view, score editing
- **ad0807f** feat: Build New Project page + useBuildProject hooks

## Key Pages/Features
- Dashboard, Repositories, Patterns, Configuration, Deployment, Agents pages
- Readiness Dashboard — assess any GitHub repo for GCP migration readiness
- Build New Project flow
- Configuration with user preferences + API keys management

## Architecture Notes
- Frontend uses `src/services/a2aClient.ts` for all backend communication
- `useApiWithDiagnostics` hook for all API calls with automatic error handling
- Manifest-based development — check `/.well-known/a2a-manifest.json` for skill definitions
- Always verify actual API response in Network tab before assuming type structure

## Connection
- Local dev: `VITE_API_BASE_URL=http://localhost:8080`
- Production: `https://pattern-discovery-agent-665374072631.us-central1.run.app`

## Documentation
- `docs/CODING_STANDARDS.md` — coding standards
- `docs/LESSONS_LEARNED.md` — lessons from past phases
- `docs/DEVELOPMENT.md` — development guide
- `docs/superpowers/plans/` — GCP readiness implementation plans
- Full integration guide in `CLAUDE.md`

---

## Related: dev-nexus Backend (GitHub Actions → GCP WIF Federation)

**Context:** The `patelmm79/dev-nexus` GitHub Actions → GCP workflow federation is broken. Build succeeds but GCR push fails.

### Current Status (2026-04-02)
- Terraform apply: ✅ completed — `serviceAccountTokenCreator` now bound from WIF pool → SA
- GCR repo permission: ✅ applied
- Workflow: pending re-run after ~5 min propagation

### Working Auth Strategy (Final)
Two-step auth in workflow:
1. `auth-token`: `token_format: access_token` → for `docker/login-action` with `username: oauth2accesstoken`
2. `auth-creds`: `export_credentials: true` → SA key file → for gcloud/Terraform

Both steps need `serviceAccountTokenCreator` on WIF pool → SA (added via Terraform).

### Key Findings (Hard Lessons)
1. **principalSet:// bindings MUST use Terraform SA-level binding** — gcloud CLI rejects this format at both project and SA levels
2. **docker/login-action requires explicit credentials** — must use `username: oauth2accesstoken` + `password: ${{ steps.auth.outputs.access_token }}`
3. **Every approach needs serviceAccountTokenCreator** — even minimal WIF (no flags) fails because gcloud refresh requires it
4. **GCR repo ACLs are separate from project IAM** — need `artifactregistry.writer` on the repository resource specifically
5. **IAM bindings take ~5 min to propagate**

### Docs Updated
- `docs/DEPLOYMENT_LESSONS_LEARNED.md` — fully updated
- `docs/github-actions-wif-setup.md` — corrected principalSet → Terraform only

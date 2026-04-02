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
- Build: ✅ succeeds
- GCR push: ❌ fails — `gcloud auth configure-docker gcr.io` can't refresh tokens

### Error
```
ERROR: (gcloud.auth.docker-helper) There was a problem refreshing your current auth tokens:
('Unable to acquire impersonated credentials', 'Permission 'iam.serviceAccounts.getAccessToken' denied on resource (or it may not exist)')
```
Then: `denied: Unauthenticated request. artifactregistry.repositories.uploadArtifacts`

### What Was Tried (from Claude Code session)
1. Initial WIF setup had binding backwards: `cloudbuild SA → serviceAccountTokenCreator on github-actions-deploy` (wrong direction)
2. Found this project's Cloud Build uses Default Compute SA: `665374072631-compute@developer.gserviceaccount.com` (no dedicated Cloud Build SA exists)
3. Set `github-actions-deploy` → `serviceAccountTokenCreator` on Compute SA (for Cloud Build impersonation)
4. Set `github-actions-deploy` → `serviceAccountTokenCreator` on itself (self-impersonation for GCR auth)
5. Tried `docker/login-action@v3` → didn't work with WIF credentials directly
6. Tried `gcloud auth configure-docker gcr.io` → fails with impersonation error

### GitHub Actions Workflow (deploy-production.yml)
Steps in "Deploy to Cloud Run" job:
1. `google-github-actions/auth` — authenticates as `github-actions-deploy@globalbiting-dev.iam.gserviceaccount.com` via WIF
2. `setup-gcloud` — sets up gcloud with those credentials
3. `gcloud auth configure-docker gcr.io` — FAILS here (current blocker)
4. `docker build + push` — skipped because step 3's error doesn't stop the step, but push fails
5. `terraform apply` — not reached

### Key Bindings on `github-actions-deploy@globalbiting-dev.iam.gserviceaccount.com`
- `serviceAccountTokenCreator` on `github-actions-deploy` (self) — for minting tokens
- `serviceAccountTokenCreator` on `665374072631-compute@developer.gserviceaccount.com` — for Cloud Build
- `roles/iam.workloadIdentityUser` via WIF pool

### Root Cause Hypothesis
`gcloud auth configure-docker gcr.io` tries to refresh OAuth2 tokens for GCR. For WIF credentials to work with GCR, either:
1. The SA needs `serviceAccountTokenCreator` on itself AND the GCR repo permissions, OR
2. Need to use `docker/login-action@v3` with proper WIF-compatible configuration

### Next Steps (Pending)
1. Try `docker/login-action@v3` with `registry: gcr.io` — but need to verify it can read ADC from `google-github-actions/auth` output
2. Alternative: Use SA key approach instead of WIF for Docker auth
3. Need to add `roles/artifactregistry.writer` to `github-actions-deploy` SA on the GCR repository

### GitHub Run History (recent failures)
- `697a308` fix(ci): use gcloud auth configure-docker — FAILURE (current)
- `66a77d5` ci: docker/login-action reads ADC — FAILURE
- `23915428740` Deploy to Production (manual) — FAILURE
- `23915426866` ci: docker/login-action with access_token — FAILURE

### Lessons Learned (To Be Documented)
- WIF credential chain for GCR push is complex — multiple impersonation hops may be needed
- `gcloud auth configure-docker` with WIF doesn't work out of the box
- `docker/login-action@v3` with GCR has its own requirements
- Project has no dedicated Cloud Build SA — uses Default Compute SA
- IAM bindings with conditions require `--condition=None` flag

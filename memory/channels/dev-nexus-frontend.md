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

## Current State (as of 2026-04-03)
- Frontend: `https://dev-nexus-frontend.vercel.app` — live
- Backend: `https://pattern-discovery-agent-75l7mntama-uc.a.run.app` — live, public, PostgreSQL connected
- GitHub OAuth: flow fixed (state via URL, no cookies)
- Frontend `.env.production` API URL fixed to correct backend URL
- Vercel dashboard `VITE_API_BASE_URL` may override local `.env.production` — check dashboard if issues recur
- CORS on backend: `dev-nexus-frontend\.vercel\.app`
- Deploy workflow: gcloud-based, working end-to-end

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
- Production: `https://pattern-discovery-agent-75l7mntama-uc.a.run.app` (was incorrectly `665374072631.us-central1.run.app`)

## Documentation
- `docs/CODING_STANDARDS.md` — coding standards
- `docs/LESSONS_LEARNED.md` — lessons from past phases
- `docs/DEVELOPMENT.md` — development guide
- `docs/superpowers/plans/` — GCP readiness implementation plans
- Full integration guide in `CLAUDE.md`

---

## Related: dev-nexus Backend

**Status (2026-04-03):** Backend fully operational. Terraform state is out of sync but deploy workflow bypasses Terraform entirely with direct `gcloud run deploy`.

**Key issue resolved:** CSRF state cookie was being stripped by Cloud Run's Google Frontend proxy. Solution: pass CSRF state in URL (GitHub passes it back unchanged through OAuth redirect chain).

**Known issues:**
- Terraform state severely out of sync — full `terraform apply` will fail (409 conflicts on existing resources)
- PostgreSQL VM managed by Terraform, state desync means postgres VM changes can't be applied via Terraform

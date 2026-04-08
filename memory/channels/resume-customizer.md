# resume-customizer channel memory
Last updated: 2026-04-08

## Project
- LangGraph multi-agent resume customization app
- Deployed: https://resume-customizer-665374072631.us-central1.run.app (Cloud Run)
- Repo: patelmm79/resume-customizer

## Status: ✅ Use case 0% bug FIXED (2026-04-08)
- Root cause: V2UseCaseSelector.__init__ called get_agent_llm_client() at object-init time,
  falling back to gemini (invalid API key) in non-Streamlit env
- Fix: get LLM client at node call-time inside v2_use_case_selector_node
- Additional fixes: is not None checks, comprehensive fallback for LLM failures, parser fixes
- OpenRouter added as provider with anthropic/claude-3.5-haiku (fast, cheap ~$0.25/M tokens)
- Verified 2026-04-08: 7/7 skills have non-zero use_case_score (40%-90%)

## Latest commits
- 50b4fe4 feat: add OpenRouter provider with Claude Haiku support
- bd1a9b2 Fix use case selector cr...
- (many intermediate fixes from 2026-04-05)
- 5a92d3e fix: chart fallback for missing importance_rank

## OpenRouter Setup
- Key: stored in .env as OPENROUTER_API_KEY
- Model: anthropic/claude-3.5-haiku (default)
- App defaults to openrouter via .settings.json

## Architecture notes
- V2 workflow: job_analysis → priority_ranking → skills_review → section_adaptation → validation → PDF
- Skills review: top_skills_extractor → gap_analyzer (with selected_use_cases) → alignment_matrix
- Gap analyzer scores: work_experience_score (from resume) + use_case_score (from career use cases)
- Cloud Build: cloudbuild.yaml triggers on push to main

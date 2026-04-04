# resume-customizer channel memory
Last updated: 2026-04-04

## Project
- LangGraph multi-agent resume customization app
- Deployed: https://resume-customizer-665374072631.us-central1.run.app (Cloud Run)
- Repo: patelmm79/resume-customizer
- Orchestrator: V2WorkflowOrchestrator (workflow/orchestrator_v2.py)
- Latest commit: f8f0e2e "add: skills_review_page.py test runner for rendering from saved state"
- Previous commit: ac31f93 "fix: auto-select use cases in confirm_skills_review when career_use_cases exists"

## Recent work
- Fix: confirm_skills_review was calling gap_analyzer without running use_case_selector first → use_case_score all 0
- Fix applied: auto-select from career_use_cases when selected_use_cases is empty (automated workflow)
- Live LLM test passed: 14 gap_analysis entries, 23 alignment_matrix rows, PDF generated (394K)
- Still: use_case_score=0 in single checkpoint mode (confirm_skills_review fix not reached)

## Test files
- tests/skills_review_page.py: standalone Streamlit page to render Skills Review from saved state
- tests/live_llm_test.py: full programmatic e2e with real LLM (Claude)
- Saved states: /tmp/skills_state*.json (full, with_uc, confirmed variants)

## Architecture notes
- V2 workflow: job_analysis → priority_ranking → skills_review → section_adaptation → validation → PDF
- Skills review runs: top_skills_extractor → gap_analyzer → alignment_matrix_node
- PDF export via export_pdf_node → utils/pdf_exporter.py
- Cloud Build: cloudbuild.yaml triggers on push to main

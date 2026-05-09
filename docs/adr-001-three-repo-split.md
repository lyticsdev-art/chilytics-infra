# ADR-001: Three-repo split (inference / backend / frontend) + infra repo

**Status:** Accepted
**Date:** 2026-05-01
**Owner:** Abdelhak Homi

## Context

Prior to this date, the ChiLytics platform lived as three nested git repos coexisting under a single working directory (`lytics-v2/`):

- root `.git` → FastAPI inference (4 commits)
- `lytics-backend/.git` → Node orchestrator (402 commits)
- `lytics-frontend/.git` → React frontend (1054 commits)

The "monorepo" was actually three independent histories sharing a folder via `cp`, not via `git subtree` or `git submodule`. This caused:

- Live secrets baked into `.git/objects` (OpenAI / HF / Gemini / NVIDIA / MongoDB credentials)
- Hardcoded old-tenant Azure IDs in 21 KB `deployment.ps1` + `config.json`
- 130+ orphan PNGs and 9 redundant deploy scripts at the FastAPI root
- No CI/CD on the FastAPI repo; old GitHub Actions workflows on backend + frontend tied to the dead Azure tenant

## Decision

Split into **four** sibling repos under a new `lyticsdev-art` GitHub org:

| Repo | Role | Stack |
|---|---|---|
| `chilytics-inference` | AI/ML inference layer | Python / FastAPI |
| `chilytics-backend` | Tenant-aware orchestrator | Node / Express |
| `chilytics-frontend` | Web UI | React / Vite |
| `chilytics-infra` | IaC + reusable CI/CD + contracts | Bicep / GitHub Actions |

**Fresh git history.** Old repos archived to `_archive_pre_split_2026_05_01/` (cold storage) for IP-provenance proof; new repos start with a single squashed initial commit.

## Why three+infra, not a true monorepo

- **Independent deploy cadence:** UI changes ship 5x/day; inference changes ship weekly. Monorepo CI would either lock everyone to the slowest gate or require complex path-filtering.
- **Different runtimes:** Python venv + Node modules + Vite build don't share tooling. A monorepo would still need per-codebase pipelines.
- **Inference boundary is a hard wall:** chilytics-inference is the only code allowed to call OpenAI / Anthropic / Vertex AI / Bedrock SDKs. Physical separation makes that boundary auditable.
- **HIPAA scope reduction:** chilytics-frontend never touches PHI. Splitting it out lets the SOC 2 / HIPAA scope shrink to inference + backend only.

## Why a separate infra repo

- App repos stay clean — no Bicep clutter
- Single place to evolve the deploy pattern (change once, all 3 apps inherit via `uses:`)
- Auditable artifact for HIPAA + SOC 2 evidence (the `ops_hipaa_soc2_external` checklist becomes IaC)
- OpenAPI contract for inference lives here as the single source of truth

## Rejected alternatives

- **Nx / Turborepo monorepo:** overkill for three services with no shared TypeScript code. Adds tooling burden without solving anything.
- **`git filter-repo` to scrub secrets in-place:** 1054 frontend commits is too many to reliably scrub. Fresh history + key rotation is safer.
- **Keep a single repo with three top-level dirs:** keeps the original problem (one slow-gate CI, mixed concerns).

## Consequences

**Good:**
- Each repo is independently testable, deployable, ownable.
- Investors see four clean repos under a real org during diligence — not a personal account dumping ground.
- HIPAA scope can be precisely defined per repo.

**Bad:**
- Cross-cutting changes (e.g., add a new env var that all 3 apps need) touch 4 repos via 4 PRs.
- Local dev requires running 3 services + checking out 4 repos. Mitigated by a `chilytics-dev/` umbrella repo with `make up` / `docker compose` in a future iteration if it becomes painful.

## References

- Cleanup manifest: see `_archive_pre_split_2026_05_01/_CLEANUP_MANIFEST.md`
- Symbiote architecture: ChiLytics memory `feedback_chilytics_symbiote_architecture`
- Inference boundary: ChiLytics memory `feedback_ai_ml_lives_in_fastapi`

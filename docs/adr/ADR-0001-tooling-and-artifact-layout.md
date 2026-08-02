# ADR-0001: Tooling commands, artifact directory, and requirement ID scheme

- **Status:** Accepted (2026-07-19)
- **Context:** Design §16.1 requires stable doctor/test/gate/bench/render/interact/soak/decision commands with structured artifacts. The repo root is NOT a git repository (only `games/RascalRally/code/.git` exists), so gate artifacts and ADRs must live as plain files with no reliance on git history. The existing convention here is a single executable shell entry (`run-tests.sh`) wrapping `lune run`.
- **Decision:**
  - Commands live in `GameStudio/ui/LuauUI/tools/` as `<name>.sh` wrappers (doctor.sh, test.sh, gate.sh, bench.sh, render.sh, interact.sh, soak.sh, decision.sh) over Lune implementations in `tools/lune/`. `run-tests.sh` stays and `tools/test.sh` delegates to it.
  - Artifacts write to `GameStudio/ui/LuauUI/artifacts/phase-<N>/` (stable, versioned by filename, machine-readable JSON preferred). The canonical aggregate gate is `tools/gate.sh`, which writes `artifacts/phase-<N>/gate.json` for the active phase and exits 0 only on PASS.
  - Requirement IDs use `UI-<AREA>-<NNN>` (registry: `requirements.json`); phase manifest: `phases.json`. Gates and specs cite these IDs.
  - ADRs: `docs/adr/ADR-<NNNN>-<slug>.md`, this format. Lessons: `docs/lessons/<slug>.md`, one lesson per file with a one-line summary first.
- **Consequences:** Everything is discoverable from the library root; no git dependency; the /goal evaluator and verifier subagents get exact paths. Dropbox may drop empty directories, so every tool `mkdir -p`s its artifact dir before writing.

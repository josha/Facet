# Fresh-context reviews — Step 8.5 (2026-08-03)

Three independent fresh-context reviews ran at stage close, per the execution
contract: the required phase-gate verification plus the two specialists whose
authority this stage changed (Roblox platform; architecture/public API). Full
findings are recorded below verbatim; dispositions are LTN-7 in
../decisions.md. Every BLOCKER/MAJOR was fixed in-session and pinned by a
named suite case; recorded-not-fixed items carry their rationale in LTN-7.

| Review | Verdict | Blockers/Majors | Outcome |
|---|---|---|---|
| Roblox platform | 1 BLOCKER, 3 MAJOR, 3 MEDIUM, 6 MINOR | F1 stale-cache poisoning (BLOCKER), F2 fail-unsafe ceiling, F3 single-face probe, F6 multi-touch, F7 ghost timer | all five FIXED + pinned; F8/F10/F11/F12/F5 recorded/corrected per LTN-7 |
| Architecture | 1 BLOCKER-candidate, 4 MAJOR, 6 MINOR | F-1 hidden-candidate plate, F-2 stale dwell snapshot, F-3 contract omission, F-4 silent column keys, F-5 mount-time gating | all five FIXED + pinned; minors fixed (F-6..F-10) or contained (F-11 fixed) |
| Phase-gate | FINDINGS (2 MAJOR, 10 MINOR) | F1 genuinely-red prior gate (dispositioned: no-removals semantics), F2 contended double sweep (lockfile added; clean re-run) | ledger/check tightenings all applied (F3..F12) |

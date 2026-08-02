# Studio disposition — api-architecture-consistency (v0.8.0)

Rule applied (execution contract + this gate's `studio-evidence` check): a
compatible fix that can affect visible / input / layout / adapter / lifecycle
behavior needs real-adapter proof; fixes that cannot are backed by the headless
suite plus the regenerated flat baseline. Canary evidence: `studio/canary.json`
(geometry probes paired with in-session captures), run in the live Rojo-synced
Rascal Rally place at source v0.8.0 after preflight (real viewport, source
marker, input-space calibration by probe).

## Runtime-affecting fixes and their real-adapter proof

| Fix | Class | Proof |
|---|---|---|
| F-27 Table header honors `column.alignment` | layout/visible | canary S1: live TextXAlignment + rect probes on real Instances, both alignments, plus the sort-mark clearance (104→98) live; capture paired |
| F-14 focus-graph internal copies | input | canary S3: real IAS keyboard drive through presenter focus (Right/Return/Down) lands focus, selects the column, cycles sort; game suite's presenter/sponsor integration specs green |
| F-15/F-16 presenter validation + critical opts | input/lifecycle | error-path-only at present time (no visual change for legal opts — game's `passive`/`none` values verified legal); live presenter path exercised end-to-end in S2/S3; headless cases pin the refusals |
| F-17 touch-gesture positional args | adapter/input | headless: normalize contract + userdata-reader cases (newproxy) + adapter source assertions in render_target_contract.spec; **Studio cannot synthesize real touch** — firing remains physical row NS-P2 (unchanged standing row), recorded honestly in canary.json |
| F-24 gallery auto-bind (Table scroll mirror) | example wiring | headless: live-drive case asserts the mirror follows engine scroll (`scrollTop == 120`); gallery is the dev surface, not a shipped screen |
| F-3 background meta / F-18 drag class gate / F-19 overflow="clip" / F-22 deep freeze / F-20 thickness metric | construction/solver | no author of the affected shapes exists in examples or the game (verified by grep); flat baseline regenerated and PASSES (1140 nodes, no uncharacterized rect/class drift); headless red-first cases pin each |
| F-1/F-2/F-4/F-5/F-37/F-12/F-13 build-time refusals | construction errors | error paths only; strict-authoring behavior is already Studio-proven as a class (0.5.0); one live confirmation incidentally captured — the canary's own first attempt was refused by Table's build validation in the running client |
| F-8..F-11 replication repairs | client state (no paint) | pure state machines; headless red-first cases; game's snapshot/mutation usage audited (consumer-impact.md) |
| Label semanticText / dump additions / type exports / text overload / Fit.state / inputHint opts | non-visual | headless only, by design |

## Honest limits carried forward

- Physical touch, real gamepad delivery, device performance: unchanged standing
  rows (NS-P2 et al.) — nothing in this stage closed or widened them.
- The five-view device matrix was NOT re-run this stage: no fix changes layout
  policy, adaptation, or paint vocabulary; the one visible-geometry change
  (header titles) is proven live in S1 and pinned headless. If a reviewer judges
  the matrix warranted, `docs/plans/studio-device-verification.md` is the recipe.
- `check_flat_baseline` PASSES at the final source; the header delta is absorbed
  by the pre-existing characterized `/Playlist/` reshape scope (recorded in
  canary.json rather than silently relied on).

# Old-brand drift guard — negative-control proof (2026-08-17)

Guard: `tools/check_brand_drift.py`. Scope: tracked files of both repos (paths +
contents; artifacts/**, docs/superpowers/**, .superpowers/** excluded as frozen
evidence), the current-facing studio surfaces (.claude/agents, both CLAUDE.md,
GameStudio/specialists, games/RascalRally/docs minus the missions/ and playtests/
history), and the serialized object Names of every buildable project (each Rojo
project built to XML — a binary .rbxl is LZ4-chunked, so byte greps prove nothing).
Every permitted match is an in-guard allowlist entry carrying a reason and a
removal rule (the rename ADR, frozen-schema readers, the attribute migration,
append-only ledgers, the guard itself).

| Run | Result |
|---|---|
| `python3 tools/check_brand_drift.py` (full, with builds) | PASS, exit 0 |
| `python3 tools/check_brand_drift.py --selftest` | PASS: planted old-name CONTENT line caught; planted old-name PATH caught; an allowlisted pattern planted OUTSIDE its allowlisted file caught; restored tree clean |

The selftest plants real files inside scanned directories and requires the scan to
go red before it may report success, so a future edit that blinds the scan also
reddens the selftest.

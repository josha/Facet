# MCP `execute_luau` runs in a different Luau VM than game scripts — bridge with BindableFunctions

**Measured 2026-07-23** (native-substrate verification surface bring-up, Studio 0.731).

`_G` (and `shared`) set by a LocalScript are **not visible** to the Studio MCP's
`execute_luau` command VM, and vice versa — the command runs in its own VM against the
same DataModel. A `_G.MyApi = ...` handshake therefore silently reads `nil` even though
the script ran fine. (Within the command VM itself, `_G` persists across successive
`execute_luau` calls — spike sessions rely on that.)

**Working bridge:** the game script publishes `BindableFunction`s (e.g. under a
`workspace.FacetScenarioAPI` folder) and the command VM calls `:Invoke(...)`.
Instances cross VMs; closures don't. Keep payloads JSON strings so no live tables
cross the boundary.

This is why `examples/gallery/scenarios/runner.luau` exposes list/steps/step/report/
reset/freezeEnv as BindableFunctions and only additionally sets `_G.FacetScenario`
for same-VM consumers.

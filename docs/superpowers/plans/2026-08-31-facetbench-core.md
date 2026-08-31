# FacetBench Core (Plan 1 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the FacetBench arena core: contracts, deterministic workload #1 (battle_hud), a self-validating Lune runner, the fixture framework, and a working Facet adapter — Phase 1 of the approved spec.

**Architecture:** FacetBench is a standalone git repo at `GameStudio/ui/FacetBench/` (sibling of Facet, outside Facet's gate scan roots). Workloads are framework-neutral data + seeded deterministic scripts; each framework contributes one small adapter translating that neutral spec idiomatically. A per-process Lune runner measures mount/step/unmount with warmup+sampling and CPU-yardstick normalization (patterns lifted from Facet's `tools/lune/bench.luau`). A toy `_fixture` framework with constructed, known cost validates the runner itself.

**Tech Stack:** Luau under Lune 0.10.4 (rokit-pinned), StyLua 2.5.2 (default config, tabs), `@lune/{fs,process,serde,task}`. Facet 0.10.0 consumed by relative require from the sibling checkout — never vendored.

**Spec:** `GameStudio/ui/Facet/docs/superpowers/specs/2026-08-31-facetbench-and-perf-fixes-design.md` (read it first; this plan implements its "Part 1 / Phase 1").

## Global Constraints

- All paths below are relative to `GameStudio/ui/FacetBench/` (repo root created in Task 1) unless prefixed `Facet/`.
- FacetBench is its own git repo; every commit in this plan is a FacetBench commit (except none — no Facet changes are allowed in this plan).
- Toolchain pins (copy verbatim): `lune = "lune-org/lune@0.10.4"`, `stylua = "JohnnyMorganz/StyLua@2.5.2"`, StyLua default config (tabs; no `.stylua.toml`).
- License: MIT for FacetBench; vendored frameworks (later plans) keep their upstream LICENSE files.
- Workload files must not import any framework. Adapters must not import each other. Facet is required in place (`require("../../../Facet/src")`), never copied.
- Determinism: every random choice flows through the seeded PRNG (`runner/lune/lib/prng.luau`); no wall-clock, no `math.random`.
- Benchmark defaults: `WARMUP = 50`, `SAMPLES = 1500` (Facet bench parity); tests override with small values via arguments, never by editing constants.
- Lune concurrency: children run **sequentially** (standing trap: >3 concurrent lune runs die silently).
- Formatting gate: `stylua --check .` must pass before every commit.
- Test gate: `lune run tests/run` must pass before every commit. New spec files are registered in the list inside `tests/run.luau`.
- Machine-generated test/bench output goes to `artifacts/` (gitignored). `results/` is reserved for deliberately committed baseline runs (Phase 4, not this plan).

---

### Task 1: Repo scaffold + test harness skeleton

**Files:**
- Create: `rokit.toml`, `.gitignore`, `LICENSE`, `README.md`, `tests/run.luau`
- Create (dirs): `frameworks/_fixture/`, `workloads/`, `runner/lune/lib/`, `results/`, `tools/`, `tests/`, `artifacts/`

**Interfaces:**
- Produces: repo root; `tests/run.luau` with a `SPECS` list later tasks append to (exact name `SPECS`).

- [ ] **Step 1: Create the repo and directories**

```bash
mkdir -p "/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/FacetBench"
cd "/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/FacetBench"
git init
mkdir -p frameworks/_fixture workloads runner/lune/lib results tools tests artifacts
```

- [ ] **Step 2: Write `rokit.toml`, `.gitignore`, `LICENSE`, `README.md`**

`rokit.toml`:
```toml
[tools]
lune = "lune-org/lune@0.10.4"
stylua = "JohnnyMorganz/StyLua@2.5.2"
```

`.gitignore`:
```
artifacts/
.DS_Store
```

`LICENSE` (MIT, full text):
```
MIT License

Copyright (c) 2026 FacetBench contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

`README.md`:
```markdown
# FacetBench

A contributable performance arena for Roblox Luau declarative UI frameworks.
Workloads are framework-neutral, seeded, and deterministic; each framework
participates through one small idiomatic adapter. Headless runs use Lune;
live runs use Roblox Studio.

Status: under construction (Phase 1). See CONTRIBUTING.md (coming) before
adding a framework or workload.

## Quickstart

    rokit install
    lune run tests/run
```

- [ ] **Step 3: Verify the toolchain**

```bash
rokit install
lune --version    # expect: lune 0.10.4
stylua --version  # expect: stylua 2.5.2
```

- [ ] **Step 4: Write the test harness skeleton `tests/run.luau`**

```lua
--!strict
-- FacetBench test harness. Each spec file is a module that runs its
-- assertions at require time and returns true. Register new specs in SPECS.

local SPECS: { string } = {
	-- "./prng.spec" etc. — appended by later tasks
}

local failures = 0
for _, path in SPECS do
	local ok, err = pcall(require, path)
	if ok then
		print(`PASS {path}`)
	else
		failures += 1
		print(`FAIL {path}: {err}`)
	end
end

if failures > 0 then
	error(`{failures} spec file(s) failed`)
end
print(`FacetBench tests: OK ({#SPECS} spec files)`)
```

- [ ] **Step 5: Run harness + formatter to verify green on empty**

```bash
lune run tests/run    # expect: FacetBench tests: OK (0 spec files)
stylua --check .      # expect: exit 0
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: FacetBench scaffold (rokit pins, MIT, test harness)"
```

---

### Task 2: Deterministic PRNG + stats

**Files:**
- Create: `runner/lune/lib/prng.luau`, `runner/lune/lib/stats.luau`
- Test: `tests/prng.spec.luau`, `tests/stats.spec.luau`
- Modify: `tests/run.luau` (register both specs in `SPECS`)

**Interfaces:**
- Produces: `Prng.new(seed: number)` → object with `:next(): number` in [0,1), `:nextInt(min: number, max: number): number` inclusive, `:pick<T>(list: {T}): T`.
- Produces: `stats.percentile(sorted: {number}, p: number): number`; `stats.summarize(samples: {number}) -> { p50: number, p95: number, p99: number }` (sorts a clone; input untouched).

- [ ] **Step 1: Write the failing tests**

`tests/prng.spec.luau`:
```lua
--!strict
local Prng = require("../runner/lune/lib/prng")

-- same seed => identical stream
local a = Prng.new(42)
local b = Prng.new(42)
for _ = 1, 50 do
	local va = a:next()
	assert(va == b:next(), "same seed must give identical stream")
	assert(va >= 0 and va < 1, "next() must be in [0,1)")
end

-- different seeds diverge somewhere in the first 10 draws
local c = Prng.new(43)
local d = Prng.new(44)
local diverged = false
for _ = 1, 10 do
	if c:next() ~= d:next() then
		diverged = true
	end
end
assert(diverged, "different seeds must diverge")

-- nextInt bounds + determinism
local e = Prng.new(7)
local f = Prng.new(7)
for _ = 1, 200 do
	local v = e:nextInt(3, 9)
	assert(v == f:nextInt(3, 9), "nextInt must be deterministic")
	assert(v >= 3 and v <= 9 and v == math.floor(v), "nextInt out of bounds")
end

-- pick stays inside the list
local g = Prng.new(1)
local list = { "x", "y", "z" }
for _ = 1, 50 do
	local v = g:pick(list)
	assert(v == "x" or v == "y" or v == "z", "pick left the list")
end

return true
```

`tests/stats.spec.luau`:
```lua
--!strict
local stats = require("../runner/lune/lib/stats")

local sorted = table.create(100)
for i = 1, 100 do
	sorted[i] = i
end
assert(stats.percentile(sorted, 0.50) == 50, "p50 of 1..100 must be 50")
assert(stats.percentile(sorted, 0.95) == 95, "p95 of 1..100 must be 95")
assert(stats.percentile(sorted, 0.99) == 99, "p99 of 1..100 must be 99")
assert(stats.percentile({ 5 }, 0.5) == 5, "single sample")

local unsorted = { 3, 1, 2 }
local s = stats.summarize(unsorted)
assert(s.p50 == 2 and s.p95 == 3 and s.p99 == 3, "summarize must sort a clone")
assert(unsorted[1] == 3, "summarize must not mutate its input")

return true
```

- [ ] **Step 2: Register specs and run to verify they fail**

In `tests/run.luau` set:
```lua
local SPECS: { string } = {
	"./prng.spec",
	"./stats.spec",
}
```
Run: `lune run tests/run` — expect both FAIL (module not found).

- [ ] **Step 3: Implement `runner/lune/lib/prng.luau`**

```lua
--!strict
-- Deterministic 32-bit LCG (Numerical Recipes constants). All benchmark
-- randomness flows through this; never math.random or the clock.
local Prng = {}
Prng.__index = Prng

local M = 2 ^ 32
local A = 1664525
local C = 1013904223

export type Prng = typeof(setmetatable({} :: { state: number }, Prng))

function Prng.new(seed: number): Prng
	assert(seed == math.floor(seed) and seed >= 0, "seed must be a non-negative integer")
	return setmetatable({ state = seed % M }, Prng)
end

function Prng.next(self: Prng): number
	self.state = (A * self.state + C) % M
	return self.state / M
end

function Prng.nextInt(self: Prng, min: number, max: number): number
	assert(max >= min, "nextInt: max < min")
	return min + math.floor(self:next() * (max - min + 1))
end

function Prng.pick<T>(self: Prng, list: { T }): T
	return list[self:nextInt(1, #list)]
end

return Prng
```

- [ ] **Step 4: Implement `runner/lune/lib/stats.luau`**

```lua
--!strict
local stats = {}

-- Same percentile convention as Facet's tools/lune/bench.luau.
function stats.percentile(sorted: { number }, p: number): number
	local idx = math.max(1, math.ceil(p * #sorted))
	return sorted[idx]
end

function stats.summarize(samples: { number }): { p50: number, p95: number, p99: number }
	local sorted = table.clone(samples)
	table.sort(sorted)
	return {
		p50 = stats.percentile(sorted, 0.50),
		p95 = stats.percentile(sorted, 0.95),
		p99 = stats.percentile(sorted, 0.99),
	}
end

return stats
```

- [ ] **Step 5: Run tests to verify pass, then commit**

```bash
lune run tests/run   # expect: PASS ./prng.spec, PASS ./stats.spec
stylua --check .
git add -A && git commit -m "feat: seeded PRNG + percentile stats with specs"
```

---

### Task 3: Scene/step contracts + stable JSON + battle_hud workload

**Files:**
- Create: `runner/lune/lib/scene.luau`, `runner/lune/lib/stable_json.luau`, `workloads/battle_hud.luau`, `workloads/init.luau`, `tests/helpers.luau`
- Test: `tests/scene.spec.luau`, `tests/battle_hud.spec.luau`
- Modify: `tests/run.luau` (register)

**Interfaces:**
- Produces (types in `scene.luau`, consumed by every adapter and runner task):

```lua
export type StateRef = { ref: string }          -- prop bound to a declared state
export type ItemRef = { item: string }          -- prop bound to a field of a list item
export type PropValue = number | string | boolean | StateRef | ItemRef
export type SceneNode = {
	kind: "panel" | "label" | "image" | "bar" | "list",
	id: string,                                  -- unique across the scene
	direction: ("vertical" | "horizontal")?,     -- panel only (default "vertical")
	props: { [string]: PropValue }?,             -- label: text/textSize; image: image; bar: value
	children: { SceneNode }?,                    -- panel only
	itemsState: string?,                         -- list only: state id holding { Item }
	template: SceneNode?,                        -- list only: row template; ItemRefs legal here only
}
export type Item = { key: string, [string]: any }
export type SceneSpec = { state: { [string]: any }, root: SceneNode }
export type Step =
	{ kind: "setState", id: string, value: any }
	| { kind: "updateItem", listState: string, key: string, field: string, value: any }
	| { kind: "addItem", listState: string, item: Item }
	| { kind: "removeItem", listState: string, key: string }
	| { kind: "reorder", listState: string, order: { string } }
	| { kind: "noop" }
```

- Produces: `scene.validate(spec: SceneSpec)` (errors with a message on any violation; returns true), `scene.validateSteps(spec: SceneSpec, steps: { Step })` (same; checks refs exist, list ops target list-backing states — note it validates against the INITIAL state only, so add/remove keys are shape-checked, not existence-checked).
- Produces: `stable_json.encode(value: any): string` — deterministic JSON: object keys sorted, numbers via `%.10g`, errors on functions/cycles.
- Produces: workload module shape (every `workloads/*.luau` returns this; `workloads/init.luau` is the registry `{ [name]: () -> Workload }`):

```lua
export type Workload = {
	name: string,
	requires: { string },                        -- capability keys, e.g. { "reactive", "keyedList" }
	sizes: { S: number, M: number, L: number },  -- workload-defined magnitude
	build: (size: "S" | "M" | "L", rng: any) -> SceneSpec,
	script: (size: "S" | "M" | "L", rng: any) -> { Step },
}
```

- [ ] **Step 1: Write `tests/helpers.luau` (deepEqual used by many specs)**

```lua
--!strict
local helpers = {}

function helpers.deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a :: { [any]: any } do
		if not helpers.deepEqual(v, (b :: { [any]: any })[k]) then
			return false
		end
	end
	for k in b :: { [any]: any } do
		if (a :: { [any]: any })[k] == nil then
			return false
		end
	end
	return true
end

return helpers
```

- [ ] **Step 2: Write the failing tests**

`tests/scene.spec.luau`:
```lua
--!strict
local scene = require("../runner/lune/lib/scene")
local stable_json = require("../runner/lune/lib/stable_json")

local good: scene.SceneSpec = {
	state = {
		hp = 0.5,
		units = { { key = "u1", hp = 1 } },
	},
	root = {
		kind = "panel",
		id = "Root",
		children = {
			{ kind = "bar", id = "Hp", props = { value = { ref = "hp" } } },
			{
				kind = "list",
				id = "Units",
				itemsState = "units",
				template = {
					kind = "panel",
					id = "Row",
					children = {
						{ kind = "bar", id = "RowHp", props = { value = { item = "hp" } } },
					},
				},
			},
		},
	},
}
assert(scene.validate(good) == true, "good spec must validate")

local function mustFail(mutate: (any) -> ())
	local function deepCopy(t: any): any
		if type(t) ~= "table" then
			return t
		end
		local out = {}
		for k, v in t :: { [any]: any } do
			out[k] = deepCopy(v)
		end
		return out
	end
	local bad = deepCopy(good)
	mutate(bad)
	local ok = pcall(scene.validate, bad)
	assert(not ok, "expected validation failure")
end

mustFail(function(bad)
	bad.root.children[1].props.value = { ref = "missing" } -- unknown state ref
end)
mustFail(function(bad)
	bad.root.children[2].itemsState = "hp" -- list backed by non-array state
end)
mustFail(function(bad)
	bad.root.children[1].id = "Root" -- duplicate id
end)
mustFail(function(bad)
	bad.root.children[1].kind = "sparkle" -- unknown kind
end)
mustFail(function(bad)
	bad.root.props = { x = { item = "hp" } } -- ItemRef outside a template
end)

-- steps
assert(scene.validateSteps(good, {
	{ kind = "setState", id = "hp", value = 0.25 },
	{ kind = "updateItem", listState = "units", key = "u1", field = "hp", value = 0.5 },
	{ kind = "addItem", listState = "units", item = { key = "u2", hp = 1 } },
	{ kind = "removeItem", listState = "units", key = "u2" },
	{ kind = "reorder", listState = "units", order = { "u1" } },
	{ kind = "noop" },
}) == true)
local ok2 = pcall(scene.validateSteps, good, { { kind = "setState", id = "nope", value = 1 } })
assert(not ok2, "setState on undeclared state must fail")
local ok3 = pcall(scene.validateSteps, good, { { kind = "addItem", listState = "hp", item = { key = "x" } } })
assert(not ok3, "list op on non-list state must fail")

-- stable_json
local s1 = stable_json.encode({ b = 2, a = 1, nested = { z = true, y = "s" } })
local s2 = stable_json.encode({ a = 1, nested = { y = "s", z = true }, b = 2 })
assert(s1 == s2, "stable_json must be key-order independent")
assert(s1 == '{"a":1,"b":2,"nested":{"y":"s","z":true}}', `unexpected encoding: {s1}`)
assert(stable_json.encode({ 1, 2, 3 }) == "[1,2,3]", "arrays encode positionally")
local okF = pcall(stable_json.encode, { f = function() end })
assert(not okF, "functions must be rejected")

return true
```

`tests/battle_hud.spec.luau`:
```lua
--!strict
local Prng = require("../runner/lune/lib/prng")
local scene = require("../runner/lune/lib/scene")
local helpers = require("./helpers")
local workloads = require("../workloads/init")

local wl = workloads.battle_hud()
assert(wl.name == "battle_hud")
assert(wl.sizes.S == 100 and wl.sizes.M == 400 and wl.sizes.L == 1000)

-- determinism: same seed => identical spec and script
local specA = wl.build("S", Prng.new(1))
local specB = wl.build("S", Prng.new(1))
assert(helpers.deepEqual(specA, specB), "build must be deterministic")
local stepsA = wl.script("S", Prng.new(2))
local stepsB = wl.script("S", Prng.new(2))
assert(helpers.deepEqual(stepsA, stepsB), "script must be deterministic")

-- spec validates; script validates against spec
assert(scene.validate(specA) == true)
assert(scene.validateSteps(specA, stepsA) == true)

-- shape: unit count drives the units list
assert(#specA.state.units == 100, "S must have 100 units")
assert(#wl.build("L", Prng.new(1)).state.units == 1000, "L must have 1000 units")

-- script length and exact kind mix (pattern of 20 x 30 repeats)
assert(#stepsA == 600, "script must have 600 steps")
local counts: { [string]: number } = {}
for _, st in stepsA do
	counts[st.kind] = (counts[st.kind] or 0) + 1
end
assert(counts.updateItem == 420, "12 hp + 2 facing per 20-slot pattern => 420")
assert((counts.addItem or 0) + (counts.removeItem or 0) == 90, "damage adds+removes = 3 per pattern")
assert(counts.setState == 60, "2 squad writes per pattern => 60")
assert(counts.noop == 30, "1 noop per pattern => 30")

return true
```

- [ ] **Step 3: Register both specs in `SPECS`, run, verify FAIL**

Run: `lune run tests/run` — expect FAIL (modules not found).

- [ ] **Step 4: Implement `runner/lune/lib/stable_json.luau`**

```lua
--!strict
local stable_json = {}

local function isArray(t: { [any]: any }): boolean
	local n = 0
	for _ in t do
		n += 1
	end
	return n == #t
end

local function encodeValue(v: any, seen: { [any]: boolean }, out: { string })
	local tv = type(v)
	if tv == "number" then
		table.insert(out, string.format("%.10g", v))
	elseif tv == "string" then
		table.insert(out, string.format("%q", v))
	elseif tv == "boolean" then
		table.insert(out, tostring(v))
	elseif tv == "nil" then
		table.insert(out, "null")
	elseif tv == "table" then
		assert(not seen[v], "stable_json: cycle detected")
		seen[v] = true
		local t = v :: { [any]: any }
		if isArray(t) then
			table.insert(out, "[")
			for i, item in ipairs(t) do
				if i > 1 then
					table.insert(out, ",")
				end
				encodeValue(item, seen, out)
			end
			table.insert(out, "]")
		else
			local keys: { string } = {}
			for k in t do
				assert(type(k) == "string", "stable_json: non-string key")
				table.insert(keys, k)
			end
			table.sort(keys)
			table.insert(out, "{")
			for i, k in keys do
				if i > 1 then
					table.insert(out, ",")
				end
				table.insert(out, string.format("%q", k) .. ":")
				encodeValue(t[k], seen, out)
			end
			table.insert(out, "}")
		end
		seen[v] = nil
	else
		error(`stable_json: unsupported type {tv}`)
	end
end

function stable_json.encode(value: any): string
	local out: { string } = {}
	encodeValue(value, {}, out)
	return table.concat(out)
end

return stable_json
```
Note: `string.format("%q", s)` in Luau escapes newlines as `\` + newline, not `\n`. If the spec's exact-string assertion fails only on quoting, replace `%q` with an explicit escaper (backslash, quote, `\n`, `\r`, `\t`, control chars) — keep the test's expected string authoritative.

- [ ] **Step 5: Implement `runner/lune/lib/scene.luau`**

Validation rules (implement exactly; each failure `error()`s with the rule name):
- node kinds limited to the closed set; `id` required, unique scene-wide (templates included).
- `children` only on `panel`; `itemsState`/`template` only on `list`, both required there; `direction` only on `panel`, `"vertical"`/`"horizontal"` only.
- Every `StateRef.ref` names a declared `spec.state` key; every list's `itemsState` names a state whose value is an array of tables each carrying a string `key`, unique within the array.
- `ItemRef` legal only inside a `template` subtree.
- `validateSteps`: `setState.id` declared; `updateItem/addItem/removeItem/reorder` `listState` must be some list node's `itemsState`; `addItem.item.key` is a string; `reorder.order` is an array of strings.

```lua
--!strict
local scene = {}

-- (types exactly as in the Interfaces block above)

local NODE_KINDS = { panel = true, label = true, image = true, bar = true, list = true }

local function walk(node: any, fn: (any, boolean) -> (), inTemplate: boolean)
	fn(node, inTemplate)
	if node.children then
		for _, child in node.children do
			walk(child, fn, inTemplate)
		end
	end
	if node.template then
		walk(node.template, fn, true)
	end
end

function scene.validate(spec: any): boolean
	assert(type(spec) == "table" and type(spec.state) == "table" and type(spec.root) == "table", "spec shape")
	local ids: { [string]: boolean } = {}
	local listStates: { [string]: boolean } = {}
	walk(spec.root, function(node, inTemplate)
		assert(NODE_KINDS[node.kind], `unknown kind {tostring(node.kind)}`)
		assert(type(node.id) == "string", "id required")
		assert(not ids[node.id], `duplicate id {node.id}`)
		ids[node.id] = true
		assert(node.children == nil or node.kind == "panel", "children only on panel")
		assert(node.direction == nil or node.kind == "panel", "direction only on panel")
		if node.direction ~= nil then
			assert(node.direction == "vertical" or node.direction == "horizontal", "bad direction")
		end
		if node.kind == "list" then
			assert(type(node.itemsState) == "string", "list needs itemsState")
			assert(type(node.template) == "table", "list needs template")
			local items = spec.state[node.itemsState]
			assert(type(items) == "table", `itemsState {node.itemsState} not declared`)
			local seenKeys: { [string]: boolean } = {}
			local n = 0
			for _ in items do
				n += 1
			end
			assert(n == #items, `itemsState {node.itemsState} must be an array`)
			for _, item in ipairs(items) do
				assert(type(item) == "table" and type(item.key) == "string", "items need string key")
				assert(not seenKeys[item.key], `duplicate item key {item.key}`)
				seenKeys[item.key] = true
			end
			listStates[node.itemsState] = true
		else
			assert(node.itemsState == nil and node.template == nil, "itemsState/template only on list")
		end
		if node.props then
			for name, value in node.props :: { [string]: any } do
				if type(value) == "table" then
					if value.ref ~= nil then
						assert(spec.state[value.ref] ~= nil, `unknown state ref {tostring(value.ref)} in {node.id}.{name}`)
					elseif value.item ~= nil then
						assert(inTemplate, `ItemRef outside template in {node.id}.{name}`)
					else
						error(`bad prop table in {node.id}.{name}`)
					end
				end
			end
		end
	end, false)
	scene._lastListStates = listStates -- internal: reused by validateSteps
	return true
end

function scene.validateSteps(spec: any, steps: { any }): boolean
	scene.validate(spec)
	local listStates = scene._lastListStates :: { [string]: boolean }
	for i, st in steps do
		if st.kind == "setState" then
			assert(spec.state[st.id] ~= nil, `step {i}: setState unknown id {tostring(st.id)}`)
		elseif st.kind == "updateItem" or st.kind == "removeItem" then
			assert(listStates[st.listState], `step {i}: {st.kind} on non-list state`)
			assert(type(st.key) == "string", `step {i}: key must be string`)
		elseif st.kind == "addItem" then
			assert(listStates[st.listState], `step {i}: addItem on non-list state`)
			assert(type(st.item) == "table" and type(st.item.key) == "string", `step {i}: bad item`)
		elseif st.kind == "reorder" then
			assert(listStates[st.listState], `step {i}: reorder on non-list state`)
			assert(type(st.order) == "table", `step {i}: order required`)
			for _, k in st.order do
				assert(type(k) == "string", `step {i}: order entries must be strings`)
			end
		elseif st.kind ~= "noop" then
			error(`step {i}: unknown kind {tostring(st.kind)}`)
		end
	end
	return true
end

return scene
```
(Also export the type declarations from the Interfaces block at the top of the file.)

- [ ] **Step 6: Implement `workloads/battle_hud.luau` + `workloads/init.luau`**

battle_hud, sizes S=100 / M=400 / L=1000 units. Scene: root vertical panel containing (a) a horizontal squad strip of 4 labels bound to `squad1..squad4`, (b) the `units` list — each row a horizontal panel with name label (static item field), hp `bar` (`{item="hp"}`), status `image` (`{item="icon"}`), facing label (`{item="facing"}`), (c) a `damage` list of floating damage labels (starts empty), (d) a `blips` list of minimap bars (`size/10` entries, `x` field). Script: 30 repeats of a fixed 20-slot pattern — slots 1-12 `updateItem` hp on an rng-chosen unit; slots 13-15 damage traffic (addItem `{ key = "d"..n, text = "-"..dmg }`, and once the live damage queue exceeds `size/10` the slot becomes a removeItem of the oldest); slots 16-17 `setState` on an rng-chosen squad; slots 18-19 `updateItem` facing on an rng-chosen unit; slot 20 `noop`. All choices via `rng`.

```lua
--!strict
local function build(size: "S" | "M" | "L", rng: any)
	local n = if size == "S" then 100 elseif size == "M" then 400 else 1000
	local units = table.create(n)
	local icons = { "rbxassetid://101", "rbxassetid://102", "rbxassetid://103" }
	for i = 1, n do
		units[i] = {
			key = `u{i}`,
			name = `Unit {i}`,
			hp = 1,
			icon = rng:pick(icons),
			facing = rng:nextInt(0, 359),
		}
	end
	local blips = table.create(n // 10)
	for i = 1, n // 10 do
		blips[i] = { key = `b{i}`, x = rng:next() }
	end
	local state: { [string]: any } = {
		units = units,
		damage = {},
		blips = blips,
		squad1 = 0,
		squad2 = 0,
		squad3 = 0,
		squad4 = 0,
	}
	local squadLabels = {}
	for s = 1, 4 do
		squadLabels[s] = {
			kind = "label" :: "label",
			id = `Squad{s}`,
			props = { text = { ref = `squad{s}` }, textSize = 14 },
		}
	end
	local root = {
		kind = "panel" :: "panel",
		id = "Root",
		direction = "vertical" :: "vertical",
		children = {
			{ kind = "panel", id = "SquadStrip", direction = "horizontal", children = squadLabels },
			{
				kind = "list",
				id = "Units",
				itemsState = "units",
				template = {
					kind = "panel",
					id = "UnitRow",
					direction = "horizontal",
					children = {
						{ kind = "label", id = "UnitName", props = { text = { item = "name" }, textSize = 12 } },
						{ kind = "bar", id = "UnitHp", props = { value = { item = "hp" } } },
						{ kind = "image", id = "UnitIcon", props = { image = { item = "icon" } } },
						{ kind = "label", id = "UnitFacing", props = { text = { item = "facing" }, textSize = 10 } },
					},
				},
			},
			{
				kind = "list",
				id = "Damage",
				itemsState = "damage",
				template = { kind = "label", id = "DmgText", props = { text = { item = "text" }, textSize = 16 } },
			},
			{
				kind = "list",
				id = "Blips",
				itemsState = "blips",
				template = { kind = "bar", id = "Blip", props = { value = { item = "x" } } },
			},
		},
	}
	return { state = state, root = root }
end

local function script(size: "S" | "M" | "L", rng: any)
	local n = if size == "S" then 100 elseif size == "M" then 400 else 1000
	local damageCap = n // 10
	local steps = {}
	local live: { string } = {} -- FIFO of live damage keys
	local nextDmg = 0
	for _ = 1, 30 do
		for slot = 1, 20 do
			if slot <= 12 then
				table.insert(steps, {
					kind = "updateItem",
					listState = "units",
					key = `u{rng:nextInt(1, n)}`,
					field = "hp",
					value = rng:next(),
				})
			elseif slot <= 15 then
				if #live > damageCap then
					table.insert(steps, { kind = "removeItem", listState = "damage", key = table.remove(live, 1) })
				else
					nextDmg += 1
					local key = `d{nextDmg}`
					table.insert(live, key)
					table.insert(steps, {
						kind = "addItem",
						listState = "damage",
						item = { key = key, text = `-{rng:nextInt(1, 999)}` },
					})
				end
			elseif slot <= 17 then
				table.insert(steps, { kind = "setState", id = `squad{rng:nextInt(1, 4)}`, value = rng:nextInt(0, 100) })
			elseif slot <= 19 then
				table.insert(steps, {
					kind = "updateItem",
					listState = "units",
					key = `u{rng:nextInt(1, n)}`,
					field = "facing",
					value = rng:nextInt(0, 359),
				})
			else
				table.insert(steps, { kind = "noop" })
			end
		end
	end
	return steps
end

return function()
	return {
		name = "battle_hud",
		requires = { "reactive", "keyedList" },
		sizes = { S = 100, M = 400, L = 1000 },
		build = build,
		script = script,
	}
end
```

`workloads/init.luau`:
```lua
--!strict
-- Workload registry. Contributors add one line per workload.
return {
	battle_hud = require("./battle_hud"),
}
```

- [ ] **Step 7: Run tests to verify pass; fix the exact-count assertions if the damage FIFO mix differs**

Run: `lune run tests/run`. The `addItem+removeItem == 90` and `updateItem == 420` counts are exact by construction; if a count assertion fails, the generator drifted from the 20-slot pattern — fix the generator, not the test.

- [ ] **Step 8: Commit**

```bash
stylua --check .
git add -A && git commit -m "feat: scene/step contracts, stable JSON, battle_hud workload"
```

---

### Task 4: Adapter contract, fixture framework, conformance checker

**Files:**
- Create: `runner/lune/lib/adapter.luau`, `runner/lune/lib/conformance.luau`, `frameworks/_fixture/adapter.luau`, `frameworks/init.luau`, `tools/check_adapters.luau`
- Test: `tests/fixture_adapter.spec.luau`, `tests/conformance.spec.luau`
- Modify: `tests/run.luau` (register)

**Interfaces:**
- Produces (types in `adapter.luau`; every framework folder must satisfy this):

```lua
export type Capabilities = { reactive: boolean?, keyedList: boolean?, headless: boolean?, styling: boolean? }
export type Adapter = {
	name: string,
	version: string,
	license: string,
	capabilities: Capabilities,
	mount: (spec: any, target: any?) -> any,      -- target nil = headless; returns opaque handle
	applyStep: (handle: any, step: any) -> (),
	snapshot: (handle: any) -> string,            -- STABLE serialization of what is mounted
	liveCount: (handle: any) -> number,           -- live UI objects/rows; must be 0 after unmount
	unmount: (handle: any) -> (),
}
```
- Produces: `adapter.validateShape(a: any)` — asserts every field above with exact type; errors naming the missing/mistyped field.
- Produces: `conformance.check(a: Adapter)` — errors on any violation (see Step 4 for the exact checks).
- Produces: `frameworks/init.luau` registry `{ [name: string]: () -> Adapter }` with entry `_fixture`.
- Consumes: `scene` types, `stable_json.encode`, `Prng.new`, `workloads/init` (`battle_hud`).

- [ ] **Step 1: Write the failing tests**

`tests/fixture_adapter.spec.luau`:
```lua
--!strict
local Prng = require("../runner/lune/lib/prng")
local workloads = require("../workloads/init")
local frameworks = require("../frameworks/init")

local a = frameworks._fixture()
assert(a.name == "_fixture" and a.license == "MIT")
assert(a.capabilities.reactive and a.capabilities.keyedList and a.capabilities.headless)

local wl = workloads.battle_hud()
local spec = wl.build("S", Prng.new(1))
local steps = wl.script("S", Prng.new(2))

local h = a.mount(spec, nil)
assert(a.liveCount(h) > 100, "rows must count as live nodes")
local s1 = a.snapshot(h)
assert(type(s1) == "string" and #s1 > 0)

-- applying a step changes the snapshot; noop does not
a.applyStep(h, { kind = "setState", id = "squad1", value = 99 })
local s2 = a.snapshot(h)
assert(s2 ~= s1, "setState must change the snapshot")
a.applyStep(h, { kind = "noop" })
assert(a.snapshot(h) == s2, "noop must not change the snapshot")

-- list ops
a.applyStep(h, { kind = "addItem", listState = "damage", item = { key = "dx", text = "-5" } })
local s3 = a.snapshot(h)
assert(s3 ~= s2)
a.applyStep(h, { kind = "removeItem", listState = "damage", key = "dx" })
assert(a.snapshot(h) == s2, "add+remove must round-trip the snapshot")
a.applyStep(h, { kind = "updateItem", listState = "units", key = "u1", field = "hp", value = 0.25 })
assert(a.snapshot(h) ~= s2)

-- full script survives
for _, st in steps do
	a.applyStep(h, st)
end

a.unmount(h)
assert(a.liveCount(h) == 0, "liveCount must be 0 after unmount")

return true
```

`tests/conformance.spec.luau`:
```lua
--!strict
local conformance = require("../runner/lune/lib/conformance")
local frameworks = require("../frameworks/init")

-- the fixture passes
conformance.check(frameworks._fixture())

-- the checker BITES: each broken clone must fail
local function brokenClone(patch: (any) -> ())
	local base = frameworks._fixture()
	local bad = table.clone(base)
	patch(bad)
	local ok = pcall(conformance.check, bad)
	assert(not ok, "conformance failed to bite")
end

brokenClone(function(bad)
	bad.snapshot = nil -- missing field
end)
brokenClone(function(bad)
	local n = 0
	local real = bad.snapshot
	bad.snapshot = function(h)
		n += 1
		return real(h) .. tostring(n) -- nondeterministic snapshot
	end
end)
brokenClone(function(bad)
	local realUnmount = bad.unmount
	bad.unmount = function(h)
		realUnmount(h)
	end
	local realLive = bad.liveCount
	bad.liveCount = function(h)
		local v = realLive(h)
		return if v == 0 then 7 else v -- leaks after unmount
	end
end)

return true
```

- [ ] **Step 2: Register specs, run, verify FAIL**

Run: `lune run tests/run` — expect FAIL (modules not found).

- [ ] **Step 3: Implement `runner/lune/lib/adapter.luau` and `frameworks/_fixture/adapter.luau`**

`runner/lune/lib/adapter.luau`:
```lua
--!strict
local adapter = {}

-- (export the Capabilities/Adapter types exactly as in the Interfaces block)

local FIELDS = {
	{ name = "name", kind = "string" },
	{ name = "version", kind = "string" },
	{ name = "license", kind = "string" },
	{ name = "capabilities", kind = "table" },
	{ name = "mount", kind = "function" },
	{ name = "applyStep", kind = "function" },
	{ name = "snapshot", kind = "function" },
	{ name = "liveCount", kind = "function" },
	{ name = "unmount", kind = "function" },
}

function adapter.validateShape(a: any)
	assert(type(a) == "table", "adapter must be a table")
	for _, f in FIELDS do
		assert(type(a[f.name]) == f.kind, `adapter.{f.name} must be a {f.kind}`)
	end
end

return adapter
```

`frameworks/_fixture/adapter.luau` — a toy retained framework with CONSTRUCTED cost. Rules (the runner self-test in Task 7 depends on them):
- `mount` burns `MOUNT_UNITS_PER_NODE` per mounted node (rows count as their template node count).
- `applyStep`: `setState` burns 1 unit; every list op (`updateItem`/`addItem`/`removeItem`/`reorder`) burns 1 unit per CURRENT item of the touched list; `noop` burns nothing. So step cost scales linearly with list size — size L / size S p50 ratio must be ≈ 10 for battle_hud.

```lua
--!strict
local stable_json = require("../../runner/lune/lib/stable_json")

local BURN_SPIN = 40 -- inner iterations per cost unit; ratio-stable across machines

local function burn(units: number): number
	local acc = 0
	for i = 1, units * BURN_SPIN do
		acc += i % 7
	end
	return acc
end

local function countNodes(node: any): number
	local n = 1
	if node.children then
		for _, c in node.children do
			n += countNodes(c)
		end
	end
	if node.template then
		n += countNodes(node.template)
	end
	return n
end

local function deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t :: { [any]: any } do
		out[k] = deepCopy(v)
	end
	return out
end

local Fixture = {}

function Fixture.mount(spec: any, _target: any?): any
	local model = {
		state = deepCopy(spec.state),
		rootNodes = countNodes(spec.root),
		lists = {} :: { [string]: { any } }, -- listState -> array of row models
		rowNodes = 0,
	}
	local function walk(node: any)
		if node.kind == "list" then
			local rows = {}
			local perRow = countNodes(node.template)
			for _, item in model.state[node.itemsState] do
				table.insert(rows, { key = item.key, item = item, nodes = perRow })
				model.rowNodes += perRow
			end
			model.lists[node.itemsState] = rows
		end
		if node.children then
			for _, c in node.children do
				walk(c)
			end
		end
	end
	walk(spec.root)
	burn(model.rootNodes + model.rowNodes)
	return model
end

function Fixture.applyStep(model: any, step: any)
	if step.kind == "noop" then
		return
	elseif step.kind == "setState" then
		model.state[step.id] = step.value
		burn(1)
	else
		local rows = model.lists[step.listState]
		assert(rows, `fixture: unknown list {tostring(step.listState)}`)
		if step.kind == "updateItem" then
			for _, row in rows do
				if row.key == step.key then
					row.item = deepCopy(row.item)
					row.item[step.field] = step.value
					break
				end
			end
		elseif step.kind == "addItem" then
			table.insert(rows, { key = step.item.key, item = deepCopy(step.item), nodes = 1 })
		elseif step.kind == "removeItem" then
			for i, row in rows do
				if row.key == step.key then
					table.remove(rows, i)
					break
				end
			end
		elseif step.kind == "reorder" then
			local byKey = {}
			for _, row in rows do
				byKey[row.key] = row
			end
			local reordered = {}
			for _, key in step.order do
				table.insert(reordered, byKey[key])
			end
			model.lists[step.listState] = reordered
			rows = reordered
		end
		burn(#rows)
	end
end

function Fixture.snapshot(model: any): string
	local view = { state = model.state, lists = {} :: { [string]: { any } } }
	for name, rows in model.lists do
		local keys = {}
		for _, row in rows do
			table.insert(keys, { key = row.key, item = row.item })
		end
		view.lists[name] = keys
	end
	return stable_json.encode(view)
end

function Fixture.liveCount(model: any): number
	if model.disposed then
		return 0
	end
	local n = model.rootNodes
	for _, rows in model.lists do
		for _, row in rows do
			n += row.nodes
		end
	end
	return n
end

function Fixture.unmount(model: any)
	model.disposed = true
	model.lists = {}
end

return {
	name = "_fixture",
	version = "1.0.0",
	license = "MIT",
	capabilities = { reactive = true, keyedList = true, headless = true, styling = true },
	mount = Fixture.mount,
	applyStep = Fixture.applyStep,
	snapshot = Fixture.snapshot,
	liveCount = Fixture.liveCount,
	unmount = Fixture.unmount,
}
```
Note: `liveCount` recomputes from `rowNodes`-style walk, so keep `model.rowNodes` only for mount burn; live counting walks `model.lists` (as written above) plus `rootNodes` — after `addItem` the new row counts 1 node. That asymmetry is fine; only monotone sanity and the 0-after-unmount rule are contractual.

- [ ] **Step 4: Implement `runner/lune/lib/conformance.luau`, `frameworks/init.luau`, `tools/check_adapters.luau`**

`runner/lune/lib/conformance.luau` — exact checks, in order:
1. `adapter.validateShape(a)`.
2. Headless determinism (only if `a.capabilities.headless`): build `battle_hud` spec with `Prng.new(1)` twice; `mount` each; `snapshot` equal, `liveCount() > 0` and equal.
3. Replay the first 100 steps of `script("S", Prng.new(2))` into both mounts; snapshots equal after every 25 steps.
4. `unmount` both; `liveCount == 0` for both.
5. If not headless: only shape is checked (record `"shape-only"` in the return note).

```lua
--!strict
local adapterLib = require("./adapter")
local Prng = require("./prng")
local workloads = require("../../../workloads/init")

local conformance = {}

function conformance.check(a: any): string
	adapterLib.validateShape(a)
	if not a.capabilities.headless then
		return "shape-only (not headless)"
	end
	local wl = workloads.battle_hud()
	local specA = wl.build("S", Prng.new(1))
	local specB = wl.build("S", Prng.new(1))
	local ha = a.mount(specA, nil)
	local hb = a.mount(specB, nil)
	assert(a.snapshot(ha) == a.snapshot(hb), "mount snapshot must be deterministic")
	assert(a.liveCount(ha) > 0, "mounted adapter must report live nodes")
	assert(a.liveCount(ha) == a.liveCount(hb), "liveCount must be deterministic")
	local steps = wl.script("S", Prng.new(2))
	for i = 1, 100 do
		a.applyStep(ha, steps[i])
		a.applyStep(hb, steps[i])
		if i % 25 == 0 then
			assert(a.snapshot(ha) == a.snapshot(hb), `snapshot diverged at step {i}`)
		end
	end
	a.unmount(ha)
	a.unmount(hb)
	assert(a.liveCount(ha) == 0 and a.liveCount(hb) == 0, "liveCount must be 0 after unmount")
	return "ok"
end

return conformance
```

`frameworks/init.luau`:
```lua
--!strict
-- Framework registry. Contributors add one line per framework folder.
return {
	_fixture = function()
		return require("./_fixture/adapter")
	end,
}
```

`tools/check_adapters.luau` (CLI producer for CI):
```lua
--!strict
local conformance = require("../runner/lune/lib/conformance")
local frameworks = require("../frameworks/init")

local names = {}
for name in frameworks :: { [string]: any } do
	table.insert(names, name)
end
table.sort(names)
for _, name in names do
	local verdict = conformance.check((frameworks :: any)[name]())
	print(`adapter {name}: {verdict}`)
end
print(`check_adapters: {#names} adapter(s) conformant`)
```

- [ ] **Step 5: Run tests to verify pass**

```bash
lune run tests/run              # both new specs PASS
lune run tools/check_adapters   # adapter _fixture: ok
```

- [ ] **Step 6: Commit**

```bash
stylua --check .
git add -A && git commit -m "feat: adapter contract, fixture framework, biting conformance checker"
```

---

### Task 5: Yardstick + single-run harness (run_one)

**Files:**
- Create: `runner/lune/lib/yardstick.luau`, `runner/lune/run_one_lib.luau`, `runner/lune/run_one.luau`
- Test: `tests/run_one.spec.luau`
- Modify: `tests/run.luau` (register)

**Interfaces:**
- Produces: `yardstick.measure(): number` — p95 ms of a fixed pure-CPU loop (200 reps of a 20k-iteration arithmetic loop).
- Produces: `run_one_lib.run(opts) -> Row` with

```lua
export type RunOpts = {
	framework: string,
	workload: string,
	size: "S" | "M" | "L",
	seed: number?,          -- default 1
	samples: number?,       -- default 1500
	warmup: number?,        -- default 50
	frameworksRegistry: any?, -- test injection; default require("../../frameworks/init")
	workloadsRegistry: any?,  -- test injection; default require("../../workloads/init")
}
export type Row = {
	framework: string, version: string, workload: string, size: string,
	status: "ok" | "unsupported" | "live-only" | "error",
	note: string?,          -- unsupported: missing caps; error: message
	meta: { seed: number, samples: number, warmup: number },
	metrics: {              -- present only when status == "ok"
		mountMs: number, stepP50Ms: number, stepP95Ms: number, stepP99Ms: number,
		stepP50Norm: number, stepP95Norm: number, unmountMs: number,
		heapNetKb: number, gcSwingKb: number, yardstickDriftPct: number,
	}?,
}
```
- Produces: CLI `lune run runner/lune/run_one <framework> <workload> <size> [seed] [samples] [warmup]` printing exactly one stable-JSON `Row` on stdout.
- Consumes: registries, `Prng`, `stats.summarize`, `scene.validate/validateSteps`, `stable_json.encode`.

- [ ] **Step 1: Write the failing test `tests/run_one.spec.luau`**

```lua
--!strict
local run_one = require("../runner/lune/run_one_lib")

-- ok path on the fixture
local row = run_one.run({ framework = "_fixture", workload = "battle_hud", size = "S", seed = 1, samples = 120, warmup = 10 })
assert(row.status == "ok", `expected ok, got {row.status} ({tostring(row.note)})`)
assert(row.framework == "_fixture" and row.workload == "battle_hud" and row.size == "S")
assert(row.version == "1.0.0")
local m = assert(row.metrics)
assert(m.mountMs > 0, "mount must take measurable time (fixture burns on mount)")
assert(m.stepP50Ms >= 0 and m.stepP95Ms >= m.stepP50Ms and m.stepP99Ms >= m.stepP95Ms)
assert(m.stepP50Norm > 0, "normalized p50 must exist")
assert(m.unmountMs >= 0)
assert(type(m.heapNetKb) == "number" and type(m.gcSwingKb) == "number")
assert(row.meta.samples == 120 and row.meta.warmup == 10 and row.meta.seed == 1)

-- unsupported path: adapter without keyedList
local stub = {
	name = "stub", version = "0", license = "MIT",
	capabilities = { reactive = true, keyedList = false, headless = true },
	mount = function() return {} end, applyStep = function() end,
	snapshot = function() return "" end, liveCount = function() return 0 end,
	unmount = function() end,
}
local rowU = run_one.run({
	framework = "stub", workload = "battle_hud", size = "S",
	frameworksRegistry = { stub = function() return stub end },
})
assert(rowU.status == "unsupported" and rowU.metrics == nil)
assert(string.find(rowU.note :: string, "keyedList", 1, true), "note must name the missing capability")

-- live-only path
local stubLive = table.clone(stub)
stubLive.capabilities = { reactive = true, keyedList = true, headless = false }
local rowL = run_one.run({
	framework = "stubLive", workload = "battle_hud", size = "S",
	frameworksRegistry = { stubLive = function() return stubLive end },
})
assert(rowL.status == "live-only" and rowL.metrics == nil)

-- error path: mount blows up
local stubBoom = table.clone(stub)
stubBoom.capabilities = { reactive = true, keyedList = true, headless = true }
stubBoom.mount = function()
	error("boom")
end
local rowE = run_one.run({
	framework = "stubBoom", workload = "battle_hud", size = "S", samples = 10, warmup = 1,
	frameworksRegistry = { stubBoom = function() return stubBoom end },
})
assert(rowE.status == "error")
assert(string.find(rowE.note :: string, "boom", 1, true), "error note must carry the message")

return true
```

- [ ] **Step 2: Register spec, run, verify FAIL**

- [ ] **Step 3: Implement `runner/lune/lib/yardstick.luau`**

```lua
--!strict
-- Fixed pure-CPU reference loop. Timings are divided by this so results
-- from different machines / load conditions stay comparable (same idea as
-- Facet's zz-yardstick-cpu scenario).
local stats = require("./stats")

local yardstick = {}

function yardstick.measure(): number
	local samples = table.create(200)
	for i = 1, 200 do
		local t0 = os.clock()
		local acc = 0
		for j = 1, 20000 do
			acc += j % 13
			if acc > 1e9 then
				acc = 0
			end
		end
		samples[i] = (os.clock() - t0) * 1000
	end
	return stats.summarize(samples).p95
end

return yardstick
```

- [ ] **Step 4: Implement `runner/lune/run_one_lib.luau`**

```lua
--!strict
local Prng = require("./lib/prng")
local stats = require("./lib/stats")
local scene = require("./lib/scene")
local yardstick = require("./lib/yardstick")

local run_one_lib = {}

function run_one_lib.run(opts: any): any
	local frameworks = opts.frameworksRegistry or require("../../frameworks/init")
	local workloads = opts.workloadsRegistry or require("../workloads/init")
	local seed = opts.seed or 1
	local samplesN = opts.samples or 1500
	local warmupN = opts.warmup or 50

	local makeAdapter = frameworks[opts.framework]
	assert(makeAdapter, `unknown framework {opts.framework}`)
	local makeWorkload = workloads[opts.workload]
	assert(makeWorkload, `unknown workload {opts.workload}`)
	local a = makeAdapter()
	local wl = makeWorkload()

	local row: any = {
		framework = opts.framework,
		version = a.version,
		workload = wl.name,
		size = opts.size,
		meta = { seed = seed, samples = samplesN, warmup = warmupN },
	}

	local missing = {}
	for _, cap in wl.requires do
		if not a.capabilities[cap] then
			table.insert(missing, cap)
		end
	end
	if #missing > 0 then
		row.status = "unsupported"
		row.note = `missing capabilities: {table.concat(missing, ", ")}`
		return row
	end
	if not a.capabilities.headless then
		row.status = "live-only"
		return row
	end

	local ok, err = pcall(function()
		local spec = wl.build(opts.size, Prng.new(seed))
		local steps = wl.script(opts.size, Prng.new(seed + 1))
		scene.validate(spec)
		scene.validateSteps(spec, steps)

		local yardBefore = yardstick.measure()

		local t0 = os.clock()
		local handle = a.mount(spec, nil)
		local mountMs = (os.clock() - t0) * 1000

		for i = 1, warmupN do
			a.applyStep(handle, steps[(i - 1) % #steps + 1])
		end

		local samples = table.create(samplesN, 0)
		local every = math.max(samplesN // 10, 1)
		local heapFirst = gcinfo()
		local heapLast, heapMin, heapMax = heapFirst, heapFirst, heapFirst
		for i = 1, samplesN do
			local step = steps[(i - 1) % #steps + 1]
			local s0 = os.clock()
			a.applyStep(handle, step)
			samples[i] = (os.clock() - s0) * 1000
			if i % every == 0 then
				heapLast = gcinfo()
				heapMin = math.min(heapMin, heapLast)
				heapMax = math.max(heapMax, heapLast)
			end
		end

		local u0 = os.clock()
		a.unmount(handle)
		local unmountMs = (os.clock() - u0) * 1000

		local yardAfter = yardstick.measure()
		local yard = (yardBefore + yardAfter) / 2
		local s = stats.summarize(samples)

		row.status = "ok"
		row.metrics = {
			mountMs = mountMs,
			stepP50Ms = s.p50,
			stepP95Ms = s.p95,
			stepP99Ms = s.p99,
			stepP50Norm = s.p50 / yard,
			stepP95Norm = s.p95 / yard,
			unmountMs = unmountMs,
			heapNetKb = heapLast - heapFirst,
			gcSwingKb = heapMax - heapMin,
			yardstickDriftPct = math.abs(yardAfter - yardBefore) / yardBefore * 100,
		}
	end)
	if not ok then
		row.status = "error"
		row.note = tostring(err)
		row.metrics = nil
	end
	return row
end

return run_one_lib
```

- [ ] **Step 5: Implement the CLI `runner/lune/run_one.luau`**

```lua
--!strict
local process = require("@lune/process")
local run_one_lib = require("./run_one_lib")
local stable_json = require("../lune/lib/stable_json") -- adjust: require("./lib/stable_json")

local args = process.args
assert(#args >= 3, "usage: lune run runner/lune/run_one <framework> <workload> <S|M|L> [seed] [samples] [warmup]")
local row = run_one_lib.run({
	framework = args[1],
	workload = args[2],
	size = args[3],
	seed = tonumber(args[4]),
	samples = tonumber(args[5]),
	warmup = tonumber(args[6]),
})
print(stable_json.encode(row))
if row.status == "error" then
	process.exit(2)
end
```
(The require path note in the comment is deliberate: the correct line is `require("./lib/stable_json")` — use that.)

- [ ] **Step 6: Run tests + a real CLI smoke, then commit**

```bash
lune run tests/run
lune run runner/lune/run_one _fixture battle_hud S 1 120 10   # one JSON line, "status":"ok"
stylua --check .
git add -A && git commit -m "feat: yardstick + run_one harness (ok/unsupported/live-only/error paths)"
```

---

### Task 6: Results schema + matrix orchestrator (fresh process per row)

**Files:**
- Create: `runner/lune/lib/schema.luau`, `runner/lune/run_matrix.luau`, `tools/check_schema.luau`
- Test: `tests/schema.spec.luau`, `tests/process_probe.spec.luau`, `tests/matrix.spec.luau`
- Modify: `tests/run.luau` (register)

**Interfaces:**
- Produces: `schema.validateEnvelope(tbl)` — errors on violation; returns true. Envelope shape (spec §Results schema):

```lua
export type Envelope = {
	run: { stamp: string, mode: "lune" | "studio", host: string, seed: number },
	rows: { any }, -- each row is a run_one Row; sorted by framework, workload, size
}
```
- Produces: CLI `lune run runner/lune/run_matrix [--frameworks a,b] [--workloads x,y] [--sizes S,M,L] [--seed N] [--samples N] [--warmup N] [--out path]` — default out `artifacts/matrix-<stamp>.json`; spawns ONE FRESH LUNE CHILD PER (framework, workload, size), sequentially.
- Consumes: `run_one` CLI (child), `@lune/process` exec, `@lune/serde` (decode child stdout), `@lune/fs`.

- [ ] **Step 1: Write the process probe test `tests/process_probe.spec.luau`** (Lune 0.10 renamed its spawn API; this pins whichever exists)

```lua
--!strict
local process = require("@lune/process")
local exec = (process :: any).exec or (process :: any).spawn
assert(type(exec) == "function", "no blocking exec/spawn on @lune/process — read Lune 0.10.4 docs and update lib/proc.luau")
local result = exec("lune", { "--version" })
assert(result.ok == true, "spawning lune must succeed")
assert(type(result.stdout) == "string" and #result.stdout > 0)
return true
```
Run it (`lune run tests/run` after registering): if BOTH names are missing, STOP and check the Lune 0.10.4 process API (`lune --help`, https://lune-org.github.io/docs) — then adapt the `exec` line here and in Step 4's `proc.luau` to the real name. The rest of the task does not change.

- [ ] **Step 2: Write the failing tests**

`tests/schema.spec.luau`:
```lua
--!strict
local schema = require("../runner/lune/lib/schema")

local good = {
	run = { stamp = "2026-08-31T00:00:00Z", mode = "lune", host = "macos-aarch64", seed = 1 },
	rows = {
		{
			framework = "_fixture", version = "1.0.0", workload = "battle_hud", size = "S",
			status = "ok", meta = { seed = 1, samples = 120, warmup = 10 },
			metrics = {
				mountMs = 1, stepP50Ms = 0.1, stepP95Ms = 0.2, stepP99Ms = 0.3,
				stepP50Norm = 0.5, stepP95Norm = 0.9, unmountMs = 0.1,
				heapNetKb = 0, gcSwingKb = 12, yardstickDriftPct = 3,
			},
		},
		{
			framework = "flux", version = "0", workload = "battle_hud", size = "S",
			status = "unsupported", note = "missing capabilities: reactive",
			meta = { seed = 1, samples = 120, warmup = 10 },
		},
	},
}
assert(schema.validateEnvelope(good) == true)

local function mustFail(patch: (any) -> ())
	local function deepCopy(t: any): any
		if type(t) ~= "table" then
			return t
		end
		local out = {}
		for k, v in t :: { [any]: any } do
			out[k] = deepCopy(v)
		end
		return out
	end
	local bad = deepCopy(good)
	patch(bad)
	assert(not pcall(schema.validateEnvelope, bad), "schema failed to bite")
end

mustFail(function(bad)
	bad.run.mode = "dream"
end)
mustFail(function(bad)
	bad.rows[1].size = "XL"
end)
mustFail(function(bad)
	bad.rows[1].metrics.stepP95Ms = nil -- ok row missing a metric
end)
mustFail(function(bad)
	bad.rows[1].status = "great"
end)
mustFail(function(bad)
	bad.rows[2].metrics = { mountMs = 1 } -- non-ok row must NOT carry metrics
end)

return true
```

`tests/matrix.spec.luau` (spawns real children; keep samples small):
```lua
--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local schema = require("../runner/lune/lib/schema")

local exec = (process :: any).exec or (process :: any).spawn
local result = exec("lune", {
	"run", "runner/lune/run_matrix",
	"--frameworks", "_fixture", "--workloads", "battle_hud", "--sizes", "S",
	"--seed", "1", "--samples", "60", "--warmup", "5",
	"--out", "artifacts/test-matrix.json",
})
assert(result.ok, `matrix run failed: {result.stderr}`)
local envelope = serde.decode("json", fs.readFile("artifacts/test-matrix.json"))
assert(schema.validateEnvelope(envelope) == true)
assert(#envelope.rows == 1, "1 framework x 1 workload x 1 size = 1 row")
assert(envelope.rows[1].status == "ok")
assert(envelope.run.mode == "lune" and envelope.run.seed == 1)
return true
```

- [ ] **Step 3: Register all three specs, run, verify FAIL** (probe may already PASS — that is fine)

- [ ] **Step 4: Implement `runner/lune/lib/proc.luau`, `runner/lune/lib/schema.luau`, `runner/lune/run_matrix.luau`, `tools/check_schema.luau`**

`runner/lune/lib/proc.luau` (one place owns the exec-name difference):
```lua
--!strict
local process = require("@lune/process")
local proc = {}
local exec = (process :: any).exec or (process :: any).spawn
assert(type(exec) == "function", "no blocking exec API on @lune/process")
function proc.run(program: string, args: { string }): any
	return exec(program, args)
end
return proc
```

`runner/lune/lib/schema.luau` — validation rules, all enforced with `assert`:
- `run.stamp` non-empty string; `run.mode` is `"lune"` or `"studio"`; `run.host` non-empty string; `run.seed` number.
- `rows` an array. Per row: `framework`/`version`/`workload` non-empty strings; `size` in {S,M,L}; `status` in {ok, unsupported, live-only, error}; `meta.seed/samples/warmup` numbers.
- `status == "ok"` requires `metrics` with ALL of: `mountMs, stepP50Ms, stepP95Ms, stepP99Ms, stepP50Norm, stepP95Norm, unmountMs, heapNetKb, gcSwingKb, yardstickDriftPct` — every one a number. Any other status requires `metrics == nil`.

`runner/lune/run_matrix.luau`:
```lua
--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local proc = require("./lib/proc")
local schema = require("./lib/schema")
local stable_json = require("./lib/stable_json")

local function parseArgs(args: { string }): { [string]: string }
	local out = {}
	local i = 1
	while i <= #args do
		local key = args[i]
		assert(string.sub(key, 1, 2) == "--", `bad arg {key}`)
		out[string.sub(key, 3)] = args[i + 1]
		i += 2
	end
	return out
end

local function csv(s: string?): { string }?
	if s == nil then
		return nil
	end
	local out = {}
	for part in string.gmatch(s, "[^,]+") do
		table.insert(out, part)
	end
	return out
end

local opts = parseArgs(process.args)
local frameworksRegistry = require("../../frameworks/init")
local workloadsRegistry = require("../../workloads/init")

local function names(registry: any): { string }
	local out = {}
	for name in registry :: { [string]: any } do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local frameworks = csv(opts.frameworks) or names(frameworksRegistry)
local workloads = csv(opts.workloads) or names(workloadsRegistry)
local sizes = csv(opts.sizes) or { "S", "M", "L" }
local seed = opts.seed or "1"
local samples = opts.samples or "1500"
local warmup = opts.warmup or "50"
local stamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
local outPath = opts.out or `artifacts/matrix-{os.date("!%Y%m%d-%H%M%S")}.json`

local rows = {}
for _, fw in frameworks do
	for _, wl in workloads do
		for _, size in sizes do
			print(`running {fw} / {wl} / {size} ...`)
			local result = proc.run("lune", { "run", "runner/lune/run_one", fw, wl, size, seed, samples, warmup })
			if result.ok or result.code == 2 then -- exit 2 = error row, still valid JSON
				table.insert(rows, serde.decode("json", result.stdout))
			else
				error(`child failed for {fw}/{wl}/{size}: {result.stderr}`)
			end
		end
	end
end

table.sort(rows, function(x, y)
	local kx = `{x.framework}|{x.workload}|{x.size}`
	local ky = `{y.framework}|{y.workload}|{y.size}`
	return kx < ky
end)

local envelope = {
	run = { stamp = stamp, mode = "lune", host = `{process.os}-{process.arch}`, seed = tonumber(seed) :: number },
	rows = rows,
}
schema.validateEnvelope(envelope)
fs.writeFile(outPath, stable_json.encode(envelope))
print(`wrote {outPath} ({#rows} rows)`)
```

`tools/check_schema.luau`:
```lua
--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local schema = require("../runner/lune/lib/schema")

local checked = 0
if fs.isDir("results") then
	for _, name in fs.readDir("results") do
		if string.match(name, "%.json$") then
			schema.validateEnvelope(serde.decode("json", fs.readFile(`results/{name}`)))
			checked += 1
		end
	end
end
print(`check_schema: {checked} committed result file(s) valid`)
```

- [ ] **Step 5: Run tests to verify pass, then commit**

```bash
lune run tests/run          # schema, probe, matrix specs PASS (matrix spec takes ~seconds)
lune run tools/check_schema # 0 files valid (results/ still empty) — exits 0
stylua --check .
git add -A && git commit -m "feat: results schema + sequential fresh-process matrix runner"
```

---

### Task 7: Runner self-test (the fixture's known ratios)

**Files:**
- Create: `runner/lune/lib/runner_selftest.luau`, `tools/check_runner.luau`
- Test: `tests/runner_selftest.spec.luau`
- Modify: `tests/run.luau` (register)

**Interfaces:**
- Produces: `runner_selftest.assertBand(label: string, ratio: number, lo: number, hi: number)` (errors outside band); `runner_selftest.run(): { stepRatio: number, mountRatio: number }` — measures `_fixture` on battle_hud S and L and asserts both ratios in **[6, 14]** (constructed expectation ≈ 10: fixture step cost is linear in the units-list length, 1000/100).
- Consumes: `run_one_lib.run` (in-process is acceptable here — the self-test compares ratios inside one process, so isolation loss cancels out).

- [ ] **Step 1: Write the failing test `tests/runner_selftest.spec.luau`**

```lua
--!strict
local selftest = require("../runner/lune/lib/runner_selftest")

-- the band check BITES
assert(pcall(selftest.assertBand, "x", 10, 6, 14) == true)
assert(not pcall(selftest.assertBand, "x", 20, 6, 14), "ratio 20 must fail the band")
assert(not pcall(selftest.assertBand, "x", 2, 6, 14), "ratio 2 must fail the band")

-- the real measurement lands in band (takes ~10-20s; small samples)
local r = selftest.run()
assert(r.stepRatio >= 6 and r.stepRatio <= 14, `stepRatio {r.stepRatio} out of band`)
assert(r.mountRatio >= 6 and r.mountRatio <= 14, `mountRatio {r.mountRatio} out of band`)

return true
```

- [ ] **Step 2: Register, run, verify FAIL**

- [ ] **Step 3: Implement `runner/lune/lib/runner_selftest.luau` and `tools/check_runner.luau`**

`runner/lune/lib/runner_selftest.luau`:
```lua
--!strict
-- The trust anchor: _fixture has CONSTRUCTED cost (linear in list length),
-- so the runner must reproduce known ratios. If this fails, the runner is
-- broken and no real framework's numbers may be trusted.
local run_one_lib = require("../run_one_lib")

local runner_selftest = {}

function runner_selftest.assertBand(label: string, ratio: number, lo: number, hi: number)
	assert(ratio >= lo and ratio <= hi, `{label}: ratio {ratio} outside [{lo}, {hi}]`)
end

function runner_selftest.run(): { stepRatio: number, mountRatio: number }
	local function measure(size: "S" | "L")
		local row = run_one_lib.run({
			framework = "_fixture",
			workload = "battle_hud",
			size = size,
			seed = 1,
			samples = 150,
			warmup = 10,
		})
		assert(row.status == "ok", `selftest row {size}: {row.status} ({tostring(row.note)})`)
		return assert(row.metrics)
	end
	local s = measure("S")
	local l = measure("L")
	local out = {
		stepRatio = l.stepP50Ms / s.stepP50Ms,
		mountRatio = l.mountMs / s.mountMs,
	}
	runner_selftest.assertBand("stepP50 L/S", out.stepRatio, 6, 14)
	runner_selftest.assertBand("mount L/S", out.mountRatio, 6, 14)
	return out
end

return runner_selftest
```

`tools/check_runner.luau`:
```lua
--!strict
local selftest = require("../runner/lune/lib/runner_selftest")
local r = selftest.run()
print(`check_runner: stepRatio {string.format("%.2f", r.stepRatio)}, mountRatio {string.format("%.2f", r.mountRatio)} — in band [6,14]`)
```

- [ ] **Step 4: Run tests to verify pass, then commit**

```bash
lune run tests/run
lune run tools/check_runner
stylua --check .
git add -A && git commit -m "feat: runner self-test against fixture's constructed cost ratios"
```

---

### Task 8: Facet adapter

**Files:**
- Create: `frameworks/facet/adapter.luau`, `frameworks/facet/NOTES.md`
- Modify: `frameworks/init.luau` (register `facet`)
- Test: `tests/facet_adapter.spec.luau`
- Modify: `tests/run.luau` (register)

**Interfaces:**
- Consumes (verified by an earlier scout; re-verify at the cited lines): Facet 0.10.0 at `../../../Facet/src` (from `frameworks/facet/adapter.luau`); `Facet.newCore()`, `Facet.newEnvironment(core)`, `Facet.UI.<VStack|HStack|Box|Text|Image|ForEach>`, `Facet.mount(core, bp) -> root` (`root.dump()`, `root.dispose()`), `Facet.renderer.attach(core, root, env, target, { rootPolicy = "coreSafeContent" }) -> controller` (`controller.initialRender()`, `.refresh()`, `.stats()`, `.dispose()`), `core:signal(v)` -> `{get/set}`, `core:memo(fn)`; headless render target `fake_target.new()` at `../../../Facet/tests/lib/fake_target` (`adapter.liveCount()`, `adapter.rootCount()`); `env:set("viewportRect", {x,y,w,h})`, `env:set("coreSafeInsets", {top,bottom,left,right})`. ForEach spec fields are TOP-LEVEL: `{ id, items: Readable<{any}>, key: (item) -> string, row: (item, itemScope) -> Blueprint }` (`Facet/src/blueprint.luau:496-502`).
- Produces: registry entry `facet` whose adapter passes conformance and produces an `ok` run_one row.

- [ ] **Step 1: Investigate two API facts; record them in `frameworks/facet/NOTES.md`**

1. **Readable props:** in `Facet/src/blueprint.luau`, check which spec fields are typed `Readable<...>`: `TextSpec.text`, `ImageSpec.image`, and whether `BoxSpec.width/height` px accepts a Readable. Record file:line.
2. **ForEach same-key replacement:** in `Facet/src/mount.luau:273-515`, determine what happens when the `items` array carries a NEW item table with the SAME key: is the row's content updated (row factory re-run or props re-bound), or is the old row kept untouched? Record file:line.

Decision rules (write the chosen branch into NOTES.md):
- If ForEach same-key replacement does NOT update row content → use **per-item signals**: `itemSignals[listState][key][field] = core:signal(v)`; template `ItemRef` props bind those signals; `updateItem` sets one signal and never touches the items array. (This is idiomatic fine-grained Facet.)
- If `BoxSpec` px does NOT accept a Readable → render `bar` as `UI.Text({ id, text = <memo of value>, textSize = 10 })` instead of a width-bound Box, and note the substitution. Headless mode measures reactive+layout compute, not pixels; Plan 2's Studio phase revisits visuals.

- [ ] **Step 2: Write the failing test `tests/facet_adapter.spec.luau`**

```lua
--!strict
local Prng = require("../runner/lune/lib/prng")
local conformance = require("../runner/lune/lib/conformance")
local frameworks = require("../frameworks/init")
local workloads = require("../workloads/init")
local run_one = require("../runner/lune/run_one_lib")

local a = frameworks.facet()
assert(a.name == "facet")
assert(a.version == "0.10.0", "keep version in lockstep with Facet.VERSION")
assert(a.capabilities.headless == true and a.capabilities.reactive == true and a.capabilities.keyedList == true)

-- contract conformance (determinism, clean unmount)
conformance.check(a)

-- reactivity actually lands in the mounted tree
local wl = workloads.battle_hud()
local spec = wl.build("S", Prng.new(1))
local h = a.mount(spec, nil)
local before = a.snapshot(h)
a.applyStep(h, { kind = "setState", id = "squad1", value = 4242 })
assert(a.snapshot(h) ~= before, "setState must change the mounted tree")
local mid = a.snapshot(h)
a.applyStep(h, { kind = "updateItem", listState = "units", key = "u1", field = "hp", value = 0.125 })
assert(a.snapshot(h) ~= mid, "updateItem must change the mounted tree")
a.unmount(h)
assert(a.liveCount(h) == 0)

-- end-to-end benchmark row
local row = run_one.run({ framework = "facet", workload = "battle_hud", size = "S", seed = 1, samples = 100, warmup = 10 })
assert(row.status == "ok", `facet row: {row.status} ({tostring(row.note)})`)
assert((row.metrics :: any).mountMs > 0)

return true
```

- [ ] **Step 3: Register spec + registry entry, run, verify FAIL**

`frameworks/init.luau` gains:
```lua
	facet = function()
		return require("./facet/adapter")
	end,
```

- [ ] **Step 4: Implement `frameworks/facet/adapter.luau`**

Skeleton (fill the branch chosen in Step 1 where marked; everything else is fixed):

```lua
--!strict
-- Facet adapter. Facet is consumed IN PLACE from the sibling checkout —
-- never vendored (Facet's DR-7 gate bans benchmark rivals in its tree;
-- symmetrically we keep Facet source out of ours).
local Facet = require("../../../Facet/src") :: any
local fake_target = require("../../../Facet/tests/lib/fake_target") :: any
local stable_json = require("../../runner/lune/lib/stable_json")

local function resolveScalar(ctx: any, v: any): any
	if type(v) == "table" and v.ref ~= nil then
		return ctx.signals[v.ref]
	end
	return v
end

-- itemCtx is nil outside templates; inside a template it resolves ItemRefs
-- per the Step 1 branch decision (item value, or per-item signal).
local function resolveProp(ctx: any, itemCtx: any, v: any): any
	if type(v) == "table" and v.item ~= nil then
		assert(itemCtx, "ItemRef outside template")
		return itemCtx(v.item)
	end
	return resolveScalar(ctx, v)
end

local function toBlueprint(ctx: any, node: any, itemCtx: any, idSuffix: string): any
	local id = node.id .. idSuffix
	if node.kind == "panel" then
		local children = {}
		for i, child in node.children or {} do
			children[i] = toBlueprint(ctx, child, itemCtx, idSuffix)
		end
		local ctor = if node.direction == "horizontal" then Facet.UI.HStack else Facet.UI.VStack
		return ctor({ id = id, gap = 4, children = children })
	elseif node.kind == "label" then
		local props = node.props or {}
		return Facet.UI.Text({
			id = id,
			text = resolveProp(ctx, itemCtx, props.text),
			textSize = (props.textSize :: any) or 14,
		})
	elseif node.kind == "image" then
		return Facet.UI.Image({ id = id, image = resolveProp(ctx, itemCtx, (node.props or {}).image) })
	elseif node.kind == "bar" then
		-- BRANCH (Step 1, fact 1): width-bound Box if BoxSpec px accepts a
		-- Readable, else the Text fallback. One of:
		--   return Facet.UI.Box({ id = id, width = { type = "fixed", px = <readable of value*100> }, height = { type = "fixed", px = 8 } })
		--   return Facet.UI.Text({ id = id, text = <readable of value>, textSize = 10 })
		error("implement per NOTES.md branch")
	elseif node.kind == "list" then
		local listState = node.itemsState :: string
		return Facet.UI.ForEach({
			id = id,
			items = ctx.listSignals[listState],
			key = function(item: any)
				return item.key
			end,
			row = function(item: any)
				-- itemCtx per BRANCH (Step 1, fact 2): either reads item
				-- fields directly, or returns ctx.itemSignals[listState][item.key][field]
				local rowItemCtx = function(field: string): any
					error("implement per NOTES.md branch")
				end
				return toBlueprint(ctx, node.template, rowItemCtx, `-{item.key}`)
			end,
		})
	end
	error(`unknown kind {tostring(node.kind)}`)
end

local FacetAdapter = {}

function FacetAdapter.mount(spec: any, _target: any?): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local ctx: any = { core = core, signals = {}, listSignals = {}, itemSignals = {} }
	for id, v in spec.state :: { [string]: any } do
		if type(v) == "table" then
			ctx.listSignals[id] = core:signal(v)
			-- per-item signals branch: also seed ctx.itemSignals[id][item.key][field]
		else
			ctx.signals[id] = core:signal(v)
		end
	end
	local bp = toBlueprint(ctx, spec.root, nil, "")
	local root = Facet.mount(core, bp)
	local target = fake_target.new()
	local controller = Facet.renderer.attach(core, root, env, target, { rootPolicy = "coreSafeContent" })
	controller.initialRender()
	return { core = core, env = env, ctx = ctx, root = root, target = target, controller = controller, disposed = false }
end

function FacetAdapter.applyStep(h: any, step: any)
	local ctx = h.ctx
	if step.kind == "noop" then
		-- deliberately still refresh: a no-op frame is part of what we measure
	elseif step.kind == "setState" then
		ctx.signals[step.id]:set(step.value)
	elseif step.kind == "updateItem" then
		-- BRANCH: per-item signal set, or clone-array-clone-item + listSignals set
		error("implement per NOTES.md branch")
	elseif step.kind == "addItem" then
		local arr = table.clone(ctx.listSignals[step.listState]:get())
		table.insert(arr, step.item)
		-- per-item signals branch: seed signals for the new item first
		ctx.listSignals[step.listState]:set(arr)
	elseif step.kind == "removeItem" then
		local old = ctx.listSignals[step.listState]:get()
		local arr = {}
		for _, item in old do
			if item.key ~= step.key then
				table.insert(arr, item)
			end
		end
		ctx.listSignals[step.listState]:set(arr)
	elseif step.kind == "reorder" then
		local byKey = {}
		for _, item in ctx.listSignals[step.listState]:get() do
			byKey[item.key] = item
		end
		local arr = {}
		for _, key in step.order do
			table.insert(arr, byKey[key])
		end
		ctx.listSignals[step.listState]:set(arr)
	end
	h.controller.refresh()
end

function FacetAdapter.snapshot(h: any): string
	local dump = h.root.dump()
	return if type(dump) == "string" then dump else stable_json.encode(dump)
end

function FacetAdapter.liveCount(h: any): number
	if h.disposed then
		return 0
	end
	return h.target.liveCount() + h.target.rootCount()
end

function FacetAdapter.unmount(h: any)
	h.controller.dispose()
	h.root.dispose()
	h.disposed = true
end

return {
	name = "facet",
	version = "0.10.0",
	license = "MIT",
	capabilities = { reactive = true, keyedList = true, headless = true, styling = true },
	mount = FacetAdapter.mount,
	applyStep = FacetAdapter.applyStep,
	snapshot = FacetAdapter.snapshot,
	liveCount = FacetAdapter.liveCount,
	unmount = FacetAdapter.unmount,
}
```

Implementation cautions:
- If `root.dump()` output embeds anything non-deterministic (timestamps, memory addresses), snapshot on a projection of it instead — strip those fields before encoding; conformance's double-mount equality is the arbiter. Document what was stripped in NOTES.md.
- If `liveCount` from `fake_target` counts differently than expected, the contract only requires: > 0 mounted, deterministic, 0 after unmount. If the fake target's root survives `controller.dispose()`, consult `Facet/tests/renderer.spec.luau:104-108` (`dispose destroys the adapter root`) — dispose order there is `controller.dispose()` then `root.dispose()`, after which `adapter.rootCount()` is 0.
- Facet requires may be slow on first load from CloudStorage; that cost lands in module load, not in `mount`, so it does not pollute metrics.

- [ ] **Step 5: Run tests to verify pass**

```bash
lune run tests/run                 # facet_adapter.spec PASS (and all prior)
lune run tools/check_adapters      # adapter facet: ok, adapter _fixture: ok
lune run runner/lune/run_one facet battle_hud S 1 100 10   # "status":"ok"
```

- [ ] **Step 6: Fill `frameworks/facet/NOTES.md`** with: Facet version + commit hash of the sibling checkout, the two investigated facts (file:line), the branches taken, anything stripped from `dump()`.

- [ ] **Step 7: Commit**

```bash
stylua --check .
git add -A && git commit -m "feat: Facet adapter (headless via fake_target; idiomatic ForEach binding)"
```

---

### Task 9: check.sh, CONTRIBUTING, wrap-up smoke

**Files:**
- Create: `tools/check.sh` (executable), `CONTRIBUTING.md`
- Modify: `README.md`

**Interfaces:**
- Produces: `tools/check.sh` — the one command CI and contributors run.

- [ ] **Step 1: Write `tools/check.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
stylua --check .
lune run tests/run
lune run tools/check_adapters
lune run tools/check_runner
lune run tools/check_schema
echo "FacetBench: all checks green"
```

```bash
chmod +x tools/check.sh
test -x tools/check.sh   # standing trap: verify the executable bit is really set AND committed
git add tools/check.sh && git update-index --chmod=+x tools/check.sh
```

- [ ] **Step 2: Write `CONTRIBUTING.md`**

```markdown
# Contributing to FacetBench

## Add a framework
1. Create `frameworks/<name>/` containing your vendored framework source
   under `vendor/` (keep its LICENSE file) and an `adapter.luau` satisfying
   the contract in `runner/lune/lib/adapter.luau`: `name`, `version`,
   `license`, `capabilities`, `mount`, `applyStep`, `snapshot`, `liveCount`,
   `unmount`. Translate the neutral scene spec idiomatically — write the
   code your framework's docs would recommend.
2. Declare only the capabilities you truly support; unsupported workloads
   are reported honestly, never shimmed.
3. Register one line in `frameworks/init.luau`.
4. `tools/check.sh` must pass (conformance = determinism + clean unmount).

## Add a workload
1. Create `workloads/<name>.luau` returning the shape in
   `runner/lune/lib/scene.luau` / `workloads/init.luau`. No framework
   imports. All randomness through the provided seeded PRNG.
2. Register it in `workloads/init.luau`. `tools/check.sh` must pass.

## Run the matrix
    lune run runner/lune/run_matrix                 # everything, defaults
    lune run runner/lune/run_matrix --frameworks facet,vide --sizes S,M

## Submitting results
Committed baselines live in `results/` and must pass
`lune run tools/check_schema`. Include your `tools/check.sh` output and
machine description in the PR. Numbers from a run whose
`tools/check_runner` fails are not accepted.
```

- [ ] **Step 3: Update `README.md` quickstart**

Replace the Quickstart section with:
```markdown
## Quickstart

    rokit install
    tools/check.sh                                  # full verification
    lune run runner/lune/run_matrix --sizes S       # quick comparative run
```

- [ ] **Step 4: Full smoke — every check + a two-framework matrix**

```bash
tools/check.sh
lune run runner/lune/run_matrix --frameworks _fixture,facet --workloads battle_hud --sizes S --samples 200 --warmup 20 --out artifacts/smoke.json
```
Expected: check.sh green; smoke matrix writes 2 rows, both `"status":"ok"`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore: check.sh gate, CONTRIBUTING, quickstart"
```

---

## After this plan

- **Plan 2** (authored on Phase 1 completion): vendor Vide/Fusion/React-lua/Blend/Flux + adapters (parallel subagents), `war_room_inventory` + `killfeed_nameplates` workloads, Studio live runner + microprofiler capture.
- **Plan 3**: committed baselines + chart page, demonstrators D1–D3 shown red, fixes F1–F3 (Facet repo, RR lockstep), public polish.

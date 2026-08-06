--!strict
-- MicroProfiler phase scopes (roadmap Step 9, docs/plans/performance-stress-places.md).
--
-- WHAT THIS IS FOR. Roblox's MicroProfiler shows engine C++ scopes by default and
-- collapses Luau work into an anonymous `$Script` bar (LibMP skill, "Limitations").
-- Manually annotated `debug.profilebegin` / `debug.profileend` scopes ARE displayed
-- correctly and are readable programmatically through LibMP's timer table, so a
-- named phase here is the difference between "scripts cost 4ms" and "the solve cost
-- 4ms and the commit cost 0.2ms".
--
-- FOUR RULES:
--
-- 1. LOW CARDINALITY. The plan is explicit — "do not create a label per row, key,
--    or node". A per-node label would make every capture unreadable AND cost more
--    than it measures, so the legal names are a CLOSED SET declared below and
--    `span` refuses anything else. The set is a phase vocabulary, not a call-site
--    log: two different call sites that answer the same profiling question share a
--    name on purpose (every commit write is `LuauUI/commit`, wherever it happens).
--
-- 2. THE BODY MUST NOT YIELD. `debug.profilebegin` opens a scope on the executing
--    thread; a yield inside it hands the engine an enter and a leave in different
--    frames, and the counters here cannot see that at all — they count Lua call
--    sites, so `balanced` would read true for a capture whose engine-side stack is
--    not what this module claims. Wrap synchronous work only. A driver that has to
--    wait for a frame puts the wait OUTSIDE the span (the performance lab's scroll
--    passes were rewritten to do exactly that after this rule was written down).
--
-- 3. BALANCED ON EVERY EXIT PATH. An unbalanced `profilebegin` does not merely lose
--    one measurement — the engine's scope stack stays open and every subsequent
--    frame in the capture is misattributed. So there is exactly ONE way to open a
--    scope (`span`), it closes in the same function that opened it, and an error
--    thrown by the body is caught, the scope closed, and the error re-raised
--    unchanged. There is deliberately no `begin`/`finish` pair on the public
--    surface of this module: a pair can be misused, a span cannot.
--
-- 4. FREE WHEN ABSENT. Lune has no `debug.profilebegin`, and a game that has turned
--    scopes off should pay a branch and a direct call — not a pcall. `active`
--    collapses both conditions into one boolean read.
--
-- This module is INTERNAL (no LuauUI.* export). The performance lab reaches it by
-- instance path through the named exemption in tools/lune/check_boundary.luau, so
-- the scenario driver's own scopes and the framework's come from one implementation
-- and can never disagree about naming or balance. Recorded as PLN-2.

local profile = {}

-- ---- the closed scope set -------------------------------------------------
-- Keys are what call sites pass; values are what the MicroProfiler shows. Every
-- label is prefixed so a LibMP `FindTimerIds("LuauUI/*")` returns this set and
-- nothing else, and so a LuauUI scope is never confused with a game's own.
local SCOPES: { [string]: string } = {
	-- the model changed: a transaction, a signal write storm, a batch commit
	mutate = "LuauUI/mutate",
	-- reactive propagation: dirty walk, memo recompute, observer dispatch
	react = "LuauUI/react",
	-- layout: the measure pass (intrinsic sizes, text metrics, candidate choice)
	measure = "LuauUI/measure",
	-- layout: the arrange pass (turning measured sizes into rects)
	arrange = "LuauUI/arrange",
	-- adapter commit: the property writes that make the frame visible
	commit = "LuauUI/commit",
	-- resource completion: an async image/asset landing and its UI update
	resource = "LuauUI/resource",
	-- building or disposing a mounted tree
	mount = "LuauUI/mount",
	-- the scenario driver: one named workload step
	scenario = "LuauUI/scenario",
	-- the scenario driver: teardown back to the idle baseline
	reset = "LuauUI/reset",
	-- THE PER-FRAME DRIVER, and it was the one thing none of the nine could see
	-- (2026-08-05). `presenter.refresh()` runs every frame from the host's frame
	-- connection, and the phases above only open when there is layout work to do — so
	-- on a frame that solves nothing, every scope read zero while the frame was not
	-- free. Measured on the ornate scroll at 360x691: 2.09 ms/frame of presenter work
	-- with no annotated phase under it at all.
	present = "LuauUI/present",
	-- ...and the part of it that turned out to own that number: re-deriving the focus
	-- map. Its own scope because "the presenter costs 2ms" is not actionable and
	-- "the focus map walk costs 2ms" is.
	focusmap = "LuauUI/focusmap",
	-- the OTHER half of every frame: the motion clock, the dwell/reveal timers and the
	-- registered tick hooks. `present` without `tick` would have left half the frame
	-- attributed to whatever happened to wrap it.
	tick = "LuauUI/tick",
}

-- The bound is asserted by tests, not merely intended. If a later stage needs a
-- tenth phase it raises this deliberately; it cannot drift upward one call site
-- at a time, which is how a per-node label set is actually born.
profile.MAX_SCOPES = 12
profile.SCOPES = SCOPES

-- ---- engine detection -----------------------------------------------------
local dbg = debug :: any
local profilebegin: ((string) -> ())? = if type(dbg.profilebegin) == "function" then dbg.profilebegin else nil
local profileend: (() -> ())? = if type(dbg.profileend) == "function" then dbg.profileend else nil
-- BOTH or NEITHER. A host with one half of the pair cannot balance a scope, and
-- opening scopes it can never close is strictly worse than not opening them.
local hasEngine = profilebegin ~= nil and profileend ~= nil

-- OFF BY DEFAULT (Roblox-platform review 2026-08-04, MAJOR-2). It was `true`, which
-- on the engine meant `active` was true for EVERY consumer — so every `mount`,
-- `commit`, `measure`, `arrange`, `react`, `mutate` and `resource` body ran under the
-- `pcall` below and re-raised at level 0. Two costs, both paid permanently by games
-- that never read a profile: a closure plus a pcall plus two C calls per phase per
-- frame, and — worse — an error thrown inside a solve reached the developer console
-- with the stack below the pcall boundary gone. Lune could never see it, because
-- `active` is false there and the suite always took the un-instrumented path.
--
-- A profiler that degrades production debuggability to instrument a session nobody is
-- watching has the default backwards. Turning it on is one call, and the performance
-- lab makes it at boot.
local enabled = false
local active = hasEngine and enabled

-- ---- the hook seam --------------------------------------------------------
-- WHY THIS IS NOT A TEST-ONLY BACK DOOR. Lune has no `debug.profilebegin`, so on
-- the host that runs the suite `active` is false and the instrumented path never
-- executes. A balance guarantee that can only be exercised on the platform where
-- an imbalance corrupts the capture is not a guarantee — it is a hope. Installing
-- a recording pair here runs the REAL instrumented path (same branch, same pcall,
-- same counter arithmetic) against an observable sink, which is what makes
-- "balanced on every exit and error path" a checkable claim rather than a comment.
--
-- Passing nil restores whatever the host actually has.
local function recompute()
	hasEngine = profilebegin ~= nil and profileend ~= nil
	active = hasEngine and enabled
end

function profile.setHooks(begin: ((string) -> ())?, finish: (() -> ())?)
	if begin == nil or finish == nil then
		profilebegin = if type(dbg.profilebegin) == "function" then dbg.profilebegin else nil
		profileend = if type(dbg.profileend) == "function" then dbg.profileend else nil
	else
		profilebegin = begin
		profileend = finish
	end
	recompute()
end

-- ---- accounting (the test + telemetry seam) -------------------------------
-- Counters are kept whether or not the engine is present, because the BALANCE
-- property is a property of this module and has to be provable headlessly. `depth`
-- is the live nesting level; `maxDepth` is the high-water mark a capture can
-- publish beside its scope times.
local opens = 0
local closes = 0
local depth = 0
local maxDepth = 0
local byScope: { [string]: number } = {}

function profile.available(): boolean
	return hasEngine
end

function profile.enabled(): boolean
	return enabled
end

-- The lab's clean-capture control: a capture that wants to measure the framework
-- WITHOUT the annotation overhead turns scopes off and says so in its metadata.
function profile.setEnabled(on: boolean)
	enabled = on == true
	recompute()
end

function profile.counters(): {
	opens: number,
	closes: number,
	depth: number,
	maxDepth: number,
	byScope: { [string]: number },
	balanced: boolean,
	engine: boolean,
	enabled: boolean,
}
	local copy: { [string]: number } = {}
	for k, v in byScope do
		copy[k] = v
	end
	return {
		opens = opens,
		closes = closes,
		depth = depth,
		maxDepth = maxDepth,
		byScope = copy,
		-- the load-bearing assertion, computed rather than asserted: an
		-- instrumented run that ends with opens ~= closes has corrupted the
		-- capture it was supposed to explain
		balanced = opens == closes and depth == 0,
		engine = hasEngine,
		enabled = enabled,
	}
end

function profile.resetCounters()
	opens, closes, depth, maxDepth = 0, 0, 0, 0
	byScope = {}
end

-- ---- the only way to open a scope -----------------------------------------
-- `span(key, fn)` runs `fn` inside the named scope and returns its first result.
-- Call sites that need several values assign to upvalues from inside `fn`; that
-- keeps this signature single-shaped and avoids a varargs pack per frame.
--
-- ERRORS. The body is pcall'd only while scopes are active, so the un-instrumented
-- path keeps LuauUI's ordinary error semantics exactly (same stack, same level).
-- While active, the error VALUE is re-raised unchanged at level 0 — a string error
-- already carries its own `file:line:` prefix from the original raise, and adding a
-- second one here would rewrite messages that callers match on.
function profile.span<T>(key: string, fn: () -> T): T
	local label = SCOPES[key]
	if label == nil then
		-- The cardinality rule, enforced at the call rather than in review. This
		-- error is deliberately loud: a new phase is a decision, and an ad-hoc
		-- label is the beginning of a per-node label set.
		error(
			`[LuauUI profile] unknown scope '{tostring(key)}' — scopes are a closed set (see src/core/profile.luau)`,
			2
		)
	end
	if not active then
		return fn()
	end
	opens += 1
	byScope[key] = (byScope[key] or 0) + 1
	depth += 1
	if depth > maxDepth then
		maxDepth = depth
	end
	-- A THROWING HOOK MUST NOT STRAND THE ACCOUNTING (reactive-runtime review, RR-2).
	-- The engine's own `debug.profilebegin` does not throw, but `setHooks` accepts an
	-- arbitrary pair and the lab installs one. An exception escaping `open` used to
	-- leave `depth` at 1 and `opens > closes` forever — and, one layer up, it escaped
	-- `flush`'s `profile.span("react", ...)` before `flushing = false` could run,
	-- silently killing the core for the rest of the session with no error recorded
	-- (RR-1). Both hooks are therefore protected: a broken instrument may lose its own
	-- measurement, it may not take the framework down with it.
	local open = profilebegin :: (string) -> ()
	local close = profileend :: () -> ()
	pcall(open, label)
	local ok, result = pcall(fn)
	pcall(close)
	depth -= 1
	closes += 1
	if not ok then
		error(result, 0)
	end
	return result :: T
end

return profile

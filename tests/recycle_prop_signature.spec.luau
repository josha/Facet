--!strict
--[[ W1b — A RECYCLED INSTANCE DOES NOT KEEP A STYLE PROP IT NEVER DECLARED.

	W1 (`fa289d5a`) deleted `propSigCache`, keyed on the props TABLE identity and
	never invalidated while `mount.luau:637` mutates that table in place. Self-
	review (Step 7, mandatory) found the theory wrong, then measured why: the
	cache was never the mechanism. `propSignature` had exactly two call sites,
	both inside the ONE `if handles[node.path] == nil` block that only ever runs
	at a node's own CREATE — nothing mutates `node.props` between them, so a
	cache hit there was always a hit on the value that SAME call's own first
	read had just computed, never a stale one (measured: every hit recorded
	across this repository's own `instance_recycling*` suite was exactly that
	shape). The real defect survived the deletion: `recycleKeyOf[path]` was
	written EXACTLY ONCE, at that create event, and never refreshed while the
	node stayed mounted — so a reactive style prop crossing nil AFTER create was
	invisible to the recorded key whether or not `propSignature` cached its
	answer. This file's own two-case reproduction reddened identically before
	and after the W1 deletion; W1b (`renderer.luau`, this commit) is the actual
	fix, and the two cases below are that reproduction, now green.

	THE FIX (`src/render/renderer.luau` + `src/render/recycle_key.luau` after
	R2's own seam): the key splits into PARTS frozen at create (class,
	decoration hint, engine kind — structural facts an instance cannot change
	while mounted) and a WORN SET of prop names maintained LIVE by
	`applyStyleProp`/`applyProp`, called from both the create-time apply loops
	and the reactive paint/semantics commit. A prop resolving non-nil is ADDED
	to the path's worn set there; one resolving nil is REMOVED. At park, the
	key is built from the frozen parts plus the CURRENT worn set — a row's own
	reactive history between create and park is what decides which bucket its
	handle files into, never a snapshot from the moment it was born.

	T8 R2 (review Critical 1) — W1b'S OWN NARROWING WAS THE BUG. The commit
	above shipped `propSignature`/the worn set as STYLE_PROPS only — an
	UNREQUESTED narrowing of the CREATE-time key from every declared name to
	style names alone, which re-opened the exact defect class one channel over:
	a row that never declares a BINDING prop (`enabled`, `image`, `tint`, …)
	could adopt a pooled instance still wearing a previous occupant's value,
	because `applyProps` only ever writes what a node DECLARES and never clears
	what it doesn't. Driven and confirmed (the reviewer's own probe, folded in
	below as "T8 R2, Critical 1"): 8 of 16 live Buttons in a 200-row churn wore
	a stale `enabled = false` nothing on screen had declared. THE NAMESPACE IS
	NOW `BINDING_PROPS ∪ STYLE_PROPS` (`render/recycle_key.luau`'s own header
	carries the full argument), signed identically by `signature()` at create
	and `noteWorn` at every point that writes one — `applyProp`, `applyStyleProp`,
	and (Important 2) `commit_walks.luau`'s compact-ladder writes (`label`,
	`icon`, `compactLabel`), which write with STYLE/binding authority but
	bypass those two choke points because their value is DERIVED, not simply
	`node.props[prop]`, and so needed the shared `noteWorn` dep threaded in
	rather than a second copy of the worn-set code. LAYOUT PROPS STAY EXCLUDED
	— not because "a layout prop never reaches `adapter.setProp`" (false;
	`commit_walks.luau` writes four of them) but because every layout write is
	value-diffed against a cache carried across an adoption instead
	(`lastTextSize`/`lastTextFont`/`lastPadding`/`lastWrapped`, `clipChildren`'s
	own re-derivation) — neither has the "stale bespoke child" failure a
	tracked prop's ABSENCE creates, so putting them in the key would only
	narrow buckets for no safety bought. The ragged-layout case below pins
	that exclusion's safety directly, GREEN both before and after this round.

	THE ADAPTER HALF OF THE BARGAIN, PAID ACROSS TWO COMMITS
	(`src/client/screen_paint.luau`): a style prop resolving to nil now tears
	its bespoke modifier down, or — `applyCorners` alone, T8 R2 Important 3 —
	RESTORES the chrome default instead. `applyShadow`/`applyGradient` own
	their instance through a handle field, so `Destroy()` is correct for them.
	`applyCorners` does NOT own its UICorner — `applySurface`/the bare-circle
	fallback share the same single child — so W1b's own first draft (`Destroy()`
	unconditionally) stripped a static `surface`'s radius the moment a sibling
	reactive `corners` crossed to nil. The fix restores whatever the node's
	OWN `declaredSurface`/`shape` would have painted (`cornerRadiusFor`, reused
	rather than re-derived) and only destroys the instance when NOTHING else
	claims it (a bare node with no surface and no circle shape) — the same
	"tear down only what nothing else needs" rule `applyShadow`/`applyGradient`
	already follow. `surface`, `role`, `textAlign`, `shape`, `scaleMode`,
	`compactLabel` and `icon` — the rest of `STYLE_PROP_ORDER` — were checked
	and already handle nil without crashing (`scaleMode` explicitly, via
	`restorePaint`; the rest by construction, e.g. `TEXT_ALIGN_MAP[nil] or
	Left`). `surface` writes the literal string "nil" via `tostring(value)` on
	a nil write rather than crashing or clearing — a real but non-crashing gap,
	out of this task's scope (it does not create a stale MODIFIER INSTANCE the
	way shadow/gradient/corners did; it is a single BackgroundColor3-class
	write that the next surface-string overwrites the moment one arrives).

	Built on `tests/lib/world.luau` (reuse audit REUSE-88; `world_substrate.spec`'s
	"hand-rolled builder count only ever falls" ratchet). No fake-Instance drive
	exists under Lune for `screen_paint.luau` (native-mode paint is Roblox-Instance-only,
	which the headless suite cannot construct) — the nil-branch pins below are
	SOURCE-SHAPE, not driven; the live proof is a Studio canary (T9 runs it):
	static `surface` + reactive `corners` real -> nil should show the UICorner's
	`CornerRadius` equal to the surface default, instance identity unchanged. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local world = require("./lib/world")

describe("W1b/R2: the cache stays gone, and the signature is BINDING ∪ STYLE", function()
	it("`propSigCache` is not a declared local anywhere in the renderer or the seam", function()
		local rendererSrc = fs.readFile("src/render/renderer.luau")
		local seamSrc = fs.readFile("src/render/recycle_key.luau")
		expect(string.find(rendererSrc, "local propSigCache", 1, true)).toBe(nil)
		expect(string.find(seamSrc, "local propSigCache", 1, true)).toBe(nil)
	end)

	it(
		"`propSignature` (now `recycle_key.signature`) filters to BINDING_PROPS ∪ STYLE_PROPS (T8 R2, Critical 1) and holds no cache table",
		function()
			local source = fs.readFile("src/render/recycle_key.luau")
			local body = string.match(source, "local function signature%(node: any%): string(.-)\n\tend")
			assert(body ~= nil, "signature's body was not found to read")
			expect(string.find(body :: string, "if BINDING_PROPS[name] or STYLE_PROPS[name] then", 1, true) ~= nil).toBe(
				true
			)
			expect(string.find(body :: string, "propSigCache", 1, true)).toBe(nil)
		end
	)

	it("the park-time key is built from PARTS + the live worn set, never a frozen string", function()
		local source = fs.readFile("src/render/recycle_key.luau")
		expect(string.find(source, "local partsOf", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "local wornOf", 1, true) ~= nil).toBe(true)
		local park = string.match(source, "local function parkKey%(path: string%): string%?(.-)\n\tend")
		assert(park ~= nil, "parkKey's body was not found to read")
		expect(
			string.find(park :: string, "key(parted.class, parted.hint, parted.kind, wornSignature(path))", 1, true)
				~= nil
		).toBe(true)
		-- the renderer forgets BOTH halves on departure, or a REUSED PATH would
		-- inherit a previous, structurally different occupant's worn set
		local forget = string.match(source, "local function forget%(path: string%)(.-)\n\tend")
		assert(forget ~= nil, "forget's body was not found to read")
		expect(string.find(forget :: string, "partsOf[path] = nil", 1, true) ~= nil).toBe(true)
		expect(string.find(forget :: string, "wornOf[path] = nil", 1, true) ~= nil).toBe(true)
		expect(string.find(fs.readFile("src/render/renderer.luau"), "recycleKeyState.forget(path)", 1, true) ~= nil).toBe(
			true
		)
	end)

	it("`applyStyleProp` is a choke point that maintains the worn set through `noteWorn`", function()
		local rendererSrc = fs.readFile("src/render/renderer.luau")
		local body = string.match(
			rendererSrc,
			"local function applyStyleProp%(handle: any, node: any, prop: string%)(.-)\n\tend"
		)
		assert(body ~= nil, "applyStyleProp's body was not found to read")
		expect(string.find(body :: string, "recycleKeyState.noteWorn(node.path, prop, value)", 1, true) ~= nil).toBe(
			true
		)
		local seamSrc = fs.readFile("src/render/recycle_key.luau")
		local noteWorn =
			string.match(seamSrc, "local function noteWorn%(path: string, prop: string, value: any%)(.-)\n\tend")
		assert(noteWorn ~= nil, "noteWorn's body was not found to read")
		expect(string.find(noteWorn :: string, "worn[prop] = true", 1, true) ~= nil).toBe(true)
		expect(string.find(noteWorn :: string, "worn[prop] = nil", 1, true) ~= nil).toBe(true)
	end)

	it(
		"`applyProp` is the OTHER choke point (T8 R2, Critical 1) — the binding half `applyStyleProp` alone cannot cover",
		function()
			local rendererSrc = fs.readFile("src/render/renderer.luau")
			local body =
				string.match(rendererSrc, "local function applyProp%(handle: any, node: any, prop: string%)(.-)\n\tend")
			assert(body ~= nil, "applyProp's body was not found to read")
			expect(string.find(body :: string, "recycleKeyState.noteWorn(node.path, prop, value)", 1, true) ~= nil).toBe(
				true
			)
			-- `recycleKeyState` must exist BEFORE `applyProp` is declared, or the call
			-- above is a nil global rather than an upvalue
			local declareAt = string.find(rendererSrc, "local recycleKeyState = recycle_key.new()", 1, true)
			local applyPropAt =
				string.find(rendererSrc, "local function applyProp(handle: any, node: any, prop: string)", 1, true)
			expect(declareAt ~= nil and applyPropAt ~= nil).toBe(true)
			expect((declareAt :: number) < (applyPropAt :: number)).toBe(true)
		end
	)

	it(
		"commit_walks.luau's compact-ladder writes (Important 2) route through the SAME `noteWorn` dep, not a second copy",
		function()
			local commitWalksSrc = fs.readFile("src/render/commit_walks.luau")
			expect(
				string.find(commitWalksSrc, "noteWorn: (path: string, prop: string, value: any) -> (),", 1, true) ~= nil
			).toBe(true)
			expect(string.find(commitWalksSrc, "local noteWorn = ctx.noteWorn", 1, true) ~= nil).toBe(true)
			expect(string.find(commitWalksSrc, 'noteWorn(node.path, "label", labelValue)', 1, true) ~= nil).toBe(true)
			expect(string.find(commitWalksSrc, 'noteWorn(node.path, "icon", iconValue)', 1, true) ~= nil).toBe(true)
			expect(
				string.find(commitWalksSrc, 'noteWorn(node.path, "compactLabel", compactLabelValue)', 1, true) ~= nil
			).toBe(true)
			-- the renderer threads its OWN choke point's updater in, rather than a
			-- second worn-set implementation living inside commit_walks
			local rendererSrc = fs.readFile("src/render/renderer.luau")
			expect(string.find(rendererSrc, "noteWorn = recycleKeyState.noteWorn,", 1, true) ~= nil).toBe(true)
			expect(string.find(commitWalksSrc, "wornOf", 1, true)).toBe(nil)
		end
	)
end)

-- ============================================================================
-- THE AUDIT TABLE (T8 R2 fix-round instruction): every `adapter.setProp(` call
-- site in `src/render/*.luau`, classified choke point / layout (excluded by
-- ruling, value-diffed by a cache) / exception (why it cannot desync the key).
-- The report carries the prose version; this pins the SET so the table cannot
-- silently go stale the next time a call site is added or removed.
-- ============================================================================

describe(
	"T8 R2: the audit table's set is exhaustive — every setProp( call site in src/render/*.luau is accounted for",
	function()
		it("the choke points, the layout sites and the presentation/registry exceptions are ALL of them", function()
			local sites: { string } = {}
			for _, relPath in
				{
					"src/render/renderer.luau",
					"src/render/commit_walks.luau",
					"src/render/drag_bridge.luau",
					"src/render/presentation_channel.luau",
				}
			do
				local source = fs.readFile(relPath)
				local lineNo = 0
				for line in string.gmatch(source .. "\n", "(.-)\n") do
					lineNo += 1
					-- a bare source-comment mentioning the call (renderer.luau's own
					-- top-of-file API summary) is not a SITE
					if
						string.match(line, "^%s*%-%-") == nil
						and string.find(line, "adapter.setProp(", 1, true) ~= nil
					then
						table.insert(sites, `{relPath}:{lineNo}`)
					end
				end
			end
			table.sort(sites)
			-- CHOKE POINTS (2, `renderer.luau`): applyProp, applyStyleProp — both
			-- now call noteWorn.
			-- COMMIT_WALKS (7): label/icon/compactLabel (choke-point-equivalent via
			-- the noteWorn dep, Important 2) + textSize/textFont/padding/textWrapped
			-- (LAYOUT, value-diffed by lastTextSize/lastTextFont/lastPadding/
			-- lastWrapped — excluded by ruling, not a defect).
			-- RENDERER (1 more): clipChildren (LAYOUT, re-derived every solve, never
			-- carries a stale identity across an adoption the way a style prop's
			-- absence would).
			-- DRAG_BRIDGE (1): dragHeld — EXCEPTION: not in BINDING_PROPS ∪
			-- STYLE_PROPS at all (`prop_channels.EMITTED_PROPS`'s own `dragHeld`
			-- carve-out); a park refusal never lets it survive into the pool anyway
			-- (the drag-binding sweep at `\0drag`/`\0drop`/`\0det` tears it down
			-- before a node is ever offered to `adapter.park`).
			-- PRESENTATION_CHANNEL (2): transform/transparency — EXCEPTION: not in
			-- BINDING_PROPS ∪ STYLE_PROPS (`prop_channels.DIRECT_PROPS`, "presentation
			-- authority"); `park` itself refuses any node carrying a live
			-- presentation transform, so one can never reach the pool at all.
			-- 2 + 7 + 1 + 1 + 2 = 13.
			expect(#sites).toBe(13)
		end)
	end
)

describe("W1b: the adapter tears a style modifier down instead of crashing on nil", function()
	local function applierBody(name: string, paramName: string): string
		local source = fs.readFile("src/client/screen_paint.luau")
		local pattern = "local function "
			.. name
			.. "%(instance: Instance, "
			.. paramName
			.. ": any, handle: any%)(.-)\n\tend"
		local body = string.match(source, pattern)
		assert(body ~= nil, `{name}'s body was not found to read`)
		return body :: string
	end

	it("applyShadow: `shadow == nil` destroys `shadowInstance` before anything indexes it", function()
		local body = applierBody("applyShadow", "shadow")
		local nilAt = string.find(body, "if shadow == nil then", 1, true)
		local indexAt = string.find(body, "shadow.blurRadius", 1, true)
		expect(nilAt ~= nil).toBe(true)
		expect(string.find(body, "handle.shadowInstance:Destroy()", 1, true) ~= nil).toBe(true)
		expect((nilAt :: number) < (indexAt :: number)).toBe(true)
	end)

	it("applyGradient: `gradient == nil` destroys `gradientInstance` before anything indexes it", function()
		local body = applierBody("applyGradient", "gradient")
		local nilAt = string.find(body, "if gradient == nil then", 1, true)
		local indexAt = string.find(body, "gradient.colors", 1, true)
		expect(nilAt ~= nil).toBe(true)
		expect(string.find(body, "handle.gradientInstance:Destroy()", 1, true) ~= nil).toBe(true)
		expect((nilAt :: number) < (indexAt :: number)).toBe(true)
	end)

	it(
		"applyCorners: `cornersData == nil` RESTORES the chrome default via `cornerRadiusFor` (T8 R2, Important 3) — no unconditional Destroy",
		function()
			local source = fs.readFile("src/client/screen_paint.luau")
			local body = string.match(
				source,
				"local function applyCorners%(instance: Instance, cornersData: any, handle: any%?%)(.-)\n\tend"
			)
			assert(body ~= nil, "applyCorners's body was not found to read")
			local nilAt = string.find(body :: string, "if cornersData == nil then", 1, true)
			local paintAt = string.find(body :: string, "styling.paintCorners(cornersData, style)", 1, true)
			expect(nilAt ~= nil).toBe(true)
			expect((nilAt :: number) < (paintAt :: number)).toBe(true)
			-- the nil branch calls the shared helper (reuses `cornerRadiusFor`,
			-- never re-derives a number) and only reaches `existing:Destroy()`
			-- INSIDE the "nothing else claims it" fallback, not unconditionally
			local nilBranch = string.match(body :: string, "if cornersData == nil then(.-)\n\t\tend")
			assert(nilBranch ~= nil, "the nil branch was not found to read")
			expect(string.find(nilBranch :: string, "chromeDefaultRadius(handle)", 1, true) ~= nil).toBe(true)
			expect(string.find(nilBranch :: string, "uiCorner.CornerRadius = restored", 1, true) ~= nil).toBe(true)
			expect(string.find(nilBranch :: string, "existing:Destroy()", 1, true) ~= nil).toBe(true)
			-- `restored == nil` gates the ONLY destroy this branch reaches
			local destroyGuard = string.match(nilBranch :: string, "if restored == nil then(.-)\n\t\t\tend")
			assert(destroyGuard ~= nil, "the restored == nil guard was not found to read")
			expect(string.find(destroyGuard :: string, "existing:Destroy()", 1, true) ~= nil).toBe(true)
		end
	)

	it("chromeDefaultRadius mirrors applySurface's own per-surface radius choice, reusing cornerRadiusFor", function()
		local source = fs.readFile("src/client/screen_paint.luau")
		local body = string.match(source, "local function chromeDefaultRadius%(handle: any%): UDim%?(.-)\n\tend")
		assert(body ~= nil, "chromeDefaultRadius's body was not found to read")
		expect(string.find(body :: string, 'surface == "raised"', 1, true) ~= nil).toBe(true)
		expect(string.find(body :: string, 'surface == "control" or surface == "chip"', 1, true) ~= nil).toBe(true)
		expect(string.find(body :: string, "cornerRadiusFor(handle, style.radii.panel)", 1, true) ~= nil).toBe(true)
		expect(string.find(body :: string, "cornerRadiusFor(handle, style.radii.control)", 1, true) ~= nil).toBe(true)
	end)

	it(
		"the call site passes `handle` through, so `applyCorners` can tell which surface owns the shared UICorner",
		function()
			local source = fs.readFile("src/client/screen_props.luau")
			expect(string.find(source, "applyCorners(instance, value, handle)", 1, true) ~= nil).toBe(true)
		end
	)

	it("applyStroke already had the shape (the precedent, unpatched)", function()
		local body = applierBody("applyStroke", "stroke")
		expect(string.find(body, "if stroke == nil then", 1, true) ~= nil).toBe(true)
	end)
end)

-- ============================================================================
-- THE DRIVEN REPRODUCTION: a virtualized list (200 rows, VIEWPORT 360x640,
-- ROW_HEIGHT 56, overscan 2), ragged the way `instance_recycling.spec.luau`
-- established the term — every third row ("odd", `n % 3 == 0`) wires `shadow`
-- as a reactive `core:signal(nil)` on its outer HStack; every other row never
-- declares `shadow` at all.
-- ============================================================================

local ROW_HEIGHT = 56
local VIEWPORT = { w = 360, h = 640 }
local ROW_COUNT = 200
local REAL_SHADOW = Facet.UI.shadowData({ blurRadius = { scale = 0, offset = 8 } })

local function makeItems(n: number)
	local out = {}
	for i = 1, n do
		table.insert(out, { id = `r{i}`, label = `Row {i}`, detail = `detail {i * 7 % 13}` })
	end
	return out
end

-- Built on `tests/lib/world.luau` (REUSE-88 / R12's follow-up trigger).
-- `shadowSignals[id]` is built for every odd item UP FRONT, before any row
-- ever mounts, so "is this signal still nil" is answerable even for a row
-- that has not been on screen yet — a signal built lazily inside `cell()`
-- could not tell "not yet built" apart from "built and still nil".
local function buildWorld()
	local w = world.new({ viewport = { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h } })
	local items = makeItems(ROW_COUNT)
	local shadowSignals: { [string]: any } = {}
	for _, item in items do
		local n = tonumber(string.match(item.id, "%d+")) :: number
		if n % 3 == 0 then
			shadowSignals[item.id] = w.core:signal(nil :: any)
		end
	end
	local rows = w.core:signal(items)
	local list = virtual_list.build(Facet, w.core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = ROW_HEIGHT,
		viewportHeight = VIEWPORT.h,
		overscan = 2,
		cell = function(item: any)
			return Facet.UI.HStack({
				id = "Row",
				gap = 6,
				-- declared on EVERY odd row (reactive, starts nil); ABSENT on
				-- every other row
				shadow = shadowSignals[item.id],
				children = {
					Facet.UI.Text({ id = "Name", text = item.label, textSize = 15 }),
					Facet.UI.Text({ id = "Detail", text = item.detail, textSize = 12 }),
				},
			})
		end,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
	w.present(screen)
	list.bindNativeScroll(w.controller)
	local wAny = w :: any
	wAny.listDispose = list.dispose
	wAny.shadowSignals = shadowSignals
	return w
end

local function scrollTo(w: any, y: number)
	w.controller.scrollTo("/S/VL", { x = 0, y = y })
	w.pres.refresh()
	w.overflowGuard()
end

-- the item index a live path's window slot carries, or nil for a path that is
-- not one of these per-row roots (the Hit surface, the Name text, …). The
-- ForEach wraps each entry as `.../[r<n>]/Row/<cell's own root id>` (probed
-- against the live adapter, not assumed).
local function itemOf(path: string): number?
	return tonumber(string.match(path, "%[r(%d+)%]/Row/Row$"))
end

local function pathOf(w: any, n: number): string?
	for path in w.adapter.liveNodes() do
		if itemOf(path) == n then
			return path
		end
	end
	return nil
end

-- flip HALF the odd rows currently on screen (`n % 6 == 0`) whose signal is
-- still nil, called after every scroll step, so each is flipped the moment it
-- is first visible and PARKS CARRYING A LIVE SHADOW once the window moves
-- past it. THE OTHER HALF (`n % 3 == 0` but `n % 6 ~= 0`) IS NEVER FLIPPED —
-- those rows stay reactive-and-nil for the whole walk, which is the second
-- case's adopter shape below.
local function flipVisibleOdds(w: any)
	local flipped = false
	for path in w.adapter.liveNodes() do
		local n = itemOf(path)
		if n ~= nil and n % 6 == 0 then
			local sig = w.shadowSignals[`r{n}`]
			if sig:get() == nil then
				sig:set(REAL_SHADOW)
				flipped = true
			end
		end
	end
	if flipped then
		w.pres.refresh()
	end
end

-- WALK THE WHOLE LIST ONCE, calling `onVisible` after each scroll step (so a
-- case can flip/unflip signals as rows come into view), then churn back and
-- forth so every corrupted handle the walk parked is actually offered to a
-- later create rather than merely sitting in the pool (capped at 64 GLOBALLY,
-- not per bucket — `renderer.luau`'s `RECYCLE_POOL_CAP`).
local function walkAndChurn(w: any, onVisible: ((any) -> ())?)
	local content = ROW_COUNT * ROW_HEIGHT
	local stride = 240 -- less than one window's worth (640px), so no row is skipped
	local y = 0
	while y < content do
		scrollTo(w, y)
		if onVisible then
			onVisible(w)
		end
		y += stride
	end
	scrollTo(w, content)
	if onVisible then
		onVisible(w)
	end
	for _, top in { 0, content // 2 } do
		scrollTo(w, top)
		local yy = top
		for _ = 1, 25 do
			yy = (yy + 173) % content
			scrollTo(w, yy)
			if onVisible then
				onVisible(w)
			end
		end
	end
end

describe("W1b: the brief's own reproduction, now green", function()
	it("a row that NEVER declares shadow does not adopt an instance carrying one", function()
		local w = buildWorld()
		walkAndChurn(w, flipVisibleOdds)
		expect(w.controller.stats().parked > 0).toBe(true)
		expect(w.controller.stats().recycled > 0).toBe(true)

		local offenders: { string } = {}
		for path, node in w.adapter.liveNodes() do
			local n = itemOf(path)
			if n ~= nil and n % 3 ~= 0 and (node.props :: any).shadow ~= nil then
				table.insert(offenders, path)
			end
		end
		table.sort(offenders)
		local message = `non-shadow rows carrying a shadow: {table.concat(offenders, ",")}`
		expect(message).toBe("non-shadow rows carrying a shadow: ")
		local wAny = w :: any
		wAny.listDispose()
	end)

	it("a row that declares shadow reactively but currently resolves nil does not adopt one either", function()
		local w = buildWorld()
		walkAndChurn(w, flipVisibleOdds)

		local offenders: { string } = {}
		for path, node in w.adapter.liveNodes() do
			local n = itemOf(path)
			-- an odd row currently on screen whose OWN signal still reads nil: it
			-- declares `shadow` reactively and is not one this walk ever flipped
			if
				n ~= nil
				and n % 3 == 0
				and (w :: any).shadowSignals[`r{n}`]:get() == nil
				and (node.props :: any).shadow ~= nil
			then
				table.insert(offenders, path)
			end
		end
		table.sort(offenders)
		local message = `nil-resolving shadow rows carrying a shadow: {table.concat(offenders, ",")}`
		expect(message).toBe("nil-resolving shadow rows carrying a shadow: ")
		local wAny = w :: any
		wAny.listDispose()
	end)
end)

describe("W1b: the value crossing the OTHER direction — real, then back to nil, while mounted", function()
	it(
		"shadow real -> nil while on screen does not crash, clears the adapter immediately, and does not leak later",
		function()
			local w = buildWorld()
			scrollTo(w, 0)
			local sig = (w :: any).shadowSignals["r3"] -- r3: n % 3 == 0, visible at the top
			local path3 = pathOf(w, 3)
			expect(path3 ~= nil).toBe(true)

			-- FIRST CROSSING: nil -> real, while mounted
			sig:set(REAL_SHADOW)
			w.pres.refresh()
			expect(w.adapter.liveNodes()[path3 :: string].props.shadow ~= nil).toBe(true)

			-- SECOND CROSSING, THE ONE THIS CASE EXISTS FOR: real -> nil, STILL
			-- mounted (row 3 has not scrolled anywhere — this is the reactive commit
			-- path, `applyStyleProp` called with a nil value, not the create path).
			-- Completing this call at all — rather than crashing inside
			-- `applyShadow` indexing `shadow.blurRadius` on nil — is half the proof.
			sig:set(nil)
			w.pres.refresh()
			expect(w.adapter.liveNodes()[path3 :: string].props.shadow).toBe(nil)

			-- now let it depart (park) and churn hard so its handle — filed under
			-- whatever key the WORN SET said it wore at that moment — is actually
			-- offered to later creates
			walkAndChurn(w, flipVisibleOdds)
			expect(pathOf(w, 3)).toBe(nil) -- long gone from the window by now
			expect(w.controller.stats().parked > 0).toBe(true)
			expect(w.controller.stats().recycled > 0).toBe(true)

			-- THE FULL ENUMERATION: every live row's adapter-held shadow must agree
			-- with what ITS OWN current declaration says — never-declares rows and
			-- still-nil reactive rows carry none; a row this walk actually flipped
			-- (and never un-flipped) carries one. If row 3's park had filed its
			-- handle under a STALE "has shadow" key (the pre-W1b defect), some
			-- later row here would disagree with its own declaration.
			local offenders: { string } = {}
			for path, node in w.adapter.liveNodes() do
				local n = itemOf(path)
				if n ~= nil then
					local hasShadow = (node.props :: any).shadow ~= nil
					local shouldHave = n % 6 == 0 -- the only rows `flipVisibleOdds` ever sets real
					if hasShadow ~= shouldHave then
						table.insert(offenders, `{path}(has={hasShadow},should={shouldHave})`)
					end
				end
			end
			table.sort(offenders)
			local message = `rows disagreeing with their own declaration: {table.concat(offenders, ",")}`
			expect(message).toBe("rows disagreeing with their own declaration: ")
			local wAny = w :: any
			wAny.listDispose()
		end
	)
end)

describe("W1b: no risk at all when a row's declared props never cross nil", function()
	it("recycles hard, and no row ever carries a shadow it did not itself declare as real", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h } })
		local items = makeItems(ROW_COUNT)
		local shadowSignals: { [string]: any } = {}
		for _, item in items do
			local n = tonumber(string.match(item.id, "%d+")) :: number
			if n % 3 == 0 then
				shadowSignals[item.id] = w.core:signal(REAL_SHADOW)
			end
		end
		local rows = w.core:signal(items)
		local list = virtual_list.build(Facet, w.core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = ROW_HEIGHT,
			viewportHeight = VIEWPORT.h,
			overscan = 2,
			cell = function(item: any)
				return Facet.UI.HStack({
					id = "Row",
					gap = 6,
					shadow = shadowSignals[item.id],
					children = {
						Facet.UI.Text({ id = "Name", text = item.label, textSize = 15 }),
						Facet.UI.Text({ id = "Detail", text = item.detail, textSize = 12 }),
					},
				})
			end,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
		w.present(screen)
		list.bindNativeScroll(w.controller)
		walkAndChurn(w)
		expect(w.controller.stats().parked > 0).toBe(true)
		expect(w.controller.stats().recycled > 0).toBe(true)

		local offenders: { string } = {}
		for path, node in w.adapter.liveNodes() do
			local n = itemOf(path)
			local hasShadow = (node.props :: any).shadow ~= nil
			if n ~= nil and hasShadow ~= (n % 3 == 0) then
				table.insert(offenders, path)
			end
		end
		table.sort(offenders)
		expect(`rows whose shadow disagrees with their own declaration: {table.concat(offenders, ",")}`).toBe(
			"rows whose shadow disagrees with their own declaration: "
		)
		list.dispose()
	end)
end)

-- ============================================================================
-- T8 R2, CRITICAL 1 — THE RAGGED-BINDING CASE (the review's own probe, folded
-- in). `enabled` (BINDING_PROPS) on every third row's Button; absent
-- everywhere else. RED at `8c25c4f5` (W1b's create-time key was STYLE_PROPS
-- only, so it did not separate these two shapes); GREEN after this round's
-- fix. Every Button's own root IS the cell (`id = "Row"`), so `itemOf`/
-- `pathOf` above read it unchanged.
-- ============================================================================

describe("T8 R2, Critical 1: the create-time key signs BINDING as well as STYLE", function()
	it("a row that never declares `enabled` does not adopt an instance wearing a stale `enabled = false`", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h } })
		local items = makeItems(ROW_COUNT)
		local rows = w.core:signal(items)
		local list = virtual_list.build(Facet, w.core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = ROW_HEIGHT,
			viewportHeight = VIEWPORT.h,
			overscan = 2,
			cell = function(item: any)
				local n = tonumber(string.match(item.id, "%d+")) :: number
				return Facet.UI.Button({
					id = "Row",
					label = item.label,
					-- declared (false) on every third row only; ABSENT (nil, not
					-- merely true) everywhere else — the review's own shape
					enabled = if n % 3 == 0 then false else nil,
					onActivate = function() end,
				})
			end,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
		w.present(screen)
		list.bindNativeScroll(w.controller)
		walkAndChurn(w)
		expect(w.controller.stats().parked > 0).toBe(true)
		expect(w.controller.stats().recycled > 0).toBe(true)

		local offenders: { string } = {}
		local checked = 0
		for path, node in w.adapter.liveNodes() do
			local n = itemOf(path)
			if n ~= nil then
				checked += 1
				local declares = n % 3 == 0
				local wears = (node.props :: any).enabled ~= nil
				if wears ~= declares then
					table.insert(offenders, `{path}(wears={tostring((node.props :: any).enabled)},declares={declares})`)
				end
			end
		end
		table.sort(offenders)
		expect(checked > 0).toBe(true)
		expect(`rows disagreeing with their own enabled declaration: {table.concat(offenders, ",")}`).toBe(
			"rows disagreeing with their own enabled declaration: "
		)
		list.dispose()
	end)
end)

-- ============================================================================
-- T8 R2 — THE RAGGED-LAYOUT SAFETY PIN. `padding` (a LAYOUT prop, excluded
-- from the recycle key by ruling) on every third row's Text; absent
-- everywhere else. GREEN BOTH BEFORE AND AFTER this round — nothing in T8 R2
-- touches `padding` at all. It pins the EXCLUSION's safety (the value-diff
-- cache + explicit un-pad branch `commit_walks.padding` already carries), not
-- a fix: if this case ever reddened, excluding layout from the key would be
-- the wrong call, not merely an unproven one.
-- ============================================================================

describe(
	"T8 R2: the layout channel stays excluded from the key on purpose — pinning why that is still safe",
	function()
		it("a row that never declares `padding` does not adopt an instance wearing a stale text inset", function()
			local w = world.new({ viewport = { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h } })
			local items = makeItems(ROW_COUNT)
			local rows = w.core:signal(items)
			local list = virtual_list.build(Facet, w.core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				rowHeight = ROW_HEIGHT,
				viewportHeight = VIEWPORT.h,
				overscan = 2,
				cell = function(item: any)
					local n = tonumber(string.match(item.id, "%d+")) :: number
					return Facet.UI.Text({
						id = "Row",
						text = item.label,
						padding = if n % 3 == 0 then 8 else nil,
					})
				end,
			})
			local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
			w.present(screen)
			list.bindNativeScroll(w.controller)
			walkAndChurn(w)
			expect(w.controller.stats().parked > 0).toBe(true)
			expect(w.controller.stats().recycled > 0).toBe(true)

			local offenders: { string } = {}
			local checked = 0
			for path, node in w.adapter.liveNodes() do
				local n = itemOf(path)
				if n ~= nil then
					checked += 1
					local declares = n % 3 == 0
					-- the adapter's recorded `padding` keeps `resolveSides`'
					-- SHAPE: the uniform number this fixture declares (8) stays a
					-- bare number, while the un-pad branch's explicit zero record
					-- is the TABLE `{top=0,right=0,bottom=0,left=0}` — never
					-- simply nil once an instance has ever worn a real one
					-- (`commit_walks.padding`'s own comment: "zeroing is a write;
					-- skipping is a stale glyph box"). So "wears" means a
					-- non-zero recorded inset, in whichever shape it arrived.
					local pad = (node.props :: any).padding
					local wears = if pad == nil
						then false
						elseif type(pad) == "number" then pad ~= 0
						else pad.top ~= 0 or pad.right ~= 0 or pad.bottom ~= 0 or pad.left ~= 0
					if wears ~= declares then
						table.insert(offenders, `{path}(padding={tostring(pad)},declares={declares})`)
					end
				end
			end
			table.sort(offenders)
			expect(checked > 0).toBe(true)
			expect(`rows disagreeing with their own padding declaration: {table.concat(offenders, ",")}`).toBe(
				"rows disagreeing with their own padding declaration: "
			)
			list.dispose()
		end)
	end
)

-- ============================================================================
-- T8 R2, IMPORTANT 2 — THE COMPACT-LADDER CASE. Every row's label is far too
-- long for its fixed 50px width, so every row goes compact from its FIRST
-- solve and the compact ladder's write always fires the moment a row appears.
-- Even rows (`n % 2 == 0`) declare an ICON-form `compactLabel` — the ladder
-- writes a real `icon` alongside it. Odd rows declare an IMAGE-form
-- `compactLabel` — the ladder writes ONLY `compactLabel`, never `icon`, and
-- an odd row's OWN props never mention `icon` at all. Before this round's
-- fix, neither write touched the worn set, so an odd row's create-time
-- signature ({compactLabel}) and an even row's PARKED signature
-- ({compactLabel} too — `icon` untracked) could collide, letting an odd row
-- adopt an even row's instance and inherit its glyph.
-- ============================================================================

describe("T8 R2, Important 2: the compact ladder's derived writes route through the same worn-set updater", function()
	it("an image-form row never adopts an icon-form row's stray `icon`", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h } })
		local items = makeItems(ROW_COUNT)
		local rows = w.core:signal(items)
		local list = virtual_list.build(Facet, w.core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = ROW_HEIGHT,
			viewportHeight = VIEWPORT.h,
			overscan = 2,
			cell = function(item: any)
				local n = tonumber(string.match(item.id, "%d+")) :: number
				local longLabel = `This label is far too long to fit in fifty pixels, row {item.id}`
				local compactLabel = if n % 2 == 0 then { icon = "flag" } else { image = "rbxassetid://1" }
				return Facet.UI.Button({
					id = "Row",
					label = longLabel,
					compactLabel = compactLabel,
					width = { type = "fixed", px = 50 },
					onActivate = function() end,
				})
			end,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
		w.present(screen)
		list.bindNativeScroll(w.controller)
		walkAndChurn(w)
		expect(w.controller.stats().parked > 0).toBe(true)
		expect(w.controller.stats().recycled > 0).toBe(true)

		local offenders: { string } = {}
		local checked = 0
		for path, node in w.adapter.liveNodes() do
			local n = itemOf(path)
			if n ~= nil and n % 2 == 1 then
				checked += 1
				if (node.props :: any).icon ~= nil then
					table.insert(offenders, `{path}(icon={tostring((node.props :: any).icon)})`)
				end
			end
		end
		table.sort(offenders)
		expect(checked > 0).toBe(true)
		expect(`image-form rows carrying a stray icon: {table.concat(offenders, ",")}`).toBe(
			"image-form rows carrying a stray icon: "
		)
		list.dispose()
	end)
end)

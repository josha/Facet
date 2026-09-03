--!strict
--[[ W1b — A RECYCLED INSTANCE DOES NOT KEEP A STYLE PROP IT NEVER DECLARED.

	W1 (`fa289d5a`) deleted `propSigCache`, keyed on the props TABLE identity and
	never invalidated while `mount.luau`'s `mountNode` mutates that table in place
	(its dynamic-prop observer writes `node.props[propName]`). Self-review (Step 7,
	mandatory) found the theory wrong, then measured why: the cache was never the
	mechanism. `propSignature` had exactly two call sites, both inside the ONE
	`if handles[node.path] == nil` block that only ever runs at a node's own
	CREATE — nothing mutates `node.props` between them, so a cache hit there was
	always a hit on the value that SAME call's own first read had just computed,
	never a stale one (measured: every hit recorded
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
	`applyCorners` does NOT own its UICorner — `applySurface`, the bare-circle
	fallback, `wireInteractiveStates` and `screen_chrome`'s
	`applySlotNativePaint` all share the same single child — so W1b's own first
	draft (`Destroy()` unconditionally) stripped a static `surface`'s radius the
	moment a sibling reactive `corners` crossed to nil.

	T8 R3 (re-review, Important 3 re-opened) — R2's ANSWER WAS THE WRONG
	MECHANISM. It re-derived each owner's radius choice from
	`handle.declaredSurface` in a table beside `applyCorners`, and that table
	mirrored four owners out of six: it never knew `wireInteractiveStates`'
	`corner(button, style.radii.control, nil, handle)` (EVERY fallback-mode
	Button and Toggle, independent of any declared `surface`) nor
	`applySlotNativePaint`'s `SLOT_ROUND_FALLBACK` radii, so a plain Button with
	no surface still lost its corner on a nil write. THE OWNER RECORDS WHAT IT
	PAINTED instead: every chrome writer that materialises the node's own
	UICorner leaves the resolved `UDim` on `handle.chromeCornerRadius`, and the
	nil branch restores exactly that record — same Instance — or destroys only
	when there is no record at all. Native mode needs no branch: every chrome
	owner returns before painting there, so nothing is recorded and the sheet's
	phantom `::UICorner` rule keeps the radius, exactly as W1b left it. The
	enumerating pin below is what stops the classification drifting again. `surface`, `role`, `textAlign`, `shape`, `scaleMode`,
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
	SOURCE-SHAPE, not driven; the live proof is a Studio canary (T9 runs it),
	four lines because R2's single line only exercised the half that worked:
	(i) `surface = "raised"` + reactive `corners` real -> nil keeps the SAME
	UICorner at `style.radii.panel`; (ii) a plain Button with NO surface, in
	fallback mode, same real -> nil, keeps the same UICorner at
	`style.radii.control`; (iii) a non-Button with no surface and no shape
	loses the UICorner on nil and gets one back on real; (iv) in NATIVE mode no
	bespoke UICorner remains after nil, on any surface. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local src_tree = require("./lib/src_tree")
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
	"T8 R2/R3: the audit table's set is exhaustive — every setProp( call site in src/render/*.luau is accounted for",
	function()
		--[[ R3 (re-review Minor 2) REPLACED A COUNT WITH A SET. The R2 form read
			FOUR HARDCODED PATHS and asserted `#sites == 13`, while its own describe
			promised "every `adapter.setProp(` call site in `src/render/*.luau`" —
			`src/render/` holds twenty-five modules, so a write added in any of the
			other twenty-one was invisible, and an add-plus-remove inside the four
			kept the count green. This walks the directory through `src_tree` and
			compares the SET.

			The key is (file, prop, authority), not a line number: line numbers make
			every unrelated edit a false failure, and the AUTHORITY is what separates
			the renderer's two generic choke points, which write the same `prop`
			variable. A site whose call head cannot be read at all is keyed by its own
			raw text so the failure names it. ]]
		it("the choke points, the layout sites and the presentation/registry exceptions are ALL of them", function()
			local CLASSIFIED: { [string]: string } = {
				-- CHOKE POINTS: both now call `noteWorn`, which is what makes the
				-- park key and the create signature the same namespace.
				["renderer.luau|prop|binding"] = "choke point (binding, incl. the late `tint` write)",
				["renderer.luau|prop|style"] = "choke point (style)",
				-- CHOKE-POINT-EQUIVALENT (Important 2): style/binding authority, but
				-- a DERIVED value, so they route through the `noteWorn` dep instead.
				['commit_walks.luau|"label"|binding'] = "choke-point-equivalent via noteWorn",
				['commit_walks.luau|"icon"|style'] = "choke-point-equivalent via noteWorn",
				['commit_walks.luau|"compactLabel"|style'] = "choke-point-equivalent via noteWorn",
				-- LAYOUT, excluded by ruling: each is value-diffed against a cache
				-- `captureParkedProps`/`restoreParkedProps` carry across an adoption,
				-- so a tracked name's ABSENCE never leaves a stale bespoke child.
				['commit_walks.luau|"textSize"|layout'] = "layout, value-diffed by lastTextSize",
				['commit_walks.luau|"textFont"|'] = "layout, value-diffed by lastTextFont",
				['commit_walks.luau|"padding"|layout'] = "layout, value-diffed by lastPadding + the un-pad branch",
				['commit_walks.luau|"textWrapped"|layout'] = "layout, value-diffed by lastWrapped",
				['renderer.luau|"clipChildren"|layout'] = "layout, re-derived every solve",
				-- EXCEPTIONS: outside BINDING_PROPS ∪ STYLE_PROPS entirely, and each
				-- with its own reason a park can never carry it into the pool.
				['drag_bridge.luau|"dragHeld"|presentation'] = "exception: EMITTED_PROPS carve-out; the drag sweep tears it down before park",
				['presentation_channel.luau|"transform"|presentation'] = "exception: DIRECT_PROPS; park refuses a live presentation transform",
				['presentation_channel.luau|"transparency"|presentation'] = "exception: DIRECT_PROPS; same park refusal",
			}

			local function stripComments(source: string): string
				local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
				out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
				return out
			end

			local seen: { [string]: boolean } = {}
			local files = 0
			for _, path in src_tree.paths() do
				local file = string.match(path, "^src/render/([%w_]+%.luau)$")
				if file == nil then
					continue
				end
				files += 1
				for line in string.gmatch(stripComments(fs.readFile(path)) .. "\n", "(.-)\n") do
					if string.find(line, "adapter.setProp(", 1, true) ~= nil then
						local prop = string.match(line, "adapter%.setProp%([^,]*,%s*([^,]+),")
						local authority = string.match(line, '"(%a+)"%)%s*$')
						if prop == nil then
							seen[`{file}|RAW {string.match(line, "^%s*(.-)%s*$") :: string}`] = true
						else
							seen[`{file}|{prop}|{authority or ""}`] = true
						end
					end
				end
			end
			-- the walk really reached the directory (`src/render` is 25 modules, not
			-- the four the R2 form read)
			expect(files >= 20).toBe(true)

			local unclassified: { string } = {}
			for entry in seen do
				if CLASSIFIED[entry] == nil then
					table.insert(unclassified, entry)
				end
			end
			table.sort(unclassified)
			expect(`unclassified setProp sites: {table.concat(unclassified, " ~ ")}`).toBe(
				"unclassified setProp sites: "
			)

			local stale: { string } = {}
			for entry in CLASSIFIED do
				if not seen[entry] then
					table.insert(stale, entry)
				end
			end
			table.sort(stale)
			expect(`classified but absent: {table.concat(stale, " ~ ")}`).toBe("classified but absent: ")
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
		"applyCorners: `cornersData == nil` RESTORES the recorded chrome radius (T8 R3, Important 3) — no unconditional Destroy",
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
			-- the nil branch reads the RECORD the owners wrote (it re-derives
			-- nothing at all now) and only reaches `existing:Destroy()` INSIDE
			-- the "no owner ever claimed it" fallback, not unconditionally
			local nilBranch = string.match(body :: string, "if cornersData == nil then(.-)\n\t\tend")
			assert(nilBranch ~= nil, "the nil branch was not found to read")
			expect(string.find(nilBranch :: string, "handle.chromeCornerRadius", 1, true) ~= nil).toBe(true)
			-- ...and R2's mirrored table is GONE, not merely unused
			expect(string.find(source, "chromeDefaultRadius", 1, true)).toBe(nil)
			expect(string.find(nilBranch :: string, "uiCorner.CornerRadius = restored", 1, true) ~= nil).toBe(true)
			expect(string.find(nilBranch :: string, "child:Destroy()", 1, true) ~= nil).toBe(true)
			-- `restored == nil` gates the ONLY destroy this branch reaches, and it
			-- sweeps EVERY UICorner (RED-TEAM T9, finding 3) rather than the first
			-- one it finds — the shape every other eraser on this instance has
			local destroyGuard = string.match(nilBranch :: string, "if restored == nil then(.-)\n\t\t\tend")
			assert(destroyGuard ~= nil, "the restored == nil guard was not found to read")
			expect(string.find(destroyGuard :: string, "for _, child in instance:GetChildren() do", 1, true) ~= nil).toBe(
				true
			)
			expect(string.find(destroyGuard :: string, "child:Destroy()", 1, true) ~= nil).toBe(true)
			expect(string.find(nilBranch :: string, "FindFirstChildOfClass", 1, true) ~= nil).toBe(true)
		end
	)

	--[[ EVERY CORNER SITE IN `src/client/` CLASSIFIES ITSELF (T8 R3, Important 3;
		the ERASERS and their record clears, T8 R4, New Important 1).

		R2 shipped a table beside `applyCorners` that MIRRORED each chrome owner's
		radius choice, and it was wrong on the day it was written — it covered four
		of the six writers of the node's own UICorner. A mirror cannot be pinned
		("does this table still agree with six other functions?" has no mechanical
		answer); a CLASSIFICATION can. This walks `src/client/` itself, finds every
		line that names a UICorner at all, and requires each one to appear in the
		table below with a bucket. A site added anywhere in that directory that
		records nothing is UNCLASSIFIED and fails here, naming its own text —
		which is exactly the failure R2 could not produce.

		R3'S PREDICATE COULD NOT SEE A DESTROY, and that is how the eraser defect
		shipped under a green pin: it matched `Instance.new("UICorner")`,
		`corner(`, `.CornerRadius =` and `chromeCornerRadius =`, so a
		`for _, child in instance:GetChildren()` loop that destroys the node's own
		UICorner matched nothing at all. The predicate is now the TOKEN rule — any
		line naming `UICorner` or `CornerRadius`, or calling `corner(`, is a site.
		`child:Destroy()` still carries no token, but the line that SELECTS the
		child to destroy has to name the class, so the selector IS the site and it
		takes the bucket of the block it guards.

		KEYED BY (file, enclosing function, normalised text). The function is part
		of the key because `if child:IsA("UICorner") then` occurs in
		`screen_chrome.luau` twice with two different meanings — the skinned
		suppression zeroes the node's OWN corner, `setTogglePartChrome` repaints
		the toggle's separate track/knob children — and no one bucket is true of
		both. It also means a new destroy loop in a NEW function cannot inherit an
		existing classification.

		The buckets:
		  records         a chrome owner that materialises the node's OWN UICorner
		                  and writes `handle.chromeCornerRadius` (the read that
		                  decides whether it needs one included)
		  record-write    those writes themselves, pinned so a recorder cannot be
		                  quietly dropped while its `corner()` call stays
		  record-clear    `handle.chromeCornerRadius = nil`, an eraser giving the
		                  record up, pinned the same way
		  record-read     reads the record to decide what to do next; writes no
		                  radius itself
		  updates-record  re-radiuses an existing corner and keeps the record true
		                  (never CREATES a record: it does not own the child)
		  erases          removes or zeroes the node's own UICorner while a record
		                  may exist — so it MUST clear the record in the same block,
		                  which the balance check below enforces
		  releases        `applyCorners`' nil branch tearing the corner down. It is
		                  reached only inside `if restored == nil`, i.e. only when no
		                  chrome owner ever claimed the child, so there is nothing
		                  to clear — which is why it is NOT `erases` and is kept out
		                  of the balance check. Its selector is the same
		                  `if child:IsA("UICorner") then` line the two real erasers
		                  use; the enclosing function is what separates them
		  prop            `applyCorners`' own authored-`corners` write — the PROP,
		                  which must never record or the next nil write would
		                  restore the value it is releasing
		  not-own-child   paints some OTHER instance's corner (the toggle's real
		                  track/knob children, the focus ring's float and the read
		                  of the host corner it mirrors, a decoration mask) —
		                  `applyCorners` never sees these
		  probe           a capability probe instance, destroyed on the next line
		  paint-guard     `assertBespokePaint("CornerRadius")`: the native-mode
		                  refusal, which writes no radius and owns no instance
		  suppression     the skinned-node override's zero write. It records
		                  nothing on purpose — its own selector is the `erases`
		                  entry that clears the record for it

		SET, not line numbers: two identical calls in one function are one entry,
		because the classification is a property of the CALL, not of where it sits.
		The eraser balance is the one check that counts OCCURRENCES, and it says
		there why. ]]
	it("every UICorner site in src/client/ is classified, and the recorders are all of them", function()
		-- bucket per (file, enclosing function, normalised call text). Text is the
		-- statement with its indentation, trailing comment and inner whitespace
		-- runs normalised away.
		local CLASSIFIED: { [string]: string } = {
			-- ===== screen_paint.luau =========================================
			-- `corner()` is the ONE materialiser for every surface, the bare
			-- circle and `wireInteractiveStates` — so it is the one recorder.
			['screen_paint.luau|corner|assertBespokePaint("CornerRadius")'] = "paint-guard",
			['screen_paint.luau|corner|local uiCorner = Instance.new("UICorner")'] = "records",
			["screen_paint.luau|corner|uiCorner.CornerRadius = resolved"] = "records",
			["screen_paint.luau|corner|handle.chromeCornerRadius = resolved"] = "record-write",
			["screen_paint.luau|applySurface|corner(instance, style.radii.panel, nil, handle)"] = "records",
			["screen_paint.luau|applySurface|corner(instance, style.radii.control, nil, handle)"] = "records",
			["screen_paint.luau|wireInteractiveStates|corner(button, style.radii.control, nil, handle)"] = "records",
			-- the bare tinted circle, and the read that decides it needs a corner
			['screen_paint.luau|applyTint|if instance:FindFirstChildOfClass("UICorner") == nil then'] = "records",
			["screen_paint.luau|applyTint|corner(instance, style.radii.control, nil, handle)"] = "records",
			-- ...and `applySurface`'s badge branch, the one surface that builds
			-- its own circle instead of calling `corner()`
			['screen_paint.luau|applySurface|local circle = Instance.new("UICorner")'] = "records",
			["screen_paint.luau|applySurface|circle.CornerRadius = UDim.new(0.5, 0)"] = "records",
			["screen_paint.luau|applySurface|handle.chromeCornerRadius = UDim.new(0.5, 0)"] = "record-write",
			-- `plain` and `scrim` REMOVE the node's own corner. The selector is the
			-- site (`child:Destroy()` names no class), and each of those two loops
			-- clears the record in its own block — counted, not just present.
			['screen_paint.luau|applySurface|if child:IsA("UICorner") then'] = "erases",
			["screen_paint.luau|applySurface|handle.chromeCornerRadius = nil"] = "record-clear",
			-- the toggle knob/track assembly: real CHILDREN of the node, passed
			-- no handle at all, and never the child `applyCorners` writes into
			["screen_paint.luau|buildToggleVisual|corner(track, style.radii.pill, true)"] = "not-own-child",
			["screen_paint.luau|buildToggleVisual|corner(knob, style.radii.pill, true)"] = "not-own-child",
			-- `applyCorners` itself: the restore reads the record, the authored
			-- path writes the PROP and records nothing
			['screen_paint.luau|applyCorners|local restored = if type(handle) == "table" then handle.chromeCornerRadius else nil'] = "record-read",
			-- ...and the teardown sweeps `GetChildren()` like every other eraser on
			-- this instance (RED-TEAM T9, finding 3): a node can wear two UICorners,
			-- and "no record" means no chrome owner claims ANY of them
			['screen_paint.luau|applyCorners|if child:IsA("UICorner") then'] = "releases",
			['screen_paint.luau|applyCorners|local uiCorner = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")'] = "prop",
			["screen_paint.luau|applyCorners|uiCorner.CornerRadius = restored"] = "updates-record",
			["screen_paint.luau|applyCorners|uiCorner.CornerRadius = UDim.new(0, corners.radius)"] = "prop",
			["screen_paint.luau|applyCorners|uiCorner.CornerRadius = UDim.new(0, top)"] = "prop",
			-- ===== screen_chrome.luau ========================================
			-- the value-control slots' own fallback paint (SLOT_ROUND_FALLBACK)
			['screen_chrome.luau|applySlotNativePaint|local uiCorner = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")'] = "records",
			["screen_chrome.luau|applySlotNativePaint|uiCorner.CornerRadius = slotRadius"] = "records",
			["screen_chrome.luau|applySlotNativePaint|handle.chromeCornerRadius = slotRadius"] = "record-write",
			-- the skinned override: its selector erases (the art replaces the
			-- chrome), so the same block gives the record up
			['screen_chrome.luau|applySkinnedSuppression|if child:IsA("UICorner") then'] = "erases",
			["screen_chrome.luau|applySkinnedSuppression|(child :: UICorner).CornerRadius = UDim.new(0, 0)"] = "suppression",
			["screen_chrome.luau|applySkinnedSuppression|handle.chromeCornerRadius = nil"] = "record-clear",
			-- a decoration layer's own mask instance, and the toggle parts again
			['screen_chrome.luau|buildChromeStack|local corner = Instance.new("UICorner")'] = "not-own-child",
			["screen_chrome.luau|buildChromeStack|corner.CornerRadius = UDim.new(0.5, 0)"] = "not-own-child",
			['screen_chrome.luau|setTogglePartChrome|if child:IsA("UICorner") then'] = "not-own-child",
			["screen_chrome.luau|setTogglePartChrome|(child :: UICorner).CornerRadius = if skinned then UDim.new(0, 0) else UDim.new(0, style.radii.pill)"] = "not-own-child",
			-- ===== screen_props.luau =========================================
			-- the `shape` write re-radiuses whatever corner is already there
			['screen_props.luau|setProp|assertBespokePaint("CornerRadius")'] = "paint-guard",
			['screen_props.luau|setProp|if child:IsA("UICorner") then'] = "updates-record",
			["screen_props.luau|setProp|(child :: UICorner).CornerRadius = reshaped"] = "updates-record",
			["screen_props.luau|setProp|if handle.chromeCornerRadius ~= nil then"] = "record-read",
			["screen_props.luau|setProp|handle.chromeCornerRadius = reshaped"] = "record-write",
			-- ===== screen_target.luau ========================================
			-- a per-corner-radii capability probe, destroyed on the next line
			['screen_target.luau|hasPerCornerRadii|local probe = Instance.new("UICorner")'] = "probe",
			-- the focus ring's FLOAT: its own instance, mirroring the node's
			['screen_target.luau|adapter.setFocusVisual|local realCorner = host:FindFirstChildOfClass("UICorner")'] = "not-own-child",
			['screen_target.luau|adapter.setFocusVisual|local floatCorner = float:FindFirstChildOfClass("UICorner")'] = "not-own-child",
			["screen_target.luau|adapter.setFocusVisual|(floatCorner :: UICorner).CornerRadius = realCorner.CornerRadius"] = "not-own-child",
			['screen_target.luau|adapter.setFocusVisual|floatCorner = Instance.new("UICorner")'] = "not-own-child",
			["screen_target.luau|adapter.setFocusVisual|(floatCorner :: UICorner).CornerRadius = radius"] = "not-own-child",
		}

		local function stripComments(source: string): string
			local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
			out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
			return out
		end
		local function normalise(line: string): string
			local text = string.gsub(line, "%-%-.*$", "")
			text = string.gsub(text, "%s+", " ")
			return string.match(text, "^%s*(.-)%s*$") :: string
		end
		-- the function a line sits in, tracked as the walk goes: a named
		-- declaration (`local function f(`, `function adapter.f(`, `function f<T>(`)
		-- or an assigned one (`f = function(`, `local f = (function(`). A callback
		-- declared inside one keeps that function's name, which is what the key
		-- wants — the callback is part of the same site.
		local function enclosingFunction(line: string, current: string): string
			local named = string.match(line, "function%s+([%w_%.:]+)%s*[<(]")
			if named ~= nil then
				return named
			end
			local assigned = string.match(line, "^%s*local%s+([%w_]+)%s*=%s*%(?function%s*%(")
				or string.match(line, "^%s*([%w_]+)%s*=%s*%(?function%s*%(")
			if assigned ~= nil then
				return assigned
			end
			return current
		end

		-- COUNTED, not just collected: the balance check below needs occurrences.
		local seen: { [string]: number } = {}
		local files = 0
		for _, path in src_tree.paths() do
			local file = string.match(path, "^src/client/([%w_]+%.luau)$")
			if file == nil then
				continue
			end
			files += 1
			local fn = "?"
			for line in string.gmatch(stripComments(fs.readFile(path)) .. "\n", "(.-)\n") do
				fn = enclosingFunction(line, fn)
				local isSite = string.find(line, "UICorner", 1, true) ~= nil
					or string.find(line, "CornerRadius", 1, true) ~= nil
					or string.find(line, "corner(", 1, true) ~= nil
				if isSite then
					local entry = `{file}|{fn}|{normalise(line)}`
					seen[entry] = (seen[entry] or 0) + 1
				end
			end
		end
		-- the walk really reached the directory: `src/client/` holds 26 modules and
		-- every classified entry lives in four of them, so a path filter that
		-- regressed to those four has to fail here rather than pass
		expect(files >= 20).toBe(true)

		local unclassified: { string } = {}
		for entry in seen do
			if CLASSIFIED[entry] == nil then
				table.insert(unclassified, entry)
			end
		end
		table.sort(unclassified)
		expect(`unclassified: {table.concat(unclassified, " ~ ")}`).toBe("unclassified: ")

		local stale: { string } = {}
		for entry in CLASSIFIED do
			if not seen[entry] then
				table.insert(stale, entry)
			end
		end
		table.sort(stale)
		expect(`classified but absent: {table.concat(stale, " ~ ")}`).toBe("classified but absent: ")

		--[[ EVERY ERASER CLEARS THE RECORD, IN THE SAME FILE AND IN THE SAME
			NUMBER (T8 R4). This is the one check that counts OCCURRENCES rather
			than distinct text: `applySurface` holds TWO identical destroy loops
			(`plain` and `scrim`) and two identical clears, so a set comparison
			would let one clear be deleted and hide behind the other. ]]
		local erases: { [string]: number } = {}
		local clears: { [string]: number } = {}
		for entry, count in seen do
			local file = string.match(entry, "^([^|]+)|") :: string
			local bucket = CLASSIFIED[entry]
			if bucket == "erases" then
				erases[file] = (erases[file] or 0) + count
			elseif bucket == "record-clear" then
				clears[file] = (clears[file] or 0) + count
			end
		end
		local eraserFiles: { [string]: boolean } = {}
		for file in erases do
			eraserFiles[file] = true
		end
		for file in clears do
			eraserFiles[file] = true
		end
		local imbalance: { string } = {}
		local totalErases, totalClears = 0, 0
		for file in eraserFiles do
			local eraseCount = erases[file] or 0
			local clearCount = clears[file] or 0
			totalErases += eraseCount
			totalClears += clearCount
			if eraseCount ~= clearCount then
				table.insert(imbalance, `{file} {eraseCount} erase / {clearCount} clear`)
			end
		end
		table.sort(imbalance)
		expect(`erasers vs record clears: {table.concat(imbalance, " ~ ")}`).toBe("erasers vs record clears: ")
		expect(totalErases).toBe(totalClears)

		-- ...and the RECORDERS are the three the mechanism names: `corner()`,
		-- the badge branch, `applySlotNativePaint`; the ERASERS are the two that
		-- remove the node's own corner, each with its clear. Counted through the
		-- buckets that make a site what it is, so none can be quietly dropped
		-- while the call it belongs to stays.
		local function bucketKeys(bucket: string): { string }
			local out: { string } = {}
			for entry, value in CLASSIFIED do
				if value == bucket then
					table.insert(out, entry)
				end
			end
			table.sort(out)
			return out
		end
		expect(bucketKeys("record-write")).toEqual({
			"screen_chrome.luau|applySlotNativePaint|handle.chromeCornerRadius = slotRadius",
			"screen_paint.luau|applySurface|handle.chromeCornerRadius = UDim.new(0.5, 0)",
			"screen_paint.luau|corner|handle.chromeCornerRadius = resolved",
			"screen_props.luau|setProp|handle.chromeCornerRadius = reshaped",
		})
		expect(bucketKeys("erases")).toEqual({
			'screen_chrome.luau|applySkinnedSuppression|if child:IsA("UICorner") then',
			'screen_paint.luau|applySurface|if child:IsA("UICorner") then',
		})
		expect(bucketKeys("record-clear")).toEqual({
			"screen_chrome.luau|applySkinnedSuppression|handle.chromeCornerRadius = nil",
			"screen_paint.luau|applySurface|handle.chromeCornerRadius = nil",
		})
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

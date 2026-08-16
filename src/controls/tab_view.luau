--!strict
-- TabView — the tab construct the placement policy has been waiting for
-- (navigation-and-menus brief §2 D5). `adaptive.navPlacement` shipped in
-- 2026-08-09 and the construct never did, so all five reference apps assemble
-- their bar by hand: four mutually-exclusive `When`-gated presentations, each
-- with its own label-degrade ladder, repeated per app. This is that, once.
--
-- ===== IT COMPOSES THE PICKER'S STRIP; IT DOES NOT REIMPLEMENT THE ROW =====
--
-- Director call (`artifacts/navigation-and-menus/additive-vs-net-new.md` §6):
-- *"its strip is precisely a segmented picker with an indicator"*, and
-- `api.md` already tells an author that a segmented picker used as a tab bar IS
-- a TabView. So the strip below IS `newPicker` — same option row, same icons,
-- same D4 sliding indicator, same 44px floor, same authoring lints — and
-- everything a strip needed that the picker did not have landed THERE as a
-- property (`sizing`, a reactive `axis`, `Option.badge`, a bound `Option.label`;
-- see that control's header). Three copies of a tab row is how a ruling about
-- one of them gets silently lost.
--
-- What makes this a CONSTRUCT rather than a fifth picker property is the three
-- things a picker never owns:
--
--   the CONTENT subtree and its lifecycle  — lazy, evicted, really disposed;
--   the PLACEMENT that restructures the screen — `adaptive.navPlacement`;
--   NESTING — two live TabViews arbitrating who owns the app-level placement.
--
-- ===== THE NESTING RULE, STATED ONCE ======================================
--
--     THE APP-LEVEL PLACEMENT BELONGS TO THE OUTERMOST TABVIEW. A TabView
--     BUILT INSIDE ANOTHER TABVIEW'S CONTENT IS INNER BY CONSTRUCTION, AND AN
--     INNER TABVIEW NEVER READS `adaptive.navPlacement`.
--
-- `r2` is exactly this: a top tab bar (For you / Charts) living inside a screen
-- that is itself a tab of the app-level bottom bar. If the inner one also asked
-- the policy, a phone would answer `bottomBar` for both and the page's own tabs
-- would be drawn in the thumb zone on top of the app's — two bars claiming one
-- home, and the inner one winning because it is painted later.
--
-- It is decidable WITHOUT asking the caller to declare it, because `content` is
-- a FACTORY this control invokes (which is also what laziness requires): a
-- TabView constructed during that invocation is inside one, and `BUILD_DEPTH`
-- is that fact. Two escapes stay open and both are explicit rather than
-- inferred: a DECLARED `placement` never consults the policy at all, and an
-- inner TabView built outside the factory (captured and passed in) is telling
-- the framework it is not inside anything, which is the caller's statement to
-- make. `dump().placementSource` reports which of the three answered, so a bug
-- report about a bar in the wrong home has a field to name.
--
-- THE OTHER TWO THINGS TWO LIVE TABVIEWS COULD FIGHT OVER ARE NOT FOUGHT OVER
-- BECAUSE NEITHER IS EVER CLAIMED. A TabView is a LAYOUT construct, not a
-- presentation: it pushes NO focus scope (no `transientScope`), traps nothing,
-- opens no presenter surface, and never touches `back()`. Its strip is ordinary
-- Buttons read in document order (the Tab-order rule, `97e9d93`) and its content
-- is a `When` branch. There is no scope to arbitrate and no stack to unbalance —
-- the two levels simply nest, the way two VStacks do. `selection` is the
-- caller's Signal, so the outer and the inner are two different Signals owned by
-- two different callers and neither construct can see the other's.
--
-- ===== LAZY CONTENT, EVICTED STATE (director ruling 2026-08-16, closed) ====
--
-- Only the selected tab's subtree exists. Switching DISPOSES the previous one:
-- scopes disposed, effects stopped, Instances released to the pool. That is the
-- memory-cheap choice and the right default for a UI competing with a live race
-- for frame budget.
--
-- IT IS THE FRAMEWORK'S OWN `When`, NOT A SECOND MECHANISM. `UI.When`'s
-- `thenView` already receives a BRANCH SCOPE that `mount.luau` disposes on
-- unmount (`mount.luau:232-234`), so `content = function(tabScope) … end` gets a
-- real disposal for free and the escape hatch is ownership rather than a flag:
--
--     state that must SURVIVE a switch is owned by the caller, OUTSIDE the
--     TabView — exactly as `selection` already is.
--
-- Own it on `tabScope` and it dies with the tab; own it on your screen's scope
-- and it outlives every switch. There is deliberately no `retain` flag: a flag
-- would be a second answer to a question ownership already answers, and the one
-- it gives is wrong half the time (retaining a tab a player visited once is the
-- leak the eviction default exists to avoid).
--
-- THE ACCEPTED COST, STATED SO NOBODY REPORTS IT AS A BUG: returning to a tab
-- REPLAYS ITS ENTRY COST. `r2`'s spinner comes back. A scroll position returns
-- to the top. An in-progress text entry is lost. All three are correct
-- behaviour under this ruling, and all three are fixed the same way — hold the
-- thing outside.
--
-- DO NOT EVICT THE STRIP. Only tab CONTENT is torn down. Every tab's label, icon
-- and badge stay live whether or not that tab is selected, because a badge on an
-- unselected tab is the whole point of a badge.
--
-- ===== OVERFLOW SCROLLS, THROUGH THE SHARED SUBSTRATE =====================
--
-- `f1`'s strip runs off the screen (`Avatars / Body / Clothing / Accessories /
-- Backg…`) and the selected tab has to be brought into view. Two facts decide
-- how:
--
--   * a `fill` strip CANNOT overflow — five tabs at 320px are 64px each — so the
--     scrolling homes ask the picker for `sizing = "hug"`, and only then is
--     there anything to scroll;
--   * `controller.scrollToVisible(path)` IS "make this rect visible in its
--     scroll ancestor" (`renderer.luau:3511`) — it finds the nearest ScrollView
--     ancestor, reads the live offset, and spends `solver.keepVisibleOffset`,
--     the ONE minimum-distance rule (A-SV2). A tab is MOUNTED (the strip is
--     never evicted), so it has a solved rect and this substrate applies
--     directly; re-deriving the arithmetic here would be a fifth copy of a
--     clamp that exists once on purpose.
--
-- `LuauUI.newAutoscroll` is NOT this and the brief named the wrong one: it is a
-- drag-to-edge POINTER PROXIMITY model (band/dwell/ramp/velocity, vertical bands
-- only) whose own header says non-pointer schemes have no autoscroll path
-- because focus-follows-navigation already scrolls the host.
--
-- A KEYBOARD OR GAMEPAD MOVE ONTO A TAB IS ALREADY REVEALED and this control
-- adds nothing for it: the presenter calls `scrollToVisible` on EVERY focus move
-- (`presenter.luau:2690`). What is genuinely uncovered is a selection change
-- that did NOT move focus — a tap, or a caller writing the Signal — so that is
-- the only case handled here.
--
-- ===== THE STRIP IS RE-HOMED, NOT REBUILT =================================
--
-- The four placements are three POSITIONS (a leading rail, a leading band, a
-- trailing band) around one content region, and declaration order is focus
-- order, so a bar that is painted after the content also reads after it — the
-- shipped rule the reference shells already carry ("the leading rail before the
-- content, the bottom bar after it", `p1_glade/init.luau:953`). One strip
-- blueprint is declared in each home under mutually-exclusive `When`s, so
-- exactly one is ever mounted and the picker OBJECT — its selection memos, its
-- indicator, its springs — is built once and survives every rotation. D5 found
-- the one thing that did not survive it (`selection_indicator` learned its
-- mounted paths exactly once) and fixed it there.

local adaptive = require("../layout/adaptive")
local contribution = require("../input/contribution")
local picker = require("./picker")
local specGuard = require("../spec_guard")

local tab_view = {}

-- `content` is a FACTORY, not a blueprint, and that is what makes the tab lazy:
-- it is not called until the tab is selected, and the scope it receives is
-- disposed when the tab is deselected.
export type Tab = {
	id: string,
	label: any?, -- string | Readable<string>; defaults to `id`
	icon: string?, -- SEMANTIC icon name, never an asset id
	badge: any?, -- string | number | Readable of either — the count seal
	content: (tabScope: any) -> any,
}

export type Spec = {
	id: string?,
	selection: any, -- owner-held Signal of a tab id (required)
	tabs: { Tab },
	-- "automatic" (default) | "bottomBar" | "bottomBarCompact" | "topBar" | "sidebar".
	-- "automatic" reads `adaptive.navPlacement` — unless this TabView is NESTED,
	-- which never claims the app-level answer (see the header).
	placement: string?,
	-- "automatic" (default, = "underline") | "underline" | "pill" | "none".
	-- Underline is what every tab strip in the reference media draws; `"pill"` is
	-- the segmented-control skin, and is what "a segmented control used as a tab
	-- bar" means in the docs.
	indicator: string?,
	-- "automatic" (default) | "fill" | "hug" — passed to the strip. Automatic
	-- fills the thumb-zone band (whose tabs divide it) and hugs everywhere else,
	-- which is what makes a top strip able to overflow and scroll.
	sizing: string?,
	iconOnly: boolean?, -- the strip's group icon decision (see newPicker)
	conditions: any?, -- the table `adaptive.conditions(core, env)` returns
	env: any?, -- an environment, when `conditions` was not built by the caller
	enabled: any?,
	onChange: ((id: any) -> ())?,
}

local PLACEMENTS: { [string]: boolean } = {
	automatic = true,
	bottomBar = true,
	bottomBarCompact = true,
	topBar = true,
	sidebar = true,
}
local INDICATORS: { [string]: boolean } = { automatic = true, none = true, underline = true, pill = true }
local SIZINGS: { [string]: boolean } = { automatic = true, fill = true, hug = true }

-- WHAT AN INNER TABVIEW RESOLVES TO. `r2` draws a top tab bar inside a screen
-- that is itself a tab, and a top bar is the one home that does not compete for
-- the thumb zone or the screen edge the app-level bar already owns.
local NESTED_PLACEMENT = "topBar"
-- ...and what `indicator = "automatic"` means. Every tab strip in the reference
-- media (r2's For you / Charts, f1's bottom strip) draws a bar, not a chip.
local AUTOMATIC_INDICATOR = "underline"

local FILL = table.freeze({ type = "fill", weight = 1 })
local NATURAL = table.freeze({ type = "content" })

-- CLOSED SPEC (constitution §4; ARCH-1). An unknown key is an authoring mistake,
-- never a silent no-op.
local TABVIEW_KEYS = specGuard.keySet({
	"conditions",
	"enabled",
	"env",
	"iconOnly",
	"id",
	"indicator",
	"onChange",
	"placement",
	"selection",
	"sizing",
	"tabs",
})

--[[ HOW DEEP INSIDE A TAB'S CONTENT WE CURRENTLY ARE.

	Module state, and the smallest honest shape for the question "is this
	TabView inside another one's content?". It is a synchronous BUILD STACK: the
	only writer is the content-factory wrapper below, which raises it, calls the
	caller's factory, and lowers it again under `pcall` so a factory that throws
	cannot leave the stack unbalanced. Nothing yields between those two lines.

	It deliberately does not know WHICH TabView is above it — an inner TabView
	needs to know only that it is not the app, and coupling the two would make
	the outer one addressable, which is how a construct grows an ambient
	registry nobody can dispose. ]]
local BUILD_DEPTH = 0

--[[ THE PLACEMENT DECISION, pure and exported so a caller can predict it and so
	the nesting rule is a test over strings rather than a claim about a mounted
	tree. Returns the placement and WHICH AUTHORITY answered:

	  declared  the caller named it; the policy is never consulted
	  nested    this TabView is inside another's content; the app-level answer is
	            not its to claim, so it takes the top bar (r2)
	  policy    `adaptive.navPlacement`, the app-level home ]]
function tab_view.resolvePlacement(requested: string, nested: boolean, policy: string?): (string, string)
	if requested ~= "automatic" then
		return requested, "declared"
	end
	if nested then
		return NESTED_PLACEMENT, "nested"
	end
	return policy or "bottomBar", "policy"
end

--[[ WHAT THE STRIP DOES WITH ITS OFFER, per placement. The thumb-zone band is
	the one home whose tabs DIVIDE the width — a full-width bar of equal targets
	is what a phone's bottom bar is — and every other home hugs, which is what
	lets a strip be wider than its offer and therefore scroll at all. Pure for
	the same reason as above. ]]
function tab_view.resolveSizing(requested: string, placement: string): string
	if requested ~= "automatic" then
		return requested
	end
	return if placement == "bottomBar" then "fill" else "hug"
end

function tab_view.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newTabView", spec, TABVIEW_KEYS, "spec")
	local UI = LuauUI.UI
	local id = spec.id or "TabView"
	local scope = core:scope("tab-view-" .. tostring(id))
	-- READ THE DEPTH BEFORE ANYTHING ELSE CAN CHANGE IT. This is the whole
	-- nesting decision, and it is a fact about WHERE THIS CALL IS, so it is taken
	-- at the top of the call and never re-read.
	local nested = BUILD_DEPTH > 0

	local selection = spec.selection
	if type(selection) ~= "table" or (selection :: any).kind ~= "signal" then
		error(
			`LuauUI newTabView('{id}'): \`selection\` must be a SETTABLE Signal the caller owns. It is the `
				.. "escape hatch as well as the state: everything that must survive a tab switch lives in a "
				.. "caller-owned Signal outside this control, and this is the first one.",
			0
		)
	end
	if type(spec.tabs) ~= "table" or #spec.tabs == 0 then
		error(`LuauUI newTabView('{id}'): \`tabs\` must be a non-empty array of ` .. "{ id, label?, content }", 0)
	end
	local seen: { [string]: boolean } = {}
	for index, tab in spec.tabs do
		if type(tab) ~= "table" then
			error(`LuauUI newTabView('{id}'): tab {index} must be a table of id / label? / icon? / badge? / content`, 0)
		end
		if type(tab.id) ~= "string" or tab.id == "" then
			error(
				`LuauUI newTabView('{id}'): tab {index} needs a non-empty string \`id\` — it is the SELECTION `
					.. "VALUE the caller's Signal holds, and it is what `dump()` reports.",
				0
			)
		end
		if seen[tab.id] then
			error(
				`LuauUI newTabView('{id}'): two tabs share the id '{tab.id}'. A tab id is the selection value, so `
					.. "a duplicate makes the selection ambiguous rather than merely confusing.",
				0
			)
		end
		seen[tab.id] = true
		if type(tab.content) ~= "function" then
			error(
				`LuauUI newTabView('{id}'): tab '{tab.id}' needs \`content\` as a FUNCTION (tabScope) -> Blueprint, `
					.. "not a blueprint. It is a factory because the tab is LAZY: it is not called until the tab "
					.. "is selected, and `tabScope` is disposed when the tab is deselected. State that must "
					.. "survive a switch belongs to a Signal the CALLER owns, outside this control.",
				0
			)
		end
	end

	local requestedPlacement = spec.placement or "automatic"
	if not PLACEMENTS[requestedPlacement] then
		error(
			`LuauUI newTabView('{id}'): unknown placement '{tostring(requestedPlacement)}'. One of automatic | `
				.. "bottomBar | bottomBarCompact | topBar | sidebar — the vocabulary `adaptive.navPlacement` "
				.. "already speaks. A device name is not one of them.",
			0
		)
	end
	local requestedIndicator = spec.indicator or "automatic"
	if not INDICATORS[requestedIndicator] then
		error(
			`LuauUI newTabView('{id}'): unknown indicator '{tostring(requestedIndicator)}'. `
				.. "One of automatic | none | underline | pill.",
			0
		)
	end
	local requestedSizing = spec.sizing or "automatic"
	if not SIZINGS[requestedSizing] then
		error(
			`LuauUI newTabView('{id}'): unknown sizing '{tostring(requestedSizing)}'. One of automatic | fill | hug.`,
			0
		)
	end

	-- ===== the placement =====================================================
	-- The policy Readable, and the ONE place it is asked for. A nested TabView
	-- never reaches it, so a page's own tabs cannot claim the app's home.
	local policySource: any = nil
	if requestedPlacement == "automatic" and not nested then
		if spec.conditions ~= nil then
			policySource = spec.conditions.navPlacement
		elseif spec.env ~= nil then
			-- built here and OWNED here: `adaptive.conditions` creates thirteen
			-- memos and a caller that rebuilds per mount without owning them leaks
			-- thirteen per cycle (that function's own RR-8 note)
			policySource = adaptive.conditions(core, spec.env, { scope = scope }).navPlacement
		else
			error(
				`LuauUI newTabView('{id}'): an automatic placement reads \`adaptive.navPlacement\`, so it needs `
					.. "either `conditions` (the table `LuauUI.adaptive.conditions(core, env)` returns — pass "
					.. "yours so its thirteen memos are not built twice) or `env`. Or declare `placement` and "
					.. "the policy is never consulted.",
				0
			)
		end
	end

	local placementSource = select(2, tab_view.resolvePlacement(requestedPlacement, nested, nil))
	local placement = scope:own(core:memo(function(use)
		local policy = if policySource ~= nil then use(policySource) else nil
		return (tab_view.resolvePlacement(requestedPlacement, nested, policy))
	end))
	local function isPlacement(name: string): any
		return scope:own(core:memo(function(use)
			return use(placement) == name
		end))
	end
	local sizing = scope:own(core:memo(function(use)
		return tab_view.resolveSizing(requestedSizing, use(placement))
	end))
	-- the SIDEBAR is the one home that runs down the screen; every other home is
	-- a band across it. The strip's axis and the root's axis are the same fact
	-- read twice, and both are bound, so a rotation is a re-solve.
	local sidebar = isPlacement("sidebar")
	local stripAxis = scope:own(core:memo(function(use)
		return if use(sidebar) then "y" else "x"
	end))
	local rootAxis = scope:own(core:memo(function(use)
		return if use(sidebar) then "x" else "y"
	end))

	-- ===== the strip: a segmented picker, nothing more ========================
	local options: { any } = {}
	for _, tab in spec.tabs do
		table.insert(options, {
			value = tab.id,
			-- the id IS a name when no label was given: `newPicker` requires a
			-- non-empty label because it is the semantic name every non-visual
			-- consumer reads, and an icon-only tab still has to carry one
			label = tab.label or tab.id,
			icon = tab.icon,
			badge = tab.badge,
		})
	end
	local strip = picker.build(LuauUI, core, {
		id = "Strip",
		options = options,
		selected = selection,
		presentation = "segmented",
		indicator = if requestedIndicator == "automatic" then AUTOMATIC_INDICATOR else requestedIndicator,
		axis = stripAxis,
		sizing = sizing,
		iconOnly = spec.iconOnly,
		env = spec.env,
		enabled = spec.enabled,
		onChange = spec.onChange,
	})
	scope:own(strip)

	-- ===== the content: one branch per tab, only one mounted =================
	local mounted: { [string]: boolean } = {}
	local mountCount = 0
	local evictions = 0
	local contentChildren: { any } = {}
	for _, tab in spec.tabs do
		local tabId = tab.id
		local selectedHere = scope:own(core:memo(function(use)
			return use(selection) == tabId
		end))
		table.insert(
			contentChildren,
			UI.When({
				id = "Tab-" .. tabId,
				condition = selectedHere,
				thenView = function(branchScope: any)
					-- THE BUILD STACK, raised for exactly the duration of the
					-- caller's factory. `pcall` so a factory that throws still
					-- lowers it: an unbalanced depth would make every later
					-- TabView on the session think it was nested.
					BUILD_DEPTH += 1
					local ok, built = pcall(tab.content, branchScope)
					BUILD_DEPTH -= 1
					if not ok then
						error(built, 0)
					end
					mounted[tabId] = true
					mountCount += 1
					-- THE EVICTION, and it is the framework's own disposal rather
					-- than a second mechanism: `mount.luau` disposes this branch
					-- scope when the condition goes false, so anything the caller
					-- owned on it dies with the tab and this bookkeeping rides
					-- along on the same event.
					branchScope:own({
						dispose = function()
							mounted[tabId] = nil
							evictions += 1
						end,
					})
					return built
				end,
			})
		)
	end
	--[[ A STACK THAT STRETCHES, NOT A ZSTACK. Exactly one branch is ever mounted,
		so either container holds it — but a ZStack gives a child its NATURAL size,
		and a page is not a natural-size thing: the first reference app migrated
		onto this control reported "this child overflows its zstack by 512x0px" at
		every one of the five matrix viewports, because its body measured wider than
		a 360px phone and nothing stretched it back down. `align = "stretch"` is
		what the hand-built content hosts all declared, and it is the statement the
		content region is actually making: the selected tab IS the page. ]]
	local content = UI.VStack({
		id = "Content",
		align = "stretch",
		width = FILL,
		height = FILL,
		children = contentChildren,
	})

	-- ===== the three homes ===================================================
	-- One strip blueprint, declared in each home under mutually-exclusive
	-- conditions, so exactly one is mounted and the picker object is built once.
	-- NO PADDING AND NO GAP ANYWHERE IN HERE, for the reason `check_theme_drift`
	-- gives about a zero: "this container adds no spacing of its own" is a
	-- STRUCTURAL statement, not a style value. A landscape phone offers ~320px of
	-- height and the first app migrated onto this control lost 8 of them to a band
	-- inset it never asked for; a host that wants breathing room around its bar
	-- can pad the node it puts this in.
	-- The scrolling homes are ScrollViews because a hugging strip can be wider
	-- than its offer; the thumb-zone band is not, because a `fill` strip divides
	-- the offer and has nothing to overflow with.
	local rail = UI.When({
		id = "RailHome",
		condition = sidebar,
		thenView = function()
			return UI.ScrollView({
				id = "Rail",
				axis = "y",
				width = NATURAL,
				height = FILL,
				indicators = "none",
				children = { strip.blueprint },
			})
		end,
	})
	local topBand = UI.When({
		id = "TopHome",
		condition = isPlacement("topBar"),
		thenView = function()
			return UI.ScrollView({
				id = "TopBand",
				axis = "x",
				width = FILL,
				indicators = "none",
				children = { strip.blueprint },
			})
		end,
	})
	local bottomBand = UI.When({
		id = "BottomHome",
		condition = isPlacement("bottomBar"),
		thenView = function()
			-- NOT a scroller: `fill` segments divide the band, so this strip is
			-- exactly as wide as its offer and a scroll host would have nothing to
			-- scroll. Declaring one anyway would put a `fill` child on a scroll
			-- axis, which measures against a canvas derived from that child.
			return UI.VStack({ id = "BottomBand", width = FILL, children = { strip.blueprint } })
		end,
	})
	local compactBand = UI.When({
		id = "CompactHome",
		condition = isPlacement("bottomBarCompact"),
		thenView = function()
			return UI.ScrollView({
				id = "CompactBand",
				axis = "x",
				width = FILL,
				indicators = "none",
				children = { strip.blueprint },
			})
		end,
	})

	-- DECLARATION ORDER IS FOCUS ORDER, and the strip reads where it is PAINTED:
	-- the leading rail and the top band before the content, the bottom bands
	-- after it (`p1_glade/init.luau:953`, the shipped rule).
	local root = UI.AdaptiveStack({
		id = id,
		axis = rootAxis,
		width = FILL,
		height = FILL,
		children = { rail, topBand, content, bottomBand, compactBand },
	})

	-- ===== reachability and keep-visible ====================================
	local boundController: any = nil
	local tabPaths: { [string]: string } = {}
	local mountedRootPath: string? = nil
	local revealed: any = nil
	local reveals = 0

	local function indexOf(value: any): number?
		for i, tab in spec.tabs do
			if tab.id == value then
				return i
			end
		end
		return nil
	end

	local function relearn(rootNode: any)
		-- resolve by IDENTITY, walking the mounted tree, never by string
		-- arithmetic: the strip's mounted path depends on which HOME is live, so
		-- guessing it is the assumption that breaks on the first rotation
		local wanted: { [string]: string } = {}
		for i, segment in strip.segments do
			wanted[segment.id] = spec.tabs[i].id
		end
		tabPaths = {}
		local function walk(node: any)
			local tabId = wanted[node.id]
			if tabId ~= nil and tabPaths[tabId] == nil then
				tabPaths[tabId] = node.path
			end
			for _, child in node.children or {} do
				walk(child)
			end
		end
		walk(rootNode)
	end

	local built = contribution.attach(root, {
		-- the renderer's controller, for the ONE programmatic scroll this control
		-- issues. Absent is a supported degradation: a standalone strip with no
		-- engine to scroll simply does not scroll.
		bindController = function(controller: any)
			boundController = controller
		end,
		--[[ SOLVED GEOMETRY, ON THE ARRANGE CADENCE. Idempotent and
			equality-guarded, as every syncGeometry in the framework must be: the
			relearn runs only when the MOUNT changed, and the reveal only when the
			SELECTION changed since the last one. Without the second guard this
			would ask the engine to scroll on every solve forever.

			The reveal lives here rather than in an observer on `selection` because
			`scrollToVisible` reads the LAST SOLVED rects, and this is the callback
			that runs immediately after a solve. ]]
		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and rootNode.path ~= mountedRootPath then
				mountedRootPath = rootNode.path
				relearn(rootNode)
			end
			local current = selection:get()
			if current == revealed then
				return
			end
			revealed = current
			local path = tabPaths[current]
			if path == nil or boundController == nil or boundController.scrollToVisible == nil then
				return
			end
			-- THE SHARED KEEP-VISIBLE SUBSTRATE (A-SV1/A-SV2), not a fifth copy of
			-- the clamp: it finds the nearest ScrollView ancestor, reads the live
			-- offset, and moves the minimum distance — returning false when the tab
			-- is already visible or the home is not a scroller at all.
			if boundController.scrollToVisible(path) then
				reveals += 1
			end
		end,
		--[[ THE STRIP'S OWN TABS, and only those. `adjustTargets` binds the Adjust
			keys — arrows, comma/period, DPad left/right and the gamepad SHOULDERS
			(L1/R1) — DYNAMICALLY, only while the focused path is one of these, so
			a screen carrying a TabView never shadows gameplay bumpers while focus
			sits elsewhere (the ADR-0013 hazard the dynamic binding exists for).

			IT DELIBERATELY DOES NOT CLAIM THE CONTENT'S FOCUSABLES. Paging from
			anywhere inside the page would read well, but a tab's content contains
			Sliders and Tables that declare their OWN adjust targets, and claiming
			a path another control owns is a contention this construct has no
			business creating. ]]
		adjustTargets = function(rootNode: any?)
			if rootNode ~= nil and rootNode.path ~= mountedRootPath then
				mountedRootPath = rootNode.path
				relearn(rootNode)
			end
			local targets: { [string]: boolean } = {}
			for _, path in tabPaths do
				targets[path] = true
			end
			return targets
		end,
		-- PAGE BY ONE, and never wrap: a bumper at the last tab does nothing
		-- rather than jumping to the first, which is the same clamp every
		-- directional move in the framework makes.
		handleAdjust = function(path: string, direction: number): boolean
			local hit: string? = nil
			for tabId, tabPath in tabPaths do
				if tabPath == path then
					hit = tabId
				end
			end
			if hit == nil then
				return false
			end
			local index = indexOf(selection:get()) or indexOf(hit)
			if index == nil then
				return false
			end
			local next = math.clamp(index + (if direction < 0 then -1 else 1), 1, #spec.tabs)
			if next == index then
				return true -- consumed: the clamp is the answer, not a fall-through
			end
			selection:set(spec.tabs[next].id)
			if spec.onChange ~= nil then
				spec.onChange(spec.tabs[next].id)
			end
			return true
		end,
	})

	local api = {}
	api.blueprint = built
	-- the placement this TabView resolved, published so a screen that has its own
	-- chrome to place (a search field that rides the bar, a wordmark that only
	-- belongs in the rail) reads ONE answer rather than re-deriving the policy
	api.placement = placement

	function api.dump()
		local current = selection:get()
		local label: string? = nil
		local index = indexOf(current)
		for _, tab in spec.tabs do
			if tab.id == current then
				local raw = tab.label or tab.id
				label = if type(raw) == "table" then tostring((raw :: any):get()) else tostring(raw)
			end
		end
		local live: { string } = {}
		for _, tab in spec.tabs do
			if mounted[tab.id] then
				table.insert(live, tab.id)
			end
		end
		return {
			schema = "luauui-tab_view-dump/1",
			id = id,
			tabCount = #spec.tabs,
			selectedId = current,
			selectedLabel = label,
			selectedIndex = index,
			-- WHAT WAS ASKED FOR beside WHAT ANSWERED, the pairing every adaptive
			-- control here already reports. `placementSource` is the nesting rule
			-- made observable: "nested" means this TabView did not claim the
			-- app-level home, which is the first thing a report of two bars wants.
			requestedPlacement = requestedPlacement,
			placement = placement:get(),
			placementSource = placementSource,
			nested = nested,
			sizing = sizing:get(),
			axis = stripAxis:get(),
			-- the strip is a picker, so its whole state is already reported by a
			-- dump that exists; nesting it keeps ONE description of a segment row
			strip = strip.dump(),
			--[[ THE LAZINESS AND THE EVICTION, as counts rather than as a claim.
				`mountedTabs` is what EXISTS right now (one, always, unless nothing
				is selected); `contentMounts` and `contentEvictions` are how many
				subtrees have been built and torn down. A tab that leaked would
				show mounts climbing while evictions stayed put. ]]
			mountedTabs = live,
			contentMounts = mountCount,
			contentEvictions = evictions,
			-- how many times a selection change actually MOVED the strip's
			-- scroller. Zero on a `fill` band is correct, not a failure.
			reveals = reveals,
			semanticText = `Tabs: {label or "none"} ({index or 0} of {#spec.tabs}) in the {placement:get()}`,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return tab_view

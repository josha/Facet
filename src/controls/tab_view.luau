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
-- `Facet.newAutoscroll` is NOT this and the brief named the wrong one: it is a
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
--
-- ===== THE CHROME BESIDE THE TABS (framework-gaps-phase2 §6) ===============
--
-- A nav bar is rarely only tabs. `p1_glade` puts a WORDMARK at the rail's head;
-- `p3_sipworks` puts a SEARCH FIELD on the top band's trailing edge and directly
-- above the thumb-zone dock. Neither was expressible, so both kept a hand-built
-- four-`When` shell and the examples directory taught the same thing two
-- contradictory ways — which is the gap this closes.
--
--     `accessories = { head?, foot?, trailing?, aboveBar? }`, each a
--     `(placement, scope) -> Blueprint?` FACTORY, invoked only by the homes that
--     host that slot. The placement this control already resolved is what decides
--     which slots mount, so no app re-derives the policy.
--
-- WHY A SLOT IS NOT HOSTED EVERYWHERE, and why that is a refusal rather than a
-- shrug. The four homes are not four boxes with the same edges:
--
--   sidebar   a RAIL down the screen: it has a head and a foot, and its foot is
--             the BOTTOM OF THE RAIL (the strip's scroller spends the slack), not
--             "under the last tab".
--   topBar    a CENTRED band (ADR-0040 B-12, the contract this file already
--             carries). Its strip HUGS, so chrome at the trailing edge RESERVES
--             its own width and the strip centres in what is left: an overlay
--             keeps the cluster centred on the whole band and sits ON the last tab
--             the moment the strip overflows, where scrolling can never uncover it.
--   bottomBar / bottomBarCompact
--             the THUMB ZONE. Nothing may sit at a band's trailing edge there: a
--             `fill` band divides its width among equal targets and an overlay
--             would cover one. What a dock has room for is a strip ABOVE it, which
--             is the shape the reference shells already call an accessory.
--
-- So `head`/`foot` are the rail's; `trailing` is the top band's; `aboveBar` is the
-- dock's. `accessoryPlacements(slot)` is that rule, pure and exported, and a slot
-- no REACHABLE placement can host refuses at construction — reachable being the
-- one placement a DECLARED `placement` (or nesting, which always resolves
-- `topBar`) can ever produce. Under `automatic` every home is still reachable, so
-- nothing is refused and a factory declines a shape by returning nothing.
--
-- DECLARING NOTHING MOUNTS NOTHING, structurally: the wrappers below appear only
-- when a factory really returned a blueprint, so every path that shipped before
-- this — the four `p4_foyer` pins among them — is byte-identical.
--
-- WHAT AN ACCESSORY IS NOT. It is CHROME, not a tab whose home moves. `p3`'s
-- Steam Stamps pocket looks like a `foot` case and is not one: it is a nav
-- DESTINATION pinned to the rail's foot, and moving a segment out of the strip is
-- a strip concern (one picker object serves every home by contract). That case is
-- recorded in ADR-0045 rather than half-served here.

local adaptive = require("../layout/adaptive")
local contribution = require("../input/contribution")
local picker = require("./picker")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")

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

-- THE CHROME BESIDE THE TABS. Each slot is a FACTORY rather than a blueprint for
-- the same two reasons `content` is: it is not built until the home that hosts it
-- is mounted, and the `scope` it receives is disposed when that home goes away. It
-- is told the placement so ONE function can serve several homes, and it may
-- return nothing to decline one of them.
export type Accessories = {
	head: ((placement: string, scope: any) -> any)?,
	foot: ((placement: string, scope: any) -> any)?,
	trailing: ((placement: string, scope: any) -> any)?,
	aboveBar: ((placement: string, scope: any) -> any)?,
}

export type Spec = {
	id: string?,
	selection: any, -- owner-held Signal of a tab id (required)
	tabs: { Tab },
	-- chrome beside the tabs, homed by the placement (see the header). A slot no
	-- reachable placement can host is an authoring mistake and refuses.
	accessories: Accessories?,
	-- the SIDEBAR RAIL's width dim; content-sized by default. A rail states its
	-- band and lets the labels adapt inside it — a 1.4x locale at the largest text
	-- preference otherwise makes the longest tab name the whole rail. Hosted by
	-- `sidebar` alone, and refused for a placement that can never have one.
	railWidth: any?,
	-- the ENTER transition each content branch carries — the framework's own
	-- `UI.When` transition table, passed through. The strip is never evicted, so
	-- it is never animated by this.
	transition: any?,
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
	-- the TYPE ROLE every tab wears, passed straight to the strip (see newPicker).
	-- Reactive, so a caller can bind it against `api.placement`: a thumb-zone tab
	-- bar is caption-sized in tighter chrome and a rail is not, and WHICH home
	-- takes which role is a design language rather than a layout rule — so the
	-- construct carries the binding and never picks the ramp.
	textSize: any?,
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

--[[ WHICH HOME HOSTS WHICH SLOT — the whole accessory rule, as data, so the
	refusal message and the mount obey ONE statement of it. Reasons in the header;
	the short form is that a rail has ends, a centred band has an overlay edge, and
	a thumb-zone dock has a strip above it. ]]
local ACCESSORY_HOMES: { [string]: { string } } = {
	aboveBar = { "bottomBar", "bottomBarCompact" },
	foot = { "sidebar" },
	head = { "sidebar" },
	trailing = { "topBar" },
}
-- sorted, because it is what every refusal message and the dump report
local ACCESSORY_SLOTS = table.freeze({ "aboveBar", "foot", "head", "trailing" })
-- the framework node each slot's blueprint lands in. It exists so the mounted
-- PATH is the framework's to promise: an app's own id is not something a spec —
-- or a bug report — can predict.
local SLOT_ID: { [string]: string } = {
	aboveBar = "AboveBarSlot",
	foot = "FootSlot",
	head = "HeadSlot",
	trailing = "TrailingSlot",
}

-- WHAT AN INNER TABVIEW RESOLVES TO. `r2` draws a top tab bar inside a screen
-- that is itself a tab, and a top bar is the one home that does not compete for
-- the thumb zone or the screen edge the app-level bar already owns.
local NESTED_PLACEMENT = "topBar"
-- ...and what `indicator = "automatic"` means. Every tab strip in the reference
-- media (r2's For you / Charts, f1's bottom strip) draws a bar, not a chip.
local AUTOMATIC_INDICATOR = "underline"

local FILL = table.freeze({ type = "fill", weight = 1 })
local NATURAL = table.freeze({ type = "content" })
--[[ THE CENTRED BAND'S TWO BOXES. `hug` is the word that makes one
	declaration serve both halves of the promise: it is the content's own width
	CAPPED AT THE OFFER, so a three-tab strip is 193px (and its ZStack parent
	centres it) while an eight-tab strip caps at the band and scrolls. `content`
	would have overflowed the ZStack — measured, with the framework's own
	"overflows its zstack" diagnostic naming it — and `fill` inside a scroller on
	its own axis takes the CONTENT width, so it centres nothing. ]]
local BAND_CAPPED = table.freeze({ type = "hug" })

-- CLOSED SPEC (constitution §4). An unknown key is an authoring mistake,
-- never a silent no-op.
local TABVIEW_KEYS = specGuard.keySet({
	"accessories",
	"conditions",
	"enabled",
	"env",
	"iconOnly",
	"id",
	"indicator",
	"onChange",
	"placement",
	"railWidth",
	"selection",
	"sizing",
	"tabs",
	"textSize",
	"transition",
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

--[[ THE PLACEMENTS THAT HOST AN ACCESSORY SLOT, or nil for a name that is not a
	slot at all. Pure and exported for the same reason `resolvePlacement` is: the
	matrix is then a test over strings, and the refusal below quotes the very list
	the mount obeys rather than a second copy of it. A COPY is returned, because a
	caller that edited the framework's own rule would move every later answer. ]]
function tab_view.accessoryPlacements(slot: string): { string }?
	local homes = ACCESSORY_HOMES[slot]
	return if homes == nil then nil else table.clone(homes)
end

function tab_view.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newTabView", spec, TABVIEW_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "TabView"
	local scope = core:scope("tab-view-" .. tostring(id))
	-- READ THE DEPTH BEFORE ANYTHING ELSE CAN CHANGE IT. This is the whole
	-- nesting decision, and it is a fact about WHERE THIS CALL IS, so it is taken
	-- at the top of the call and never re-read.
	local nested = BUILD_DEPTH > 0

	local selection = spec.selection
	if type(selection) ~= "table" or (selection :: any).kind ~= "signal" then
		error(
			`Facet newTabView('{id}'): \`selection\` must be a SETTABLE Signal the caller owns. It is the `
				.. "escape hatch as well as the state: everything that must survive a tab switch lives in a "
				.. "caller-owned Signal outside this control, and this is the first one.",
			0
		)
	end
	if type(spec.tabs) ~= "table" or #spec.tabs == 0 then
		error(`Facet newTabView('{id}'): \`tabs\` must be a non-empty array of ` .. "{ id, label?, content }", 0)
	end
	local seen: { [string]: boolean } = {}
	for index, tab in spec.tabs do
		if type(tab) ~= "table" then
			error(`Facet newTabView('{id}'): tab {index} must be a table of id / label? / icon? / badge? / content`, 0)
		end
		if type(tab.id) ~= "string" or tab.id == "" then
			error(
				`Facet newTabView('{id}'): tab {index} needs a non-empty string \`id\` — it is the SELECTION `
					.. "VALUE the caller's Signal holds, and it is what `dump()` reports.",
				0
			)
		end
		if seen[tab.id] then
			error(
				`Facet newTabView('{id}'): two tabs share the id '{tab.id}'. A tab id is the selection value, so `
					.. "a duplicate makes the selection ambiguous rather than merely confusing.",
				0
			)
		end
		seen[tab.id] = true
		if type(tab.content) ~= "function" then
			error(
				`Facet newTabView('{id}'): tab '{tab.id}' needs \`content\` as a FUNCTION (tabScope) -> Blueprint, `
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
			`Facet newTabView('{id}'): unknown placement '{tostring(requestedPlacement)}'. One of automatic | `
				.. "bottomBar | bottomBarCompact | topBar | sidebar — the vocabulary `adaptive.navPlacement` "
				.. "already speaks. A device name is not one of them.",
			0
		)
	end
	local requestedIndicator = spec.indicator or "automatic"
	if not INDICATORS[requestedIndicator] then
		error(
			`Facet newTabView('{id}'): unknown indicator '{tostring(requestedIndicator)}'. `
				.. "One of automatic | none | underline | pill.",
			0
		)
	end
	local requestedSizing = spec.sizing or "automatic"
	if not SIZINGS[requestedSizing] then
		error(
			`Facet newTabView('{id}'): unknown sizing '{tostring(requestedSizing)}'. One of automatic | fill | hug.`,
			0
		)
	end

	-- ===== the accessories ====================================================
	--[[ THE ONE MOMENT A SLOT MISTAKE IS PROVABLE. A DECLARED placement — or
		nesting, which always resolves `topBar` — narrows the reachable homes to
		exactly one, so chrome declared for a home that can never exist is a bug
		whose only symptom is silence. Under `automatic` every home is still
		reachable and nothing is refused; a factory declines a shape by returning
		nothing. ]]
	local reachable: { [string]: boolean } = {}
	if requestedPlacement ~= "automatic" then
		reachable[requestedPlacement] = true
	elseif nested then
		reachable[NESTED_PLACEMENT] = true
	else
		for name in PLACEMENTS do
			if name ~= "automatic" then
				reachable[name] = true
			end
		end
	end
	local function whyUnreachable(): string
		return if nested
			then "this TabView is NESTED, so its placement is always '" .. NESTED_PLACEMENT .. "'"
			else "this TabView DECLARED placement '" .. requestedPlacement .. "'"
	end
	-- the rail's band rides the SAME reachability rule the slots do: a width for a
	-- rail that can never exist is the same silent authoring mistake
	if spec.railWidth ~= nil and not reachable.sidebar then
		error(
			`Facet newTabView('{id}'): \`railWidth\` is the SIDEBAR rail's band, and {whyUnreachable()}. `
				.. "Leave the placement `automatic` and it applies wherever the rail is, or drop it.",
			0
		)
	end

	local accessories: any = spec.accessories
	local declaredSlots: { string } = {}
	if accessories ~= nil then
		if type(accessories) ~= "table" then
			error(
				`Facet newTabView('{id}'): \`accessories\` must be a TABLE of slots — `
					.. "{ head?, foot?, trailing?, aboveBar? }, each a (placement, scope) -> Blueprint? factory.",
				0
			)
		end
		--[[ SORTED, not the caller's hash order: an author with two bad slots got a
			different one named per run, so fixing the one they were shown could
			surface the other — or the same again. A refusal a reader cannot
			reproduce is one they cannot act on. ]]
		local declaredNames: { string } = {}
		for slot in accessories do
			table.insert(declaredNames, tostring(slot))
		end
		table.sort(declaredNames)
		for _, slot in declaredNames do
			local factory = accessories[slot]
			local homes = ACCESSORY_HOMES[slot]
			if homes == nil then
				error(
					`Facet newTabView('{id}'): unknown accessory slot '{tostring(slot)}'. One of `
						.. table.concat(ACCESSORY_SLOTS, " | ")
						.. " — the head and foot of the RAIL, the trailing edge of the TOP band, and the strip "
						.. "ABOVE a thumb-zone dock. A band has no other edge to spare (see this control's header).",
					0
				)
			end
			if type(factory) ~= "function" then
				error(
					`Facet newTabView('{id}'): accessory '{slot}' must be a FUNCTION (placement, scope) -> Blueprint?, `
						.. "not a blueprint. The placement is its argument — one factory can serve several homes — "
						.. "and the scope it receives is disposed when that home goes away.",
					0
				)
			end
			local hosted = false
			for _, home in homes do
				if reachable[home] then
					hosted = true
				end
			end
			if not hosted then
				error(
					`Facet newTabView('{id}'): accessory '{slot}' can never mount — {whyUnreachable()}, and '{slot}' is hosted `
						.. "only by "
						.. table.concat(homes, " / ")
						.. ". Leave the placement `automatic` and the slot mounts wherever it is hosted, or drop "
						.. "the slot: silently ignoring it is how a wordmark never appears and nobody can say why.",
					0
				)
			end
			table.insert(declaredSlots, slot)
		end
	end

	--[[ THE CONTENT REGION'S ENTER TRANSITION (§6). Both reference shells this
		control replaced declared one on their own section hosts, and there was
		nowhere to say it — so adopting the construct swapped a fade for a hard cut
		in two shipped proofs. It is `UI.When`'s own table, validated here only for
		SHAPE: the grammar itself is the blueprint layer's to police, once. ]]
	if spec.transition ~= nil and type(spec.transition) ~= "table" then
		error(
			`Facet newTabView('{id}'): \`transition\` must be a TABLE — the same `
				.. "{ enter?, exit?, class? } `UI.When` takes, not the name of one.",
			0
		)
	end

	-- ===== the placement =====================================================
	-- The policy Readable, and the ONE place it is asked for. A nested TabView
	-- never reaches it, so a page's own tabs cannot claim the app's home.
	local policySource: any = nil
	if requestedPlacement == "automatic" and not nested then
		--[[ THE THIRD ROUTE (2026-08-18): the surface's own environment.
			This control has always REFUSED rather than guessed, which is the pattern
			the rest of the framework has now adopted — but a refusal is only the
			right answer when nothing can answer, and the core a TabView is built on
			publishes its environment (`src/env/surface_env.luau`). So an automatic
			placement now costs the author nothing on a real surface, and the refusal
			below still fires for the case it was written for: a control with no
			environment anywhere. ]]
		local publishedEnv = if spec.env ~= nil then spec.env else (surfaceEnv.find(core))
		if spec.conditions ~= nil then
			policySource = spec.conditions.navPlacement
		elseif publishedEnv ~= nil then
			-- built here and OWNED here: `adaptive.conditions` creates its own set
			-- of memos and a caller that rebuilds per mount without owning them
			-- leaks all of them per cycle (that function's own leak note says so)
			policySource = adaptive.conditions(core, publishedEnv, { scope = scope }).navPlacement
		else
			error(
				`Facet newTabView('{id}'): an automatic placement reads \`adaptive.navPlacement\`, so it needs `
					.. "an environment. A surface stood up with `Facet.client.host.new` publishes one on the "
					.. "core it builds and this control finds it with no wiring; otherwise pass `conditions` "
					.. "(the table `Facet.adaptive.conditions(core, env)` returns — pass yours so its memos "
					.. "are not built twice) or `env`. Or declare `placement` and the policy is never "
					.. "consulted.",
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
	local strip = picker.build(Facet, core, {
		id = "Strip",
		options = options,
		selected = selection,
		presentation = "segmented",
		indicator = if requestedIndicator == "automatic" then AUTOMATIC_INDICATOR else requestedIndicator,
		axis = stripAxis,
		sizing = sizing,
		iconOnly = spec.iconOnly,
		textSize = spec.textSize,
		env = spec.env,
		enabled = spec.enabled,
		onChange = spec.onChange,
	})
	scope:own(strip)

	--[[ THE CONTENT TRANSITION'S EXIT IS ALWAYS `instant` (task-fix3 symptoms 4/5;
		director device round, 2026-08-23; "mid-screen then pops to the top" /
		"layout appears then pops"). `Content` below is a STRETCH VSTACK, not a ZStack (see its own
		header comment) — every branch's page declares `width/height = fill`
		against it. `mount.luau`'s ordinary retire model (a departing branch
		STAYS MOUNTED, non-interactive, until its exit transition settles — right
		for a list row, which is a peer sharing space with its siblings) is wrong
		here: while the OUTGOING tab's branch is retiring, it and the INCOMING
		tab's branch are BOTH mounted as fill-height siblings of the same stack for
		that window, so the stack divides the offer between them instead of
		handing the offer to either — measured: a 798px pane became two 399px
		panes, the incoming one pinned to the BOTTOM half, until the outgoing one
		finished retiring and the stack re-solved to give the survivor the whole
		798. A tab's own page is not a list row sharing a shelf with its
		neighbour; it is the WHOLE surface, mutually exclusive with every other
		tab's page, so nothing is lost by removing the outgoing one on the spot —
		`exit = "instant"` skips the retire entirely (transitions.luau's
		`shouldRetire` returns nil for it), which is what keeps exactly one branch
		mounted, exactly the invariant this construct's own comment below already
		claims. The caller's `enter` (and `class`/`fade`) still plays for the
		branch arriving. ]]
	local function contentTransition(declared: any): any
		if declared == nil then
			return nil
		end
		return {
			enter = declared.enter,
			exit = "instant",
			class = declared.class,
			fade = declared.fade,
			-- task CONN, review-fix234 Finding 2: `distance` (task-fix3 cause A) is
			-- a no-op for the forced-instant `exit` and matters only for `enter`,
			-- which IS live here — dropping it silently reproduced cause A's own
			-- "slides a few pixels" bug, scoped to this construct's content region
			distance = declared.distance,
		}
	end

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
				transition = contentTransition(spec.transition),
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

	--[[ THE ACCESSORY, BUILT INSIDE THE HOME THAT HOSTS IT. The homes are already
		`When`s, so the factory runs in a real branch scope (disposed on re-home,
		which is the whole ownership story) and its RETURN decides whether any node
		exists at all — an empty wrapper still takes a dock's slot and a rail's
		slack. `mountedSlots` is that fact made reportable, and it rides the same
		disposal rather than a second mechanism.

		IT HOLDS THE OWNING SCOPE, NOT A BOOLEAN, and that is not bookkeeping taste.
		`aboveBar` is hosted by TWO placements, and `mount.luau` BUILDS THE ARRIVING
		BRANCH BEFORE IT DISPOSES THE DEPARTING ONE — so on a `bottomBar` ⇄
		`bottomBarCompact` rotation the newcomer writes the cell and the leaver then
		clears it, and the dump goes on reporting the slot as absent while its node
		is on screen. Clearing only when the cell still holds THIS scope makes the
		leaver's disposal a no-op in exactly that case, and identical in every
		other. ]]
	local railWidth: any = if spec.railWidth ~= nil then spec.railWidth else NATURAL
	local mountedSlots: { [string]: any } = {}
	local function accessory(slot: string, home: string, branchScope: any): any?
		local factory = if accessories ~= nil then accessories[slot] else nil
		if factory == nil then
			return nil
		end
		local built = factory(home, branchScope)
		if built == nil then
			return nil
		end
		mountedSlots[slot] = branchScope
		branchScope:own({
			dispose = function()
				if mountedSlots[slot] == branchScope then
					mountedSlots[slot] = nil
				end
			end,
		})
		if slot == "trailing" then
			--[[ CONTENT-WIDTH, because the band RESERVES it rather than painting over
				it (I-6, 2026-08-22). It began as an overlay in a ZStack, which keeps a
				hugging cluster centred on the whole band and is what the hand-built
				shell it replaced drew — and it is wrong the moment the strip
				OVERFLOWS: a hugging band takes the whole offer then, so the strip's
				trailing edge and the band's are the same edge, the accessory sits on
				the last tab (measured: 60px of it, taking the taps), and scrolling can
				never uncover it because the content ends exactly where the accessory
				begins. Reserving the width costs the cluster its centre ON THE BAND
				and gives it its centre IN THE SPACE THE TABS HAVE, which is the only
				one of the two that is true at every tab count. ]]
			return UI.HStack({ id = SLOT_ID[slot], align = "center", width = NATURAL, children = { built } })
		end
		if slot == "aboveBar" then
			return UI.VStack({ id = SLOT_ID[slot], align = "stretch", width = FILL, children = { built } })
		end
		-- the rail's ends: CONTENT width, so the rail still hugs the widest of
		-- {head, strip, foot} rather than measuring a `fill` child against nothing
		return UI.VStack({ id = SLOT_ID[slot], align = "stretch", width = NATURAL, children = { built } })
	end

	local rail = UI.When({
		id = "RailHome",
		condition = sidebar,
		thenView = function(branchScope: any)
			local scroller = UI.ScrollView({
				id = "Rail",
				axis = "y",
				width = railWidth,
				height = FILL,
				indicators = "none",
				children = { strip.blueprint },
			})
			local head = accessory("head", "sidebar", branchScope)
			local foot = accessory("foot", "sidebar", branchScope)
			if head == nil and foot == nil then
				return scroller
			end
			--[[ THE FOOT IS THE BOTTOM OF THE RAIL, and this is what makes it so:
				the scroller keeps `height = FILL`, so it spends every pixel of slack
				between the head and the foot. Put the three in a hugging stack
				instead and a three-tab strip leaves the foot parked under the last
				tab — which reads identically in a dump and wrongly on screen. ]]
			local children: { any } = {}
			if head ~= nil then
				table.insert(children, head)
			end
			table.insert(children, scroller)
			if foot ~= nil then
				table.insert(children, foot)
			end
			return UI.VStack({
				id = "RailShell",
				align = "stretch",
				width = railWidth,
				height = FILL,
				children = children,
			})
		end,
	})
	--[[ THE TWO CENTRED HOMES (audit 2026-08-18). `adaptive.luau` states
		the contract twice — `bottomBarCompact` is "the SAME bottom bar in its
		reduced, inline, CENTERED form" and `topBar` is "a CENTER-ALIGNED top tab
		bar that HUGS its content" — and api.md repeats it in two places. This file
		declared no main-axis alignment at all, so on a television a three-tab bar
		was a 193px cluster in the top-left corner with 1547px of empty band beside
		it, and the same at every tablet and landscape-phone width.

		THE NAIVE FIX IS ACCEPTED AND IGNORED, which is why the centring is a
		ZStack: `alignH` is honoured for zstack children and a stack "never reads"
		it (the framework diagnoses exactly that, and `level_picker.luau`'s own
		2026-07-27 ruling records the same trap). The scroller keeps its id and its
		job; the box around it is what decides where the slack goes. Proven by a
		measured `leftGap == rightGap`, never by the property appearing in a dump. ]]
	local topBand = UI.When({
		id = "TopHome",
		condition = isPlacement("topBar"),
		thenView = function(branchScope: any)
			local scroller = UI.ScrollView({
				id = "TopBand",
				axis = "x",
				width = BAND_CAPPED,
				alignH = "center",
				indicators = "none",
				children = { strip.blueprint },
			})
			-- declared AFTER the strip, so it is painted after it and — the same
			-- fact read twice — reads after it in the focus ring
			local trailing = accessory("trailing", "topBar", branchScope)
			if trailing == nil then
				return UI.ZStack({ id = "TopBandCenter", width = FILL, children = { scroller } })
			end
			--[[ A ROW, NOT A STACK, and only when there is something to reserve for.
				The box the strip centres in is the one the accessory has not taken;
				an author who declares nothing gets the shape that shipped, node for
				node. ]]
			return UI.HStack({
				id = "TopBandCenter",
				align = "center",
				width = FILL,
				children = {
					UI.ZStack({ id = "TopBandBox", width = FILL, children = { scroller } }),
					trailing,
				},
			})
		end,
	})
	--[[ THE DOCK. `aboveBar` is a band-relative slot rather than a screen-relative
		one: it rides directly above the strip INSIDE the bottom home, so it moves
		with the bar and disappears with it, and it is declared BEFORE the strip
		because that is where a dock accessory reads (the reference shells' own
		order: the field, then the tabs). Both thumb-zone homes host it — the same
		bar in two forms is still one bar. ]]
	local function dock(id: string, home: string, band: any, branchScope: any): any
		local above = accessory("aboveBar", home, branchScope)
		if above == nil then
			return band
		end
		return UI.VStack({ id = id, align = "stretch", width = FILL, children = { above, band } })
	end
	--[[ THE THUMB ZONE'S TWO SHAPES, and which one it takes is decided ONCE, here:
		`resolveSizing` is pure and this home's placement is a constant, so a
		declared sizing is known at construction and no memo is needed.

		  fill (the default)  NOT a scroller: `fill` segments divide the band, so
		                      the strip is exactly as wide as its offer and a scroll
		                      host would have nothing to scroll. Declaring one anyway
		                      would put a `fill` child on a scroll axis, which
		                      measures against a canvas derived from that child.
		  hug (declared)      the same centred scroller every other hugging home
		                      gets. The comment above belongs to the DEFAULT, not to
		                      the home: before §6 a declared `hug` here was parked at
		                      the band's leading edge with nothing able to scroll it,
		                      so a strip wider than a phone simply ran off the screen.
		                      `p1_glade` is that caller — its bottom bar has always
		                      been a centred natural-width cluster, because equal
		                      segments truncate four localized words on a 320px
		                      phone. ]]
	local bottomHugs = tab_view.resolveSizing(requestedSizing, "bottomBar") == "hug"
	local bottomBand = UI.When({
		id = "BottomHome",
		condition = isPlacement("bottomBar"),
		thenView = function(branchScope: any)
			local band = if bottomHugs
				then UI.ZStack({
					id = "BottomBandCenter",
					width = FILL,
					children = {
						UI.ScrollView({
							id = "BottomBand",
							axis = "x",
							width = BAND_CAPPED,
							alignH = "center",
							indicators = "none",
							children = { strip.blueprint },
						}),
					},
				})
				else UI.VStack({ id = "BottomBand", width = FILL, children = { strip.blueprint } })
			return dock("BottomDock", "bottomBar", band, branchScope)
		end,
	})
	local compactBand = UI.When({
		id = "CompactHome",
		condition = isPlacement("bottomBarCompact"),
		thenView = function(branchScope: any)
			local band = UI.ZStack({
				id = "CompactBandCenter",
				width = FILL,
				children = {
					UI.ScrollView({
						id = "CompactBand",
						axis = "x",
						width = BAND_CAPPED,
						alignH = "center",
						indicators = "none",
						children = { strip.blueprint },
					}),
				},
			})
			return dock("CompactDock", "bottomBarCompact", band, branchScope)
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

	-- sorted, so the dump is deterministic (it is compared whole by the spec that
	-- pins every field a bug report needs)
	local function accessoryMounted(): { string }
		local live: { string } = {}
		for _, slot in ACCESSORY_SLOTS do
			if mountedSlots[slot] ~= nil then
				table.insert(live, slot)
			end
		end
		return live
	end

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
			schema = "facet-tab_view-dump/1",
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
			--[[ THE CHROME, as what was ASKED FOR beside what the home ACTUALLY
				HOSTS — the same pairing `requestedPlacement`/`placement` makes. A
				report of "my wordmark is missing" is answered by the two lists: in
				`declared` but not `mounted` means the placement does not host it,
				which is the sentence the refusal could not say because `automatic`
				makes every home reachable. NOT a substitute for measuring where the
				accessory landed — that is a rect, never a dump. ]]
			accessories = { declared = declaredSlots, mounted = accessoryMounted() },
			semanticText = `Tabs: {label or "none"} ({index or 0} of {#spec.tabs}) in the {placement:get()}`,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return tab_view

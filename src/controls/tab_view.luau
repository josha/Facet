--!strict

-- TabView combines a Picker strip with lazy page content and adaptive placement.
-- Compose owns the control's state, subscriptions, pages and cleanup. Durable
-- application state stays outside page factories so it survives navigation.
-- Nested tabs use local navigation; only the outer tabs follow the environment.
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local selectionModel = require("../selection_model")
local adaptive = require("../layout/adaptive")
local contribution = require("../input/contribution")
local picker = require("./picker")
local collapsibleView = require("./collapsible_view")
local chromeSlots = require("../tokens/chrome_slots")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")

local tab_view = {}

-- `content` is a FACTORY, not a blueprint, and that is what makes the tab lazy:
-- it is not called until the tab is selected, and the scope it receives is
-- disposed when the tab is deselected.
local specTypes = require("../spec_types/tab_view")
export type Tab = specTypes.Tab

-- THE CHROME BESIDE THE TABS. Each slot is a FACTORY rather than a blueprint for
-- the same two reasons `content` is: it is not built until the home that hosts it
-- is mounted, and the `scope` it receives is disposed when that home goes away. It
-- is told the placement so ONE function can serve several homes, and it may
-- return nothing to decline one of them.
export type Accessories = specTypes.Accessories

type StringCell = specTypes.StringCell
export type Spec<V = StringCell> = specTypes.Spec<V>

local PLACEMENTS: { [string]: boolean } = {
	automatic = true,
	bottomBar = true,
	bottomBarCompact = true,
	topBar = true,
	sidebar = true,
}
local INDICATORS: { [string]: boolean } = { automatic = true, none = true, underline = true, pill = true }
local SIZINGS: { [string]: boolean } = { automatic = true, fill = true, hug = true }

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

local BAND_CAPPED = table.freeze({ type = "hug" })

-- CLOSED SPEC (constitution §4). An unknown key is an authoring mistake,
-- never a silent no-op.
local TABVIEW_KEYS = specGuard.keySet({
	"accessories",
	"conditions",
	"customization",
	"sections",
	"enabled",
	"env",
	"iconOnly",
	"id",
	"indicator",
	"onChange",
	"placement",
	"railWidth",
	"restoreFocus",
	"shoulderNavigation",
	"sidebarPreference",
	"restoreScroll",
	"selection",
	"sizing",
	"style",
	"tabs",
	"textSize",
	"transition",
})

local BUILD_DEPTH = 0

--[[ THE PAGE TRANSITION, RESOLVED BY THE FRAMEWORK'S OWN RESOLVER.

	The refusal below has always promised "the same { enter?, exit?, class? }
	`UI.When` takes" — and the construct then keyed on `transition.fade == true`
	and nothing else, so `transition = { enter = "fade" }`, which is the spelling
	the promise names and the one both reference shells write, was accepted and
	SILENTLY DROPPED: a declared crossfade played as a hard cut and no diagnostic
	said so. Two spellings disagreeing about the same field is worse than either.

	So the declaration goes through `transitions.resolve`, which is the exact
	validator `UI.When` runs — unknown fields, unknown forms and a malformed
	`source` are refused here in the same words they are refused there.

	WHAT A TABVIEW CAN PLAY IS ONE FORM. Its pages occupy the SAME box, so a
	slide has nothing to slide against and a transform has no origin: the only
	structural motion between two co-located layers is a crossfade. A form it
	cannot play is refused rather than ignored, which is the whole defect above
	turned into a rule. `instant` is legal and means what it says.

	`{ fade = true }` — the spelling this control shipped with, and the one the
	reference gallery and `examples/` still carry — stays legal. `fade` is a
	MODIFIER in the shared vocabulary and names no form on its own, so on a
	TabView it means the one form a TabView has. ]]
local function resolveTransition(id: string, declared: any): boolean
	if declared == nil then
		return false
	end
	if type(declared) ~= "table" then
		error(
			`Facet UI.TabView('{id}'): \`transition\` must be a TABLE — the same `
				.. "{ enter?, exit?, class? } `UI.When` takes, not the name of one.",
			0
		)
	end
	if declared.enter == nil and declared.fade == true then
		declared = table.clone(declared)
		declared.enter = "fade"
	end
	local ok, resolved = pcall(require("../render/transitions").resolve, declared)
	if not ok then
		error(`Facet UI.TabView('{id}'): {tostring(resolved)}`, 0)
	end
	local enter, exit = resolved.enter, resolved.exit
	if enter == "instant" and exit == "instant" then
		return false
	end
	if enter ~= "fade" or exit ~= "fade" then
		error(
			`Facet UI.TabView('{id}'): cannot play \`enter = "{enter}"\` / \`exit = "{exit}"\` — a TabView's pages `
				.. "occupy the SAME box, so the only structural motion between them is a crossfade. Declare "
				.. '`transition = { enter = "fade" }` (or `{ fade = true }`), `{ enter = "instant" }` for a hard '
				.. "cut, or drop `transition` entirely — playing a form you did not ask for is not the answer, "
				.. "and neither is ignoring the one you did.",
			0
		)
	end
	return true
end

function tab_view.resolvePlacement(requested: string, nested: boolean, policy: string?): (string, string)
	if requested ~= "automatic" then
		return requested, "declared"
	end
	if nested then
		return NESTED_PLACEMENT, "nested"
	end
	return policy or "bottomBar", "policy"
end

function tab_view.resolveSizing(requested: string, placement: string): string
	if requested ~= "automatic" then
		return requested
	end
	return if placement == "bottomBar" then "fill" else "hug"
end

function tab_view.accessoryPlacements(slot: string): { string }?
	local homes = ACCESSORY_HOMES[slot]
	return if homes == nil then nil else table.clone(homes)
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	specGuard.assertKnownKeys("UI.TabView", spec, TABVIEW_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "TabView"
	local scrollBookmarks = if spec.restoreScroll ~= false then require("./scroll_bookmarks").new(owner.own) else nil
	-- READ THE DEPTH BEFORE ANYTHING ELSE CAN CHANGE IT. This is the whole
	-- nesting decision, and it is a fact about WHERE THIS CALL IS, so it is taken
	-- at the top of the call and never re-read.
	local nested = BUILD_DEPTH > 0

	local selection = spec.selection
	if not selectionModel.isWritable(selection) then
		error(
			`Facet UI.TabView('{id}'): \`selection\` must be a writable Compose cell the caller owns. It is the `
				.. "escape hatch as well as the state: everything that must survive a tab switch lives in a "
				.. "writable Compose cell outside this control, and this is the first one.",
			0
		)
	end
	if type(spec.tabs) ~= "table" or #spec.tabs == 0 then
		error(`Facet UI.TabView('{id}'): \`tabs\` must be a non-empty array of ` .. "{ id, label?, content }", 0)
	end
	local seen: { [string]: boolean } = {}
	for index, tab in spec.tabs do
		if type(tab) ~= "table" then
			error(`Facet UI.TabView('{id}'): tab {index} must be a table of id / label? / icon? / badge? / content`, 0)
		end
		if type(tab.id) ~= "string" or tab.id == "" then
			error(
				`Facet UI.TabView('{id}'): tab {index} needs a non-empty string \`id\` — it is the SELECTION `
					.. "VALUE the caller's cell holds, and it is what `dump()` reports.",
				0
			)
		end
		if seen[tab.id] then
			error(
				`Facet UI.TabView('{id}'): two tabs share the id '{tab.id}'. A tab id is the selection value, so `
					.. "a duplicate makes the selection ambiguous rather than merely confusing.",
				0
			)
		end
		seen[tab.id] = true
		if type(tab.content) ~= "function" then
			error(
				`Facet UI.TabView('{id}'): tab '{tab.id}' needs \`content\` as a FUNCTION (tabScope) -> Blueprint, `
					.. "not a blueprint. It is a factory because the tab is LAZY: it is not called until the tab "
					.. "is selected, and `tabScope` is disposed when the tab is deselected. State that must "
					.. "survive a switch belongs to a cell the CALLER owns, outside this control.",
				0
			)
		end
	end

	local sectionLabels = {}
	for _, section in spec.sections or {} do
		specGuard.assertKnownKeys("TabView.section", section, specGuard.keySet({ "id", "label" }), "section")
		assert(
			type(section.id) == "string"
				and section.id ~= ""
				and not sectionLabels[section.id]
				and type(section.label) == "string",
			"UI.TabView.sections require unique IDs and labels"
		)
		sectionLabels[section.id] = section.label
	end
	for _, tab in spec.tabs do
		assert(tab.required == nil or type(tab.required) == "boolean", "UI.TabView.tab.required must be boolean")
		assert(
			tab.section == nil or sectionLabels[tab.section] ~= nil,
			"UI.TabView.tab.section must name a declared section"
		)
	end
	assert(
		spec.customization == nil or selectionModel.isWritable(spec.customization),
		"UI.TabView.customization must be a caller-owned signal"
	)
	local liveStrip = spec.customization ~= nil or spec.sections ~= nil
	local function customized(state)
		state = state or {}
		specGuard.assertKnownKeys(
			"TabView.customization",
			state,
			specGuard.keySet({ "order", "hidden" }),
			"customization"
		)
		local hidden, ordered, used = {}, {}, {}
		for _, name in { "order", "hidden" } do
			assert(state[name] == nil or type(state[name]) == "table", "UI.TabView.customization arrays required")
			for _, value in state[name] or {} do
				assert(type(value) == "string", "UI.TabView.customization IDs must be strings")
			end
		end
		for _, id in state.hidden or {} do
			hidden[id] = true
		end
		local function append(id)
			if used[id] then
				return
			end
			for _, tab in spec.tabs do
				if tab.id == id then
					used[id] = true
					if tab.required or not hidden[id] then
						table.insert(ordered, tab)
					end
					return
				end
			end
		end
		for _, id in state.order or {} do
			append(id)
		end
		for _, tab in spec.tabs do
			append(tab.id)
		end
		if #ordered == 0 then
			table.insert(ordered, spec.tabs[1])
		end
		return ordered
	end
	local visibleTabs = Compose.formula(function(use)
		return customized(if spec.customization then selectionModel.read(spec.customization, use) else nil)
	end)
	local function reconcileTabs()
		local current = selectionModel.read(selection)
		for _, tab in visibleTabs:peek() do
			if tab.id == current then
				return
			end
		end
		if seen[current] then
			selection:set(visibleTabs:peek()[1].id)
		end
	end
	if liveStrip then
		owner.watchStatic(visibleTabs, reconcileTabs)
		reconcileTabs()
	end
	assert(
		spec.restoreScroll == nil or type(spec.restoreScroll) == "boolean",
		"UI.TabView.restoreScroll must be boolean"
	)

	assert(
		spec.restoreFocus == nil or type(spec.restoreFocus) == "boolean",
		"UI.TabView.restoreFocus must be a boolean"
	)
	local function contentShoulders()
		local value = selectionModel.read(spec.shoulderNavigation)
		assert(
			value == nil or value == "strip" or value == "content",
			"UI.TabView.shoulderNavigation must be strip | content, or a readable policy"
		)
		return value == "content"
	end
	contentShoulders()

	local collapsed = spec.style == "collapsible"
	local collapsedOpen = if collapsed then Compose.cell(false) else nil
	local adaptable = spec.style == "sidebarAdaptable" and not nested
	assert(
		spec.style == nil or spec.style == "automatic" or spec.style == "sidebarAdaptable" or collapsed,
		"UI.TabView.style must be automatic | sidebarAdaptable | collapsible"
	)
	assert(
		not adaptable or spec.placement == nil or spec.placement == "automatic",
		"UI.TabView.sidebarAdaptable requires automatic placement"
	)
	local navigationEnv = surfaceEnv.forSpec(core, spec.env)
	assert(not adaptable or navigationEnv ~= nil, "UI.TabView.sidebarAdaptable requires the surface environment")
	assert(
		spec.sidebarPreference == nil or adaptable or nested,
		"UI.TabView.sidebarPreference requires sidebarAdaptable style"
	)
	local declaredSidebarPreference = Compose.formula(function(use)
		local value = if spec.sidebarPreference == nil
			then "automatic"
			else selectionModel.read(spec.sidebarPreference, use)
		assert(
			value == "automatic" or value == "sidebar" or value == "topBar",
			"UI.TabView.sidebarPreference must be automatic | sidebar | topBar"
		)
		return value
	end)
	declaredSidebarPreference:peek()
	local sidebarPreference = if adaptable then Compose.cell(nil) else nil
	local pendingNavigation: string? = nil
	local pendingPlacement: string? = nil
	local navigationAttempts = 0
	local distantNavigation = if adaptable
		then Compose.formula(function(use)
			return use(navigationEnv:get("distanceProfile")) == "ten-foot"
		end)
		else nil
	assert(
		not collapsed or spec.placement == nil or spec.placement == "automatic" or spec.placement == "topBar",
		"UI.TabView.collapsible uses topBar placement"
	)
	local requestedPlacement = if collapsed then "topBar" else spec.placement or "automatic"
	if not PLACEMENTS[requestedPlacement] then
		error(
			`Facet UI.TabView('{id}'): unknown placement '{tostring(requestedPlacement)}'. One of automatic | `
				.. "bottomBar | bottomBarCompact | topBar | sidebar — the vocabulary `adaptive.navPlacement` "
				.. "already speaks. A device name is not one of them.",
			0
		)
	end
	local requestedIndicator = spec.indicator or "automatic"
	if not INDICATORS[requestedIndicator] then
		error(
			`Facet UI.TabView('{id}'): unknown indicator '{tostring(requestedIndicator)}'. `
				.. "One of automatic | none | underline | pill.",
			0
		)
	end
	local requestedSizing = spec.sizing or "automatic"
	if not SIZINGS[requestedSizing] then
		error(
			`Facet UI.TabView('{id}'): unknown sizing '{tostring(requestedSizing)}'. One of automatic | fill | hug.`,
			0
		)
	end

	-- ===== the accessories ====================================================

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
			`Facet UI.TabView('{id}'): \`railWidth\` is the SIDEBAR rail's band, and {whyUnreachable()}. `
				.. "Leave the placement `automatic` and it applies wherever the rail is, or drop it.",
			0
		)
	end

	local accessories: any = spec.accessories
	local declaredSlots: { string } = {}
	if accessories ~= nil then
		if type(accessories) ~= "table" then
			error(
				`Facet UI.TabView('{id}'): \`accessories\` must be a TABLE of slots — `
					.. "{ head?, foot?, trailing?, aboveBar? }, each a (placement, scope) -> Blueprint? factory.",
				0
			)
		end

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
					`Facet UI.TabView('{id}'): unknown accessory slot '{tostring(slot)}'. One of `
						.. table.concat(ACCESSORY_SLOTS, " | ")
						.. " — the head and foot of the RAIL, the trailing edge of the TOP band, and the strip "
						.. "ABOVE a thumb-zone dock. A band has no other edge to spare (see this control's header).",
					0
				)
			end
			if type(factory) ~= "function" then
				error(
					`Facet UI.TabView('{id}'): accessory '{slot}' must be a FUNCTION (placement, scope) -> Blueprint?, `
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
					`Facet UI.TabView('{id}'): accessory '{slot}' can never mount — {whyUnreachable()}, and '{slot}' is hosted `
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

	local crossfade = resolveTransition(id, spec.transition)

	-- ===== the placement =====================================================
	-- The policy Readable, and the ONE place it is asked for. A nested TabView
	-- never reaches it, so a page's own tabs cannot claim the app's home.
	local policySource: any = nil
	if requestedPlacement == "automatic" and not nested then
		local publishedEnv = surfaceEnv.forSpec(core, spec.env)
		if spec.conditions ~= nil then
			policySource = spec.conditions.navPlacement
		elseif publishedEnv ~= nil then
			-- Compute only the policy this control uses, from the shared rules.
			policySource = Compose.formula(function(use)
				local viewport = use(publishedEnv:get("viewportRect"))
				local distance = use(publishedEnv:get("distanceProfile"))
				local interaction = use(publishedEnv:get("interactionClasses"))
				return adaptive.navPlacement({
					sizeClass = use(publishedEnv:get("sizeClass")),
					heightClass = adaptive.heightClass(viewport.h, { distanceProfile = distance }),
					distanceProfile = distance,
					primary = interaction.primary,
					displaySize = use(publishedEnv:get("effectiveDisplaySize")),
				})
			end)
		else
			error(
				`Facet UI.TabView('{id}'): an automatic placement reads \`adaptive.navPlacement\`, so it needs `
					.. "an environment. A surface stood up with `Facet.client.host.new` publishes one on the "
					.. "core it builds and this control finds it with no wiring; otherwise pass `conditions` "
					.. "(the table `Facet.adaptive.conditions(env)` returns — pass yours so its memos "
					.. "are not built twice) or `env`. Or declare `placement` and the policy is never "
					.. "consulted.",
				0
			)
		end
	end

	local function preferredHome(home, distant, declared, command)
		if home == "bottomBar" or home == "bottomBarCompact" then
			return home
		end
		if command ~= nil and command.distant == distant then
			return if command.expanded then "sidebar" else "topBar"
		end
		return if not distant and declared ~= "automatic" then declared else home
	end
	local placementSource = select(2, tab_view.resolvePlacement(requestedPlacement, nested, nil))
	local placement = Compose.formula(function(use)
		local policy = if policySource ~= nil then use(policySource) else nil
		local home = tab_view.resolvePlacement(requestedPlacement, nested, policy)
		if not adaptable or nested or home == "bottomBar" or home == "bottomBarCompact" then
			return home
		end
		return preferredHome(home, use(distantNavigation), use(declaredSidebarPreference), use(sidebarPreference))
	end)
	local function setSidebar(expanded: boolean)
		local previous = placement:peek()
		local distant = distantNavigation:peek()
		local preference = sidebarPreference:peek()
		if preference and preference.expanded == expanded and preference.distant == distant then
			return
		end
		sidebarPreference:set({ expanded = expanded, distant = distant })
		-- Remember the preference for a later resize, but only hand off focus
		-- when navigation actually relocates. Compact bottom tabs cannot expand.
		if placement:peek() ~= previous then
			pendingNavigation = if expanded then "tabs" else "content"
			pendingPlacement = placement:peek()
			navigationAttempts = 0
		end
	end
	if adaptable then
		local previousDeclaration = declaredSidebarPreference:peek()
		owner.watchStatic(declaredSidebarPreference, function(value)
			if value == previousDeclaration then
				return
			end
			local home = tab_view.resolvePlacement(requestedPlacement, nested, selectionModel.read(policySource))
			local previous =
				preferredHome(home, distantNavigation:peek(), previousDeclaration, sidebarPreference:peek())
			previousDeclaration = value
			sidebarPreference:set(nil)
			if placement:peek() ~= previous then
				pendingNavigation = if placement:peek() == "sidebar" then "tabs" else "content"
				pendingPlacement = placement:peek()
				navigationAttempts = 0
			end
		end)
	end
	local function isPlacement(name: string): any
		return Compose.formula(function(use)
			return use(placement) == name
		end)
	end
	local sizing = Compose.formula(function(use)
		return tab_view.resolveSizing(requestedSizing, use(placement))
	end)
	-- the SIDEBAR is the one home that runs down the screen; every other home is
	-- a band across it. The strip's axis and the root's axis are the same fact
	-- read twice, and both are bound, so a rotation is a re-solve.
	local sidebar = isPlacement("sidebar")

	local barCornerToken = Compose.formula(function(use)
		return if use(sidebar) then "panel" else "control"
	end)
	local barCorners = Compose.formula(function(use)
		return UI.cornersData(use(barCornerToken))
	end)
	-- ...and this is the one the STRIP is handed: the band's control shape, or nothing
	local stripContainer = Compose.formula(function(use)
		return if use(sidebar) then nil else "control"
	end)
	local stripAxis = Compose.formula(function(use)
		return if collapsed or use(sidebar) then "y" else "x"
	end)
	local rootAxis = Compose.formula(function(use)
		return if use(sidebar) then "x" else "y"
	end)

	-- ===== the strip: a segmented picker, nothing more ========================
	local function stripOptions(use)
		local out = {}
		local previousSection
		for _, tab in (if use then use(visibleTabs) else visibleTabs:peek()) do
			table.insert(out, {
				id = if liveStrip then tab.id else nil,
				value = tab.id,
				label = tab.label or tab.id,
				icon = tab.icon,
				badge = tab.badge,
				sectionTitle = if liveStrip and tab.section ~= previousSection then sectionLabels[tab.section] else nil,
			})
			previousSection = tab.section
		end
		return out
	end
	local options = if liveStrip then Compose.formula(stripOptions) else stripOptions()
	local strip = picker.build(
		Facet,
		core,
		{
			id = "Strip",
			options = options,
			selected = selection,
			presentation = "segmented",
			-- a tab strip sits in the band this control already draws; the picker's
			-- own segmented track would be a second plate around it (2026-09-11)
			track = false,
			-- ...and THAT band is the container the selected fill has to match, so the
			-- adaptable bar's BAND corner travels with the strip. `nil` for the rail
			-- form and for every other style: a rail row is not concentric with the
			-- rail, and a plain top band is a bare scroller with no plate at all.
			stripCorner = if adaptable then stripContainer else nil,
			indicator = if requestedIndicator == "automatic"
				then (if adaptable then "pill" else AUTOMATIC_INDICATOR)
				else requestedIndicator,
			axis = stripAxis,
			sizing = if collapsed then "fill" else sizing,
			iconOnly = spec.iconOnly,
			textSize = spec.textSize,
			env = spec.env,
			enabled = spec.enabled,
			onChange = function(value)
				if collapsedOpen then
					collapsedOpen:set(false)
				end
				if spec.onChange then
					spec.onChange(value)
				end
			end,
		},
		if collapsed
			then function()
				collapsedOpen:set(false)
			end
			else nil
	)
	owner.own(function()
		strip.dispose()
	end)

	local collapsedControl
	if collapsed then
		local function selectedProperty(property, fallback)
			return Compose.formula(function(use)
				local current = selectionModel.read(selection, use)
				for _, tab in use(visibleTabs) do
					if tab.id == current then
						local value = tab[property]
						return selectionModel.read(value, use) or fallback
					end
				end
				return fallback
			end)
		end
		collapsedControl = collapsibleView.build(Facet, core, {
			id = "Navigation",
			label = selectedProperty("label", "Navigation"),
			icon = selectedProperty("icon", nil),
			initialFocus = Compose.formula(function(use)
				local current = selectionModel.read(selection, use)
				for index, tab in use(visibleTabs) do
					if tab.id == current then
						return if strip.segments and strip.segments[index]
							then strip.segments[index].id
							else "Option-" .. tab.id
					end
				end
				return "first"
			end),
			expanded = collapsedOpen,
			content = strip.blueprint,
			env = spec.env,
			enabled = spec.enabled,
		})
		owner.own(function()
			collapsedControl.dispose()
		end)
	end

	-- ===== the content: one branch per tab, only one mounted =================
	local mounted: { [string]: boolean } = {}
	local mountCount = 0
	local evictions = 0
	local function buildPage(tab)
		-- `content` receives the page's Compose owner, as NavigationStack pages do.
		local pageOwner = Compose.currentOwner()
		local tabId = tab.id
		-- THE BUILD STACK, raised for exactly the duration of the
		-- caller's factory. `pcall` so a factory that throws still
		-- lowers it: an unbalanced depth would make every later
		-- TabView on the session think it was nested.
		BUILD_DEPTH += 1
		local ok, built = pcall(tab.content, pageOwner)
		BUILD_DEPTH -= 1
		if not ok then
			error(built, 0)
		end
		mounted[tabId] = true
		mountCount += 1
		-- Release page bookkeeping with the page's owner.
		local function releasePage()
			mounted[tabId] = nil
			evictions += 1
		end
		pageOwner.own(releasePage)
		return built
	end
	local contentChildren: { any }
	if crossfade then
		contentChildren = {}
		local env = require("../env/surface_env").find(core)
		for _, tab in spec.tabs do
			local completed
			table.insert(
				contentChildren,
				Compose.presence(function(use)
					return selectionModel.read(selection, use) == tab.id
				end, function(phase)
					local entry = Facet.runtime.timeline({ duration = 0.16 })
					local departure = Facet.runtime.tween(function(use)
						return if use(phase.exiting) then 0 else 1
					end, { seconds = 0.16 })
					local function reduced(use)
						return env ~= nil and use(env:get("motionPolicy")) == "reduced"
					end
					completed = Compose.formula(function(use)
						return reduced(use) or use(departure) <= 0
					end)
					return UI.ZStack({
						id = "Tab-" .. tab.id,
						width = FILL,
						height = FILL,
						enabled = function(use)
							return not use(phase.exiting)
						end,
						opacity = function(use)
							if reduced(use) then
								return if use(phase.exiting) then 0 else 1
							end
							return use(entry.progress) * use(departure)
						end,
						children = { buildPage(tab) },
					})
				end, {
					exit = function()
						return { completed = completed }
					end,
				})
			)
		end
	else
		contentChildren = {
			Compose.LayerStack({
				from = function(use)
					local selected = selectionModel.read(selection, use)
					for _, tab in spec.tabs do
						if tab.id == selected then
							return { tab }
						end
					end
					return {}
				end,
				key = function(tab)
					return tab.id
				end,
				retention = "top",
				render = function(current)
					local tab = current:peek()
					return UI.VStack({
						id = "Tab-" .. tab.id,
						width = FILL,
						height = FILL,
						children = { buildPage(tab) },
					})
				end,
			}),
		}
	end

	local content = (if crossfade then UI.ZStack else UI.VStack)({
		id = "Content",
		align = if crossfade then nil else "stretch",
		width = FILL,
		height = FILL,
		children = contentChildren,
	})

	-- ===== the three homes ===================================================
	-- One strip blueprint, declared in each home under mutually-exclusive
	-- conditions, so exactly one is mounted and the picker object is built once.
	-- Every strip/content boundary owns a theme-sized gap (see the root stack's
	-- own `gap`); pages still own their internal spacing.

	-- The scrolling homes are ScrollViews because a hugging strip can be wider
	-- than its offer; the thumb-zone band is not, because a `fill` strip divides
	-- the offer and has nothing to overflow with.

	local railWidth: any = if spec.railWidth ~= nil then spec.railWidth else NATURAL
	local mountedSlots: { [string]: any } = {}
	local function accessory(slot: string, home: string): any?
		local factory = if accessories ~= nil then accessories[slot] else nil
		if factory == nil then
			return nil
		end
		local slotOwner = Compose.currentOwner()
		local built = factory(home, slotOwner)
		if built == nil then
			return nil
		end
		local owner = slotOwner
		mountedSlots[slot] = owner
		local function releaseSlot()
			if mountedSlots[slot] == owner then
				mountedSlots[slot] = nil
			end
		end
		slotOwner.own(releaseSlot)
		if slot == "trailing" then
			return UI.HStack({ id = SLOT_ID[slot], align = "center", width = NATURAL, children = { built } })
		end
		if slot == "aboveBar" then
			return UI.VStack({ id = SLOT_ID[slot], align = "stretch", width = FILL, children = { built } })
		end
		-- the rail's ends: CONTENT width, so the rail still hugs the widest of
		-- {head, strip, foot} rather than measuring a `fill` child against nothing
		return UI.VStack({ id = SLOT_ID[slot], align = "stretch", width = NATURAL, children = { built } })
	end

	local rail = if adaptable
		then nil
		else UI.When({
			id = "RailHome",
			condition = sidebar,
			thenView = function()
				local scroller = UI.ScrollView({
					id = "Rail",
					axis = "y",
					width = railWidth,
					height = FILL,
					indicators = "none",
					children = { strip.blueprint },
				})
				local head = accessory("head", "sidebar")
				local foot = accessory("foot", "sidebar")
				if head == nil and foot == nil then
					return scroller
				end

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

	local topBand = if adaptable
		then nil
		else UI.When({
			id = "TopHome",
			condition = isPlacement("topBar"),
			thenView = function()
				local scroller = if collapsedControl
					then UI.ZStack({ id = "TopBand", alignH = "center", children = { collapsedControl.blueprint } })
					else UI.ScrollView({
						id = "TopBand",
						axis = "x",
						width = BAND_CAPPED,
						alignH = "center",
						indicators = "none",
						children = { strip.blueprint },
					})
				-- declared AFTER the strip, so it is painted after it and — the same
				-- fact read twice — reads after it in the focus ring
				local trailing = accessory("trailing", "topBar")
				if trailing == nil then
					return UI.ZStack({ id = "TopBandCenter", width = FILL, children = { scroller } })
				end

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

	local function dock(id: string, home: string, band: any): any
		local above = accessory("aboveBar", home)
		if above == nil then
			return band
		end
		return UI.VStack({ id = id, align = "stretch", width = FILL, children = { above, band } })
	end

	local bottomHugs = tab_view.resolveSizing(requestedSizing, "bottomBar") == "hug"
	local bottomBand = UI.When({
		id = "BottomHome",
		condition = isPlacement("bottomBar"),
		thenView = function()
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
			return dock("BottomDock", "bottomBar", band)
		end,
	})
	local compactBand = UI.When({
		id = "CompactHome",
		condition = isPlacement("bottomBarCompact"),
		thenView = function()
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
			return dock("CompactDock", "bottomBarCompact", band)
		end,
	})

	-- One adaptive home keeps the navigation controls mounted when the rail
	-- becomes a top capsule. Only placement-specific accessory factories retire.
	local persistentHome
	if adaptable then
		persistentHome = UI.When({
			id = "RailHome",
			condition = Compose.formula(function(use)
				local p = use(placement)
				return p == "topBar" or p == "sidebar"
			end),
			thenView = function()
				local function choose(a, b)
					return function(use)
						return if use(sidebar) then a else b
					end
				end
				local stripWidth, stripHeight = choose(railWidth, BAND_CAPPED), choose(FILL, NATURAL)
				local bar = chromeSlots.attachHint(
					UI.AdaptiveStack({
						id = "AdaptableBar",
						axis = stripAxis,
						width = choose(railWidth, BAND_CAPPED),
						height = choose(FILL, NATURAL),
						align = "center",
						alignH = "center",
						surface = "raised",

						corners = barCorners,
						padding = "xs",
						gap = "m",
						children = {
							UI.ScrollView({
								id = "StripScroll",
								axis = stripAxis,
								width = stripWidth,
								height = stripHeight,
								indicators = "none",
								children = { strip.blueprint },
							}),
						},
					}),
					{ slot = "navigation" }
				)
				local children = {}
				local function addAccessory(slot, home)
					if accessories == nil or accessories[slot] == nil then
						return
					end
					table.insert(
						children,
						UI.When({
							id = slot .. "Home",
							condition = if home == "sidebar"
								then sidebar
								else function(use)
									return use(placement) == "topBar"
								end,
							thenView = function()
								return accessory(slot, home)
							end,
						})
					)
				end
				addAccessory("head", "sidebar")
				table.insert(
					children,
					UI.ZStack({
						id = "NavigationCenter",
						width = FILL,
						height = choose(FILL, NATURAL),
						children = { bar },
					})
				)
				addAccessory("trailing", "topBar")
				addAccessory("foot", "sidebar")
				return UI.AdaptiveStack({
					id = "NavigationHome",
					axis = stripAxis,
					align = choose("stretch", "center"),
					width = choose(railWidth, FILL),
					height = choose(FILL, NATURAL),
					children = children,
				})
			end,
		})
	end

	-- DECLARATION ORDER IS FOCUS ORDER, and the strip reads where it is PAINTED:
	-- the leading rail and the top band before the content, the bottom bands
	-- after it (`p1_glade/init.luau:953`, the shipped rule).
	local root = UI.AdaptiveStack({
		id = id,
		axis = rootAxis,

		gap = Compose.formula(function(use)
			if use(sidebar) then
				return "m"
			end
			return if use(placement) == "bottomBarCompact" then 0 else "s"
		end),
		width = FILL,
		height = FILL,
		children = if persistentHome
			then { persistentHome, content, bottomBand, compactBand }
			else { rail, topBand, content, bottomBand, compactBand },
	})

	-- ===== reachability and keep-visible ====================================
	local boundController: any = nil
	local tabPaths: { [string]: string } = {}
	local mountedRootPath: string? = nil
	local learnedStructureEpoch = nil
	local learnedPlacement: string? = nil
	local revealed: any = nil
	local reveals = 0
	-- One stable path per authored tab, owned by this control, not by its evicted
	-- content. Pointer entry chooses exactly what was clicked. Navigation entry
	-- restores only a still-eligible mounted target; virtual collections retain
	-- responsibility for revealing off-window keys. No instances or item models
	-- are kept alive by a bookmark.
	local bookmarks: { [string]: string } = {}
	local graph: any = nil
	local offFocus: any = nil
	local enteredTab: string? = nil
	owner.own(function()
		if offFocus ~= nil then
			offFocus()
		end
		table.clear(bookmarks)
	end)
	local function rememberFocus(path: string?)
		if graph == nil or mountedRootPath == nil or spec.restoreFocus == false then
			return
		end
		local tabId = selectionModel.read(selection)
		local prefix = mountedRootPath .. "/Content/Tab-" .. tabId .. "/"
		if path == nil or string.sub(path, 1, #prefix) ~= prefix then
			enteredTab = nil
			return
		end
		local entering = enteredTab ~= tabId
		enteredTab = tabId -- set before focusOn: notification is synchronous
		local saved = bookmarks[tabId]
		if entering and saved ~= nil and saved ~= path and graph.focusOrigin() == "navigation" then
			if graph.focusOn(saved) then
				if boundController ~= nil and boundController.scrollToVisible ~= nil then
					boundController.scrollToVisible(saved)
				end
				return
			end
		end
		bookmarks[tabId] = path
	end

	local function indexOf(value: any): number?
		for i, tab in visibleTabs:peek() do
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
		for i, segment in strip.segments or {} do
			wanted[segment.id] = spec.tabs[i].id
		end
		tabPaths = {}
		local function walk(node: any)
			local tabId = wanted[node.id]
			if liveStrip and (node.id == "Option" or string.sub(node.id, 1, 7) == "Option-") then
				for _, tab in visibleTabs:peek() do
					if string.find(node.path, "/Options/Rows/[" .. tab.id .. "]", 1, true) then
						tabId = tab.id
						break
					end
				end
			end
			if tabId ~= nil and tabPaths[tabId] == nil then
				tabPaths[tabId] = node.path
			end
			for _, child in node.children or {} do
				walk(child)
			end
		end
		for _, child in rootNode.children or {} do
			if child.id ~= "Content" then
				walk(child)
			end
		end
	end

	local built = contribution.attach(root, {
		handleCancel = function(path)
			if
				adaptable
				and placement:peek() == "sidebar"
				and path
				and mountedRootPath
				and string.sub(path, 1, #mountedRootPath + 10) == mountedRootPath .. "/RailHome/"
			then
				setSidebar(false)
				return true
			end
			return false
		end,
		bindInputScope = if adaptable or spec.shoulderNavigation ~= nil
			then function(input)
				owner.own(input.onTick(function()
					if pendingNavigation and graph and mountedRootPath then
						if placement:peek() ~= pendingPlacement then
							pendingNavigation = nil
							return
						end
						local pending = pendingNavigation
						navigationAttempts += 1
						-- No eligible content (or compact fallback) must not poll forever.
						if navigationAttempts >= 3 then
							pendingNavigation = nil
						end
						if pending == "tabs" then
							local dest = tabPaths[selectionModel.read(selection)]
							-- Tick may precede refresh: never consume the handoff by
							-- focusing a still-indexed option in the outgoing home.
							if
								dest
								and string.sub(dest, 1, #mountedRootPath + 10) == mountedRootPath .. "/RailHome/"
								and learnedPlacement == pendingPlacement
								and graph.focusOn(dest)
							then
								pendingNavigation = nil
							end
						else
							local prefix = mountedRootPath .. "/Content/Tab-" .. selectionModel.read(selection) .. "/"
							local map = graph.focusMap()
							for _, entry in (map and map.traversal) or {} do
								if string.sub(entry.path, 1, #prefix) == prefix and graph.focusOn(entry.path) then
									pendingNavigation = nil
									break
								end
							end
						end
					end
				end))
			end
			else nil,
		bindFocusGraph = function(focusGraph: any)
			if graph == focusGraph then
				return
			end
			if offFocus ~= nil then
				offFocus()
			end
			graph = focusGraph
			offFocus = owner.watchStatic(graph.focused, rememberFocus)
		end,
		-- the renderer's controller, for the ONE programmatic scroll this control
		-- issues. Absent is a supported degradation: a standalone strip with no
		-- engine to scroll simply does not scroll.
		bindController = function(controller: any)
			boundController = controller
		end,

		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			-- A solve can notify the previous contribution list before the
			-- presenter collects the newly mounted pages.
			if owner.isDisposed() then
				return
			end
			if scrollBookmarks then
				scrollBookmarks.sync(boundController, rootNode)
			end
			if
				rootNode ~= nil
				and (
					(learnedStructureEpoch ~= boundController.structureEpoch())
					or rootNode.path ~= mountedRootPath
					or learnedPlacement ~= placement:peek()
				)
			then
				mountedRootPath = rootNode.path
				learnedStructureEpoch = boundController.structureEpoch()
				learnedPlacement = placement:peek()
				relearn(rootNode)
			end
			local current = selectionModel.read(selection)
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
		-- Content paging is explicit and owns shoulders only. The nearest value
		-- control keeps its adjustment; the surface owns gameplay arbitration.
		adjustAxis = if spec.shoulderNavigation ~= nil then "none" else nil,
		adjustTargets = function(rootNode: any?)
			if
				rootNode ~= nil
				and (
					(learnedStructureEpoch ~= boundController.structureEpoch())
					or rootNode.path ~= mountedRootPath
					or learnedPlacement ~= placement:peek()
				)
			then
				mountedRootPath = rootNode.path
				learnedStructureEpoch = boundController.structureEpoch()
				learnedPlacement = placement:peek()
				relearn(rootNode)
			end
			local targets: { [string]: boolean } = {}
			for _, path in tabPaths do
				targets[path] = true
			end
			if contentShoulders() and graph and mountedRootPath then
				local prefix = mountedRootPath .. "/Content/"
				local map = graph.focusMap()
				for _, entry in (map and map.traversal) or {} do
					if string.sub(entry.path, 1, #prefix) == prefix then
						targets[entry.path] = true
					end
				end
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
			local fromContent = hit == nil
				and contentShoulders()
				and mountedRootPath ~= nil
				and string.sub(path, 1, #mountedRootPath + 9) == mountedRootPath .. "/Content/"
			if hit == nil and not fromContent then
				return false
			end
			local index = indexOf(selectionModel.read(selection)) or indexOf(hit)
			if index == nil then
				return false
			end
			local tabs = visibleTabs:peek()
			local next = math.clamp(index + (if direction < 0 then -1 else 1), 1, #tabs)
			if next == index then
				return true -- consumed: the clamp is the answer, not a fall-through
			end
			selection:set(tabs[next].id)
			if fromContent then
				pendingNavigation, pendingPlacement, navigationAttempts = "content", placement:peek(), 0
			end
			if spec.onChange ~= nil then
				spec.onChange(tabs[next].id)
			end
			return true
		end,
	})

	local api = {}
	function api.moveTab(tabId, position)
		assert(spec.customization, "UI.TabView.moveTab requires customization")
		assert(
			type(position) == "number" and position == math.floor(position),
			"UI.TabView.moveTab position must be an integer"
		)
		if not seen[tabId] then
			return false
		end
		local order = {}
		for _, tab in visibleTabs:peek() do
			if tab.id ~= tabId then
				table.insert(order, tab.id)
			end
		end
		table.insert(order, math.clamp(position, 1, #order + 1), tabId)
		local state = selectionModel.read(spec.customization)
		spec.customization:set({ order = order, hidden = table.clone(state.hidden or {}) })
		return true
	end
	function api.setTabHidden(tabId, hidden)
		assert(spec.customization, "UI.TabView.setTabHidden requires customization")
		assert(type(hidden) == "boolean", "UI.TabView.setTabHidden requires boolean")
		if not seen[tabId] then
			return false
		end
		for _, tab in spec.tabs do
			if tab.id == tabId and tab.required and hidden then
				return false
			end
		end
		local list = visibleTabs:peek()
		if hidden and #list == 1 and list[1].id == tabId then
			return false
		end
		local state = selectionModel.read(spec.customization)
		local out = {}
		for _, id in state.hidden or {} do
			if id ~= tabId then
				table.insert(out, id)
			end
		end
		if hidden then
			table.insert(out, tabId)
		end
		spec.customization:set({ order = table.clone(state.order or {}), hidden = out })
		return true
	end

	api.blueprint = built
	-- the placement this TabView resolved, published so a screen that has its own
	-- chrome to place (a search field that rides the bar, a wordmark that only
	-- belongs in the rail) reads ONE answer rather than re-deriving the policy
	api.placement = placement
	api.expandSidebar = function()
		if adaptable then
			setSidebar(true)
		end
	end
	api.collapseSidebar = function()
		if adaptable then
			setSidebar(false)
		end
	end

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
		local current = selectionModel.read(selection)
		local label: string? = nil
		local index = indexOf(current)
		for _, tab in spec.tabs do
			if tab.id == current then
				local raw = tab.label or tab.id
				label = tostring(selectionModel.read(raw))
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
			visibleTabs = (function()
				local out = {}
				for _, tab in visibleTabs:peek() do
					table.insert(out, tab.id)
				end
				return out
			end)(),
			selectedId = current,
			selectedLabel = label,
			selectedIndex = index,
			-- WHAT WAS ASKED FOR beside WHAT ANSWERED, the pairing every adaptive
			-- control here already reports. `placementSource` is the nesting rule
			-- made observable: "nested" means this TabView did not claim the
			-- app-level home, which is the first thing a report of two bars wants.
			requestedPlacement = requestedPlacement,
			placement = placement:peek(),
			placementSource = placementSource,
			nested = nested,
			sizing = sizing:peek(),
			axis = stripAxis:peek(),
			-- the strip is a picker, so its whole state is already reported by a
			-- dump that exists; nesting it keeps ONE description of a segment row
			strip = strip.dump(),

			mountedTabs = live,
			contentMounts = mountCount,
			contentEvictions = evictions,
			-- how many times a selection change actually MOVED the strip's
			-- scroller. Zero on a `fill` band is correct, not a failure.
			reveals = reveals,

			accessories = { declared = declaredSlots, mounted = accessoryMounted() },
			semanticText = `Tabs: {label or "none"} ({index or 0} of {#spec.tabs}) in the {placement:peek()}`,
		}
	end

	function api.dispose()
		owner.dispose()
	end

	return api
end

function tab_view.build(Facet, core, spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
return tab_view

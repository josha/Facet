--!strict
--[[ NavBar — the shared shape behind FOUR hand-built back+title bars this
	construct replaces (registry item 13; task-g6-report.md's item-13
	assessment named the four verbatim, with file:line pointers, and
	established the reason a `TabView` accessory slot cannot host them: every
	one is a PRESENTED OR COMPACT-OPEN DETAIL SURFACE'S OWN CHROME — three sit
	at the top of a modal, one is a header inside a compact screen's content —
	never a tab strip's, so a slot keyed to `adaptive.navPlacement` and
	invoked only from `UI.TabView`'s own home branches structurally cannot
	reach any of them.

	WHAT THE FOUR ACTUALLY SHARE, verbatim from that assessment: "(a) a
	leading Back bound to the surface stack's own verb, (b) a title that
	truncates into its disclosure rather than widening its pane, and (c)
	optional trailing actions." NOTHING ELSE — one site's Back verb reaches an
	app-level modal-stack wrapper, another an app router; one has no title at
	all; two of the four hand-typed a `<` glyph inside a circle rather than
	the framework's own `chevron.leading` icon. So this stays a PURE blueprint
	assembly, never touching a presenter or a handle: every one of the four
	sites already decided FOR ITSELF whether a Back verb exists and what it
	does when pressed (one bookkeeps a `retired`-scope list and app state
	alongside the presenter's own dismiss; none can have that decision made
	for them). `onBack` is that decision, handed over as a plain callback —
	`nil` means "nothing to go back to", which is refuse-don't-guess applied
	the only way this construct honestly can: it never invents a verb the
	caller did not give it.

	HOME. `src/present/*` (task-g6-report.md's own recommendation: "its real
	companion is registry item 12's sibling... not this gap" — meaning NOT
	`UI.TabView` — "a presenter-side surface-chrome seam" is the shape asked
	for, and this file is present/-scoped exactly the way `catchers.luau` and
	`modal_zones.luau` are: pure, stateless, holding no presenter reference of
	its own).

	WHAT MIGRATING THE FOUR SITES CHANGES, on the record. Two of the four already
	drew `compactLabel = { icon = "chevron.leading" }`; the other two drew a
	circle-shaped Button with a literal `"<"` Text child. This construct
	standardizes on the framework's own chevron icon (the semantic, themeable,
	non-hand-typed vocabulary) for all four — a deliberate, disclosed visual
	harmonization, not an oversight. ]]

local Compose = require("../vendor/compose/core")
local blueprintLib = require("../blueprint")
local specGuard = require("../spec_guard")
local contribution = require("../input/contribution")
local themeSnapshot = require("../themes/snapshot")
local surfaceEnv = require("../env/surface_env")

local navBar = {}

export type NavBarSpec = {
	id: string?,
	-- nil = "nothing to go back to": no Back button renders. A Button always
	-- needs a label (a11y), so `backLabel` travels with it — each of the four
	-- migrated sites already owns its own localized "Back" string (this
	-- construct has no i18n system of its own to invent one from).
	onBack: (() -> ())?,
	backLabel: string?,
	-- nil = no Title node (one of the four sites has none — its title lives
	-- inside the scrolled body instead). May be a Readable<string>, exactly
	-- like every other Facet text prop.
	title: any?,
	titleSize: string?, -- default "title"
	-- the exact dim each migrated site already computed for its own Title
	-- (nil leaves Title unbounded/hugging, matching the two sites that never
	-- set one); this construct invents no new default width policy
	titleWidth: any?,
	-- placed after the spacer, in order; nil/empty = none (two of the four
	-- sites have no trailing content at all)
	trailing: { any }?,
	-- THE SLOT FORM (opt-in; either key selects it): `leading` follows Back,
	-- `center` replaces the default title and gets the remaining width
	leading: any?,
	center: any?,
	gap: any?,
	padding: any?,
}

local NAV_BAR_KEYS: { [string]: boolean } = {
	id = true,
	onBack = true,
	backLabel = true,
	title = true,
	titleSize = true,
	titleWidth = true,
	trailing = true,
	leading = true,
	center = true,
	gap = true,
	padding = true,
}

-- the center's floor before the trailing content gives way to a second row
local CENTER_FLOOR = "controls.popup.panelWidth"

local function backButton(UI: any, spec: NavBarSpec): any
	return UI.Button({
		id = "Back",
		label = spec.backLabel,
		-- the chevron is what paints; the label is the full-value path behind it
		disclose = true,
		compactLabel = { icon = "chevron.leading", prefer = true },
		onActivate = spec.onBack,
	})
end

--[[ THE SLOT FORM. Back, then `leading`, then the center (the caller's
	`center`, or the default one-line title) filling what is left, then the
	trailing content. When the measured sides leave the center under its floor,
	the trailing content moves to a second row while Back, leading and the
	center stay first — an AXIS change on one AdaptiveStack, so no slot is ever
	rebuilt and a focused search field in the center keeps its state. Optional
	trailing controls degrade through their own compactLabel first. ]]
local function slotted(UI: any, spec: NavBarSpec, trailing: { any }, metricsNow: (() -> any)?): any
	local primary: { any } = {}
	if spec.onBack ~= nil then
		table.insert(primary, backButton(UI, spec))
	end
	if spec.leading ~= nil then
		table.insert(
			primary,
			UI.HStack({ id = "Leading", gap = spec.gap or "s", align = "center", children = { spec.leading } })
		)
	end
	local center = spec.center
	if center == nil and spec.title ~= nil then
		center = UI.Text({
			id = "Title",
			text = spec.title,
			textSize = spec.titleSize or "title",
			lineLimit = 1,
			disclose = true,
			width = UI.fill(),
		})
	end
	table.insert(
		primary,
		UI.HStack({
			id = "Center",
			width = UI.fill(),
			align = "center",
			children = if center ~= nil then { center } else {},
		})
	)
	local axis = Compose.cell("x")
	local children: { any } = {
		UI.HStack({ id = "Primary", width = UI.fill(), gap = spec.gap or "s", align = "center", children = primary }),
	}
	if #trailing > 0 then
		table.insert(
			children,
			UI.HStack({ id = "Trailing", gap = spec.gap or "s", align = "center", children = trailing })
		)
	end
	local bar = UI.AdaptiveStack({
		id = spec.id or "NavBar",
		axis = axis,
		gap = spec.gap or "s",
		align = "center",
		padding = spec.padding,
		width = UI.fill(),
		children = children,
	})
	if #trailing == 0 then
		return bar
	end
	return contribution.attach(bar, {
		syncGeometry = function(rectOf: any, node: any?)
			if node == nil then
				return
			end
			local box = rectOf(node.path)
			local sides = rectOf(`{node.path}/Trailing`)
			local main = rectOf(`{node.path}/Primary`)
			local centerBox = rectOf(`{node.path}/Primary/Center`)
			if
				type(box) ~= "table"
				or type(sides) ~= "table"
				or type(main) ~= "table"
				or type(centerBox) ~= "table"
			then
				return
			end
			local metrics = if metricsNow ~= nil then metricsNow() else themeSnapshot.neutral()
			local floor = themeSnapshot.resolveNumber(metrics, CENTER_FLOOR) or 360
			local gap = themeSnapshot.resolveNumber(metrics, spec.gap or "s") or 8
			-- the width the center would get beside the trailing content
			local fixed = main.w - centerBox.w
			local beside = box.w - fixed - sides.w - gap
			local want = if beside >= math.min(floor, box.w - fixed) then "x" else "y"
			if axis:peek() ~= want then
				axis:set(want)
			end
		end,
	})
end

--[[ build(spec) -> Blueprint. Pure: no core, no scope, no presenter — a
	plain HStack the caller places wherever its own layout already put the
	hand-rolled version (pinned above a ScrollView, inside a compact-only
	`UI.When`, scrolling with the body — every placement the four sites used
	stays exactly where it was; only the bar's own children are shared code
	now). ]]
-- `constructors` is the application's `app.controls` (or a control library's
-- internal UI); `app.controls.navBar(spec)` is the same call.
function navBar.build(spec: NavBarSpec, constructors: any?): any
	if constructors ~= nil and rawget(constructors, "navBar") ~= nil then
		return constructors.navBar(spec)
	end
	if constructors == nil and Compose.currentOwner() ~= nil then
		error(
			"Facet.navBar: inside a component, build the bar from the application's controls — "
				.. "`app.controls.navBar(spec)` or `Facet.navBar(spec, app.controls)`",
			0
		)
	end
	local UI = constructors or blueprintLib
	specGuard.assertKnownKeys("Facet.navBar", spec, NAV_BAR_KEYS, "spec")
	if spec.leading ~= nil or spec.center ~= nil then
		return slotted(UI, spec, spec.trailing or {})
	end
	local children: { any } = {}
	if spec.onBack ~= nil then
		table.insert(
			children,
			UI.Button({
				id = "Back",
				label = spec.backLabel,
				-- `prefer = true`: ALWAYS the chevron, never a degrade candidate.
				-- A nav-bar Back button is icon-only by platform convention on
				-- every one of the four migrated sites — two already drew it
				-- that way; the other two drew a FIXED circle+glyph that could
				-- never grow a text label at all. Without `prefer`, the ladder's
				-- default "full label when it fits" rung is live, and the
				-- 1.4x-pseudo-locale + largest-text-preference corpus sweep
				-- measured it actually winning at `p3_sipworks/book.luau`'s
				-- TopBar — a 7px main-axis overflow no site had before this
				-- construct existed (tests/overflow_sweep.spec.luau).
				compactLabel = { icon = "chevron.leading", prefer = true },
				onActivate = spec.onBack,
			})
		)
	end
	if spec.title ~= nil then
		table.insert(
			children,
			UI.Text({
				id = "Title",
				text = spec.title,
				textSize = spec.titleSize or "title",
				lineLimit = 1,
				disclose = true,
				width = spec.titleWidth,
			})
		)
	end
	table.insert(children, UI.Spacer({ id = "Push" }))
	if spec.trailing ~= nil then
		for _, node in spec.trailing do
			table.insert(children, node)
		end
	end
	return UI.HStack({
		id = spec.id or "NavBar",
		gap = spec.gap or "s",
		align = "center",
		padding = spec.padding,
		width = UI.fill(),
		children = children,
	})
end

--[[ UI.NavBar — the typed, named control: ALWAYS the slot form, and its
	`trailing` is ONE blueprint (a cluster is an HStack you author). ]]
local CONTROL_KEYS: { [string]: boolean } = table.clone(NAV_BAR_KEYS)
CONTROL_KEYS.titleWidth = nil
function navBar.buildControl(Facet: any, core: any, spec: any): any
	specGuard.assertKnownKeys("UI.NavBar", spec, CONTROL_KEYS, "spec")
	if spec.trailing ~= nil and (type(spec.trailing) ~= "table" or type(spec.trailing.class) ~= "string") then
		error("Facet UI.NavBar: `trailing` is ONE blueprint; put a cluster in an HStack.", 0)
	end
	for _, key in { "leading", "center" } do
		local slot = spec[key]
		if slot ~= nil and (type(slot) ~= "table" or type(slot.class) ~= "string") then
			error(`Facet UI.NavBar: \`{key}\` is a blueprint.`, 0)
		end
	end
	local env = surfaceEnv.find(core)
	local blueprint = slotted(Facet.UI, spec, if spec.trailing ~= nil then { spec.trailing } else {}, function()
		return if env ~= nil then env:get("themeMetrics"):peek() else themeSnapshot.neutral()
	end)
	return {
		blueprint = blueprint,
		dump = function()
			return {
				schema = "facet-navbar-dump/1",
				id = spec.id or "NavBar",
				back = spec.onBack ~= nil,
				leading = spec.leading ~= nil,
				center = if spec.center ~= nil then "custom" elseif spec.title ~= nil then "title" else "none",
				trailing = spec.trailing ~= nil,
			}
		end,
	}
end

return navBar

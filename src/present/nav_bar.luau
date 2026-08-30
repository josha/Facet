--!strict
--[[ NavBar — the shared shape behind FOUR hand-built back+title bars this
	construct replaces (registry item 13; task-g6-report.md's item-13
	assessment named the four verbatim, with file:line pointers, and
	established the reason a `TabView` accessory slot cannot host them: every
	one is a PRESENTED OR COMPACT-OPEN DETAIL SURFACE'S OWN CHROME — three sit
	at the top of a modal, one is a header inside a compact screen's content —
	never a tab strip's, so a slot keyed to `adaptive.navPlacement` and
	invoked only from `newTabView`'s own home branches structurally cannot
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
	`newTabView` — "a presenter-side surface-chrome seam" is the shape asked
	for, and this file is present/-scoped exactly the way `catchers.luau` and
	`modal_zones.luau` are: pure, stateless, holding no presenter reference of
	its own).

	WHAT MIGRATING THE FOUR SITES CHANGES, on the record. Two of the four already
	drew `compactLabel = { icon = "chevron.leading" }`; the other two drew a
	circle-shaped Button with a literal `"<"` Text child. This construct
	standardizes on the framework's own chevron icon (the semantic, themeable,
	non-hand-typed vocabulary) for all four — a deliberate, disclosed visual
	harmonization, not an oversight. ]]

local blueprintLib = require("../blueprint")
local specGuard = require("../spec_guard")

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
	gap = true,
	padding = true,
}

--[[ build(spec) -> Blueprint. Pure: no core, no scope, no presenter — a
	plain HStack the caller places wherever its own layout already put the
	hand-rolled version (pinned above a ScrollView, inside a compact-only
	`UI.When`, scrolling with the body — every placement the four sites used
	stays exactly where it was; only the bar's own children are shared code
	now). ]]
function navBar.build(spec: NavBarSpec): any
	specGuard.assertKnownKeys("Facet.navBar", spec, NAV_BAR_KEYS, "spec")
	local children: { any } = {}
	if spec.onBack ~= nil then
		table.insert(
			children,
			blueprintLib.Button({
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
			blueprintLib.Text({
				id = "Title",
				text = spec.title,
				textSize = spec.titleSize or "title",
				lineLimit = 1,
				disclose = true,
				width = spec.titleWidth,
			})
		)
	end
	table.insert(children, blueprintLib.Spacer({ id = "Push" }))
	if spec.trailing ~= nil then
		for _, node in spec.trailing do
			table.insert(children, node)
		end
	end
	return blueprintLib.HStack({
		id = spec.id or "NavBar",
		gap = spec.gap or "s",
		align = "center",
		padding = spec.padding,
		width = blueprintLib.fill(),
		children = children,
	})
end

return navBar

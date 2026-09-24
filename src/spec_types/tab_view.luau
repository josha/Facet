--!strict
-- The `tab_view` control's types, apart from its implementation: reading a type must
-- not load the control.
local publicCore = require("../core/contract")
local publicBlueprint = require("../blueprint")
local publicEnv = require("../env/environment")
local adaptive = require("../layout/adaptive")
local statusIndicator = require("./status_indicator")
export type Tab = {
	id: string,
	label: publicBlueprint.Bound<string>?, -- string | Readable<string>; defaults to `id`
	icon: string?, -- SEMANTIC icon name, never an asset id
	required: boolean?,
	section: string?,
	badge: publicBlueprint.Bound<string | number>?, -- string | number | Readable of either — the count seal
	-- a StatusIndicator spec painted in this tab's segment (construction-only table)
	indicator: statusIndicator.Spec?,
	-- false leaves the tab in the strip but refuses its selection on every input class
	enabled: publicBlueprint.Bound<boolean>?,
	content: (tabScope: publicCore.Owner) -> publicBlueprint.Blueprint,
}
export type Accessories = {
	head: ((placement: string, scope: publicCore.Owner) -> publicBlueprint.Blueprint?)?,
	foot: ((placement: string, scope: publicCore.Owner) -> publicBlueprint.Blueprint?)?,
	trailing: ((placement: string, scope: publicCore.Owner) -> publicBlueprint.Blueprint?)?,
	aboveBar: ((placement: string, scope: publicCore.Owner) -> publicBlueprint.Blueprint?)?,
}
export type StringCell = publicCore.Cell<string>
export type Spec<V = StringCell> = {
	id: string?,
	selection: V, -- the caller's writable cell of a tab id (required)
	tabs: { Tab },
	sections: { { id: string, label: string } }?,
	customization: publicCore.Cell<{ order: { string }, hidden: { string } }>?, -- caller-owned {order: {string}, hidden: {string}} signal
	-- chrome beside the tabs, homed by the placement (see the header). A slot no
	-- reachable placement can host is an authoring mistake and refuses.
	accessories: Accessories?,
	-- the SIDEBAR RAIL's width dim; content-sized by default. A rail states its
	-- band and lets the labels adapt inside it — a 1.4x locale at the largest text
	-- preference otherwise makes the longest tab name the whole rail. Hosted by
	-- `sidebar` alone, and refused for a placement that can never have one.
	railWidth: publicBlueprint.Bound<publicBlueprint.Dim>?,
	-- the ENTER transition each content branch carries — the framework's own
	-- `UI.When` transition table, passed through. The strip is never evicted, so
	-- it is never animated by this.
	transition: publicBlueprint.TransitionSpec?,
	-- "automatic" (default) | "bottomBar" | "bottomBarCompact" | "topBar" | "sidebar".
	-- "automatic" reads `adaptive.navPlacement` — unless this TabView is NESTED,
	-- which never claims the app-level answer (see the header).
	placement: string?,
	style: string?, -- automatic | sidebarAdaptable | collapsible
	sidebarPreference: publicBlueprint.Bound<string>?, -- automatic | sidebar | topBar, or Readable; nearby adaptable home
	restoreScroll: boolean?,
	shoulderNavigation: publicBlueprint.Bound<string>?, -- strip (default) | content, or readable policy
	restoreFocus: boolean?, -- default true; bounded path bookmarks for each tab
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
	textSize: publicBlueprint.Bound<number | string>?,
	conditions: any?, -- the table `adaptive.conditions(env)` returns
	env: publicEnv.Env?, -- an environment, when `conditions` was not built by the caller
	enabled: publicBlueprint.Bound<boolean>?,
	onChange: ((id: string) -> ())?,
}
return nil

--!strict
-- The `menu` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local coreContract = require("../core/contract")
export type Item = {
	checked: coreContract.Cell<boolean>?,
	selected: any?, -- Signal of the caller's arbitrary identity type, paired with value
	value: any?, -- same identity type as selected; boolean for checked callbacks
	description: (string | coreContract.Readable<string>)?,
	dismiss: boolean?,
	onChange: ((any) -> ())?,
	id: string?,
	label: string?,
	icon: string?, -- semantic icon NAME, never an asset id
	role: string?, -- "default" (the fallback) | "destructive"
	enabled: any?, -- boolean | Readable<boolean>
	onSelect: (() -> ())?, -- an ACTION item
	children: { Item }?, -- a SUBMENU item
	divider: boolean?, -- a rule between two groups
}
export type Spec = {
	id: string?,
	trigger: blueprint.Blueprint?, -- custom trigger; omit when using label
	label: string?, -- standard accessible menu button
	items: { Item }, -- required, non-empty
	triggers: { string }?, -- which gestures open it; default all five
	-- string | Readable<string> (automatic | menu | sheet; gap 20, framework-
	-- gaps-phase2). Was construction-time only; a forced (non-"automatic")
	-- value now rides the SAME hot-switch machinery `sizeClass`/
	-- `interactionClasses` already drive an open menu through.
	presentation: any?,
	sizeClass: blueprint.Bound<string>?, -- string | Readable<string>
	interactionClasses: any?, -- table | Readable<table>
	--[[ the environment both facts above come from. Omitted, an
		automatic presentation finds the one this control's own core published, and
		refuses to construct when there is none. ]]
	env: any?,
	--[[ THE SHEET'S BACK ROW LABEL (review finding I1, task PANEL fix round 1),
		following `present/nav_bar.luau`'s own `NavBarSpec.backLabel: string?`
		shape exactly — same optional typing, same reason: "a Button always needs
		a label (a11y)... this construct has no i18n system of its own to invent
		one from." UNLIKE `nav_bar` (which has no built-in Back verb at all, so
		omitting `backLabel` there means no text and an icon-only button),
		`UI.Menu` invented its own Back row before this field existed, so omitting
		this stays WORKING rather than blank: it falls back to the literal English
		"Back" `buildPanel` already drew. That fallback is an i18n gap, not a
		feature — a caller shipping `sheet`-reachable submenus (any compact
		width, the framework default since this round) to a localized audience
		must set this, exactly as `docs/reference/api.md` now says. ]]
	backLabel: string?,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}
return nil

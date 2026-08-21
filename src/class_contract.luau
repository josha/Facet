--!strict
--[[ PRIMITIVE-CLASS CONTRACT REGISTRY (design §10.2).

	Every production v1 CLASS declares its semantic roles here: focus role,
	semantic actions, effective hit target, lifecycle ownership, async policy.
	Prop->dirty maps live in `blueprint.luau`; property authorities in
	`render/authority.luau`.

	IT LIVED AT `src/controls/contract.luau` AND WAS NEITHER (moved 0.10.0). Its rows are Screen, VStack, Text, Grip, ScrollView — the
	PRIMITIVES a composite control is built out of, not the composites — so its
	old name misled every reader who opened it expecting Table and Slider. And
	`src/render/layout_node.luau` required it, which made `render/` depend on
	`controls/` and inverted the layering the architecture guide teaches
	(composites are built ON TOP OF primitives, never underneath them).

	WHY A ROOT LEAF RATHER THAN `render/class_contract.luau`, CORRECTED. The
	first version of this header argued from `src/layout/solver.luau`, and that
	was wrong: solver has never required this module — its only mention is the
	comment at `solver.luau:220`, and the R5 review caught the misreading. The
	true reason is the one the REQUIRE LIST gives, which is stronger. The
	consumers are `src/blueprint.luau`, `src/render/layout_node.luau` and five
	`src/controls/*` modules, so filing this under `render/` would have made the
	AUTHORING layer and five composite controls depend on the RENDER layer — the
	same inversion pointing the other way, and a worse one, because `blueprint`
	is structurally above `render` rather than beside it.

	This file requires NOTHING — the `src/spec_guard.luau` shape — so every layer
	may depend on it and no layer is depending on another by doing so. That is
	also why no CONTEST was needed: the brief said "or the location that makes the
	layering true", so a root leaf was authorised from the start.

	minHitSize is ENFORCED: after every
	solve the renderer compares each declared class's solved rect against this
	floor and pushes an expanded HIT rect through the adapter's `setHitRect` seam,
	which the engine adapter realises as a transparent expander behind the
	control. The VISUAL rect is deliberately untouched — flooring the painted size
	would silently rewrite shipped design — so declaring a floor here is all a new
	control has to do.
]]

local contract = {}

export type ControlContract = {
	focusRole: string, -- "none" | "focusable"
	actions: { string }, -- semantic actions the control consumes
	minHitSize: number?, -- effective target floor (Facet px units)
	accessibility: string, -- readable summary of behavior
}

local CONTROLS: { [string]: ControlContract } = {
	Screen = { focusRole = "none", actions = {}, accessibility = "container; presenter owns inset policy" },
	VStack = { focusRole = "none", actions = {}, accessibility = "layout container" },
	HStack = { focusRole = "none", actions = {}, accessibility = "layout container" },
	ZStack = { focusRole = "none", actions = {}, accessibility = "overlay container" },
	ScrollView = { focusRole = "none", actions = { "Scroll" }, accessibility = "scrollable region; overflow declared" },
	Spacer = { focusRole = "none", actions = {}, accessibility = "layout spacing only" },
	Box = { focusRole = "none", actions = {}, accessibility = "decorative/custom rect" },
	Text = { focusRole = "none", actions = {}, accessibility = "static or bound text; wraps; never truncates silently" },
	Image = { focusRole = "none", actions = {}, accessibility = "decorative unless labeled" },
	-- The strict-authoring milestone completed the registry:
	-- every public UI.* constructor now declares a contract. Structural and
	-- layout nodes are legitimately non-interactive, but they must not be
	-- INVISIBLE to conformance — an unlisted primitive is a primitive nothing
	-- checks. Grip in particular was a focusable, pointer-handling control that
	-- no four-input rule could see.
	Anchor = { focusRole = "none", actions = {}, accessibility = "free-position overlay container" },
	Grid = { focusRole = "none", actions = {}, accessibility = "row-major uniform grid container" },
	GridRow = {
		focusRole = "none",
		actions = {},
		accessibility = "one row of a ROW grid (§2.2): its cells take the columns the parent Grid "
			.. "derived from every row, so column n is the same column in every row. Carries no focus "
			.. "semantics of its own — the cells keep theirs, in declaration order",
	},
	AdaptiveStack = {
		focusRole = "none",
		actions = {},
		accessibility = "stack container whose axis is a reactive prop; an axis flip re-solves in "
			.. "place so children keep their identity, focus, and state (A-AL2)",
	},
	ViewThatFits = {
		focusRole = "none",
		actions = {},
		accessibility = "chooses among candidate layouts by MEASURING them against the space it "
			.. "received; losing candidates stay mounted but are hidden and excluded from focus "
			.. "order, so navigation never lands on an invisible control (A-AL1)",
	},
	Composition = {
		focusRole = "none",
		actions = {},
		accessibility = "screen-level container that resolves an ARRANGEMENT from ranked regions and "
			.. "the box it received, on BOTH axes; regions that stepped out or dropped keep their mount "
			.. "but are hidden and excluded from focus order, and focus order is the declaration's own "
			.. "and therefore identical in every arrangement (ADR-0023)",
	},
	Region = {
		focusRole = "none",
		actions = {},
		accessibility = "one ranked thing a Composition has to say; its children are its forms, richest "
			.. "first, and exactly one of them is shown — the others are hidden and unreachable (ADR-0023)",
	},
	Divider = {
		focusRole = "none",
		actions = {},
		accessibility = "decorative hairline; infers its orientation from the enclosing stack so one "
			.. "declaration reads correctly on both axes (A-LV3)",
	},
	Path = {
		focusRole = "none",
		actions = {},
		accessibility = "decorative stroked path (Path2D); color via style role",
	},
	Stage = {
		focusRole = "none",
		actions = {},
		accessibility = "engine-content box (ViewportFrame): reserves a rect for a scene the ENGINE draws "
			.. "and owns its camera/lighting/content root behind controller.stageHost. It owns no input — "
			.. "a stage is a picture, and interaction is composed AROUND it (a Grip sibling, a Button "
			.. "overlay), so the surrounding controls keep the four-input story",
	},
	Foreign = {
		focusRole = "none",
		actions = {},
		accessibility = "a box for a GuiObject Facet does not wrap (ADR-0034): the framework reserves and "
			.. "CLIPS the rect, the caller adopts an instance into it through controller.foreignHost, and "
			.. "Facet writes exactly one property on that instance (its Parent) and nothing else. It owns no "
			.. "input and takes no focus stop — the content is outside the focus graph by construction, since "
			.. "the framework has never seen it — so a consumer who needs a focus stop composes one AROUND the "
			.. "box (a Button overlay, a focusable Grip sibling), exactly as a Stage does. The content's own "
			.. "engine input still works; Facet's Tab/gamepad traversal simply cannot stop on it",
	},
	Grip = {
		focusRole = "focusable", -- OPT-IN: unfocusable unless focusable = true
		actions = { "Adjust" },
		minHitSize = 44,
		accessibility = "non-button pointer zone with capture-based drag routing; "
			.. "opt-in focusable so gamepad/keyboard reach it, where the focus-gated Adjust verb "
			.. "replaces the drag (a virtual cursor cannot see a MouseIcon hint)",
	},
	-- structural regions (design §5.4): mount-layer control flow. They own no
	-- rect, no paint, and no input surface — their children are spliced into the
	-- parent's layout flow — but they ARE public constructors, so they declare
	-- a contract like everything else.
	When = { focusRole = "none", actions = {}, accessibility = "structural region; mounts/unmounts a branch" },
	ForEach = { focusRole = "none", actions = {}, accessibility = "keyed structural region; add/remove/move only" },
	ErrorBoundary = {
		focusRole = "none",
		actions = {},
		accessibility = "structural region; swaps its subtree to a fallback view when a factory throws",
	},
	Button = {
		focusRole = "focusable",
		actions = { "Activate" },
		minHitSize = 44,
		accessibility = "activates on Activate action from any bound input; takes optional custom content "
			.. "inside its ONE activation surface (a focusable in that content is a build error); semantic "
			.. "role default|cancel|destructive rides a style tag; enabled=false removes it from focus "
			.. "order AND refuses activation on every input class",
	},
	Toggle = {
		focusRole = "focusable",
		actions = { "Activate" },
		minHitSize = 44,
		accessibility = "Activate flips value; state changes are semantic (value binding), not visual-only",
	},
	-- TextField (§17 Phase 5 expansion): the text-entry leaf. Activate enters
	-- text-entry mode — a high-priority sinking InputContext so keystrokes
	-- become text, not navigation, until commit/cancel/focus-loss. Disabled
	-- fields opt out of focus. Value/edits are semantic (owner-held signal +
	-- setTextInputHandlers seam), never visual-only.
	TextField = {
		focusRole = "focusable",
		actions = { "Activate" },
		minHitSize = 44,
		accessibility = "Activate enters text-entry mode (sinking context: typing/arrows do not navigate); "
			.. "commit on Enter/focus-loss, Cancel (ButtonB / engine-reported Escape) reverts; disabled excluded from focus",
	},
}

-- WHAT `enabled` MEANS, decided once (Step 5.5 cleanup ledger C-01). Every
-- composite control takes the same optional `spec.enabled`, and the reading is a
-- policy, not arithmetic: absent means enabled, a Readable is asked, and anything
-- else is enabled unless it is literally `false`. Five controls each carried their
-- own copy of that policy and a sixth spelling had already drifted into
-- `stepper`'s bound memos — which is the whole argument for one owner. It lives
-- here because this file already is "the remaining declared contract" a control
-- owes, and `enabled` is the most load-bearing entry in it: it gates activation on
-- EVERY input class and removes the control from focus order.
--
-- Two spellings because there are two callers, and the difference is load-bearing:
--   enabledNow(e)      a one-shot read inside a handler — must NOT subscribe
--   enabledIn(use, e)  inside a memo/effect — MUST subscribe, or a control stays
--                      interactive after its own `enabled` signal flips
function contract.enabledNow(enabled: any): boolean
	if enabled == nil then
		return true
	end
	if type(enabled) == "table" then
		return (enabled :: any):get() ~= false
	end
	return enabled ~= false
end

function contract.enabledIn(use: (any) -> any, enabled: any): boolean
	if enabled == nil then
		return true
	end
	if type(enabled) == "table" then
		return use(enabled) ~= false
	end
	return enabled ~= false
end

--[[ DOES THIS CLASS CONTRIBUTE A FOCUS STOP OR A SEMANTIC ACTION? (wave REVEAL).

	The `expand` affordance has to answer one question about a compact form — "do
	the player's existing gestures on it already mean something?" — because the
	answer decides which gesture opens the expansion. A form that means nothing can
	BE the target; a form that means something keeps its meanings and takes a
	chevron beside it.

	IT IS READ OFF THE REGISTRY ABOVE RATHER THAN OFF A LIST OF CLASS NAMES, and
	that is the whole point: the day a new primitive declares a focus role or an
	action, the expand mechanism learns it in the same commit that declares it,
	instead of in the commit after the bug. `ScrollView` is the case a name list
	always missed — no focus stop, one action (`Scroll`), and overloading a
	scrollable compact form with a tap-to-expand is exactly the collision the
	chevron exists to avoid.

	THE PROP OPT-OUTS ARE NOT CONSULTED HERE, deliberately. `focusable = false` on a
	Button removes a focus STOP and leaves an activation surface standing; `enabled
	= false` is a state, not a shape. Both still mean "the player's tap on this
	thing already has an owner", which is the question being asked. ]]
function contract.isInteractive(class: string): boolean
	local c = CONTROLS[class]
	if c == nil then
		return false
	end
	return c.focusRole == "focusable" or #c.actions > 0
end

function contract.forClass(class: string): ControlContract?
	return CONTROLS[class]
end

function contract.all(): { [string]: ControlContract }
	return CONTROLS
end

return contract

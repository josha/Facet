--!strict
-- Control contract registry (design §10.2): every production v1 control
-- declares its semantic roles here. Prop->dirty maps live in blueprint.luau;
-- property authorities in render/authority.luau; this file carries the
-- remaining declared contract: focus role, semantic actions, effective hit target,
-- lifecycle ownership, and async policy.
--
-- minHitSize is now ENFORCED (B-BTN3, swiftui-parity-next investment 3): after every
-- solve the renderer compares each declared control's solved rect against this floor
-- and pushes an expanded HIT rect through the adapter's `setHitRect` seam, which the
-- engine adapter realises as a transparent expander behind the control. The VISUAL
-- rect is deliberately untouched — flooring the painted size would silently rewrite
-- shipped design — so declaring a floor here is all a new control has to do.

local contract = {}

export type ControlContract = {
	focusRole: string, -- "none" | "focusable"
	actions: { string }, -- semantic actions the control consumes
	minHitSize: number?, -- effective target floor (LuauUI px units)
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
	-- Milestone 0 (swiftui-parity-next investment 1) completed the registry:
	-- every public UI.* constructor now declares a contract. Structural and
	-- layout nodes are legitimately non-interactive, but they must not be
	-- INVISIBLE to conformance — an unlisted primitive is a primitive nothing
	-- checks. Grip in particular was a focusable, pointer-handling control that
	-- no four-input rule could see.
	Anchor = { focusRole = "none", actions = {}, accessibility = "free-position overlay container" },
	Grid = { focusRole = "none", actions = {}, accessibility = "row-major uniform grid container" },
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

function contract.forClass(class: string): ControlContract?
	return CONTROLS[class]
end

function contract.all(): { [string]: ControlContract }
	return CONTROLS
end

return contract

--!strict
-- DisclosureGroup: a labelled header that expands and collapses its content
-- (docs/plans/parity-next.md investment 7; acceptance row B-DSP2).
--
-- The row the plan singles out is FOCUS: "DisclosureGroup with correct focus
-- updates". Collapsing while focus sits inside the content would leave focus on an
-- unmounted node, so the control moves focus back to its own header BEFORE the
-- content unmounts. Expanding leaves focus on the header — the player asked to see
-- the content, not to jump into it.
--
-- Content is mounted through UI.When, so a collapsed group costs nothing: only
-- structural regions may mount or unmount (UI-RUNTIME-002).
--
-- OWNERSHIP: `expanded` is the CALLER's Signal, so the disclosure state survives
-- the control (a settings screen remembers which sections were open).

local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local themePackage = require("../themes/package")
local chrome_slots = require("../tokens/chrome_slots")
local specGuard = require("../spec_guard")

local disclosure_group = {}

export type Spec = {
	id: string?,
	label: string, -- required: the header IS the control
	expanded: any, -- owner-held Signal<boolean>
	content: () -> any, -- () -> Blueprint, mounted only while expanded
	enabled: any?,
	onToggle: ((expanded: boolean) -> ())?,
	-- OPTIONAL (task 12, transitions round). When given, the toggle runs inside
	-- `presenter.withAnimation("dismiss", …)` so every sibling whose position
	-- the flip moves — a section below this one sliding to make or close room —
	-- GLIDES to its new place instead of jumping there. Absent (the common case:
	-- a bare mount with no presenter, or a screen that has not opted in) degrades
	-- to an ordinary instant flip; the caret and the content still animate their
	-- OWN paint either way, off the ambient motion clock `bindMotion` hands over.
	presenter: any?,
}

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local DISCLOSURE_GROUP_KEYS = specGuard.keySet({
	"content",
	"enabled",
	"expanded",
	"id",
	"label",
	"onToggle",
	"presenter",
})

function disclosure_group.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newDisclosureGroup", spec, DISCLOSURE_GROUP_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Disclosure"
	local scope = core:scope("disclosure-" .. tostring(id))
	if type(spec.label) ~= "string" or spec.label == "" then
		error(`Facet newDisclosureGroup('{id}'): \`label\` is required (the header is the control)`, 0)
	end
	local expanded = spec.expanded
	if type(expanded) ~= "table" or (expanded :: any).kind ~= "signal" then
		error(
			`Facet newDisclosureGroup('{id}'): \`expanded\` must be a SETTABLE Signal<boolean> the caller `
				.. `owns (the disclosure state must outlive the control)`,
			0
		)
	end
	if type(spec.content) ~= "function" then
		error(`Facet newDisclosureGroup('{id}'): \`content\` must be a function returning a Blueprint`, 0)
	end
	if spec.presenter ~= nil and type((spec.presenter :: any).withAnimation) ~= "function" then
		error(`Facet newDisclosureGroup('{id}'): \`presenter\` must be a presenter (something with withAnimation)`, 0)
	end

	local headerPath: string? = nil
	local focusGraph: any = nil

	-- the contract's one reading of `enabled` (a one-shot read: never subscribes)
	local function isEnabled(): boolean
		return controlContract.enabledNow(spec.enabled)
	end

	local function toggle(): boolean
		if not isEnabled() then
			return false
		end
		local next_ = not expanded:get()
		if not next_ then
			-- COLLAPSING: pull focus back to the header BEFORE the content unmounts,
			-- or focus is left pointing at a node that is about to disappear
			if focusGraph ~= nil and headerPath ~= nil then
				local focused = focusGraph.focused:get()
				if focused ~= nil and string.sub(focused, 1, #headerPath) ~= headerPath then
					focusGraph.focusOn(headerPath)
				end
			end
		end
		-- THE FLIP ITSELF, optionally inside `withAnimation` (task 12). The focus
		-- hand-back above already ran, so it is never inside the presenter's own
		-- armed transaction — `withAnimation` refuses re-entrancy and a call from
		-- inside an already-open core transaction, and the hand-back's `focusOn`
		-- write must land BEFORE the content unmounts regardless of which branch
		-- runs below.
		local function flip()
			expanded:set(next_)
			if spec.onToggle ~= nil then
				spec.onToggle(next_)
			end
		end
		if spec.presenter ~= nil then
			spec.presenter.withAnimation("dismiss", flip)
		else
			flip()
		end
		return true
	end

	-- THE DISCLOSURE CARET (the proof defect).
	--
	-- The header used to build one string from U+25BE and U+25B8 — the two
	-- GEOMETRIC-SHAPE triangles. They are present in some faces and absent in
	-- others, and sci-fi's Michroma is one of the others: the caret rendered as
	-- TOFU on a live screen while every headless test stayed green, because a
	-- string is a string and no assertion can see a missing glyph.
	--
	-- The characters now come from the framework's semantic-icon table, which is
	-- plain ASCII by construction and asserted to be (`themes.isSafeGlyph`). That
	-- alone made the caret legible in every font a package can name — but it left
	-- the OTHER half of R4 unbuilt: nothing here ever REQUESTED the icon, so a
	-- package's `chevron.down` / `chevron.trailing` art could never paint and the
	-- reference packages' carets were dead declarations (phase-gate verifier F3).
	--
	-- So the caret is now its own node, exactly like the stepper's glyphs: it
	-- draws the ASCII character itself and carries the semantic NAME beside it,
	-- and the adapter paints the theme's picture over the character when the
	-- installed package declares one. A control never names an asset.
	--
	-- ONE GLYPH, NOT TWO REGIONS (task 12, transitions round). The header used
	-- to mount `CaretOpen`/`CaretShut` as a `UI.When` pair — two DIFFERENT
	-- semantic names for the same idea, because a hint is static blueprint
	-- metadata (it has to be — it is read at create time, before any signal
	-- exists on the node) and the ladder had no way to carry one icon name
	-- through two states. That made every flip a MOUNT/UNMOUNT of the whole
	-- caret for what is really just an ANGLE, so the caret is now a single
	-- `chevron.trailing` glyph whose `rotation` (paint-only, presentation
	-- channel — never seen by the solver) springs 0 -> 90 as `expanded` flips,
	-- turning to point down rather than swapping identity. A package's
	-- `chevron.down` art, if it declared any, is no longer requested here.
	--
	-- The header becomes a CONTENT button (B-BTN1): its `label` stays the
	-- semantic label the contract and every assistive reader want, and the
	-- visible text moves into a child so suppressing the CARET's glyph under a
	-- picture cannot take the label with it.
	local CARET = themePackage.iconGlyph("chevron.trailing") or ">"
	-- the caret's aim, in degrees; `bindMotion` below seeds a spring from it the
	-- first time a presenter hands one over, so a control built already-expanded
	-- (or mounted with no presenter at all) starts pointed the right way with no
	-- flight
	local caretAngle = scope:own(core:signal(if expanded:get() then 90 else 0))
	local clock: any, caretMotion: any = nil, nil
	local function aimCaret()
		local target = if expanded:get() then 90 else 0
		if caretMotion ~= nil then
			caretMotion:setTarget(target)
		else
			-- no clock bound yet (a bare mount, or reduced motion's own instant
			-- placement already did the work through the spring) — write directly
			caretAngle:set(target)
		end
	end
	scope:own(core:observe(expanded, aimCaret))

	local root = UI.VStack({
		id = id,
		gap = "xs",
		width = { type = "fill", weight = 1 },
		children = {
			UI.Button({
				id = "Header",
				label = spec.label,
				enabled = spec.enabled,
				selected = expanded,
				gap = "xs",
				width = { type = "fill", weight = 1 },
				height = { type = "minMax", min = "targetSizes.minimum" },
				children = {
					chrome_slots.attachHint(
						UI.Text({ id = "Caret", text = CARET, textSize = "control", rotation = caretAngle }),
						{ icon = "chevron.trailing" }
					),
					UI.Text({
						id = "Label",
						text = spec.label,
						-- the SAME role the renderer gives a Button's own text, so
						-- moving the label into content changes no geometry
						textSize = "control",
						width = { type = "fill", weight = 1 },
					}),
				},
			}),
			-- Fade the content during the caret's close, so removal never reveals
			-- the last fully opaque frame. The region still owns exit and reversal.
			UI.When({
				id = "Content",
				condition = expanded,
				thenView = function()
					return UI.ZStack({
						id = "Fade",
						canvasGroup = true,
						width = { type = "fill", weight = 1 },
						children = { spec.content() },
					})
				end,
				transition = { enter = "fade", class = "dismiss", exitClass = "dismiss" },
			}),
		},
	})

	local built = contribution.attach(root, {
		handleActivate = function(path: string): boolean
			if string.sub(path, -7) == "/Header" then
				headerPath = path
				return toggle()
			end
			return false
		end,
		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and headerPath == nil then
				for _, child in rootNode.children or {} do
					if child.id == "Header" then
						headerPath = child.path
					end
				end
			end
		end,
		-- the focus graph is reached through the presenter's own binding rather than
		-- being passed in by the consumer
		bindController = function(controller: any)
			if controller ~= nil and controller.focusGraph ~= nil then
				focusGraph = controller.focusGraph
			end
		end,
		-- the caret's spring, seeded from whatever `caretAngle` already reads (the
		-- construction-time value, or the last instant write if `expanded` flipped
		-- before a presenter ever bound one) — so binding late never jumps
		bindMotion = function(c)
			clock = c
			if caretMotion == nil then
				caretMotion = scope:own(clock:spring(caretAngle:get(), "dismiss", { eps = 0.01 }))
				scope:own(core:observe(caretMotion, function()
					caretAngle:set(caretMotion:get())
				end))
			end
		end,
	})

	local api = {}
	api.blueprint = built

	-- the presenter hands the focus graph over here (the control must be able to
	-- move focus off content it is about to unmount)
	function api.bindFocus(graph: any)
		focusGraph = graph
	end

	function api.dump()
		return {
			schema = "facet-disclosure-dump/1",
			id = id,
			label = spec.label,
			expanded = expanded:get(),
			headerPath = headerPath,
			semanticText = `{spec.label}: {if expanded:get() then "expanded" else "collapsed"}`,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return disclosure_group

--!strict
--[[ Card — artwork, a title and an optional caption, with a primary action and a
	More menu that reveal on engagement (phase6 P6a, D6).

	THREE SIBLING HIT SURFACES, NEVER NESTED. The body is an image `UI.Button` when
	`onActivate` is given and plain artwork + text when it is not; the primary
	action is an ordinary Button and More is `UI.Menu`'s trigger. The outer card is
	noninteractive, so a press lands on exactly one of them and nothing bubbles.

	ENGAGEMENT is the owned OR of pointer-within (the card root's hover observer),
	focus-within (the graph's focused path under the card), a press held on one of
	its Buttons, its own menu open, the actions entered from a browse stop, and the
	caller's `browseTarget` being the focused path. The menu's own `isOpen` is set
	before its surface is presented, so the portal taking focus never drops the
	reveal. No global listener, no frame loop.

	`reveal = "always"` keeps the action row in the card's own layout.
	`reveal = "automatic"` keeps it visible at rest whenever the session has touch
	and otherwise shows it while engaged. The card root is one hosted envelope: the
	body and, directly below it, the action plate, which is ALWAYS laid out and only
	`hidden` (out of paint, focus and the tap path) at rest. The box never changes,
	and a pointer moving from the body to Play or More never leaves the envelope it
	is observed on. Entry fades in on the container motion class; exit is a cut
	once the pointer has left the envelope. `api.revealExtent.body` is the measured
	envelope height, so a grid sizes its lines from the card.

	BROWSE ENTRY. Inside a `UI.VirtualGrid` the cell's own Hit is the browse stop;
	`api.enterActions()` holds the reveal and traps focus in the actions (the
	contribution `transientScope`), entering at the first eligible action. Cancel
	closes an open menu first (its own surface), then leaves the actions, and the
	trap restores the browse stop. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local contribution = require("../input/contribution")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local themePackage = require("../themes/package")

local card = {}

-- the engaged card's paint-only scale (see THE LIFT below)
card.LIFT = 1.04

local specTypes = require("../spec_types/card")
export type Spec = specTypes.Spec

local KEYS = guard.keySet({
	"browseTarget",
	"caption",
	"enabled",
	"env",
	"id",
	"image",
	"imageAspectRatio",
	"imageFraming",
	"menu",
	"onActivate",
	"primaryAction",
	"reveal",
	"title",
	"width",
})
local PRIMARY_KEYS = guard.keySet({ "busy", "enabled", "icon", "label", "onActivate" })
local MENU_KEYS = guard.keySet({ "items", "label" })
local REVEALS = { automatic = true, always = true }
local DUMP_SCHEMA = "facet-card-dump/1"

local function textish(v: any): boolean
	return type(v) == "string" or selection.isSource(v)
end

local function prefixed(root: string, path: any): boolean
	return type(path) == "string" and (path == root or string.sub(path, 1, #root + 1) == root .. "/")
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.Card", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Card"
	local where = `UI.Card('{id}')`

	-- ===== validation, before anything is allocated =======================
	local function nonempty(key: string, v: any)
		local now = selection.read(v)
		if not textish(v) or type(now) ~= "string" or now == "" then
			error(`Facet {where}: \`{key}\` is required — a nonempty string or a bound string.`, 0)
		end
	end
	nonempty("image", spec.image)
	nonempty("title", spec.title)
	if spec.caption ~= nil and (not textish(spec.caption) or type(selection.read(spec.caption)) ~= "string") then
		error(`Facet {where}: \`caption\` is a string or a bound string.`, 0)
	end
	local reveal = spec.reveal or "automatic"
	if REVEALS[reveal] ~= true then
		error(`Facet {where}: \`reveal\` is automatic | always.`, 0)
	end
	local ratio = spec.imageAspectRatio
	if ratio ~= nil and (type(ratio) ~= "number" or ratio ~= ratio or ratio <= 0 or ratio == math.huge) then
		error(`Facet {where}: \`imageAspectRatio\` is a positive finite number.`, 0)
	end
	for _, key in { "onActivate", "browseTarget" } do
		if (spec :: any)[key] ~= nil and type((spec :: any)[key]) ~= "function" then
			error(`Facet {where}: \`{key}\` is a function.`, 0)
		end
	end
	local primary = spec.primaryAction
	if primary ~= nil then
		if type(primary) ~= "table" then
			error(`Facet {where}: \`primaryAction\` is \{ label, icon?, onActivate, enabled?, busy? }.`, 0)
		end
		guard.assertKnownKeys("UI.Card", primary, PRIMARY_KEYS, "primaryAction")
		if not textish(primary.label) or type(primary.onActivate) ~= "function" then
			error(`Facet {where}: \`primaryAction\` needs a label and an onActivate function.`, 0)
		end
		if primary.icon ~= nil and not (type(primary.icon) == "string" and themePackage.isIconName(primary.icon)) then
			error(`Facet {where}: \`primaryAction.icon\` is a semantic icon name.`, 0)
		end
	end
	local menuSpec = spec.menu
	if menuSpec ~= nil then
		if type(menuSpec) ~= "table" then
			error(`Facet {where}: \`menu\` is \{ items, label? }.`, 0)
		end
		guard.assertKnownKeys("UI.Card", menuSpec, MENU_KEYS, "menu")
		if menuSpec.label ~= nil and (type(menuSpec.label) ~= "string" or menuSpec.label == "") then
			error(`Facet {where}: \`menu.label\` is a nonempty string.`, 0)
		end
	end
	local enabledRead = selection.read(spec.enabled)
	if enabledRead ~= nil and type(enabledRead) ~= "boolean" then
		error(`Facet {where}: \`enabled\` is a boolean or a bound boolean.`, 0)
	end

	-- ===== late content keeps the last legal value =========================
	local diagnostics: { string } = {}
	local function quarantined(key: string, source: any, allowEmpty: boolean): any
		if not selection.isSource(source) then
			return source
		end
		local last: string = selection.read(source)
		local refused = false
		return ownedFormula(owner, function(use)
			local v = selection.read(source, use)
			if type(v) == "string" and (allowEmpty or v ~= "") then
				last, refused = v, false
			elseif not refused then
				refused = true
				local line = `Facet {where}: \`{key}\` {if allowEmpty then "is a string" else "is a nonempty string"}`
					.. " — keeping the last legal value"
				selection.note(diagnostics, line)
			end
			return last
		end)
	end
	local image = quarantined("image", spec.image, false)
	local title = quarantined("title", spec.title, false)
	local caption = if spec.caption ~= nil then quarantined("caption", spec.caption, true) else nil

	local env = if spec.env ~= nil then spec.env else surfaceEnv.find(core)
	local enabled = ownedFormula(owner, function(use)
		return selection.read(spec.enabled, use) ~= false
	end)

	-- ===== engagement ======================================================
	local hovered = Compose.cell(false)
	local focusWithin = Compose.cell(false)
	local pressing = Compose.cell(false)
	local browsing = Compose.cell(false)
	local entered = Compose.cell(false)
	local menuRecord: any = nil
	local press = {
		onPointerDown = function()
			pressing:set(true)
			return nil
		end,
		onPointerUp = function()
			pressing:set(false)
		end,
		onPointerCancel = function()
			pressing:set(false)
		end,
	}
	local touchAtRest = ownedFormula(owner, function(use)
		local classes = if env ~= nil then use(env:get("interactionClasses")) else nil
		-- any touch at all: a finger has no hover, so a hybrid device must not hide them
		return type(classes) == "table" and classes.touch == true
	end)
	local engaged = ownedFormula(owner, function(use)
		return use(hovered)
			or use(focusWithin)
			or use(pressing)
			or use(browsing)
			or use(entered)
			or (menuRecord ~= nil and use(menuRecord.api.isOpen))
	end)
	-- a card with no stop of its own (an informational body and no browse stop to
	-- enter from) shows its actions at rest, or a keyboard could never reach them
	local reachableOnlyThroughActions = spec.onActivate == nil and spec.browseTarget == nil
	local revealed = ownedFormula(owner, function(use)
		return reveal == "always" or reachableOnlyThroughActions or use(touchAtRest) or use(engaged)
	end)

	-- ===== the parts =======================================================
	local buttonLib = require("./button")
	local body: any
	if spec.onActivate ~= nil then
		local onActivate: any = spec.onActivate
		body = buttonLib.build(Facet, core, {
			id = "Body",
			label = title,
			image = image,
			subtitle = caption,
			imageAspectRatio = ratio,
			imageFraming = spec.imageFraming,
			onActivate = function()
				onActivate()
			end,
			onPointerDown = press.onPointerDown,
			onPointerUp = press.onPointerUp,
			onPointerCancel = press.onPointerCancel,
		}).blueprint
	else
		local copy: { any } = {
			UI.aspectRatio(
				UI.Image({
					id = "Artwork",
					image = image,
					imageFraming = spec.imageFraming,
					scaleMode = "crop",
					width = UI.fill(),
				}),
				ratio or 16 / 9
			),
			UI.Text({ id = "Title", text = title, width = UI.fill() }),
		}
		if caption ~= nil then
			table.insert(
				copy,
				UI.Text({ id = "Subtitle", text = caption, textSize = "caption", role = "secondary", width = UI.fill() })
			)
		end
		body = UI.VStack({ id = "Body", width = UI.fill(), padding = "s", gap = "xs", children = copy })
	end

	local actions: { any } = {}
	if primary ~= nil then
		local onPrimary: any = primary.onActivate
		table.insert(
			actions,
			buttonLib.build(Facet, core, {
				id = "Primary",
				label = primary.label,
				icon = primary.icon,
				enabled = primary.enabled,
				busy = primary.busy,
				surface = "accent",
				disclose = true,
				width = UI.fill(),
				onActivate = function()
					onPrimary()
				end,
				onPointerDown = press.onPointerDown,
				onPointerUp = press.onPointerUp,
				onPointerCancel = press.onPointerCancel,
			}).blueprint
		)
	end
	if menuSpec ~= nil then
		menuRecord = require("./menu").build(Facet, core, {
			id = "More",
			trigger = UI.Button({
				id = "More",
				label = menuSpec.label or "More",
				disclose = true,
				compactLabel = { icon = "more", prefer = true },
				onPointerDown = press.onPointerDown,
				onPointerUp = press.onPointerUp,
				onPointerCancel = press.onPointerCancel,
			}),
			items = menuSpec.items,
			env = spec.env,
		})
		owner.own(menuRecord.dispose)
		table.insert(actions, menuRecord.blueprint)
	end
	local hasActions = #actions > 0

	-- the card's measured height (body plus the action plate), so a grid can size
	-- its lines from the card instead of predicting text
	local height = Compose.cell(0)
	local extent = ownedFormula(owner, function(use)
		return { body = use(height) }
	end, function(a: any, b: any)
		return a ~= nil and b ~= nil and a.body == b.body
	end)

	local fade = if reveal == "automatic"
		then Facet.runtime.spring(function(use)
			return if use(revealed) then 1 else 0
		end, { period = 0.35, damping = 1 }) -- the container class: ζ1, 0.35 s
		else nil
	local reduced = ownedFormula(owner, function(use)
		return env ~= nil and use(env:get("motionPolicy")) == "reduced"
	end)

	local children = { body }
	if hasActions and reveal == "always" then
		table.insert(
			children,
			UI.HStack({ id = "Actions", width = UI.fill(), gap = "s", align = "center", children = actions })
		)
	elseif hasActions then
		-- the plate is part of the card's own envelope, directly below the body: the
		-- box never changes, and a pointer travelling from the body to an action never
		-- leaves the card
		table.insert(
			children,
			UI.ZStack({
				id = "Reveal",
				width = UI.fill(),
				opacity = function(use: any): number
					return if use(reduced) or fade == nil then 1 else math.clamp(use(fade), 0, 1)
				end,
				hidden = function(use: any): boolean
					return not use(revealed)
				end,
				-- the plate is its own layer, so a themed panel's chrome never narrows the row
				children = {
					UI.Box({ id = "Plate", surface = "raised", width = UI.fill(), height = UI.fill() }),
					UI.HStack({
						id = "Row",
						width = UI.fill(),
						padding = "s",
						gap = "s",
						align = "center",
						children = actions,
					}),
				},
			})
		)
	end
	--[[ THE LIFT: an engaged card (any input — hover, painted focus, a held
		press, its menu) rises by LIFT on the control spring with a raised shadow.
		Paint only: the box never moves, so a grid's gutters reserve the lifted
		footprint (`Facet.layout.transformFootprint(w, h, card.LIFT, 0)`).
		Reduced motion keeps the shadow alone, and at ten feet the focus visual's
		own `tenFootFocusScale` is the lift, so the card does not scale again. ]]
	local still = ownedFormula(owner, function(use)
		return use(reduced) or (env ~= nil and use(env:get("distanceProfile")) == "ten-foot")
	end)
	local lift = Facet.runtime.spring(function(use)
		return if use(engaged) and not use(still) then card.LIFT else 1
	end, { period = 0.28, damping = 0.85 })
	local raised = UI.shadowData("raised")
	local root = UI.VStack({
		id = id,
		width = spec.width or UI.fill(),
		gap = if reveal == "always" then "s" else 0,
		enabled = enabled,
		scale = function(use: any): number
			return if use(still) then 1 else math.clamp(use(lift), 1, card.LIFT)
		end,
		shadow = function(use: any): any
			return if use(engaged) then raised else nil
		end,
		children = children,
	})

	-- ===== the contribution ================================================
	local rootPath: string? = nil
	local controller: any = nil
	local graph: any = nil
	local hoverOff: (() -> ())? = nil
	local disposed = false
	local transient = { active = entered, rootPath = nil :: string? }
	local refusedTarget = false

	local function syncFocus()
		if disposed then
			return
		end
		local focused = if graph ~= nil then graph.focused:peek() else nil
		-- a PAINTED ring is engagement; the logical focus a pointer session is
		-- parked on (or a finger moved) is not, or the first card of every screen
		-- would open at rest
		local painted = graph ~= nil and (graph.focusVisible == nil or graph.focusVisible:peek() ~= false)
		focusWithin:set(rootPath ~= nil and prefixed(rootPath, focused) and painted)
		local target: any = nil
		if spec.browseTarget ~= nil and rootPath ~= nil then
			local resolve: any = spec.browseTarget
			target = resolve()
			if target ~= nil and type(target) ~= "string" then
				if not refusedTarget then
					refusedTarget = true
					local line = `Facet {where}: \`browseTarget\` returns a path string or nil — ignored`
					selection.note(diagnostics, line)
				end
				target = nil
			end
		end
		-- the browse stop the same way: a parked, unpainted focus is not engagement
		browsing:set(target ~= nil and focused == target and painted)
	end
	local function attachHover()
		if hoverOff == nil and controller ~= nil and rootPath ~= nil and controller.attachContextGestures ~= nil then
			hoverOff = controller.attachContextGestures(rootPath, {
				onHoverChanged = function(on: boolean)
					if not disposed then
						hovered:set(on == true)
					end
				end,
			})
		end
	end
	local function detach()
		if hoverOff ~= nil then
			hoverOff()
			hoverOff = nil
		end
		hovered:set(false)
		pressing:set(false)
	end

	local api = {} :: any
	function api.enterActions(): boolean
		if disposed or rootPath == nil or not enabled:peek() then
			return false
		end
		local eligible = menuRecord ~= nil
		if primary ~= nil and not eligible then
			eligible = selection.read(primary.enabled) ~= false and selection.read(primary.busy) ~= true
		end
		if not eligible then
			return false
		end
		entered:set(true)
		return true
	end
	function api.leaveActions()
		entered:set(false)
	end
	api.engaged = engaged
	api.revealed = revealed
	api.revealExtent = extent
	function api.diagnostics(): { string }
		return table.clone(diagnostics)
	end

	-- a disabled card holds no entry
	owner.watchStatic(enabled, function(on: boolean)
		if not on then
			entered:set(false)
		end
	end)

	local blueprint = contribution.attach(root, {
		bindController = function(c: any)
			controller = c
			attachHover()
		end,
		bindFocusGraph = function(g: any)
			graph = g
			owner.watchStatic(g.focused, syncFocus)
			if g.focusVisible ~= nil then
				owner.watchStatic(g.focusVisible, syncFocus)
			end
			syncFocus()
		end,
		syncGeometry = function(rectOf: any, node: any?)
			if node == nil or disposed then
				return
			end
			if node.path ~= rootPath then
				-- a fresh mount identity: nothing observed on the old one carries
				detach()
				rootPath = node.path
				transient.rootPath = `{node.path}/Reveal`
			end
			attachHover()
			-- the NATURAL bottom of the last part: the root can be offered less than it
			-- (a line sized from the previous measure), so measuring the root would never grow
			local last = if not hasActions then "Body" elseif reveal == "always" then "Actions" else "Reveal"
			local r, b = rectOf(node.path), rectOf(`{node.path}/{last}`)
			if type(r) == "table" and type(b) == "table" then
				height:set(b.y + b.h - r.y)
			end
			syncFocus()
		end,
		transientScope = if reveal == "automatic" and hasActions then transient else nil,
		handleCancel = function(): boolean
			if entered:peek() then
				entered:set(false)
				return true
			end
			return false
		end,
		outsideDismiss = if hasActions
			then {
				active = entered,
				dismiss = function()
					entered:set(false)
				end,
				consume = false,
			}
			else nil,
	})

	owner.own(function()
		disposed = true
		detach()
		entered:set(false)
	end)

	local function dump()
		return {
			schema = DUMP_SCHEMA,
			id = id,
			reveal = reveal,
			revealed = revealed:peek(),
			engaged = engaged:peek(),
			-- the engagement sources, each one owned here
			hovered = hovered:peek(),
			focusWithin = focusWithin:peek(),
			pressing = pressing:peek(),
			browsing = browsing:peek(),
			entered = entered:peek(),
			menuOpen = menuRecord ~= nil and menuRecord.api.isOpen:peek(),
			body = if spec.onActivate ~= nil then "button" else "informational",
			actions = #actions,
			extent = extent:peek(),
			diagnostics = table.clone(diagnostics),
		}
	end

	return {
		blueprint = blueprint,
		api = api,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function card.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return card

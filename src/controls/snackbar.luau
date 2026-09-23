--!strict
--[[ Snackbar — a short message at the bottom of the screen, with an optional
	icon, one optional action and a close button, shown one at a time by the
	application's snackbar service (`present/snackbar_layer.luau`, which holds the
	whole presentation contract: proposals, reasons, admission, dwell).

	`UI.Snackbar` registers with that service for as long as its Compose owner
	lives; the node it returns is an empty anchor. `app.presentSnackbar(spec)` is
	the same registration without a component, released by the function it
	returns. Screen applications only: a SurfaceGui or Billboard application has
	no bottom of the screen to dock to, so select a screen application for
	global notifications.

	LAYOUT. Message-only and icon+message hug their copy up to the safe maximum.
	An action or a close button selects the theme's constrained width
	(`controls.snackbar.maxWidth`, bounded by the safe room); the action sits
	beside the copy when the measured width holds both and moves below it when it
	does not; the close button keeps its full target. Long copy wraps. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local contribution = require("../input/contribution")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local themeSnapshot = require("../themes/snapshot")
local textFit = require("../layout/text_fit")
local alert = require("./alert")

local snackbar = {}

local specTypes = require("../spec_types/snackbar")
export type Spec = specTypes.Spec

local KEYS = guard.keySet({
	"action",
	"closeButton",
	"duration",
	"icon",
	"id",
	"isPresented",
	"message",
	"onDismiss",
	"onPresentedChange",
	"priority",
})
local ACTION_KEYS = guard.keySet({ "label", "onActivate" })
local DUMP_SCHEMA = "facet-snackbar-dump/1"

local function textish(v: any): boolean
	return type(v) == "string" or type(v) == "function" or Compose.isReadable(v)
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- the closed contract, shared by `UI.Snackbar` and `app.presentSnackbar`
function snackbar.validate(spec: any, where: string)
	if type(spec) ~= "table" then
		error(`Facet {where}: expected a spec table.`, 0)
	end
	guard.assertKnownKeys(where, spec, KEYS, "spec")
	if spec.isPresented == nil or not (type(spec.isPresented) == "boolean" or textish(spec.isPresented)) then
		error(`Facet {where}: \`isPresented\` is required — the caller's Bound<boolean> fact.`, 0)
	end
	if not textish(spec.message) then
		error(`Facet {where}: \`message\` is required — a string or a bound string.`, 0)
	end
	if spec.icon ~= nil and (type(spec.icon) ~= "string" or spec.icon == "") then
		error(`Facet {where}: \`icon\` is a semantic icon name or an image source.`, 0)
	end
	if spec.action ~= nil then
		if type(spec.action) ~= "table" then
			error(`Facet {where}: \`action\` is \{ label, onActivate }.`, 0)
		end
		guard.assertKnownKeys(where, spec.action, ACTION_KEYS, "action")
		if not textish(spec.action.label) or type(spec.action.onActivate) ~= "function" then
			error(`Facet {where}: \`action\` needs a label and an onActivate function.`, 0)
		end
	end
	for _, key in { "onPresentedChange", "onDismiss" } do
		if spec[key] ~= nil and type(spec[key]) ~= "function" then
			error(`Facet {where}: \`{key}\` is a function.`, 0)
		end
	end
	if spec.closeButton ~= nil and type(spec.closeButton) ~= "boolean" then
		error(`Facet {where}: \`closeButton\` is true (default) or false.`, 0)
	end
	if spec.duration ~= nil and not (finite(spec.duration) and spec.duration > 0) then
		error(`Facet {where}: \`duration\` is a positive finite number of seconds, or nil (persistent).`, 0)
	end
	if spec.priority ~= nil and not finite(spec.priority) then
		error(`Facet {where}: \`priority\` is a finite number (default 0).`, 0)
	end
	if (spec.closeButton ~= false or spec.duration ~= nil) and spec.onPresentedChange == nil then
		error(
			`Facet {where}: a close button or a duration PROPOSES a close, so it needs \`onPresentedChange\`. `
				.. "A read-only snackbar sets `closeButton = false` and no duration.",
			0
		)
	end
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	local id = (spec :: any).id or "Snackbar"
	local where = `UI.Snackbar('{id}')`
	snackbar.validate(spec, where)
	local service = if Facet.surfaces ~= nil then Facet.surfaces.snackbar else nil
	if service == nil then
		error(
			`Facet {where}: snackbars are a screen-space application service. Build it under a screen `
				.. "application (`Facet.client.application.new`); a SurfaceGui or Billboard application has no "
				.. "screen bottom to dock to, so present global notifications from a screen application.",
			0
		)
	end
	local registration = service.register(spec, owner, where)
	local function dump()
		local out = registration.dump()
		out.schema = DUMP_SCHEMA
		out.id = id
		return out
	end
	return {
		blueprint = Facet.UI.ZStack({ id = id .. "Anchor" }),
		api = { dump = dump },
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function snackbar.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

-- ===== the host and its rows (built with the application's controls) ======
local function resolve(metrics: any, name: string, fallback: number): number
	return themeSnapshot.resolveNumber(metrics, name) or fallback
end

local function rowView(Facet: any, env: any, rec: any, actions: any): any
	local UI = Facet.UI
	local spec = rec.spec
	local closable = spec.closeButton ~= false
	local constrained = spec.action ~= nil or closable
	local metrics, viewport = env:get("themeMetrics"), env:get("viewportRect")
	local function cap(use: any): number
		local m, v = use(metrics), use(viewport)
		local token = resolve(m, "controls.snackbar.maxWidth", 560)
		return math.max(0, math.min(token, v.w - 2 * resolve(m, "m", 16)))
	end
	-- beside when the measured width holds the copy and the action both
	local function beside(use: any): boolean
		if spec.action == nil then
			return true
		end
		local m = use(metrics)
		local facts = textFit.facts({ env = env, use = use })
		local gap = resolve(m, "s", 8)
		local target = resolve(m, "targetSizes.minimum", 44)
		local message = selection.read(spec.message, use)
		local label = selection.read(spec.action.label, use)
		local need = alert.labelWidth(m, facts, if type(message) == "string" then message else "")
			+ alert.labelWidth(m, facts, if type(label) == "string" then label else "")
			+ alert.buttonChromeX(m)
			+ gap
		local chrome = 2 * gap
			+ (if spec.icon ~= nil then resolve(m, "iconSizes.medium", 24) + gap else 0)
			+ (if closable then target + gap else 0)
		return need + chrome <= cap(use)
	end
	local body: { any } = { UI.Text({ id = "Message", text = spec.message, width = UI.fill() }) }
	if spec.action ~= nil then
		table.insert(
			body,
			Facet.nativeControls.Button({
				id = "Action",
				label = spec.action.label,
				disclose = true,
				onActivate = function()
					actions.activate(rec)
				end,
			})
		)
	end
	local row: { any } = {}
	if spec.icon ~= nil then
		table.insert(
			row,
			UI.Image({
				id = "Icon",
				image = spec.icon,
				width = { type = "fixed", px = "iconSizes.medium" },
				height = { type = "fixed", px = "iconSizes.medium" },
			})
		)
	end
	table.insert(
		row,
		UI.AdaptiveStack({
			id = "Body",
			width = UI.fill(),
			gap = "s",
			-- beside: centred on the copy; below it: the action trails
			align = function(use: any): string
				return if beside(use) then "center" else "end"
			end,
			axis = function(use: any): string
				return if beside(use) then "x" else "y"
			end,
			children = body,
		})
	)
	if closable then
		table.insert(
			row,
			Facet.nativeControls.Button({
				id = "Close",
				label = "Close",
				disclose = true,
				compactLabel = { icon = "close", prefer = true },
				onActivate = function()
					actions.close(rec)
				end,
			})
		)
	end
	local controller: any = nil
	local hoverOff: any = nil
	local root = contribution.attach(
		UI.ZStack({
			id = "Snack",
			width = function(use: any): any
				local w = cap(use)
				return if constrained then { type = "fixed", px = w } else { type = "hug", max = w }
			end,
			height = UI.hug(),
			children = {
				UI.Box({ id = "Plate", width = UI.fill(), height = UI.fill(), surface = "raised" }),
				UI.HStack({
					id = "Row",
					width = UI.fill(),
					padding = "s",
					gap = "s",
					align = "center",
					children = row,
				}),
			},
		}),
		{
			bindController = function(c: any)
				controller = c
			end,
			syncGeometry = function(_rectOf: any, node: any?)
				if node == nil then
					return
				end
				actions.mounted(rec, node.path)
				if hoverOff == nil and controller ~= nil and controller.attachContextGestures ~= nil then
					hoverOff = controller.attachContextGestures(node.path, {
						onHoverChanged = function(on: boolean)
							actions.hover(rec, on == true)
						end,
					}) or false
				end
			end,
			handleCancel = function(): boolean
				return actions.cancel(rec)
			end,
		}
	)
	Compose.cleanup(function()
		if hoverOff then
			hoverOff()
		end
		actions.unmounted(rec)
	end)
	return root
end

-- the persistent host: one bottom dock, a keyed row region, the keyboard's room
function snackbar.host(Facet: any, env: any, rows: any, attach: (any) -> any, actions: any): any
	local UI = Facet.UI
	local viewport, keyboard, chrome =
		env:get("viewportRect"), env:get("keyboardOcclusionRect"), env:get("platformChrome")
	local metrics = env:get("themeMetrics")
	return attach(UI.Screen({
		id = "FacetSnackbars",
		children = {
			UI.VStack({
				id = "Dock",
				width = UI.fill(),
				height = UI.fill(),
				align = "center",
				gap = "s",
				padding = function(use: any): any
					local v, occ, c = use(viewport), use(keyboard), use(chrome)
					local m = resolve(use(metrics), "m", 16)
					local inset = if type(c) == "table" and type(c.insets) == "table" then c.insets.bottom or 0 else 0
					local below = if type(occ) == "table" and type(occ.y) == "number"
						then math.max(0, v.y + v.h - inset - occ.y)
						else 0
					return { top = m, left = m, right = m, bottom = below + m }
				end,
				children = {
					-- the rows dock at the bottom edge
					UI.Spacer({ id = "Push", height = { type = "fill", weight = 1 } }),
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(rec: any): string
							return rec.key
						end,
						row = function(rec: any): any
							return rowView(Facet, env, rec, actions)
						end,
						transition = { enter = "slide-up", exit = "slide-down" },
					}),
				},
			}),
		},
	}))
end

return snackbar

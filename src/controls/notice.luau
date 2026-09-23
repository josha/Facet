--!strict
--[[ Notice — an inline status message: an icon for its severity, an optional
	title, the message, an optional link and up to two actions, and a close
	button when `onDismiss` is given. It never traps or takes focus; its
	controls join the page's own focus order, and its action roles only paint.

	PLACEMENT. `inline` (default) is ordinary flow. `affixed` is the page-local
	top recipe: put the Notice in the caller's safe-root fill ZStack, outside the
	body scroller; it fills the width, hugs its height, sits at the top and
	publishes its measured window rect through `presenter.reserveHud` under a
	mount-unique key. Content that should avoid it reads
	`presenter.hudReservations` through `Facet.layout.hudInsets` — an explicit
	consumer, never a change to every page. The reservation is cleared while the
	notice paints nothing and released with its owner.

	LAYOUT. The link and actions sit beside the copy when the measured width
	holds both, and move below it when it does not (the one AdaptiveStack; no
	fixed percentage). Closing reports the press; the caller unmounts. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local contribution = require("../input/contribution")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local textFit = require("../layout/text_fit")
local vocabulary = require("./control_vocabulary")
local statusIndicator = require("./status_indicator")
local alert = require("./alert")
local overlayParts = require("./overlay_parts")

local notice = {}

local specTypes = require("../spec_types/notice")
export type Spec = specTypes.Spec

local KEYS = guard.keySet({
	"actions",
	"appearance",
	"controlSize",
	"env",
	"icon",
	"id",
	"link",
	"message",
	"onDismiss",
	"placement",
	"severity",
	"title",
})
local LINK_KEYS = guard.keySet({ "label", "onActivate" })
local SEVERITIES = { info = true, success = true, warning = true, error = true }
local APPEARANCES = { standard = true, emphasis = true }
local PLACEMENTS = { inline = true, affixed = true }
local DUMP_SCHEMA = "facet-notice-dump/1"

local function textish(v: any): boolean
	return type(v) == "string" or type(v) == "function" or Compose.isReadable(v)
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.Notice", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Notice"
	local where = `UI.Notice('{id}')`

	if not textish(spec.message) then
		error(`Facet {where}: \`message\` is required — a string or a bound string.`, 0)
	end
	if spec.title ~= nil and not textish(spec.title) then
		error(`Facet {where}: \`title\` is a string or a bound string.`, 0)
	end
	local severity = spec.severity or "info"
	if SEVERITIES[severity] ~= true then
		error(`Facet {where}: \`severity\` is info | success | warning | error.`, 0)
	end
	local appearance = spec.appearance or "standard"
	if APPEARANCES[appearance] ~= true then
		error(`Facet {where}: \`appearance\` is standard | emphasis.`, 0)
	end
	local placement = spec.placement or "inline"
	if PLACEMENTS[placement] ~= true then
		error(`Facet {where}: \`placement\` is inline | affixed.`, 0)
	end
	if spec.icon ~= nil and type(spec.icon) ~= "boolean" and (type(spec.icon) ~= "string" or spec.icon == "") then
		error(`Facet {where}: \`icon\` is true (default), false, or an icon name / image source.`, 0)
	end
	if spec.link ~= nil then
		if type(spec.link) ~= "table" then
			error(`Facet {where}: \`link\` is \{ label, onActivate }.`, 0)
		end
		guard.assertKnownKeys("UI.Notice", spec.link, LINK_KEYS, "link")
		if not textish(spec.link.label) or type(spec.link.onActivate) ~= "function" then
			error(`Facet {where}: \`link\` needs a label and an onActivate function.`, 0)
		end
	end
	if spec.onDismiss ~= nil and type(spec.onDismiss) ~= "function" then
		error(`Facet {where}: \`onDismiss\` is a function.`, 0)
	end
	vocabulary.assertSize("UI.Notice", spec.controlSize)
	local actions: { any } = spec.actions or {}
	overlayParts.checkActions(where, spec.actions, 2)

	local env = surfaceEnv.forSpec(core, spec.env)
	local plateRole = statusIndicator.PLATE_ROLES[severity]
	local onRole = statusIndicator.ON_ROLES[severity]
	local emphasis = appearance == "emphasis"
	local lettering = if emphasis then { role = onRole, blend = 1 } else nil
	local offered = Compose.cell(0)

	-- beside the copy when the measured width holds copy and accessories both
	local accessoryLabels: { any } = {}
	if spec.link ~= nil then
		table.insert(accessoryLabels, spec.link.label)
	end
	for _, action in actions do
		table.insert(accessoryLabels, action.label)
	end
	local beside = ownedFormula(owner, function(use)
		if #accessoryLabels == 0 then
			return true
		end
		local metrics = if env ~= nil then use(env:get("themeMetrics")) else themeSnapshot.neutral()
		local facts = if env ~= nil then textFit.facts({ env = env, use = use }) else { scale = 1, offset = 0 }
		local gap = themeSnapshot.resolveNumber(metrics, "s") or 8
		local need = 0
		for _, label in accessoryLabels do
			local text = selection.read(label, use)
			need += alert.labelWidth(metrics, facts, if type(text) == "string" then text else "") + alert.buttonChromeX(
				metrics
			) + gap
		end
		local message = selection.read(spec.message, use)
		local copy = alert.labelWidth(metrics, facts, if type(message) == "string" then message else "")
		local chrome = (themeSnapshot.resolveNumber(metrics, "targetSizes.minimum") or 44) * 2 + gap * 4
		return copy + need + chrome <= use(offered)
	end)

	local function row(): any
		local children: { any } = {}
		if spec.icon ~= false then
			table.insert(
				children,
				UI.Image({
					id = "Icon",
					image = if type(spec.icon) == "string" then spec.icon else `status.{severity}`,
					width = { type = "fixed", px = "iconSizes.medium" },
					height = { type = "fixed", px = "iconSizes.medium" },
					tint = { role = if emphasis then onRole else plateRole, blend = 1 },
				})
			)
		end
		local copy: { any } = {}
		if spec.title ~= nil then
			table.insert(
				copy,
				UI.Text({ id = "Title", text = spec.title, textSize = "label", width = UI.fill(), tint = lettering })
			)
		end
		table.insert(copy, UI.Text({ id = "Message", text = spec.message, width = UI.fill(), tint = lettering }))
		local body: { any } = { UI.VStack({ id = "Copy", width = UI.fill(), gap = "xs", children = copy }) }
		if #accessoryLabels > 0 then
			local accessories: { any } = {}
			if spec.link ~= nil then
				table.insert(
					accessories,
					Facet.nativeControls.Button({
						id = "Link",
						label = spec.link.label,
						appearance = "link",
						disclose = true,
						controlSize = spec.controlSize,
						onActivate = spec.link.onActivate,
					})
				)
			end
			for _, action in actions do
				table.insert(
					accessories,
					Facet.nativeControls.Button({
						id = action.id,
						label = action.label,
						enabled = action.enabled,
						busy = action.busy,
						-- roles PAINT here; a page is not a modal and gets no default/cancel keys
						role = if action.role == "destructive" then "destructive" else nil,
						surface = if action.role == "default" then "accent" else nil,
						disclose = true,
						controlSize = spec.controlSize,
						onActivate = action.onActivate,
					})
				)
			end
			-- below the copy the accessories wrap rather than run past the plate
			table.insert(
				body,
				UI.HStack({ id = "Accessories", gap = "s", align = "center", wrap = true, children = accessories })
			)
		end
		table.insert(
			children,
			UI.AdaptiveStack({
				id = "Body",
				width = UI.fill(),
				gap = "s",
				axis = ownedFormula(owner, function(use)
					return if use(beside) then "x" else "y"
				end),
				align = "center",
				children = body,
			})
		)
		if spec.onDismiss ~= nil then
			table.insert(
				children,
				Facet.nativeControls.Button({
					id = "Close",
					label = "Close",
					disclose = true,
					compactLabel = { icon = "close", prefer = true },
					controlSize = spec.controlSize,
					onActivate = function()
						pcall(spec.onDismiss :: any)
					end,
				})
			)
		end
		return UI.HStack({ id = "Row", width = UI.fill(), gap = "s", align = "start", children = children })
	end

	local root = UI.ZStack({
		id = id,
		width = UI.fill(),
		height = UI.hug(),
		alignV = if placement == "affixed" then "start" else nil,
		children = {
			UI.Box({
				id = "Plate",
				width = UI.fill(),
				height = UI.fill(),
				surface = if emphasis then nil else "raised",
				tint = if emphasis then { role = plateRole, blend = 1 } else nil,
			}),
			UI.VStack({ id = "Content", width = UI.fill(), padding = "s", children = { row() } }),
		},
	})

	-- ===== measured width, and the affixed reservation ====================
	local controller: any = nil
	local reservation: any = nil
	local reservedPath: string? = nil
	local token = tostring(owner) -- a mount identity, never a shared counter
	local blueprint = contribution.attach(root, {
		bindController = function(c: any)
			controller = c
		end,
		syncGeometry = function(rectOf: any, node: any?)
			if node == nil then
				return
			end
			local r = rectOf(node.path)
			if type(r) == "table" and r.w ~= offered:peek() then
				offered:set(r.w)
			end
			if placement ~= "affixed" or Facet.presenter == nil or Facet.presenter.reserveHud == nil then
				return
			end
			if reservedPath ~= node.path then
				if reservation ~= nil then
					reservation.dispose()
				end
				reservedPath = node.path
				reservation = Facet.presenter.reserveHud({
					id = `facet-notice:{node.path}:{token}`,
					edge = "top",
					scope = owner,
				})
			end
			local screen = if controller ~= nil and controller.screenRectOf ~= nil
				then controller.screenRectOf(node.path)
				else r
			local paints = type(screen) == "table" and screen.w > 0 and screen.h > 0
			reservation.update(if paints then screen else nil)
		end,
	})

	local function dump()
		return {
			schema = DUMP_SCHEMA,
			id = id,
			severity = severity,
			appearance = appearance,
			placement = placement,
			accessories = if beside:peek() then "beside" else "below",
			actionCount = #actions,
			closable = spec.onDismiss ~= nil,
		}
	end

	return {
		blueprint = blueprint,
		api = { layout = beside },
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function notice.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return notice

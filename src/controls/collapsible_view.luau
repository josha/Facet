--!strict
-- One view transforms between a summary button and an expanded clipping plate.
local guard = require("../spec_guard")
local selectionModel = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local chromeSlots = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local themeSnapshot = require("../themes/snapshot")
local regionExpand = require("../region_expand")
local contribution = require("../input/contribution")
local collapsible = {}
local Compose = require("../vendor/compose/core")
local specTypes = require("../spec_types/collapsible_view")
type BooleanCell = specTypes.BooleanCell
export type Spec<V = BooleanCell> = specTypes.Spec<V>
local KEYS = guard.keySet({
	"id",
	"label",
	"icon",
	"image",
	"content",
	"expanded",
	"env",
	"width",
	"initialFocus",
	"enabled",
	"dismissButton",
})
function collapsible.build(Facet, core, spec: Spec)
	guard.assertKnownKeys("UI.CollapsibleView", spec, KEYS, "spec")
	assert(
		spec.dismissButton == nil or spec.dismissButton == "always" or spec.dismissButton == "automatic",
		"UI.CollapsibleView.dismissButton must be always | automatic"
	)
	local UI = Facet.UI
	local id = spec.id or "CollapsibleView"
	assert(
		type(id) == "string" and id ~= "" and not id:find("/", 1, true),
		"UI.CollapsibleView.id must be a nonempty path segment"
	)
	assert(
		selectionModel.isWritable(spec.expanded) and type(selectionModel.read(spec.expanded)) == "boolean",
		"UI.CollapsibleView.expanded must be a writable Compose cell holding a boolean, owned by the caller"
	)
	assert(
		type(spec.content) == "function" or (type(spec.content) == "table" and type(spec.content.class) == "string"),
		"UI.CollapsibleView.content must be a node or a content factory"
	)
	local function read(value)
		return selectionModel.read(value)
	end
	assert(
		type(read(spec.label)) == "string" and read(spec.label) ~= "",
		"UI.CollapsibleView.label must contain nonempty text"
	)
	assert(
		read(spec.icon) == nil or type(read(spec.icon)) == "string",
		"UI.CollapsibleView.icon must contain an icon name or nil"
	)
	assert(spec.icon == nil or spec.image == nil, "CollapsibleView accepts icon or image, not both")
	assert(
		read(spec.image) == nil or type(read(spec.image)) == "string",
		"UI.CollapsibleView.image must contain an asset string or nil"
	)
	local env = surfaceEnv.resolve("CollapsibleView", id, core, spec.env, "presentation needs the available safe area")
	local rootPath, presentAnchored, dismiss, handle
	local triggerWidth = Compose.cell(0)
	local disposed = false
	local triggerRect
	local controller
	local focusVisible
	local function collapse()
		spec.expanded:set(false)
	end
	local function closeSurface()
		if handle then
			local old = handle
			handle = nil
			if dismiss then
				dismiss(old)
			end
		end
	end
	local function maxHeightValue(use)
		local vp = use(env:get("viewportRect"))
		local insets = use(env:get("platformChrome")).insets
		return {
			type = "minMax",
			max = math.max(
				1,
				vp.h
					- insets.top
					- insets.bottom
					- 2 * (themeSnapshot.resolveNumber(use(env:get("themeMetrics")), "m") or 16)
			),
		}
	end
	local maxHeight = Compose.formula(maxHeightValue)
	local function panelWidthValue(use)
		local vp = use(env:get("viewportRect"))
		local insets = use(env:get("platformChrome")).insets
		local margin = themeSnapshot.resolveNumber(use(env:get("themeMetrics")), "m") or 16
		local maximum = math.max(1, vp.w - insets.left - insets.right - 2 * margin)
		return {
			type = "minMax",
			min = math.min(use(triggerWidth), maximum),
			preferred = "controls.popup.panelWidth",
			max = maximum,
		}
	end
	local panelWidth = Compose.formula(panelWidthValue)
	local function panel()
		return contribution.attach(
			UI.ZStack({
				id = "Panel",
				canvasGroup = true,
				clipChildren = true,
				surface = "raised",
				width = panelWidth,
				height = maxHeight,
				children = {
					UI.ZStack({
						id = "Content",
						-- The panel owns the single compositing buffer for expansion.
						width = UI.fill(),
						height = maxHeight,
						children = {
							UI.ScrollView({
								id = "Body",
								axis = "y",
								width = UI.fill(),
								height = maxHeight,
								padding = "m",
								gap = "s",
								children = {
									if type(spec.content) == "function" then spec.content() else spec.content,
									regionExpand.collapseButton(
										UI,
										"Collapse",
										collapse,
										spec.dismissButton,
										focusVisible
									),
								},
							}),
						},
					}),
				},
			}),
			{
				handleCancel = function()
					collapse()
					return true
				end,
			}
		)
	end
	local function sync()
		if not selectionModel.read(spec.expanded) then
			closeSurface()
			return
		end
		if disposed or handle or not rootPath or not presentAnchored or not triggerRect then
			return
		end
		local source = controller and controller.screenRectOf(rootPath)
		if source then
			triggerRect = table.clone(source)
		end
		local nextHandle = presentAnchored(if Facet.surfaces then panel else panel(), {
			id = "Expanded-" .. rootPath:gsub(".", function(c)
				return string.format("%02X", string.byte(c))
			end),
			modal = true,
			outsideTapCancel = true,
			cancelPolicy = "none",
			scrim = "none",
			anchor = { source = { path = rootPath }, edge = "overlap", margin = "m" },
			initialFocus = read(spec.initialFocus),
			transition = {
				enter = "transform",
				exit = "transform",
				fromRect = triggerRect,
				plate = "fades",
				class = "dismiss",
				exitClass = "dismiss",
			},
		})
		handle = nextHandle
		nextHandle.scope.own(function()
			if handle == nextHandle then
				handle = nil
				collapse()
			end
		end)
	end
	Compose.watch(function(use)
		assert(type(use(spec.expanded)) == "boolean", "UI.CollapsibleView.expanded must remain boolean")
		sync()
	end)
	local function dispose()
		if disposed then
			return
		end
		disposed = true
		closeSurface()
	end
	local function iconsValue(use)
		local value = selectionModel.read(spec.icon, use)
		assert(value == nil or type(value) == "string", "UI.CollapsibleView.icon must contain an icon name or nil")
		return if value then { value } else {}
	end
	local icons = Compose.formula(iconsValue)
	local function iconView(name, nodeId)
		return chromeSlots.attachHint(
			UI.Text({ id = nodeId, text = themePackage.iconGlyph(name) or "", textSize = "control" }),
			{ icon = name, iconSize = "small" }
		)
	end
	local function hasImage(use)
		local value = selectionModel.read(spec.image, use)
		return value ~= nil and value ~= ""
	end
	local function imageView()
		return UI.Image({
			id = "Image",
			image = spec.image,
			width = { type = "fixed", px = "controlSizes.regular.iconSize" },
			height = { type = "fixed", px = "controlSizes.regular.iconSize" },
		})
	end
	local blueprint = contribution.attach(
		UI.corners(
			UI.Button({
				id = id,
				label = spec.label,
				width = spec.width,
				enabled = spec.enabled,
				children = {
					UI.HStack({
						id = "Summary",
						shrinkWeight = 1,
						gap = "s",
						align = "center",
						children = {
							Compose.show(hasImage, imageView),
							Compose.keyed({
								from = icons,
								key = function(name)
									return name
								end,
								render = function(item)
									return iconView(item:peek(), "Image")
								end,
							}),
							UI.Text({
								id = "Label",
								text = spec.label,
								width = { type = "minMax", min = 0 },
								shrinkWeight = 1,
								textSize = "control",
								lineLimit = 1,
								disclose = true,
							}),
							iconView("chevron.down", "Chevron"),
						},
					}),
				},
				disclose = true,
				height = { type = "minMax", min = "targetSizes.minimum" },
				onActivate = function()
					spec.expanded:set(not selectionModel.read(spec.expanded))
				end,
			}),
			"pill"
		),
		{
			bindFocusGraph = function(graph)
				focusVisible = graph.focusVisible
			end,
			bindController = function(c)
				controller = c
			end,
			bindPresent = function(_, dismissFn, presentFn)
				dismiss = dismissFn
				presentAnchored = if Facet.surfaces then Facet.surfaces.anchored else presentFn
				sync()
			end,
			syncGeometry = function(rectOf, node)
				if node then
					rootPath = node.path
					local rect = rectOf(rootPath)
					if rect then
						triggerWidth:set(rect.w)
						if triggerRect and handle then
							local screen = controller and controller.screenRectOf(rootPath)
							if screen then
								for _, key in { "x", "y", "w", "h" } do
									triggerRect[key] = screen[key]
								end
							end
						else
							triggerRect = rect
						end
					end
					sync()
				end
			end,
			bindInputScope = function(inputScope)
				inputScope.onDispose(function()
					closeSurface()
					rootPath = nil
					presentAnchored = nil
					dismiss = nil
					spec.expanded:set(false)
				end)
			end,
		}
	)
	local function dump()
		return {
			schema = "facet-collapsible-view-dump/1",
			id = id,
			expanded = selectionModel.read(spec.expanded),
			presented = handle ~= nil,
		}
	end
	return table.freeze({
		blueprint = blueprint,
		collapse = collapse,
		dump = dump,
		dispose = dispose,
	})
end
return collapsible

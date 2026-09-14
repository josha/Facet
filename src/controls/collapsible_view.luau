--!strict
-- One view transforms between a summary button and an expanded clipping plate.
local guard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local chromeSlots = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local themeSnapshot = require("../themes/snapshot")
local collapsible = {}
export type Spec = {
	id: string?,
	label: any,
	icon: any?,
	image: any?,
	content: any,
	expanded: any,
	env: any?,
	width: any?,
	initialFocus: any?,
	enabled: any?,
}
local KEYS =
	guard.keySet({ "id", "label", "icon", "image", "content", "expanded", "env", "width", "initialFocus", "enabled" })
function collapsible.build(Facet, core, spec: Spec)
	guard.assertKnownKeys("Controls.CollapsibleView", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "CollapsibleView"
	assert(
		type(id) == "string" and id ~= "" and not id:find("/", 1, true),
		"CollapsibleView.id must be a nonempty path segment"
	)
	assert(
		type(spec.expanded) == "table" and spec.expanded.kind == "signal" and type(spec.expanded:get()) == "boolean",
		"CollapsibleView.expanded must be an owner-held boolean Signal"
	)
	assert(
		type(spec.content) == "table" and type(spec.content.class) == "string",
		"CollapsibleView.content must be a blueprint"
	)
	local function read(value)
		return if type(value) == "table" and type(value.get) == "function" then value:get() else value
	end
	assert(
		type(read(spec.label)) == "string" and read(spec.label) ~= "",
		"CollapsibleView.label must contain nonempty text"
	)
	assert(
		read(spec.icon) == nil or type(read(spec.icon)) == "string",
		"CollapsibleView.icon must contain an icon name or nil"
	)
	assert(spec.icon == nil or spec.image == nil, "CollapsibleView accepts icon or image, not both")
	assert(
		read(spec.image) == nil or type(read(spec.image)) == "string",
		"CollapsibleView.image must contain an asset string or nil"
	)
	UI.Button({ label = spec.label, width = spec.width, enabled = spec.enabled })
	local env = surfaceEnv.resolve("CollapsibleView", id, core, spec.env, "presentation needs the available safe area")
	local scope = core:scope("collapsible-view-" .. id)
	local rootPath, presentAnchored, dismiss, handle
	local triggerWidth = scope:own(core:signal(0))
	local disposed = false
	local triggerRect
	local controller
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
	local maxHeight = scope:own(core:memo(function(use)
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
	end))
	local panelWidth = scope:own(core:memo(function(use)
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
	end))
	local panel = Facet.contribution.attach(
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
					canvasGroup = true,
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
								spec.content,
								UI.Button({
									id = "Collapse",
									label = "Collapse",
									compactLabel = { icon = "chevron.up", prefer = true },
									disclose = true,
									width = UI.fill(),
									height = { type = "minMax", min = "targetSizes.minimum" },
									onActivate = collapse,
								}),
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
	local function sync()
		if not spec.expanded:get() then
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
		local nextHandle = presentAnchored(panel, {
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
				content = "Content",
				plate = "fades",
				class = "dismiss",
				exitClass = "dismiss",
			},
		})
		handle = nextHandle
		nextHandle.scope:own(function()
			if handle == nextHandle then
				handle = nil
				collapse()
			end
		end)
	end
	scope:own(core:observe(spec.expanded, function(value)
		assert(type(value) == "boolean", "CollapsibleView.expanded must remain boolean")
		sync()
	end))
	scope:own(function()
		disposed = true
		closeSurface()
	end)
	local icons = scope:own(core:memo(function(use)
		local value = if type(spec.icon) == "table" and spec.icon.get then use(spec.icon) else spec.icon
		assert(value == nil or type(value) == "string", "CollapsibleView.icon must contain an icon name or nil")
		return if value then { value } else {}
	end))
	local function iconView(name, nodeId)
		return chromeSlots.attachHint(
			UI.Text({ id = nodeId, text = themePackage.iconGlyph(name) or "", textSize = "control" }),
			{ icon = name, iconSize = "small" }
		)
	end
	local imageView
	if spec.image ~= nil then
		imageView = UI.Image({
			id = "Image",
			image = spec.image,
			width = { type = "fixed", px = "controlSizes.regular.iconSize" },
			height = { type = "fixed", px = "controlSizes.regular.iconSize" },
		})
	end
	local blueprint = Facet.contribution.attach(
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
							UI.When({
								id = "CustomImage",
								condition = scope:own(core:memo(function(use)
									local value = if type(spec.image) == "table" and spec.image.get
										then use(spec.image)
										else spec.image
									return value ~= nil and value ~= ""
								end)),
								thenView = function()
									return imageView
								end,
							}),
							UI.ForEach({
								id = "Icon",
								items = icons,
								key = function(name)
									return name
								end,
								row = function(name)
									return iconView(name, "Image")
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
					spec.expanded:set(not spec.expanded:get())
				end,
			}),
			"pill"
		),
		{
			bindController = function(c)
				controller = c
			end,
			bindPresent = function(_, dismissFn, presentFn)
				dismiss = dismissFn
				presentAnchored = presentFn
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
			expanded = spec.expanded:get(),
			presented = handle ~= nil,
		}
	end
	return table.freeze({
		blueprint = blueprint,
		collapse = collapse,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
	})
end
return collapsible

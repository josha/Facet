--!strict
type Context = typeof(require("@repo/examples/types").Context)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ThemePackage)
type ZoomControls = typeof(require("@repo/tools/typecheck/aliases").ZoomControls)
type Role = "caption" | "label" | "body" | "heading" | "title" | "control" | "strong" | "numeral"
local model = require("./model")
type Node = model.Node
local source = require("./copy")
local art = require("./art")

return function(ctx: Context)
	local UI, H, C, runtime = ctx.UI, ctx.Host, ctx.Compose, ctx.runtime
	local D2, V2, C3, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Color3, ctx.types.Enum
	local theme: Readable<ThemePackage> = ctx.theme or C.cell(ctx.Facet.themes.neutralPackage())
	local mode: Readable<string> = ctx.themeMode or C.cell(theme:peek().style.defaultTheme)
	local LocalizationTable = ((H :: unknown) :: {
		LocalizationTable: (string) -> ({ SourceLocaleId: string }) -> LocalizationTable,
	}).LocalizationTable
	local translations = LocalizationTable "AscentStrings" { SourceLocaleId = "en-us" }
	local entries = {}
	for key, value in source do
		table.insert(entries, { Key = "Ascent." .. key, Source = value, Values = { ["en-us"] = value } })
	end
	translations:SetEntries(entries)
	local translator = translations:GetTranslator(if ctx.player then ctx.player.LocaleId else "en-us")
	local function text(key: string, args: { [string]: string }?): string
		assert(source[key], "Missing Ascent localization key: " .. key)
		return translator:FormatByKey("Ascent." .. key, args or {})
	end
	local function color(role: string, use: Use): Color3
		local package = use(theme)
		local palette = package.style.themes[1]
		for _, candidate in package.style.themes do
			if candidate.name == use(mode) then
				palette = candidate
				break
			end
		end
		local rgb = assert(palette.colors[role], "Missing palette color: " .. role)
		return C3.new(rgb.r, rgb.g, rgb.b)
	end
	local state = C.cell(model.initial())
	local height = C.cell(700)
	local short = C.formula(function(use: Use)
		return use(height) < 420
	end)
	local zoom, focus = C.cell(0.85), C.cell(V2.new(600, 630))
	local camera: ZoomControls = {}
	local notice = C.cell(text("ready"))
	local last, flash = C.cell(""), C.cell(0)
	local nodes: { [string]: TextButton } = {}
	local map: ScrollingFrame? = nil
	local reduced = ctx.reducedMotion or C.cell(false)
	local env = UI.environment()
	local sequence = UI.sequence {
		steps = {
			{
				duration = "travel",
				sample = function(progress: number)
					flash:set(math.sin(progress * math.pi))
				end,
			},
		},
	}
	local function select(id: string): boolean
		local node = model.byId[id]
		if not node or not model.visible(state:peek(), node) then
			return false
		end
		if state:peek().selected ~= id then
			notice:set(text("ready"))
		end
		local nextState = table.clone(state:peek())
		nextState.selected = id
		state:set(nextState)
		return true
	end
	local function reveal(id: string)
		local view, button = map, nodes[id]
		if not view or not button or not camera.zoomTo then
			return
		end
		local area = view.AbsoluteWindowSize
		if area.X <= 0 or area.Y <= 0 then
			return
		end
		local offset = button.AbsolutePosition - view.AbsolutePosition
		if
			offset.X >= 0
			and offset.Y >= 0
			and offset.X + button.AbsoluteSize.X <= area.X
			and offset.Y + button.AbsoluteSize.Y <= area.Y
		then
			return
		end
		local scale = if ctx.previewScale then ctx.previewScale:peek() else 1
		local size = area / math.max(0.01, scale) / zoom:peek()
		local node = model.byId[id]
		camera.zoomTo({ x = node.x - size.X / 2, y = node.y - size.Y / 2, w = size.X, h = size.Y })
	end
	local function buy()
		local before = state:peek()
		local node = model.byId[before.selected]
		local after, result = model.purchase(before, node.id)
		runtime:batch(function()
			state:set(after)
			if result == "unlocked" then
				last:set(node.id)
				notice:set(text("unlocked", { name = text(node.id .. "Name") }))
			elseif result == "insufficient" then
				notice:set(text("insufficient", { missing = tostring(node.cost - before.points) }))
			elseif result == "locked" then
				notice:set(text("lockedMessage", { name = text(assert(node.parent) .. "Name") }))
			else
				notice:set(text("ownedMessage"))
			end
		end)
		if result == "unlocked" then
			sequence.play()
			UI.feedback("success")
		else
			UI.feedback("warning")
		end
	end
	local function label(
		name: string,
		value: string | Readable<string> | (Use) -> string,
		role: Role?,
		secondary: boolean?,
		visibleWhen: ((Use) -> boolean)?
	): GuiObject
		return UI.Text(name) {
			Visible = visibleWhen,
			text = value,
			textRole = role or "body",
			wrap = true,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			role = if secondary then "secondary" else "content",
			AutoLocalize = false,
		}
	end
	local visible = C.formula(function(use: Use): { Node }
		local result: { Node } = {}
		for _, node in model.nodes do
			if model.visible(use(state), node) then
				table.insert(result, node)
			end
		end
		return result
	end)
	local function boardSize(): Vector2
		local x, y = 0, 0
		for _, node in model.nodes do
			x = math.max(x, node.x + 110)
			y = math.max(y, node.y + 110)
		end
		return V2.new(x, y)
	end
	local function tile(current: Readable<Node>): GuiObject
		local node = current:peek()
		local status = C.formula(function(use: Use)
			return model.status(use(state), node)
		end)
		local selected = C.formula(function(use: Use)
			return use(state).selected == node.id
		end)
		local hovering = C.cell(false)
		local target = C.cell(0)
		local enter = runtime.tween(function(use: Use)
			return use(target)
		end, {
			seconds = function()
				return assert(theme:peek().metrics.motion.durations).travel
			end,
			ease = C.easing.outCubic,
			reducedMotion = reduced,
		})
		local emphasis = runtime.tween(function(use: Use)
			return if use(hovering) or use(selected) then 1 else 0
		end, {
			seconds = function()
				return theme:peek().metrics.motion.fast
			end,
			reducedMotion = reduced,
		})
		local function ink(use: Use): Color3
			return if use(status) == "locked"
				then color("content", use):Lerp(color("surfaceStrong", use), 0.35)
				else color("accent", use)
		end
		local body = H.Frame "Gem" {
			Size = D2.fromOffset(180, 156),
			Position = D2.fromScale(0.5, 0.5),
			AnchorPoint = V2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			C.show(selected, function()
				return art.outline(ctx, function(use: Use)
					return color("accent", use):Lerp(color("contentStrong", use), 0.7)
				end)
			end),
			H.UIScale {
				Scale = function(use: Use)
					return (0.3 + 0.7 * use(enter)) * (1 + 0.045 * use(emphasis))
				end,
			},
			art.hex(ctx, "Edge", 180, function(use: Use)
				local strength = if use(selected) then 1 elseif use(status) == "locked" then 0.13 else 0.8
				local edge = color("surfaceStrong", use):Lerp(ink(use), strength)
				return if use(last) == node.id and not use(reduced)
					then edge:Lerp(color("contentStrong", use), use(flash) * 0.7)
					else edge
			end, 3),
			art.hex(ctx, "Bevel", 174, function(use: Use)
				return color("surface", use):Lerp(ink(use), 0.18)
			end, 4),
			art.hex(ctx, "Face", 164, function(use: Use)
				return color("surfaceStrong", use):Lerp(ink(use), if use(status) == "owned" then 0.75 else 0.12)
			end, 5),
			H.Frame "Emblem" {
				ZIndex = 8,
				Size = D2.fromOffset(48, 48),
				Position = D2.fromScale(0.5, 0.27),
				AnchorPoint = V2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				C.show(function(use: Use)
					return use(status) == "locked"
				end, function()
					return art.icon(ctx, "lock", ink, 30)
				end),
				C.show(function(use: Use)
					return use(status) ~= "locked"
				end, function()
					return art.icon(ctx, node.icon, function(use: Use)
						return if use(status) == "owned" then color("onAccent", use) else color("contentStrong", use)
					end, 36)
				end),
			},
			UI.Text "SkillName" {
				TextColor3 = function(use: Use)
					return color(if use(status) == "owned" then "onAccent" else "content", use)
				end,
				text = text(node.id .. "Name"),
				textRole = "control",
				textAlign = "center",
				wrap = false,
				truncate = "end",
				AutoLocalize = false,
				Size = D2.fromOffset(120, 24),
				Position = D2.new(0.5, 0, 0, 70),
				AnchorPoint = V2.new(0.5, 0),
				ZIndex = 8,
			},
			UI.Text "SkillStatus" {
				TextColor3 = function(use: Use)
					return color(if use(status) == "owned" then "onAccent" else "content", use)
				end,
				text = function(use: Use)
					return if use(status) == "owned"
						then text("owned")
						elseif use(status) == "locked" then text("locked")
						else text(if use(selected) then "unlock" else "cost", { cost = tostring(node.cost) })
				end,
				textRole = "caption",
				textAlign = "center",
				wrap = false,
				truncate = "end",
				AutoLocalize = false,
				Size = D2.fromOffset(92, 20),
				Position = D2.new(0.5, 0, 0, 106),
				AnchorPoint = V2.new(0.5, 0),
				ZIndex = 8,
			},
		}
		local selectionImage = H.Frame "HexFocus" {
			Size = D2.fromScale(0.3, 0.025),
			Position = D2.fromScale(0.35, 1.025),
			AnchorPoint = V2.new(0.5, 0.5),
			BackgroundColor3 = function(use: Use)
				return color(if use(status) == "owned" then "onAccent" else "contentStrong", use)
			end,
			BorderSizePixel = 0,
		}
		local button = UI.Button("Skill_" .. node.id) {
			name = text("inspect", { name = text(node.id .. "Name") }),
			SelectionImageObject = C.static(selectionImage),
			label = "",
			appearance = "utility",
			BackgroundTransparency = 1,
			Size = D2.fromOffset(136, 120),
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
			ZIndex = 10,
			pop = false,
			AutoLocalize = false,
			onActivate = function()
				if state:peek().selected == node.id then
					buy()
				else
					select(node.id)
				end
			end,
			[C.event("MouseEnter")] = function()
				hovering:set(true)
			end,
			[C.event("MouseLeave")] = function()
				hovering:set(false)
			end,
			[C.event("SelectionGained")] = function()
				hovering:set(true)
				select(node.id)
				reveal(node.id)
			end,
			[C.event("SelectionLost")] = function()
				hovering:set(false)
			end,
		}
		nodes[node.id] = button
		C.cleanup(function()
			nodes[node.id] = nil
		end)
		local parent = if node.parent then model.byId[node.parent] else node
		local root = H.Frame("Node_" .. node.id) {
			Size = D2.fromOffset(180, 156),
			AnchorPoint = V2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = function(use: Use)
				local p = use(enter)
				return D2.fromOffset(parent.x + (node.x - parent.x) * p, parent.y + (node.y - parent.y) * p)
			end,
			body,
			button,
		}
		target:set(1)
		return root
	end
	local function board(): GuiObject
		local children: { Child } = {}
		for _, node in model.nodes do
			if node.parent then
				local parent = model.byId[node.parent]
				local dx, dy = node.x - parent.x, node.y - parent.y
				table.insert(
					children,
					H.Frame("Link_" .. node.id) {
						Size = D2.fromOffset(math.sqrt(dx * dx + dy * dy), 2),
						AnchorPoint = V2.new(0.5, 0.5),
						Position = D2.fromOffset((node.x + parent.x) / 2, (node.y + parent.y) / 2),
						Rotation = math.deg(math.atan2(dy, dx)),
						BorderSizePixel = 0,
						ZIndex = 1,
						Visible = function(use: Use)
							return model.visible(use(state), node)
						end,
						BackgroundColor3 = function(use: Use)
							return color("surfaceStrong", use):Lerp(
								color("accent", use),
								if use(state).owned[node.id] then 0.8 else 0.22
							)
						end,
					}
				)
			end
		end
		table.insert(
			children,
			C.keyed {
				from = visible,
				key = function(node: Node)
					return node.id
				end,
				render = tile,
			}
		)
		return H.Frame "SkillTreeCanvas" { Size = D2.fromScale(1, 1), BackgroundTransparency = 1, table.unpack(children) }
	end
	local function screen(): Instance
		map = UI.ZoomView "SkillMap" {
			contentSize = boardSize(),
			content = board,
			zoom = zoom,
			focus = focus,
			controls = camera,
			minZoom = 0.65,
			maxZoom = 1.5,
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}
		local root = UI.VStack "Ascent" {
			width = "fill",
			height = "fill",
			padding = "s",
			gap = "s",
			UI.VStack "MapPanel" {
				UI.fill(),
				width = "fill",
				height = "fill",
				surface = "panel",
				gap = "xs",
				padding = "xs",
				UI.HStack "MapTools" {
					width = "fill",
					gap = "xs",
					align = "center",
					UI.Button "FitTree" {
						label = text("fit"),
						AutoLocalize = false,
						onActivate = function()
							if camera.fit then
								camera.fit()
							end
						end,
					},
					UI.Button "ZoomOut" {
						label = text("minus"),
						name = text("farther"),
						AutoLocalize = false,
						onActivate = function()
							if camera.zoomAt then
								camera.zoomAt(math.max(0.65, zoom:peek() * 0.85))
							end
						end,
					},
					UI.Button "ZoomIn" {
						label = text("plus"),
						name = text("closer"),
						AutoLocalize = false,
						onActivate = function()
							if camera.zoomAt then
								camera.zoomAt(math.min(1.5, zoom:peek() * 1.18))
							end
						end,
					},
					UI.Text "SkillPoints" {
						text = function(use: Use)
							return text("points", { count = tostring(use(state).points) })
						end,
						textRole = "strong",
						AutoLocalize = false,
					},
					UI.Button "ResetTree" {
						label = text("restartSymbol"),
						name = text("reset"),
						appearance = "link",
						AutoLocalize = false,
						onActivate = function()
							sequence.cancel()
							flash:set(0)
							state:set(model.initial())
							notice:set(text("ready"))
							focus:set(V2.new(600, 580))
						end,
					},
				},
				UI.VStack "MapBounds" { width = "fill", height = "fill", UI.fill(), map },
				label(
					"MapHint",
					function(use: Use)
						local input = use(env.effectiveInput)
						return text(
							if input == "Gamepad" then "gamepad" elseif input == "Touch" then "touch" else "pointer"
						)
					end,
					"caption",
					true,
					function(use: Use)
						return not use(short)
					end
				),
			},
			UI.VStack "UpgradeDetails" {
				width = "fill",
				gap = "xs",
				label("UpgradeBenefit", function(use: Use)
					local id = use(state).selected
					return text("detail", { name = text(id .. "Name"), benefit = text(id .. "Benefit") })
				end, "body"),
				label("UpgradeNotice", function(use: Use)
					if use(notice) ~= text("ready") then
						return use(notice)
					end
					local current = use(state)
					local node = model.byId[current.selected]
					local status = model.status(current, node)
					if status == "locked" then
						return text("requires", { name = text(assert(node.parent) .. "Name") })
					end
					if status == "owned" then
						return text("ready")
					end
					return text(
						if use(env.effectiveInput) == "Gamepad" then "confirmGamepad" else "confirmTile",
						{ cost = tostring(node.cost) }
					)
				end, "caption", true),
			},
		}
		local function measure()
			local scale = if ctx.previewScale then ctx.previewScale:peek() else 1
			height:set(root.AbsoluteSize.Y / math.max(0.01, scale))
		end
		measure()
		local mapView = assert(map)
		runtime.connect(mapView, "Changed", function(property: string)
			if property == "AbsoluteWindowSize" then
				reveal(state:peek().selected)
			end
		end)
		runtime.connect(root, "Changed", function(property: string)
			if property == "AbsoluteSize" then
				measure()
			end
		end)
		local overview = assert(root:FindFirstChild("FitTree", true)) :: GuiObject
		C.watch(function(use: Use)
			local shown = use(visible)
			overview.NextSelectionDown = nodes[use(state).selected] or mapView
			for _, from in shown do
				local button = nodes[from.id]
				if not button then
					continue
				end
				for _, direction in { "Left", "Right", "Up", "Down" } do
					local nearest: TextButton? = nil
					local best = math.huge
					for _, to in shown do
						local dx, dy = to.x - from.x, to.y - from.y
						local along = if direction == "Left"
							then -dx
							elseif direction == "Right" then dx
							elseif direction == "Up" then -dy
							else dy
						local across = if direction == "Left" or direction == "Right"
							then math.abs(dy)
							else math.abs(dx)
						local score = along + across * 1.5
						if along > 0 and across <= along * 2 and score < best then
							nearest = nodes[to.id]
							best = score
						end
					end
					if direction == "Left" then
						button.NextSelectionLeft = nearest or overview
					elseif direction == "Right" then
						button.NextSelectionRight = nearest or overview
					elseif direction == "Up" then
						button.NextSelectionUp = nearest or overview
					else
						button.NextSelectionDown = nearest or overview
					end
				end
			end
		end)
		return root
	end
	return {
		screen = screen,
		select = function(value: unknown): boolean
			if type(value) ~= "string" or not select(value) then
				return false
			end
			reveal(value)
			return true
		end,
		report = function()
			local current = state:peek()
			local owned = {}
			for id in current.owned do
				table.insert(owned, id)
			end
			table.sort(owned)
			return {
				points = current.points,
				selected = current.selected,
				owned = owned,
				visible = #visible:peek(),
				zoom = zoom:peek(),
				notice = notice:peek(),
			}
		end,
	}
end

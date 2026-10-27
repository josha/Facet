--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Theme = require("./theme_types")
local layoutKit = require("./layout_kit")
local textMeasure = require("./text_measure")

local geometryQueue: { [() -> ()]: boolean } = {}
local geometryStop: (() -> ())? = nil

local function flushGeometry()
	local queued = geometryQueue
	geometryQueue = {}
	for refresh in queued do
		refresh()
	end
	if next(geometryQueue) == nil and geometryStop then
		local stop = geometryStop
		geometryStop = nil
		stop()
	end
end

local function attachLayout(
	ctx: Shared.Context,
	label: TextLabel | TextButton,
	stable: boolean?,
	watchPadding: boolean?
)
	local Compose, runtime, types, Host = ctx.Compose, ctx.runtime, ctx.types, ctx.Host
	local Enum, services = types.Enum, ctx.config.services
	local writable = (label :: unknown) :: { FontFace: Font, TextSize: number, AutomaticSize: Enum.AutomaticSize }
	local previousFace: Font?, previousSize: number? = nil, nil
	local frames = services.RunService
	local pending: RBXScriptConnection? = nil
	local floor: UISizeConstraint? = nil
	local alive = true
	local refreshing = false
	local function measuredFloor(): boolean
		return services.TextService ~= nil and floor ~= nil
	end
	local function reflow(metrics: boolean?)
		local automatic = label.AutomaticSize
		if automatic ~= Enum.AutomaticSize.None then
			refreshing = true
			local face, points = label:GetStyled("FontFace") :: Font, label:GetStyled("TextSize") :: number
			local resetFace, resetSize =
				metrics == true and label.FontFace ~= face, metrics == true and label.TextSize ~= points
			if resetFace then
				writable.FontFace = face
			end
			if resetSize then
				writable.TextSize = points
			end
			writable.AutomaticSize = Enum.AutomaticSize.None
			writable.AutomaticSize = automatic
			if resetFace then
				label:ResetPropertyToDefault("FontFace")
			end
			if resetSize then
				label:ResetPropertyToDefault("TextSize")
			end
			refreshing = false
		end
	end
	local function deferReflow()
		if
			pending == nil
			and frames
			and alive
			and not refreshing
			and label.AutomaticSize ~= Enum.AutomaticSize.None
		then
			local function nextFrame()
				if pending then
					pending:Disconnect()
					pending = nil
				end
				reflow(true)
			end
			pending = if frames.PreRender
				then frames.PreRender:Connect(nextFrame)
				else frames.Heartbeat:Connect(nextFrame)
		end
	end
	local function refreshMetrics()
		local face, points = label:GetStyled("FontFace") :: Font, label:GetStyled("TextSize") :: number
		if alive and (face ~= previousFace or points ~= previousSize) then
			local changed = previousFace ~= nil or previousSize ~= nil
			previousFace, previousSize = face, points
			if changed then
				reflow()
				deferReflow()
			end
		end
	end
	local revision = Compose.cell(0)
	local styling = Compose.cell(0)
	local snapshotAt = -1
	local snapMode, snapSize, snapWrapped = label.AutomaticSize, label.Size, false
	local function snapshot()
		local at = styling:peek()
		if at ~= snapshotAt then
			snapshotAt = at
			snapMode, snapSize = label.AutomaticSize, label.Size
			snapWrapped = label:GetStyled("TextWrapped") == true
		end
	end
	local framed = services.RunService ~= nil and getfenv ~= nil and getfenv(0).game ~= nil
	local box = label.AbsoluteSize
	local bounds = Compose.cell(label.TextBounds)
	local frameSource = runtime.host.frames
	local checkStale: () -> () = function() end
	local function readGeometry()
		if alive then
			box = label.AbsoluteSize
			bounds:set(label.TextBounds)
			checkStale()
		end
	end
	local function geometryChanged()
		if not framed or frameSource == nil then
			readGeometry()
			return
		end
		geometryQueue[readGeometry] = true
		if geometryStop == nil then
			geometryStop = frameSource.onFrame(flushGeometry)
		end
	end
	local refloor: () -> () = function() end
	local floorApply: () -> () = function() end
	local function invalidate()
		if not refreshing then
			styling:set(styling:peek() + 1)
			revision:set(revision:peek() + 1)
			refloor()
			floorApply()
			checkStale()
		end
	end
	local function styleChanged()
		if not refreshing then
			refreshMetrics()
			invalidate()
		end
	end
	local styled = label.StyledPropertiesChanged:Connect(styleChanged)
	local changed = label.Changed:Connect(function(property: string)
		if property == "FontFace" or property == "TextSize" then
			styleChanged()
		elseif property == "AbsoluteSize" or property == "TextBounds" then
			geometryChanged()
		elseif property == "Text" then
			floorApply()
			if not measuredFloor() and previousSize ~= nil and label.TextSize ~= previousSize then
				deferReflow()
			end
		elseif
			property == "AutomaticSize"
			or property == "Size"
			or property == "TextWrapped"
			or property == "TextTruncate"
			or property == "LineHeight"
			or property == "RichText"
		then
			invalidate()
		end
	end)
	refreshMetrics()
	if watchPadding then
		local function observePadding(child: Instance)
			if child:IsA("UIPadding") then
				runtime.connect(child, "StyledPropertiesChanged", invalidate)
				runtime.connect(child, "Changed", invalidate)
				invalidate()
			end
		end
		for _, child in label:GetChildren() do
			observePadding(child)
		end
		runtime.connect(label, "ChildAdded", observePadding)
		runtime.connect(label, "ChildRemoved", function(child: Instance)
			if child:IsA("UIPadding") then
				invalidate()
			end
		end)
	end
	checkStale = function()
		snapshot()
		local glyph, mode = bounds:peek(), snapMode
		local freeX = mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY
		local freeY = mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY
		local measured = measuredFloor()
		local stale = measured
			and freeX
			and glyph.X > 0
			and glyph.Y > 0
			and glyph.X <= box.X
			and glyph.Y <= box.Y
			and not label.TextFits
		if
			box.X > 0
			and box.Y > 0
			and (stale or (not measured and ((freeX and glyph.X > box.X) or (freeY and glyph.Y > box.Y))))
		then
			deferReflow()
		end
	end
	checkStale()
	local function buildWrapped(
		wrappedHeight: ComposeTypes.Value<number>,
		unit: () -> ComposeTypes.ReadOnlyValue<number>
	)
		local serial, last = 0, ""
		local active = true
		local release: (() -> ())? = nil
		local params: GetTextBoundsParams? = nil
		local function finish()
			if release then
				release()
				release = nil
			end
		end
		local words =
			runtime.observe(label, "Text", if framed then { frame = true } else nil) :: ComposeTypes.ReadOnlyValue<string>
		local wrappedSize =
			runtime.observe(label, "AbsoluteSize", if framed then { frame = true } else nil) :: ComposeTypes.ReadOnlyValue<Vector2>
		Compose.cleanup(function()
			active = false
			finish()
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(revision)
			snapshot()
			local mode = snapMode
			if not snapWrapped or not (mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY) then
				serial += 1
				last = ""
				wrappedHeight:set(0)
				floorApply()
				finish()
				return
			end
			local wide = use(wrappedSize).X / use(unit())
			local padding = label:FindFirstChildWhichIsA("UIPadding")
			if padding then
				local left = padding:GetStyled("PaddingLeft") :: UDim
				local right = padding:GetStyled("PaddingRight") :: UDim
				wide -= left.Offset + right.Offset + wide * (left.Scale + right.Scale)
			end
			local text = use(words)
			local font, points, spacing =
				label:GetStyled("FontFace") :: Font,
				label:GetStyled("TextSize") :: number,
				label:GetStyled("LineHeight") :: number
			if wide <= 0 or text == "" then
				serial += 1
				last = ""
				wrappedHeight:set(0)
				floorApply()
				finish()
				return
			end
			local key = `{wide}|{text}|{points}|{spacing}|{font.Family}|{font.Weight.Name}|{font.Style.Name}`
			if key == last then
				return
			end
			last = key
			serial += 1
			local ticket = serial
			finish()
			release = textMeasure.hold(label)
			local request = params
				or ((Host :: unknown) :: { GetTextBoundsParams: ({ Width: number }) -> GetTextBoundsParams }).GetTextBoundsParams({
					Width = 0,
				})
			params = request
			request.Text, request.Font, request.Size, request.Width, request.RichText =
				text, font, points, wide, label.RichText
			local function measure()
				local ok, measured = pcall(function()
					return (services.TextService :: TextService):GetTextBoundsAsync(request)
				end)
				if ok and active and alive and ticket == serial and measured.Y > 0 then
					local lineCount = math.max(1, math.round(measured.Y / points))
					local inset = label:FindFirstChildWhichIsA("UIPadding")
					local vertical = if inset
						then (inset:GetStyled("PaddingTop") :: UDim).Offset
							+ (inset:GetStyled("PaddingBottom") :: UDim).Offset
						else 0
					local height = measured.Y
						+ math.ceil((lineCount - 1) * points * (math.max(spacing, 1) - 1))
						+ vertical
					local shrinking = height < wrappedHeight:peek()
					wrappedHeight:set(height)
					floorApply()
					if shrinking then
						deferReflow()
					end
				end
				if ticket == serial then
					finish()
				end
			end
			if task and task.spawn then
				task.spawn(measure)
			else
				measure()
			end
		end)
	end
	type Parts = { free: boolean?, height: ComposeTypes.ReadOnlyValue<number>? }
	local function buildFloor(
		parts: ComposeTypes.ReadOnlyValue<Parts>,
		unitOf: (() -> ComposeTypes.ReadOnlyValue<number>) -> ()
	)
		local unitProbe: ComposeTypes.ReadOnlyValue<number>? = nil
		local makeProbe = Compose.bindOwner(function()
			unitProbe = ctx.layoutUnit(label, "TextBoundsUnit")
		end)
		local function unit(): ComposeTypes.ReadOnlyValue<number>
			if unitProbe == nil then
				makeProbe()
			end
			return assert(unitProbe)
		end
		unitOf(unit)
		local read = if services.TextService
			then textMeasure.inline(ctx, label, stable, styling, function()
				floorApply()
			end)
			else nil
		local constraint = Host.UISizeConstraint "TextBoundsFloor" {}
		local appliedMinimum, appliedMaximum = constraint.MinSize, constraint.MaxSize
		local appliedBounds: Vector2?, appliedRevision = nil, -1
		local widest, tallest, metrics = 0, 0, ""
		local previousText, updated = label.Text, false
		local previousLength = utf8.len(previousText) or #previousText
		local lastX, lastY = 0, 0
		local styled, free, single, styleKey = -1, false, false, ""
		local insetX, insetY, shareX, shareY = 0, 0, 1, 1
		local function readInsets()
			insetX, insetY, shareX, shareY = 0, 0, 1, 1
			local padding = label:FindFirstChildWhichIsA("UIPadding")
			if padding then
				local left, right = padding:GetStyled("PaddingLeft") :: UDim, padding:GetStyled("PaddingRight") :: UDim
				local top, bottom = padding:GetStyled("PaddingTop") :: UDim, padding:GetStyled("PaddingBottom") :: UDim
				insetX, insetY = left.Offset + right.Offset, top.Offset + bottom.Offset
				shareX = math.max(1 - left.Scale - right.Scale, 0.000001)
				shareY = math.max(1 - top.Scale - bottom.Scale, 0.000001)
			end
		end
		local function readStyle(mode: Enum.AutomaticSize)
			if not watchPadding then
				readInsets()
			end
			if styled == styling:peek() then
				return
			end
			styled = styling:peek()
			if watchPadding then
				readInsets()
			end
			free = label:GetStyled("TextWrapped") == false and label:GetStyled("TextTruncate") == Enum.TextTruncate.None
			single = label:GetStyled("LineHeight") == 1
			local face = label:GetStyled("FontFace") :: Font
			styleKey =
				`{face.Family}|{face.Weight.Name}|{face.Style.Name}|{label:GetStyled("TextSize")}|{label:GetStyled(
					"LineHeight"
				)}|{label.RichText}|{mode.Name}|{free}`
		end
		local function apply(use: ComposeTypes.Use?)
			if use then
				use(revision)
			end
			snapshot()
			local current = (if use then use(parts) else parts:peek())
			local wrappedHeight = current.height
			if current.free == nil and wrappedHeight == nil then
				return
			end
			local nativeBounds = if read and current.free then read(label.Text) else nil
			local mode, authoredSize = snapMode, snapSize
			local measured = nativeBounds or (if use then use(bounds) else bounds:peek())
			if nativeBounds and measured == appliedBounds and revision:peek() == appliedRevision then
				return
			end
			appliedBounds, appliedRevision = nativeBounds, revision:peek()
			local scale = if nativeBounds then 1 else (if use then use(unit()) else unit():peek())
			local glyphX, glyphY = measured.X / scale, measured.Y / scale
			readStyle(mode)
			local freeX = mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY
			local freeY = mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY
			freeX, freeY = freeX and free, freeY and free
			freeY = freeY and (nativeBounds == nil or single)
			local known = glyphX < math.huge
			freeX, freeY = freeX and known, freeY and known
			local x, y =
				if nativeBounds then glyphX else math.ceil(glyphX), if nativeBounds then glyphY else math.ceil(glyphY)
			if stable and nativeBounds == nil then
				local key = styleKey
				if key ~= metrics then
					widest, tallest, metrics = 0, 0, key
					lastX, lastY = 0, 0
					updated = false
				end
				if previousText ~= label.Text then
					local length = utf8.len(label.Text) or #label.Text
					if length == previousLength then
						widest, tallest = math.max(widest, lastX), math.max(tallest, lastY)
					else
						widest, tallest = 0, 0
					end
					previousText, previousLength, updated = label.Text, length, true
				end
				if not updated then
					widest, tallest = 0, 0
				end
				lastX, lastY = x, y
				if freeX then
					x = math.max(widest, x)
				end
				if freeY then
					y = math.max(tallest, y)
				end
			end
			x, y = (x + insetX) / shareX, (y + insetY) / shareY
			local maximum = types.Vector2.new(
				if freeX
						and glyphX > 0
						and authoredSize.X.Scale == 0
					then math.max(x, authoredSize.X.Offset)
					else math.huge,
				if freeY
						and glyphY > 0
						and authoredSize.Y.Scale == 0
					then math.max(y, authoredSize.Y.Offset)
					else math.huge
			)
			local minimum = types.Vector2.new(
				if freeX then x else 0,
				if freeY
					then y
					elseif wrappedHeight then (if use then use(wrappedHeight) else wrappedHeight:peek())
					else 0
			)
			local lower = appliedMinimum
			if maximum.X >= lower.X and maximum.Y >= lower.Y then
				if appliedMaximum ~= maximum then
					constraint.MaxSize = maximum
				end
				if lower ~= minimum then
					constraint.MinSize = minimum
				end
			else
				constraint.MinSize = minimum
				if appliedMaximum ~= maximum then
					constraint.MaxSize = maximum
				end
			end
			appliedMinimum, appliedMaximum = minimum, maximum
		end
		if services.TextService then
			floorApply = function()
				apply(nil)
			end
			Compose.cleanup(function()
				floorApply = function() end
			end)
			apply(nil)
		else
			Compose.watch(apply)
		end
		floor = constraint
		constraint.Parent = label
		Compose.cleanup(function()
			if floor == constraint then
				floor = nil
			end
			constraint:Destroy()
		end)
	end
	if label:FindFirstChildWhichIsA("UISizeConstraint") == nil then
		local overridden = false
		local kind = "none"
		local scope: { dispose: () -> () }? = nil
		local inner: { dispose: () -> () }? = nil
		local parts = Compose.cell({} :: Parts)
		local unit: (() -> ComposeTypes.ReadOnlyValue<number>)? = nil
		local function release()
			local measuring, current = inner, scope
			inner, scope = nil, nil
			if measuring then
				measuring.dispose()
			end
			if current then
				current.dispose()
			end
		end
		refloor = function()
			local next = "none"
			if not overridden and alive then
				local wrapped = label:GetStyled("TextWrapped")
				if wrapped == false and label:GetStyled("TextTruncate") == Enum.TextTruncate.None then
					next = "free"
				elseif services.TextService ~= nil and wrapped == true then
					next = "wrapped"
				end
			end
			if next == kind then
				return
			end
			kind = next
			if next == "none" then
				release()
				parts:set({})
				return
			end
			if inner then
				local measuring = inner
				inner = nil
				measuring.dispose()
			end
			if scope == nil then
				parts:set(if next == "free" then { free = true } else {})
				scope = Compose.createRootOwner(function()
					buildFloor(parts, function(probe: () -> ComposeTypes.ReadOnlyValue<number>)
						unit = probe
					end)
				end, runtime.reactor)
			end
			if next == "wrapped" then
				inner = Compose.createRootOwner(function()
					local height = Compose.cell(0)
					buildWrapped(height, assert(unit))
					parts:set({ height = height })
					floorApply()
				end, runtime.reactor)
			elseif not parts:peek().free then
				parts:set({ free = true })
				floorApply()
			end
		end
		local added = label.ChildAdded:Connect(function(child: Instance)
			if child ~= floor and child:IsA("UISizeConstraint") and not overridden then
				overridden = true
				refloor()
			end
		end)
		Compose.cleanup(function()
			added:Disconnect()
			release()
		end)
		refloor()
	end
	Compose.cleanup(function()
		alive = false
		styled:Disconnect()
		changed:Disconnect()

		if pending then
			pending:Disconnect()
			pending = nil
		end
	end)
end

return function(
	ctx: Shared.Context,
	config: Shared.Config,
	services: Shared.Services,
	themes: Theme.Themes,
	live: (unknown) -> boolean
)
	local Compose, runtime, types, Host = ctx.Compose, ctx.runtime, ctx.types, ctx.Host
	local Enum = types.Enum
	local layout = layoutKit.attach(ctx)
	function ctx.textLayout(label: TextLabel | TextButton, stable: boolean?, watchPadding: boolean?)
		attachLayout(ctx, label, stable, watchPadding)
	end
	function ctx.padding(horizontal: number, vertical: number): UIPadding
		local sides: Shared.Sides = { top = vertical, right = horizontal, bottom = vertical, left = horizontal }
		return assert(layout.insets(sides))
	end
	function ctx.round(use: ComposeTypes.Use?, radius: UDim?): UDim
		return if ctx.metric("radii.pill", use) > 0 then radius or types.UDim.new(1, 0) else types.UDim.new(0, 0)
	end
	function ctx.corner(radius: number?): UICorner
		if radius == nil then
			return Host.UICorner({})
		end
		return Host.UICorner({
			CornerRadius = function(use: ComposeTypes.Use): UDim
				return ctx.round(use, types.UDim.new(0, radius))
			end,
		})
	end
	function ctx.layoutUnit(parent: GuiBase2d, name: string?): ComposeTypes.ReadOnlyValue<number>
		local _, probe = runtime.mount(function()
			return Host.Frame(name or "LayoutUnit")({ Size = types.UDim2.fromOffset(100, 1), Visible = false })
		end, parent)
		local size = ctx.observe.AbsoluteSize(probe :: GuiObject)
		return Compose.formula(function(use: ComposeTypes.Use): number
			local unit = use(size).X / 100
			return if unit > 0 then unit else 1
		end)
	end
	function ctx.layoutSize(
		node: GuiBase2d,
		unit: ComposeTypes.ReadOnlyValue<number>?
	): ComposeTypes.ReadOnlyValue<Vector2>
		local size, unit = ctx.observe.AbsoluteSize(node), unit or ctx.layoutUnit(node)
		return Compose.formula(function(use: ComposeTypes.Use): Vector2
			return use(size) / use(unit)
		end)
	end
	function ctx.layoutBounds(
		label: TextLabel | TextButton | TextBox,
		unit: ComposeTypes.ReadOnlyValue<number>?
	): ComposeTypes.ReadOnlyValue<Vector2>
		local bounds, unit = ctx.observe.TextBounds(label), unit or ctx.layoutUnit(label)
		return Compose.formula(function(use: ComposeTypes.Use): Vector2
			return use(bounds) / use(unit)
		end)
	end
	function ctx.text(properties: Shared.TextLabelNativeProps?, stable: boolean?): TextLabel
		local native: Shared.TextLabelNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			Size = types.UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextXAlignment = Enum.TextXAlignment.Left,
		}
		local fields = native :: { [unknown]: unknown }
		for key, value in (properties or {}) :: { [unknown]: unknown } do
			fields[key] = value
		end
		local label = ctx.styled(Host.TextLabel(native), "Text")

		if label.AutomaticSize == Enum.AutomaticSize.None then
			local attach = Compose.bindOwner(function()
				attachLayout(ctx, label, stable)
			end)
			local stop: ComposeTypes.Dispose?
			stop = Compose.cleanup(assert(runtime.host.observation).observeProperty(label, "AutomaticSize", function()
				if label.AutomaticSize ~= Enum.AutomaticSize.None then
					local detach = stop
					stop = nil
					if detach then
						detach()
					end
					attach()
				end
			end))
		else
			attachLayout(ctx, label, stable)
		end

		return label
	end
	function ctx.row(children: { ComposeTypes.Child }, properties: Shared.FrameNativeProps?): Frame
		return layout.stack(children, properties, { gap = 8 }, false)
	end
	function ctx.column(children: { ComposeTypes.Child }, properties: Shared.FrameNativeProps?): Frame
		return layout.stack(children, properties, { gap = 8 }, true)
	end
	function ctx.listRow(parts: Shared.ListRow): (Frame, Shared.Input<UDim2>, (GuiObject) -> ())
		for _, caption in parts.captions do
			if caption.Name == "Description" then
				caption:AddTag("facet-secondary")
			end
			if caption:IsA("TextLabel") then
				caption.Size = types.UDim2.fromScale(1, 0)
				caption.AutomaticSize = Enum.AutomaticSize.Y
				caption.TextWrapped = true
			end
		end
		local columns: { ComposeTypes.Child } = table.clone(parts.leading or {})
		table.insert(
			columns,
			ctx.column(parts.captions, {
				Name = "Captions",
				Size = types.UDim2.new(0, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.Fill }),
			})
		)
		table.move(parts.trailing or {}, 1, #(parts.trailing or {}), #columns + 1, columns)
		local content = ctx.row(columns, {
			Name = "Content",
			ZIndex = 1,
			Size = types.UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			AnchorPoint = if parts.described then types.Vector2.zero else types.Vector2.new(0, 0.5),
			Position = types.UDim2.fromScale(0, if parts.described then 0 else 0.5),
		})
		assert(content:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = Enum.VerticalAlignment.Center
		local rung: Shared.Input<Shared.ControlSize?>? = parts.controlSize
		local function height(use: ComposeTypes.Use?): UDim2
			return types.UDim2.new(1, 0, 0, ctx.controlSize(rung, "height", use))
		end
		local size = if live(config.theme) or live(rung) then height else height()
		return content,
			size,
			function(node: GuiObject)
				node:AddTag("facet-list-row")
				local captions = assert(content:FindFirstChild("Captions")) :: GuiObject
				local wraps = node.AutomaticSize
				local function hug()
					local parent = node.Parent
					local automatic = if parent and parent:IsA("GuiObject") then parent.AutomaticSize else nil
					local hugging = automatic == Enum.AutomaticSize.X or automatic == Enum.AutomaticSize.XY
					local across = if hugging then Enum.AutomaticSize.XY else Enum.AutomaticSize.Y
					node.AutomaticSize = if hugging then Enum.AutomaticSize.XY else wraps
					content.AutomaticSize, captions.AutomaticSize = across, across
					for _, caption in parts.captions do
						if caption:IsA("TextLabel") then
							caption.Size = types.UDim2.fromScale(if hugging then 0 else 1, 0)
							caption.AutomaticSize = across
						end
					end
				end
				runtime.connect(node, "AncestryChanged", hug)
				hug()
				local function tagRung(use: ComposeTypes.Use?)
					local current = ctx.read(rung, use)
					for _, name in { "xsmall", "compact", "regular", "large" } do
						if current == name then
							node:AddTag("facet-size-" .. name)
						elseif node:HasTag("facet-size-" .. name) then
							node:RemoveTag("facet-size-" .. name)
						end
					end
				end
				if live(rung) then
					Compose.watch(tagRung)
				else
					tagRung()
				end
			end
	end
	function ctx.iconVaries(name: Shared.Input<string>?): boolean
		if name == nil then
			return false
		end
		if live(name) or live(config.theme) or live(config.icons) then
			return true
		end
		local requested = name :: string
		if requested == "" or string.match(requested, "^rbx") then
			return false
		end
		local package: Theme.IconRegistry = ctx.read(config.theme) or {}
		local overrides = ctx.read(config.icons)
		if overrides then
			package = table.clone(package)
			package.icons = overrides
		end
		local resting = themes.resolveIcon(package, requested, "default")
		return themes.resolveIcon(package, requested, "hover") ~= resting
			or themes.resolveIcon(package, requested, "pressed") ~= resting
			or themes.resolveIcon(package, requested, "selected") ~= resting
			or themes.resolveIcon(package, requested, "disabled") ~= resting
	end
	function ctx.icon(
		name: Shared.Input<string>,
		properties: Shared.ImageLabelNativeProps?,
		state: Shared.Input<Theme.SkinState>?
	): ImageLabel
		local function image(use: ComposeTypes.Use?): string
			local requested = ctx.read(name, use)
			if requested == "" then
				return ""
			end
			local package: Theme.IconRegistry = ctx.read(config.theme, use) or {}
			local overrides = ctx.read(config.icons, use)
			if overrides then
				package = table.clone(package)
				package.icons = overrides
			end
			local asset = if type(requested) == "string" and string.match(requested, "^rbx")
				then requested
				else themes.resolveIcon(package, requested, ctx.read(state, use))
			assert(type(asset) == "string", `Facet icon {tostring(requested)} requires an image asset`)
			return asset
		end
		local native: Shared.ImageLabelNativeProps = {
			Image = if live(name) or live(config.theme) or live(config.icons) or live(state) then image else image(),
			BackgroundTransparency = 1,
		}
		local function iconSize(use: ComposeTypes.Use?): UDim2
			local size = ctx.controlSize(config.controlSize, "iconSize", use)
			return types.UDim2.fromOffset(size, size)
		end
		local function resample(use: ComposeTypes.Use?): Enum.ResamplerMode
			local package = ctx.read(config.theme, use)
			return if package and package.identity.rendering == "pixel"
				then Enum.ResamplerMode.Pixelated
				else Enum.ResamplerMode.Default
		end
		local themeLive = live(config.theme)
		native.Size = if themeLive or live(config.controlSize) then iconSize else iconSize()
		if themeLive then
			native.ResampleMode = resample
		elseif resample() ~= Enum.ResamplerMode.Default then
			native.ResampleMode = resample()
		end
		local fields = native :: { [unknown]: unknown }
		for key, value in (properties or {}) :: { [unknown]: unknown } do
			fields[key] = value
		end
		return ctx.styled(Host.ImageLabel(native), "Icon")
	end
end

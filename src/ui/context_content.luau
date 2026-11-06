--!strict
local dataModel = require("./ambient")
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Theme = require("./theme_types")
local standardIcons = require("./icons")
local layoutKit = require("./layout_kit")
local textMeasure = require("./text_measure")
local NATIVE_KEYS = table.freeze({ "ref" })

type Geometry = { apply: () -> (), frame: number }

local geometryQueue: { [() -> ()]: Geometry } = {}
local geometryStop: (() -> ())? = nil
local geometryFrame = 0

local function flushGeometry()
	geometryFrame += 1
	local settled: { [() -> ()]: Geometry } = {}
	for sample, entry in geometryQueue do
		if entry.frame < geometryFrame - 1 then
			settled[sample] = entry
		end
	end
	for sample in settled do
		geometryQueue[sample] = nil
		sample()
	end
	for _, entry in settled do
		entry.apply()
	end
	if next(geometryQueue) == nil and geometryStop then
		local stop = geometryStop
		geometryStop = nil
		stop()
	end
end

local function attachMeasuredLayout(
	ctx: Shared.Context,
	label: TextLabel | TextButton,
	stable: boolean?,
	watchPadding: boolean?,
	lazy: boolean?,
	warm: boolean?,
	priorText: string?,
	previousFace: Font?,
	previousSize: number?
)
	local Compose, runtime, types, Host = ctx.Compose, ctx.runtime, ctx.types, ctx.Host
	local Enum, services = types.Enum, ctx.config.services
	local snapMode, snapSize = label.AutomaticSize, label.Size
	local wrapped: boolean? = nil
	local function isWrapped(): boolean
		if wrapped == nil then
			wrapped = label:GetStyled("TextWrapped") == true
		end
		return wrapped == true
	end
	local styling: textMeasure.Style? = nil
	local function textStyle(): textMeasure.Style
		local style = styling
		if style then
			return style
		end
		local face = assert(previousFace)
		local size = assert(previousSize)
		local wrapped = isWrapped()
		local truncate: Enum.TextTruncate = label:GetStyled("TextTruncate")
		local lineHeight: number = label:GetStyled("LineHeight")
		local rich = label.RichText
		local measured: textMeasure.Style = {
			face = face,
			size = size,
			rich = rich,
			wrapped = wrapped,
			truncate = truncate,
			lineHeight = lineHeight,
			key = `{face.Family}|{face.Weight.Name}|{face.Style.Name}|{size}|{rich}|{snapMode.Name}|{wrapped}|{truncate}|{lineHeight}`,
		}
		styling = measured
		return measured
	end
	local frames = services.RunService
	local pending: RBXScriptConnection? = nil
	local floor: UISizeConstraint? = nil
	local alive = true
	local refreshing = false
	local textChanged = not lazy
	local refloor: () -> () = function() end
	local function measuredFloor(): boolean
		return services.TextService ~= nil and floor ~= nil
	end
	local function reflow(metrics: boolean?)
		local automatic = snapMode
		if automatic ~= Enum.AutomaticSize.None then
			refreshing = true
			local style = textStyle()
			local face, points = style.face, style.size
			local resetFace, resetSize =
				metrics == true and label.FontFace ~= face, metrics == true and label.TextSize ~= points
			if resetFace then
				label.FontFace = face
			end
			if resetSize then
				label.TextSize = points
			end
			label.AutomaticSize = Enum.AutomaticSize.None
			label.AutomaticSize = automatic
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
		if pending == nil and frames and alive and not refreshing and snapMode ~= Enum.AutomaticSize.None then
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
		local face: Font = label:GetStyled("FontFace")
		local points: number = label:GetStyled("TextSize")
		local changed = previousFace ~= nil or previousSize ~= nil
		local moved = face ~= previousFace or points ~= previousSize
		previousFace, previousSize = face, points
		if alive and not textChanged and (face ~= label.FontFace or points ~= label.TextSize) then
			textChanged = true
			refloor()
		end
		if alive and changed and moved then
			reflow()
			deferReflow()
		end
	end
	local revision = Compose.cell(0)
	local framed = services.RunService ~= nil and dataModel() ~= nil
	local box = label.AbsoluteSize
	local bounds = Compose.cell(label.TextBounds)
	local frameSource = runtime.host.frames
	local checkStale: () -> () = function() end
	local sizeMoved, boundsMoved = false, false
	textChanged = textChanged or (warm == true and not framed)
	local sampledBounds: Vector2? = nil
	local function sampleGeometry()
		if alive then
			if sizeMoved then
				box = label.AbsoluteSize
			end
			if boundsMoved then
				sampledBounds = label.TextBounds
			end
			sizeMoved, boundsMoved = false, false
		end
	end
	local function applyGeometry()
		if alive then
			local glyph = sampledBounds
			sampledBounds = nil
			if glyph then
				bounds:set(glyph)
			end
			if warm and not textChanged then
				textChanged = true
				refloor()
			end
			checkStale()
		end
	end
	local function geometryChanged(property: string)
		local frames = frameSource
		if property == "AbsoluteSize" then
			sizeMoved = true
		else
			boundsMoved = true
		end
		if not framed or frames == nil then
			sampleGeometry()
			applyGeometry()
			return
		end
		local entry = geometryQueue[sampleGeometry]
		if entry then
			entry.frame = geometryFrame
		else
			geometryQueue[sampleGeometry] = { apply = applyGeometry, frame = geometryFrame }
		end
		if geometryStop == nil then
			geometryStop = frames.onFrame(flushGeometry)
		end
	end
	local currentText = label.Text
	local priorText = priorText or currentText
	local floorApply: () -> () = function() end
	local function invalidate(metrics: boolean?)
		if not refreshing then
			styling, wrapped = nil, nil
			if metrics == true then
				refreshMetrics()
			end
			revision:set(revision:peek() + 1)
			refloor()
			floorApply()
			checkStale()
		end
	end
	local function styleChanged()
		invalidate(true)
	end
	local styled = label.StyledPropertiesChanged:Connect(styleChanged)
	local changed = label.Changed:Connect(function(property: string)
		if property == "FontFace" or property == "TextSize" then
			styleChanged()
		elseif property == "AbsoluteSize" or property == "TextBounds" then
			geometryChanged(property)
		elseif property == "Text" then
			priorText, currentText = currentText, label.Text
			if not textChanged then
				textChanged = true
				refloor()
			end
			floorApply()
			if not measuredFloor() and previousSize ~= nil and label.TextSize ~= previousSize then
				deferReflow()
			end
		elseif property == "AutomaticSize" then
			if not refreshing then
				snapMode = label.AutomaticSize
				invalidate()
			end
		elseif property == "Size" then
			snapSize = label.Size
			invalidate()
		elseif
			property == "TextWrapped"
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
		local glyph, mode = bounds:peek(), snapMode
		local freeX = mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY
		local freeY = mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY
		local measured = measuredFloor()
		local stale = (measured or services.TextService ~= nil)
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
			if not measured and not textChanged and services.TextService ~= nil then
				textChanged = true
				refloor()
			end
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
		local prepare = textMeasure.prepare(ctx)
		local function finish()
			if release then
				release()
				release = nil
			end
		end
		local words = runtime.observe(label, "Text", if framed then { frame = true } else nil)
		local wrappedSize = runtime.observe(label, "AbsoluteSize", if framed then { frame = true } else nil)
		Compose.cleanup(function()
			active = false
			finish()
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(revision)
			local mode = snapMode
			if not isWrapped() or not (mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY) then
				serial += 1
				last = ""
				wrappedHeight:set(0)
				floorApply()
				finish()
				return
			end
			local size = use(wrappedSize)
			assert(typeof(size) == "Vector2")
			local wide = size.X / use(unit())
			local padding = label:FindFirstChildWhichIsA("UIPadding")
			if padding then
				local left: UDim = padding:GetStyled("PaddingLeft")
				local right: UDim = padding:GetStyled("PaddingRight")
				wide -= left.Offset + right.Offset + wide * (left.Scale + right.Scale)
			end
			local text = use(words)
			assert(type(text) == "string")
			local style = textStyle()
			local font, points, spacing = style.face, style.size, style.lineHeight
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
			local request = prepare(text, style.rich, font, points, wide)
			local service = assert(services.TextService)
			local function measure()
				local ok, measured = pcall(function()
					return service:GetTextBoundsAsync(request)
				end)
				if ok and active and alive and ticket == serial and measured.Y > 0 then
					local lineCount = math.max(1, math.round(measured.Y / points))
					local inset = label:FindFirstChildWhichIsA("UIPadding")
					local vertical = 0
					if inset then
						local top: UDim = inset:GetStyled("PaddingTop")
						local bottom: UDim = inset:GetStyled("PaddingBottom")
						vertical = top.Offset + bottom.Offset
					end
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
			then textMeasure.inline(ctx, label, stable, textStyle, function()
				floorApply()
			end)
			else nil
		if read and stable and priorText ~= currentText then
			read(priorText)
		end
		local constraint = Host.UISizeConstraint "TextBoundsFloor" {}
		local appliedMinimum, appliedMaximum = constraint.MinSize, constraint.MaxSize
		local appliedBounds: Vector2?, appliedRevision = nil, -1
		local widest, tallest, metrics = 0, 0, ""
		local previousText, updated = currentText, false
		local previousLength = utf8.len(previousText) or #previousText
		local lastX, lastY = 0, 0
		local insetX, insetY, shareX, shareY = 0, 0, 1, 1
		local function readInsets()
			insetX, insetY, shareX, shareY = 0, 0, 1, 1
			local padding = label:FindFirstChildWhichIsA("UIPadding")
			if padding then
				local left: UDim = padding:GetStyled("PaddingLeft")
				local right: UDim = padding:GetStyled("PaddingRight")
				local top: UDim = padding:GetStyled("PaddingTop")
				local bottom: UDim = padding:GetStyled("PaddingBottom")
				insetX, insetY = left.Offset + right.Offset, top.Offset + bottom.Offset
				shareX = math.max(1 - left.Scale - right.Scale, 0.000001)
				shareY = math.max(1 - top.Scale - bottom.Scale, 0.000001)
			end
		end
		local function apply(use: ComposeTypes.Use?)
			if use then
				use(revision)
			end
			local current = (if use then use(parts) else parts:peek())
			local wrappedHeight = current.height
			if current.free == nil and wrappedHeight == nil then
				return
			end
			local nativeBounds = if read and current.free then read(currentText) else nil
			local mode, authoredSize = snapMode, snapSize
			local measured = nativeBounds or (if use then use(bounds) else bounds:peek())
			if nativeBounds and measured == appliedBounds and revision:peek() == appliedRevision then
				return
			end
			if not watchPadding or appliedRevision ~= revision:peek() then
				readInsets()
			end
			appliedBounds, appliedRevision = nativeBounds, revision:peek()
			local scale = if nativeBounds then 1 else (if use then use(unit()) else unit():peek())
			local glyphX, glyphY = measured.X / scale, measured.Y / scale
			local style = textStyle()
			local free = not style.wrapped and style.truncate == Enum.TextTruncate.None
			local freeX = mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY
			local freeY = mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY
			freeX, freeY = freeX and free, freeY and free
			freeY = freeY and (nativeBounds == nil or style.lineHeight == 1)
			local known = glyphX < math.huge
			freeX, freeY = freeX and known, freeY and known
			local x, y =
				if nativeBounds then glyphX else math.ceil(glyphX), if nativeBounds then glyphY else math.ceil(glyphY)
			if stable and nativeBounds == nil then
				local key = style.key
				if key ~= metrics then
					widest, tallest, metrics = 0, 0, key
					lastX, lastY = 0, 0
					updated = false
				end
				if previousText ~= currentText then
					local length = utf8.len(currentText) or #currentText
					if length == previousLength then
						widest, tallest = math.max(widest, lastX), math.max(tallest, lastY)
					else
						widest, tallest = 0, 0
					end
					previousText, previousLength, updated = currentText, length, true
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
			local maximumX = if freeX
					and glyphX > 0
					and authoredSize.X.Scale == 0
				then math.max(x, authoredSize.X.Offset)
				else math.huge
			local maximumY = if freeY
					and glyphY > 0
					and authoredSize.Y.Scale == 0
				then math.max(y, authoredSize.Y.Offset)
				else math.huge
			local minimumX = if freeX then x else 0
			local minimumY = if freeY
				then y
				elseif wrappedHeight then (if use then use(wrappedHeight) else wrappedHeight:peek())
				else 0
			local maximum = if appliedMaximum.X == maximumX and appliedMaximum.Y == maximumY
				then appliedMaximum
				else types.Vector2.new(maximumX, maximumY)
			local minimum = if appliedMinimum.X == minimumX and appliedMinimum.Y == minimumY
				then appliedMinimum
				else types.Vector2.new(minimumX, minimumY)
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
		local initial: Parts = {}
		local parts = Compose.cell(initial)
		local unit: (() -> ComposeTypes.ReadOnlyValue<number>)? = nil
		local ownFloor = Compose.bindOwner(function(body: (ComposeTypes.Owner) -> ()): ComposeTypes.RootScope
			return Compose.createRootOwner(body, runtime.reactor)
		end)
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
				local measuring = services.TextService ~= nil
				if measuring and isWrapped() then
					next = "wrapped"
				elseif
					(textChanged or not measuring)
					and not isWrapped()
					and textStyle().truncate == Enum.TextTruncate.None
				then
					next = "free"
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
				scope = ownFloor(function()
					buildFloor(parts, function(probe: () -> ComposeTypes.ReadOnlyValue<number>)
						unit = probe
					end)
				end)
			end
			if next == "wrapped" then
				inner = ownFloor(function()
					local height = Compose.cell(0)
					buildWrapped(height, assert(unit))
					parts:set({ height = height })
					floorApply()
				end)
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

local function attachLayout(
	ctx: Shared.Context,
	label: TextLabel | TextButton,
	stable: boolean?,
	watchPadding: boolean?,
	lazy: boolean?,
	warm: boolean?
)
	if lazy and not warm and ctx.config.services.TextService and label:GetStyled("TextWrapped") ~= true then
		local face: Font = label:GetStyled("FontFace")
		local size: number = label:GetStyled("TextSize")
		if face == label.FontFace and size == label.TextSize then
			local Compose, E = ctx.Compose, ctx.types.Enum
			local owner = assert(Compose.currentOwner())
			local text = label.Text
			local changed: RBXScriptConnection?, styled: RBXScriptConnection?
			local checking = false
			local function release()
				if changed then
					changed:Disconnect()
					changed = nil
				end
				if styled then
					styled:Disconnect()
					styled = nil
				end
			end
			local function start(...: string)
				local property: string? = ...
				if checking then
					return
				end
				if property == nil or property == "AbsoluteSize" or property == "TextBounds" then
					checking = true
					local mode, glyph, box = label.AutomaticSize, label.TextBounds, label.AbsoluteSize
					local freeX = mode == E.AutomaticSize.X or mode == E.AutomaticSize.XY
					local freeY = mode == E.AutomaticSize.Y or mode == E.AutomaticSize.XY
					local stale = freeX
						and glyph.X > 0
						and glyph.Y > 0
						and glyph.X <= box.X
						and glyph.Y <= box.Y
						and not label.TextFits
					local overflow = box.X > 0
						and box.Y > 0
						and (stale or (freeX and glyph.X > box.X) or (freeY and glyph.Y > box.Y))
					checking = false
					if
						not overflow
						and (
							property ~= nil
							or (
								label:GetStyled("TextWrapped") ~= true
								and label:GetStyled("FontFace") == face
								and label:GetStyled("TextSize") == size
							)
						)
					then
						return
					end
				elseif
					property ~= "Text"
					and property ~= "FontFace"
					and property ~= "TextSize"
					and property ~= "AutomaticSize"
					and property ~= "Size"
					and property ~= "TextWrapped"
					and property ~= "TextTruncate"
					and property ~= "LineHeight"
					and property ~= "RichText"
				then
					return
				end
				release()
				Compose.withOwner(owner, function()
					attachMeasuredLayout(ctx, label, stable, watchPadding, property ~= "Text", warm, text, face, size)
				end)
			end
			local laidOut = ctx.afterLayout(function()
				if changed then
					start("AbsoluteSize")
				end
			end)
			changed = label.Changed:Connect(function(property: string)
				if property == "AbsoluteSize" or property == "TextBounds" then
					laidOut()
				else
					start(property)
				end
			end)
			styled = label.StyledPropertiesChanged:Connect(start)
			Compose.cleanup(release)
			start("AbsoluteSize")
			return
		end
	end
	attachMeasuredLayout(ctx, label, stable, watchPadding, lazy, warm)
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
	local function textDefaultsFor(size: UDim2): Shared.TextLabelNativeProps
		return {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			Size = size,
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
		}
	end
	local textDefaults = textDefaultsFor(types.UDim2.fromScale(1, 0))
	local huggingDefaults = textDefaultsFor(types.UDim2.fromOffset(0, 0))
	local ROLE_PREFIX = "facet-type-"
	local function applyRole(node: Instance, value: Shared.TextRole?)
		local name = value or "body"
		assert(table.find(themes.TYPE_ROLES, name) ~= nil, `Facet text: unknown type role {name}`)
		local wanted = ROLE_PREFIX .. name
		for _, tag in node:GetTags() do
			if tag ~= wanted and string.sub(tag, 1, #ROLE_PREFIX) == ROLE_PREFIX then
				node:RemoveTag(tag)
			end
		end
		if not node:HasTag(wanted) then
			node:AddTag(wanted)
		end
	end
	function ctx.textRole(node: Instance, role: Shared.Input<Shared.TextRole>?)
		if Compose.isValue(role) or type(role) == "function" then
			Compose.watch(function(use: ComposeTypes.Use)
				applyRole(node, ctx.read<<Shared.TextRole?>>(role, use))
			end)
		else
			applyRole(node, role :: Shared.TextRole?)
		end
	end
	local layout = layoutKit.attach(ctx)
	function ctx.textLayout(label: TextLabel | TextButton, stable: boolean?, watchPadding: boolean?, lazy: boolean?)
		attachLayout(ctx, label, stable, watchPadding, lazy)
	end
	function ctx.padding(horizontal: number, vertical: number): UIPadding
		local sides: Shared.Sides = { top = vertical, right = horizontal, bottom = vertical, left = horizontal }
		return assert(layout.insets(sides))
	end
	function ctx.round(use: ComposeTypes.Use?, ...: UDim?): UDim
		local radius = ...
		return if ctx.metric("radii.pill", use) > 0 then radius or types.UDim.new(1, 0) else types.UDim.new(0, 0)
	end
	function ctx.corner(radius: number?): UICorner
		if radius == nil then
			return Host.UICorner {}
		end
		return Host.UICorner {
			CornerRadius = function(use: ComposeTypes.Use): UDim
				return ctx.round(use, types.UDim.new(0, radius))
			end,
		}
	end
	function ctx.layoutUnit(parent: GuiBase2d, name: string?): ComposeTypes.ReadOnlyValue<number>
		local probe: Frame? = nil
		runtime.mount(function()
			probe = Host.Frame(name or "LayoutUnit")({ Size = types.UDim2.fromOffset(100, 1), Visible = false })
			return probe
		end, parent)
		local size = ctx.observe.AbsoluteSize(assert(probe))
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
	function ctx.text(
		properties: Shared.TextLabelNativeProps?,
		stable: boolean?,
		role: Shared.Input<Shared.TextRole>?
	): TextLabel
		local given: Shared.TextLabelNativeProps = properties or {}
		assert(
			role == nil or given.TextSize == nil,
			"Facet text: pick the size with a type role or with a pixel TextSize, not both"
		)
		local automatic = given.AutomaticSize
		local defaults = if automatic == nil or automatic == Enum.AutomaticSize.Y then textDefaults else huggingDefaults
		local native = ctx.props<<Shared.TextLabelNativeProps>>(given, NATIVE_KEYS, defaults)
		local bound = Compose.isValue(native.Text) or type(native.Text) == "function"
		local label = ctx.styled(Host.TextLabel(native), "Text")
		if given.TextSize == nil then
			ctx.textRole(label, role)
		end

		if label.AutomaticSize == Enum.AutomaticSize.None then
			local attach = Compose.bindOwner(function()
				attachLayout(ctx, label, stable, nil, true, bound)
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
			attachLayout(ctx, label, stable, nil, true, bound)
		end

		return label
	end
	function ctx.clampLines(label: TextLabel, lines: number)
		local styledSize = ctx.observeStyled.TextSize(label)
		local styledLine = ctx.observeStyled.LineHeight(label)
		runtime.mount(function()
			return Host.UISizeConstraint {
				Name = "LineClamp",
				MaxSize = function(use: ComposeTypes.Use): Vector2
					local inset = label:FindFirstChildWhichIsA("UIPadding")
					local vertical = if inset then inset.PaddingTop.Offset + inset.PaddingBottom.Offset else 0
					return types.Vector2.new(math.huge, math.ceil(lines * use(styledSize) * use(styledLine)) + vertical)
				end,
			}
		end, label)
	end
	function ctx.row(children: Shared.ChildList, properties: Shared.FrameNativeProps?): Frame
		return layout.stack(children, properties, { gap = 8 }, false)
	end
	function ctx.column(children: Shared.ChildList, properties: Shared.FrameNativeProps?): Frame
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
				Host.UIFlexItem { FlexMode = Enum.UIFlexMode.Fill },
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
		for _, child in parts.trailing or {} do
			if typeof(child) == "Instance" and child:IsA("TextLabel") then
				child.TextWrapped = true
				child.TextTruncate = Enum.TextTruncate.None
				local room = ctx.layoutSize(content)
				runtime.mount(function()
					return Host.UISizeConstraint "TrailingBounds" {
						MaxSize = function(use: ComposeTypes.Use): Vector2
							return types.Vector2.new(math.max(0, use(room).X / 2), math.huge)
						end,
					}
				end, child)
			end
		end
		local rung: Shared.Input<Shared.ControlSize?>? = parts.controlSize
		local function height(use: ComposeTypes.Use?): UDim2
			return types.UDim2.new(1, 0, 0, ctx.controlSize(rung, "height", use))
		end
		local size = if live(config.theme) or live(rung) then height else height()
		return content,
			size,
			function(node: GuiObject)
				node:AddTag("facet-list-row")
				local captions = content:FindFirstChild("Captions")
				assert(captions and captions:IsA("GuiObject"))
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
		local requested: string = ctx.read<<string>>(name)
		if requested == "" or string.match(requested, "^rbx") then
			return false
		end
		local package: Theme.IconRegistry = ctx.read<<Theme.ReadOnlyThemePackage?>>(config.theme) or {}
		local overrides = ctx.read<<{ [string]: Theme.IconEntry }?>>(config.icons)
		if overrides then
			package = { icons = overrides, assets = package.assets }
		end
		local resting = themes.resolveIcon(package, requested, "default")
		return themes.resolveIcon(package, requested, "hover") ~= resting
			or themes.resolveIcon(package, requested, "pressed") ~= resting
			or themes.resolveIcon(package, requested, "selected") ~= resting
			or themes.resolveIcon(package, requested, "disabled") ~= resting
	end
	function ctx.icon(
		name: Shared.Input<string?>,
		properties: Shared.ImageLabelNativeProps?,
		state: Shared.Input<Theme.SkinState>?
	): ImageLabel
		local function image(use: ComposeTypes.Use?): string
			local requested = ctx.read<<string?>>(name, use)
			if requested == nil or requested == "" then
				return ""
			end
			local package: Theme.IconRegistry = ctx.read<<Theme.ReadOnlyThemePackage?>>(config.theme, use) or {}
			local overrides = ctx.read<<{ [string]: Theme.IconEntry }?>>(config.icons, use)
			if overrides then
				package = { icons = overrides, assets = package.assets }
			end
			local asset = if type(requested) == "string" and string.match(requested, "^rbx")
				then requested
				else themes.resolveIcon(package, requested, ctx.read<<Theme.SkinState?>>(state, use))
			if asset == nil and standardIcons.registered(requested) then
				return ""
			end
			assert(type(asset) == "string", `Facet icon {tostring(requested)} requires an image asset`)
			return asset
		end
		local native: Shared.ImageLabelProps = {
			Image = if live(name) or live(config.theme) or live(config.icons) or live(state) then image else image(),
			BackgroundTransparency = 1,
		}
		local function iconSize(use: ComposeTypes.Use?): UDim2
			local size = ctx.controlSize(config.controlSize, "iconSize", use)
			return types.UDim2.fromOffset(size, size)
		end
		local function resample(use: ComposeTypes.Use?): Enum.ResamplerMode
			local package = ctx.read<<Theme.ReadOnlyThemePackage?>>(config.theme, use)
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
		return ctx.styled(Host.ImageLabel(ctx.props(properties or {}, NATIVE_KEYS, native)), "Icon")
	end
end

--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local decoration = require("./native_decoration")

export type Reach = { meets: { [string]: boolean }, glass: { [string]: number } }
type Lease = { count: number, clipped: boolean }

local SIDES = { "top", "left", "bottom", "right" }
local leases = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [ScreenGui]: Lease }

local function apart(): Reach
	return {
		meets = { top = false, left = false, bottom = false, right = false },
		glass = { top = 0, left = 0, bottom = 0, right = 0 },
	}
end

local function same(a: Reach, b: Reach): boolean
	for _, side in SIDES do
		if a.meets[side] ~= b.meets[side] or a.glass[side] ~= b.glass[side] then
			return false
		end
	end
	return true
end

local function bands(ctx: Types.Context, service: GuiService, screen: ScreenGui): (Vector2, Vector2)
	local E, V2 = ctx.types.Enum, ctx.types.Vector2
	if service.GetInsetArea then
		local ok, full, content = pcall(function(): (Rect, Rect)
			return service:GetInsetArea(E.ScreenInsets.None), service:GetInsetArea(screen.ScreenInsets)
		end)
		if ok and typeof(full) == "Rect" and typeof(content) == "Rect" then
			return content.Min - full.Min, full.Max - content.Max
		end
	end
	if not screen.IgnoreGuiInset and screen.ScreenInsets == E.ScreenInsets.CoreUISafeInsets then
		local ok, topLeft, bottomRight = pcall(service.GetGuiInset, service)
		if ok and typeof(topLeft) == "Vector2" then
			return topLeft, if typeof(bottomRight) == "Vector2" then bottomRight else V2.zero
		end
	end
	return V2.zero, V2.zero
end

local function margins(frame: GuiObject, screen: ScreenGui): { [string]: number }?
	local at, box = frame.AbsolutePosition, frame.AbsoluteSize
	local start, bounds = screen.AbsolutePosition, screen.AbsoluteSize
	if box.X <= 0 or box.Y <= 0 or bounds.X <= 0 or bounds.Y <= 0 then
		return nil
	end
	return {
		top = at.Y - start.Y,
		left = at.X - start.X,
		bottom = start.Y + bounds.Y - at.Y - box.Y,
		right = start.X + bounds.X - at.X - box.X,
	}
end

local function fills(frame: GuiObject): boolean
	local screen = frame:FindFirstAncestorWhichIsA("ScreenGui")
	local inside = if screen then margins(frame, screen) else nil
	if inside == nil then
		return false
	end
	for _, side in SIDES do
		if inside[side] > 1 then
			return false
		end
	end
	return true
end

local function hold(ctx: Types.Context, node: Instance, wanted: ComposeTypes.Readable<boolean>?)
	local Compose, runtime = ctx.Compose, ctx.runtime
	local held: ScreenGui? = nil
	local function release()
		local screen = held
		held = nil
		local lease = if screen then leases[screen] else nil
		if screen and lease then
			lease.count -= 1
			if lease.count == 0 then
				leases[screen] = nil
				screen.ClipToDeviceSafeArea = lease.clipped
			end
		end
	end
	local function acquire()
		local wants = wanted == nil or wanted:peek()
		local screen = if wants then node:FindFirstAncestorWhichIsA("ScreenGui") else nil
		if screen == held then
			return
		end
		release()
		if screen then
			local lease = leases[screen]
			if lease == nil then
				lease = { count = 0, clipped = screen.ClipToDeviceSafeArea == true }
				leases[screen] = lease
			end
			lease.count += 1
			held = screen
			screen.ClipToDeviceSafeArea = false
		end
	end
	runtime.connect(node, "AncestryChanged", acquire)
	if wanted then
		Compose.watch(function(use: ComposeTypes.Use)
			use(wanted)
			acquire()
		end)
	else
		acquire()
	end
	Compose.cleanup(release)
end

local function reach(ctx: Types.Context, frame: GuiObject): ComposeTypes.Readable<Reach>
	local Compose, runtime = ctx.Compose, ctx.runtime
	local service = ctx.config.guiService
	local result: ComposeTypes.Cell<Reach> = Compose.cell(apart())
	local function measure()
		local value = apart()
		local screen = frame:FindFirstAncestorWhichIsA("ScreenGui")
		local inside = if screen then margins(frame, screen) else nil
		if screen and service and inside then
			local near, far = bands(ctx, service, screen)
			local widths: { [string]: number } = { top = near.Y, left = near.X, bottom = far.Y, right = far.X }
			for _, side in SIDES do
				if inside[side] <= 1 then
					value.meets[side] = true
					value.glass[side] = math.max(0, widths[side] + inside[side])
				end
			end
		end
		if not same(result:peek(), value) then
			result:set(value)
		end
	end
	local position, size = ctx.observe.AbsolutePosition(frame), ctx.observe.AbsoluteSize(frame)
	local band = if service then ctx.observe.TopbarInset(service) else nil
	Compose.watch(function(use: ComposeTypes.Use)
		use(position)
		use(size)
		if band then
			use(band)
		end
		measure()
	end)
	runtime.connect(frame, "AncestryChanged", measure)
	local frames = ctx.config.services.RunService
	if frames then
		runtime.connect(frames, "Heartbeat", measure)
	end
	return result
end

local function backdrop(ctx: Types.Context, frame: GuiObject, tag: string, corner: string?, skinned: boolean): Frame
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2 = ctx.types.UDim2
	local measured = reach(ctx, frame)
	local unit = ctx.layoutUnit(frame, "GlassUnit")
	local extension = Compose.formula(function(use: ComposeTypes.Use): { [string]: number }
		local value = use(measured)
		local scale = math.max(use(unit), 0.001)
		local overshoot = if corner then ctx.metric(corner, use) else 0
		local sides: { [string]: number } = {}
		for _, side in SIDES do
			sides[side] = if value.meets[side] then value.glass[side] / scale + overshoot else 0
		end
		return sides
	end)
	local reaching = Compose.formula(function(use: ComposeTypes.Use): boolean
		local value = use(measured)
		for _, side in SIDES do
			if value.meets[side] and value.glass[side] > 0 then
				return true
			end
		end
		return false
	end)
	hold(ctx, frame, reaching)
	local paint = Host.Frame "Backdrop" {
		BorderSizePixel = 0,
		ZIndex = 0,
		Position = function(use: ComposeTypes.Use): UDim2
			local sides = use(extension)
			return D2.fromOffset(-sides.left, -sides.top)
		end,
		Size = function(use: ComposeTypes.Use): UDim2
			local sides = use(extension)
			return D2.new(1, sides.left + sides.right, 1, sides.top + sides.bottom)
		end,
	}
	paint:AddTag(tag)
	if skinned then
		ctx.skin(paint, "panel")
	end
	runtime.mount(function()
		return Host.Folder "Glass" { decoration(Compose, runtime, ctx.types, frame, paint) }
	end, frame)
	return paint
end

return {
	bands = bands,
	fills = fills,
	hold = hold,
	reach = reach,
	backdrop = backdrop,
}

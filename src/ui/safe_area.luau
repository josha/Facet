--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Env = require("./environment_types")
local freeze = require("./freeze")

export type Bars = {
	status: ComposeTypes.ReadOnlyValue<unknown>?,
	bottom: ComposeTypes.ReadOnlyValue<unknown>?,
	navigation: ComposeTypes.ReadOnlyValue<unknown>?,
	right: ComposeTypes.ReadOnlyValue<unknown>?,
}

type SafeZone = { GetSafeZoneOffsets: (self: SafeZone) -> unknown }

local function extent(value: unknown): number
	return if type(value) == "number" and value == value and math.abs(value) < math.huge then math.max(value, 0) else 0
end

local function bar(
	ctx: Shared.Context,
	input: UserInputService?,
	property: string
): ComposeTypes.ReadOnlyValue<unknown>?
	local node = input
	local observation = ctx.runtime.host.observation
	if node == nil or observation == nil then
		return nil
	end
	local readable, value = pcall(observation.readProperty, node, property)
	if not readable or typeof(value) ~= "Vector2" then
		return nil
	end
	local observed, source = pcall(ctx.runtime.observe, node, property)
	return if observed then source else nil
end

local function bars(ctx: Shared.Context, input: UserInputService?): Bars
	return {
		status = bar(ctx, input, "StatusBarSize"),
		bottom = bar(ctx, input, "BottomBarSize"),
		navigation = bar(ctx, input, "NavBarSize"),
		right = bar(ctx, input, "RightBarSize"),
	}
end

local function zoneRevision(ctx: Shared.Context, gui: GuiService?): ComposeTypes.ReadOnlyValue<number>
	local revision = ctx.Compose.cell(0)
	if gui then
		local service = gui
		pcall(function()
			ctx.runtime.connect(service, "SafeZoneOffsetsChanged", function()
				revision:set(revision:peek() + 1)
			end)
		end)
	end
	return revision
end

local function insets(ctx: Shared.Context, gui: GuiService?, sources: Bars, use: ComposeTypes.Use): Env.SafeInsets
	local top, left, bottom, right = 0, 0, 0, 0
	if gui then
		local service = gui
		local E = ctx.types.Enum
		local measured, full, safe = pcall(function(): (Rect, Rect)
			return service:GetInsetArea(E.ScreenInsets.None), service:GetInsetArea(E.ScreenInsets.CoreUISafeInsets)
		end)
		if measured and typeof(full) == "Rect" and typeof(safe) == "Rect" then
			top, left = extent(safe.Min.Y - full.Min.Y), extent(safe.Min.X - full.Min.X)
			bottom, right = extent(full.Max.Y - safe.Max.Y), extent(full.Max.X - safe.Max.X)
		else
			local inset, topLeft, bottomRight = pcall(function(): (Vector2, Vector2)
				return service:GetGuiInset()
			end)
			if inset and typeof(topLeft) == "Vector2" and typeof(bottomRight) == "Vector2" then
				top, left, bottom, right =
					extent(topLeft.Y), extent(topLeft.X), extent(bottomRight.Y), extent(bottomRight.X)
			end
		end
		local zone = (service :: unknown) :: SafeZone
		local zoned, offsets = pcall(function(): unknown
			return zone:GetSafeZoneOffsets()
		end)
		if zoned and type(offsets) == "table" then
			local named = offsets :: { [string]: unknown }
			top, left = math.max(top, extent(named.top)), math.max(left, extent(named.left))
			bottom, right = math.max(bottom, extent(named.bottom)), math.max(right, extent(named.right))
		end
	end
	local function measure(source: ComposeTypes.ReadOnlyValue<unknown>?): Vector2?
		local value = if source then use(source) else nil
		return if typeof(value) == "Vector2" then value else nil
	end
	local status, home, navigation, side =
		measure(sources.status), measure(sources.bottom), measure(sources.navigation), measure(sources.right)
	top = math.max(top, if status then extent(status.Y) else 0)
	bottom = math.max(bottom, if home then extent(home.Y) else 0, if navigation then extent(navigation.Y) else 0)
	right = math.max(right, if side then extent(side.X) else 0)
	return freeze({ top = top, left = left, bottom = bottom, right = right })
end

return table.freeze({ bars = bars, zoneRevision = zoneRevision, insets = insets })

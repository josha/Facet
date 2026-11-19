--!strict
local Types = require("./types")

local SHARE = 0.7
local FLOOR = 10

local function styledSize(label: TextLabel): number
	local ok, value = pcall(function(): unknown
		return label:GetStyled("TextSize")
	end)
	return if ok and type(value) == "number" then value else label.TextSize
end

local function allowed(ctx: Types.Context): boolean
	local gui = ctx.config.guiService
	if gui == nil then
		return true
	end
	local ok, chosen = pcall(function(): unknown
		return gui.PreferredTextSize
	end)
	return not ok or typeof(chosen) ~= "EnumItem" or (chosen :: EnumItem).Name == "Medium"
end

local function target(ctx: Types.Context, label: TextLabel, room: number?, wide: number?): number
	if room == nil or wide == nil or wide >= math.huge or room <= 0 or wide <= room + 0.5 or not allowed(ctx) then
		return 1
	end
	local least = math.min(1, math.max(SHARE, FLOOR / math.max(styledSize(label), 1)))
	return math.clamp(room / wide, least, 1)
end

local function chainScale(node: Instance?): number
	local scale = 1
	local at = node
	while at and at:IsA("GuiObject") do
		local factor = at:FindFirstChildWhichIsA("UIScale")
		if factor and factor.Name ~= "TextFit" then
			scale *= factor.Scale
		end
		at = at.Parent
	end
	return scale
end

local function current(label: GuiObject): number
	local scale = label:FindFirstChild("TextFit")
	return if scale and scale:IsA("UIScale") then scale.Scale else 1
end

local function apply(label: GuiObject, value: number, make: () -> UIScale)
	local found = label:FindFirstChild("TextFit")
	local scale: UIScale? = if found and found:IsA("UIScale") then found else nil
	if value < 0.995 then
		local made = scale or make()
		if math.abs(made.Scale - value) > 0.005 then
			made.Scale = value
		end
		if made.Parent ~= label then
			made.Parent = label
		end
	elseif scale and scale.Scale ~= 1 then
		scale.Scale = 1
	end
end

local function eligible(ctx: Types.Context, label: GuiObject): TextLabel?
	if not label:IsA("TextLabel") or not label:HasTag("facet-text-fits") then
		return nil
	end
	local text = label :: TextLabel
	if text.TextWrapped or text.TextScaled or text.TextTruncate ~= ctx.types.Enum.TextTruncate.None then
		return nil
	end
	return text
end

return table.freeze({
	target = target,
	chainScale = chainScale,
	current = current,
	apply = apply,
	eligible = eligible,
})

--!strict

local assets = {}

assets.match3Tiles = {
	a = { image = "rbxassetid://92798715826227", iconName = "chevron.up", name = "Up tile", label = "^" },
	b = { image = "rbxassetid://90343755930598", iconName = "chevron.down", name = "Down tile", label = "v" },
	c = { image = "rbxassetid://81739481512878", iconName = "chevron.leading", name = "Left tile", label = "<" },
	d = { image = "rbxassetid://121626475799702", iconName = "chevron.trailing", name = "Right tile", label = ">" },
	e = { image = "rbxassetid://108245103349446", iconName = "checkmark", name = "Check tile", label = "+" },
}

assets.match3Tints = {
	a = "accent",
	b = "success",
	c = "warning",
	d = "error",
	e = "neutral",
}

assets.pending = "rbxassetid://1000000000"

return assets

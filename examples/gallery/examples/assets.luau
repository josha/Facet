--!strict

local assets = {}

assets.match3Tiles = {
	a = { image = "rbxassetid://92798715826227", iconName = "chevron.up", label = "^" },
	b = { image = "rbxassetid://90343755930598", iconName = "chevron.down", label = "v" },
	c = { image = "rbxassetid://81739481512878", iconName = "chevron.leading", label = "<" },
	d = { image = "rbxassetid://121626475799702", iconName = "chevron.trailing", label = ">" },
	e = { image = "rbxassetid://108245103349446", iconName = "checkmark", label = "+" },
}

assets.match3Tints = {
	a = "accent",
	b = "content",
	c = "contentStrong",
	d = "danger",
	e = "contentSecondary",
}

assets.pending = "rbxassetid://1000000000"

return assets

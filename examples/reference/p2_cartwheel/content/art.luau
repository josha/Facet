--!strict

export type Mark = { image: string, iconName: string, label: string }

local art = {}

local MARKS: { [string]: Mark } = {
	chevronLeft = table.freeze({ image = "rbxassetid://81739481512878", iconName = "chevron.leading", label = "<" }),
	chevronRight = table.freeze({ image = "rbxassetid://121626475799702", iconName = "chevron.trailing", label = ">" }),
	chevronUp = table.freeze({ image = "rbxassetid://92798715826227", iconName = "chevron.up", label = "^" }),
	chevronDown = table.freeze({ image = "rbxassetid://90343755930598", iconName = "chevron.down", label = "v" }),
	check = table.freeze({ image = "rbxassetid://108245103349446", iconName = "checkmark", label = "v" }),
	close = table.freeze({ image = "rbxassetid://133198978089241", iconName = "close", label = "x" }),
	plus = table.freeze({ image = "rbxassetid://128664097463435", iconName = "increment", label = "+" }),
	minus = table.freeze({ image = "rbxassetid://115068690098353", iconName = "decrement", label = "-" }),
	menu = table.freeze({ image = "rbxassetid://119066409501208", iconName = "menu", label = "=" }),
	more = table.freeze({ image = "rbxassetid://117014407191998", iconName = "more", label = "..." }),
	edit = table.freeze({ image = "rbxassetid://97349995335189", iconName = "edit", label = "/" }),
}
art.marks = table.freeze(MARKS)

art.cycle = table.freeze({
	"chevronUp",
	"check",
	"chevronRight",
	"plus",
	"chevronDown",
	"menu",
	"chevronLeft",
	"more",
	"edit",
	"minus",
	"close",
})

function art.markFor(index: number): Mark
	local key = art.cycle[((index - 1) % #art.cycle) + 1]
	return MARKS[key]
end

return table.freeze(art)

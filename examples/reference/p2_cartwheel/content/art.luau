--!strict
-- Cartwheel's art references.
--
-- THE IDS BELOW ARE THE FRAMEWORK'S OWN SHIPPED ICON ART, and that is a stated
-- substitution, not a shortcut taken quietly. The responsibility ledger gives a
-- proof its own original assets; uploading eleven original potion silhouettes
-- needs Open Cloud credentials and a creative pass that is not in this package's
-- scope, and the alternative — invented `rbxassetid://` numbers — is the exact
-- defect the tutorial gallery's own art comment records: on a real client every
-- picture draws nothing and the screens become indistinguishable plates.
--
-- So the proof borrows REAL, UPLOADED ids (`src/themes/standard_icons.luau`) and
-- pins them: `tests/reference/cartwheel_spec.luau` asserts every id here still
-- matches the framework table, so a re-upload fails a test instead of silently
-- blanking the cart. Each entry also carries an ASCII `label`, so a client that
-- cannot fetch the picture still shows a distinct mark per potion.
--
-- Every potion additionally carries its own `hue` (content/data.luau), painted
-- through the `tint` channel's DECLARED theming-exempt form — a potion's colour
-- is game data, which is the one thing that channel is for.
local art = {}

-- name -> { image, iconName, label }. `iconName` is the framework icon the id
-- belongs to; the spec file cross-checks the pair.
art.marks = table.freeze({
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
})

-- THE ELEVEN MARKS, IN A STABLE ORDER. A potion's art is `marks[cycle[i]]` where
-- `i` is its index in the catalogue, so seventeen potions reuse eleven
-- silhouettes and no two ADJACENT potions ever share one.
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

-- the mark for a 1-based catalogue index
function art.markFor(index: number): { image: string, iconName: string, label: string }
	local key = art.cycle[((index - 1) % #art.cycle) + 1]
	return (art.marks :: any)[key]
end

return table.freeze(art)

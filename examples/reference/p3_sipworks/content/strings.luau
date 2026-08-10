--!strict
-- Sipworks copy, keyed by locale (build-decisions "Code layout": every string
-- routes through the proof's own strings table; `xa` is the ≥1.4× pseudo-
-- expansion locale).
--
-- TWO SHAPES, ONE TABLE. A key is either a plain template string or a PLURAL
-- FIXTURE `{ zero?, one, other }` (spec §13). I18nService picks the form; no
-- call site branches on a count.
--
-- `{name}` placeholders are substituted by I18nService. Nothing here is ever
-- concatenated at a call site — a sentence assembled from fragments is a
-- sentence that cannot be translated, and the list ("A, B, and C") and measure
-- ("1.5 tsp") formats are service calls for exactly that reason.
--
-- THE `xa` TABLE IS DERIVED, NOT AUTHORED. It is the `en` table run through
-- `expand` at load: bracketed, and every literal run lengthened to at least
-- 1.4× — placeholders preserved byte for byte, so a pseudo-localized sentence
-- still formats. Deterministic (a pure function of the source string), which is
-- what lets the suite pin the ratio instead of trusting it.

local strings = {}

-- ---------------------------------------------------------------------------
-- the pseudo-expansion
-- ---------------------------------------------------------------------------

local EXPANSION = 1.4

-- expandRun(s): lengthen ONE literal run to >= EXPANSION x its length by
-- repeating a slice of itself, then keep the words legible. Empty and
-- whitespace-only runs are left alone (there is nothing to translate).
local function expandRun(s: string): string
	local trimmed = string.match(s, "^%s*(.-)%s*$") :: string
	if trimmed == "" then
		return s
	end
	local target = math.ceil(#s * EXPANSION)
	local out = s
	local i = 1
	-- A ONE-WORD SOURCE STAYS ONE WORD. The framework's own rule is that a single
	-- word has no legal break and is drawn on one line (it ellipsizes instead of
	-- wrapping), so a pseudo-locale that inserted a space into a one-word button
	-- label would be testing WRAPPING rather than expansion — and it did: a
	-- four-tab band whose every label wrapped to two lines made a 320px-tall
	-- landscape phone illegal in the composition.
	local joiner = if string.find(trimmed, "%s") ~= nil then " " else ""
	-- append slices of the source until the run is long enough; deterministic,
	-- and it never introduces a character the source did not already contain
	while #out < target do
		local take = math.min(#trimmed, math.max(2, target - #out))
		out ..= joiner .. string.sub(trimmed, i, i + take - 1)
		i += take
		if i > #trimmed then
			i = 1
		end
	end
	return out
end

-- expand(template): bracket the whole and expand every literal run between
-- `{placeholder}` tokens. The brackets are the pseudo-locale's tell — a string
-- on screen without them is a string that never went through the table.
function strings.expand(template: string): string
	local out = "["
	local cursor = 1
	while true do
		local openAt, closeAt = string.find(template, "{[%w_]+}", cursor)
		if openAt == nil then
			break
		end
		out ..= expandRun(string.sub(template, cursor, (openAt :: number) - 1))
		out ..= string.sub(template, openAt :: number, closeAt :: number)
		cursor = (closeAt :: number) + 1
	end
	out ..= expandRun(string.sub(template, cursor))
	return out .. "]"
end

-- ---------------------------------------------------------------------------
-- the authored locale
-- ---------------------------------------------------------------------------

local en: { [string]: any } = {
	["app.title"] = "Sipworks",
	["app.tagline"] = "A craft tea house",

	["nav.menu"] = "Menu",
	["nav.favorites"] = "Favorites",
	["nav.book"] = "Blend Book",
	["nav.stamps"] = "Steam Stamps",
	["nav.back"] = "Back",
	-- the nav's MINIMUM-VIABLE form (spec §5's second ranked form). Localized,
	-- because a `compactLabel` is construction-only and could never follow the
	-- live locale flip this proof's loop drives.
	["nav.menu.short"] = "Menu",
	["nav.favorites.short"] = "Saved",
	["nav.book.short"] = "Book",
	["nav.stamps.short"] = "Stamps",

	["search.placeholder"] = "Search blends and botanicals",
	["search.suggestions"] = "Botanicals",
	["detail.empty"] = "Pick a blend to see it here.",
	["detail.title"] = "Blend",

	["row.favorite"] = "Save {title} to favorites",
	["row.unfavorite"] = "Remove {title} from favorites",
	["row.caffeine"] = "{n} mg caffeine",
	["row.free"] = "Free recipe",

	["favorites.empty"] = "Mark a few blends to keep them here.",
	["favorites.browse"] = "Browse the menu",

	["ingredients.menu"] = "In the pot",
	["ingredients.recipe"] = "What you'll need",

	["card.close"] = "Close",
	["card.factsOpen"] = "Brew facts",
	["card.factsClose"] = "Turn the card back",
	["facts.title"] = "Brew facts",
	["facts.leaf"] = "Leaf in this pot",
	["facts.caffeine"] = "Caffeine",
	["facts.steep"] = "Steep",
	["facts.warmth"] = "Warmth",
	["facts.grams"] = "{value} g",
	["facts.mg"] = "{value} mg",
	["facts.minutes"] = "{value} min",
	["facts.warmthValue"] = "{value} of 5",

	["order.place"] = "Place order — {price}",
	["order.redeem"] = "Redeem a free pour!",
	["order.pending"] = "Placing…",
	["order.rejected"] = "Couldn't place your order — the counter is closed.",
	["order.redeemed"] = "Redeemed — 10 stamps spent.",

	["guard.paused"] = "Ordering is paused — the counter can't take this order.",
	["guard.title"] = "Ordering paused",
	["guard.paymentsDisabled"] = "This kiosk code was scanned too far from the shop, so ordering is off for your protection.",
	["guard.fallback"] = "Ordering is unavailable right now.",

	["common.ok"] = "OK",
	["common.done"] = "Done",

	["placed.thanks"] = "Thanks for your order!",
	["placed.notify"] = "This card flips when your pour is ready.",
	["placed.ready"] = "Your pour is ready!",
	["placed.pickup"] = "{title} is waiting at the counter.",

	["rewards.title"] = "Steam Stamps",
	["rewards.away"] = {
		zero = "Your next pour is on the house!",
		one = "You are 1 stamp from a free pour!",
		other = "You are {n} stamps from a free pour!",
	},
	["rewards.progress"] = {
		one = "1 of 10 stamps",
		other = "{n} of 10 stamps",
	},

	["unlock.name"] = "The Blend Book",
	["unlock.description"] = "Every house recipe, yours to brew.",
	["unlock.loading"] = "Loading…",
	["unlock.buy"] = "Unlock — {price}",
	["unlock.pending"] = "Unlocking…",
	["unlock.rejected"] = "The Blend Book purchase was declined — nothing was charged.",
	["unlock.unlocked"] = "The Blend Book is yours.",

	["recipe.batches"] = {
		zero = "No pots",
		one = "1 pot",
		other = "{n} pots",
	},
	["recipe.gathered"] = "Gathered: {name}",
	["recipe.title"] = "Recipe",

	["list.pair"] = "{a} and {b}",
	["list.two"] = "{a}, {b}",
	["list.last"] = "{head}, and {tail}",
	["measure.value"] = "{value} {unit}",
}

-- ---------------------------------------------------------------------------
-- the derived pseudo-locale
-- ---------------------------------------------------------------------------

local function expandEntry(value: any): any
	if type(value) == "string" then
		return strings.expand(value)
	end
	local out: { [string]: string } = {}
	for form, text in value do
		out[form] = strings.expand(text)
	end
	return out
end

local xa: { [string]: any } = {}
for key, value in en do
	xa[key] = expandEntry(value)
end

strings.EXPANSION = EXPANSION
strings.byLocale = table.freeze({ en = en, xa = xa })
strings.LOCALES = table.freeze({ "en", "xa" })

return strings

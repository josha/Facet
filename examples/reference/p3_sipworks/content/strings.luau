--!strict

local strings = {}

export type Plural = { zero: string?, one: string?, other: string? }
export type Entry = string | Plural

local EXPANSION = 1.4

local function expandRun(s: string): string
	local trimmed = string.match(s, "^%s*(.-)%s*$") or s
	if trimmed == "" then
		return s
	end
	local target = math.ceil(#s * EXPANSION)
	local out = s
	local i = 1

	local joiner = if string.find(trimmed, "%s") ~= nil then " " else ""

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

function strings.expand(template: string): string
	local out = "["
	local cursor = 1
	while true do
		local openAt, closeAt = string.find(template, "{[%w_]+}", cursor)
		if openAt == nil or closeAt == nil then
			break
		end
		out ..= expandRun(string.sub(template, cursor, openAt - 1))
		out ..= string.sub(template, openAt, closeAt)
		cursor = closeAt + 1
	end
	out ..= expandRun(string.sub(template, cursor))
	return out .. "]"
end

local en: { [string]: Entry } = {
	["app.title"] = "Sipworks",
	["app.tagline"] = "A craft tea house",

	["task.title"] = "Today's order",
	["task.intro"] = "Sipworks is a tea house. Pick a blend, serve it, and take a stamp — ten stamps is a free pour.",
	["task.next.order"] = "Choose a blend and place the order.",
	["task.next.placing"] = "The counter is taking your order…",
	["task.next.rejected"] = "The counter turned that order away and charged nothing. Your stamps are safe — order again when you're ready.",
	["task.next.redeem"] = "Your card is full. Choose another blend and redeem the free pour.",
	["task.cta.order"] = "Order {title}",
	["task.cta.redeem"] = "Redeem with {title}",
	["task.done.title"] = "A free pour, on the house.",
	["task.done.body"] = "One order filled the stamp card, and all ten stamps went back over the counter for a free pour.",
	["task.done.reset"] = "Serve another customer",
	["task.shows.open"] = "What this shows",
	["task.shows.body"] = "One tea house, laid out for every screen: the navigation moves between a sidebar, a top band and a thumb-zone tab bar as the window changes, the order waits on a real reply that is allowed to refuse, and every word on screen comes from a table that can grow by nearly half again without clipping.",

	["nav.menu"] = "Menu",
	["nav.favorites"] = "Favorites",
	["nav.book"] = "Blend Book",
	["nav.stamps"] = "Steam Stamps",
	["nav.back"] = "Back",

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

	["menu.intro"] = "Browse house blends, collect Steam Stamps, and make your next pour on us.",
	["menu.status"] = "Today's order: {phase} · {n} of 10 stamps",
	["task.phase.order"] = "order",
	["task.phase.placing"] = "placing",
	["task.phase.rejected"] = "rejected",
	["task.phase.redeem"] = "redeem",
	["task.phase.done"] = "done",
	["task.cta.redeemOne"] = "Redeem a {title}",
	["row.save"] = "Save favorite",
	["row.remove"] = "Remove favorite",

	["sheet.blend"] = "House blend",
	["sheet.botanical"] = "Botanical",
	["detail.stats"] = "{caffeine} mg caffeine · {grams} g leaves · {minutes} min steep",
	["detail.order"] = "Order · {price}",
	["detail.confirming"] = "Confirming…",
	["detail.viewRecipe"] = "View recipe",
	["detail.unlock"] = "Unlock Blend Book · {price}",
	["book.unlock"] = "Unlock · {price}",
	["recipe.batchSize"] = "Batch size",
	["recipe.line"] = "{name} · {measure}",
	["facts.line"] = "{label}: {value}",
	["botanical.summary"] = "{grams} g per teaspoon · {caffeine} mg caffeine per gram",

	["locale.en"] = "English",
	["locale.xa"] = "Expanded",
	["rewards.summary"] = "{n} stamps · ten stamps earn a free pour",
	["rewards.card"] = "Stamp card",
	["rewards.redeemFree"] = "Redeem a free {title}",
	["rewards.acknowledge"] = "Acknowledge new stamps",

	["notice.confirmed"] = "Your order is confirmed. Your stamp is on the card.",
	["notice.rejected"] = "The counter is closed. Your stamps are unchanged; try again.",
	["notice.ready"] = "Your pour is ready.",
	["notice.unlocked"] = "Your Blend Book is unlocked.",
	["notice.declined"] = "The purchase was declined. Try again.",

	["list.pair"] = "{a} and {b}",
	["list.two"] = "{a}, {b}",
	["list.last"] = "{head}, and {tail}",
	["measure.value"] = "{value} {unit}",
}

local function expandEntry(value: Entry): Entry
	if type(value) == "string" then
		return strings.expand(value)
	end
	return {
		zero = if value.zero then strings.expand(value.zero) else nil,
		one = if value.one then strings.expand(value.one) else nil,
		other = if value.other then strings.expand(value.other) else nil,
	}
end

local xa: { [string]: Entry } = {}
for key, value in en do
	xa[key] = expandEntry(value)
end

strings.EXPANSION = EXPANSION
local BY_LOCALE: { [string]: { [string]: Entry } } = { en = en, xa = xa }
local LOCALES: { string } = { "en", "xa" }
strings.byLocale = table.freeze(BY_LOCALE)
strings.LOCALES = table.freeze(LOCALES)

return strings

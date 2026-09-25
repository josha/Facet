--!strict

local strings = {}

strings.EXPANSION = 1.4

local en: { [string]: string } = {

	["app.title"] = "Cartwheel",
	["nav.cart"] = "The Cart",
	["nav.brews"] = "Brews",
	["nav.chatter"] = "Town Chatter",
	["nav.chatterPlus"] = "Chatter+",
	["nav.ledger"] = "The Ledger",
	["nav.potions"] = "Potions",
	["nav.workbench"] = "Workbench",
	["nav.topfive"] = "Top Five",
	["nav.guild"] = "Guild Card",
	["nav.groupPotions"] = "Potions",
	["nav.groupPlazas"] = "Plazas",
	["nav.back"] = "Back",
	["nav.menu"] = "Sections",

	["cart.title"] = "The Cart",
	["cart.newBrews"] = "New Brews",
	["cart.openBrews"] = "Open Brews",
	["cart.skyglow"] = "Skyglow",
	["cart.skyglowLink"] = "Open Willowmere Market",
	["cart.rack"] = "Potion Rack",
	["cart.openPotions"] = "Open Potions",
	["cart.chatter"] = "Town Chatter",
	["cart.chatterFooter"] = "What the town is saying",
	["cart.tally"] = "Brew #{id} · {bottles} bottles",
	["cart.lanternLit"] = "Lantern-lit",
	["cart.lanternOut"] = "Lantern-out",
	["cart.skyCharge"] = "Sky charge",

	["brews.title"] = "Brews",
	["brews.search"] = "Search brews",
	["brews.open"] = "Open",
	["brews.openHint"] = "Select a brew first",
	["brews.collectSelected"] = "Collect Selected ({n})",
	["brews.collectShort"] = "Collect",
	["brews.select"] = "Select",
	["brews.selectDone"] = "Done",
	["brews.empty"] = "No brews match that search.",
	["brews.colBrew"] = "Brew",
	["brews.colBottles"] = "Bottles",
	["brews.colStatus"] = "Status",
	["brews.colPlaced"] = "Placed",
	["brews.colActions"] = "Actions",
	["brews.rowLabel"] = "Brew #{id}",

	["status.new"] = "New",
	["status.brewing"] = "Brewing",
	["status.ready"] = "Ready",
	["status.done"] = "Done",

	["detail.title"] = "Brew #{id}",
	["detail.started"] = "Started {time}",
	["detail.placed"] = "Placed {time}",
	["detail.bottles"] = "Bottles",
	["detail.totalBottles"] = "Total bottles",
	["detail.start"] = "Start Brew",
	["detail.finish"] = "Finish Brew",
	["detail.collected"] = "Collected",
	["detail.collectedHint"] = "This brew is finished",
	["detail.readyToFinish"] = "Ready to finish",
	["detail.countdown"] = "{clock} left",
	["detail.working"] = "Working…",

	["celebrate.title"] = "Brew #{id} collected!",
	["celebrate.detail"] = "{bottles} bottles · {time}",
	["celebrate.done"] = "Done",

	["gallery.title"] = "Potions",
	["gallery.search"] = "Search potions",
	["gallery.layout"] = "Layout",
	["gallery.icons"] = "Icons",
	["gallery.list"] = "List",
	["gallery.sort"] = "Sort",
	["gallery.sortPopularity"] = "Popularity",
	["gallery.sortName"] = "Name",
	["gallery.sortAttribute"] = "Attribute",
	["gallery.newPotion"] = "New Potion",
	["gallery.colPotion"] = "Potion",
	["gallery.colStrongest"] = "Strongest",
	["gallery.empty"] = "No potions match that search.",

	["time.today"] = "Today",
	["time.week"] = "Week",
	["time.month"] = "Month",
	["time.year"] = "Year",
	["time.day"] = "Day",
	["time.twoWeeks"] = "2 Weeks",

	["bench.title"] = "Workbench",
	["bench.live"] = "Changes apply as you brew.",
	["bench.draft"] = "Draft potion — edits apply live",
	["bench.sectionPotion"] = "Potion",
	["bench.sectionAttributes"] = "Attributes",
	["bench.sectionIngredients"] = "Ingredients",
	["bench.name"] = "Name",
	["bench.base"] = "Base",
	["bench.essence"] = "Essence",
	["bench.garnish"] = "Garnish",
	["bench.none"] = "None",
	["bench.preview"] = "Preview",

	["attr.spark"] = "Spark",
	["attr.bloom"] = "Bloom",
	["attr.frost"] = "Frost",
	["attr.ember"] = "Ember",
	["attr.murk"] = "Murk",
	["attr.zing"] = "Zing",

	["top.title"] = "Top Five",
	["top.totalBottles"] = "Total bottles",

	["chatter.title"] = "Town Chatter",
	["chatter.plusTitle"] = "Chatter+",
	["chatter.getTitle"] = "Get Chatter+",
	["chatter.getBody"] = "Highlighted posts, engagement tools, and the plaza chatter before it reaches the quay.",
	["chatter.getStarted"] = "Get Started",
	["chatter.subscribe"] = "Subscribe",
	["chatter.tierMonthly"] = "Monthly · {credits} credits",
	["chatter.tierYearly"] = "Yearly · {credits} credits",
	["chatter.save"] = "Save {percent}%",
	["chatter.highlighted"] = "Highlighted Posts",
	["chatter.options"] = "Chatter+ Options",
	["chatter.optionsStatus"] = "Chatter+ is active on this cart.",
	["chatter.optHighlight"] = "Highlight Chatter+ posts",
	["chatter.optTools"] = "Engagement tools",
	["chatter.postSaid"] = "{who} on {potion}",
	["chatter.ago"] = "{ago} ago",

	["ledger.title"] = "The Ledger",
	["ledger.locked"] = "Premium — Full Ledger",
	["ledger.unlockTitle"] = "Unlock the Full Ledger",
	["ledger.unlockBody"] = "Every plaza, every season, side by side.",
	["ledger.unlock"] = "Unlock",
	["ledger.unlockRow"] = "Unlock the Full Ledger — {credits} credits",
	["ledger.close"] = "Close",
	["ledger.lockedOption"] = "{name} (locked)",
	["ledger.legend"] = "Plazas",

	["plaza.recommended"] = "Recommended · Pitch",
	["plaza.fallback"] = "Live view unavailable on this device.",
	["plaza.popular"] = "Popular",
	["plaza.trending"] = "Trending",
	["plaza.charge"] = "Sky charge {percent}%",
	["plaza.cloud"] = "Cloud cover {percent}%",
	["plaza.seasonal"] = "Seasonal: {potion} is pouring well here.",
	["plaza.stock"] = "Stock {bottles} bottles before the lantern hour.",

	["guild.title"] = "Guild Card",
	["guild.note"] = "A UI exercise — Roblox identity is ambient; nothing is stored.",
	["guild.name"] = "Guild name",
	["guild.watchword"] = "Watchword",
	["guild.watchwordVisible"] = "Heads up — your watchword is visible as you type.",
	["guild.cancel"] = "Cancel",
	["guild.submit"] = "Sign Up",
	["guild.submitHint"] = "Fill in both fields",
	["guild.welcome"] = "Welcome to the guild, {name}",
	["guild.signedIn"] = "Signed in as {name}",
	["guild.signOut"] = "Sign out",
	["guild.signOutConfirm"] = "Sign out of the guild?",
	["guild.signOutBody"] = "Nothing is stored either way.",

	["reject.collected"] = "Brew already collected",
	["reject.purchase"] = "Purchase declined — nothing was charged",
	["reject.guildTaken"] = "That guild name is taken",
	["reject.fallback"] = "Something went wrong. Nothing was changed.",
	["command.working"] = "Working…",
}

local function pseudo(value: string): string
	local pad = math.max(1, math.ceil(#value * (strings.EXPANSION - 1)) + 2)
	return "[" .. value .. string.rep("~", pad - 2) .. "]"
end

local xa: { [string]: string } = {}
for key, value in en do
	xa[key] = pseudo(value)
end

strings.locales = table.freeze({ en = table.freeze(en), xa = table.freeze(xa) })
strings.pseudo = pseudo

function strings.format(template: string, vars: { [string]: any }?): string
	if vars == nil then
		return template
	end
	return (
		string.gsub(template, "{(%w+)}", function(name: string): string
			local value = (vars :: any)[name]
			return if value == nil then "{" .. name .. "}" else tostring(value)
		end)
	)
end

function strings.new(locale: string?): any
	local name = if locale ~= nil and (strings.locales :: any)[locale] ~= nil then locale else "en"
	local table_ = (strings.locales :: any)[name]
	local self = { locale = name }
	function self.t(key: string, vars: { [string]: any }?): string
		local template = table_[key]
		if template == nil then
			return key
		end
		return strings.format(template, vars)
	end
	function self.has(key: string): boolean
		return table_[key] ~= nil
	end
	return self
end

function strings.clockTime(minutes: number): string
	local m = math.floor(minutes) % (24 * 60)
	local hour24 = math.floor(m / 60)
	local minute = m % 60
	local suffix = if hour24 < 12 then "AM" else "PM"
	local hour = hour24 % 12
	if hour == 0 then
		hour = 12
	end
	return string.format("%d:%02d %s", hour, minute, suffix)
end

function strings.countdown(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

function strings.relative(minutes: number): string
	if minutes < 60 then
		return string.format("%dm", math.max(1, math.floor(minutes)))
	elseif minutes < 60 * 24 then
		return string.format("%dh", math.floor(minutes / 60))
	end
	return string.format("%dd", math.floor(minutes / (60 * 24)))
end

return strings

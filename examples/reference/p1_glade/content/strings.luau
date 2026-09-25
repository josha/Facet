--!strict

local strings = {}

strings.LOCALES = { "en", "xa" }
strings.DEFAULT_LOCALE = "en"

strings.PRICE_MARK = "★"

local en: { [string]: string } = {

	["app.title"] = "Glade",
	["section.glades"] = "Glades",
	["section.wisps"] = "Wisps",
	["section.flora"] = "Flora",
	["section.keeper"] = "Keeper",

	["section.glades.short"] = "Glades",
	["section.wisps.short"] = "Wisps",
	["section.flora.short"] = "Flora",
	["section.keeper.short"] = "You",

	["task.title"] = "Prepare this glade",
	["task.intro"] = "Wisps visit glades that have fresh dew and the nectar they like.",
	["task.subject"] = "{glade}, for {wisp} — it likes {nectar}.",
	["task.row.dew"] = "Refill {glade}'s dew",
	["task.row.nectar"] = "Set out {nectar}",
	["task.row.done"] = "Done",
	["task.row.todo"] = "To do",
	["task.progress"] = "{n} of 2 ready",
	["task.next.start"] = "Open {glade} and refill its dew.",
	["task.next.nectar"] = "Now set out {nectar} in {glade}.",
	["task.next.dew"] = "{glade}'s dew has dried out again — refill it to finish. The nectar is still set out.",
	["task.next.resume"] = "{glade}'s supplies have run down again. Refill the dew and set out {nectar}.",
	["task.open"] = "Open {glade}",
	["task.done.title"] = "{wisp} has settled into {glade}.",
	["task.done.body"] = "Fresh dew and the nectar it likes are all a wisp asks for. Keep the supplies up and it will stay.",
	["task.done.reset"] = "Prepare again",
	["task.toast"] = "{wisp} settles into {glade}.",
	["task.shows.open"] = "What this shows",
	["task.shows.body"] = "One glade keeper's app on every screen: the tab bar moves between a sidebar, a top band and a thumb-zone dock, the detail sits beside the list where there is room and slides in over it where there is not, supplies drain on a clock the whole screen reacts to, and the arrival animates or places instantly depending on the reduced-motion setting.",

	["overview.search"] = "Find a glade",
	["overview.visiting"] = " is visiting ",
	["overview.noMatches"] = 'No glades match "{term}".',
	["overview.clearSearch"] = "Clear search",
	["overview.favorite"] = "Favorite",
	["overview.open"] = "Open {glade}",
	["offer.pitch"] = "Keep every glade open, and the wisps arrive sooner.",
	["offer.cta"] = "See the Charm",
	["offer.dismiss"] = "Dismiss",

	["supply.nectar"] = "Nectar",
	["supply.dew"] = "Dew",
	["supply.low"] = "Low",
	["supply.empty"] = "Empty",
	["supply.caption"] = "{remaining} left — refills the glow",
	["supply.captionEmpty"] = "Nothing left — refills the glow",

	["detail.back"] = "Back",
	["detail.chooseNectar"] = "Choose nectar",
	["detail.refillDew"] = "Refill dew",
	["detail.visitors"] = "Recent visitors",
	["detail.noVisitors"] = "No visitors yet — keep the dew fresh.",

	["picker.title"] = "Choose nectar",
	["picker.done"] = "Done",
	["picker.premium"] = "Premium",
	["picker.standard"] = "Standard",
	["picker.shopRow"] = "Provision Shop",
	["picker.choose"] = "Choose",
	["picker.use"] = "Use 1",
	["picker.shop"] = "Shop",
	["picker.pending"] = "Confirming…",

	["shop.title"] = "Provision Shop",
	["shop.bestValue"] = "Best value",
	["shop.more"] = "More provisions",
	["shop.buy"] = "Buy",
	["shop.single"] = "One jar",
	["shop.bundle"] = "Five jars",

	["charm.title"] = "Keeper's Charm",
	["charm.pitch"] = "One charm, every glade — and the wisps notice.",
	["charm.upgradePitch"] = "Go Lumen — Frostwisps arrive at first light.",
	["charm.buy"] = "Buy",
	["charm.tier.ember"] = "Ember",
	["charm.tier.grove"] = "Grove",
	["charm.tier.lumen"] = "Lumen",
	["charm.tagline.ember"] = "Every glade, no limits",
	["charm.tagline.grove"] = "Share the grove's warmth",
	["charm.tagline.lumen"] = "The full glade at first light",
	["charm.toast"] = "You're a {tier} Keeper now.",

	["wisp.close"] = "Close",
	["wisp.lastSeen"] = "Last seen {when} in {glade}",
	["wisp.neverSeen"] = "Not yet seen",
	["wisp.lumenChip"] = "Lumen only",
	["wisp.lumenPitch"] = "Arrives early for Lumen Keepers",
	["wisp.favourite"] = "Favourite nectar: {nectar}",
	["wisp.activate"] = "About {wisp}",

	["keeper.title"] = "Keeper",
	["keeper.joined"] = "Tending glades since {date}",
	["keeper.charmNone"] = "Get the Keeper's Charm",
	["keeper.charmUpgrade"] = "Check out Lumen",
	["keeper.charmStatus"] = "Your Keeper's Charm: {tier}",
	["keeper.charmStatusNone"] = "Your Keeper's Charm: none yet",
	["keeper.restore"] = "Restore provisions",
	["keeper.restoring"] = "Restoring…",
	["keeper.restoreToast"] = "Satchel up to date.",
	["keeper.edit"] = "Edit keeper",
	["keeper.editTitle"] = "Edit keeper",
	["keeper.displayName"] = "Display name",
	["keeper.contact"] = "Contact",
	["keeper.save"] = "Done",
	["keeper.cancel"] = "Cancel",
	["keeper.freshStart"] = "Fresh Start",
	["keeper.confirmTitle"] = "Start over?",
	["keeper.confirmBody"] = "Glades, satchel and charm return to a fresh morning.",
	["keeper.keep"] = "Keep my glades",
	["keeper.startOver"] = "Start over",

	["flora.title"] = "Flora",

	["toast.refill"] = "{glade} is glowing brighter.",
	["toast.purchase"] = "Added to your satchel — {count}× {nectar}",

	["reject.declined"] = "The purchase didn't go through. You weren't charged.",
	["reject.offline"] = "Can't reach the shop right now. Try again in a moment.",
	["reject.owned"] = "You already have this charm tier.",
	["reject.fallback"] = "Something went wrong. You weren't charged.",

	["time.hour"] = "{n}h",
	["time.minute"] = "{n}m",
	["time.second"] = "{n}s",
	["time.ago"] = "{when} ago",
	["time.now"] = "just now",

	["glade.mossholm"] = "Mossholm",
	["glade.fernhollow"] = "Fernhollow",
	["glade.lanternDell"] = "Lantern Dell",
	["glade.brambleRest"] = "Bramble Rest",
	["glade.stillpond"] = "Stillpond",

	["wisp.emberwisp"] = "Emberwisp",
	["wisp.palewisp"] = "Palewisp",
	["wisp.frostwisp"] = "Frostwisp",
	["wisp.duskwisp"] = "Duskwisp",
	["wisp.sunwisp"] = "Sunwisp",
	["wisp.tidewisp"] = "Tidewisp",
	["species.emberwisp"] = "Ember sprite — drawn to warm moss",
	["species.palewisp"] = "Pale sprite — the first light of a glade",
	["species.frostwisp"] = "Frost sprite — arrives before the thaw",
	["species.duskwisp"] = "Dusk sprite — settles as the light goes",
	["species.sunwisp"] = "Sun sprite — noon in the clearing",
	["species.tidewisp"] = "Tide sprite — follows the wet stones",

	["nectar.clover"] = "Clover Nectar",
	["nectar.meadow"] = "Meadow Nectar",
	["nectar.fern"] = "Fern Nectar",
	["nectar.thistle"] = "Thistle Nectar",
	["nectar.bramble"] = "Bramble Nectar",
	["nectar.heather"] = "Heather Nectar",
	["nectar.starlight"] = "Starlight Syrup",
	["nectar.moonpetal"] = "Moonpetal Nectar",
	["nectar.gilded"] = "Gilded Amber",
	["summary.clover"] = "Plain and steady. Every wisp knows it.",
	["summary.meadow"] = "Cut grass and sun. Keeps a glade busy.",
	["summary.fern"] = "Green and cool, for the shaded corners.",
	["summary.thistle"] = "Sharp on the first sip, sweet after.",
	["summary.bramble"] = "Dark and syrupy. Emberwisps queue for it.",
	["summary.heather"] = "Thin honey with a wind off the hill in it.",
	["summary.starlight"] = "Rare and slow to fade — the longest glow a glade can hold.",
	["summary.moonpetal"] = "Cold silver sweetness. Duskwisps stay the night for it.",
	["summary.gilded"] = "Amber pressed thick. One jar carries a long evening.",

	["flora.mosscap"] = "Mosscap",
	["flora.lanternvine"] = "Lanternvine",
	["flora.dewfern"] = "Dewfern",
	["flora.bramblewort"] = "Bramblewort",
	["flora.stillreed"] = "Stillreed",
	["flora.species.mosscap"] = "Cushion moss — holds the damp",
	["flora.species.lanternvine"] = "Climbing vine — glows at dusk",
	["flora.species.dewfern"] = "Shade fern — catches the morning",
	["flora.species.bramblewort"] = "Thorn shrub — feeds the bramble nectar",
	["flora.species.stillreed"] = "Water reed — grows where the dew pools",
}

local PAD_CYCLE = "aeiou"

local function expand(s: string): string
	local pad = math.ceil(#s * 0.4)
	if pad <= 0 then
		pad = 1
	end
	local out = table.create(pad)
	for i = 1, pad do
		local index = (i - 1) % #PAD_CYCLE + 1
		out[i] = string.sub(PAD_CYCLE, index, index)
	end
	return s .. table.concat(out)
end

local xa: { [string]: string } = {}
for key, value in en do
	xa[key] = expand(value)
end

local TABLES: { [string]: { [string]: string } } = { en = en, xa = xa }
strings.TABLES = TABLES

function strings.format(template: string, subs: { [string]: string }?): string
	if subs == nil then
		return template
	end
	return (
		string.gsub(template, "{(%w+)}", function(name: string): string
			local value = subs[name]
			return if value ~= nil then value else "{" .. name .. "}"
		end)
	)
end

function strings.get(locale: string, key: string, subs: { [string]: string }?): string
	local table_ = TABLES[locale] or en
	local value = table_[key]
	if value == nil then
		value = en[key]
	end
	if value == nil then
		return key
	end
	return strings.format(value, subs)
end

function strings.has(key: string): boolean
	return en[key] ~= nil
end

function strings.keys(): { string }
	local out: { string } = {}
	for key in en do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

return strings

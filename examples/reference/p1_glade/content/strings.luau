--!strict
-- Glade (RA-P1) — the proof's OWN string table, keyed by locale (spec §13).
--
-- Facet measures and reflows; it does not own copy, plurals, dates or
-- expansion. So the proof ships its own table, and a second locale `xa` that
-- exists for exactly one purpose: proving every screen survives a ~1.4×
-- expansion without clipping essential text.
--
-- `xa` is DERIVED, not authored. A hand-written pseudo-locale drifts the moment
-- a key is added — one string gets forgotten, the audit passes, and the screen
-- that would have clipped is the one nobody translated. So the expansion is a
-- pure function of the `en` value, applied to every key at load: the padding is
-- `ceil(#en * 0.4)` characters, which makes `#xa == ceil(#en * 1.4)` exactly, for
-- every key, forever. `tests/reference/glade_spec.luau` pins that identity.
--
-- Padding is appended, never interleaved, so `{placeholder}` spans survive
-- untouched and substitution behaves identically in both locales.

local strings = {}

strings.LOCALES = { "en", "xa" }
strings.DEFAULT_LOCALE = "en"

-- The one non-ASCII price mark this proof draws. `newRating` chose ★/☆ the same
-- way — BMP characters confirmed to draw on a real device in the fonts this
-- library ships against — so the price glyph reuses that confirmed character
-- rather than gambling on a rarer "spark" codepoint.
strings.PRICE_MARK = "★"

local en: { [string]: string } = {
	-- shell -----------------------------------------------------------------
	["app.title"] = "Glade",
	["section.glades"] = "Glades",
	["section.wisps"] = "Wisps",
	["section.flora"] = "Flora",
	["section.keeper"] = "Keeper",
	-- THE TERSE TAB VOCABULARY (director refinement 2026-08-09: a bottom tab bar
	-- speaks the compact form, because a thumb-zone band is where cut-off text
	-- shows up first). It is a second LOCALIZED string rather than the framework's
	-- `compactLabel`, which is construction-only and so could not follow this
	-- proof's live locale flip. Three of the four section names are already at
	-- their terse form — a "short" string invented to differ would be a worse
	-- label, not a shorter one — and the widest of the four, the keeper's, has the
	-- conventional shorter tab name for the player's own section.
	["section.glades.short"] = "Glades",
	["section.wisps.short"] = "Wisps",
	["section.flora.short"] = "Flora",
	["section.keeper.short"] = "You",

	-- S1 overview -----------------------------------------------------------
	["overview.search"] = "Find a glade",
	["overview.visiting"] = " is visiting ",
	["overview.noMatches"] = 'No glades match "{term}".',
	["overview.clearSearch"] = "Clear search",
	["overview.favorite"] = "Favorite",
	["overview.open"] = "Open {glade}",
	["offer.pitch"] = "Keep every glade open, and the wisps arrive sooner.",
	["offer.cta"] = "See the Charm",
	["offer.dismiss"] = "Dismiss",

	-- supplies --------------------------------------------------------------
	["supply.nectar"] = "Nectar",
	["supply.dew"] = "Dew",
	["supply.low"] = "Low",
	["supply.empty"] = "Empty",
	["supply.caption"] = "{remaining} left — refills the glow",
	["supply.captionEmpty"] = "Nothing left — refills the glow",

	-- S2 detail -------------------------------------------------------------
	["detail.back"] = "Back",
	["detail.chooseNectar"] = "Choose nectar",
	["detail.refillDew"] = "Refill dew",
	["detail.visitors"] = "Recent visitors",
	["detail.noVisitors"] = "No visitors yet — keep the dew fresh.",

	-- S3 nectar picker ------------------------------------------------------
	["picker.title"] = "Choose nectar",
	["picker.done"] = "Done",
	["picker.premium"] = "Premium",
	["picker.standard"] = "Standard",
	["picker.shopRow"] = "Provision Shop",
	["picker.choose"] = "Choose",
	["picker.use"] = "Use 1",
	["picker.shop"] = "Shop",
	["picker.pending"] = "Confirming…",

	-- S4 provision shop -----------------------------------------------------
	["shop.title"] = "Provision Shop",
	["shop.bestValue"] = "Best value",
	["shop.more"] = "More provisions",
	["shop.buy"] = "Buy",
	["shop.single"] = "One jar",
	["shop.bundle"] = "Five jars",

	-- S5 Keeper's Charm -----------------------------------------------------
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

	-- S6 wisp info ----------------------------------------------------------
	["wisp.close"] = "Close",
	["wisp.lastSeen"] = "Last seen {when} in {glade}",
	["wisp.neverSeen"] = "Not yet seen",
	["wisp.lumenChip"] = "Lumen only",
	["wisp.lumenPitch"] = "Arrives early for Lumen Keepers",
	["wisp.favourite"] = "Favourite nectar: {nectar}",
	["wisp.activate"] = "About {wisp}",

	-- S7 keeper -------------------------------------------------------------
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

	-- flora (browse-only) ---------------------------------------------------
	["flora.title"] = "Flora",

	-- toasts ----------------------------------------------------------------
	["toast.refill"] = "{glade} is glowing brighter.",
	["toast.purchase"] = "Added to your satchel — {count}× {nectar}",

	-- rejection copy (spec §10) ---------------------------------------------
	["reject.declined"] = "The purchase didn't go through. You weren't charged.",
	["reject.offline"] = "Can't reach the shop right now. Try again in a moment.",
	["reject.owned"] = "You already have this charm tier.",
	["reject.fallback"] = "Something went wrong. You weren't charged.",

	-- proof-owned time formatting (Facet has no date formatter) -------------
	["time.hour"] = "{n}h",
	["time.minute"] = "{n}m",
	["time.second"] = "{n}s",
	["time.ago"] = "{when} ago",
	["time.now"] = "just now",

	-- glade names -----------------------------------------------------------
	["glade.mossholm"] = "Mossholm",
	["glade.fernhollow"] = "Fernhollow",
	["glade.lanternDell"] = "Lantern Dell",
	["glade.brambleRest"] = "Bramble Rest",
	["glade.stillpond"] = "Stillpond",

	-- wisp names + species lines --------------------------------------------
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

	-- nectar names ----------------------------------------------------------
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

	-- flora names (browse-only, spec §3) ------------------------------------
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

-- ---- the derived pseudo-locale ---------------------------------------------

local PAD_CYCLE = "aeiou"

-- expand(s) -> a string exactly `ceil(#s * 1.4)` bytes long. Deterministic,
-- ASCII-only (so no font in the matrix has a coverage excuse), and appended so
-- placeholders and punctuation survive.
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

-- ---- reads ------------------------------------------------------------------

-- format(template, subs) — `{name}` substitution. A key with no substitution
-- table is returned verbatim, so a template accidentally left unsubstituted is
-- VISIBLE ("{glade} is glowing brighter.") rather than silently blank.
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

-- get(locale, key, subs?) — the one read. An unknown key answers the key itself
-- (loud in a capture, and never nil into a Text prop); an unknown locale falls
-- back to `en` rather than blanking the screen.
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

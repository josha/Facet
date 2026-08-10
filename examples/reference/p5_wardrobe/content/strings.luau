--!strict
-- Wardrobe proof strings (RA-P5). `en` plus `xa` pseudo-expansion (≥1.4x,
-- bracketed). All player-facing copy lives here.

local STRINGS: { [string]: { [string]: string } } = {
	en = {
		["section.boutique"] = "Boutique",
		["section.outfits"] = "Outfits",
		["section.profile"] = "Profile",
		["stub.body"] = "Nothing to show yet.",
		["stub.honest"] = "This section is a labeled stub in this proof.",
		["cat.all"] = "All",
		["cat.hats"] = "Hats",
		["cat.hair"] = "Hair",
		["cat.faces"] = "Faces",
		["cat.torso"] = "Torso",
		["cat.legs"] = "Legs",
		["cat.shoes"] = "Shoes",
		["cat.accents"] = "Accents",
		["cat.backdrops"] = "Backdrops",
		["picked.header"] = "Picked for you",
		["everything.header"] = "Everything",
		["filter"] = "Refine",
		["filter.owned"] = "Owned only",
		["filter.sort"] = "Sort",
		["filter.sort.featured"] = "Featured",
		["filter.sort.price"] = "Price: low first",
		["filter.sort.newest"] = "Newest",
		["filter.done"] = "Done",
		["filter.none"] = "Nothing matches",
		["filter.reset"] = "Reset filters",
		["chip.owned"] = "Owned",
		["chip.wearing"] = "Wearing",
		["verified"] = "Verified creator",
		["preview.autorotate"] = "Auto-rotate",
		["preview.unavailable"] = "Live preview isn't available here.",
		["undo"] = "Undo",
		["redo"] = "Redo",
		["buy.cta"] = "Buy %s",
		["buy.cta.compact"] = "Buy",
		["buy.confirm"] = "Confirm",
		["buy.cancel"] = "Not now",
		["buy.pending"] = "Confirming…",
		["buy.after"] = "Leaves you %s",
		["buy.done"] = "%s is yours",
		["err.buy.insufficient"] = "Not enough Sparks — you have %s.",
		["err.buy.soldout"] = "That one just sold out.",
		["err.generic"] = "Something went wrong. Try again.",
		["close.label"] = "Close",
	},
	xa = {
		["section.boutique"] = "[Ɓøůţíƣůé šħøƿƿé~]",
		["section.outfits"] = "[Øůţƒíţš ćĺøšéţ~~]",
		["section.profile"] = "[Ƥŕøƒíĺé ƿáǧé~~~]",
		["stub.body"] = "[Ñøţħíɳǧ áţ áĺĺ ţø šħøẃ ýéţ.]",
		["stub.honest"] = "[Ţħíš šéćţíøɳ íš á ĺáβéĺéď šţůβ íɳ ţħíš ƿŕøøƒ.]",
		["cat.all"] = "[Áĺĺ øƒ ţħéɱ]",
		["cat.hats"] = "[Ħáţš áɳď ćáƿš]",
		["cat.hair"] = "[Ħáíŕ šţýĺéš]",
		["cat.faces"] = "[Ƒáćé ĺøøķš~]",
		["cat.torso"] = "[Ţøŕšø ẃéáŕ~]",
		["cat.legs"] = "[Ĺéǧ ẃéáŕ~~]",
		["cat.shoes"] = "[Šħøéš áɳď βøøţš]",
		["cat.accents"] = "[Áććéɳţ ƿíéćéš]",
		["cat.backdrops"] = "[Ɓáćķďŕøƿ šćéɳéš]",
		["picked.header"] = "[Ƥíćķéď øůţ ĵůšţ ƒøŕ ýøů]",
		["everything.header"] = "[Áβšøĺůţéĺý éνéŕýţħíɳǧ]",
		["filter"] = "[Ŕéƒíɳé ţħé ĺíšţ]",
		["filter.owned"] = "[Øẃɳéď íţéɱš øɳĺý]",
		["filter.sort"] = "[Šøŕţ øŕďéŕ~]",
		["filter.sort.featured"] = "[Ƒéáţůŕéď ƒíŕšţ]",
		["filter.sort.price"] = "[Ƥŕíćé: ĺøẃéšţ ƒíŕšţ]",
		["filter.sort.newest"] = "[Ñéẃéšţ áŕŕíνáĺš ƒíŕšţ]",
		["filter.done"] = "[Ďøɳé ŕéƒíɳíɳǧ]",
		["filter.none"] = "[Ñøţħíɳǧ ɱáţćħéš ţħéšé ƒíĺţéŕš]",
		["filter.reset"] = "[Ŕéšéţ áĺĺ ţħé ƒíĺţéŕš]",
		["chip.owned"] = "[Øẃɳéď~~]",
		["chip.wearing"] = "[Ŵéáŕíɳǧ íţ]",
		["verified"] = "[Ʋéŕíƒíéď ćŕéáţøŕ βáďǧé]",
		["preview.autorotate"] = "[Áůţø-ŕøţáţé ţħé šţáɳď]",
		["preview.unavailable"] = "[Ţħé ĺíνé ƿŕéνíéẃ íšɳ'ţ áνáíĺáβĺé øɳ ţħíš šůŕƒáćé.]",
		["undo"] = "[Ůɳďø ţħé ĺášţ]",
		["redo"] = "[Ŕéďø ţħé ĺášţ]",
		["buy.cta"] = "[Ɓůý ţħé %s ɳøẃ]",
		["buy.cta.compact"] = "[Ɓůý íţ]",
		["buy.confirm"] = "[Ćøɳƒíŕɱ ţħé ƿůŕćħášé]",
		["buy.cancel"] = "[Ñøţ ŕíǧħţ ɳøẃ]",
		["buy.pending"] = "[Ćøɳƒíŕɱíɳǧ ţħé ƿůŕćħášé…]",
		["buy.after"] = "[Ĺéáνéš ýøů ẃíţħ %s]",
		["buy.done"] = "[Ţħé %s íš ýøůŕš ɳøẃ]",
		["err.buy.insufficient"] = "[Ñøţ éɳøůǧħ Šƿáŕķš — ýøů øɳĺý ħáνé %s.]",
		["err.buy.soldout"] = "[Ţħáţ øɳé ĵůšţ šøĺď øůţ ćøɱƿĺéţéĺý.]",
		["err.generic"] = "[Šøɱéţħíɳǧ ẃéɳţ ẃŕøɳǧ šøɱéẃħéŕé. Ţŕý áǧáíɳ.]",
		["close.label"] = "[Ćĺøšé ţħíš]",
	},
}

local strings = {}

strings.locales = { "en", "xa" }

function strings.get(locale: string, key: string, param: string?): string
	local table_ = STRINGS[locale] or STRINGS.en
	local s = table_[key] or STRINGS.en[key] or ("!" .. key .. "!")
	if param ~= nil then
		s = s:format(param)
	end
	return s
end

return strings

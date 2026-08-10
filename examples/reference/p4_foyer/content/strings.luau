--!strict
-- Foyer proof strings (RA-P4). Proof-owned i18n table: `en` plus the `xa`
-- pseudo-expansion locale (every string ≥1.4x the English width, bracketed so a
-- missed lookup is visible on screen). All player-facing copy lives here —
-- a literal in a blueprint is a defect the drift check hunts.

local STRINGS: { [string]: { [string]: string } } = {
	en = {
		["app.name"] = "Foyer",
		["nav.home"] = "Home",
		["nav.crews"] = "Crews",
		["nav.forge"] = "Forge",
		["nav.mail"] = "Mail",
		["nav.you"] = "You",
		["tab.forYou"] = "For you",
		["tab.charts"] = "Charts",
		["search.ph"] = "Search worlds",
		["search.label"] = "Search worlds",
		["search.none"] = "No worlds match",
		["search.clear"] = "Clear search",
		["refresh.label"] = "Refresh the feed",
		["profile.label"] = "Your profile",
		["profile.caption"] = "Exploring since day one",
		["bell.label"] = "Notifications",
		["notices.title"] = "Notifications",
		["invite.label"] = "Invite friends",
		["invite.stub"] = "Inviting friends isn't part of this proof.",
		["section.picked"] = "Picked for you",
		["section.continue"] = "Keep playing",
		["section.new"] = "New this week",
		["section.friends"] = "Friends are in",
		["section.seeAll"] = "See all %s",
		["chip.sponsored"] = "Sponsored",
		["detail.visit"] = "Visit",
		["detail.visiting"] = "Visiting…",
		["toast.visited"] = "Added to Keep playing",
		["toast.refreshed"] = "Feed refreshed",
		["err.feed.refresh.offline"] = "Can't refresh right now — the hallway is quiet. Try again.",
		["err.generic"] = "Something went wrong. Try again.",
		["stub.body"] = "Nothing to show yet.",
		["stub.honest"] = "This wing is a labeled stub in this proof.",
		["close.label"] = "Close",
		["time.now"] = "just now",
		["time.h"] = "%sh ago",
		["time.d"] = "%sd ago",
	},
	xa = {
		["app.name"] = "[Ƒøýéŕ~~~]",
		["nav.home"] = "[Ħøɱé ẃíɳǧ~~]",
		["nav.crews"] = "[Ćŕéẃš ẃíɳǧ~]",
		["nav.forge"] = "[Ƒøŕǧé ẃíɳǧ~]",
		["nav.mail"] = "[Ϻáíĺ ẃíɳǧ~~]",
		["nav.you"] = "[Ýøů ẃíɳǧ~~~]",
		["tab.forYou"] = "[Ƒøŕ ýøů éšƿéćíáĺĺý]",
		["tab.charts"] = "[Ćħáŕţš áɳď ŕáɳķíɳǧš]",
		["search.ph"] = "[Šéáŕćħ áĺĺ ţħé ẃøŕĺďš]",
		["search.label"] = "[Šéáŕćħ áĺĺ ţħé ẃøŕĺďš]",
		["search.none"] = "[Ñø ẃøŕĺďš ɱáţćħ ţħáţ ƣůéŕý]",
		["search.clear"] = "[Ćĺéáŕ ţħé šéáŕćħ ƒíéĺď]",
		["refresh.label"] = "[Ŕéƒŕéšħ ţħé ẃħøĺé ƒééď]",
		["profile.label"] = "[Ýøůŕ øẃɳ ƿŕøƒíĺé ƿáǧé]",
		["profile.caption"] = "[Éxƿĺøŕíɳǧ šíɳćé ţħé νéŕý ƒíŕšţ ďáý]",
		["bell.label"] = "[Ñøţíƒíćáţíøɳš ĺíšţ]",
		["notices.title"] = "[Ñøţíƒíćáţíøɳš ĺíšţ]",
		["invite.label"] = "[Íɳνíţé ýøůŕ ƒŕíéɳďš]",
		["invite.stub"] = "[Íɳνíţíɳǧ ƒŕíéɳďš íšɳ'ţ ƿáŕţ øƒ ţħíš ƿŕøøƒ áţ áĺĺ.]",
		["section.picked"] = "[Ƥíćķéď øůţ ĵůšţ ƒøŕ ýøů]",
		["section.continue"] = "[Ķééƿ øɳ ƿĺáýíɳǧ ţħéšé]",
		["section.new"] = "[Ɓŕáɳď ɳéẃ ţħíš νéŕý ẃééķ]",
		["section.friends"] = "[Ƒŕíéɳďš áŕé íɳ ţħéšé ɳøẃ]",
		["section.seeAll"] = "[Šéé áβšøĺůţéĺý áĺĺ øƒ %s]",
		["chip.sponsored"] = "[Šƿøɳšøŕéď ćøɳţéɳţ]",
		["detail.visit"] = "[Ʋíšíţ ţħíš ẃøŕĺď]",
		["detail.visiting"] = "[Ʋíšíţíɳǧ ţħíš ẃøŕĺď…]",
		["toast.visited"] = "[Áďďéď ţø ţħé Ķééƿ ƿĺáýíɳǧ šħéĺƒ]",
		["toast.refreshed"] = "[Ţħé ƒééď ẃáš ŕéƒŕéšħéď]",
		["err.feed.refresh.offline"] = "[Ćáɳ'ţ ŕéƒŕéšħ ŕíǧħţ ɳøẃ — ţħé ħáĺĺẃáý íš ƣůíéţ. Ţŕý áǧáíɳ ĺáţéŕ.]",
		["err.generic"] = "[Šøɱéţħíɳǧ ẃéɳţ ẃŕøɳǧ šøɱéẃħéŕé. Ţŕý áǧáíɳ.]",
		["stub.body"] = "[Ñøţħíɳǧ áţ áĺĺ ţø šħøẃ ýéţ.]",
		["stub.honest"] = "[Ţħíš ẃíɳǧ íš á ĺáβéĺéď šţůβ íɳ ţħíš ƿŕøøƒ.]",
		["close.label"] = "[Ćĺøšé ţħíš]",
		["time.now"] = "[ĵůšţ ɳøẃ~]",
		["time.h"] = "[%s ħøůŕš áǧø]",
		["time.d"] = "[%s ďáýš áǧø]",
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

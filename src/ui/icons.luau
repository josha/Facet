--!strict

export type IconArt = { assetName: string, contentId: string?, tintRole: string }
local standard_icons = {}

standard_icons.ART = table.freeze({
	["view.grid"] = table.freeze({
		assetName = "facet_icon_view_grid",
		contentId = "rbxassetid://81137934612324",
		tintRole = "content",
	}),
	["view.list"] = table.freeze({
		assetName = "facet_icon_view_list",
		contentId = "rbxassetid://71986932171552",
		tintRole = "content",
	}),
	["view.table"] = table.freeze({
		assetName = "facet_icon_view_table",
		contentId = "rbxassetid://71955029916091",
		tintRole = "content",
	}),
	["settings"] = table.freeze({
		assetName = "facet_icon_settings",
		contentId = "rbxassetid://78513807849201",
		tintRole = "content",
	}),
	["facet:search"] = table.freeze({
		assetName = "facet_icon_search",
		tintRole = "content",
	}),
	["chevron.leading"] = table.freeze({
		assetName = "facet_icon_chevron_left",
		tintRole = "content",
	}),
	["chevron.trailing"] = table.freeze({
		assetName = "facet_icon_chevron_right",
		tintRole = "content",
	}),
	["chevron.up"] = table.freeze({
		assetName = "facet_icon_chevron_up",
		tintRole = "content",
	}),
	["chevron.down"] = table.freeze({
		assetName = "facet_icon_chevron_down",
		tintRole = "content",
	}),

	["chevron.up.chevron.down"] = table.freeze({
		assetName = "facet_icon_chevron_up_down",
		tintRole = "content",
	}),
	["checkmark"] = table.freeze({
		assetName = "facet_icon_check",
		tintRole = "content",
	}),
	["check"] = table.freeze({
		assetName = "facet_icon_check",
		tintRole = "content",
	}),

	["facet:selection.radio.off"] = table.freeze({
		assetName = "facet_icon_radio_off",
		tintRole = "content",
	}),
	["facet:selection.radio.on"] = table.freeze({
		assetName = "facet_icon_radio_on",
		tintRole = "content",
	}),
	["facet:selection.check.off"] = table.freeze({
		assetName = "facet_icon_check_off",
		tintRole = "content",
	}),
	["close"] = table.freeze({
		assetName = "facet_icon_close",
		tintRole = "content",
	}),
	["increment"] = table.freeze({
		assetName = "facet_icon_plus",
		tintRole = "content",
	}),
	["decrement"] = table.freeze({
		assetName = "facet_icon_minus",
		tintRole = "content",
	}),
	["menu"] = table.freeze({
		assetName = "facet_icon_menu",
		tintRole = "content",
	}),
	["more"] = table.freeze({
		assetName = "facet_icon_more",
		tintRole = "content",
	}),
	["edit"] = table.freeze({
		assetName = "facet_icon_edit",
		contentId = "rbxassetid://97349995335189",
		tintRole = "content",
	}),

	["trash"] = table.freeze({
		assetName = "facet_icon_trash",
		contentId = "rbxassetid://84398508341623",
		tintRole = "content",
	}),
	["flag"] = table.freeze({
		assetName = "facet_icon_flag",
		contentId = "rbxassetid://109067109704366",
		tintRole = "content",
	}),

	["status.info"] = table.freeze({
		assetName = "facet_icon_info",
		tintRole = "content",
	}),
	["status.success"] = table.freeze({
		assetName = "facet_icon_success",
		tintRole = "content",
	}),
	["status.warning"] = table.freeze({
		assetName = "facet_icon_warning",
		tintRole = "content",
	}),
	["status.error"] = table.freeze({
		assetName = "facet_icon_error",
		tintRole = "content",
	}),
	["calendar"] = table.freeze({
		assetName = "facet_icon_calendar",
		tintRole = "content",
	}),
	["clock"] = table.freeze({
		assetName = "facet_icon_clock",
		tintRole = "content",
	}),
	["vote.up"] = table.freeze({
		assetName = "facet_icon_thumb_up",
		contentId = "rbxassetid://75207492738442",
		tintRole = "content",
	}),
	["vote.down"] = table.freeze({
		assetName = "facet_icon_thumb_down",
		contentId = "rbxassetid://105653007466295",
		tintRole = "content",
	}),
	["person"] = table.freeze({
		assetName = "facet_icon_person",
		contentId = "rbxassetid://75342910516929",
		tintRole = "content",
	}),
	["chevron.first"] = table.freeze({
		assetName = "facet_icon_chevron_first",
		tintRole = "content",
	}),
	["chevron.last"] = table.freeze({
		assetName = "facet_icon_chevron_last",
		tintRole = "content",
	}),
	["star"] = table.freeze({
		assetName = "facet_icon_star",
		contentId = "rbxassetid://104695763973039",
		tintRole = "content",
	}),
	["heart"] = table.freeze({
		assetName = "facet_icon_heart",
		contentId = "rbxassetid://97016939821888",
		tintRole = "content",
	}),
	["chat"] = table.freeze({
		assetName = "facet_icon_chat",
		contentId = "rbxassetid://101645084139822",
		tintRole = "content",
	}),
	["gift"] = table.freeze({
		assetName = "facet_icon_gift",
		contentId = "rbxassetid://129117910575986",
		tintRole = "content",
	}),
	["coin"] = table.freeze({
		assetName = "facet_icon_coin",
		contentId = "rbxassetid://96906906975801",
		tintRole = "content",
	}),
	["gem"] = table.freeze({
		assetName = "facet_icon_gem",
		contentId = "rbxassetid://71560351614290",
		tintRole = "content",
	}),
	["bag"] = table.freeze({
		assetName = "facet_icon_bag",
		contentId = "rbxassetid://103508277273326",
		tintRole = "content",
	}),
	["trophy"] = table.freeze({
		assetName = "facet_icon_trophy",
		contentId = "rbxassetid://131393157291569",
		tintRole = "content",
	}),
	["crown"] = table.freeze({
		assetName = "facet_icon_crown",
		contentId = "rbxassetid://102786792326123",
		tintRole = "content",
	}),
	["lock"] = table.freeze({
		assetName = "facet_icon_lock",
		contentId = "rbxassetid://93858454796839",
		tintRole = "content",
	}),
	["bolt"] = table.freeze({
		assetName = "facet_icon_bolt",
		contentId = "rbxassetid://97139397993413",
		tintRole = "content",
	}),
	["wrench"] = table.freeze({
		assetName = "facet_icon_wrench",
		contentId = "rbxassetid://106572191354612",
		tintRole = "content",
	}),
	["timer"] = table.freeze({
		assetName = "facet_icon_timer",
		contentId = "rbxassetid://113224887080370",
		tintRole = "content",
	}),
	["car"] = table.freeze({
		assetName = "facet_icon_car",
		contentId = "rbxassetid://117662121804827",
		tintRole = "content",
	}),
}) :: { [string]: IconArt }

standard_icons.BUILTIN = table.freeze({
	speaker = table.freeze({
		assetName = "roblox_speaker",
		contentId = "rbxasset://textures/ui/VoiceChat/SpeakerLight/Unmuted0.png",
		tintRole = "content",
	}),
	volume = table.freeze({
		assetName = "roblox_speaker",
		contentId = "rbxasset://textures/ui/VoiceChat/SpeakerLight/Unmuted0.png",
		tintRole = "content",
	}),
	mute = table.freeze({
		assetName = "roblox_speaker_muted",
		contentId = "rbxasset://textures/ui/VoiceChat/SpeakerLight/Muted.png",
		tintRole = "content",
	}),
}) :: { [string]: IconArt }

function standard_icons.registered(name: string): boolean
	local regular = string.match(name, "^(.+)%.fill$") or name
	return standard_icons.ART[regular] ~= nil or standard_icons.BUILTIN[regular] ~= nil
end

function standard_icons.resolve(name: string): IconArt?
	local entry = standard_icons.ART[name] or standard_icons.BUILTIN[name]
	if entry == nil or type(entry.contentId) ~= "string" or entry.contentId == "" then
		return nil
	end
	return entry
end

return standard_icons

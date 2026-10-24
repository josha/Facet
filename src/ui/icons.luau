--!strict

export type IconArt = { assetName: string, contentId: string, tintRole: string }
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
		contentId = "rbxassetid://85188541706347",
		tintRole = "content",
	}),
	["chevron.leading"] = table.freeze({
		assetName = "facet_icon_chevron_left",
		contentId = "rbxassetid://81739481512878",
		tintRole = "content",
	}),
	["chevron.trailing"] = table.freeze({
		assetName = "facet_icon_chevron_right",
		contentId = "rbxassetid://121626475799702",
		tintRole = "content",
	}),
	["chevron.up"] = table.freeze({
		assetName = "facet_icon_chevron_up",
		contentId = "rbxassetid://92798715826227",
		tintRole = "content",
	}),
	["chevron.down"] = table.freeze({
		assetName = "facet_icon_chevron_down",
		contentId = "rbxassetid://90343755930598",
		tintRole = "content",
	}),

	["chevron.up.chevron.down"] = table.freeze({
		assetName = "facet_icon_chevron_up_down",
		contentId = "rbxassetid://133513168894379",
		tintRole = "content",
	}),
	["checkmark"] = table.freeze({
		assetName = "facet_icon_check",
		contentId = "rbxassetid://108245103349446",
		tintRole = "content",
	}),
	["check"] = table.freeze({
		assetName = "facet_icon_check",
		contentId = "rbxassetid://108245103349446",
		tintRole = "content",
	}),

	["facet:selection.radio.off"] = table.freeze({
		assetName = "facet_icon_radio_off",
		contentId = "rbxassetid://73716910467356",
		tintRole = "content",
	}),
	["facet:selection.radio.on"] = table.freeze({
		assetName = "facet_icon_radio_on",
		contentId = "rbxassetid://113804826986290",
		tintRole = "content",
	}),
	["facet:selection.check.off"] = table.freeze({
		assetName = "facet_icon_check_off",
		contentId = "rbxassetid://121698536401041",
		tintRole = "content",
	}),
	["close"] = table.freeze({
		assetName = "facet_icon_close",
		contentId = "rbxassetid://133198978089241",
		tintRole = "content",
	}),
	["increment"] = table.freeze({
		assetName = "facet_icon_plus",
		contentId = "rbxassetid://128664097463435",
		tintRole = "content",
	}),
	["decrement"] = table.freeze({
		assetName = "facet_icon_minus",
		contentId = "rbxassetid://115068690098353",
		tintRole = "content",
	}),
	["menu"] = table.freeze({
		assetName = "facet_icon_menu",
		contentId = "rbxassetid://119066409501208",
		tintRole = "content",
	}),
	["more"] = table.freeze({
		assetName = "facet_icon_more",
		contentId = "rbxassetid://117014407191998",
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
		contentId = "rbxassetid://119954823374061",
		tintRole = "content",
	}),
	["status.success"] = table.freeze({
		assetName = "facet_icon_success",
		contentId = "rbxassetid://108245103349446",
		tintRole = "content",
	}),
	["status.warning"] = table.freeze({
		assetName = "facet_icon_warning",
		contentId = "rbxassetid://94336971455701",
		tintRole = "content",
	}),
	["status.error"] = table.freeze({
		assetName = "facet_icon_error",
		contentId = "rbxassetid://131379225714116",
		tintRole = "content",
	}),
	["calendar"] = table.freeze({
		assetName = "facet_icon_calendar",
		contentId = "rbxassetid://93477762216058",
		tintRole = "content",
	}),
	["clock"] = table.freeze({
		assetName = "facet_icon_clock",
		contentId = "rbxassetid://101095496899333",
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
		contentId = "rbxassetid://121092340130819",
		tintRole = "content",
	}),
	["chevron.last"] = table.freeze({
		assetName = "facet_icon_chevron_last",
		contentId = "rbxassetid://124199778383157",
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
		contentId = "rbxassetid://119848041941567",
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

function standard_icons.resolve(name: string): IconArt?
	local entry = standard_icons.ART[name] or standard_icons.BUILTIN[name]
	if entry == nil or type(entry.contentId) ~= "string" or entry.contentId == "" then
		return nil
	end
	return entry
end

return standard_icons

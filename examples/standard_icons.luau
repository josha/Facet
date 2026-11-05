--!strict

type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ThemePackage)

local CONTENT = table.freeze({
	bag = "rbxassetid://103508277273326",
	bolt = "rbxassetid://97139397993413",
	calendar = "rbxassetid://93477762216058",
	car = "rbxassetid://117662121804827",
	chat = "rbxassetid://101645084139822",
	check = "rbxassetid://108245103349446",
	checkmark = "rbxassetid://108245103349446",
	["chevron.down"] = "rbxassetid://90343755930598",
	["chevron.first"] = "rbxassetid://121092340130819",
	["chevron.last"] = "rbxassetid://124199778383157",
	["chevron.leading"] = "rbxassetid://81739481512878",
	["chevron.trailing"] = "rbxassetid://121626475799702",
	["chevron.up"] = "rbxassetid://92798715826227",
	["chevron.up.chevron.down"] = "rbxassetid://133513168894379",
	clock = "rbxassetid://101095496899333",
	close = "rbxassetid://133198978089241",
	coin = "rbxassetid://96906906975801",
	crown = "rbxassetid://102786792326123",
	decrement = "rbxassetid://115068690098353",
	edit = "rbxassetid://97349995335189",
	["facet:search"] = "rbxassetid://85188541706347",
	["facet:selection.check.off"] = "rbxassetid://121698536401041",
	["facet:selection.radio.off"] = "rbxassetid://73716910467356",
	["facet:selection.radio.on"] = "rbxassetid://113804826986290",
	flag = "rbxassetid://109067109704366",
	gem = "rbxassetid://71560351614290",
	gift = "rbxassetid://129117910575986",
	heart = "rbxassetid://97016939821888",
	increment = "rbxassetid://128664097463435",
	lock = "rbxassetid://93858454796839",
	menu = "rbxassetid://119066409501208",
	more = "rbxassetid://117014407191998",
	person = "rbxassetid://75342910516929",
	settings = "rbxassetid://78513807849201",
	star = "rbxassetid://104695763973039",
	["status.error"] = "rbxassetid://131379225714116",
	["status.info"] = "rbxassetid://119954823374061",
	["status.success"] = "rbxassetid://108245103349446",
	["status.warning"] = "rbxassetid://94336971455701",
	timer = "rbxassetid://113224887080370",
	trash = "rbxassetid://84398508341623",
	trophy = "rbxassetid://131393157291569",
	["view.grid"] = "rbxassetid://81137934612324",
	["view.list"] = "rbxassetid://71986932171552",
	["view.table"] = "rbxassetid://71955029916091",
	["vote.down"] = "rbxassetid://105653007466295",
	["vote.up"] = "rbxassetid://75207492738442",
	wrench = "rbxassetid://106572191354612",
}) :: { [string]: string }

local standard_icons = {}

standard_icons.CONTENT = CONTENT

function standard_icons.apply(package: ThemePackage): ThemePackage
	local icons = table.clone(package.icons or {})
	for name, content in CONTENT do
		if icons[name] == nil then
			icons[name] = content
		end
	end
	local themed = table.clone(package)
	themed.icons = icons
	return themed
end

return standard_icons

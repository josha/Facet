--!strict
local icons = require("./icons")
local ThemeTypes = require("./theme_types")

local function resolveIcon(package: ThemeTypes.IconRegistry, name: string, state: ThemeTypes.SkinState?): string?
	local assets: { [string]: ThemeTypes.Asset } = package.assets or {}
	local entry: unknown = (package.icons or {})[name] or icons.BUILTIN[name] or icons.ART[name]
	local regular = string.match(name, "^(.+)%.fill$")
	if entry == nil and regular then
		return resolveIcon(package, regular, state)
	end
	if type(entry) == "table" and ((entry :: unknown) :: { default: unknown }).default ~= nil then
		local variants = (entry :: unknown) :: { [string]: string | ThemeTypes.IconAsset }
		entry = variants[state or "default"] or variants.default
	end
	if type(entry) == "string" then
		entry = assets[entry] or { contentId = entry }
	end
	if type(entry) ~= "table" then
		return nil
	end
	local icon = entry :: ThemeTypes.IconAsset
	local asset: ThemeTypes.Asset? = if icon.asset then assets[icon.asset] else icon
	return if asset then asset.contentId or asset.content else nil
end

return resolveIcon

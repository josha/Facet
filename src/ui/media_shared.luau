--!strict
local Types = require("./types")
local Theme = require("./theme_types")
local ComposeTypes = require("../vendor/compose/core")
local bindThemes = require("./themes")

export type Shared = {
	skin: (node: GuiObject, slot: string, options: Theme.SkinOptions?) -> GuiObject,
	bind: <T>(source: Types.Input<T>?, fallback: T) -> Types.Input<T>,
}

return function(ctx: Types.Context): Shared
	local runtime, Compose = ctx.runtime, ctx.Compose
	local themes = bindThemes(Compose)
	local types, read = ctx.types, ctx.read
	local function skin(node: GuiObject, slot: string, options: Theme.SkinOptions?): GuiObject
		local package = ctx.config.theme
		if not Compose.isValue(package) and type(package) ~= "function" then
			local resolved = read(package)
			local recipe = if resolved then (resolved.chrome or {})[slot] else nil
			if recipe == nil or ((recipe.kind == "native" or recipe.kind == "none") and recipe.shadow == nil) then
				return node
			end
		end
		local settings: Theme.SkinOptions = options or {}
		settings.types, settings.target = types, node
		runtime.mount(function()
			return themes.skin(runtime, ctx.config.theme, slot, settings)
		end, node)
		return node
	end

	local function bind<T>(source: Types.Input<T>?, fallback: T): Types.Input<T>
		if not Compose.isValue(source) and type(source) ~= "function" then
			return if source == nil then fallback else source :: T
		end
		local live = source :: Types.Input<T>
		return function(use: ComposeTypes.Use)
			local value = read(live, use)
			return if value == nil then fallback else value
		end
	end
	return { skin = skin, bind = bind }
end

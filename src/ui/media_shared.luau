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
	local presence: { [string]: ComposeTypes.AcquireSharedResource<ComposeTypes.ReadOnlyValue<boolean>> } = {}
	local function needsSkin(slot: string): ComposeTypes.ReadOnlyValue<boolean>
		local acquire: ComposeTypes.AcquireSharedResource<ComposeTypes.ReadOnlyValue<boolean>>? = presence[slot]
		if acquire == nil then
			acquire = Compose.createSharedResource(function(): (ComposeTypes.ReadOnlyValue<boolean>, (() -> ())?)
				return Compose.formula(function(use: ComposeTypes.Use): boolean
					local package = read(ctx.config.theme, use)
					local chrome = if package then package.chrome else nil
					local recipe = if chrome then chrome[slot] else nil
					return recipe ~= nil and (recipe.kind ~= "native" and recipe.kind ~= "none" or recipe.shadow ~= nil)
				end),
					nil
			end)
			presence[slot] = assert(acquire)
		end
		return assert(acquire)()
	end
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
		local needed = needsSkin(slot)
		local attached = false
		runtime.mountFragment(function()
			return {
				Compose.show(function(use: ComposeTypes.Use): boolean
					attached = attached or use(needed)
					return attached
				end, function()
					return themes.skin(runtime, ctx.config.theme, slot, settings)
				end),
			}
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

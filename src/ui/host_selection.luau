--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

type CoreSelection = { SelectedCoreObject: GuiObject? }

return function(
	ctx: Shared.Context,
	watch: (GuiService) -> ComposeTypes.ReadOnlyValue<GuiObject?>
): Shared.HostSelection
	local gui = ctx.config.guiService
	local granted: boolean? = nil

	local function core(): CoreSelection?
		if gui == nil or granted == false then
			return nil
		end
		local host = (gui :: unknown) :: CoreSelection
		if granted == nil then
			granted = pcall(function(): GuiObject?
				return host.SelectedCoreObject
			end)
		end
		return if granted then host else nil
	end

	local function coreHeld(host: CoreSelection): GuiObject?
		local ok, held = pcall(function(): GuiObject?
			return host.SelectedCoreObject
		end)
		return if ok then held else nil
	end

	local function writeCore(host: CoreSelection, target: GuiObject?): boolean
		local ok = pcall(function()
			host.SelectedCoreObject = target
		end)
		if not ok then
			granted = false
		end
		return ok
	end

	local function underCoreGui(target: Instance): boolean
		return target:FindFirstAncestorOfClass("CoreGui") ~= nil
	end

	local function get(): GuiObject?
		local service = gui
		if service == nil then
			return nil
		end
		local host = core()
		local held = if host then coreHeld(host) else nil
		return held or service.SelectedObject
	end

	local function set(target: GuiObject?)
		local service = gui
		if service == nil then
			return
		end
		local host = core()
		if host then
			if target ~= nil and underCoreGui(target) then
				if writeCore(host, target) then
					return
				end
			elseif coreHeld(host) ~= nil and writeCore(host, nil) and target == nil then
				return
			end
		end
		service.SelectedObject = target
	end

	local function changed(listener: () -> ()): () -> ()
		local service = gui
		if service == nil then
			return function() end
		end
		local observation = assert(ctx.runtime.host.observation)
		local stops: { () -> () } = { observation.observeProperty(service, "SelectedObject", listener) }
		if core() then
			local ok, stop = pcall(observation.observeProperty, service, "SelectedCoreObject", listener)
			if ok then
				table.insert(stops, stop)
			end
		end
		return function()
			for _, stop in stops do
				stop()
			end
			table.clear(stops)
		end
	end

	local function observe(): ComposeTypes.ReadOnlyValue<GuiObject?>
		local service = gui
		if service == nil then
			return ctx.Compose.cell<<GuiObject?>>(nil)
		end
		return watch(service)
	end

	return table.freeze({ get = get, set = set, changed = changed, observe = observe })
end

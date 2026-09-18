--!strict

local Children = require "../runtime/children"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"

export type Builder = () -> Host.Node | Children.Directive

local function switch<K>(source: any, branches: { [K]: Builder }, fallback: Builder?): Children.Directive
	local from = Support.sourceOf(source, "switch", "source") :: Types.Body<K>
	if type(branches) ~= "table" then
		Support.optionsOf(branches, "switch", "a table of branches keyed by value")
	end
	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "switch"
		Support.mountPointOf(mountPoint, "switch")
		local disposeCurrent: Types.Dispose? = nil
		local selected: K? = nil
		local started = false

		owner.watch(function(use)
			local key = from(use)
			if started and key == selected then
				return
			end
			started = true
			selected = key

			if disposeCurrent ~= nil then
				disposeCurrent()
				disposeCurrent = nil
			end

			local chosen: Builder? = branches[key]
			if chosen == nil then
				chosen = fallback
			end
			if chosen == nil then
				return
			end

			local pick = chosen :: Builder
			disposeCurrent = Support.mountBuilder(mountPoint, owner, pick, "switch")
		end)
	end
end

return switch

--!strict

local Children = require "../runtime/children"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"

export type Builder = () -> Host.Node | Children.Directive

local function show<T>(condition: Types.Source<T>, builder: Builder, fallback: Builder?): Children.Directive
	local when = Support.sourceOf(condition, "show", "condition") :: Types.Body<T>
	local render = Support.builderOf(builder, "show", "builder") :: Builder
	local otherwise = if fallback ~= nil then Support.builderOf(fallback, "show", "fallback") :: Builder else nil
	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "show"
		Support.mountPointOf(mountPoint, "show")
		local disposeCurrent: Types.Dispose? = nil
		local shown: boolean? = nil

		owner.watch(function(use)
			local truthy = not not when(use)
			if truthy == shown then
				return
			end
			shown = truthy

			if disposeCurrent ~= nil then
				disposeCurrent()
				disposeCurrent = nil
			end

			local pick = if truthy then render else otherwise
			if pick == nil then
				return
			end
			disposeCurrent = Support.mountBuilder(mountPoint, owner, pick, "show")
		end)
	end
end

return show

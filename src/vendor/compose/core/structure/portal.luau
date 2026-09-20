--!strict

local Block = require "../runtime/block"
local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Nodes = require "../ownership/nodes"
local Support = require "./support"

export type Builder = () -> { Host.Node }

local function portal(target: Host.Node, builder: Builder): Children.Directive
	if type(target) ~= "table" and type(target) ~= "userdata" then
		Diagnostics.raise("mount/target-not-a-node", "portal expects a host node to mount into", {
			actual = Diagnostics.describe(target),
			expected = "a node belonging to the host this runtime renders to",
			contract = "a portal's target is borrowed: Compose adds to it and leaves it standing",
			fix = "pass the layer node itself, e.g. portal(screenLayer, function() ... end)",
		})
	end
	local build = Support.builderOf(builder, "portal", "builder") :: Builder
	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "portal"
		Support.mountPointOf(mountPoint, "portal")

		Nodes.markBorrowed(target)
		local elsewhere = Children.wholeOf(mountPoint.host, target)
		Block.mountBlock(elsewhere, owner, build, Block.nameOf(build), nil)
	end
end

return portal

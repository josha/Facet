--!strict
--!nolint LocalUnused
--!nolint LocalShadow
local task = nil -- Disable usage of Roblox's task scheduler

-- [Facet vendor patch] removed instance-path alias: local Package = script.Parent.Parent
local Types = require("../Types")
local External = require("../External")
local doCleanup = require("../Memory/doCleanup")

local function legacyCleanup(
	value: Types.Task
)
	External.logWarn("cleanupWasRenamed")
	return doCleanup(value)
end

return legacyCleanup
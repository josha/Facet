--!strict
-- Headless facade over vendored Fusion 0.3's reactive-state subset.
-- The root vendor/Fusion/init.luau cannot load under Lune because
-- Instances/defaultProps reads Roblox globals (Enum) at require time; the
-- Instances layer is engine-only by design. Everything the scheduler/lifetime
-- conformance work needs (Value/Computed/Observer/scopes/peek) is engine-free
-- and is re-exported here. Callers must run fusion_lune_external.setup() first.

local fusion_headless = {
	scoped = require("../../vendor/Fusion/Memory/scoped"),
	deriveScope = require("../../vendor/Fusion/Memory/deriveScope"),
	innerScope = require("../../vendor/Fusion/Memory/innerScope"),
	doCleanup = require("../../vendor/Fusion/Memory/doCleanup"),
	peek = require("../../vendor/Fusion/State/peek"),
	Value = require("../../vendor/Fusion/State/Value"),
	Computed = require("../../vendor/Fusion/State/Computed"),
	ForValues = require("../../vendor/Fusion/State/ForValues"),
	ForPairs = require("../../vendor/Fusion/State/ForPairs"),
	ForKeys = require("../../vendor/Fusion/State/ForKeys"),
	Observer = require("../../vendor/Fusion/Graph/Observer"),
	Contextual = require("../../vendor/Fusion/Utility/Contextual"),
	Safe = require("../../vendor/Fusion/Utility/Safe"),
}

return fusion_headless

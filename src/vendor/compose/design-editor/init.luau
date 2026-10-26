--!strict

local Compose = require "./core"
local Design = require "./design"
local Environment = require "@self/environment"
local Editor = require "@self/editor"
local UI = require "@self/ui"
local RobloxLibrary = require "@self/roblox-library"
local Roblox3DLibrary = require "@self/roblox-3d-library"

export type Environment = Environment.Environment
export type Values = Environment.Values
export type Point = UI.Point
export type Editor = Editor.Editor
export type Options = Editor.Options & { environment: Environment.Environment }

local function create(
	library: Design.Library,
	initial: Design.Document,
	parent: Compose.Node,
	options: Options
): Editor.Editor
	local ui = UI.create(options.runtime, options.environment)
	local ok, result = pcall(function(): Editor.Editor
		return Compose.withOwner(ui.owner, function(): Editor.Editor
			return Editor(ui)(library, initial, parent, options)
		end)
	end)
	if not ok then
		local cleaned, failure: unknown = pcall(ui.dispose)
		if not cleaned then
			error(`{tostring(result)}\n{tostring(failure)}`, 0)
		end
		error(result, 0)
	end
	local disposed = false
	return {
		root = result.root,
		session = result.session,
		stage = result.stage,
		scene = result.scene,
		dispose = function()
			if disposed then
				return
			end
			disposed = true
			local released, failure: unknown = pcall(result.dispose)
			local cleaned, cleanupFailure: unknown = pcall(ui.dispose)
			if not released then
				error(if cleaned then failure else `{tostring(failure)}\n{tostring(cleanupFailure)}`, 0)
			elseif not cleaned then
				error(cleanupFailure, 0)
			end
		end,
	}
end

return {
	create = create,
	robloxLibrary = RobloxLibrary,
	roblox3DLibrary = Roblox3DLibrary,
}

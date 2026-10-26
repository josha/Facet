--!strict

local Compose = require "./core"
local Design = require "./design"
local DesignTypes = require "./design/types"
local Environment = require "@self/environment"
local Editor = require "@self/editor"
local UI = require "@self/ui"
local RobloxLibrary = require "@self/roblox-library"
local Roblox3DLibrary = require "@self/roblox-3d-library"

export type Environment = Environment.Environment
export type Values = Environment.Values
export type Point = UI.Point
export type Editor = Editor.Editor
export type Device = Editor.Device
export type Preview = Editor.Preview
export type Options = Editor.Options & { environment: Environment.Environment }
export type Workspace = {
	runtime: Compose.Runtime,
	environment: Environment.Environment,
	library: Design.Library,
	root: string,
	stageSize: UI.Point?,
	devices: { Editor.Device }?,
	previews: { Editor.Preview }?,
	token: ((name: string) -> Design.Literal)?,
	resolveToken: ((name: string) -> Design.Resolved)?,
	tokens: { string }?,
	slots: { [string]: () -> unknown }?,
	dispose: (() -> ())?,
}
export type Kit = DesignTypes.Kit

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

local function kit(name: string, open: () -> Workspace): Kit
	return {
		name = name,
		edit = function(parent: Compose.Node, documentName: string, link: Design.LinkStore?): DesignTypes.OpenDesign
			local workspace = open()
			local library = workspace.library
			local initial = Design.document.new(documentName, library, workspace.root)
			if link ~= nil then
				local current = link.read()
				if string.match(current, "^%s*$") then
					link.write(current, Design.emit(initial, library))
				end
			end
			local devices = workspace.devices
			local options: Options = {
				runtime = workspace.runtime,
				environment = workspace.environment,
				stageSize = workspace.stageSize
					or if devices ~= nil and devices[1] ~= nil then devices[1].size else { X = 390, Y = 844 },
				devices = devices,
				previews = workspace.previews,
				token = workspace.token,
				resolveToken = workspace.resolveToken,
				tokens = workspace.tokens,
				slots = workspace.slots,
				link = link,
			}
			local ok, result = pcall(create, library, initial, parent, options)
			local release = workspace.dispose
			if not ok then
				if release ~= nil then
					release()
				end
				error(result, 0)
			end
			local editor = result
			return {
				dispose = function()
					editor.dispose()
					if release ~= nil then
						release()
					end
				end,
			}
		end,
	}
end

return {
	create = create,
	kit = kit,
	robloxLibrary = RobloxLibrary,
	roblox3DLibrary = Roblox3DLibrary,
}

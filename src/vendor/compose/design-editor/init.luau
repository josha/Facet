--!strict

local Compose = require "./core"
local Design = require "./design"
local DesignTypes = require "./design/types"
local Environment = require "@self/environment"
local Editor = require "@self/editor"
local UI = require "@self/ui"
local RobloxLibrary = require "@self/roblox-library"
local Roblox3DLibrary = require "@self/roblox-3d-library"
local Devices = require "@self/devices"
local Canvas = require "@self/canvas"
local Prompt = require "@self/prompt"
local ThemePanel = require "@self/theme-panel"
local Stage3D = require "@self/stage3d"

export type Environment = Environment.Environment
export type Values = Environment.Values
export type Point = UI.Point
export type Editor = Editor.Editor
export type Command = Editor.Command
export type Result = Editor.Result
export type Device = Editor.Device
export type Frame = Canvas.Frame
export type FrameContext = Canvas.Context
export type SlotSample = Canvas.SlotSample
export type PromptRequest = Prompt.Request
export type PromptOptions = Prompt.Options
export type PromptResult = Prompt.Result
export type ThemeValue = ThemePanel.Value
export type ThemeField = ThemePanel.Field
export type ThemeStore = ThemePanel.Store
export type Preview = Editor.Preview
export type Sequences = Roblox3DLibrary.Sequences
export type SceneTarget = Stage3D.Target
export type CameraPreset = Stage3D.Preset
export type CameraState = Stage3D.CameraState
export type Options = Editor.Options & { environment: Environment.Environment }
export type Workspace = {
	identity: { commit: string, path: string }?,
	scene: Stage3D.Target?,
	runtime: Compose.Runtime,
	environment: Environment.Environment,
	library: Design.Library,
	root: string,
	devices: { Editor.Device }?,
	device: string?,
	frame: ((Editor.Device, Compose.ReadOnlyValue<number>) -> Canvas.Context)?,
	prompt: Prompt.Options?,
	theme: ThemePanel.Store?,
	bindings: { [string]: Design.Resolved }?,
	outputs: { [string]: (args: { Design.Literal }) -> () }?,
	backdrop: (() -> unknown)?,
	previews: { Editor.Preview }?,
	token: ((name: string) -> Design.Literal)?,
	resolveToken: ((name: string) -> Design.Resolved)?,
	tokens: { string }?,
	slots: { [string]: () -> unknown }?,
	slotSamples: { [string]: Canvas.SlotSample }?,
	capture: ((name: string, frame: Canvas.Frame) -> { string })?,
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
	local dispose: () -> () = function() end
	local configured = table.clone(options)
	configured.onClose = function()
		dispose()
		if options.onClose then
			options.onClose()
		end
	end
	local ok, result = pcall(function(): Editor.Editor
		return Compose.withOwner(ui.owner, function(): Editor.Editor
			return Editor(
				ui,
				function(
					library: Design.Library,
					initial: Design.Document,
					parent: Compose.Node,
					nestedOptions: Editor.Options
				): Editor.Editor
					return create(library, initial, parent, {
						runtime = nestedOptions.runtime,
						environment = options.environment,
						link = nestedOptions.link,
						token = nestedOptions.token,
						resolveToken = nestedOptions.resolveToken,
						tokens = nestedOptions.tokens,
						stageSize = nestedOptions.stageSize,
					})
				end
			)(library, initial, parent, configured)
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
	end
	local editor: Editor.Editor = {
		root = result.root,
		session = result.session,
		canvas = result.canvas,
		execute = result.execute,
		nested = result.nested,
		dispose = dispose,
	}
	setmetatable(editor, {
		__index = function(_, key: string): unknown
			if key == "stage" then
				return result.canvas.current().stage
			elseif key == "scene" then
				return result.canvas.current().scene
			end
			return nil
		end,
	})
	return editor
end

local function kit(name: string, open: () -> Workspace): Kit
	return {
		name = name,
		edit = function(subject: unknown, documentName: string, link: Design.LinkStore?): DesignTypes.OpenDesign
			local parent = UI.node(subject)
			local workspace = open()
			local library = workspace.library
			local initial = Design.document.new(documentName, library, workspace.root)
			if link ~= nil then
				local current = link.read()
				if string.match(current, "^%s*$") then
					link.write(current, Design.emit(initial, library))
				end
			end
			local devices = workspace.devices or Devices.all
			local released = false
			local function release()
				if not released then
					released = true
					if workspace.dispose then
						workspace.dispose()
					end
				end
			end
			local options: Options = {
				runtime = workspace.runtime,
				environment = workspace.environment,
				scene = workspace.scene,
				identity = workspace.identity,
				devices = devices,
				device = workspace.device,
				frame = workspace.frame,
				prompt = workspace.prompt,
				theme = workspace.theme,
				bindings = workspace.bindings,
				outputs = workspace.outputs,
				backdrop = workspace.backdrop,
				previews = workspace.previews,
				token = workspace.token,
				resolveToken = workspace.resolveToken,
				tokens = workspace.tokens,
				slots = workspace.slots,
				slotSamples = workspace.slotSamples,
				capture = workspace.capture,
				onClose = release,
				link = link,
			}
			local ok, result = pcall(create, library, initial, parent, options)
			if not ok then
				release()
				error(result, 0)
			end
			local editor = result
			return {
				dispose = function()
					editor.dispose()
					release()
				end,
			}
		end,
	}
end

return {
	devices = Devices,
	create = create,
	kit = kit,
	robloxLibrary = RobloxLibrary,
	roblox3DLibrary = Roblox3DLibrary.create,
	roblox3DSchema = Roblox3DLibrary.schema,
}

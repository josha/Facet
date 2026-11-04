--!strict

local Compose = require "../core"
local Design = require "../design"
local Devices = require "./devices"
local UI = require "./ui"
local Stage = require "./stage"
local Stage3D = require "./stage3d"
local Projection = require "./projection"

export type Context = {
	library: Design.Library?,
	token: ((string) -> Design.Literal)?,
	resolveToken: ((string) -> Design.Resolved)?,
	bindings: { [string]: Design.Resolved }?,
	slots: { [string]: () -> unknown }?,
	dispose: (() -> ())?,
}
export type Frame = {
	device: Devices.Profile,
	root: Compose.Node,
	stage: Stage.Stage?,
	scene: Stage3D.Scene?,
	scale: Compose.Value<number>,
}
export type Canvas = {
	root: Compose.Node,
	zoom: Compose.Value<number>,
	all: Compose.Value<boolean>,
	device: Compose.ReadOnlyValue<Devices.Profile>,
	current: () -> Frame,
	frames: () -> { Frame },
	select: (id: string) -> (),
	showAll: (enabled: boolean) -> (),
	fit: () -> (),
	zoomTo: (scale: number, around: UI.Point?) -> (),
	dispose: () -> (),
}
export type Options = Context & {
	devices: { Devices.Profile },
	device: string?,
	frame: ((Devices.Profile, Compose.ReadOnlyValue<number>) -> Context)?,
	readOnly: boolean?,
}

return function(ui: UI.UI, session: Design.Session, parent: Compose.Node, options: Options): Canvas
	local Theme = require "./theme"(ui)
	local root = Theme.scroller "DesignDevices"
	ui.set(root, "BackgroundTransparency", 0)
	ui.set(root, "BackgroundColor3", Theme.color.canvas)
	Theme.place(root, parent, ui.values.udim2(1, 0, 1, 0))
	local grid = ui.new "UIGridLayout"
	ui.set(grid, "CellPadding", ui.values.udim2(0, 16, 0, 16))
	ui.set(grid, "SortOrder", ui.values.enum("SortOrder", "LayoutOrder"))
	local entries: { [number]: Frame } = {}
	local releases: { () -> () } = {}
	local connections: { UI.Connection } = {}
	local active = Compose.cell(1)
	local activeDevice = Compose.formula(function(use: Compose.Use): Devices.Profile
		return assert(options.devices[use(active)])
	end)
	local revision = Compose.cell(0)
	local all = Compose.cell(false)
	local zoom = Compose.cell(1)
	local cancelFit = function(): boolean
		return false
	end
	local function current(): Frame
		return assert(entries[active:peek()], "Design canvas has no frame")
	end
	local function fit()
		for _, entry in entries do
			if all:peek() or entry == current() then
				local view = entry.stage or entry.scene
				assert(view).fit()
			end
		end
	end
	local function layout()
		local size = ui.xy(root, "AbsoluteSize")
		local columns = math.clamp(math.floor(size.X / 280), 1, 4)
		local width = math.max(240, (size.X - (columns - 1) * 16 - 8) / columns)
		local rows = math.ceil(#options.devices / columns)
		local height = if columns == 1
			then width * 0.8 + 56
			else math.max(160, math.min(width * 0.8 + 56, (size.Y - (rows - 1) * 16) / rows))
		ui.set(grid, "FillDirectionMaxCells", columns)
		ui.set(grid, "CellSize", ui.values.udim2(0, width, 0, height))
		ui.set(grid, "Parent", if all:peek() then root else nil)
		ui.set(root, "AutomaticCanvasSize", ui.values.enum("AutomaticSize", if all:peek() then "Y" else "None"))
		for index, entry in entries do
			ui.set(entry.root, "Visible", all:peek() or index == active:peek())
			ui.set(entry.root, "Size", ui.values.udim2(1, 0, 1, 0))
			ui.set(entry.root, "Position", ui.values.udim2(0, 0, 0, 0))
		end
		cancelFit()
		cancelFit = ui.runtime.scheduler(ui.owner).after(0, fit)
	end
	local function ensure(index: number): Frame
		local existing = entries[index]
		if existing then
			return existing
		end
		local device = assert(options.devices[index], "Missing Design device")
		local header = if device.id == "Canvas" then 0 else 56
		local scale = Compose.cell(1)
		local context = if options.frame then options.frame(device, scale) else options
		if options.frame and context.dispose then
			table.insert(releases, Compose.owner.own(ui.owner, context.dispose))
		end
		local frame = Theme.frame(device.id, Theme.color.canvas)
		ui.set(frame, "LayoutOrder", index)
		ui.set(frame, "ClipsDescendants", true)
		ui.set(frame, "Parent", root)
		local name = Theme.label(device.name, Theme.color.text, Theme.size.text, Theme.font.bold)
		ui.set(name, "Name", "DeviceName")
		ui.set(name, "Visible", header > 0)
		Theme.place(name, frame, ui.values.udim2(1, -24, 0, 24), ui.values.udim2(0, 12, 0, 4))
		local facts = Theme.label(
			`{device.size.X} × {device.size.Y} · {device.inputMode} · Text {device.textScale}`,
			Theme.color.secondary,
			Theme.size.small
		)
		ui.set(facts, "Name", "DeviceFacts")
		ui.set(facts, "Visible", header > 0)
		Theme.place(facts, frame, ui.values.udim2(1, -24, 0, 24), ui.values.udim2(0, 12, 0, 28))
		local body = Theme.frame "DeviceCanvas"
		Theme.place(body, frame, ui.values.udim2(1, 0, 1, -header), ui.values.udim2(0, 0, 0, header))
		local library = Projection(ui, context.library or session.library, device)
		local entry: Frame = { device = device, root = frame, scale = scale }
		if library.space == "3d" then
			local resolution = Theme.frame "DeviceResolution"
			ui.set(resolution, "AnchorPoint", ui.values.vector2(0.5, 0.5))
			ui.set(resolution, "Position", ui.values.udim2(0.5, 0, 0.5, 0))
			ui.set(resolution, "Size", ui.values.udim2(0, device.size.X, 0, device.size.Y))
			ui.set(resolution, "ClipsDescendants", true)
			ui.set(resolution, "Parent", body)
			local cameraScale = ui.new "UIScale"
			ui.set(cameraScale, "Parent", resolution)
			local function resize()
				local size = ui.xy(body, "AbsoluteSize")
				local factor = math.max(0.01, math.min(size.X / device.size.X, size.Y / device.size.Y))
				ui.set(cameraScale, "Scale", factor)
				scale:set(factor)
			end
			table.insert(connections, ui.changed(body, "AbsoluteSize", resize))
			resize()
			entry.scene = Stage3D(ui)(session, resolution, {
				readOnly = options.readOnly,
				library = library,
				fieldOfView = device.fieldOfView,
				bindings = context.bindings or options.bindings,
				token = context.token or options.token,
				resolveToken = context.resolveToken or options.resolveToken,
				slots = context.slots or options.slots,
			})
		else
			entry.stage = Stage(ui)(session, body, {
				readOnly = options.readOnly,
				library = library,
				size = { X = device.size.X, Y = device.size.Y },
				compact = #options.devices > 1,
				bindings = context.bindings or options.bindings,
				token = context.token or options.token,
				resolveToken = context.resolveToken or options.resolveToken,
				slots = context.slots or options.slots,
			})
		end
		entries[index] = entry
		revision:update(function(value: number): number
			return value + 1
		end)
		local input = if entry.stage then entry.stage.overlay else assert(entry.scene).viewport
		table.insert(
			connections,
			ui.connect(input, "InputBegan", function()
				active:set(index)
			end)
		)
		return entry
	end
	local first = 1
	for index, device in options.devices do
		if device.id == options.device or device.name == options.device then
			first = index
		end
	end
	ensure(first)
	active:set(first)
	local owner = Compose.createRootOwner(function()
		Compose.watch(function(use: Compose.Use)
			use(revision)
			local selected = use(active)
			for index, entry in entries do
				local view = assert(entry.stage or entry.scene)
				local value = use(view.zoom)
				if entry.stage then
					entry.scale:set(value)
				end
				if index == selected then
					zoom:set(value)
				end
			end
		end)
	end, ui.runtime.reactor)
	local release = Compose.owner.own(ui.owner, owner.dispose)
	table.insert(connections, ui.changed(root, "AbsoluteSize", layout))
	layout()
	return {
		root = root,
		zoom = zoom,
		all = all,
		device = activeDevice,
		current = current,
		frames = function(): { Frame }
			local result: { Frame } = {}
			for index in options.devices do
				if entries[index] then
					table.insert(result, entries[index])
				end
			end
			return result
		end,
		select = function(id: string)
			local found = false
			for index, device in options.devices do
				if device.id == id or device.name == id then
					ensure(index)
					active:set(index)
					found = true
					break
				end
			end
			assert(found, "Unknown Design frame: " .. id)
			layout()
		end,
		showAll = function(enabled: boolean)
			all:set(enabled)
			if enabled then
				for index in options.devices do
					ensure(index)
				end
			end
			layout()
		end,
		fit = fit,
		zoomTo = function(value: number, around: UI.Point?)
			assert(current().stage or current().scene).zoomTo(value, around)
		end,
		dispose = function()
			cancelFit()
			release()
			for _, connection in connections do
				connection:Disconnect()
			end
			for _, entry in entries do
				assert(entry.stage or entry.scene).dispose()
			end
			for _, dispose in releases do
				dispose()
			end
			ui.destroy(root)
			ui.destroy(grid)
		end,
	}
end

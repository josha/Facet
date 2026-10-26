--!strict

local UI = require "./ui"

local Compose = require "../core"
local Design = require "../design"
local Stage = require "./stage"
local Stage3D = require "./stage3d"
local Layers = require "./layers"
local LibraryPanel = require "./library-panel"
local Inspector = require "./inspector"

export type Editor = {
	root: Compose.Node,
	session: Design.Session,
	stage: Stage.Stage?,
	scene: Stage3D.Scene?,
	dispose: () -> (),
}

export type Device = { name: string, size: UI.Point }

export type Preview = { name: string, choices: { string }, initial: string?, select: (choice: string) -> () }

export type Options = {
	stageSize: UI.Point,
	devices: { Device }?,
	previews: { Preview }?,
	token: ((name: string) -> Design.Literal)?,
	tokens: { string }?,
	slots: { [string]: () -> unknown }?,
	onExport: ((source: string) -> ())?,
	link: Design.LinkStore?,
	runtime: Compose.Runtime,
}

return function(ui: UI.UI)
	local Theme = require "./theme"(ui)
	local color = Theme.color
	local size = Theme.size

	local function chip(name: string, text: string, primary: boolean): Compose.Node
		local button = ui.new "TextButton"
		ui.set(button, "Name", name)
		ui.set(button, "AutomaticSize", ui.values.enum("AutomaticSize", "X"))
		ui.set(button, "Size", ui.values.udim2(0, 0, 0, 30))
		ui.set(button, "BorderSizePixel", 0)
		ui.set(button, "AutoButtonColor", false)
		ui.set(button, "BackgroundTransparency", if primary then 0 else 1)
		ui.set(button, "Text", text)
		ui.set(button, "TextColor3", if primary then color.white else color.text)
		ui.set(button, "TextSize", size.text)
		ui.set(button, "FontFace", if primary then Theme.font.bold else Theme.font.medium)
		Theme.corner(button, 6)
		Theme.pad(button, if primary then 14 else 10)
		return button
	end

	local function divider(order: number): Compose.Node
		local line = Theme.frame("Divider", color.raised)
		ui.set(line, "Size", ui.values.udim2(0, 1, 0, 20))
		ui.set(line, "LayoutOrder", order)
		return line
	end

	local function group(name: string, order: number, alignment: unknown): Compose.Node
		local frame = Theme.frame(name)
		ui.set(frame, "AutomaticSize", ui.values.enum("AutomaticSize", "X"))
		ui.set(frame, "Size", ui.values.udim2(0, 0, 1, 0))
		ui.set(frame, "LayoutOrder", order)
		local layout = Theme.list(
			frame,
			ui.values.enum("FillDirection", "Horizontal"),
			2,
			ui.values.enum("VerticalAlignment", "Center")
		)
		ui.set(layout, "HorizontalAlignment", alignment)
		return frame
	end

	return function(library: Design.Library, initial: Design.Document, parent: Compose.Node, options: Options): Editor
		local session = Design.session(library, initial)
		local root = Theme.frame("ComposeDesign", color.canvas)
		ui.set(root, "Size", ui.values.udim2(1, 0, 1, 0))
		local toolbar = Theme.frame("Toolbar", color.panel)
		ui.set(toolbar, "Size", ui.values.udim2(1, 0, 0, size.toolbar))
		ui.set(toolbar, "Parent", root)
		local toolRule = Theme.frame("Rule", color.divider)
		ui.set(toolRule, "AnchorPoint", ui.values.vector2(0, 1))
		ui.set(toolRule, "Position", ui.values.udim2(0, 0, 1, 0))
		ui.set(toolRule, "Size", ui.values.udim2(1, 0, 0, 1))
		ui.set(toolRule, "Parent", toolbar)
		local leftTools = group("Insert", 1, ui.values.enum("HorizontalAlignment", "Left"))
		ui.set(leftTools, "Position", ui.values.udim2(0, size.gutter, 0, 0))
		ui.set(leftTools, "Parent", toolbar)
		local brand = Theme.label("◆", color.accent, 18, Theme.font.bold)
		ui.set(brand, "Name", "Brand")
		ui.set(brand, "Size", ui.values.udim2(0, 24, 0, 30))
		ui.set(brand, "TextXAlignment", ui.values.enum("TextXAlignment", "Center"))
		ui.set(brand, "LayoutOrder", 0)
		ui.set(brand, "Parent", leftTools)
		local rightTools = group("Actions", 3, ui.values.enum("HorizontalAlignment", "Right"))
		ui.set(rightTools, "AnchorPoint", ui.values.vector2(1, 0))
		ui.set(rightTools, "Position", ui.values.udim2(1, -size.gutter, 0, 0))
		ui.set(rightTools, "Parent", toolbar)
		local heading = Theme.label("", color.text, size.title, Theme.font.bold)
		ui.set(heading, "Name", "DocumentTitle")
		ui.set(heading, "AnchorPoint", ui.values.vector2(0.5, 0.5))
		ui.set(heading, "Position", ui.values.udim2(0.5, 0, 0.5, 0))
		ui.set(heading, "Size", ui.values.udim2(0, 320, 0, 20))
		ui.set(heading, "TextXAlignment", ui.values.enum("TextXAlignment", "Center"))
		ui.set(heading, "RichText", true)
		ui.set(heading, "Parent", toolbar)
		local function side(name: string, title: string, anchor: number): (Compose.Node, Compose.Node)
			local frame = Theme.frame(name, color.panel)
			ui.set(frame, "AnchorPoint", ui.values.vector2(anchor, 0))
			ui.set(frame, "Position", ui.values.udim2(anchor, 0, 0, size.toolbar))
			ui.set(frame, "Size", ui.values.udim2(0, size.side, 1, -size.toolbar - size.status))
			ui.set(frame, "Parent", root)
			local rule = Theme.frame("Rule", color.divider)
			ui.set(rule, "AnchorPoint", ui.values.vector2(1 - anchor, 0))
			ui.set(rule, "Position", ui.values.udim2(1 - anchor, 0, 0, 0))
			ui.set(rule, "Size", ui.values.udim2(0, 1, 1, 0))
			ui.set(rule, "Parent", frame)
			local caption = Theme.label(title, color.text, size.small, Theme.font.bold)
			ui.set(caption, "Name", "Caption")
			ui.set(caption, "Position", ui.values.udim2(0, size.gutter + 4, 0, 0))
			ui.set(caption, "Size", ui.values.udim2(1, -2 * size.gutter, 0, size.header))
			ui.set(caption, "Parent", frame)
			local body = Theme.frame "Body"
			ui.set(body, "Position", ui.values.udim2(0, 0, 0, size.header))
			ui.set(body, "Size", ui.values.udim2(1, -1, 1, -size.header))
			ui.set(body, "Parent", frame)
			return frame, body
		end
		local libraryFrame, libraryBody = side("LibraryPanel", "Library", 0)
		ui.set(libraryFrame, "Size", ui.values.udim2(0, size.side, 0.45, -size.toolbar))
		local layersFrame, left = side("LayersPanel", "Layers", 0)
		ui.set(layersFrame, "Position", ui.values.udim2(0, 0, 0.45, 0))
		ui.set(layersFrame, "Size", ui.values.udim2(0, size.side, 0.55, -size.status))
		local _, right = side("InspectorPanel", "Design", 1)
		local center = Theme.frame("StagePanel", color.canvas)
		ui.set(center, "Position", ui.values.udim2(0, size.side, 0, size.toolbar))
		ui.set(center, "Size", ui.values.udim2(1, -2 * size.side, 1, -size.toolbar - size.status))
		ui.set(center, "ClipsDescendants", true)
		ui.set(center, "Parent", root)
		local status = Theme.frame("StatusBar", color.panel)
		ui.set(status, "AnchorPoint", ui.values.vector2(0, 1))
		ui.set(status, "Position", ui.values.udim2(0, 0, 1, 0))
		ui.set(status, "Size", ui.values.udim2(1, 0, 0, size.status))
		ui.set(status, "Parent", root)
		local statusRule = Theme.frame("Rule", color.divider)
		ui.set(statusRule, "Size", ui.values.udim2(1, 0, 0, 1))
		ui.set(statusRule, "Parent", status)
		local problem = Theme.label("", color.tertiary, size.small)
		ui.set(problem, "Name", "Problem")
		ui.set(problem, "Position", ui.values.udim2(0, size.gutter, 0, 0))
		ui.set(problem, "Size", ui.values.udim2(0.6, 0, 1, 0))
		ui.set(problem, "Parent", status)
		local zoomLabel = ui.new "TextButton"
		ui.set(zoomLabel, "Name", "Zoom")
		ui.set(zoomLabel, "BackgroundTransparency", 1)
		ui.set(zoomLabel, "AutoButtonColor", false)
		ui.set(zoomLabel, "AnchorPoint", ui.values.vector2(0.5, 0))
		ui.set(zoomLabel, "Position", ui.values.udim2(0.5, 0, 0, 0))
		ui.set(zoomLabel, "Size", ui.values.udim2(0, 64, 0, size.status))
		ui.set(zoomLabel, "TextColor3", color.secondary)
		ui.set(zoomLabel, "TextSize", size.small)
		ui.set(zoomLabel, "FontFace", Theme.font.bold)
		ui.set(zoomLabel, "Parent", status)
		local hint = Theme.label(
			"⇧1 Fit   ⌘Z Undo   ⌘D Duplicate   ⌫ Delete   Tab Next   Esc Parent",
			color.tertiary,
			size.small
		)
		ui.set(hint, "Name", "Shortcuts")
		ui.set(hint, "AnchorPoint", ui.values.vector2(1, 0))
		ui.set(hint, "Position", ui.values.udim2(1, -size.gutter, 0, 0))
		ui.set(hint, "Size", ui.values.udim2(0.4, 0, 1, 0))
		ui.set(hint, "TextXAlignment", ui.values.enum("TextXAlignment", "Right"))
		ui.set(hint, "Parent", status)
		local syncButton = ui.new "TextButton"
		ui.set(syncButton, "Name", "Sync")
		ui.set(syncButton, "BackgroundTransparency", 1)
		ui.set(syncButton, "AutoButtonColor", false)
		ui.set(syncButton, "AnchorPoint", ui.values.vector2(0.5, 0))
		ui.set(syncButton, "Position", ui.values.udim2(0.5, 96, 0, 0))
		ui.set(syncButton, "Size", ui.values.udim2(0, 160, 0, size.status))
		ui.set(syncButton, "TextSize", size.small)
		ui.set(syncButton, "FontFace", Theme.font.bold)
		ui.set(syncButton, "Text", "")
		ui.set(syncButton, "Parent", status)
		ui.set(root, "Parent", parent)
		type View = {
			zoom: Compose.Value<number>,
			fit: () -> (),
			zoomTo: (scale: number, around: UI.Point?) -> (),
			dispose: () -> (),
		}
		local stage: Stage.Stage? = nil
		local scene: Stage3D.Scene? = nil
		local view: View
		if library.space == "3d" then
			local built = Stage3D(ui)(session, center, {
				accent = color.accent,
				token = options.token,
				slots = options.slots,
			})
			scene = built
			view = { zoom = built.zoom, fit = built.fit, zoomTo = built.zoomTo, dispose = built.dispose }
		else
			local built = Stage(ui)(session, center, {
				size = options.stageSize,
				accent = color.accent,
				token = options.token,
				slots = options.slots,
			})
			stage = built
			view = { zoom = built.zoom, fit = built.fit, zoomTo = built.zoomTo, dispose = built.dispose }
		end
		local layers = Layers(ui)(session, left)
		local libraryPanel = LibraryPanel(ui)(session, libraryBody)
		local inspector = Inspector(ui)(session, right, {
			tokens = options.tokens,
			play = function(sequence: string)
				local flat = stage
				if flat then
					flat.play(sequence)
				end
			end,
			measure = function(id: string, key: string): number?
				local flat = stage
				local instance: Compose.Node? = if flat then flat.nodes[id] else nil
				if instance == nil then
					return nil
				end
				local scale = view.zoom:peek()
				if key == "width" then
					return ui.xy(instance, "AbsoluteSize").X / scale
				elseif key == "height" then
					return ui.xy(instance, "AbsoluteSize").Y / scale
				end
				return nil
			end,
		})
		local connections: { UI.Connection } = {}
		local function action(
			name: string,
			text: string,
			order: number,
			container: Compose.Node,
			primary: boolean,
			run: () -> ()
		): Compose.Node
			local button = chip(name, text, primary)
			ui.set(button, "LayoutOrder", order)
			local rest = if primary then color.accent else color.panel
			local over = if primary then ui.rgb(56, 172, 255) else color.hover
			ui.set(button, "BackgroundColor3", rest)
			for _, connection in Theme.hover(button, rest, over, if primary then 0 else 1) do
				table.insert(connections, connection)
			end
			table.insert(
				connections,
				ui.connect(button, "Activated", function()
					run()
				end)
			)
			ui.set(button, "Parent", container)
			return button
		end
		local previewOrder = 10
		local function cycling(name: string, choices: { string }, initial: string?, select: (choice: string) -> ())
			if #choices == 0 then
				return
			end
			local at = math.max(1, table.find(choices, initial or choices[1]) or 1)
			local button: Compose.Node? = nil
			button = action(name, choices[at], previewOrder, leftTools, false, function()
				at = at % #choices + 1
				local chosen = choices[at]
				ui.set(assert(button), "Text", chosen)
				select(chosen)
			end)
			previewOrder += 1
		end
		local devices = options.devices
		if devices and #devices > 0 and stage then
			local flat = stage
			local names: { string } = {}
			for _, device in devices do
				table.insert(names, device.name)
			end
			ui.set(divider(previewOrder), "Parent", leftTools)
			previewOrder += 1
			cycling("Device", names, nil, function(choice: string)
				for _, device in devices do
					if device.name == choice then
						flat.resize(device.size)
					end
				end
			end)
		end
		local previews = options.previews
		if previews then
			for _, preview in previews do
				cycling(preview.name, preview.choices, preview.initial, preview.select)
			end
		end
		local undo = action("Undo", "Undo", 1, rightTools, false, function()
			session.undo()
		end)
		local redo = action("Redo", "Redo", 2, rightTools, false, function()
			session.redo()
		end)
		ui.set(divider(3), "Parent", rightTools)
		local _ = action("Duplicate", "Duplicate", 4, rightTools, false, function()
			session.duplicate()
		end)
		local _ = action("Delete", "Delete", 5, rightTools, false, function()
			session.remove()
		end)
		local exportHandler = options.onExport
		if exportHandler then
			local onExport = exportHandler
			local spacer = Theme.frame "Spacer"
			ui.set(spacer, "Size", ui.values.udim2(0, 6, 0, 1))
			ui.set(spacer, "LayoutOrder", 6)
			ui.set(spacer, "Parent", rightTools)
			local _ = action("Export", "Export", 7, rightTools, true, function()
				onExport(Design.emit(session.document:peek(), library))
			end)
		end
		local context = ui.new "InputContext"
		ui.set(context, "Name", "ComposeDesignShortcuts")
		ui.set(context, "Sink", true)
		local function bind(name: string, run: () -> (), keys: { { unknown } })
			local inputAction = ui.new "InputAction"
			ui.set(inputAction, "Name", name)
			for _, combo in keys do
				local binding = ui.new "InputBinding"
				ui.set(binding, "KeyCode", combo[1])
				if combo[2] then
					ui.set(binding, "PrimaryModifier", combo[2])
				end
				if combo[3] then
					ui.set(binding, "SecondaryModifier", combo[3])
				end
				ui.set(binding, "Parent", inputAction)
			end
			table.insert(
				connections,
				ui.connect(inputAction, "Pressed", function()
					local UserInputService = ui.service "UserInputService"
					local focused: Compose.Node? = ui.call(UserInputService, "GetFocusedTextBox")
					if not focused then
						run()
					end
				end)
			)
			ui.set(inputAction, "Parent", context)
		end
		bind("Delete", function()
			session.remove()
		end, { { ui.values.enum("KeyCode", "Delete") }, { ui.values.enum("KeyCode", "Backspace") } })
		bind("Duplicate", function()
			session.duplicate()
		end, {
			{ ui.values.enum("KeyCode", "D"), ui.values.enum("KeyCode", "LeftControl") },
			{ ui.values.enum("KeyCode", "D"), ui.values.enum("KeyCode", "LeftMeta") },
		})
		bind("Undo", function()
			session.undo()
		end, {
			{ ui.values.enum("KeyCode", "Z"), ui.values.enum("KeyCode", "LeftControl") },
			{ ui.values.enum("KeyCode", "Z"), ui.values.enum("KeyCode", "LeftMeta") },
		})
		bind("Redo", function()
			session.redo()
		end, {
			{ ui.values.enum("KeyCode", "Y"), ui.values.enum("KeyCode", "LeftControl") },
			{
				ui.values.enum("KeyCode", "Z"),
				ui.values.enum("KeyCode", "LeftControl"),
				ui.values.enum("KeyCode", "LeftShift"),
			},
			{
				ui.values.enum("KeyCode", "Z"),
				ui.values.enum("KeyCode", "LeftMeta"),
				ui.values.enum("KeyCode", "LeftShift"),
			},
		})
		bind("Fit", function()
			view.fit()
		end, { { ui.values.enum("KeyCode", "One"), ui.values.enum("KeyCode", "LeftShift") } })
		bind("Actual", function()
			view.zoomTo(1)
		end, { { ui.values.enum("KeyCode", "Zero"), ui.values.enum("KeyCode", "LeftShift") } })
		bind("ZoomIn", function()
			view.zoomTo(view.zoom:peek() * 1.25)
		end, {
			{ ui.values.enum("KeyCode", "Equals"), ui.values.enum("KeyCode", "LeftControl") },
			{ ui.values.enum("KeyCode", "Equals"), ui.values.enum("KeyCode", "LeftMeta") },
		})
		bind("ZoomOut", function()
			view.zoomTo(view.zoom:peek() / 1.25)
		end, {
			{ ui.values.enum("KeyCode", "Minus"), ui.values.enum("KeyCode", "LeftControl") },
			{ ui.values.enum("KeyCode", "Minus"), ui.values.enum("KeyCode", "LeftMeta") },
		})
		bind("Parent", function()
			session.selectRelative "parent"
		end, { { ui.values.enum("KeyCode", "Escape") } })
		bind("Child", function()
			session.selectRelative "child"
		end, { { ui.values.enum("KeyCode", "Return") } })
		bind("Next", function()
			session.selectRelative "next"
		end, { { ui.values.enum("KeyCode", "Tab") } })
		bind("Previous", function()
			session.selectRelative "previous"
		end, { { ui.values.enum("KeyCode", "Tab"), ui.values.enum("KeyCode", "LeftShift") } })
		ui.set(context, "Parent", root)
		table.insert(
			connections,
			ui.connect(zoomLabel, "Activated", function()
				view.fit()
			end)
		)
		local scheduler = options.runtime.scheduler(ui.owner)
		scheduler.after(0, view.fit)
		local linkStore = options.link
		local link = if linkStore then Design.link(session, linkStore) else nil
		local unlink = if link then Compose.owner.own(ui.owner, link.dispose) else nil
		if link then
			local active = link
			table.insert(
				connections,
				ui.connect(syncButton, "Activated", function()
					if active.status:peek() ~= "synchronized" then
						active.import()
					end
				end)
			)
		end
		local owner = Compose.createRootOwner(function()
			if link then
				local active = link
				Compose.watch(function(use: Compose.Use)
					local state = use(active.status)
					ui.set(
						syncButton,
						"Text",
						if state == "synchronized"
							then "● Source synced"
							elseif state == "conflict" then "▲ Source changed · Import"
							else "○ Custom source · Import"
					)
					ui.set(
						syncButton,
						"TextColor3",
						if state == "synchronized"
							then ui.rgb(80, 200, 120)
							elseif state == "conflict" then color.danger
							else color.tertiary
					)
				end)
			end
			Compose.watch(function(use: Compose.Use)
				local message = use(session.problem)
				ui.set(problem, "Text", message or "Ready")
				ui.set(problem, "TextColor3", if message then color.danger else color.tertiary)
			end)
			Compose.watch(function(use: Compose.Use)
				ui.set(zoomLabel, "Text", `{math.round(use(view.zoom) * 100)}%`)
			end)
			Compose.watch(function(use: Compose.Use)
				local value = use(session.document)
				ui.set(heading, "Text", `{value.name}  <font color="#78787E">· {library.name}</font>`)
			end)
			Compose.watch(function(use: Compose.Use)
				ui.set(undo, "TextColor3", if use(session.canUndo) then color.text else color.tertiary)
				ui.set(redo, "TextColor3", if use(session.canRedo) then color.text else color.tertiary)
			end)
		end, ui.runtime.reactor)
		local release = Compose.owner.own(ui.owner, owner.dispose)
		return {
			root = root,
			session = session,
			stage = stage,
			scene = scene,
			dispose = function()
				release()
				if unlink then
					unlink()
				end
				for _, connection in connections do
					connection:Disconnect()
				end
				view.dispose()
				layers.dispose()
				libraryPanel.dispose()
				inspector.dispose()
				ui.destroy(root)
			end,
		}
	end
end

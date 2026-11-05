--!strict

local Compose = require "../core"
local Design = require "../design"
local Devices = require "./devices"
local Canvas = require "./canvas"
local Drafts = require "./drafts"
local UI = require "./ui"

export type Segment = { id: string, name: string, kind: string }
export type Request = {
	designPath: string,
	nodePath: { Segment },
	props: { [string]: Design.Value },
	tokens: { string },
	frame: Devices.Profile,
	source: string,
	request: string,
	count: number,
}
export type Result = string | Drafts.Draft
export type Options = { designPath: string, submit: (Request) -> Result, theme: ((Request) -> string)? }

local function snapshot(session: Design.Session, device: Devices.Profile, path: string, text: string): Request
	local document = Design.document.copy(session.document:peek())
	local selected = session.selected:peek()
	local route: { Segment } = {}
	local target: Design.Node? = nil
	local function visit(node: Design.Node): boolean
		table.insert(route, { id = node.id, name = node.name, kind = node.kind })
		if node.id == selected then
			target = node
			return true
		end
		for _, child in node.children do
			if visit(child) then
				return true
			end
		end
		table.remove(route)
		return false
	end
	assert(visit(document.root), "Select a Design node first")
	local props = assert(target).props
	local tokens: { string } = {}
	local function token(name: string)
		if not table.find(tokens, name) then
			table.insert(tokens, name)
		end
	end
	local function literal(value: Design.Literal)
		if type(value) ~= "table" then
			return
		end
		if type(value.token) == "string" then
			token(value.token)
		end
		for _, child in value do
			literal(child)
		end
	end
	for _, value in props do
		if value.token then
			token(value.token)
		end
		if value.literal ~= nil then
			literal(value.literal)
		end
	end
	table.sort(tokens)
	local counted = string.gsub(string.gsub(string.lower(text), "%f[%a]two%f[%A]", "2"), "%f[%a]three%f[%A]", "3")
	local count = tonumber(string.match(counted, "%f[%d]([23])%s+variants?%f[%A]")) or 1
	return {
		designPath = path,
		nodePath = route,
		props = props,
		tokens = tokens,
		frame = device,
		source = Design.emit(document, session.library),
		request = text,
		count = count,
	}
end

local function create(
	ui: UI.UI,
	session: Design.Session,
	canvas: Canvas.Canvas,
	parent: Compose.Node,
	options: Options,
	render: Drafts.Render
)
	local Theme = require "./theme"(ui)
	local panel = Theme.frame("DesignPrompt", Theme.color.panel)
	ui.set(panel, "AnchorPoint", ui.values.vector2(0, 1))
	Theme.place(panel, parent, ui.values.udim2(1, 0, 0, 140), ui.values.udim2(0, 0, 1, 0))
	ui.set(canvas.root, "Size", ui.values.udim2(1, 0, 1, -140))
	local caption = Theme.label("", Theme.color.secondary, Theme.size.small)
	ui.set(caption, "Name", "PromptTarget")
	Theme.place(caption, panel, ui.values.udim2(1, -24, 0, 24), ui.values.udim2(0, 12, 0, 4))
	local field = Theme.field ""
	ui.set(field, "Name", "PromptRequest")
	ui.set(field, "PlaceholderText", "Describe a change to the selected node")
	ui.set(field, "MultiLine", true)
	ui.set(field, "TextWrapped", true)
	ui.set(field, "TextYAlignment", ui.values.enum("TextYAlignment", "Top"))
	Theme.place(field, panel, ui.values.udim2(1, -24, 0, 56), ui.values.udim2(0, 12, 0, 32))
	local send = Theme.button("SendPrompt", "Apply prompt", Theme.color.white)
	ui.set(send, "BackgroundTransparency", 0)
	ui.set(send, "BackgroundColor3", Theme.color.accent)
	Theme.place(send, panel, ui.values.udim2(0, 140, 0, 32), ui.values.udim2(1, -152, 0, 100))
	Theme.corner(send, 6)
	local status = Theme.label("", Theme.color.secondary, Theme.size.small)
	ui.set(status, "Name", "PromptStatus")
	Theme.place(status, panel, ui.values.udim2(1, -176, 0, 32), ui.values.udim2(0, 12, 0, 100))
	local disposed, busy = false, false
	local draft: { dispose: () -> (), choose: (number) -> () }? = nil
	local function clear()
		if draft then
			draft.dispose()
			draft = nil
		end
		ui.set(canvas.root, "Visible", true)
	end
	local count = 1
	local variants = Theme.button("PromptVariants", "1 variant")
	ui.set(variants, "Position", ui.values.udim2(1, if options.theme then -360 else -256, 0, 100))
	Theme.place(variants, panel, ui.values.udim2(0, 96, 0, 32))
	ui.set(status, "Size", ui.values.udim2(1, if options.theme then -384 else -280, 0, 32))
	local countConnection = ui.connect(variants, "Activated", function()
		if not busy then
			count = count % 3 + 1
			ui.set(variants, "Text", if count == 1 then "1 variant" else `{count} variants`)
		end
	end)
	local theming = false
	local scopeConnection: UI.Connection? = nil
	if options.theme then
		local scope = Theme.button("PromptScope", "Design")
		Theme.place(scope, panel, ui.values.udim2(0, 96, 0, 32), ui.values.udim2(1, -256, 0, 100))
		scopeConnection = ui.connect(scope, "Activated", function()
			if not busy then
				theming = not theming
				ui.set(scope, "Text", if theming then "Theme" else "Design")
				ui.set(send, "Text", if theming then "Apply theme" else "Apply prompt")
				ui.set(variants, "Visible", not theming)
				ui.set(status, "Size", ui.values.udim2(1, if theming then -280 else -384, 0, 32))
			end
		end)
	end
	local function submit(text: string, requestedCount: number?, theme: boolean?)
		assert(not disposed and not busy, "Prompt is busy or closed")
		assert(string.find(text, "%S") and #text <= 8000, "Enter a request of up to 8000 characters")
		assert(
			requestedCount == nil or requestedCount == 1 or requestedCount == 2 or requestedCount == 3,
			"Choose one, two or three variants"
		)
		local request = snapshot(session, canvas.current().device, options.designPath, text)
		local themeRequest = if theme == nil then theming else theme
		local submit: (Request) -> Result = if themeRequest
			then assert(options.theme, "Theme prompt requires a provider")
			else options.submit
		busy = true
		clear()
		request.count = if themeRequest
			then 1
			elseif requestedCount then requestedCount
			elseif request.count > 1 then request.count
			else count
		ui.set(send, "Text", "Working...")
		ui.set(status, "Text", "Capturing the selected frame")
		ui.runtime.scheduler(ui.owner).after(0, function()
			if disposed then
				return
			end
			local submitted, message = pcall(submit, request)
			if disposed then
				return
			end
			busy = false
			ui.set(send, "Text", if theming then "Apply theme" else "Apply prompt")
			if submitted and type(message) == "table" then
				local ok, result = pcall(Drafts, ui, parent, request.frame, message, render, clear)
				if ok then
					draft = result
					ui.set(canvas.root, "Visible", false)
				end
				ui.set(status, "Text", if ok then message.message else "Draft preview failed; source unchanged")
			else
				ui.set(status, "Text", if submitted then message else "Prompt failed; source preserved")
			end
		end)
	end
	local connection = ui.connect(send, "Activated", function()
		if busy then
			return
		end
		local ok, failure = pcall(submit, ui.text(field, "Text"), nil, nil)
		if not ok then
			ui.set(status, "Text", tostring(failure))
		end
	end)
	local owner = Compose.createRootOwner(function()
		Compose.watch(function(use: Compose.Use)
			local value, selected = use(session.document), use(session.selected)
			local node = Design.document.find(value.root, selected)
			ui.set(
				caption,
				"Text",
				if node then `Selected: {node.name} · {node.kind}` else "Select a node on the canvas"
			)
		end)
	end, ui.runtime.reactor)
	local release = Compose.owner.own(ui.owner, owner.dispose)
	return {
		submit = submit,
		choose = function(index: number)
			assert(draft, "No draft comparison is open").choose(index)
		end,
		discard = clear,
		read = function(): { busy: boolean, drafts: boolean, status: string }
			return { busy = busy, drafts = draft ~= nil, status = ui.text(status, "Text") }
		end,
		dispose = function()
			disposed = true
			clear()
			connection:Disconnect()
			countConnection:Disconnect()
			if scopeConnection then
				scopeConnection:Disconnect()
			end
			release()
			ui.destroy(panel)
		end,
	}
end

return { snapshot = snapshot, create = create }

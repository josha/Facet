--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type CommandScope = typeof(require("@repo/tools/typecheck/aliases").CommandScope)
type Command = typeof(require("@repo/tools/typecheck/aliases").Command)
type Live = {
	mount: ((Controls, Host, Compose) -> Instance, { frames: number }?) -> GuiObject,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
}
type State = {
	first: GuiObject,
	second: GuiObject,
	chat: TextBox,
	scope: CommandScope,
	counts: () -> (number, number, number),
}
local GuiService = game:GetService("GuiService")
local function setup(t: Live): State
	local state: State
	t.mount(function(UI: Controls, Host: Host, C: Compose): Instance
		local letters, placed, returned = { "A", "A" }, 0, 0
		local notice = C.cell("Select a cell. A or X places one A. Backspace or Y recalls it.")
		local first = UI.Button "FirstCell" {
			label = "Cell 1",
			Position = UDim2.fromOffset(20, 20),
			Size = UDim2.fromOffset(120, 60),
		}
		local second = UI.Button "SecondCell" {
			label = "Cell 2",
			Position = UDim2.fromOffset(160, 20),
			Size = UDim2.fromOffset(120, 60),
		}
		first.NextSelectionRight, second.NextSelectionLeft = second, first
		local chat = UI.TextInput "Chat" {
			value = C.cell(""),
			placeholder = "Type A here. It must stay in chat.",
			Position = UDim2.fromOffset(20, 100),
			Size = UDim2.fromOffset(300, 44),
		}
		local label = UI.Text { text = notice, Position = UDim2.fromOffset(20, 164), Size = UDim2.fromOffset(360, 60) }
		local root = Host.Frame {
			Size = UDim2.fromScale(1, 1),
			first :: unknown,
			second :: unknown,
			chat :: unknown,
			label :: unknown,
		}
		local commands: { Command } = {
			{
				id = "Letter",
				keys = { "A", "ButtonX" },
				onInvoke = function(key: number)
					if #letters > 0 then
						table.remove(letters, 1)
						placed += 1
						notice:set("Placed one A at cell " .. tostring(key) .. ". Rack count: " .. tostring(#letters))
					end
				end,
			},
			{
				id = "Recall",
				keys = { "Backspace", "ButtonY" },
				onInvoke = function(key: number)
					if returned < placed then
						table.insert(letters, "A")
						returned += 1
						notice:set("Recalled one A from cell " .. tostring(key))
					end
				end,
			},
		}
		local targets: { { key: number, node: GuiObject } } = { { key = 1, node = first }, { key = 2, node = second } }
		local scope = UI.commandScope(root, { targets = targets, commands = commands })
		state = {
			first = first,
			second = second,
			chat = if chat:IsA("TextBox")
				then chat
				else assert(chat:FindFirstChildWhichIsA("TextBox", true)) :: TextBox,
			scope = scope,
			counts = function(): (number, number, number)
				return placed, returned, #letters
			end,
		}
		return root
	end, { frames = 12 })
	state.scope.focus(1)
	t.note("input steps", "Select Cell 1, press A/X once, edit chat, select Cell 2, press Backspace/Y once.")
	return state
end
local function afterPlace(t: Live, state: State)
	local placed, returned, count = state.counts()
	t.check("one duplicate A is placed", placed == 1 and returned == 0 and count == 1)
	t.check("native focus remains visible", GuiService.SelectedObject == state.first)
end
local function afterChat(t: Live, state: State)
	local placed, returned, count = state.counts()
	t.check("text entry does not place or recall", placed == 1 and returned == 0 and count == 1)
	t.check("chat receives the typed letter", string.find(string.upper(state.chat.Text), "A", 1, true) ~= nil)
	t.check("commands are disabled during text entry", not state.scope.actions.Letter.Enabled)
	state.chat:ReleaseFocus()
	state.scope.focus(2)
end
local function afterRecall(t: Live, state: State)
	local placed, returned, count = state.counts()
	t.check("one item is returned", placed == 1 and returned == 1 and count == 2)
	t.check(
		"native focus identifies Cell 2",
		GuiService.SelectedObject == state.second and state.scope.current:peek() == 2
	)
end
type Case = { id: string, contracts: { string }, setup: (Live) -> State, steps: { [string]: (Live, State) -> () } }
local cases: { Case } = {
	{
		id = "board-typing-pointer-and-text-entry",
		contracts = { "UI.commandScope", "UI.TextInput" },
		setup = setup,
		steps = { afterPlace = afterPlace, afterChat = afterChat, afterRecall = afterRecall },
	},
	{
		id = "board-command-gamepad",
		contracts = { "UI.commandScope" },
		setup = setup,
		steps = { afterPlace = afterPlace, afterRecall = afterRecall },
	},
}
return cases

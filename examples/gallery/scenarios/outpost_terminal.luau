--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Value<T> =
	ReadOnlyValue<T>
	& { set: (Value<T>, T) -> (), update: (Value<T>, (T) -> T) -> (), dispose: (Value<T>) -> () }
type Use = <T>(ReadOnlyValue<T>) -> T
type Terminal = typeof(require("@repo/examples/gallery/examples/outpost_terminal"))
type Reply = {
	kind: string?,
	token: string?,
	allocation: { [string]: number }?,
	revision: number?,
	ok: boolean?,
	requestId: number?,
	reason: string?,
	code: string?,
	message: string?,
}
type ExampleContext = typeof(require("@repo/examples/types").Context)
type Payload = {
	kind: string?,
	action: string?,
	requestId: number?,
	expectedRevision: number?,
	allocation: { [string]: number }?,
	token: string?,
}
local loadTerminal: (ModuleScript | string) -> Terminal = require
return {
	title = "Outpost power terminal (world surface)",
	build = function(ctx: ExampleContext)
		local Compose: ComposeModule, Host, UI = ctx.Compose, ctx.Host, ctx.UI
		local UDim, UDim2, Vector2, Enum = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
		local terminal =
			loadTerminal(if ctx.find then ctx.find("example", "outpost_terminal") else "../examples/outpost_terminal")
		local remote, player = ctx.outpostRemote, ctx.player
		if not remote and game then
			local found = game:GetService("ReplicatedStorage"):FindFirstChild("Facet_Outpost")
			if found and found:IsA("RemoteEvent") then
				remote = found
			end
			player = game:GetService("Players").LocalPlayer
		end
		local world = ctx.worldTarget
		local noConsole: BasePart? = nil
		local console: Value<BasePart?> = Compose.cell(noConsole)
		local token: string? = nil
		local replies: { Reply } = {}
		local connectionState =
			Compose.cell(if remote then "Opening the outpost…" else "No outpost server connected.")
		local lastExit = Compose.cell("—")
		local previousSelection: GuiObject? = nil
		local function command(kind: string, payload: Payload?)
			if not remote then
				return false
			end
			local message: Payload = if payload then table.clone(payload) else {}
			message.kind = kind
			remote:FireServer(message)
			return true
		end
		local built = terminal.build(ctx, {
			send = if remote
				then function(envelope: {
					requestId: number,
					expectedRevision: number,
					payload: { kind: string, allocation: { [string]: number } },
				})
					command("apply", {
						requestId = envelope.requestId,
						expectedRevision = envelope.expectedRevision,
						allocation = envelope.payload.allocation,
						token = token,
					})
				end
				else nil,
			onExit = function()
				token = nil
				command("release")
				if ctx.guiService then
					ctx.guiService.SelectedObject = if previousSelection and previousSelection.Parent
						then previousSelection
						else nil
				end
			end,
		})
		local function release(reason: string)
			lastExit:set(reason)
			built.steps.exit(reason)
		end
		local function findConsole()
			local model = world and world:FindFirstChild("Outpost")
			local found = model and model:FindFirstChild("Console")
			local part = if found and found:IsA("BasePart") then found else nil
			if part ~= console:peek() then
				if console:peek() and not part then
					release("adornee-lost")
				end
				console:set(part)
			end
		end
		if remote then
			ctx.runtime.connect(remote, "OnClientEvent", function(reply: Reply)
				table.insert(replies, reply)
				if #replies > 40 then
					table.remove(replies, 1)
				end
				findConsole()
				if reply.kind == "session" then
					token = reply.token
					if ctx.guiService then
						previousSelection = ctx.guiService.SelectedObject
					end
					built.steps.engage(assert(reply.allocation), assert(reply.revision))
					connectionState:set("Console engaged. Apply sends your draft to the server.")
				elseif reply.kind == "state" then
					built.steps.ingest(assert(reply.revision), assert(reply.allocation))
					connectionState:set("Walk to the console and use its prompt.")
				elseif reply.kind == "verdict" then
					if reply.ok then
						built.steps.confirm(assert(reply.requestId), reply)
					else
						built.steps.reject(assert(reply.requestId), reply)
					end
				elseif reply.kind == "closed" then
					release(reply.reason or "closed")
				end
			end)
			command("open")
		end
		local function checkEngagement()
			findConsole()
			if built.model.phase:peek() ~= "engaged" then
				return
			end
			local part = console:peek()
			local character = player and player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not part then
				release("adornee-lost")
			elseif not root then
				release("character-removed")
			elseif root:IsA("BasePart") then
				if (root.Position - part.Position).Magnitude > terminal.rules.RANGE then
					release("out-of-range")
				elseif RaycastParams and world and world:IsA("WorldRoot") then
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { assert(character) }
					local hit = world:Raycast(root.Position, part.Position - root.Position, params)
					if hit and hit.Instance ~= part then
						release("line-of-sight")
					end
				end
			end
		end
		if ctx.runService then
			ctx.runtime.connect(ctx.runService, "Heartbeat", checkEngagement)
		end
		findConsole()
		local sceneVisible = ctx.sceneVisible
		if sceneVisible then
			sceneVisible:set(true)
			Compose.cleanup(function()
				sceneVisible:set(false)
			end)
		end
		local steps = {
			open = function()
				return command("open")
			end,
			loadCharacter = function()
				return command("character", { action = "load" })
			end,
			exitCharacter = function()
				return command("character", { action = "remove" })
			end,
			exitAdornee = function()
				return command("console", { action = "remove" })
			end,
			restoreConsole = function()
				return command("console", { action = "restore" })
			end,
			exitCancel = function()
				release("cancel")
			end,
			exitControl = function()
				built.steps.exit("exit-control")
			end,
			setValue = built.steps.setValue,
			apply = built.steps.apply,
			resetOutpost = built.steps.reset,
			terminal = built.report,
			replies = function()
				return table.clone(replies)
			end,
			solve = function()
				built.steps.setValue("door", 2)
				built.steps.setValue("beacon", 1)
				built.steps.setValue("workshop", 2)
				return built.steps.apply()
			end,
		}
		local function raw(allocation: { [string]: number }, override: string?)
			return command("apply", { requestId = -1, allocation = allocation, token = override or token })
		end
		steps.refuseRange = function()
			return raw({ door = 9, beacon = 0, workshop = 0 })
		end
		steps.refuseBudget = function()
			return raw({ door = 3, beacon = 2, workshop = 4 })
		end
		steps.refuseStale = function()
			return raw({ door = 2, beacon = 1, workshop = 2 }, "stale-token")
		end
		steps.refuseFast = function()
			raw({ door = 2, beacon = 1, workshop = 2 })
			return raw({ door = 2, beacon = 1, workshop = 2 })
		end
		Compose.cleanup(function()
			command("close")
		end)
		local function button(name: string, label: string, action: () -> ...unknown): TextButton
			return UI.Button({ Name = name, label = label, onActivate = action, Size = UDim2.new(1, 0, 0, 40) })
		end
		local loadTerminal: (ModuleScript | string) -> Terminal = require
		return {
			screen = function()
				local sheet = ctx.Facet.themes.createStyleSheet(
					ctx.runtime,
					ctx.theme,
					{ types = ctx.types, theme = ctx.themeMode }
				)
				local gui = Host.SurfaceGui("OutpostSurface")({
					Parent = ctx.inputTarget,
					Adornee = function(use: Use): BasePart?
						return use(console)
					end,
					Face = Enum.NormalId.Back,
					CanvasSize = Vector2.new(terminal.CANVAS.w, terminal.CANVAS.h),
					SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
					AlwaysOnTop = false,
					LightInfluence = 0,
					MaxDistance = 64,
					Active = function(use: Use)
						return use(built.model.phase) == "engaged"
					end,
					Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
					built.screen(),
				})
				Host.InputContext("OutpostInput")({
					Parent = ctx.inputTarget,
					Priority = 3000,
					Sink = true,
					Enabled = function(use: Use)
						return use(built.model.phase) == "engaged"
					end,
					Host.InputAction("LeaveConsole")({
						Type = Enum.InputActionType.Bool,
						Pressed = function()
							release("cancel")
						end,
						Host.InputBinding({ KeyCode = Enum.KeyCode.Escape }),
						Host.InputBinding({ KeyCode = Enum.KeyCode.ButtonB }),
					}),
				})
				local previousPhase = built.model.phase:peek()
				Compose.watch(function(use: Use)
					local phase = use(built.model.phase)
					if phase == "engaged" and previousPhase ~= phase and ctx.guiService then
						for _, node in gui:GetDescendants() do
							if node:IsA("GuiObject") and node.Selectable and not node:IsA("ScrollingFrame") then
								ctx.guiService.SelectedObject = node
								break
							end
						end
					end
					previousPhase = phase
				end)
				return Host.Frame("OutpostCompanion")({
					Position = UDim2.fromOffset(12, 12),
					Size = UDim2.new(0, 280, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIPadding({
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
						PaddingTop = UDim.new(0, 12),
						PaddingBottom = UDim.new(0, 12),
					}),
					Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
					UI.Text({

						text = "Outpost 7 — World terminal",
						textRole = "heading",
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 54),
					}),
					UI.Text({

						text = connectionState,
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 72),
					}),
					button("Character", "Enter the outpost", steps.loadCharacter),
					button("Exit", "Leave console", steps.exitCancel),
					button("Restore", "Restore console", steps.restoreConsole),
					UI.Text({

						text = function(use: Use)
							return `Last exit: {use(lastExit)}`
						end,
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 36),
					}),
				})
			end,
			steps = steps,
			report = function()
				local loadTerminal: (ModuleScript | string) -> Terminal = require
				return {
					serverConnected = remote ~= nil,
					mounted = console:peek() ~= nil,
					face = "Back",
					lastExit = lastExit:peek(),
					terminal = built.report(),
				}
			end,
		}
	end,
}

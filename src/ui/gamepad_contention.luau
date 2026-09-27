--!strict
local freeze = require("./freeze")

export type GamepadContention = {
	describeContention: () -> string,
	legacyStackActive: () -> boolean,
	iasPlayerScriptsActive: (player: Player?, waitSeconds: number?) -> boolean,
	cameraKeysContended: (boundActionInfo: { [string]: any }?) -> boolean,
	traversalKeyContended: () -> boolean,
	freedJumpAction: (before: { [string]: any }, after: { [string]: any }) -> boolean,
	disableLegacyControls: (playerModuleParent: Instance?, player: Player?) -> (boolean, string),
}

local DESCRIPTION = table.concat({
	"Gamepad and keyboard contention with the legacy player scripts:",
	"1. The legacy control scripts bind gamepad ButtonA to jumpAction through ContextActionService at "
		.. "priority 2000 and consume it, so a selected control never receives ButtonA. In a UI-only place, "
		.. "disableLegacyControls() turns the controls off (or unbinds jumpAction). A game with an avatar must "
		.. "not do this.",
	"2. The fix for a game is Workspace.PlayerScriptsUseInputActionSystem, which is REQUIRED by Facet: it "
		.. "moves the player scripts, camera included, onto the Input Action System. It is NOT scriptable, but "
		.. "a Rojo project file CAN declare it.",
	"3. GuiService.CoreGuiNavigationEnabled turns itself back on when a script turns it off; do not rely on it.",
	"4. Tab opens the CoreGui players list while that list is enabled, so Facet's Tab traversal does not "
		.. "receive it. StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) frees it. "
		.. "traversalKeyContended() reports it.",
	"5. ContextActionService priority and InputContext.Priority are NOT one arbitration space: a sinking "
		.. "ContextActionService binding takes a key before any InputContext at any priority. The camera's "
		.. "RbxCameraKeypress holds Left and Right that way. A BindActionAtPriority claim is not Facet's route. "
		.. "THE FIX IS TRUTH 2, NOT A NUMBER.",
	"6. cameraKeysContended() reports whether any ContextActionService binding holds an arrow key. It reads "
		.. "a different binding than legacyStackActive(), and one can be true while the other is false.",
}, "\n")

local ARROWS = {
	["Enum.KeyCode.Left"] = true,
	["Enum.KeyCode.Right"] = true,
	["Enum.KeyCode.Up"] = true,
	["Enum.KeyCode.Down"] = true,
}
local DEFAULT_CONTEXTS = { "CharacterContext", "CameraContext", "VehicleContext" }

local function service(name: string): any
	local game = getfenv(0).game
	return assert(game, "no game here"):GetService(name)
end

local function boundActions(): { [string]: any }
	return service("ContextActionService"):GetAllBoundActionInfo()
end

local contention = {}

function contention.describeContention(): string
	return DESCRIPTION
end

function contention.legacyStackActive(): boolean
	local ok, active = pcall(function()
		return boundActions()["jumpAction"] ~= nil
	end)
	return ok and active == true
end

function contention.iasPlayerScriptsActive(player: Player?, waitSeconds: number?): boolean
	local ok, active = pcall(function(): boolean
		local subject: any = player or service("Players").LocalPlayer
		local folder = subject:FindFirstChild("InputContexts")
			or subject:WaitForChild("InputContexts", waitSeconds or 1)
		if folder == nil then
			return false
		end
		for _, name in DEFAULT_CONTEXTS do
			local context = folder:FindFirstChild(name)
			if context ~= nil and context.ClassName == "InputContext" then
				return true
			end
		end
		return false
	end)
	return ok and active == true
end

function contention.cameraKeysContended(boundActionInfo: { [string]: any }?): boolean
	local bound = boundActionInfo
	if bound == nil then
		local ok, live = pcall(boundActions)
		if not ok then
			return false
		end
		bound = live
	end
	for _, info in bound :: { [string]: any } do
		for _, code in info.inputTypes or {} do
			if ARROWS[tostring(code)] then
				return true
			end
		end
	end
	return false
end

function contention.traversalKeyContended(): boolean
	local ok, contended = pcall(function()
		return service("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
	end)
	return ok and contended == true
end

function contention.freedJumpAction(before: { [string]: any }, after: { [string]: any }): boolean
	return before["jumpAction"] ~= nil and after["jumpAction"] == nil
end

function contention.disableLegacyControls(playerModuleParent: Instance?, player: Player?): (boolean, string)
	if contention.iasPlayerScriptsActive(player) then
		return true, "inert: IAS owns PlayerScripts"
	end
	local disabled = pcall(function()
		local parent: any = playerModuleParent
			or assert(service("Players").LocalPlayer:WaitForChild("PlayerScripts", 5), "no PlayerScripts")
		local module: any = assert(parent:WaitForChild("PlayerModule", 5), "no PlayerModule")
		local loaded: any = (require :: any)(module)
		loaded:GetControls():Disable()
	end)
	if disabled then
		return true, "disabled"
	end
	local ok, freed = pcall(function(): boolean
		local before = boundActions()
		if before["jumpAction"] == nil then
			return false
		end
		service("ContextActionService"):UnbindAction("jumpAction")
		return contention.freedJumpAction(before, boundActions())
	end)
	if ok and freed then
		return true, "unbound"
	end
	return false, "unavailable"
end

return freeze(contention) :: GamepadContention

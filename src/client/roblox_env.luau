--!strict
-- Roblox environment adapter (design §8.1; CLIENT-ONLY): populates the
-- engine-free environment's fact keys from engine services and keeps them
-- live. This is the ONE place allowed to read UserInputService/GuiService
-- facts (UI-INPUT-001's platform-adapter rule). Returns an unbind function.

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local preferred_text = require("./preferred_text")

local roblox_env = {}

function roblox_env.bind(env: any): () -> ()
	local connections: { RBXScriptConnection } = {}
	local camera = workspace.CurrentCamera

	local function pushViewportFacts()
		local size = camera.ViewportSize
		env:set("viewportRect", { x = 0, y = 0, w = size.X, h = size.Y })
		local topInset, bottomInset = GuiService:GetGuiInset()
		-- Four-edge inset facts via the modern GuiService:GetInsetArea (native-
		-- substrate NS-A1; spike m8-safe-area.json). The returned Rect is in the
		-- SAME inset-subtracted space AbsolutePosition uses (engine truth: the
		-- desktop CoreUISafeInsets rect reads (0,0)->(w,h-58) while the window
		-- is h tall), so convert to window space by adding the legacy gui inset
		-- before deriving per-edge distances. pcall-guarded: an engine without
		-- GetInsetArea falls back to the legacy top/bottom-only computation
		-- (right stays 0 there — the documented pre-adoption limitation).
		local function insetsFromArea(area: Rect): { top: number, bottom: number, left: number, right: number }
			local ox, oy = topInset.X, topInset.Y
			return {
				top = math.max(0, area.Min.Y + oy),
				left = math.max(0, area.Min.X + ox),
				right = math.max(0, size.X - (area.Max.X + ox)),
				bottom = math.max(0, size.Y - (area.Max.Y + oy)),
			}
		end
		local okCore, coreArea = pcall(function()
			return GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
		end)
		if okCore and typeof(coreArea) == "Rect" then
			env:set("coreSafeInsets", insetsFromArea(coreArea))
		else
			env:set("coreSafeInsets", {
				top = topInset.Y,
				bottom = math.max(0, bottomInset.Y),
				left = topInset.X,
				right = 0,
			})
		end
		local okDevice, deviceArea = pcall(function()
			return GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
		end)
		if okDevice and typeof(deviceArea) == "Rect" then
			env:set("deviceSafeInsets", insetsFromArea(deviceArea))
		end
		-- ...and the TOPBAR-SAFE area, which is what makes `topbarInset` placeable:
		-- that rect is stated relative to THIS area, not to the window, so its
		-- window-space origin is `topbarSafeInsets.left/.top`. Same pcall belt and
		-- the same conversion as the two above; an engine without `GetInsetArea`
		-- keeps the zeroes, which are the desktop/no-notch answer.
		local okTopbar, topbarArea = pcall(function()
			return GuiService:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets)
		end)
		if okTopbar and typeof(topbarArea) == "Rect" then
			env:set("topbarSafeInsets", insetsFromArea(topbarArea))
		end
		local topbar = GuiService.TopbarInset
		env:set("topbarInset", { x = topbar.Min.X, y = topbar.Min.Y, w = topbar.Width, h = topbar.Height })
		-- console 10-foot fact (input-paradigms expansion): the physical
		-- display class. pcall-guarded — the property shipped 2025-10; a
		-- pre-release engine simply keeps the Medium default.
		local okDisplay, displaySize = pcall(function()
			return (GuiService :: any).ViewportDisplaySize
		end)
		if okDisplay and typeof(displaySize) == "EnumItem" then
			env:set("displaySize", displaySize.Name)
		end
	end

	--[[ ONE RESIZE IS ONE FACT-GROUP, NOT SIX. Everything above is learned from
		a SINGLE platform event, and the renderer re-solves for most of it. Written
		loose, one resize cost 5 solves — L-27's reproducible number, priced by the
		2026-08-13 device capture at 8.270 ms of arrange + 3.057 ms of measure
		each. Inside one transaction it costs 1 (tests/geometry_solve_coalescing).
		The pcall-guarded reads stay INSIDE: an engine that lacks `GetInsetArea`
		must still publish the facts it does have, atomically with the rest. ]]
	local function pushViewport()
		env:batch(pushViewportFacts)
	end

	-- sticky within the session: actual gamepad input is proof the class is
	-- live even when detection lags or fails (GamepadEnabled=false with a
	-- working pad is a documented engine failure class — Studio/macOS HID
	-- forwarding, controller-emulator slot shift; ADR-0015)
	local sawGamepadInput = false

	-- same fact-group rule as pushViewport: the class and the capability set are
	-- one truth about the device, and the interactionClasses memo reads BOTH.
	local function pushInput()
		env:batch(function()
			local preferred = UserInputService.PreferredInput
			env:set("preferredInput", preferred.Name)
			env:set("capabilities", {
				keyboard = UserInputService.KeyboardEnabled,
				mouse = UserInputService.MouseEnabled,
				touch = UserInputService.TouchEnabled,
				gamepad = UserInputService.GamepadEnabled or sawGamepadInput,
			})
		end)
	end

	-- PREFERRED TEXT SIZE (Step 8.5, decision LTN-1; probe artifact
	-- artifacts/large-text-accessibility/probe/preference-probe.json): the
	-- engine paints every text node at TextSize + a per-preference constant
	-- pixel offset (measured Medium=0 / Large=4 / Larger=10 / Largest=14,
	-- uniform across font, weight and size), and `GetTextBoundsAsync` answers
	-- WITHOUT it — so reserving at `size + offset` is exact, and this one env
	-- fact is the entire live seam. The controller applies the measured
	-- fallback synchronously (first mount never waits), confirms each value
	-- once through the yielding `GetTextSizeOffsetAsync` (cached; failure keeps
	-- the fallback; a stale answer never applies), and the renderer's existing
	-- `preferredTextOffset` watch turns a change into one re-solve of the
	-- mounted tree — never a remount.
	-- The multiplicative preferredTextSize fact stays 1 on the live path — it
	-- remains the injectable test/profile seam (non-overlapping authority).
	local CONFIRM_PROBE_SIZE = 16 -- any size works: the offset is size-independent (probe)
	-- TWO FACES, MAX WINS (platform review F3). The probe measured the offset
	-- as font-independent, and the env fact is one global number — so if the
	-- platform ever made it font-dependent, a single-face confirm would push
	-- the SMALLEST face's answer over the conservative fallback and clip every
	-- wider face. Probing two distinct built-in families and taking the max
	-- keeps the confirm exact today and fail-safe (over-reserving) under that
	-- drift; a per-font offset model would be a new stage, not a silent bet.
	local CONFIRM_FACES = {
		"rbxasset://fonts/families/BuilderSans.json",
		"rbxasset://fonts/families/GothamSSm.json",
	}
	local offsetController = preferred_text.new({
		getOffset = function(_preference: string): number?
			-- asks for the CURRENT live preference — the API has no per-enum
			-- parameter; the controller's epoch guard handles the race
			local best: number? = nil
			for _, file in CONFIRM_FACES do
				local ok, answer = pcall(function()
					return TextService:GetTextSizeOffsetAsync(CONFIRM_PROBE_SIZE, Font.new(file))
				end)
				if ok and type(answer) == "number" then
					best = if best == nil then answer else math.max(best, answer)
				end
			end
			return best
		end,
		apply = function(offset: number)
			env:set("preferredTextOffset", offset)
		end,
	})

	-- and again for the accessibility group: the text-size preference reaches the
	-- solver through preferredTextOffset, so it must land with its siblings.
	local function pushAccessibility()
		env:batch(function()
			env:set("reducedMotion", GuiService.ReducedMotionEnabled)
			env:set("preferredTransparency", GuiService.PreferredTransparency)
			local okText, textSize = pcall(function()
				return (GuiService :: any).PreferredTextSize
			end)
			if okText and typeof(textSize) == "EnumItem" then
				offsetController:setPreference(textSize.Name)
			end
		end)
	end

	pushViewport()
	pushInput()
	pushAccessibility()

	table.insert(connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(pushViewport))
	table.insert(connections, GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(pushViewport))
	do
		-- docking a handheld to a TV flips this mid-session; guarded like the read
		local okSignal, displaySignal = pcall(function()
			return GuiService:GetPropertyChangedSignal("ViewportDisplaySize")
		end)
		if okSignal and displaySignal ~= nil then
			table.insert(connections, displaySignal:Connect(pushViewport))
		end
	end
	table.insert(connections, UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(pushInput))
	-- capability facts move independently of the preference (ADR-0015): a
	-- gamepad connecting mid-session, or a keyboard/mouse joining a docked
	-- handheld, must reach env even when PreferredInput never flips
	-- (director repro 2026-07-21). GamepadConnected/Disconnected are the
	-- documented connect events; the *Enabled properties also carry change
	-- signals for the classes without connect events.
	table.insert(connections, UserInputService.GamepadConnected:Connect(pushInput))
	table.insert(connections, UserInputService.GamepadDisconnected:Connect(pushInput))
	for _, property in { "KeyboardEnabled", "MouseEnabled", "TouchEnabled", "GamepadEnabled" } do
		table.insert(connections, UserInputService:GetPropertyChangedSignal(property):Connect(pushInput))
	end
	table.insert(
		connections,
		UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
			if not sawGamepadInput and inputType.Name:sub(1, 7) == "Gamepad" then
				sawGamepadInput = true
				pushInput()
			end
		end)
	)
	table.insert(connections, GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(pushAccessibility))
	table.insert(connections, GuiService:GetPropertyChangedSignal("PreferredTransparency"):Connect(pushAccessibility))
	do
		-- the player can change text size mid-session from the in-experience
		-- menu (probe: the change signal fires reliably on every step, both
		-- directions). Guarded like the read: a pre-release engine without the
		-- property simply never fires.
		local okSignal, textSignal = pcall(function()
			return GuiService:GetPropertyChangedSignal("PreferredTextSize")
		end)
		if okSignal and textSignal ~= nil then
			table.insert(connections, textSignal:Connect(pushAccessibility))
		end
	end
	table.insert(
		connections,
		UserInputService.OnScreenKeyboardVisible
				and UserInputService:GetPropertyChangedSignal("OnScreenKeyboardPosition"):Connect(function()
					if UserInputService.OnScreenKeyboardVisible then
						local pos = UserInputService.OnScreenKeyboardPosition
						local size = UserInputService.OnScreenKeyboardSize
						env:set("keyboardOcclusionRect", { x = pos.X, y = pos.Y, w = size.X, h = size.Y })
					else
						env:set("keyboardOcclusionRect", nil)
					end
				end)
			or nil :: any
	)

	return function()
		offsetController:dispose()
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

return roblox_env

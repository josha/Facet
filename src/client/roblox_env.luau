--!strict
-- Roblox environment adapter (design §8.1; CLIENT-ONLY): populates the
-- engine-free environment's fact keys from engine services and keeps them
-- live. This is the ONE place allowed to read UserInputService/GuiService
-- facts (UI-INPUT-001's platform-adapter rule). Returns an unbind function.

local preferred_text = require("./preferred_text")
-- the pure inset arithmetic and its staleness test: engine-free, so
-- the conversion and the belt are provable without a rotating device
local safe_insets = require("../env/safe_insets")

local roblox_env = {}

--[[ THE SERVICES ARE RESOLVED AT BIND, NOT AT REQUIRE. They used to be three
	module-scope `game:GetService` locals, which made the module engine-only to
	REQUIRE — so the one file that decides what the framework believes about the
	device could not be driven by a fake, and three shipped defects in it
	— a keyboard connection that was never made, an orphaned camera connection
	and a stale-inset publish — had no headless instrument at all.
	Resolving inside `bind` is the `text_premeasure` idiom, already used here for
	exactly this reason, and the optional second argument is the seam the spec
	drives: pass nothing on a client and the engine's own services are used. ]]
local function engineServices(): any
	local GuiService = game:GetService("GuiService")
	return {
		userInput = game:GetService("UserInputService"),
		gui = GuiService,
		text = game:GetService("TextService"),
		world = workspace,
		--[[ THE THREE INSET AREAS, AS PLAIN DATA (re-measured 2026-08-17).

			`GetInsetArea` takes an `Enum.ScreenInsets` member and answers a `Rect`,
			and BOTH are engine types — so the branch that reads them was
			unreachable under Lune and the belt below had, measurably, no test that
			executed it in situ at all. Unpacking here is what moves the engine's
			half of this to the ONE place that is allowed to be engine-only and
			leaves the judgement on plain tables, where a fake can deliver the shape
			the finding is about: a stale area arriving beside a fresh viewport.

			pcall-guarded per area, exactly as before: an engine without
			`GetInsetArea` answers nil for all three and the legacy fallback below
			stands. ]]
		insetAreas = function(): { [string]: any }
			local function area(name: string): any
				local ok, rect = pcall(function()
					return GuiService:GetInsetArea((Enum :: any).ScreenInsets[name])
				end)
				if not ok or typeof(rect) ~= "Rect" then
					return nil
				end
				return { minX = rect.Min.X, minY = rect.Min.Y, maxX = rect.Max.X, maxY = rect.Max.Y }
			end
			return {
				core = area("CoreUISafeInsets"),
				device = area("DeviceSafeInsets"),
				topbar = area("TopbarSafeInsets"),
			}
		end,
	}
end

function roblox_env.bind(env: any, services: any?): () -> ()
	local svc = services or engineServices()
	local insetAreas: () -> { [string]: any } = svc.insetAreas or function()
		return {}
	end
	-- one belt per binding: the three areas lag independently, so each carries
	-- its own last-agreed pair (see safe_insets' header)
	local insetBelt = safe_insets.newBelt()
	local UserInputService = svc.userInput
	local GuiService = svc.gui
	local TextService = svc.text
	local world = svc.world
	local connections: { RBXScriptConnection } = {}
	local camera = world.CurrentCamera

	local function pushViewportFacts()
		if camera == nil then
			return
		end
		local size = camera.ViewportSize
		env:set("viewportRect", { x = 0, y = 0, w = size.X, h = size.Y })
		local topInset, bottomInset = GuiService:GetGuiInset()
		-- Four-edge inset facts via the modern GuiService:GetInsetArea (native-
		-- substrate; spike m8-safe-area.json). The returned Rect is in the
		-- SAME inset-subtracted space AbsolutePosition uses (engine truth: the
		-- desktop CoreUISafeInsets rect reads (0,0)->(w,h-58) while the window
		-- is h tall), so convert to window space by adding the legacy gui inset
		-- before deriving per-edge distances. pcall-guarded: an engine without
		-- GetInsetArea falls back to the legacy top/bottom-only computation
		-- (right stays 0 there — the documented pre-adoption limitation).
		local viewport = { w = size.X, h = size.Y }
		local guiInset = { x = topInset.X, y = topInset.Y }
		local areas = insetAreas()
		--[[ ── THE STALE-INSET BELT (redone after review) ──

			`Camera.ViewportSize` and `GetInsetArea` update on DIFFERENT frames, so
			one pass through here can convert an area measured against the OLD
			viewport using the NEW one. `env:batch` makes the write atomic; it
			cannot make the two engine reads agree.

			THE FIRST VERSION OF THIS BELT COULD NOT REFUSE ANYTHING, and the reason
			is worth keeping: it tested the DERIVED INSET against the viewport that
			derived it, and `fromArea` subtracts that same viewport, so the test
			cancelled down to "does the area have positive extent". Measured over
			this call shape, 48 cases, zero refusals — including a portrait area on
			a landscape window publishing a `bottom` that reserved 96% of the axis.

			The belt judges the AREA against the viewport instead, and it is
			stateful because the disagreement only exists across passes: a safe area
			ENCODES the window it was measured on, so an area byte-identical to the
			previous pass's, arriving beside a viewport that CHANGED, is still
			describing the previous viewport. A held pass publishes nothing and the
			last good value stands — publishing zeroes was rejected, because on a
			notched device that is a wrong answer that looks right. The next platform
			event re-pushes and settles it (`TopbarInset`, `ViewportSize`,
			`CurrentCamera` and `ViewportDisplaySize` all land here). ]]
		local coreArea = areas.core
		if coreArea ~= nil and insetBelt:judge("core", coreArea, guiInset, viewport) then
			env:set("coreSafeInsets", safe_insets.fromArea(coreArea, guiInset, viewport))
		elseif coreArea == nil then
			-- an engine without `GetInsetArea` keeps the legacy top/bottom-only
			-- computation (right stays 0 there — the documented pre-adoption
			-- limitation). A HELD area is not this case: it keeps the last good.
			env:set("coreSafeInsets", {
				top = topInset.Y,
				bottom = math.max(0, bottomInset.Y),
				left = topInset.X,
				right = 0,
			})
		end
		local deviceArea = areas.device
		if deviceArea ~= nil and insetBelt:judge("device", deviceArea, guiInset, viewport) then
			env:set("deviceSafeInsets", safe_insets.fromArea(deviceArea, guiInset, viewport))
		end
		-- ...and the TOPBAR-SAFE area, which is what makes `topbarInset` placeable:
		-- that rect is stated relative to THIS area, not to the window, so its
		-- window-space origin is `topbarSafeInsets.left/.top`. It pays the same
		-- belt as its two siblings — `environment.luau:354` carries a second,
		-- consume-side belt for this one key, and a fact that never becomes
		-- nonsense in the first place is strictly better than one caught later.
		local topbarArea = areas.topbar
		if topbarArea ~= nil and insetBelt:judge("topbar", topbarArea, guiInset, viewport) then
			env:set("topbarSafeInsets", safe_insets.fromArea(topbarArea, guiInset, viewport))
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
	-- working pad is a documented engine failure class — Studio HID
	-- forwarding, controller-emulator slot shift; ADR-0015)
	local sawGamepadInput = false

	--[[ A PAD THAT IS MERELY THERE IS NOT THE PLAYER'S PAD (director round 5,
		2026-08-21: "we don't need to see the lb/rb tips unless the user has a gamepad
		as the primary input"). MEASURED on the director's desktop: three pads
		connected, the player driving with a mouse, and
		`UserInputService.PreferredInput` reading **Gamepad** — so `primary` resolved
		to "gamepad", `effectiveInput` to "Gamepad", and every pad affordance in the
		framework turned on for a player who had not touched one.

		THE ENGINE'S PREFERENCE IS STICKY AND THE LAST INPUT IS NOT. `PreferredInput`
		is the engine's standing guess and it does not come back on its own once a pad
		has spoken — one drifting thumbstick, or an emulator's virtual pads, is enough
		to set it for the session. `GetLastInputType()` answers the other question,
		"what did this player just DO", and the two disagreeing is precisely the state
		the director measured.

		SO THIS IS THE MIRROR OF THE RULE ALREADY WRITTEN in `env/environment.luau`'s
		own fallback — *"a preference the player has not expressed yet cannot outvote
		what the device physically is"* — applied on the side the engine's guess is
		STICKY on instead of the side it is DEFAULT on. It is deliberately narrow, and
		every clause is load-bearing:

		  * only when the device HAS a mouse. A console or a handheld with no pointer
		    at all is a pad player whatever the last input was, and nothing here moves
		    for them;
		  * only while the last input actually seen is a POINTER or KEYBOARD one. The
		    first press of any pad button flips `GetLastInputType` to a Gamepad value
		    and the preference is honoured again in the same frame, through the
		    `LastInputTypeChanged` connection below — so a desktop player who picks up
		    a pad gets the pad layout on their first press, which is the case this must
		    not break;
		  * the CAPABILITY is untouched. `capabilities.gamepad` still reports the pad
		    as live, because it is: this changes which class is PRIMARY (emphasis, and
		    which idiom leads — ADR-0015 Decision 2), never which classes exist.

		The correction lives HERE rather than in the memo because it is about an
		ENGINE fact's known behaviour, which is this module's whole job — the same
		place `capabilities.gamepad` already corrects `GamepadEnabled` with
		`sawGamepadInput`.

		=== AND IT READS A DELIBERATE ACT, NOT `GetLastInputType()` (fix round 1) ===

		The first cut of this correction read `UserInputService:GetLastInputType()`.
		THIS REPOSITORY HAS ALREADY REJECTED THAT FUNCTION, in a ledger entry it
		enforces: `tools/check_input_authority.py` INPUT-100/101 records that Rascal
		Rally's `InputIdentity.luau` refuses it because *"deadzone drift flaps it
		several times a second"* — a thumb RESTING on a stick emits `Gamepad1`
		continuously — and requires *"a DELIBERATE act (past a 0.25 deadzone) before
		identity changes"*. On the exact hardware the director reported (a mouse in
		hand, three pads connected, one of them drifting) the first cut therefore
		traded a preference that was stickily WRONG for one that FLAPS, and every
		consumer of `primary` — density, scroll indicators, every pad affordance —
		would have flapped with it.

		SO THE HOUSE RECORD IS FOLLOWED RATHER THAN RE-DERIVED, clause for clause:

		  · the RAW stream, not the engine's summary. `InputBegan` is a press by
		    definition, and `InputChanged` carries the analogue noise, so the two are
		    read separately and only the first is trusted outright;
		  · a THUMBSTICK claims the pad only past `DELIBERATE_DEADZONE`. Drift never
		    qualifies, which is the entire finding INPUT-100 is about;
		  · MOUSE MOVEMENT IS NOISE TOO — `InputIdentity`'s own list says so, and a
		    pad player whose sleeve brushes a mouse must not lose the pad. A click or
		    a wheel is the deliberate pointer act;
		  · and nothing at all is claimed until something deliberate happens: the
		    class starts `nil`, and a `nil` class leaves the engine's preference
		    exactly as reported.

		The constant is the house number. If it ever needs to differ from the game's,
		that is a decision with two owners, not a second literal. ]]
	local DELIBERATE_DEADZONE = 0.25
	--[[ WHAT A DELIBERATE PRESS MEANS, by `UserInputType` name. Gamepad buttons are
		not in the table because they arrive on a different branch (any gamepad
		`InputBegan` is a button — sticks come through `InputChanged`), and
		`MouseMovement` is not in it because it is not an act. ]]
	local DELIBERATE_CLASS: { [string]: string } = {
		MouseButton1 = "pointer",
		MouseButton2 = "pointer",
		MouseButton3 = "pointer",
		MouseWheel = "pointer",
		Keyboard = "keyboard",
		Touch = "touch",
	}
	--[[ The last class the player DELIBERATELY used, or nil while they have used
		nothing. Read by `pushInput` below and written only by the two raw-stream
		connections further down. ]]
	local deliberateClass: string? = nil

	-- same fact-group rule as pushViewport: the class and the capability set are
	-- one truth about the device, and the interactionClasses memo reads BOTH.
	local function pushInput()
		env:batch(function()
			local preferred = UserInputService.PreferredInput
			local name = preferred.Name
			local mouse = UserInputService.MouseEnabled
			--[[ A pad the player has not deliberately used cannot outvote a pointer
				the device physically has. `deliberateClass` is nil until something
				deliberate happens, and a nil answer changes nothing — so a session that
				has seen no input at all, and any engine whose raw stream this module
				could not reach, keep the preference exactly as reported. ]]
			if name == "Gamepad" and mouse and deliberateClass ~= nil and deliberateClass ~= "gamepad" then
				name = "KeyboardAndMouse"
			end
			env:set("preferredInput", name)
			env:set("capabilities", {
				keyboard = UserInputService.KeyboardEnabled,
				mouse = mouse,
				touch = UserInputService.TouchEnabled,
				gamepad = UserInputService.GamepadEnabled or sawGamepadInput,
			})
		end)
	end

	-- PREFERRED TEXT SIZE (Step 8.5, the large-text decision; probe artifact
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

	--[[ THE CAMERA IS RE-RESOLVED, NOT CAPTURED ONCE (2026-08-17).

		`workspace.CurrentCamera` was read at bind and never again, so a game that
		replaces its camera — a cutscene rig, a spectator camera, a respawn — kept
		this connection on the OLD camera's `ViewportSize` and `viewportRect` stopped
		updating for the rest of the session. Every resize, rotation and window drag
		after that point silently did nothing.

		`CurrentCamera` carries a change signal, so the connection follows it: the
		old one is disconnected, the new one is subscribed, and the facts are pushed
		once against the camera that is actually rendering. ]]
	local viewportConnection: any = nil
	local function bindCamera()
		if viewportConnection ~= nil then
			viewportConnection:Disconnect()
			viewportConnection = nil
		end
		camera = world.CurrentCamera
		if camera ~= nil then
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(pushViewport)
		end
	end
	bindCamera()
	table.insert(
		connections,
		world:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bindCamera()
			pushViewport()
		end)
	)
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
	--[[ THE CAPABILITY LATCH, UNCHANGED. `LastInputTypeChanged` is still the cheapest
		place to learn that a pad exists at all when detection lagged or failed, and it
		still fires exactly once for that — it is a CAPABILITY question and noise
		answers it just as well as a press does. Nothing about PRIMACY is decided here
		any more; that reads the deliberate stream below. ]]
	table.insert(
		connections,
		UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
			if not sawGamepadInput and inputType.Name:sub(1, 7) == "Gamepad" then
				sawGamepadInput = true
				pushInput()
			end
		end)
	)
	--[[ ── THE DELIBERATE STREAM (INPUT-100/101: the engine's last-input summary is unusable for primacy without a deadzone, so primacy reads the raw stream and only DELIBERATE events count; see `pushInput`) ──────────────────
		A press is deliberate by definition, so `InputBegan` is taken at face value —
		including for a gamepad, where `InputBegan` can only be a BUTTON (sticks and
		triggers arrive on `InputChanged`). Mouse MOVEMENT never reaches this branch
		because the engine reports it as a change rather than a beginning, which is
		the same split `InputIdentity.luau` relies on.

		A re-push only on a CHANGE of class: a player clicking a mouse fires this on
		every click and the fact has not moved.

		BOTH CONNECTIONS ARE OPTIONAL. An engine without the member — a fake in a
		test, a future target — keeps `deliberateClass` nil forever, and a nil class
		leaves the preference exactly as the engine reported it. That is the same
		"cleanly skipped, with no nil hole" contract every guarded read in this module
		carries. ]]
	local function claimDeliberate(class: string?)
		if class == nil or class == deliberateClass then
			return
		end
		deliberateClass = class
		pushInput()
	end
	do
		local okBegan, began = pcall(function()
			return (UserInputService :: any).InputBegan
		end)
		if okBegan and began ~= nil then
			table.insert(
				connections,
				began:Connect(function(io: any)
					local name = if type(io) == "table" or typeof(io) == "Instance"
						then tostring((io :: any).UserInputType)
						else ""
					-- `tostring` on an EnumItem is "Enum.UserInputType.Foo"; the fake
					-- engine hands a plain table whose field is already the name
					local short = string.match(name, "([^%.]+)$") or name
					if string.sub(short, 1, 7) == "Gamepad" then
						claimDeliberate("gamepad")
					else
						claimDeliberate(DELIBERATE_CLASS[short])
					end
				end)
			)
		end
		local okChanged, changed = pcall(function()
			return (UserInputService :: any).InputChanged
		end)
		if okChanged and changed ~= nil then
			table.insert(
				connections,
				changed:Connect(function(io: any)
					local name = string.match(tostring((io :: any).UserInputType), "([^%.]+)$") or ""
					--[[ THE DEADZONE, AND IT IS THE WHOLE POINT (INPUT-100: stick noise below 0.25 must never claim primacy — without this the primary input flaps on every idle wobble). A stick a
						thumb is resting on emits continuously; only a deflection past the
						house number is an act. Triggers and every other analogue axis are
						deliberately NOT read here — a trigger at rest drifts too, and a
						pulled trigger arrives as a button on `InputBegan`. ]]
					if string.sub(name, 1, 7) == "Gamepad" then
						local key = string.match(tostring((io :: any).KeyCode), "([^%.]+)$") or ""
						if key == "Thumbstick1" or key == "Thumbstick2" then
							local pos = (io :: any).Position
							local mag = if type(pos) == "table"
								then math.sqrt((pos.X or 0) ^ 2 + (pos.Y or 0) ^ 2)
								elseif pos ~= nil then (pos :: any).Magnitude
								else 0
							if type(mag) == "number" and mag > DELIBERATE_DEADZONE then
								claimDeliberate("gamepad")
							end
						end
					elseif name == "MouseWheel" then
						-- a wheel IS an act; `MouseMovement`, which arrives on this same
						-- connection, deliberately is not
						claimDeliberate("pointer")
					end
				end)
			)
		end
	end
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
	--[[ THE OCCLUSION CONNECTION WAS NEVER MADE (2026-08-17).

		This read `UserInputService.OnScreenKeyboardVisible and <connect> or nil`.
		The guard was meant to ask "does this engine HAVE the member" and instead
		asked "is the on-screen keyboard up RIGHT NOW" — which at bind time, before
		any text field exists, is always false. So the `and` short-circuited, the
		`or nil` was inserted into `connections`, and `keyboardOcclusionRect` stayed
		nil for the whole session: on a phone the keyboard never occluded anything
		and nothing ever scrolled out from under it. The failure was silent in both
		directions — `table.insert(t, nil)` appends nothing to complain about, and
		every headless suite has no keyboard.

		The guard now asks the question it meant to ask, once, on the MEMBER; the
		callback keeps the live-value read where it belongs. An engine without the
		property is cleanly skipped, and nothing nil-shaped reaches `connections`. ]]
	do
		local okMember, hasMember = pcall(function()
			return (UserInputService :: any).OnScreenKeyboardVisible ~= nil
		end)
		local okSignal, keyboardSignal = pcall(function()
			return UserInputService:GetPropertyChangedSignal("OnScreenKeyboardPosition")
		end)
		if okMember and hasMember == true and okSignal and keyboardSignal ~= nil then
			table.insert(
				connections,
				keyboardSignal:Connect(function()
					if UserInputService.OnScreenKeyboardVisible then
						local pos = UserInputService.OnScreenKeyboardPosition
						local size = UserInputService.OnScreenKeyboardSize
						env:set("keyboardOcclusionRect", { x = pos.X, y = pos.Y, w = size.X, h = size.Y })
					else
						env:set("keyboardOcclusionRect", nil)
					end
				end)
			)
		end
	end

	return function()
		offsetController:dispose()
		if viewportConnection ~= nil then
			viewportConnection:Disconnect()
			viewportConnection = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

return roblox_env

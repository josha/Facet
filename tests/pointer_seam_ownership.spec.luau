--!strict
--[[
	WHAT THE POINTER SEAM OWNS, AND WHAT IT ONLY BORROWS — release-candidate
	platform review PLAT-4, PLAT-5 and PLAT-6.

	All three findings are the same mistake in three places: adapter-wide state
	treated as though it belonged to whatever happened to touch it last.

	  · PLAT-4 — `destroyRoot` disconnected the adapter-wide `GuiService.MenuOpened`
	    connection. An adapter hosts several roots at once (the presenter mounts and
	    retires a transient popup-catcher root reactively), so the first retirement
	    killed drag-abort-on-menu for every remaining root, session-wide. Escape
	    cannot be intercepted, so that abort is the only thing between an open
	    CoreGui menu and a stuck drag behind it.
	  · PLAT-5 — every cursor write was `MouseIcon = <art> or ""`, and `CURSOR_ART`
	    is empty, so the only thing this module could do to a host game's custom
	    cursor was erase it.
	  · PLAT-6 — the pointer capture's `InputChanged`/`InputEnded` are GLOBAL and
	    were not filtered to the finger that opened the capture, so a second finger
	    drove and ended the first one's drag.

	THE HARNESS, AND ITS ONE HONEST LIMIT. `screen_pointer` now resolves its
	services at construction, so a fake UserInputService/GuiService drives the
	cursor and teardown paths directly. The CAPTURE path cannot be driven the same
	way: its bodies compare against `Enum.UserInputType.*`, and `Enum` does not
	exist under Lune. Installing a fake `Enum` global was rejected — `getfenv(0)`
	is shared by every spec in the process and a dozen modules feature-detect
	engine globals through exactly that lookup (`tests/lib/gui_value_shim.luau`
	explains why the shim there is two constructors and not an emulator). So
	PLAT-6 is pinned as STRUCTURE, on the live source, and says so.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local screen_pointer = require("../src/client/screen_pointer")
local adapter_source = require("./lib/adapter_source")

local function newSignal(): any
	local records: { any } = {}
	local signal = {}
	function signal.Connect(_self, fn: (...any) -> ()): any
		local record = { fn = fn, connected = true }
		table.insert(records, record)
		return {
			Connected = true,
			Disconnect = function()
				record.connected = false
			end,
		}
	end
	function signal.fire(_self, ...)
		for _, record in records do
			if record.connected then
				record.fn(...)
			end
		end
	end
	function signal.liveCount(_self): number
		local n = 0
		for _, record in records do
			if record.connected then
				n += 1
			end
		end
		return n
	end
	return signal
end

local function newFakeInstance(): any
	local instance: any = {
		InputBegan = newSignal(),
		InputChanged = newSignal(),
		MouseEnter = newSignal(),
		MouseLeave = newSignal(),
	}
	function instance.IsA(_self, className: string): boolean
		return className == "GuiObject"
	end
	return instance
end

local function newSeam(cursorArt: { [string]: string }?): any
	local menuOpened = newSignal()
	local userInput: any = {
		MouseIcon = "",
		InputChanged = newSignal(),
		InputEnded = newSignal(),
	}
	local gui: any = {
		MenuOpened = menuOpened,
		GetGuiInset = function()
			return { X = 0, Y = 0 }
		end,
	}
	local seam = screen_pointer.new({
		handlesByPath = {},
		cursorArt = cursorArt,
		services = { userInput = userInput, gui = gui },
	})
	return { seam = seam, userInput = userInput, gui = gui, menuOpened = menuOpened }
end

describe("the pointer seam borrows the host's cursor (PLAT-5)", function()
	it("writes nothing at all while it has no cursor art of its own", function()
		local fixture = newSeam()
		fixture.userInput.MouseIcon = "rbxassetid://the-host-crosshair"

		local handle = { class = "Grip", instance = newFakeInstance(), cursorHint = "colResize" }
		fixture.seam.setPointerHandlers(handle, {})
		handle.instance.MouseEnter:fire()
		expect(fixture.userInput.MouseIcon).toBe("rbxassetid://the-host-crosshair")
		handle.instance.MouseLeave:fire()
		expect(fixture.userInput.MouseIcon).toBe("rbxassetid://the-host-crosshair")

		-- ...and the whole-adapter teardown leaves it alone too
		fixture.seam.disposeGlobals()
		expect(fixture.userInput.MouseIcon).toBe("rbxassetid://the-host-crosshair")
	end)

	it("when it DOES have art, it captures the prior value and restores it", function()
		local fixture = newSeam({ colResize = "rbxassetid://facet-col-resize" })
		fixture.userInput.MouseIcon = "rbxassetid://the-host-crosshair"

		local handle = { class = "Grip", instance = newFakeInstance(), cursorHint = "colResize" }
		fixture.seam.setPointerHandlers(handle, {})
		handle.instance.MouseEnter:fire()
		expect(fixture.userInput.MouseIcon).toBe("rbxassetid://facet-col-resize")
		handle.instance.MouseLeave:fire()
		-- the host's cursor comes BACK — it is never replaced with the default arrow
		expect(fixture.userInput.MouseIcon).toBe("rbxassetid://the-host-crosshair")
	end)

	it("teardown restores the borrowed cursor even mid-hover", function()
		local fixture = newSeam({ colResize = "rbxassetid://facet-col-resize" })
		fixture.userInput.MouseIcon = "rbxassetid://the-host-crosshair"
		local handle = { class = "Grip", instance = newFakeInstance(), cursorHint = "colResize" }
		fixture.seam.setPointerHandlers(handle, {})
		handle.instance.MouseEnter:fire()
		fixture.seam.disposeGlobals()
		expect(fixture.userInput.MouseIcon).toBe("rbxassetid://the-host-crosshair")
	end)
end)

describe("the menu connection is the adapter's, the cursor hint is the root's (PLAT-4)", function()
	it("releaseCursorHint leaves the menu connection alive", function()
		local fixture = newSeam({ colResize = "rbxassetid://facet-col-resize" })
		expect(fixture.menuOpened:liveCount()).toBe(1)

		local handle = { class = "Grip", instance = newFakeInstance(), cursorHint = "colResize" }
		fixture.seam.setPointerHandlers(handle, {})
		handle.instance.MouseEnter:fire()
		expect(fixture.userInput.MouseIcon).toBe("rbxassetid://facet-col-resize")

		-- one root of several comes down
		fixture.seam.releaseCursorHint()
		expect(fixture.userInput.MouseIcon).toBe("")
		expect(fixture.menuOpened:liveCount()).toBe(1)

		-- ...and the LAST one takes the connection with it
		fixture.seam.disposeGlobals()
		expect(fixture.menuOpened:liveCount()).toBe(0)
	end)

	it("the adapter calls the two apart: only a last-root teardown disposes globals", function()
		--[[ `screen_target` cannot load headlessly (engine globals at module
			scope), so the CALL SITE is pinned as text. Both halves matter: the
			unconditional call is gone, and the surviving call is gated on there
			being no other root left. ]]
		local source = adapter_source.live()
		expect(string.find(source, "releaseCursorHint()", 1, true) ~= nil).toBe(true)
		local gated = string.match(
			source,
			"local remainingRoots = 0.-if remainingRoots == 0 then%s*\n%s*disposeGlobalPointerState%(%)"
		)
		expect(gated ~= nil).toBe(true)
	end)
end)

describe("a touch capture belongs to the finger that opened it (PLAT-6)", function()
	--[[ STRUCTURAL, and the header says why: the capture bodies compare against
		`Enum.UserInputType.*`, which does not exist under Lune, and a fake `Enum`
		global would leak into every other spec in the process. What is pinned here
		is that the identity filter exists, that it is TOUCH-scoped (a mouse drag
		legitimately mixes InputObjects — moves arrive as `MouseMovement`, the
		release as `MouseButton1`), and that BOTH global connections apply it. ]]
	-- read as ITS OWN file rather than through `adapter_source.live()`: the
	-- concatenated adapter carries several other `InputChanged:Connect(function(...)`
	-- sites (the disclosure long-press among them) and a pattern over the whole
	-- text can match one of those instead of the capture
	local source = fs.readFile("src/client/screen_pointer.luau")

	it("the capture records the originating touch object", function()
		expect(string.find(source, "local originatingTouch: InputObject?", 1, true) ~= nil).toBe(true)
	end)

	it("the filter is touch-scoped, so a mouse drag is unaffected", function()
		local predicate =
			string.match(source, "local function fromThisPointer%(other: InputObject%): boolean(.-)\n\tend")
		expect(predicate ~= nil).toBe(true)
		expect(string.find(predicate :: string, "originatingTouch == nil", 1, true) ~= nil).toBe(true)
		expect(string.find(predicate :: string, "other.UserInputType ~= Enum.UserInputType.Touch", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(predicate :: string, "other == originatingTouch", 1, true) ~= nil).toBe(true)
	end)

	it("BOTH global connections apply it, and they are the first thing each does", function()
		local moved = string.match(source, "InputChanged:Connect%(function%(moveObject: InputObject%)(.-)UserInputType")
		local ended = string.match(source, "InputEnded:Connect%(function%(endObject: InputObject%)(.-)UserInputType")
		expect(moved ~= nil).toBe(true)
		expect(ended ~= nil).toBe(true)
		expect(string.find(moved :: string, "not fromThisPointer(moveObject)", 1, true) ~= nil).toBe(true)
		expect(string.find(ended :: string, "not fromThisPointer(endObject)", 1, true) ~= nil).toBe(true)
	end)
end)

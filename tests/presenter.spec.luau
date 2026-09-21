--!strict
-- P1.3/P1.5 presenter tests (§12.1, §17 Phase 1 exit gate): modal context
-- priority/sinking/disposal, focus trap + restoration, Cancel routing, and
-- full-slice churn neutrality (mount+render+input+focus together).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")
local renderer = require("../src/render/renderer")

local function makeWorld()
	return worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
end
local function noop() end

local function settingsScreen(w: any)
	local UI = w.UI
	return function()
		return UI.Screen("Settings")({
			UI.Text("Title")({ text = "Settings", textSize = 24 }),
			UI.Button("Music")({ label = "Music", onActivate = noop }),
			UI.Button("Sfx")({ label = "Sfx", onActivate = noop }),
			UI.Button("Save")({ label = "Save", onActivate = noop }),
		})
	end
end

local function confirmModal(w: any)
	local UI = w.UI
	return function()
		return UI.Screen("Confirm")({
			UI.Text("Prompt")({ text = "Discard changes?", textSize = 18 }),
			UI.Button("Yes")({ label = "Yes", onActivate = noop }),
			UI.Button("No")({ label = "No", onActivate = noop }),
		})
	end
end

describe("presenter: screens and modals", function()
	for _, enabled in { false, true } do
		it(`anchored chrome forwards renderer comparisons (enabled={enabled})`, function()
			local w = makeWorld()
			local opts: any = {
				id = "Tip",
				chrome = true,
				anchor = { source = { rect = { x = 100, y = 100, w = 40, h = 40 } }, edge = "bottom" },
			}
			local flags = { "measureReuse", "commitScope", "structuralReuse", "translateHosts" }
			if not enabled then
				for _, flag in flags do
					opts[flag] = false
				end
			end
			-- Observe the real renderer boundary while still mounting and solving
			-- the public chrome route. Restore the hook even if mounting fails.
			local attach = renderer.attach
			local observed, calls = nil, 0
			renderer.attach = function(core, root, env, adapter, options)
				observed = options
				calls += 1
				return attach(core, root, env, adapter, options)
			end
			local ok, err = pcall(function()
				w.app.presentAnchored(function()
					return w.UI.Box("Probe")({
						width = { type = "fixed", px = 40 },
						height = { type = "fixed", px = 20 },
					})
				end, opts)
			end)
			renderer.attach = attach
			assert(ok, tostring(err))
			expect(calls).toBe(1)
			for _, flag in flags do
				expect(observed[flag]).toBe(enabled)
			end
			local path = "/Tip/Layer/Surface/Probe"
			local rect = w.adapter.node(path).rect
			expect(rect.w).toBe(40)
			expect(rect.h).toBe(20)
			expect(w.pres.depth()).toBe(0)
			w.app.dispose()
			expect(w.adapter.node(path)).toBe(nil)
		end)
	end

	for _, method in { "mount", "presentModal", "presentAnchored" } do
		it(`{method} accepts renderer comparison options on a mounted component`, function()
			local w = makeWorld()
			local opts: any = {
				structuralReuse = false,
				measureReuse = false,
				commitScope = false,
				translateHosts = false,
				initialFocus = "none",
			}
			local path = "/Probe"
			if method == "presentAnchored" then
				opts.id = "Tip"
				opts.anchor = { source = { rect = { x = 100, y = 100, w = 40, h = 40 } }, edge = "bottom" }
				path = "/Tip/Layer/Surface/Probe"
			end
			w.app[method](function()
				return w.UI.Box("Probe")({
					width = { type = "fixed", px = 40 },
					height = { type = "fixed", px = 20 },
				})
			end, opts)
			local rect = w.adapter.node(path).rect
			expect(rect.w).toBe(40)
			expect(rect.h).toBe(20)
			w.app.dispose()
			expect(w.adapter.node(path)).toBe(nil)
		end)
	end

	it("presents a screen with document-order focus and device navigation", function()
		local w = makeWorld()
		local system, pres = w.system, w.pres
		w.present(settingsScreen(w))
		expect(pres.focus.focused:peek()).toBe("/Settings/Music")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:peek()).toBe("/Settings/Sfx")
	end)

	it("a modal sinks navigation from the base screen and traps focus", function()
		local w = makeWorld()
		local system, pres = w.system, w.pres
		w.present(settingsScreen(w))
		w.presentModal(confirmModal(w))
		expect(pres.focus.focused:peek()).toBe("/Confirm/Yes")
		-- device navigation reaches ONLY the modal (sink)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:peek()).toBe("/Confirm/No")
		-- wraps inside the trap, never escapes to Settings
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:peek()).toBe("/Confirm/Yes")
	end)

	it("Cancel dismisses the modal, restores focus, and disposes its context", function()
		local w = makeWorld()
		local core, system, pres = w.core, w.system, w.pres
		w.present(settingsScreen(w))
		system.deviceKey("Down", true)
		system.deviceKey("Down", false) -- focus Sfx
		local modal = w.presentModal(confirmModal(w))
		expect(pres.depth()).toBe(2)
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		expect(pres.depth()).toBe(1)
		expect(pres.focus.focused:peek()).toBe("/Settings/Sfx") -- restored
		-- destroyed context: firing its old bindings is a silent no-op
		expect(modal.context.destroyed).toBe(true)
		-- navigation returns to the base screen
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:peek()).toBe("/Settings/Save")
	end)

	it("activate routes to the focused control of the top scope", function()
		local w = makeWorld()
		local system, pres = w.system, w.pres
		local activated: { string } = {}
		w.present(settingsScreen(w), {
			onActivate = function(path)
				table.insert(activated, path)
			end,
		})
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(activated[1]).toBe("/Settings/Music")
	end)

	it("open/close churn is registry-neutral across the whole slice", function()
		local w = makeWorld()
		local core, adapter, pres = w.core, w.adapter, w.pres
		w.present(settingsScreen(w))
		local baseline = core.owner.size()
		local liveBaseline = adapter.liveCount()
		for _ = 1, 20 do
			local modal = w.presentModal(confirmModal(w))
			pres.dismiss(modal)
		end
		local after = core.owner.size()
		expect(after).toBe(baseline)
		expect(adapter.liveCount()).toBe(liveBaseline)
	end)
end)

describe("presenter: re-entrant dismiss (phase-2 verifier F-2)", function()
	it("dismissing a modal from inside its own onActivate is safe", function()
		local w = makeWorld()
		local system, pres = w.system, w.pres
		w.present(settingsScreen(w))
		local modal
		modal = w.presentModal(confirmModal(w), {
			onActivate = function(_path)
				pres.dismiss(modal) -- close from within the action dispatch
			end,
		})
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(pres.depth()).toBe(1)
		expect(modal.context.destroyed).toBe(true)
		-- base screen navigation still works after the re-entrant dismiss
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:peek()).toBe("/Settings/Sfx")
	end)
end)

--[[ THE STRING-ENUM OPTS ARE VALIDATED AT PRESENT TIME
	(api-architecture-consistency F-15). `makeHandle` has refused an unknown
	`cancelPolicy` since it existed, with a comment stating the rule: "a typo that
	silently kept the default would read as 'the framework ignored my mandatory
	modal'". Two of the four string enums did not follow it — `responder` was
	compared by equality (`responder = "Passive"` silently presented an ENGAGED
	surface that sank nothing) and `scrim` was passed through raw (`scrim = "None"`
	silently DIMMED the screen). Both now fail at the call site like their sibling. ]]
describe("presenter: unknown string-enum opts fail at the call site (F-15)", function()
	it("an unknown responder names the opt and its legal set", function()
		local w = makeWorld()
		local pres = w.pres
		local ok, err = pcall(function()
			w.present(settingsScreen(w), { responder = "Passive" } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "responder", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "Passive", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "passive", 1, true) ~= nil).toBe(true)
		-- and nothing was presented behind the error
		expect(pres.depth()).toBe(0)
	end)

	it("an unknown scrim names the opt and its legal set", function()
		local w = makeWorld()
		local pres = w.pres
		local ok, err = pcall(function()
			w.presentModal(confirmModal(w), { scrim = "None" } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "scrim", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "None", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "none", 1, true) ~= nil).toBe(true)
		expect(pres.depth()).toBe(0)
	end)

	it("the legal values still present: responder passive, scrim scrim/none", function()
		local w = makeWorld()
		local pres = w.pres
		local hud = w.present(settingsScreen(w), { responder = "passive" })
		expect(hud.responder:peek()).toBe("passive")
		local modal = w.presentModal(confirmModal(w), { scrim = "none" })
		expect(modal.scrimMode).toBe("none")
		local plain = w.presentModal(confirmModal(w), { scrim = "scrim" })
		expect(plain.scrimMode).toBe("scrim")
		expect(pres.depth()).toBe(3)
	end)
end)

--[[ `presenter.raise` (registry item 23; W3-D) — re-band a LIVE
	surface without dismiss+re-present. `examples/gallery/client/
	showcase_chrome.luau`'s `raisePanel` is the real, migrated consumer
	(`tests/gallery_chrome.spec.luau` describe (15) exercises it end-to-end,
	through the real InputAction/demo-picker path); this block is the direct,
	presenter-level unit coverage the seam itself needs. ]]
describe("presenter: raise re-bands a live surface without dismiss+re-present", function()
	it("bumps a base screen into a fresh band slot, in place", function()
		local w = makeWorld()
		local adapter, pres = w.adapter, w.pres
		local handle = w.present(settingsScreen(w))
		local before = adapter.rootDisplayOrder("Settings")
		pres.raise(handle)
		local after = adapter.rootDisplayOrder("Settings")
		expect(`raised: {after} (was {before})`).toBe(`raised: {before + 100} (was {before})`)
		expect(handle.displayOrder).toBe(after)
	end)

	it("raises within the MODAL band, never the base band", function()
		local w = makeWorld()
		local pres = w.pres
		w.present(settingsScreen(w))
		local modal = w.presentModal(confirmModal(w))
		pres.raise(modal)
		-- a base-band mistake would land far below this floor (~10000+N*100
		-- against a 40000 floor), so this is the branch assertion, not just "it
		-- went up"
		expect(modal.displayOrder >= pres.SURFACE_LAYER.modal).toBe(true)
	end)

	it("re-homes an owned scrim's displayOrder along with the surface it belongs to", function()
		local w = makeWorld()
		local adapter, pres = w.adapter, w.pres
		w.present(settingsScreen(w))
		local modal = w.presentModal(confirmModal(w))
		local scrimBefore = adapter.rootDisplayOrder("__scrim__")
		pres.raise(modal)
		local scrimAfter = adapter.rootDisplayOrder("__scrim__")
		expect(`scrim followed: {scrimAfter} = modal - 50 ({modal.displayOrder - 50})`).toBe(
			`scrim followed: {modal.displayOrder - 50} = modal - 50 ({modal.displayOrder - 50})`
		)
		expect(scrimAfter > scrimBefore).toBe(true)
	end)

	it("REFUSES a handle already dismissed — silently, matching `dismiss`'s own shape", function()
		local w = makeWorld()
		local pres = w.pres
		local handle = w.present(settingsScreen(w))
		pres.dismiss(handle)
		local before = handle.displayOrder
		pres.raise(handle)
		expect(handle.displayOrder).toBe(before)
	end)

	it("REFUSES nil without erroring — a defensive caller must not be punished", function()
		local w = makeWorld()
		local pres = w.pres
		w.present(settingsScreen(w))
		pres.raise(nil :: any)
	end)

	it("never remounts: zero instance churn and focus never moves", function()
		local w = makeWorld()
		local core, adapter, system, pres = w.core, w.adapter, w.system, w.pres
		local handle = w.present(settingsScreen(w))
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:peek()).toBe("/Settings/Sfx")
		local baseline = core.owner.size()
		local liveBaseline = adapter.liveCount()
		pres.raise(handle)
		local after = core.owner.size()
		expect(after).toBe(baseline)
		expect(adapter.liveCount()).toBe(liveBaseline)
		-- the ring never moved, because nothing capable of moving it ran
		expect(pres.focus.focused:peek()).toBe("/Settings/Sfx")
	end)
end)

--[[ THE TRANSITION SPEC IS A SNAPSHOT OF THE PRESENT, NOT A RE-READ AT DISMISS
	(review D1). `dismiss` re-resolved `handle.transition` to decide whether the
	exit was `instant` — AFTER the surface had left the stack, its context was
	destroyed and its focus scope popped, and BEFORE the teardown was registered,
	inside no pcall. A Readable holding an invalid value at that moment therefore
	raised out of `presenter.dismiss` with the surface half-dismantled: its
	instances stayed mounted forever, the pending teardown was never registered
	so nothing could flush it, and the id could never be presented again.

	`transitions.resolve`'s own header already said what the fix is — "Read once
	at the structural event boundary. The mounted node retains the source; an
	active entry retains this validated value snapshot." A surface's own spec now
	obeys the same rule: resolved once at PRESENT, kept on the handle, read from
	there at dismiss. A Readable that changes mid-surface therefore applies to the
	NEXT present, which is the only instant at which changing it can be honoured
	without the exit disagreeing with the enter it is mirroring. ]]
describe("presenter: a surface's transition is resolved at present, never again (D1)", function()
	local function boundWorld(value: any)
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		local UI = w.UI
		local declared = w.Compose.cell(value)
		local function screen()
			return UI.Screen("Bound")({
				UI.ZStack("Content")({
					canvasGroup = true,
					UI.Button("Ok")({ label = "Ok", onActivate = noop }),
				}),
			})
		end
		return w, declared, screen
	end

	it("a Readable that goes invalid mid-surface still dismisses cleanly", function()
		local w, declared, screen = boundWorld({ enter = "fade" })
		local rootsBefore = w.adapter.rootCount()
		local handle = w.present(screen, { transition = declared })
		for _ = 1, 90 do
			w.pres.tick(1 / 60)
		end
		expect(w.adapter.rootCount()).toBe(rootsBefore + 1)

		-- the value goes bad while the surface is up
		declared:set({ enter = "swirl" })
		local ok, err = pcall(function()
			w.pres.dismiss(handle)
		end)
		expect(`dismissed {ok} {if ok then "" else tostring(err)}`).toBe("dismissed true ")
		expect(w.pres.depth()).toBe(0)

		-- ...and the exit really runs and really finishes, so nothing is stranded
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(w.adapter.rootCount()).toBe(rootsBefore)
	end)

	it("...and the id can be presented again afterwards", function()
		local w, declared, screen = boundWorld({ enter = "fade" })
		local rootsBefore = w.adapter.rootCount()
		local handle = w.present(screen, { transition = declared })
		for _ = 1, 90 do
			w.pres.tick(1 / 60)
		end
		declared:set({ enter = "swirl" })
		pcall(function()
			w.pres.dismiss(handle)
		end)
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(w.adapter.rootCount()).toBe(rootsBefore)
		-- a NEW present reads the Readable again, so the bad value is refused HERE
		-- — at the boundary that can still say so — rather than half way through a
		-- dismissal that has already destroyed the context
		local refused = pcall(function()
			w.present(screen, { transition = declared })
		end)
		expect(refused).toBe(false)
		--[[ a `present()` that RAISES leaves the root it had already built — a
			pre-existing shape of every mid-present failure (a bad blueprint does
			the same) and not this item's, so the count below is taken from here
			rather than pretending the refusal was free. Ledgered in the report. ]]
		local afterRefusal = w.adapter.rootCount()
		declared:set({ enter = "fade" })
		local again = w.present(screen, { transition = declared })
		expect(again ~= nil).toBe(true)
		expect(w.adapter.rootCount()).toBe(afterRefusal + 1)
		-- ...and it is a LIVE surface, not a husk: it dismisses the ordinary way
		w.pres.dismiss(again)
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(w.adapter.rootCount()).toBe(afterRefusal)
	end)

	it("a Readable that changes mid-surface applies to the NEXT present, not this exit", function()
		--[[ the documented consequence of snapshotting: an exit mirrors the enter
			it was presented with. Swapping the declaration to `exit = "instant"`
			while the surface is up does NOT make this dismissal instant. ]]
		local w, declared, screen = boundWorld({ enter = "fade" })
		local rootsBefore = w.adapter.rootCount()
		local handle = w.present(screen, { transition = declared })
		for _ = 1, 90 do
			w.pres.tick(1 / 60)
		end
		declared:set({ enter = "fade", exit = "instant" })
		w.pres.dismiss(handle)
		w.pres.refresh()
		-- still on screen, still fading on the spec it was PRESENTED with
		expect(w.adapter.rootCount()).toBe(rootsBefore + 1)
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(w.adapter.rootCount()).toBe(rootsBefore)

		-- ...and the NEXT present takes the new value: an instant exit now
		local second = w.present(screen, { transition = declared })
		for _ = 1, 90 do
			w.pres.tick(1 / 60)
		end
		w.pres.dismiss(second)
		w.pres.refresh()
		expect(w.adapter.rootCount()).toBe(rootsBefore)
	end)
end)

describe("presenter: two LIVE surfaces under one id are noted, once (D4)", function()
	--[[ `pendingExits` fixes the case where one surface is LEAVING under an id
		another is taking. It is keyed BY that id, so it has nothing to say about
		two surfaces that are both UP — and they collide anyway: every node path
		is rooted at `"/" .. (blueprint.id or "")`, so the adapter's path maps hold
		one owner per path and the second surface silently takes them over.

		A DIAGNOSTIC, NOT A REFUSAL (controller ruling): refusing would break
		whatever ships today doing this by accident. The refusal is ledgered as a
		follow-up. ]]
	local function twin(w: any, id: string)
		return function()
			return w.UI.Screen(id)({ w.UI.Button("Ok")({ label = "Ok", onActivate = noop }) })
		end
	end

	it("the second present under a live id notes it, and the third does not repeat it", function()
		local w = makeWorld()
		local pres = w.pres
		expect(#pres.surfaceIdNotes()).toBe(0)
		w.present(twin(w, "Twin"))
		-- one surface is not a collision
		expect(#pres.surfaceIdNotes()).toBe(0)
		w.present(twin(w, "Twin"))
		local notes = pres.surfaceIdNotes()
		expect(#notes).toBe(1)
		expect(string.find(notes[1], "already presented under the id 'Twin'", 1, true) ~= nil).toBe(true)
		expect(string.find(notes[1], "/Twin", 1, true) ~= nil).toBe(true)
		-- ...and it is ONCE PER ID, not once per collision: a session that opens
		-- the same duplicate repeatedly says it once
		w.present(twin(w, "Twin"))
		w.present(twin(w, "Twin"))
		expect(#pres.surfaceIdNotes()).toBe(1)
	end)

	it("a DIFFERENT duplicated id gets its own note", function()
		local w = makeWorld()
		local pres = w.pres
		w.present(twin(w, "A"))
		w.present(twin(w, "A"))
		w.present(twin(w, "B"))
		w.present(twin(w, "B"))
		expect(#pres.surfaceIdNotes()).toBe(2)
	end)

	it("presenting under an id whose surface has been DISMISSED is not a collision", function()
		-- the ordinary re-present, which is the shape `flushPendingExit` exists
		-- for: the first surface is gone from the stack, so nothing is noted
		local w = makeWorld()
		local pres = w.pres
		local first = w.present(twin(w, "Solo"))
		pres.dismiss(first)
		w.present(twin(w, "Solo"))
		expect(#pres.surfaceIdNotes()).toBe(0)
	end)

	it("the read is a COPY, like every other diagnostic read", function()
		local w = makeWorld()
		local pres = w.pres
		w.present(twin(w, "C"))
		w.present(twin(w, "C"))
		local notes = pres.surfaceIdNotes()
		table.clear(notes)
		expect(#pres.surfaceIdNotes()).toBe(1)
	end)
end)

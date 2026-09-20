--!strict
local harness = require("./lib/harness")
-- TextInput control tests (composite over UI.* primitives; the first Phase-5
-- expansion). The control is a ZStack of a new TextField leaf primitive (the
-- headless seam the engine maps to a TextBox) plus an optional trailing clear
-- Button shown via UI.When. The OWNER holds the `value` signal; the control
-- never creates it. Editing is a control-owned handshake: activating the field
-- (tap / focus+Activate on any input) enters edit mode, which raises a
-- high-priority SINKING InputContext so keystrokes stop being navigation while
-- a field is focused. Typed text arrives through the render-adapter seam
-- (setTextInputHandlers) exactly as the engine adapter will feed it; the model
-- clamps (maxLength) and validates every proposed edit before accepting it.
-- Every interaction goes through the REAL paths (adapter.tap / system.deviceKey
-- / the adapter text-input simulation), never by calling callbacks directly.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local Facet = require("../src") :: any
local text_input = require("../src/controls/text_input")
local fake_target = require("../tests/lib/fake_target")
local Compose = require("../src/vendor/compose/core")
local observeChange = require("../src/core/on_change")

local FIELD = "/S/Name/Field"
local CLEAR = "/S/Name/Clear"

-- headless world: mount the control under a Screen and present it, wiring the
-- presenter's Activate to the control's router and the two occlusion seams
-- (onGeometry feeds solved rects in; keepVisibleOffset drives the keep-visible
-- transform out). The action system is injected into the control so the
-- edit-mode sinking context is real (proved with system.deviceKey, never a
-- direct callback).
local function world(opts: any?)
	local options = opts or {}
	local core = options.core or harness.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	if options.reducedMotion == true then
		-- the FACT, never the derived key: `motionPolicy` is a memo over this and
		-- setting it directly is refused (tests/example_match3_motion.spec.luau)
		env:set("reducedMotion", true)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new({ ops = true })
	local pres = harness.newPresenter(core, env, adapter, system)

	local changes: { string } = {}
	local commits: { { text: string, reason: string } } = {}
	local value = options.value or Compose.cell(options.initial or "")

	local spec: any = {
		id = "Name",
		value = value,
		placeholder = options.placeholder,
		presentation = options.presentation,
		onChange = function(text: string)
			table.insert(changes, text)
		end,
		onCommit = function(text: string, reason: string)
			table.insert(commits, { text = text, reason = reason })
		end,
		disabled = options.disabled,
		keyboardType = options.keyboardType,
		submitLabel = options.submitLabel,
		clearButton = options.clearButton,
		clearButtonMode = options.clearButtonMode,
		maxLength = options.maxLength,
		validate = options.validate,
		invalid = options.invalid,
		numericValue = options.numericValue,
		min = options.min,
		max = options.max,
		env = if options.env == false then nil else env,
		actionSystem = system,
	}
	local control = text_input.build(Facet, core, spec)

	local screen = harness.UI.Screen({ id = "S", children = { control.blueprint } })
	local handle = pres.present(screen, {
		sinkNavigation = true,
		onActivate = function(path, meta)
			control.api.handleActivate(path, meta)
		end,
		onGeometry = function(rectOf)
			control.api.syncGeometry(rectOf)
		end,
		keepVisibleOffset = control.api.keepVisibleOffset,
	})
	pres.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		pres = pres,
		system = system,
		control = control,
		value = value,
		changes = changes,
		commits = commits,
		handle = handle,
	}
end

describe("TextInput: build + render (TextField primitive wired headless)", function()
	it("mounts and renders headlessly with no runtime error", function()
		local w = world({ placeholder = "Your name" })
		expect(w.control.blueprint ~= nil).toBe(true)
		expect(w.adapter.node(FIELD) ~= nil).toBe(true)
		expect(w.core.lastError()).toBeNil()
	end)

	it("the field shows the owner value as its text binding and the placeholder as data", function()
		local w = world({ initial = "Ada", placeholder = "Your name" })
		expect(w.adapter.node(FIELD).props.text).toBe("Ada")
		expect(w.adapter.node(FIELD).props.placeholder).toBe("Your name")
	end)

	it("a bare TextField primitive mounts and renders text/placeholder through the renderer", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 200 })
		local adapter = fake_target.new({ ops = true })
		local root = harness.mount(
			core,
			harness.UI.Screen({
				id = "S",
				children = { harness.UI.TextField({ id = "F", text = "hi", placeholder = "type", maxLength = 10 }) },
			})
		)
		local controller = Facet.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		local node = adapter.node("/S/F")
		expect(node ~= nil).toBe(true)
		expect(node.props.text).toBe("hi")
		expect(node.props.placeholder).toBe("type")
		expect(node.props.maxLength).toBe(10)
		expect(node.rect ~= nil).toBe(true)
	end)

	-- api-architecture-consistency F-26. `spec.env` is DOCUMENTED optional (and
	-- the control has three env reads: the keyboard-occlusion memo, the
	-- edit-start touch snapshot, and the hot-switch observer). Nothing proved
	-- the nil-env path, so the whole edit flow was one unguarded deref away from
	-- crashing on the first tap for anyone who took the documented option. This
	-- drives the flow end to end WITHOUT an env: the env only tells the control
	-- which classes were live, and without one there is simply no touch to
	-- snapshot and no occlusion to dodge.
	it("a TextInput with NO env builds, edits, types and commits (the documented optional)", function()
		local w = world({ env = false, initial = "" })
		expect(w.adapter.node(FIELD) ~= nil).toBe(true)
		w.adapter.tap(FIELD)
		expect(w.control.api.editing:peek()).toBe(true)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "abc")
		expect(w.value:peek()).toBe("abc")
		w.adapter.commitText(FIELD)
		expect(w.control.api.editing:peek()).toBe(false)
		expect(w.commits[1].text).toBe("abc")
		expect(w.core.lastError()).toBeNil()
	end)
end)

describe("TextInput: pointer (tap to edit, type, commit)", function()
	it("tapping the field enters editing (the control-owned handshake)", function()
		local w = world({ initial = "" })
		expect(w.control.api.editing:peek()).toBe(false)
		w.adapter.tap(FIELD)
		expect(w.control.api.editing:peek()).toBe(true)
		-- the engine adapter learns to CaptureFocus from the editing binding,
		-- flushed on the next presenter refresh (the client refreshes per frame)
		w.pres.refresh()
		expect(w.adapter.node(FIELD).props.editing).toBe(true)
	end)

	it("typed text flows through the adapter seam into the owner value, firing onChange per accepted edit", function()
		local w = world({ initial = "" })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "abc")
		expect(w.value:peek()).toBe("abc")
		expect(#w.changes).toBe(3)
		expect(w.changes[1]).toBe("a")
		expect(w.changes[3]).toBe("abc")
		-- typing has not committed yet
		expect(#w.commits).toBe(0)
	end)

	it("commit (engine Enter/focus-lost) fires onCommit with the reason and ends editing", function()
		local w = world({ initial = "" })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "hi")
		w.adapter.commitText(FIELD) -- engine FocusLost(enterPressed)
		expect(#w.commits).toBe(1)
		expect(w.commits[1].text).toBe("hi")
		expect(w.commits[1].reason).toBe("enter")
		expect(w.control.api.editing:peek()).toBe(false)
		expect(w.adapter.node(FIELD).props.editing).toBe(false)
	end)

	it("blur (focus lost without Enter) commits with reason focusLost", function()
		local w = world({ initial = "x" })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "y")
		w.adapter.blurText(FIELD)
		expect(#w.commits).toBe(1)
		expect(w.commits[1].reason).toBe("focusLost")
		expect(w.commits[1].text).toBe("xy")
	end)
end)

describe("TextInput: keyboard (Activate enters, sink blocks navigation, Enter commits, nav resumes)", function()
	-- a lower-than-edit-context probe: it sits ABOVE the presenter nav (so it
	-- fires normally when nobody sinks) yet BELOW the edit context (so editing's
	-- sink swallows the key before it arrives). Bound to DPadDown, which the
	-- edit context swallows.
	local function probe(w: any)
		local ctx = w.system.createContext({ name = "Probe", priority = 3000, sink = false })
		local nav = ctx.createAction("ProbeNav", "Direction1D")
		nav.bind({ keyCode = "DPadDown", direction = 1 })
		local fired = { n = 0 }
		nav.onReleased(function() end)
		observeChange(w.core.owner, nav.state, function(dir)
			if dir == 1 then
				fired.n += 1
			end
		end)
		return fired
	end

	it("focused field + Activate (Return) enters editing", function()
		local w = world({ initial = "" })
		expect(w.pres.focus.focused:peek()).toBe(FIELD)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.control.api.editing:peek()).toBe(true)
	end)

	it("while editing, navigation keys are sunk: a lower Navigate probe never fires and focus stays", function()
		local w = world({ initial = "" })
		local fired = probe(w)
		-- before editing, the probe fires (proves the probe path is live)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(fired.n).toBe(1)
		-- enter editing
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.control.api.editing:peek()).toBe(true)
		-- now DPadDown is swallowed by the edit context's sink
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(fired.n).toBe(1) -- unchanged: never fired while editing
		expect(w.pres.focus.focused:peek()).toBe(FIELD) -- focus did not move
	end)

	it("Enter commits, editing ends, and navigation works again (probe fires post-edit)", function()
		local w = world({ initial = "" })
		local fired = probe(w)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "hi")
		w.adapter.commitText(FIELD)
		expect(w.control.api.editing:peek()).toBe(false)
		expect(w.commits[1].reason).toBe("enter")
		-- navigation resumes
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(fired.n).toBe(1)
	end)

	it("Activate does not re-fire while editing: a second Return is an idempotent no-op", function()
		local w = world({ initial = "" })
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.control.api.editing:peek()).toBe(true)
		-- second Activate must not commit, must not change value, stays editing
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.control.api.editing:peek()).toBe(true)
		expect(#w.commits).toBe(0)
		expect(#w.changes).toBe(0)
	end)
end)

describe("TextInput: gamepad (D-pad focus, A enters, D-pad sunk, B cancels-revert, A re-enters)", function()
	it("ButtonA enters editing; D-pad does not navigate; ButtonB cancels reverting to the snapshot", function()
		local w = world({ initial = "seed" })
		expect(w.pres.focus.focused:peek()).toBe(FIELD)
		-- A enters edit
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.control.api.editing:peek()).toBe(true)
		-- edit the value
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "X")
		expect(w.value:peek()).toBe("seedX")
		expect(#w.changes).toBe(1)
		-- ButtonB cancels: revert to the pre-edit snapshot, end editing, focus stays
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		expect(w.value:peek()).toBe("seed") -- reverted
		expect(w.control.api.editing:peek()).toBe(false)
		expect(w.pres.focus.focused:peek()).toBe(FIELD) -- focus unchanged
		-- cancel fires NEITHER onCommit NOR an onChange for the revert
		expect(#w.commits).toBe(0)
		expect(#w.changes).toBe(1) -- still just the one edit, none for the revert
	end)

	it("ButtonA re-enters editing after a cancel", function()
		local w = world({ initial = "seed" })
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		expect(w.control.api.editing:peek()).toBe(false)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.control.api.editing:peek()).toBe(true)
	end)
end)

describe("TextInput: value model (onChange live, onCommit modes coexist, maxLength, validate)", function()
	it("onChange and onCommit are distinct and both fire", function()
		local w = world({ initial = "" })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "ab")
		expect(#w.changes).toBe(2) -- live edits
		expect(#w.commits).toBe(0)
		w.adapter.commitText(FIELD)
		expect(#w.commits).toBe(1) -- commit
		expect(w.commits[1].text).toBe("ab")
	end)

	it("maxLength clamps typed text at the value-model boundary", function()
		local w = world({ initial = "", maxLength = 5 })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "hello") -- exactly at the limit
		expect(w.value:peek()).toBe("hello")
		w.adapter.typeText(FIELD, "world") -- would exceed: each char clamped away
		expect(w.value:peek()).toBe("hello")
	end)

	it("maxLength clamps a paste-like multi-char append to the boundary", function()
		local w = world({ initial = "ab", maxLength = 5 })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.pasteText(FIELD, "cdefgh") -- one TextChanged: "abcdefgh" -> clamp
		expect(w.value:peek()).toBe("abcde")
	end)

	it("engine reports over-long text -> model clamps -> commit reconciles to the clamped value", function()
		local w = world({ initial = "", maxLength = 5 })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "hello")
		-- the engine view diverges (its buffer holds more) but the model holds
		-- the last accepted value; the text the adapter is told to show is clamped
		w.adapter.pasteText(FIELD, "XYZ") -- engine buffer now "helloXYZ"
		expect(w.value:peek()).toBe("hello") -- model never accepted the overflow
		-- the adapter is told to show the clamped model value (reconciled on the
		-- next refresh); the engine buffer's overflow never reaches the model
		w.pres.refresh()
		expect(w.adapter.node(FIELD).props.text).toBe("hello") -- reconciled view
		w.adapter.commitText(FIELD)
		expect(w.commits[1].text).toBe("hello")
	end)

	it("rejects an edit containing invalid UTF-8 (value unchanged, no onChange) with maxLength set", function()
		local w = world({ initial = "ok", maxLength = 10 })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.pasteText(FIELD, "\xC3(") -- lead byte with no valid continuation
		expect(w.value:peek()).toBe("ok") -- never accepted a non-UTF-8 byte sequence
		expect(#w.changes).toBe(0)
	end)

	it("rejects invalid UTF-8 even without maxLength (an applyProposed-level guard, not a truncate quirk)", function()
		local w = world({ initial = "ok" })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.pasteText(FIELD, "\xC3(")
		expect(w.value:peek()).toBe("ok")
		expect(#w.changes).toBe(0)
	end)

	it("validate normalizes accepted text and can reject an edit (value unchanged, no onChange)", function()
		local w = world({
			initial = "",
			validate = function(proposed: string): string?
				if string.find(proposed, "%d") ~= nil then
					return nil -- reject any edit that introduces a digit
				end
				return string.upper(proposed) -- normalize to upper-case
			end,
		})
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "ab")
		expect(w.value:peek()).toBe("AB") -- normalized
		expect(#w.changes).toBe(2)
		w.adapter.pasteText(FIELD, "9") -- rejected
		expect(w.value:peek()).toBe("AB") -- unchanged
		expect(#w.changes).toBe(2) -- no onChange for the rejected edit
	end)
end)

describe("TextInput: clear affordance", function()
	it(
		"the clear button appears only while value is non-empty; activating it empties the value (a user edit)",
		function()
			local w = world({ initial = "typed", clearButton = true })
			expect(w.adapter.node(CLEAR) ~= nil).toBe(true)
			w.adapter.tap(CLEAR)
			w.pres.refresh()
			expect(w.value:peek()).toBe("")
			-- clearing is a user edit: fires onChange, does NOT commit
			expect(#w.changes).toBe(1)
			expect(#w.commits).toBe(0)
			-- the affordance is gone now that the value is empty
			expect(w.adapter.node(CLEAR)).toBe(nil)
			-- focus returns to the field (the vanished clear's nearest survivor)
			expect(w.pres.focus.focused:peek()).toBe(FIELD)
		end
	)

	it("no clear button when the value is empty", function()
		local w = world({ initial = "", clearButton = true })
		expect(w.adapter.node(CLEAR)).toBe(nil)
	end)

	it(
		"the field fills full width and the clear ✕ sits inset INSIDE the field's right edge (WP7 drive defect 3)",
		function()
			local w = world({ initial = "typed", clearButton = true })
			local composite = w.handle.controller.rectOf("/S/Name")
			local field = w.handle.controller.rectOf("/S/Name/Field")
			-- the TextField spans the composite's FULL width (the inset must not come
			-- from a shared container padding that also shrinks the field)
			expect((field.x + field.w) == (composite.x + composite.w)).toBe(true)
			-- negative space between the field's right edge and the ✕
			local clear = w.handle.controller.rectOf(CLEAR)
			local gap = (field.x + field.w) - (clear.x + clear.w)
			expect(gap >= 8).toBe(true)
		end
	)

	it("the clear button sits at the field's trailing (right) edge, vertically centered (WP7 rider)", function()
		local w = world({ initial = "typed", clearButton = true })
		local fieldRect = w.handle.controller.rectOf("/S/Name")
		local clearRect = w.handle.controller.rectOf(CLEAR)
		expect(fieldRect ~= nil).toBe(true)
		expect(clearRect ~= nil).toBe(true)
		-- RIGHT-aligned: the clear's right edge sits within a small inset of the
		-- field's right edge (not flush-overflowing, not at the LEFT origin)
		local fieldRight = fieldRect.x + fieldRect.w
		local clearRight = clearRect.x + clearRect.w
		expect(fieldRight - clearRight >= 0).toBe(true) -- inside the field
		expect(fieldRight - clearRight <= 12).toBe(true) -- within a sane inset
		expect(clearRect.x > fieldRect.x + fieldRect.w / 2).toBe(true) -- in the right half
		-- vertically centered, not pinned to the top origin
		expect(clearRect.y > fieldRect.y).toBe(true)
	end)
end)

describe("TextInput: disabled", function()
	it("a disabled field is not focusable, tap does nothing, and shows no clear button", function()
		local w = world({ initial = "locked", disabled = true, clearButton = true })
		-- not focusable: the presenter's initial focus is not the field
		expect(w.pres.focus.focused:peek()).never().toBe(FIELD)
		-- tap does nothing: editing never begins
		w.adapter.tap(FIELD)
		expect(w.control.api.editing:peek()).toBe(false)
		-- no clear affordance while disabled
		expect(w.adapter.node(CLEAR)).toBe(nil)
	end)
end)

describe("TextInput: keyboardType", function()
	it("a known keyboardType lands on the field as data for the engine adapter", function()
		local w = world({ initial = "", keyboardType = "numeric" })
		expect(w.adapter.node(FIELD).props.keyboardType).toBe("numeric")
	end)

	it("numeric, email, and phone keyboardType hints are accepted and land on the field as data", function()
		-- the engine enum has Number/Email/Phone (facts §1); the model accepts the
		-- matching hint vocabulary so a numeric/email/phone field can restrict the
		-- on-screen layout on engines that expose the (security-locked) member.
		for _, kt in { "default", "numeric", "email", "phone" } do
			local w = world({ initial = "", keyboardType = kt })
			expect(w.adapter.node(FIELD).props.keyboardType).toBe(kt)
		end
	end)

	it("an unknown keyboardType is a build error", function()
		local core = harness.newCore()
		local ok = pcall(function()
			text_input.build(Facet, core, {
				id = "Bad",
				value = Compose.cell(""),
				keyboardType = "frobnicate",
			})
		end)
		expect(ok).toBe(false)
	end)
end)

-- The keyboardType engine APPLICATION is capability-gated: TextBox.TextInputType
-- is a real member but RobloxScript-security-locked both directions on shipping
-- game/plugin scripts (docs/research/2026-07-20-textbox-engine-facts.md §1), so
-- screen_target's canSetTextInputType probe is false and the mapped write is
-- skipped (clean degrade). The FakeTarget mirrors that gate headlessly: the
-- declared hint always lands as data (props.keyboardType), while
-- appliedTextInputType() reports the engine token the adapter WOULD apply —
-- mapped when capable, nothing when not.
describe("TextInput: keyboardType engine-application contract (capability-gated)", function()
	it("nothing is applied to the engine on a shipping (not-capable) adapter", function()
		local w = world({ initial = "", keyboardType = "email" })
		expect(w.adapter.appliedTextInputType(FIELD)).toBe(nil)
	end)

	it("the MAPPED engine text-input-type reaches the adapter once it is capable", function()
		local w = world({ initial = "", keyboardType = "email" })
		w.adapter.setTextInputTypeCapable(true)
		expect(w.adapter.appliedTextInputType(FIELD)).toBe("Email")
	end)

	it("maps numeric -> Number and phone -> Phone when capable", function()
		local wn = world({ initial = "", keyboardType = "numeric" })
		wn.adapter.setTextInputTypeCapable(true)
		expect(wn.adapter.appliedTextInputType(FIELD)).toBe("Number")
		local wp = world({ initial = "", keyboardType = "phone" })
		wp.adapter.setTextInputTypeCapable(true)
		expect(wp.adapter.appliedTextInputType(FIELD)).toBe("Phone")
	end)
end)

-- submitLabel (Return-key label hint) has NO reachable public engine surface:
-- TextBox.ReturnKeyType is [Hidden, NotReplicated] / absent from public creator
-- docs (artifacts/expansion-textinput/platform-research.json), so — unlike
-- keyboardType — there is nothing to wire even behind a capability gate. It is a
-- declared-intent hint carried as model data (parity with keyboardType-as-data,
-- the TextInput expansion), a justified engine-absent exception. Validated as a
-- closed set.
describe("TextInput: submitLabel (declared Return-key hint; engine-absent clean degrade)", function()
	it("a known submitLabel is accepted and carried as declared data (dump)", function()
		local w = world({ initial = "", submitLabel = "search" })
		expect(w.control.dump().submitLabel).toBe("search")
	end)

	it("defaults to 'default' when unset", function()
		local w = world({ initial = "" })
		expect(w.control.dump().submitLabel).toBe("default")
	end)

	it("an unknown submitLabel is a build error", function()
		local core = harness.newCore()
		local ok = pcall(function()
			text_input.build(Facet, core, {
				id = "Bad",
				value = Compose.cell(""),
				submitLabel = "frobnicate",
			})
		end)
		expect(ok).toBe(false)
	end)
end)

describe("TextInput: keyboard-occlusion keep-visible", function()
	it("a mid-edit occlusion that overlaps the field produces an upward transform, restored on dismiss", function()
		-- place the field low so the on-screen keyboard overlaps it
		local w = world({ initial = "" })
		-- enter editing so the keep-visible policy is active
		w.adapter.tap(FIELD)
		expect(w.control.api.editing:peek()).toBe(true)
		local rect = w.handle.controller.rectOf(FIELD)
		expect(rect ~= nil).toBe(true)
		w.adapter.takeOps()
		local runsBefore = w.handle.root.counters().factoryRuns
		-- keyboard rises to cover the lower part of the screen, overlapping the field
		local keyboardTop = rect.y + rect.h - 20 -- overlaps the field's bottom by 20
		w.env:set("keyboardOcclusionRect", { x = 0, y = keyboardTop, w = 800, h = 600 - keyboardTop })
		-- the control exposes a positive keep-visible offset
		expect(w.control.api.keepVisibleOffset:peek()).toBeGreaterThan(0)
		-- the presented screen shifts up via a presentation transform...
		expect(w.adapter.node("/S").props.transform ~= nil).toBe(true)
		expect(w.adapter.node("/S").props.transform.y).toBeLessThan(0)
		-- ...as prop/transform writes only: no remount, zero factory reruns
		expect(w.handle.root.counters().factoryRuns).toBe(runsBefore)
		local ops = w.adapter.takeOps()
		for _, op in ops do
			expect(string.sub(op, 1, 6) == "create" or string.sub(op, 1, 6) == "remove").toBe(false)
		end
		-- keyboard dismisses: the offset restores to zero
		w.env:set("keyboardOcclusionRect", nil)
		expect(w.control.api.keepVisibleOffset:peek()).toBe(0)
	end)

	it("no occlusion offset when not editing, even if the keyboard rect is set", function()
		local w = world({ initial = "" })
		w.env:set("keyboardOcclusionRect", { x = 0, y = 0, w = 800, h = 600 })
		expect(w.control.api.keepVisibleOffset:peek()).toBe(0)
	end)

	it("disposing the control mid-occlusion restores the screen's presentation transform to 0 (ARCH-TI-2)", function()
		local w = world({ initial = "" })
		w.adapter.tap(FIELD)
		local rect = w.handle.controller.rectOf(FIELD)
		local keyboardTop = rect.y + rect.h - 20
		w.env:set("keyboardOcclusionRect", { x = 0, y = keyboardTop, w = 800, h = 600 - keyboardTop })
		expect(w.control.api.keepVisibleOffset:peek()).toBeGreaterThan(0)
		expect(w.adapter.node("/S").props.transform.y).toBeLessThan(0) -- shifted up
		-- dispose the CONTROL while the screen stays PRESENTED (not dismissed):
		-- the presentation offset must not stay frozen at -dy
		w.control.dispose()
		expect(w.adapter.node("/S").props.transform.y).toBe(0)
	end)

	it("engine-initiated focus (native TextBox tap, NO prior activate) is occlusion-capable", function()
		-- F1 (WP3 decision 2): on the real engine a pointer/touch tap focuses the
		-- TextBox NATIVELY (setActivateHandler is a no-op for a non-GuiButton), so
		-- handleActivate never runs — editing begins via onFocusGained. The field
		-- must still learn its path from that seam or keep-visible stays dead on
		-- exactly the touch path where occlusion matters most.
		local w = world({ initial = "" })
		w.adapter.focusText(FIELD) -- engine-initiated focus; NO tap/activate first
		expect(w.control.api.editing:peek()).toBe(true)
		local rect = w.handle.controller.rectOf(FIELD)
		expect(rect ~= nil).toBe(true)
		local keyboardTop = rect.y + rect.h - 20
		w.env:set("keyboardOcclusionRect", { x = 0, y = keyboardTop, w = 800, h = 600 - keyboardTop })
		expect(w.control.api.keepVisibleOffset:peek()).toBeGreaterThan(0)
	end)
end)

describe("TextInput: touch (activation + keep-visible, end to end)", function()
	it("a touch tap enters editing and the occlusion keep-visible engages (touch story end to end)", function()
		local w = world({ initial = "" })
		-- activate via a TOUCH pointer (tap meta { pointer = "touch" }); touch
		-- rides the same onNodeTap seam as mouse (touch parity by construction)
		w.adapter.tap(FIELD, { pointer = "touch" })
		expect(w.control.api.editing:peek()).toBe(true)
		-- the on-screen keyboard rises and overlaps the field's lower edge
		local rect = w.handle.controller.rectOf(FIELD)
		expect(rect ~= nil).toBe(true)
		local keyboardTop = rect.y + rect.h - 20
		w.env:set("keyboardOcclusionRect", { x = 0, y = keyboardTop, w = 800, h = 600 - keyboardTop })
		expect(w.control.api.keepVisibleOffset:peek()).toBeGreaterThan(0)
		-- tapping away commits by focus loss and dismisses; the offset restores
		w.adapter.blurText(FIELD)
		expect(w.control.api.editing:peek()).toBe(false)
		expect(w.commits[1].reason).toBe("focusLost")
		expect(w.control.api.keepVisibleOffset:peek()).toBe(0)
	end)
end)

describe("TextInput: conformance (reactive discipline, dump, registry neutrality)", function()
	it("typing does not rerun the factory or remount (paint/semantic writes only)", function()
		local w = world({ initial = "" })
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		local runs = w.handle.root.counters().factoryRuns
		w.adapter.takeOps()
		w.adapter.typeText(FIELD, "abcde")
		expect(w.handle.root.counters().factoryRuns).toBe(runs) -- no factory reruns
		local ops = w.adapter.takeOps()
		for _, op in ops do
			expect(string.sub(op, 1, 6) == "create" or string.sub(op, 1, 6) == "remove").toBe(false)
		end
	end)

	it("dump() is deterministic and reflects value, editing, placeholder-visible, clearVisible, offset", function()
		local w = world({ initial = "", placeholder = "Name", clearButton = true })
		local d1 = serde.encode("json", w.control.dump(), true)
		expect(d1).toBe(serde.encode("json", w.control.dump(), true))
		expect(w.control.dump().value).toBe("")
		expect(w.control.dump().editing).toBe(false)
		expect(w.control.dump().placeholderVisible).toBe(true)
		expect(w.control.dump().clearVisible).toBe(false)
		expect(w.control.dump().occlusionOffset).toBe(0)
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "z")
		expect(w.control.dump().editing).toBe(true)
		expect(w.control.dump().value).toBe("z")
		expect(w.control.dump().placeholderVisible).toBe(false)
		expect(w.control.dump().clearVisible).toBe(true)
	end)

	it("build/mount/interact/dispose returns every registry to its baseline (incl. a mid-edit dispose)", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new({ ops = true })
		local pres = harness.newPresenter(core, env, adapter, system)
		local baseline = core.owner.size()

		local value = Compose.cell("")
		local control = text_input.build(Facet, core, {
			id = "Name",
			value = value,
			placeholder = "Name",
			clearButton = true,
			maxLength = 10,
			onChange = function() end,
			onCommit = function() end,
			env = env,
			actionSystem = system,
		})
		local screen = harness.UI.Screen({ id = "S", children = { control.blueprint } })
		local handle = pres.present(screen, {
			sinkNavigation = true,
			onActivate = function(path, meta)
				control.api.handleActivate(path, meta)
			end,
			onGeometry = function(rectOf)
				control.api.syncGeometry(rectOf)
			end,
			keepVisibleOffset = control.api.keepVisibleOffset,
		})
		pres.refresh()
		-- exercise: edit, type, occlude, then dispose WHILE STILL EDITING (the
		-- edit-mode context must be disposed by the control's dispose)
		adapter.tap(FIELD)
		adapter.focusText(FIELD)
		adapter.typeText(FIELD, "abc")
		env:set("keyboardOcclusionRect", { x = 0, y = 0, w = 800, h = 600 })
		expect(control.api.editing:peek()).toBe(true)

		pres.dismiss(handle)
		control.dispose()

		local after = core.owner.size()
		expect(after).toBe(baseline)
	end)
end)

describe("TextInput: build-time contract", function()
	it("value is required and must be a Compose cell the caller owns", function()
		local core = harness.newCore()
		expect(pcall(function()
			text_input.build(Facet, core, { id = "NoValue" })
		end)).toBe(false)
		expect(pcall(function()
			text_input.build(Facet, core, { id = "BadValue", value = "not a signal" })
		end)).toBe(false)
	end)

	it("value must be a WRITABLE cell — a read-only formula is a build error (ARCH-TI-1)", function()
		local core = harness.newCore()
		local memo = Compose.formula(function()
			return "x"
		end)
		-- a formula passes a bare readable check but errors on the first edit
		-- (value:set); fail loudly at BUILD instead
		local ok, err = pcall(function()
			text_input.build(Facet, core, { id = "M", value = memo })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "writable Compose cell", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===========================================================================
-- Dispose/activate race (Studio drive F2, 2026-07-21): an Activate that
-- reaches a control AFTER its dispose must be a harmless no-op — never a
-- "cannot own into a disposed scope" fault from ensureEditContext. Observed
-- live during rapid example switching (stale handle dispatched a late tap).
-- ===========================================================================
describe("TextInput: activate after dispose is a harmless no-op", function()
	it("handleActivate on a disposed control neither throws nor enters editing", function()
		local w = world()
		w.control.dispose()
		local ok, err = pcall(function()
			w.control.api.handleActivate("/S/Name/Field", { source = "pointer", pointer = "mouse" })
		end)
		expect(ok).toBe(true)
		expect(err).toBe(nil)
		expect(w.control.api.editing:peek()).toBe(false)
	end)
end)

-- ===========================================================================
-- THE CLEAR CHIP IS A GLYPH, NOT A LABELLED BUTTON
-- (director round 10, found live 2026-07-26 on two themes)
--
-- It was a `fixed` 28px box carrying a Button's default text inset — 12 a side,
-- which exists to keep a WORD off a plate's edge. That leaves 4px for the ×, so
-- the glyph drew at its natural size OUTSIDE its own plate; and a package that
-- skins `control` (Glossy Touch reserves 14 a side, Pixel Quest 16) drove the
-- content box to zero outright.
-- ===========================================================================
describe("TextInput: the clear chip sizes for its glyph, in every theme", function()
	local themes = Facet.themes

	local function clearRect(pkgModule: any?): any
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new({ ops = true })
		local pres = harness.newPresenter(core, env, adapter, system)
		local control = harness.Controls.TextInput(core, {
			id = "F",
			value = Compose.cell("typed"),
			placeholder = "filter",
			clearButton = true,
		})
		pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		if pkgModule ~= nil then
			env:set("themeMetrics", themes.resolve(pkgModule, nil, {}))
			pres.refresh()
		end
		return adapter.node("/S/F/Clear").rect
	end

	it("a flat theme keeps the historic 28px chip exactly", function()
		local r = clearRect(nil)
		expect(r.w).toBe(28)
		expect(r.h).toBe(28)
	end)

	it("but it never grows TALLER than the field it lives inside", function()
		-- a floor alone let the box outgrow its container: Pixel Quest reserves
		-- 16px a side, which took a 28px chip to 52 inside a 44px field, so the ✕
		-- hung out of the field top and bottom (measured 2026-07-27).
		for _, name in { "glossy_touch", "pixel_quest", "fantasy_ornate" } do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			local snap = themes.resolve(pkg, nil, {})
			expect(clearRect(pkg).h <= snap.controls.textInput.fieldHeight).toBe(true)
		end
	end)

	it("a skinning theme GROWS the chip for its own frame instead of eating the glyph", function()
		for _, name in { "glossy_touch", "pixel_quest" } do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			local snap = themes.resolve(pkg, nil, {})
			local reserve = snap.chromeInsets.control
			expect(reserve.left > 0).toBe(true)
			local r = clearRect(pkg)
			-- the box is at least its floor PLUS what the art reserves, so the
			-- content box the glyph draws in never goes to zero
			expect(r.w >= reserve.left + reserve.right).toBe(true)
			expect(r.w >= 28).toBe(true)
			expect(r.h >= 28).toBe(true)
		end
	end)
end)

-- ===========================================================================
-- clearButtonMode — the four conventional answers, because they are the four real ones
-- (director request, 2026-07-27: "something akin to the conventional
-- textField.clearButtonMode = .whileEditing")
-- ===========================================================================
describe("TextInput: clearButtonMode", function()
	local CLEAR_PATH = "/S/Name/Clear"

	local function modeWorld(mode: any, initial: string?)
		local w = world({ initial = initial or "typed", clearButtonMode = mode })
		w.pres.refresh()
		return w
	end
	local function focus(w: any)
		w.adapter.tap(FIELD)
		w.adapter.focusText(FIELD)
		w.pres.refresh()
	end
	local function blur(w: any)
		w.adapter.blurText(FIELD)
		w.pres.refresh()
	end

	it("never: no affordance, whatever the text or the focus", function()
		local w = modeWorld("never")
		expect(w.adapter.node(CLEAR_PATH)).toBe(nil)
		focus(w)
		expect(w.adapter.node(CLEAR_PATH)).toBe(nil)
	end)

	it("always: offered whenever there is something to clear, editing or not", function()
		local w = modeWorld("always")
		expect(w.adapter.node(CLEAR_PATH) ~= nil).toBe(true)
		focus(w)
		expect(w.adapter.node(CLEAR_PATH) ~= nil).toBe(true)
	end)

	it("whileEditing: appears with the caret and leaves with it", function()
		local w = modeWorld("whileEditing")
		expect(w.adapter.node(CLEAR_PATH)).toBe(nil) -- text, but not editing
		focus(w)
		expect(w.adapter.node(CLEAR_PATH) ~= nil).toBe(true)
		blur(w)
		expect(w.adapter.node(CLEAR_PATH)).toBe(nil)
	end)

	it("unlessEditing: the mirror image — it gets out of the way while you type", function()
		local w = modeWorld("unlessEditing")
		expect(w.adapter.node(CLEAR_PATH) ~= nil).toBe(true)
		focus(w)
		expect(w.adapter.node(CLEAR_PATH)).toBe(nil)
	end)

	it("every mode still needs SOMETHING to clear — an empty field offers nothing", function()
		for _, mode in { "always", "whileEditing", "unlessEditing" } do
			local w = modeWorld(mode, "")
			expect(w.adapter.node(CLEAR_PATH)).toBe(nil)
			focus(w)
			expect(w.adapter.node(CLEAR_PATH)).toBe(nil)
		end
	end)

	it("`clearButton = true` still means `always`, so nothing published breaks", function()
		local w = world({ initial = "typed", clearButton = true })
		expect(w.adapter.node(CLEAR_PATH) ~= nil).toBe(true)
		expect(w.control.dump().clearButtonMode).toBe("always")
	end)

	it("an unrecognised mode is a build error, not a field that never offers a ✕", function()
		local core = harness.newCore()
		expect(pcall(function()
			return harness.Controls.TextInput(core, {
				id = "Bad",
				value = Compose.cell(""),
				clearButtonMode = "sometimes",
			})
		end)).toBe(false)
	end)
end)

describe("TextInput: themed search art", function()
	it("keeps its semantic request and live icon geometry across art and glyph themes", function()
		local w = world({ presentation = "search", initial = "kept" })
		local iconPath = "/S/Name/SearchIcon"
		local icon = w.adapter.node(iconPath)
		expect(icon.decorationHint.icon).toBe("facet:search")
		expect(icon.props.text).toBe("o/")
		local neutral = require("../src/themes/snapshot").neutralPackage()
		local ornate = require("../examples/themes/fantasy_ornate").build(Facet.themes)
		local glyph = require("../examples/themes/compact_pointer").build(Facet.themes)
		for _, pkg in { neutral, ornate, glyph, neutral } do
			local snap = Facet.themes.resolve(pkg, nil, {})
			w.env:set("themeMetrics", snap)
			w.pres.refresh()
			local node = w.adapter.node(iconPath)
			local resolved = require("../src/themes/package").resolveIcon(pkg, "facet:search")
			expect(node).toBe(icon) -- theme changes remeasure the existing control
			expect(node.decorationHint.icon).toBe("facet:search")
			if resolved.source == "asset" then
				expect(node.rect.w >= snap.iconSizes.medium).toBe(true)
				expect(node.rect.h >= snap.iconSizes.medium).toBe(true)
			else
				expect(node.props.text).toBe(resolved.glyph)
				-- The prior ornate picture reserved 32px; opting out removes that floor.
				expect(node.rect.w < Facet.themes.resolve(ornate, nil, {}).iconSizes.medium).toBe(true)
			end
			expect(w.value:peek()).toBe("kept")
			expect(w.core.lastError()).toBeNil()
		end
		w.pres.dismiss(w.handle)
		w.control.dispose()
	end)
end)

--[[ THE INVALID SHAKE (transitions round 2026-09-12).

	`invalid` is a caller-owned readable boolean whose false->true edge nudges the
	field sideways and back, and the number presentation shakes on the same edge of
	its OWN validation message. It rides the paint-only `offset` prop, so the claim
	that has to hold is the PAIR: the painted position moved, and the solved rect —
	what the solver, hit-testing and the focus order all read — did not. The shake
	is decorative, so a reduced-motion session drops it whole (the timeline's own
	policy), which is the second test here. ]]
describe("TextInput: the invalid shake", function()
	local FRAME = 1 / 60

	-- the PAINTED displacement: the fake target composes `rect + transform` into
	-- `presentedPosition` exactly as the live adapter writes the engine Position
	-- (tests/with_animation.spec.luau reads the same accessor)
	local function paintedShift(w: any, path: string): number
		local node = w.adapter.node(path)
		return node.presentedPosition.x - node.rect.x
	end

	-- one presenter frame: step the motion clock, then commit what it dirtied
	local function frame(w: any)
		w.pres.tick(FRAME)
		w.pres.refresh()
	end

	it("a false->true edge nudges the root sideways and returns to rest", function()
		local core = harness.newCore()
		local invalid = Compose.cell(false)
		local w = world({ core = core, invalid = invalid })
		local restX = w.adapter.node("/S/Name").rect.x
		local restY = w.adapter.node("/S/Name").rect.y
		expect(paintedShift(w, "/S/Name")).toBe(0)

		invalid:set(true)
		frame(w)
		expect(paintedShift(w, "/S/Name") ~= 0).toBe(true)
		-- the solver never moved: the rect the hit test and focus order read is
		-- exactly where it was before the shake began
		expect(w.adapter.node("/S/Name").rect.x).toBe(restX)
		expect(w.adapter.node("/S/Name").rect.y).toBe(restY)

		-- it crosses the rest line rather than leaning to one side
		local sawNegative, sawPositive = false, false
		for _ = 1, 40 do
			local shift = paintedShift(w, "/S/Name")
			sawNegative = sawNegative or shift < 0
			sawPositive = sawPositive or shift > 0
			frame(w)
		end
		expect(sawNegative).toBe(true)
		expect(sawPositive).toBe(true)
		expect(paintedShift(w, "/S/Name")).toBe(0)
		expect(w.adapter.node("/S/Name").rect.x).toBe(restX)
		expect(w.core.lastError()).toBeNil()
		w.control.dispose()
	end)

	--[[ A SECOND EDGE MID-SHAKE RESTARTS IT — and the proof is not "it ends at
		rest" (two racing timelines end at rest too), it is that the restarted shake
		retraces a fresh shake's first frames exactly. The nudge is interpolated, so
		a shake left running underneath would show through as a different
		displacement on those frames. ]]
	it("a second edge mid-shake restarts it rather than racing the one already running", function()
		local core = harness.newCore()
		local invalid = Compose.cell(false)
		local w = world({ core = core, invalid = invalid })
		invalid:set(true)
		local fresh: { number } = {}
		for index = 1, 10 do
			frame(w)
			fresh[index] = paintedShift(w, "/S/Name")
		end
		expect(fresh[1] ~= 0).toBe(true)
		invalid:set(false)
		invalid:set(true)
		for index = 1, 4 do
			frame(w)
			expect(paintedShift(w, "/S/Name")).toBe(fresh[index])
		end
		for _ = 1, 40 do
			frame(w)
		end
		expect(paintedShift(w, "/S/Name")).toBe(0)
		expect(w.core.lastError()).toBeNil()
		w.control.dispose()
	end)

	it("reduced motion keeps the message and drops the shake", function()
		local core = harness.newCore()
		local invalid = Compose.cell(false)
		local w = world({ core = core, invalid = invalid, reducedMotion = true })
		expect(w.env:get("motionPolicy"):peek()).toBe("reduced")
		invalid:set(true)
		w.pres.refresh()
		-- not "settles at rest" but "never leaves it", on EVERY frame the shake
		-- would have been playing across
		expect(paintedShift(w, "/S/Name")).toBe(0)
		for _ = 1, 20 do
			frame(w)
			expect(paintedShift(w, "/S/Name")).toBe(0)
		end
		expect(w.core.lastError()).toBeNil()
		w.control.dispose()
	end)

	it("a rejected numeric commit shakes the field and leaves the message beneath it still", function()
		local core = harness.newCore()
		local number = Compose.cell(2)
		local w = world({ core = core, presentation = "number", numericValue = number, min = 0, max = 10 })
		local messageX = w.adapter.node("/S/Name/Validation").rect.x
		expect(paintedShift(w, "/S/Name/Input")).toBe(0)

		w.adapter.tap("/S/Name/Input/Field")
		w.adapter.pasteText("/S/Name/Input/Field", "-")
		w.adapter.commitText("/S/Name/Input/Field")
		expect(w.control.dump().validationError ~= "").toBe(true)
		frame(w)
		-- the FIELD moved; the danger-tinted message is the information and holds
		-- its place
		expect(paintedShift(w, "/S/Name/Input") ~= 0).toBe(true)
		expect(paintedShift(w, "/S/Name/Validation")).toBe(0)
		expect(w.adapter.node("/S/Name/Validation").rect.x).toBe(messageX)
		for _ = 1, 40 do
			frame(w)
		end
		expect(paintedShift(w, "/S/Name/Input")).toBe(0)
		expect(w.core.lastError()).toBeNil()
		w.control.dispose()
	end)

	--[[ THE TIMELINE BELONGS TO THE CONTROL'S OWNER, so disposing mid-shake ends
		it: no beat fires afterwards, no write reaches a cell the same teardown just
		disposed, and the presenter's own clock never carried it. ]]
	it("disposing mid-shake leaves nothing armed", function()
		local core = harness.newCore()
		local invalid = Compose.cell(false)
		local w = world({ core = core, invalid = invalid })
		local atRest = w.pres.motionClock:activeCount()
		invalid:set(true)
		frame(w)
		expect(paintedShift(w, "/S/Name") ~= 0).toBe(true)
		w.control.dispose()
		-- no beat fires after the dispose: the displacement stays where the
		-- teardown left it, on every frame the shake would still have played
		local held = paintedShift(w, "/S/Name")
		for _ = 1, 10 do
			frame(w)
			expect(paintedShift(w, "/S/Name")).toBe(held)
		end
		-- the presenter's clock carries nothing of the control's
		expect(w.pres.motionClock:activeCount()).toBe(atRest)
		w.pres.dismiss(w.handle)
		for _ = 1, 40 do
			w.pres.tick(FRAME)
		end
		expect(core.lastError()).toBeNil()
		expect(w.pres.motionClock:lastError()).toBeNil()
	end)

	it("invalid refuses anything but a readable boolean", function()
		local core = harness.newCore()
		Facet.newEnvironment(core)
		for _, bad in { true, "yes", 1, Compose.cell("no") } do
			local ok, err =
				pcall(harness.Controls.TextInput, core, { id = "Name", value = Compose.cell(""), invalid = bad })
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "invalid", 1, true) ~= nil).toBe(true)
		end
	end)
end)

--!strict
-- RenderTargetAdapter contract (design §13, ADR-0003/ADR-0009): the seam every
-- render target implements. The renderer feature-detects OPTIONAL methods with
-- `~= nil`; REQUIRED ones it calls unconditionally. Headless conformance
-- (tests/render_target_contract.spec.luau) checks the FakeTarget against this
-- list; engine adapters (ScreenTarget, BillboardTarget) are checked at runtime
-- during their Studio drives — an adapter missing an optional method degrades
-- (no z-order, no pointer), never crashes.

local target_contract = {}

-- `create`'s optional arguments are CREATION-TIME facts an adapter can only honour
-- while it is choosing the engine object: the decoration hint it classifies a
-- decoration slot from (ADR-0019), and `createOpts` — today `{ canvasGroup }`,
-- which decides the node's engine CLASS so a subtree can be faded as one group
-- (ADR-0022 Decision 2). Neither can arrive as a later prop write; an adapter that
-- does not skin or group ignores them.
--
-- `setProp` DISPATCHES ON A NAME, and the set of names is part of this contract:
-- `renderer.EMITTED_PROPS` declares every one the renderer can write and
-- tests/render_target_contract.spec.luau pins it against both adapters' handler
-- lists. A target that silently ignores a written prop is the SF-M9 defect class
-- (docs/lessons/fake-adapter-records-what-live-adapter-ignores.md).
target_contract.REQUIRED = {
	"createRoot", -- (screenId) -> rootHandle
	"create", -- (rootHandle, path, class, decorationHint?, createOpts?) -> handle
	"setRect", -- (handle, rect)                     [layout authority]
	"setProp", -- (handle, prop, value, authority)
	"remove", -- (handle)
	"destroyRoot", -- (rootHandle)
}

target_contract.OPTIONAL = {
	"setActivateHandler", -- (handle, fn(meta?))     [taps -> semantic activate]
	"setFocusVisual", -- (handle, on, profile?)      [focus ring; profile strengthens 10-foot]
	-- pointer hover layer (UI-PARADIGM-001, matrix R§7): the renderer calls this
	-- for interactive nodes ONLY when the pointer class is live, so a pure-touch
	-- tree allocates no hover wiring. The adapter wires MouseEnter/MouseLeave to
	-- its hover fill; an adapter without it degrades (no hover preview), never
	-- crashes — nothing essential lives behind hover.
	"enableHover", -- (handle)                        [pointer hover state]
	"setZOrder", -- (handle, z)                      [deterministic paint order]
	"setPointerHandlers", -- (handle, {down,move,up,cancel})  [ADR-0008 capture]
	-- text-entry seam (§17 Phase 5, UI.TextInput): a TextField adapter wires
	-- the engine TextBox to the control's handlers and reports edits/focus back
	-- through them. handlers = { onTextChanged(text), onFocusGained(path),
	-- onFocusLost(reason) } where reason ∈ "enter" | "focusLost" | "cancel".
	-- onFocusGained carries the focused node's FULL PATH: on the real engine a
	-- pointer/touch tap focuses the TextBox natively (setActivateHandler is a
	-- no-op for a non-GuiButton), so the control never sees handleActivate on
	-- that path and learns its path only here — required for keep-visible (F1)
	-- (desktop Escape is engine-reserved, so the adapter reports it as
	-- onFocusLost("cancel") — D1). An adapter without this method degrades to a
	-- read-only field; the CaptureFocus/ReleaseFocus and .Text/.PlaceholderText
	-- writes ride the ordinary setProp path (editing/text/placeholder bindings).
	"setTextInputHandlers", -- (handle, { onTextChanged, onFocusGained, onFocusLost })
	-- native scroll host (native-substrate NS-A2): a scroll node's SOLVED
	-- content extent maps to the engine canvas (CanvasSize); the ENGINE owns
	-- the live offset (physics, bars, momentum) and reports it via
	-- observeScroll; setScrollPosition is the framework's programmatic
	-- keep-visible write. An adapter without these degrades to the clip-only
	-- fallback (content geometry still correct; no user scrolling) — the
	-- renderer feature-detects and never crashes.
	"setScrollRegion", -- (handle, { axis, contentW, contentH } | nil)
	"setScrollPosition", -- (handle, { x, y })
	"observeScroll", -- (handle, fn({x,y})) -> unsubscribe
	-- engine-selection bridge (native-substrate NS-A12): the renderer calls
	-- this ONLY for a surface presented with engineSelectionBridge=true (a
	-- modal). handle=nil clears. Adapters without it degrade to LuauUI's own
	-- focus visual — the bridge is an experiment until physical-pad proof.
	"setEngineSelection", -- (handle | nil)
	-- native drag acquisition (NS-A5): UIDragDetector in CustomOffset mode
	-- (Position authority stays with the renderer). Returns a detach function,
	-- or nil when the engine lacks the class / fallback is forced — consumers
	-- then use setPointerHandlers (the raw capture seam, ADR-0008).
	"setVisible", -- (handle, visible: boolean); hidden subtrees (losing ViewThatFits candidates) must not paint
	"setDragDetector", -- (handle, {onStart,onContinue(pos, totalOffset),onEnd}) -> detach | nil; totalOffset = CUMULATIVE DragUDim2 since DragStart, never a per-frame delta (verifier F5)
	-- native touch gestures (NS-A6): engine-recognized events normalized into
	-- src/input/touch_gestures value objects. Connection-level; firing needs
	-- real touch (physical row NS-P2).
	"setTouchGestureHandlers", -- (handle, onGesture) -> disconnect
	-- engine text premeasurement (text-measurement milestone): the renderer
	-- hands over the WORDS its last solve could not size exactly and takes the
	-- exact widths one re-solve later. Words, not laid-out strings — the key is
	-- (font, size, word), so a resize or a device-profile change costs no new
	-- measurement. May yield internally; it MUST return to the renderer without
	-- yielding and answer through `done`. An adapter without it keeps the
	-- headless estimator's conservative bound, which never under-reserves — the
	-- first frame of an adapter WITH it is that same bound, by design.
	"measureTextWidths", -- (requests: {{font,size,word}}, done({{font,size,word,width?}}, final?))
	-- whole-surface visibility. The presenter's no-pop text gate mounts and
	-- solves a screen with its root hidden and reveals it once the text is
	-- exact, so a player never sees the conservative boxes shrink. An adapter
	-- without it simply is not gateable — the surface shows immediately, which
	-- is today's behaviour and always correct, just occasionally jumpy.
	"setRootVisible", -- (rootHandle, visible: boolean)
}

-- ---------------------------------------------------------------------------
-- FUTURE TARGETS (roadmap Step 4, ADR-0021). DECLARED, NOT IMPLEMENTED.
--
-- A render target is where the solved tree materializes. Two exist:
-- `screen_target` (ScreenGui) and `billboard_target` (BillboardGui). A world
-- surface is the third, and it is written down here — with its unanswered
-- questions attached — for one reason: so that adding it later is a new adapter
-- rather than a change to every control. Nothing below is shipped, and
-- `target_contract.check` does not know about it.
--
-- The questions are the deliverable. Each is something a Studio and physical
-- spike must answer BEFORE an adapter is written, because guessing at any of
-- them produces an adapter that looks correct and is not.
target_contract.FUTURE = table.freeze({
	surface = table.freeze({
		instance = "SurfaceGui",
		status = "not implemented; no adapter, no capability claim",
		presentationSpace = "world",
		playbook = "docs/extending/new-render-target.md + docs/extending/new-platform-mode.md",
		-- ADR-0003 deferred the world target and listed the checklist; these are
		-- the same questions, restated as the spike a future implementer runs
		openQuestions = table.freeze({
			"canvas mapping: pixels-per-stud policy, and whether solved rects map linearly at every part size",
			"adornee lifetime: what the adapter does when the part streams out, is destroyed, or is re-parented mid-interaction",
			"local ownership: the SurfaceGui must be client-owned like every other LuauUI target, never replicated UI",
			"clipping: whether ClipsDescendants and the scroll host behave as they do on a ScreenGui",
			"stylesheets: whether a StyleLink under a SurfaceGui resolves the same rules with the same cascade",
			"pointer coordinates: mouse/touch hit points arrive in surface space, and a spatial ray arrives as world geometry — both must reach the same solver rects",
			"interactivity precondition: a SurfaceGui's GuiObjects are input-active only when the SurfaceGui lives under PlayerGui with Adornee set to the part; parented INTO the part it is display-only. A spike that parents it the wrong way measures a surface that can never be clicked.",
			"focus visuals: whether a focus ring is legible at the distances and angles a world surface is viewed from",
			"occlusion: what a control does when the surface is behind geometry, edge-on, or off-screen",
			"teardown: that destroyRoot releases every instance and connection, as the contract already requires",
			"performance: a world surface renders every frame the part is visible; the cost has to be measured, not assumed",
		}),
	}),
})

function target_contract.check(adapter: any): { missing: { string }, optionalAbsent: { string } }
	local missing = {}
	for _, name in target_contract.REQUIRED do
		if type(adapter[name]) ~= "function" then
			table.insert(missing, name)
		end
	end
	local optionalAbsent = {}
	for _, name in target_contract.OPTIONAL do
		if type(adapter[name]) ~= "function" then
			table.insert(optionalAbsent, name)
		end
	end
	return { missing = missing, optionalAbsent = optionalAbsent }
end

return target_contract

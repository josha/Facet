--!strict
-- RenderTargetAdapter contract (design §13, ADR-0003/ADR-0009): the seam every
-- render target implements. Three lists: REQUIRED (called unconditionally),
-- OPTIONAL (feature-detected with `~= nil`; each absence is one named degrade)
-- and THEME (the five `theme_controller` reaches for — without them a target
-- cannot take a theme package). The lists are the CONTRACT, so a name the
-- framework calls must appear on one of them: nine did not (SEAM-20), which let
-- an adapter pass `check` with `#optionalAbsent == 0` and still ship with no
-- hit-target floor, no wheel scrolling, no display order and no theming at all.
-- Headless conformance
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
	-- ── the five the RENDERER also feature-detects (SEAM-20) ───────────────
	-- They were called and undeclared, which made `check` answer a question
	-- narrower than the seam: an adapter could pass with `#optionalAbsent == 0`
	-- and still silently drop five channels. Each line names what degrades.
	--
	-- WITHOUT IT: no 44 px effective-target floor (src/controls/contract.luau) —
	-- a small control stays exactly as big as it paints, so touch accuracy is
	-- whatever the visual happens to be. Layout is unaffected; only the hit area.
	"setHitRect", -- (handle, rect | nil)
	-- WITHOUT IT: no wheel channel — `onScrollWheel` never fires, so a pointer
	-- user cannot scroll a ScrollView with the wheel (drag/keyboard still work).
	"setScrollHandler", -- (handle, fn(delta: number))
	-- WITHOUT IT: the framework cannot READ the live engine offset, so
	-- keep-visible and scroll-position diagnostics work from the last value the
	-- framework itself wrote rather than where the engine actually is.
	"getScrollPosition", -- (handle) -> { x, y } | nil
	-- WITHOUT IT: native transitions cannot be turned off, so a reduced-motion
	-- environment cannot suppress engine-side animation (LuauUI's own motion
	-- still honours the policy; only the target's native layer is unreachable).
	"setNativeTransitionsEnabled", -- (on: boolean)
	-- WITHOUT IT: no cross-surface paint order — the presenter's base < scrim <
	-- modal ordering cannot reach the engine, so a modal may paint under the
	-- screen it is modal over.
	"setRootDisplayOrder", -- (rootHandle, n: number)
}

-- THEME (ADR-0019 §7). Not "optional" in the OPTIONAL sense: these four are the
-- surface `src/client/theme_controller.luau` reaches for, and a target that
-- lacks them cannot be themed by a package at all —
-- `theme_controller.install` degrades to fallback paint (nativeStyleInfo
-- absent/non-table) and, in native mode, ERRORS unless the caller passes
-- `opts.rootGui` (themeRootGui absent). They are declared as their own list so
-- an adapter author sees "theming" as one capability with one consequence
-- rather than four unrelated names, and so `check` can report it separately
-- from the degrade-quietly optionals.
target_contract.THEME = {
	-- WITHOUT IT: `install` reports fallback with the reason "the adapter does
	-- not report native paint", so the package paints through explicit writes
	-- and no StyleSheet is ever linked.
	"nativeStyleInfo", -- () -> { active: boolean, ... } | nil
	-- WITHOUT IT: native mode has no root to link its sheet at, and `install`
	-- errors naming both this method and `opts.rootGui`.
	"themeRootGui", -- () -> Instance?
	-- WITHOUT IT: the DECORATION half of a package never reaches the target —
	-- chrome recipes, semantic icons and the focus treatment stay unpainted
	-- while metrics still change (a package half-applied).
	"setThemePackage", -- (package?, themeName?, snapshot?) -> chromeChanged: boolean
	-- WITHOUT IT: the controller falls back to the single-root `linkAt` path, so
	-- a root created AFTER the install (a modal) keeps the legacy sheet and
	-- appears Neutral over a themed screen.
	"relinkThemeSheet", -- (sheet: StyleSheet?)
	-- WITHOUT IT: a FALLBACK-paint target never learns the new theme's token
	-- style, so a runtime theme swap changes metrics and leaves every explicit
	-- colour write on the outgoing palette (ADR-0019 §7; theme_controller feature-
	-- detects and calls it on every commit). ScreenTarget does not implement it —
	-- that absence is the degrade this line names, not a defect.
	"setThemeStyle", -- (style: CompiledStyle) -> ()
}

-- ...and exactly one THEME name is a GROWTH seam rather than a prerequisite
-- (ARCH-5). ADR-0019's integration ruling is explicit — the controller "calls
-- `adapter.setThemeStyle(style)` on every commit for ANY TARGET THAT GROWS THE
-- SEAM" — so a target without it is still fully themeable (ScreenTarget is, and
-- is the shipping path); it simply takes its palette at construction. It is
-- declared on THEME because the contract's own rule is that a name the framework
-- calls must appear on a list, and named here so `themeable` keeps meaning "this
-- target can be themed by a package" instead of silently becoming false for every
-- adapter in the tree.
target_contract.THEME_GROWTH = table.freeze({ setThemeStyle = true })

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

-- check(adapter) -> what this adapter does and does not implement.
--   missing         REQUIRED names absent — the renderer calls these
--                   unconditionally, so the target cannot be mounted.
--   optionalAbsent  OPTIONAL names absent — each is one named degrade.
--   themeAbsent     THEME names absent — theming degrades or refuses.
--   themeable       every THEME name present.
-- `missing` and `optionalAbsent` keep their meaning and their names; the theme
-- fields are additive, so existing callers read exactly what they read before.
export type Result = {
	missing: { string },
	optionalAbsent: { string },
	themeAbsent: { string },
	themeGrowthAbsent: { string },
	themeable: boolean,
}

function target_contract.check(adapter: any): Result
	local function absent(names: { string }): { string }
		local out: { string } = {}
		for _, name in names do
			if type(adapter[name]) ~= "function" then
				table.insert(out, name)
			end
		end
		return out
	end
	local themeAbsent: { string } = {}
	local themeGrowthAbsent: { string } = {}
	for _, name in absent(target_contract.THEME) do
		if target_contract.THEME_GROWTH[name] then
			table.insert(themeGrowthAbsent, name)
		else
			table.insert(themeAbsent, name)
		end
	end
	return {
		missing = absent(target_contract.REQUIRED),
		optionalAbsent = absent(target_contract.OPTIONAL),
		themeAbsent = themeAbsent,
		-- declared THEME names this target has not grown; each is a named degrade,
		-- never a theming blocker (see THEME_GROWTH)
		themeGrowthAbsent = themeGrowthAbsent,
		themeable = #themeAbsent == 0,
	}
end

return target_contract

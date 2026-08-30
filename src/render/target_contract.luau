--!strict
-- RenderTargetAdapter contract (design §13, ADR-0003/ADR-0009): the seam every
-- render target implements. Three lists: REQUIRED (called unconditionally),
-- OPTIONAL (feature-detected with `~= nil`; each absence is one named degrade)
-- and THEME (the five `theme_controller` reaches for — without them a target
-- cannot take a theme package). The lists are the CONTRACT, so a name the
-- framework calls must appear on one of them: nine did not, which let
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
-- lists. A target that silently ignores a written prop is the defect class that is green headless and dead on the device
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
	-- full-value disclosure engagement zones (Step 8.5): the renderer
	-- calls this for a `disclose` text node, per input class that is live
	-- (hover half on pointer, long-press half on touch; calls MERGE per half so
	-- a class arriving mid-session retrofits the missing half). WITHOUT IT: no
	-- pointer-dwell or touch-long-press engagement — focus-driven disclosure
	-- still works through the presenter, so the full value stays reachable on
	-- keyboard/gamepad; pointer/touch reachability degrades to focus.
	"enableDisclosure", -- (handle, { hover?, longPress? })
	-- scroll indicator policy (director ruling 2026-08-09; its reserve half
	-- REVERSED 2026-08-12): the presenter pushes the environment's derived policy
	-- ("always" on pointer sessions, "auto" on touch/gamepad) plus the
	-- reduced-motion fact, and the adapter drives the indicator lifecycle from it
	-- (flash on first overflow, show while scrolling, fade when idle; reduced
	-- motion never fades). It decides PAINT only: `scrollBarThickness` is the same
	-- under both policies, because the engine charges a ScrollingFrame's window
	-- for its bar instance however the bar is painted (see
	-- src/client/screen_target.luau SCROLL_BAR_THICKNESS for the measured defect).
	-- WITHOUT IT: the constant persistent bar — the pre-policy behavior, degraded
	-- by name; the reserve is unaffected either way.
	"setScrollIndicatorPolicy", -- (policy: "always"|"auto", reduced: boolean?)
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
	-- native scroll host (the native substrate): a scroll node's SOLVED
	-- content extent maps to the engine canvas (CanvasSize); the ENGINE owns
	-- the live offset (physics, bars, momentum) and reports it via
	-- observeScroll; setScrollPosition is the framework's programmatic
	-- keep-visible write. An adapter without these degrades to the clip-only
	-- fallback (content geometry still correct; no user scrolling) — the
	-- renderer feature-detects and never crashes.
	"setScrollRegion", -- (handle, { axis, contentW, contentH } | nil)
	"setScrollPosition", -- (handle, { x, y })
	"observeScroll", -- (handle, fn({x,y})) -> unsubscribe
	-- engine-selection bridge (the native substrate): the renderer calls
	-- this ONLY for a surface presented with engineSelectionBridge=true (a
	-- modal). handle=nil clears. Adapters without it degrade to Facet's own
	-- focus visual — the bridge is an experiment until physical-pad proof.
	"setEngineSelection", -- (handle | nil)
	-- native drag acquisition: UIDragDetector in CustomOffset mode
	-- (Position authority stays with the renderer). Returns a detach function,
	-- or nil when the engine lacks the class / fallback is forced — consumers
	-- then use setPointerHandlers (the raw capture seam, ADR-0008).
	"setVisible", -- (handle, visible: boolean); hidden subtrees (losing ViewThatFits candidates) must not paint
	"setDragDetector", -- (handle, {onStart,onContinue(pos, totalOffset),onEnd}) -> detach | nil; totalOffset = CUMULATIVE DragUDim2 since DragStart, never a per-frame delta (verifier F5)
	-- native touch gestures: engine-recognized events normalized into
	-- src/input/touch_gestures value objects. Connection-level; firing needs
	-- real touch (physical row the native substrate).
	"setTouchGestureHandlers", -- (handle, onGesture) -> disconnect
	-- the pointer's SECONDARY button (navigation-and-menus D2): the trigger half
	-- of the context-menu construct on a mouse. The primary button is already the semantic
	-- Activate (`setActivateHandler`), and a right-click is a DIFFERENT verb, so
	-- it needs its own channel rather than a meta flag on the same one. It
	-- OBSERVES, exactly as the disclosure zones do — the node underneath keeps
	-- whatever it already did with the primary button. WITHOUT IT: no right-click
	-- menu; every other Menu trigger (activate, long-press, gamepad, keyboard)
	-- still opens it, which is why this is optional and not a dependency.
	"setSecondaryActivate", -- (handle, fn()) -> disconnect
	-- engine text premeasurement (text-measurement milestone): the renderer
	-- hands over the WORDS its last solve could not size exactly and takes the
	-- exact widths one re-solve later. Words, not laid-out strings — the key is
	-- (font, size, word), so a resize or a device-profile change costs no new
	-- measurement. May yield internally; it MUST return to the renderer without
	-- yielding and answer through `done`. An adapter without it keeps the
	-- headless estimator's conservative bound, which never under-reserves — the
	-- first frame of an adapter WITH it is that same bound, by design.
	--
	-- MAY RETURN A CANCEL FUNCTION. An adapter that can answer LATE —
	-- the Roblox one answers a boot-window batch twice, up to ~12 s apart —
	-- returns a nullary function the renderer calls on dispose, after which the
	-- adapter must not invoke `done` again. Optional: returning nothing keeps the
	-- previous contract exactly, and the renderer's `disposed` guard still stands
	-- behind it. It cancels the DELIVERY, never an engine read already in flight.
	"measureTextWidths", -- (requests: {{font,size,word}}, done({{font,size,word,width?}}, final?)) -> (() -> ())?
	-- whole-surface visibility. The presenter's no-pop text gate mounts and
	-- solves a screen with its root hidden and reveals it once the text is
	-- exact, so a player never sees the conservative boxes shrink. An adapter
	-- without it simply is not gateable — the surface shows immediately, which
	-- is today's behaviour and always correct, just occasionally jumpy.
	"setRootVisible", -- (rootHandle, visible: boolean)
	-- ── the five the RENDERER also feature-detects ───────────────
	-- They were called and undeclared, which made `check` answer a question
	-- narrower than the seam: an adapter could pass with `#optionalAbsent == 0`
	-- and still silently drop five channels. Each line names what degrades.
	--
	-- WITHOUT IT: no 44 px effective-target floor (src/class_contract.luau) —
	-- a small control stays exactly as big as it paints, so touch accuracy is
	-- whatever the visual happens to be. Layout is unaffected; only the hit area.
	"setHitRect", -- (handle, rect | nil)
	--[[ THE PER-CONTROL SENSORY DECLARATION (director request 2026-08-13). The
		verb `UI.sensoryFeedback(bp, { activation = … })` resolved onto this node,
		or nil for "nothing was declared anywhere above me". Pushed only for the
		classes that can actually be ACTIVATED, and pushed on every create/adopt —
		including the nil — because instance recycling would otherwise let a
		commit button hand its sensation to whatever control adopts its object next.

		IT IS A FACT, NOT A COMMAND. The renderer never asks the adapter to play
		anything; it publishes what the author declared so an engine-side consumer
		(the opt-in client haptics adapter, which turns it into the button's own
		press-effect property) can. `src/present/feedback.luau:4-5` — Facet plays
		nothing — is why this is a property write and not a `play` seam. The engine
		symbols are named only in `src/client/`, a boundary tests/haptics.spec.luau
		enforces by scanning every file outside it.

		WITHOUT IT: the bus still carries the declared verb, so a game's own
		subscriber is unaffected; what is lost is the ENGINE press route being able
		to distinguish one control's sensation from another's, and every button
		falls back to the one generic press effect. ]]
	"setActivationFeedback", -- (handle, verb: string | nil)
	-- WITHOUT IT: no wheel channel — `onScrollWheel` never fires, so a pointer
	-- user cannot scroll a ScrollView with the wheel (drag/keyboard still work).
	"setScrollHandler", -- (handle, fn(delta: number))
	-- WITHOUT IT: the framework cannot READ the live engine offset, so
	-- keep-visible and scroll-position diagnostics work from the last value the
	-- framework itself wrote rather than where the engine actually is.
	"getScrollPosition", -- (handle) -> { x, y } | nil
	-- WITHOUT IT: the target's NATIVE (StyleSheet-owned) transitions cannot be
	-- turned off, so a reduced-motion environment cannot suppress engine-side
	-- sheet animation. This is the SHEET half only — a target's own bespoke
	-- tweens ride `setReducedMotion` below.
	"setNativeTransitionsEnabled", -- (on: boolean)
	--[[ THE BESPOKE half of the same fact (C1, 2026-08-12). WITHOUT IT: a
		target's own tweens — the press dip, the state-paint fades, the fill
		crossfade — never learn that the player asked for reduced motion, so an
		accessibility preference silently does nothing.

		It is a PUSH, deliberately, and this is the whole point of the seam. The
		fact used to reach `screen_target` only through a construction-time
		`opts.isReducedMotion` closure, which every one of its four production
		call sites (the showcase and three RascalRally GUIs) forgot to pass — a
		design that four callers forget is a design that invites forgetting. The
		renderer already observes the env fact for `setNativeTransitionsEnabled`;
		this rides the same observation, so an adapter gets the fact with zero
		consumer wiring and keeps getting it when the player flips the setting
		mid-session.
	]]
	"setReducedMotion", -- (reduced: boolean)
	--[[ THE PLAYER'S BACKGROUND TRANSPARENCY PREFERENCE (ADR-0035, owed row O-26).
		WITHOUT IT: a player who set Background Transparency to "opaque" still sees a
		see-through modal backdrop, because the framework's one partial background is
		painted by the target and only the target can move it. The value is
		`effectiveTransparency` — already clamped to 0..1 by the env memo, 1 meaning
		"paint what the theme declared" — and the renderer pushes it at attach and on
		every change, so an adapter gets it with zero consumer wiring. It is the ONE
		optional seam on this list that must REPAINT rather than remember: the
		backdrop is on screen when the setting moves. ]]
	"setPreferredTransparency", -- (effective: number)
	-- THE ENGINE-CONTENT SEAM (UI.Stage, ViewportFrame adoption 2026-08-08). Answers
	-- a per-node handle for a mounted `Stage`: `setCamera{ position, lookAt, fov? }`,
	-- `setLighting{ ambient?, lightColor?, lightDirection? }` and `contentRoot()`.
	-- The boundary is engine-type-free (plain {x,y,z} / {r,g,b} tables) — converting
	-- to CFrame/Color3/Vector3 is the adapter's job, which is what keeps the leaf
	-- itself engine-free. CONTENT IS CALLER-OWNED: the handle hands back a root to
	-- parent models into, and Facet owns the box, the lifecycle, the camera and the
	-- lighting writes. WITHOUT IT: `controller.stageHost(path)` answers nil, so a
	-- Stage is an empty reserved box — authors gate on the nil or present a fallback
	-- plate. `billboard_target` deliberately does not offer it (its canvas story is
	-- unproven), and neither does an engine without ViewportFrame/WorldModel.
	"stageHost", -- (handle) -> { setCamera, setLighting, contentRoot } | nil
	-- THE FOREIGN-CONTENT SEAM (UI.Foreign, ADR-0034). Answers a per-node handle
	-- for a mounted `Foreign` with ONE verb: `adopt(instance)`, which runs the pure
	-- refusal ladder (`src/render/foreign_content.luau`) and then makes the single
	-- claim the framework declares over content it does not own — the instance's
	-- `Parent`, gated by `authority.assertWrite("Foreign", "Parent", "host")`.
	-- There is deliberately NO `contentRoot()` here, unlike `stageHost`: handing
	-- back the container would hand back a framework-owned GuiObject, which is
	-- exactly the writable-handle hole `fusion-comparison.md` §5's `Ref` defers.
	-- WITHOUT IT: `controller.foreignHost(path)` answers nil, so a Foreign is an
	-- empty reserved box — authors gate on the nil and present a fallback plate.
	-- `billboard_target` deliberately does not offer it (same unproven canvas
	-- story that keeps `stageHost` off it).
	"foreignHost", -- (handle) -> { adopt } | nil
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
-- ADR-0019's integration ruling is explicit — the controller "calls
-- `adapter.setThemeStyle(style)` on every commit for ANY TARGET THAT GROWS THE
-- SEAM" — so a target without it is still fully themeable (ScreenTarget is, and
-- is the shipping path); it simply takes its palette at construction. It is
-- declared on THEME because the contract's own rule is that a name the framework
-- calls must appear on a list, and named here so `themeable` keeps meaning "this
-- target can be themed by a package" instead of silently becoming false for every
-- adapter in the tree.
target_contract.THEME_GROWTH = table.freeze({ setThemeStyle = true })

-- ---------------------------------------------------------------------------
-- THE WORLD SURFACE: the questions, and which of them are now answered.
--
-- A render target is where the solved tree materializes. THREE exist:
-- `screen_target` (ScreenGui), `billboard_target` (BillboardGui) and — since
-- 2026-08-29, ADR-0063 — `surface_target` (SurfaceGui).
--
-- This block was written when the third was future, and it stays here rather
-- than being deleted, because the questions were the deliverable and where the
-- next implementer looks for them is exactly where the ANSWERS belong. Each was
-- something a Studio spike had to settle BEFORE an adapter was written, on the
-- grounds that guessing at any of them produces an adapter that looks correct
-- and is not. Two of them turned out to be wrong in this file, which is the best
-- possible argument for having written them down.
--
-- The spike record is
-- artifacts/example-games-and-standalones/spike/world-surface.md; the adapter
-- carries each answer beside the option it decides.
target_contract.FUTURE = table.freeze({
	surface = table.freeze({
		instance = "SurfaceGui",
		status = "SHIPPED 2026-08-29 (ADR-0063) — src/client/surface_target.luau",
		presentationSpace = "world",
		playbook = "docs/extending/new-render-target.md + docs/extending/new-platform-mode.md",
		--[[ ANSWERED BY THE SPIKE. Two of these corrected this file's own premises,
			and both corrections matter to anyone reading it next. ]]
		answered = table.freeze({
			"canvas mapping: SizingMode = FixedSize gives a canvas INVARIANT to the part — 8x5, 4x2.5, 16x10 and 8x2 studs all reported the same 400x250 — and descendants read in canvas pixels, so the solver is handed one exact rect and a part resize costs no re-solve",
			"interactivity precondition: WRONG AS ORIGINALLY WRITTEN. A SurfaceGui parented INTO the part is NOT display-only on Studio 0.736 — both topologies took input (activated=1, inputBegan=2 each). PlayerGui + Adornee is still required, on OWNERSHIP grounds: a SurfaceGui inside a Workspace part replicates to every player, and shared UI is what Facet must never build",
			"local ownership: unchanged and now load-bearing — it is the whole reason for the topology above",
			"the queryable precondition (not originally listed): CanQuery = false renders the surface at full size and receives nothing, with no error — activation went 1 -> 0 -> 1 as the flag was cleared and restored",
			"occlusion: geometry in front blocks input with AlwaysOnTop = false, and DOES NOT with it true — a player would operate the terminal through a wall, which is why the adapter pins it false and does not offer the option",
			"a live surface SINKS the world input under it: a ClickDetector on the same part fired while the surfaces were inert and zero times once they were live",
			"adornee lifetime: a destroyed part is INVISIBLE through .Adornee, which still names it with the canvas size unchanged — the adapter watches the instance's own lifetime and reports through onAdorneeLost",
			"clipping: a child overflowing the canvas still reports its full AbsoluteSize, so clipping is a paint fact and the solver's overflow diagnostics keep meaning what they mean, exactly as on a ScreenGui",
			"text measurement: TextService takes no target, so there is no per-target text question — GetTextBoundsAsync answered identically",
		}),
		--[[ STILL OPEN. Each is here because nothing has measured it, not because
			nobody thought of it; the adapter withholds the matching capability by
			name rather than shipping an unproven one. ]]
		openQuestions = table.freeze({
			"stylesheets: whether a StyleLink under a SurfaceGui resolves the same rules with the same cascade — the spike could not close this, because its hand-built StyleRule failed to apply on the SCREEN control too and a shared null proves nothing. It closes with native_style itself driven on a surface; until then the adapter passes nativeStyle = false",
			"pointer coordinates: activation reaches a surface control, but what coordinates a CAPTURE carries is unmeasured — and on a SurfaceGui the ScreenGui inset correction is not merely wrong, it is the wrong KIND of correction. setPointerHandlers and setTouchGestureHandlers are withheld until a mapping is measured",
			"the native scroll host: a scripted CanvasPosition write took, but a wheel, a drag and a touch flick are what a consumer gets and none has been driven. forceScrollFallback stays true",
			"focus visuals: whether a focus ring is legible at the distances and angles a world surface is viewed from",
			"engine content: a ViewportFrame (UI.Stage) or a caller's own GuiObject (UI.Foreign) inside a canvas that is itself a world surface is a composition nobody has looked at. Both hosts are withheld",
			"performance: a world surface renders every frame the part is visible; the cost has to be measured against the same scene at idle, not assumed",
			"retail client: every answer above is Studio Play with an injected pointer. The real client remains a named device row",
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

# Release-candidate Roblox-platform review (fresh-context verifier, 2026-08-17)

Reviewed at commit b230b87. Stored verbatim by the controller from the
verifier's returned report (stub could not write files).

[PLATFORM-REVIEW]: CONCERNS

PLAT-1 | High | High | src/client/roblox_env.luau:226-239 | OSK occlusion connection never made: `false and X or nil` short-circuits at bind; `table.insert(t,nil)` is a silent no-op, so keyboardOcclusionRect stays nil forever.
PLAT-2 | High | High | src/client/roblox_env.luau:17,180 | `workspace.CurrentCamera` captured once at bind; a replaced CurrentCamera orphans the ViewportSize connection and viewportRect stops updating for the session.
PLAT-3 | High | Medium | src/client/roblox_env.luau:31-58 vs src/env/environment.luau:354 | Stale-inset/new-viewport race belted only for topbarSafeInsets; core/deviceSafeInsets can publish a huge bogus bottom/right inset after rotation.
PLAT-4 | Medium | High | src/client/screen_pointer.luau:445-449, src/client/screen_target.luau:3898 | `disposeGlobals` unconditionally disconnects the adapter-wide GuiService.MenuOpened conn on ANY destroyRoot; drag-abort-on-menu dies session-wide.
PLAT-5 | Medium | High | src/client/screen_pointer.luau:56-59,445 | `applyCursor` writes `UserInputService.MouseIcon = ""` on every hint clear and on teardown, silently stomping a host game's custom cursor (CURSOR_ART is empty).
PLAT-6 | Medium | High | src/client/screen_pointer.luau:338,356 | Pointer capture's global InputChanged/InputEnded do not filter to the originating touch InputObject, so a second finger drives and ends another finger's drag.
PLAT-7 | Medium | High | src/replication/adapters.luau:112-124 | A lost (not thrown) resnapshot reply wedges the collection permanently: awaitingResnapshot latches, every later patch returns "gap", no retry or timeout exists.
PLAT-8 | Medium | High | src/client/screen_target.luau:2480-2509, 3876-3950 | destroyRoot never clears the engine-selection bridge, leaving GuiService.SelectedObject pointing into a destroyed tree.
PLAT-9 | Medium | High | src/client/native_style.luau:352-390,448-453 | Stamp-matching existing sheet path never backfills a missing "Theme <name>" child sheet, so a designer-deleted theme hard-errors mount via setTheme's assert.
PLAT-10 | Medium | Medium | src/client/native_style.luau:48 | `DEFAULT_ENABLED = false` ships native StyleSheet paint OFF by default; theme packages requiring the `nativeStyleSheets` capability then fail to install on a default target.
PLAT-11 | Medium | Medium | src/client/roblox_input.luau:18 | `Players.LocalPlayer:WaitForChild("PlayerScripts")` is unbounded and unguarded, unlike gamepad_contention.luau:285 which bounds the identical pattern after a live hang.
PLAT-12 | Medium | Medium | src/client/text_premeasure.luau:328-358 | `measure` re-invokes `done` up to ~12s later with no disposal/cancellation token; a torn-down renderer is called back after teardown.
PLAT-13 | Low | Medium | src/client/roblox_input.luau:300-337 | `bindAxis` companion Direction2D actions are named per-component under one context; duplicate binds collide and the thumbstick binding sinks on a sinking context.
PLAT-14 | Low | Medium | src/client/roblox_input.luau:368-387 | preferredBinding only maps `left` for modifier-gated bindings, so an engine PreferredBinding resolving to the RightShift instance falls through to the heuristic.
PLAT-15 | Low | High | src/client/roblox_input.luau:10 | Comment claims `InputAction:Fire()/GetState()` are deprecated; only Fire is marked deprecated (https://create.roblox.com/docs/reference/engine/classes/InputAction).
PLAT-16 | Low | High | src/client/roblox_input.luau:276-287 | "documented analog surface … create.roblox.com/docs/input/input-action-system" — that page contains no Thumbstick1/Direction1D-vs-2D statement; claim is measured, not documented.
PLAT-17 | Low | Medium | src/client/screen_target.luau:1000-1013 | ScreenGui sets legacy IgnoreGuiInset but never ScreenInsets/SafeAreaCompatibility (default FullscreenExtension); notched-device interaction unproven (docs/reference/engine/classes/ScreenGui).
PLAT-18 | Low | Medium | src/client/roblox_env.luau:141-159 | `GetTextSizeOffsetAsync` is documented as a label-HEIGHT offset but is used as an additive TextSize delta (https://create.roblox.com/docs/reference/engine/classes/TextService).
PLAT-19 | Low | Medium | src/client/roblox_env.luau:46-51 | GetInsetArea-absent fallback uses `topInset.X` as a LEFT safe inset and `bottomInset.Y` as a bottom inset; neither is a safe-area edge (dead path today).
PLAT-20 | Low | Medium | src/client/text_premeasure.luau:151-164 | `boundsWidth` allocates a `GetTextBoundsParams` Instance per measured word and never Destroys it; reuse one per batch.
PLAT-21 | Low | Medium | src/client/gamepad_contention.luau:293-296 | UnbindAction on an unbound action only warns, so `disableLegacyControls` returns true on any live client even when nothing was freed.
PLAT-22 | Low | Medium | src/client/responder_effects.luau:53-73 | TouchControlsEnabled suppression is not refcounted and pcall-success is treated as "the write landed"; a second binder captures the suppressed value as prior.
PLAT-23 | Low | High | src/client/native_style.luau:10-11 | Header still documents `<host>.Facet` / `<host>.Facet["Theme <name>"]` while the code writes `FacetStyle` / `FacetTheme <id>` — stale post-rename comment.
PLAT-24 | Low | Medium | src/client/native_style.luau:288-301 | A stale (wrong-schema) sheet found in ReplicatedStorage is discarded by the second lookup and never destroyed when the PlayerGui lookup succeeds.
PLAT-25 | Low | Low | src/replication/adapters.luau:130 | `patch.remove` is read only as an array; a set-shaped `remove` silently removes nothing.
PLAT-26 | Low | Low | src/client/roblox_resources.luau:41 | PreloadAsync is passed content strings; the typed signature is `{any}` but every official sample passes Instances (docs/reference/engine/classes/ContentProvider).

Verified clean: client/server topology (no shared module requires src/client/*; engine globals only under src/client/), insetsFromArea math vs the recorded desktop spike, InputBinding:Fire/PrimaryModifier/UIButton and InputAction.PreferredBinding existence, HapticEffectType members and GuiButton.Press/HoverHapticEffect, StyleSheet Priority-pinned cascade, ZIndexBehavior=Sibling on both root factories, IgnoreGuiInset inset-add in pointer/drag paths. Suite green at 6188 via tools/suite_transcript.sh. Not run: gate.sh/perf.sh (prohibited), Studio/device (controller owns the session) — PLAT-3, PLAT-6, PLAT-17 need a physical/rotating touch device to confirm.

Counts: Blocker 0 | High 3 | Medium 9 | Low 14 (26 total).

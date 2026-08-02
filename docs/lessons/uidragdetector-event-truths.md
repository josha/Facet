# UIDragDetector event truths (live-measured 2026-07-23, Studio 0.731)

- **DragStart/DragContinue/DragEnd pass a `Vector2`**, not the `UDim2` a reader
  might infer from `DragUDim2`. Indexing `.X.Offset` on it throws
  "attempt to index number with 'Offset'" — and because DragContinue fires every
  frame of a drag, the error spams and the wired handlers effectively go dead.
- **The position needs NO inset correction under LuauUI roots** (`IgnoreGuiInset
  = true`): measured window-space coordinates match solver rects directly. Do not
  blanket-add `GetGuiInset` the way the raw pointer seam must
  (`engine-input-truths-phaseb.md` §1) — the two seams differ. (Official docs
  call the value "screen space"; the m3 spike under a default-inset gui echoed
  the inset-subtracted injection coords exactly. For LuauUI's roots the two
  descriptions coincide; do NOT generalize the default-inset behavior to other
  gui configurations without a fresh spike — platform verifier F7.)
- `DragUDim2` IS a `UDim2` (cumulative drag delta in offsets) and works as
  documented with `ResponseStyle = CustomOffset`.
- Default `ResponseStyle = Offset` makes the DETECTOR write `GuiObject.Position`
  (measured in spike m3) — always use `CustomOffset`/`Scriptable` under LuauUI so
  the renderer keeps Position authority.
- `Enabled = false` mid-drag fires `DragEnd` immediately (usable cancellation).
- **The detector CONSUMES the click** (measured live 2026-07-27, sponsor-framework-gaps):
  a `UIDragDetector` on a GuiButton suppresses `.Activated` entirely — a plain tap on
  a draggable Button did NOTHING on device, while the headless suite stayed green
  because the fake detector mirror preserved the native tap. The framework rule that
  closed it: `drag_registry.pointerUp` answers `"tap"` for a release under the
  promotion token, and the renderer's detector wiring dispatches that tap through the
  SAME `onNodeTap` path a native tap takes (gated on `TAPPABLE` classes, so parity
  with the native path is exact). The raw-capture path still relies on the native
  `Activated` — only detector acquisition dispatches, so nothing double-fires.
  Regression: `tests/presenter_drag_integration.spec.luau` "detector taps are never
  eaten". Found by a REAL injected click (`user_mouse_input` on the instance path)
  against a fixture counter — the class of defect only live input finds.

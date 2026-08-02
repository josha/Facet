# Studio spike results (2026-07-19): IAS, property authority, engine fidelity

Run live in Roblox Studio (Play Solo) via the Studio MCP; full machine-readable
evidence in `artifacts/studio/*.json`. Studio timings are derated proxies —
device measurements stay authoritative (design §14.3).

## Input Action System (UI-INPUT-001..004) — artifacts/studio/ias-spike.json

- API surface confirmed: contexts default `Enabled=true Priority=1000 Sink=false`; action types include `Direction3D`; binding types are `Automatic | Scriptable`.
- **`InputBinding:Fire()` requires `Type = Scriptable`** — exact engine error confirmed: `InputBinding:Fire() can only be called when Type is Scriptable`.
- Real key events respect priority + Sink (high-priority sink context blocks lower context on the same KeyCode; disabling it releases the key).
- **Design §9.2 correction (the spike's key finding): scriptable `Fire()` BYPASSES context arbitration.** Firing a low-priority context's scriptable binding while a higher-priority Sink context was enabled still drove the low action. A scriptable binding pushes state into ITS action directly.
  - **Adopted fallback (documented, recoverable):** the test harness uses scriptable bindings for action-level traces (typed state, dedup, enable/disable, disposal) — same pipeline from binding to action — and validates cross-context priority/sinking with real or MCP-injected key events (`user_keyboard_input`) at phase gates. UI-INPUT-003 is satisfied by this split; no control-level bypass is ever used.
- Context `Destroy()` disconnects everything it owns: post-destroy `Fire()` is a silent no-op.
- `PreferredBinding` reads (nil in a keyboard Studio session with only key bindings); Phase 1 hint derivation must tolerate nil and fall back to `UserInputService.PreferredInput`.

## ScreenGui/StyleSheet property authority (UI-STYLE-001) — artifacts/studio/property-authority-spike.json

- An explicitly-set instance property **silently and permanently defeats** a StyleRule for that property, and style application fires **no** `GetPropertyChangedSignal` and does not change property reads.
- Consequence: the engine will not police authority conflicts; LuauUI's property-authority manifest (one authority per engine property, conflicts are debug errors — design §7.3) must be enforced in the framework. Validated as buildable: authority checks live where writes are issued (the renderer), which is the only writer.

## Engine fidelity differential (UI-FID-001) — artifacts/studio/engine-fidelity.json

- The settings-phone dump (artifacts/render/settings-phone-portrait.json) applied as real instances matched **exactly** on every rect (AbsoluteSize/relative AbsolutePosition), and every TextLabel's `TextBounds` fit inside its reserved rect.
- Text calibration table captured (headless vs `GetTextBoundsAsync`, BuilderSans): engine line height = 1.0×fontSize (headless assumes 1.2); engine glyphs narrower than the 0.62 em average. Headless over-reserves height 1.21–2.44× — conservative in every measured case, per the §7.4 contract.
- Declared tolerance: headless = conservative screening bound; exact-fit is engine-only; Phase 1's premeasurement queue supplies engine numbers through ready/pending/failed.

# PreferredInput / gamepad platform research (2026-07-21)

Commissioned during the input-paradigms expansion to root-cause the example-02
live defect (physical gamepad, no Edit button). Produced by the
roblox-platform verifier (bounded WebSearch/WebFetch research); persisted
verbatim below. Consumed by ADR-0015 and the defect disposition in
`artifacts/input-paradigms/`.

---

## VERDICT: Facts established. The live defect is explained by a documented Studio/macOS platform limitation, not a Facet logic bug.

The most load-bearing finding: on macOS Roblox Studio playtests, a physical HID gamepad is frequently NOT forwarded to the Studio VM at all (`GamepadEnabled == false`, `GetConnectedGamepads()` empty). If the engine never sees a gamepad, `PreferredInput` cannot flip to `Gamepad` — matching the live observation exactly. This is independent of, and upstream of, the separate (now-fixed) "connect vs first-input" quirk.

---

### 1. Documented semantics of `Enum.PreferredInput` / `UserInputService.PreferredInput`

- **Property is read-only**; reports the primary input type from device capability + most recent interaction. Three enum values only: `KeyboardAndMouse` (0), `Gamepad` (1), `Touch` (2). Confidence: high.
  - Enum yaml quotes: Gamepad = "The player has connected or most recently interacted with a gamepad." KeyboardAndMouse analogous. Touch = "device has touch capability and no other input method is available or was recently interacted with."
  - Source: https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/enums/PreferredInput.yaml ; https://create.roblox.com/docs/reference/engine/classes/UserInputService
- **When it becomes Gamepad (documented intent):** on gamepad *connect* OR most-recent interaction. The docs assert connect alone should suffice. Confidence: high (doc text), but see finding 2 — the connect path was actually broken until Aug 2025.
- **Persistence:** "PreferredInput remembers the player's last configuration when they start the client" (persists across sessions). Full release **June 17, 2025** (previously client beta). Recommended read pattern is exactly what Facet uses: `UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(...)`. Confidence: high.
  - Source: https://devforum.roblox.com/t/full-release-introducing-preferredinput-and-improved-touch-capabilities/3750890

### 2. Known bugs/quirks on the PreferredInput property itself

- **"PreferredInput does not update when gamepad is connected"** — Engine Bugs, reported **2025-06-18**. Symptom: property only flips to `Gamepad` after the user *presses a button / moves a stick*, NOT on connect (contradicting docs). Also reported: did not update on mouse *movement*, only on click. Physical gamepad explicitly. Staff `crypto_mancer` **2025-08-20**: "This has been fixed now." Status: fixed. Confidence: high.
  - Source: https://devforum.roblox.com/t/preferredinput-does-not-update-when-gamepad-is-connected/3754247
- **Implication for the live repro:** even post-fix, the fix presumes the engine *sees* the gamepad. In Studio-on-macOS where the pad is not forwarded (finding 3), neither connect nor first-input can flip the value. No DevForum thread was found asserting PreferredInput itself is Studio/macOS-broken *given a detected pad*; the failure is upstream at detection. Confidence: high that the property is not the fault; medium that no residual Studio-only PreferredInput bug exists (absence-of-evidence).

### 3. `GamepadEnabled` / `GetConnectedGamepads` in Studio with a physical controller on macOS

- **Documented, long-standing Studio bug:** physical gamepads fail to be detected in Studio playtests; `UserInputService.GamepadEnabled` returns `false` and `GetConnectedGamepads()` returns empty, while the same controller works in the retail client. Spans Windows 11 and macOS (incl. M2 Apple Silicon), reports **June 2023 → Feb 2025**, controllers affected: Xbox One/Series, DualShock/DualSense, Switch Pro. Confidence: high.
  - Staff (Mar 2024): could not reproduce on production Studio; note SDL-based gamepad support.
  - Root cause surfaced (Feb 2025): the **Virtual Gamepad / Controller Emulator beta occupies the Gamepad1 slot**, pushing a physical pad to slots 2–3 (so `Gamepad1`-keyed logic and character movement silently break even when detection nominally works).
  - Source: https://devforum.roblox.com/t/gamepads-do-not-work-in-studio-playtests-xbox-emulation-leaves-glitched-ui-on-screen/2434925 ; corroborating: https://devforum.roblox.com/t/ps4-gamepad-not-working-with-roblox-on-mac/454882
- **Net:** In Studio on macOS you cannot rely on a physical HID pad being visible to the engine. Two failure modes stack: (a) pad not forwarded at all → `GamepadEnabled=false`; (b) Controller Emulator enabled → physical pad shunted off `Gamepad1`. Either yields "no gamepad affordance." Confidence: high.

### 4. Recommended engine-truth pattern for "gamepad UX now"

- Official gamepad docs recommend **`PreferredInput`** as the *primary* method for deciding cross-platform UI affordances; `GamepadEnabled` + `GamepadConnected`/`GamepadDisconnected` events are named as *secondary alternatives*. So Facet's choice of `PreferredInput` is the doc-endorsed approach. Confidence: high.
  - Source: https://create.roblox.com/docs/input/gamepad
- Docs do NOT recommend `LastInputTypeChanged` for the presentation decision (it is lower-level, raw `UserInputType`); `PreferredInput` is the higher-level, capability-aware, persistence-aware signal that supersedes hand-rolled `LastInputTypeChanged` heuristics. Confidence: medium-high (docs present PreferredInput as the successor pattern; no doc explicitly deprecates LastInputTypeChanged for this).
  - **Design note:** keying purely off `PreferredInput` is correct per docs, but it inherits the Studio-detection gap. A defensive fallback (e.g. also flip the affordance on any `Gamepad*` `UserInputType` seen via `InputBegan`/`LastInputTypeChanged`, or on `GamepadEnabled`) lets the affordance appear in retail-client edge cases where connect-signal timing lags — but will NOT help in Studio-macOS where the pad is invisible. This is a correctness-vs-testability tradeoff, not a spec violation.

### 5. `GuiService.ViewportDisplaySize` + overscan (console 10-foot)

- **API surface confirmed:** `GuiService.ViewportDisplaySize`, read-only, returns `Enum.DisplaySize`. Values: `Small` (tablet/mobile/handheld), `Medium` (laptops/monitors), `Large` (most TVs or larger). Change signal: `GuiService:GetPropertyChangedSignal("ViewportDisplaySize")`. Confidence: high.
  - Availability timeline: **Studio Beta 2025-08-14; Client Beta 2025-09-26; Full Release 2025-10-21.** So it IS available in Studio (beta then GA) as of the 2026-07-21 session. Confidence: high.
  - Mechanism: derived from vendor API physical screen size (inches); mirroring uses main screen, docking uses the external TV. Staff caveat: "This API should not be used to make decisions about rendering quality." Confidence: high.
  - Sources: https://devforum.roblox.com/t/full-release-build-cross-platform-ui-with-the-viewportdisplaysize-api/3880384 ; https://create.roblox.com/docs/production/publishing/console-guidelines
- **Overscan / TV-safe guidance:** Console guidelines instruct placing UI inside "TV-safe areas" keyed off `ViewportDisplaySize == Large`, because some TVs clip edges. The guidelines give a *qualitative* illustration (TV-unsafe zone) but the fetched page did **not** state an exact safe-margin percentage. Industry/10-foot norm is ~10% overscan (≈90% action-safe / ~5% title-safe); no Roblox-published numeric margin was confirmed from these sources. Confidence: high on the qualitative guidance; low/unverified on any Roblox-specified percentage.
  - The fetched docs did not tie ViewportDisplaySize to `GuiService:GetGuiInset()`/`TopbarInset`; overscan margins appear to be developer-authored, not returned by an inset API. Confidence: medium (absence in fetched excerpt; not exhaustively searched).

---

### Physically UNVERIFIABLE in Studio (macOS, synthetic drive)
1. **Real `PreferredInput == Gamepad` flip from a physical pad** — blocked because Studio-macOS does not reliably forward HID gamepads (`GamepadEnabled=false`/empty `GetConnectedGamepads`), and `VirtualInputManager:HandleGamepadConnect` is RobloxScript-capability-gated (verified live 2026-07-21), while `SendKeyEvent` with gamepad KeyCodes arrives as `UserInputType.Keyboard` (verified live 2026-07-21). Net: the Gamepad branch of PreferredInput is not exercisable synthetically in this environment.
2. **The Controller-Emulator slot-shift interaction** (emulator on Gamepad1) — cannot be exercised without the beta emulator engaged; would itself perturb results.
3. **Actual TV overscan clipping / true `DisplaySize.Large` from a real TV vendor API** — Studio can emulate device *resolution* but the value is derived from physical-inches vendor APIs on real hardware; a real console/TV is needed to confirm `Large` selection and true overscan margins.
4. **Whether the Aug-2025 connect-path fix is present in the specific Studio build used** — not checkable without a detected pad.

### Bottom line
Facet's `env.preferredInput` sourcing is doc-correct and uses the Roblox-recommended signal. The example-02 "no Edit button on gamepad" repro is fully consistent with a **known Studio/macOS gamepad-forwarding limitation** (pad invisible to engine → PreferredInput cannot read Gamepad), compounded by the Controller-Emulator Gamepad1-slot bug. It is NOT evidence of a Facet machinery fault (the full engine→env→memo→When→render chain was verified live both directions the same session). Definitive confirmation of the Gamepad affordance requires the **retail client on a real console or a desktop with a detected pad** — not synthetically reproducible in Studio here.

---

**Correction (verified live, 2026-07-21 later session):** item 3 of "Physically
UNVERIFIABLE in Studio" is partially superseded — the Studio **Xbox One device
emulator DOES report `GuiService.ViewportDisplaySize == Large`** (probed in a
play session: viewport 1920×1079, `Enum.DisplaySize.Large`). The ten-foot
profile is therefore exercisable in Studio via the console emulator; only true
TV overscan clipping and the vendor-API path on real hardware remain
physical-only.

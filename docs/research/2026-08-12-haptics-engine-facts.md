# Roblox haptics — engine facts, 2026-08-12

Measured against the live creator docs and the current API dump (client
`0.734.0.7340915`) for SwiftUI-parity round 2 Phase 3, which adds one opt-in
client haptics adapter behind LuauUI's semantic feedback bus. Recorded here per
constitution §12 ("engine facts are measured, then recorded, never assumed from
memory") and `ENGINEERING.md` "platform-native first — verify, every time".

**Headline: use `HapticEffect`, not `HapticService:SetMotor`. Haptics are not
gamepad-only. There is no capability API. This dev machine cannot produce
positive evidence.**

## 1. `HapticService` is superseded, though not tagged deprecated

Four live methods — `SetMotor`, `GetMotor`, `IsMotorSupported`,
`IsVibrationSupported` — and none carries a `Deprecated` tag in the API dump
(checked against a dump that does tag 48 classes and 465 members, so the absence
is meaningful). The docs supersede it anyway:

> "This service has been superseded by `HapticEffect`, which supports
> waveform-based effects, looping, spatial attenuation, and preset effect types.
> For new work, use `HapticEffect` instead."
> — <https://create.roblox.com/docs/reference/engine/classes/HapticService>

`Enum.VibrationMotor` still ships all six values (`Large`, `Small`,
`LeftTrigger`, `RightTrigger`, `LeftHand`, `RightHand`), none deprecated.

**The disqualifying silence:** `SetMotor`'s numeric range, how long a motor stays
set, and whether it must be explicitly zeroed are **undocumented**. A motor you
cannot prove stops is a stuck-rumble bug with no test. `HapticEffect` has
explicit `Play` / `Stop` / `Ended`.

## 2. `HapticEffect` — the current API

A creatable `Instance` class, full release 2025-09-16.

- Properties: `Looped: bool`, `Position: Vector3`, `Radius: float`,
  `Type: HapticEffectType`. (`WaveformData` is `Hidden, NotScriptable,
  RobloxSecurity` — not consumer surface.)
- Methods: `Play()`, `Stop()`, `SetWaveformKeys(keys)` — an array of
  `FloatCurveKey`, each a time in milliseconds, an intensity in `[0, 1]`, and a
  `KeyInterpolationMode` (`Constant` / `Linear` / `Cubic`).
- Event: `Ended` — does **not** fire when `Looped` is true, and does not fire on
  a manual `Stop()`. One community report says it only fires with a gamepad
  connected, so **do not build effect lifecycle on `Ended`**; pool and reuse.

`Enum.HapticEffectType`, six members, none deprecated: `Custom`, `UIHover`
("subtle and does not disrupt"), `UIClick` ("crisp … immediate feedback"),
`UINotification` ("draw the player's attention away from their current
gameplay"), `GameplayExplosion` ("high intensity … lingers"),
`GameplayCollision` ("a large immediate rumble that dies down quickly").

## 3. `GuiButton` fires haptics itself — the property route

Two live, scriptable, untagged properties:

- `GuiButton.HoverHapticEffect: HapticEffect` — plays while hovered.
- `GuiButton.PressHapticEffect: HapticEffect` — plays while pressed.

<https://create.roblox.com/docs/reference/engine/classes/GuiButton#HoverHapticEffect>

LuauUI already materializes `TextButton`s, so assigning these makes the **engine**
the player — LuauUI hands over a reference and never calls `Play()`, which keeps
`src/present/feedback.luau:4-5` ("LuauUI PLAYS NOTHING") literally true rather
than nearly true. Two caveats: the docs never say which input devices trigger
them, and an Instance-reference property is not StyleSheet-expressible, so the
adapter assigns it directly.

## 4. Device coverage — a documented conflict, recorded not resolved

The `HapticEffect` class reference:

> "Roblox supports haptics for the following devices: Android and iOS phones
> supporting haptics including most iPhone, Pixel, and Samsung Galaxy devices;
> PlayStation gamepads; Xbox gamepads; Quest Touch controller"

The gamepad input guide, in equally absolute phrasing, lists **only** PlayStation,
Xbox and Quest (<https://create.roblox.com/docs/en-us/input/gamepad.md>). That
page is gamepad-scoped so the omission is defensible, but the wording is not.

The 2025-09-16 full-release announcement resolves it toward mobile by what its
*unsupported* list excludes: "All game controllers connected to MacOS 15+", "VR
controllers connected to PC", "All game controllers connected to mobile devices"
— it rules out controllers *attached to* phones, not phones themselves. The
2025-04 beta announcement said haptics work "across haptic-enabled input devices
across mobile phones, Gamepads, and VR controllers", unsupported on "Android 11
and below".

**Write it as:** gamepad — documented and physically verifiable; phone —
documented, and unverified here. Never as a flat "touch supported".

## 5. There is no capability API, and the probe is genuinely tri-state

- No `IsSupported`, no `CanPlay`, nothing on `HapticEffect`; `UserInputService`
  has **zero** haptic members (verified against the dump).
- The only probe on the platform is `HapticService:IsVibrationSupported` /
  `IsMotorSupported`, which belong to the superseded service, are **boolean**,
  and are never claimed to describe `HapticEffect`'s routing.

This is precisely the shape [`../lessons/capability-probes-must-be-tri-state.md`](../lessons/capability-probes-must-be-tri-state.md)
was written about, for three independent reasons:

1. `Instance.new("HapticEffect")` can throw on a client without the class — the
   lesson's `absent` vs `blocked` distinction applies verbatim, so the `pcall`
   must keep the error text.
2. `IsVibrationSupported` returns `false` both for "this device has no motor" and
   for "no gamepad connected *yet*" — one boolean, two worlds.
3. On touch there is **no probe at all**. `TouchEnabled` says there is a screen;
   the docs say only "most" iPhone/Pixel/Galaxy devices have haptics. A phone is
   therefore permanently `unknown`, never `supported`.

Use `supported | unsupported | unknown | blocked | absent`, defaulting to
`unknown` for touch and for the pre-first-gamepad state, where `unknown` means
"attempt it, expect nothing, publish no platform claim".

## 6. Hot-plug invalidates a cached answer

`UserInputService.GamepadConnected` / `GamepadDisconnected` /
`LastInputTypeChanged` / `GetConnectedGamepads()` / `GamepadEnabled` are the
seams. The docs **never** say whether `Play()` re-routes to a newly connected pad
or whether `IsVibrationSupported` is re-evaluated — silent. So re-probe on those
three events; never cache once at boot. Note the documented caveat that input
events "only fire when the Roblox client window is in focus".

## 7. Constraints an adapter must respect

| Constraint | Source | Consequence |
|---|---|---|
| Keep "less than 100 simultaneous haptic effects" | beta announcement FAQ | pool one effect per mapped verb; never `Instance.new` per fire |
| "haptic intensity below 0.1 may not trigger any haptic effects" on some clients | full-release announcement | a custom waveform must not author keys under 0.1 and call it subtle |
| Effects run locally in Studio (edit, play, local server); later fixed for Team Test and Virtual Cursor | beta + full release | you can construct and fire without throwing; you cannot feel it |
| **"All game controllers connected to MacOS 15+"** unsupported | full-release announcement | **this repo's dev machine is darwin** — no Studio canary here can ever be positive evidence, and a silent run must not be recorded as "haptics do not work" |
| Controllers on phones, VR on PC, Android ≤ 11 unsupported | both announcements | degrade silently; `unknown`, not a bug |
| iPhone + voice chat inconsistent | full-release known issues | a missed phone tick is not necessarily an adapter defect |

## 8. The player's preference exists and the game cannot read it

`HapticService`'s docs say "Motor output is scaled by the user's haptic intensity
preference in their Roblox settings." The backing property,
`UserGameSettings.HapticStrength`, is `Hidden, NotReplicated` with
`RobloxScriptSecurity` on **both** read and write — game code cannot see it.
Roblox staff, asked directly: "As of now, we don't expose the haptics option in
the User Settings."

Whether `HapticEffect` is scaled by that same preference is **undocumented**.
Assume it is (the alternative would be a platform bug) but do not record it as
fact. Consequence: the adapter owns its own on/off switch and cannot verify it
honors the player — only a device can answer that.

## 9. Two inherited claims that are NOT documented

RascalRally's `src/client/ItemAudio.luau` already uses `HapticEffect` and its
comments assert two things the docs do not support. Do not copy them into LuauUI
as facts:

- `:590-600` — "an effect outside the evaluated container is a silent no-op",
  hence parenting to `workspace`. The docs state **no** parenting requirement;
  only the official sample happens to parent to `Workspace`. If the adapter
  parents somewhere, say "matching the official sample", not "required".
- "HapticEffect plays on the active gamepad regardless of parent" — plausible,
  unsourced.

What that file *did* record and is worth inheriting: `UISelection` is **not** a
real `HapticEffectType` member, and guessing it made every tier silently fall
back to the weakest tick; and `Custom` used as a fallback is a **guaranteed
silent no-op**, because a `Custom` effect with no `SetWaveformKeys` plays
nothing. Both are why the adapter resolves the enum defensively by name and
never falls back to `Custom`.

## Sources

- <https://create.roblox.com/docs/reference/engine/classes/HapticEffect>
- <https://create.roblox.com/docs/reference/engine/classes/HapticService>
- <https://create.roblox.com/docs/reference/engine/enums/HapticEffectType>
- <https://create.roblox.com/docs/reference/engine/enums/VibrationMotor>
- <https://create.roblox.com/docs/reference/engine/classes/GuiButton#HoverHapticEffect>
- <https://create.roblox.com/docs/en-us/input/gamepad.md>
- <https://create.roblox.com/docs/en-us/reference/engine/classes/UserInputService.md>
- <https://create.roblox.com/docs/reference/engine/classes/UserGameSettings>
- Full release, 2025-09-16: <https://devforum.roblox.com/t/full-release-you-can-now-publish-haptic-effects-in-your-experience/3660577>
- Studio beta, 2025-04-15: <https://devforum.roblox.com/t/studio-beta-introducing-new-haptics-effects-and-apis/3606858>
- `HapticEffect.Ended` update: <https://devforum.roblox.com/t/introducing-new-updates-to-the-haptics-system/4067702>

---

## Re-confirmation, live in Studio, 2026-08-14

Standing rule 1 (`docs/plans/swiftui-parity-round3-brief.md`) requires checking
the *current* platform rather than trusting a two-day-old note, so every fact
above was re-asked of a running client — `0.734.0.7340915`, `LuauUI-Showcase`,
Play mode, macOS. **Nothing had moved.** The creator docs for `HapticEffect`,
`GuiButton` and the two announcement threads are byte-identical in substance; the
newest platform change anywhere in this area is still the November 2025 `Ended`
update.

Everything below was measured by executing Luau in the live client. **None of it
required a LuauUI module from the place**, so the stale-Rojo-sync issue recorded
the same day (additions land, modifications do not) cannot have contaminated it:
these are questions about the ENGINE.

| Question | Live answer |
|---|---|
| `Instance.new("HapticEffect")` from a LocalScript | succeeds |
| `Enum.HapticEffectType` members | exactly six: `Custom`, `UIHover`, `UIClick`, `UINotification`, `GameplayExplosion`, `GameplayCollision` |
| `Enum.HapticEffectType["UISelection"]` | **throws** — `UISelection is not a valid member of "Enum.HapticEffectType"`. Confirms fact 4: the lookup must sit inside a `pcall` or a typo is a crash |
| `GuiButton.PressHapticEffect` / `HoverHapticEffect` write | both succeed from a LocalScript, and read back the assigned instance |
| `HapticEffect:Play()` / `:Stop()` | neither throws (they run locally in Studio; you cannot feel them) |
| `HapticEffect.IsSupported` / `.IsPlaying` | **absent** — no capability API on the class |
| `UserInputService` haptic members | **zero**. `PreferredInput`, `TouchEnabled`, `GamepadEnabled` etc. exist; nothing haptic |
| `HapticService:IsVibrationSupported` on all 8 gamepad slots | `false` on every slot, with **zero pads attached** — the boolean lying exactly as fact 5 predicts |
| `HapticService:IsMotorSupported(Gamepad1, …)` all 6 motors | `false` on every one, same caveat |
| `UserGameSettings.HapticStrength` read | **refused**: *"The current thread cannot read 'HapticStrength' (lacking capability RobloxScript)"* — fact 8, quoted from the engine rather than from the dump |
| Session input class | `TouchEnabled = true`, `GamepadEnabled = false`, `PreferredInput = Touch` (Studio device emulator) |

One fact the class reference has that this document did not record: **every
`HapticEffect` member requires the `Input` capability**, which matters for code
running inside a sandboxed container.

### The attribute channel, measured

The per-control sensory hook (2026-08-14) publishes a control's declared verb as
an attribute the haptics adapter reads. That channel was exercised live:

- `SetAttribute("LuauUI_ActivationFeedback", "commit")` then `GetAttribute` round
  trips on a `TextButton`;
- `SetAttribute(name, nil)` **clears** it (`GetAttribute` answers `nil`) — which
  is what makes the renderer's unconditional push safe against instance
  recycling.

### The resolution rules, end to end on the real engine

The shipped `pressEffectFor` + `decorate` rules were replayed inline (as a pasted
script, **not** by requiring the stale module in the place) against six real
`TextButton`s, each pre-decorated with a stale `GameplayExplosion` reference so a
"skip" could not pass as a "clear":

| attribute | resulting `PressHapticEffect` |
|---|---|
| *(absent)* | `UIClick` |
| `commit` | `UIClick` |
| `reject` | `UINotification` |
| `adjust` | `UIHover` |
| `none` | **none — the stale reference was cleared** |
| `cancel` | **none** (a verb the map deliberately silences) |

Four effects constructed for six buttons: effects pool by *sensation*, so the
three `UIClick` buttons share one Instance. Two buttons with different verbs hold
two different instances, which is the whole point of the per-control declaration.
Wiring `Activated` on a decorated button raised no error.

**What is still unprovable here.** Nothing was *felt*. The full-release
announcement lists "all game controllers connected to MacOS 15+" as unsupported
and this machine is macOS with no pad attached, so a silent run is expected and
must never be recorded as "haptics do not work". The three `PENDING_PHYSICAL`
rows stand.

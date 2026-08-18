# E2 — the ScreenInsets / SafeAreaCompatibility decision packet (PLAT-17)

Written 2026-08-18 for the DIR wave, contract 6's second half. **No property is
flipped by this wave** (controller ruling R8: an unverifiable device-behaviour
change does not land mid-stage). This is the packet the pending device round
runs from.

## 1. What Facet's root ScreenGui is, today

`src/client/screen_target.luau:1000-1015` is the only place a Facet root is
constructed. Every property it sets, and nothing else:

| property | value Facet sets | where |
|---|---|---|
| `Name` | `Facet_<screenId>` | `screen_target.luau:1001` |
| `ResetOnSpawn` | `false` | `:1002` |
| `IgnoreGuiInset` | **`true`** | `:1003` |
| `ZIndexBehavior` | `Enum.ZIndexBehavior.Sibling` | `:1004` |
| `DisplayOrder` | set per surface by `adapter.setRootDisplayOrder` | `:2047-2050` |
| `Parent` | `PlayerGui` | `:1013` |
| (native mode) one `StyleLink` child | `native_style.link(gui, sheet)` | `:1006-1011` |

Three properties are therefore at their **engine defaults and are never
written**:

- `ScreenInsets`
- `SafeAreaCompatibility`
- `ClipToDeviceSafeArea`

The edit-mode preview root (`src/client/edit_preview.luau:41-45`) sets the same
`IgnoreGuiInset = true` / `ZIndexBehavior = Sibling` pair plus `DisplayOrder =
1000`, and the billboard target (`src/client/billboard_target.luau:72-82`) sets
`ZIndexBehavior` + `ResetOnSpawn`. Neither writes the three above either.

## 2. What the official documentation says

Roblox's reference pages carry the **type signatures with no prose**: the
`ScreenGui` page lists `ScreenGui.ScreenInsets:[Enum.ScreenInsets]`,
`ScreenGui.SafeAreaCompatibility:[Enum.SafeAreaCompatibility]`,
`ScreenGui.IgnoreGuiInset:[boolean]` (Not Replicated) and
`ScreenGui.ClipToDeviceSafeArea:[boolean]` and describes none of them
(<https://create.roblox.com/docs/reference/engine/classes/ScreenGui>). **That is
itself part of the finding** — the behaviour below is documented in enum pages
and staff replies, not in the property reference, so any decision taken from the
reference alone would be taken from nothing.

### `Enum.ScreenInsets`

<https://create.roblox.com/docs/reference/engine/enums/ScreenInsets> — four
members, values only, **no summary text for any of them**:

| member | value | what it means (from the staff reply in §2.1 and the notched-screen release) |
|---|---|---|
| `None` | 0 | the GUI's coordinate origin is the raw viewport: it fills the whole screen, cutouts included |
| `DeviceSafeInsets` | 1 | origin is the device-safe viewport (notch/rounded-corner excluded, CoreUI topbar **included**) |
| `CoreUISafeInsets` | 2 | origin is below Roblox's own topbar — the default coordinate system `AbsolutePosition` is expressed in |
| `TopbarSafeInsets` | 3 | origin is the topbar band itself, for UI meant to sit level with Roblox's cluster |

### `Enum.SafeAreaCompatibility`

<https://create.roblox.com/docs/reference/engine/enums/SafeAreaCompatibility> —
two members, values only, **no summary text**:

| member | value | what it means |
|---|---|---|
| `None` | 0 | no compatibility transform; a descendant that declares a fullscreen size gets exactly that box |
| `FullscreenExtension` | 1 | the engine applies an automatic transform to descendant *fullscreen* GuiObjects so they extend under a screen cutout |

The one-sentence description that exists anywhere official is on the property
summary: *"specifies whether automatic UI compatibility transformations are
applied to descendant 'fullscreen' GuiObjects of a ScreenGui on displays with
screen cutouts"*.

### 2.1 The staff reply that actually settles the coordinate question

<https://devforum.roblox.com/t/ignoreguiinset-coreuisafeinsets-does-not-get-ignored-in-absoluteposition/3771408>
— reported as a bug, answered by Roblox as **intended behaviour**:

> The `AbsolutePosition` property uses the CoreUISafeInsets coordinate system,
> whose origin is at the bottom left of the top bar area.

and, on why `IgnoreGuiInset = true` produces negative `AbsolutePosition.Y`:

> `Position` specifies 0 offset between the GuiObject and the DeviceSafeInsets
> viewport, which is above the CoreUISafeInsets viewport.

The same reply states that **`ScreenInsets` does not change this**:
`AbsolutePosition` stays in CoreUISafeInsets space whatever `ScreenInsets` is
set to. This is the engine-side confirmation of the standing Facet lesson that a
Facet root reads back inset-subtracted, and a negative `y` means *near the top*,
not *off the top*.

### 2.2 The open engine bug that makes a blind flip unsafe

<https://devforum.roblox.com/t/trying-to-set-screenguiscreeninsets-to-enumscreeninsetscoreuisafeinsets-defaults-to-enumscreeninsetsdevicesafeinsets/3177424>
— assigning `ScreenInsets = CoreUISafeInsets` is reported to read back as
`DeviceSafeInsets`. Roblox acknowledged and filed an internal ticket; **no fix
is announced**. So on today's engine a `ScreenInsets` write may or may not take,
and the property read is not proof the write landed. Any flip must be verified
by measuring a rect, never by reading the property back.

## 3. What would change for Facet's inset-fact model

Facet does **not** consume the engine's inset behaviour; it re-derives it. The
model is:

1. `src/client/roblox_env.luau:31-56` reads the three inset areas as plain data
   through `GuiService:GetInsetArea(Enum.ScreenInsets.<CoreUISafeInsets |
   DeviceSafeInsets | TopbarSafeInsets>)` — the enum is used as a **query key**,
   never as a ScreenGui property.
2. `src/env/safe_insets.luau` turns each area into per-edge insets, and the belt
   (`newBelt`) refuses an area that has not moved with the viewport that is
   published beside it (PLAT-3, redone in R1). The three areas lag
   independently.
3. `src/env/environment.luau`'s `platformChrome` merges the platform band, the
   app's own `appChromeRects`, and the safe insets into one fact.
4. Every surface spends those facts itself, because the root is
   `IgnoreGuiInset = true` — i.e. the root's box is the **DeviceSafeInsets
   viewport** and Facet subtracts everything else in the solver.

So the consequences of each candidate flip:

| change | what it would do to Facet | risk |
|---|---|---|
| `ScreenInsets = DeviceSafeInsets` | **the state Facet is already in** — `IgnoreGuiInset = true` is the legacy spelling of it. Writing it explicitly is a no-op *if* the two are truly equivalent, which §2.2 says cannot be assumed from a property read | low value, non-zero risk |
| `ScreenInsets = CoreUISafeInsets` | the root would start below Roblox's topbar and Facet would subtract the topbar **again** (`platformChrome.insets.top` is still 58): every surface loses 58px twice, and the ADR-0027 topbar band becomes unreachable | **breaks the model** |
| `ScreenInsets = None` | the root gains the cutout region. Facet's `deviceSafeInsets` fact is currently **lateral-zero on the reported devices** (the engine pre-excludes the notch from the camera — see `docs/lessons/device-emulator-truths`), so nothing in the solver would reserve the notch and content would paint under it | needs the device probe in §4 before it can even be evaluated |
| `SafeAreaCompatibility = FullscreenExtension` | applies an engine-side transform to descendants that declare a fullscreen size. Facet writes explicit `Position`/`Size` offsets on every node from solved rects — a silent engine transform on top of a solved rect is exactly the "measured one box, painted another" family | **do not** |
| `ClipToDeviceSafeArea = false` | stops the engine clipping to the safe area. Would let a theme's rim/shadow paint into the cutout region instead of being clipped there | only meaningful together with a `ScreenInsets` change |

**The DIR-1 relevance.** DIR-1 (the chip strip's left border clipped at the
glass) did not reproduce in emulation: chip left margins measured 8/6/4px per
package at 360x691 and no skin image extends left of any chip rect. Contract 6
floors every package's screen-edge step at 8px, which is a belt against the
model ever becoming the cause. If the border is still clipped on the device
after the republish, the remaining suspect is this table's row 3/5 — the pixels
between the solved rect and the glass — and §4 is how to tell which.

## 4. The probe the pending device round runs

Run on a **real phone with a cutout** (the director's device), on the republished
showcase place, with the demo picker's chip strip visible. Studio's emulator is
explicitly **not** sufficient: it is on record as not respecting
`DeviceSafeInsets` on the Y axis
(<https://devforum.roblox.com/t/studio-mobile-emulator-does-not-respect-devicesafeinsets-along-y-axis/4703438>),
which is the axis half of this question.

### 4.1 Read the facts before touching anything

```lua
-- run in the live client (execute_luau against the running session)
local GuiService = game:GetService("GuiService")
local cam = workspace.CurrentCamera
local out = { viewport = { cam.ViewportSize.X, cam.ViewportSize.Y } }
for _, name in { "None", "DeviceSafeInsets", "CoreUISafeInsets", "TopbarSafeInsets" } do
	local ok, r = pcall(function() return GuiService:GetInsetArea(Enum.ScreenInsets[name]) end)
	out[name] = ok and { r.Min.X, r.Min.Y, r.Max.X, r.Max.Y } or "unavailable"
end
out.guiInset = { select(1, GuiService:GetGuiInset()), select(2, GuiService:GetGuiInset()) }
local gui = game.Players.LocalPlayer.PlayerGui:FindFirstChild("Facet_ShowcaseChrome", true)
out.root = gui and {
	ScreenInsets = tostring(gui.ScreenInsets),
	SafeAreaCompatibility = tostring(gui.SafeAreaCompatibility),
	ClipToDeviceSafeArea = gui.ClipToDeviceSafeArea,
	IgnoreGuiInset = gui.IgnoreGuiInset,
	AbsoluteSize = { gui.AbsoluteSize.X, gui.AbsoluteSize.Y },
} or "no Facet root found"
return game:GetService("HttpService"):JSONEncode(out)
```

**What to record:** all four areas, the legacy `GetGuiInset`, and the root's four
properties as the engine reports them with Facet never having written three of
them. This is the row the packet is missing — every number above §3 is derived
from source and documentation, and none of it is a device measurement.

### 4.2 Measure the strip against the glass

With the chip strip on screen, in **portrait**:

```lua
local chips = -- /ShowcaseChrome/Dock/Bar/Chips, via the Facet showcase API
return { chips.AbsolutePosition.X, chips.AbsolutePosition.Y,
         chips.AbsoluteSize.X, chips.AbsoluteSize.Y }
```

Expected after this wave's contract 6: `AbsolutePosition.X >= 8` under every
package (it was 4 under classic-desktop and 6 under compact-pointer before).
`AbsolutePosition.Y` will be **negative** on a Facet root and that is correct
(§2.1). Then take a zoomed capture of the strip's **left border** at the glass.

- Border visible with a gap → DIR-1 is closed by the gutter floor; no property
  flip is needed and this packet is filed as a null result.
- Border still clipped at x = 0 → the gutter is not the cause; go to §4.3.

### 4.3 The one flip worth testing, and how to tell whether it took

Only `ScreenInsets = DeviceSafeInsets` written **explicitly** is worth a trial,
because it is the state Facet already believes it is in. Write it, then **verify
by geometry, never by the property read** (§2.2):

```lua
local before = { chips.AbsolutePosition.X, chips.AbsolutePosition.Y }
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
task.wait(0.2)
local after = { chips.AbsolutePosition.X, chips.AbsolutePosition.Y }
return { before = before, after = after, read = tostring(gui.ScreenInsets) }
```

`before == after` is the answer this packet predicts: the write is a no-op and
`IgnoreGuiInset = true` was already the same viewport. **Any movement at all is
a finding** — it means Facet's whole inset model has been subtracting from the
wrong origin, which is a stage-blocking result rather than a tuning knob.

`SafeAreaCompatibility` and `ClipToDeviceSafeArea` are **not** to be flipped on
this round: §3 rules the first out on principle (a silent engine transform over
a solved rect) and the second is only meaningful after a `ScreenInsets` decision
that this probe has not earned yet.

## 5. Decision, as it stands

**No flip this wave.** Facet's model is self-consistent and the one property
that is already effectively set (`IgnoreGuiInset = true` ≡ DeviceSafeInsets
origin) is confirmed by a Roblox staff reply. The gutter floor lands instead,
because it is a change whose effect a headless check can prove. §4 is the
evidence the next device round owes before any of this becomes a code change.

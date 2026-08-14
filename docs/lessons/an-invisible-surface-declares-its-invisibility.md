# An invisible surface has to *declare* its invisibility — and the second copy declared nothing

**Found:** 2026-08-13, director device report on the showcase place, Pixel Quest.
*"in the showcase when i swipe from left to right in swipe row actions/table,
some random thing appears over the top of the screen blocking the demo picker
and settings button."*

## The mechanism

`src/present/presenter.luau` synthesizes **two** presenter-private catchers —
full-viewport `Button`s whose entire job is to swallow one tap and be seen by
nobody:

- the **modal / engaged scrim** (`mountScrim`), and
- the **transient popup catcher** (`mountPopupCatcher`), mounted whenever any
  contribution publishes `outsideDismiss.active` — which `row_actions.luau` does
  for exactly as long as a swipe tray is open.

Nothing about a `Button` says "invisible". `chrome_slots.classify` falls **every**
`Button` through to the `control` slot, and `screen_target`'s native paint gives
every surface-less control the package's solid control colour. So being invisible
is two explicit declarations, not a default:

```lua
surface = "plain"                       -- no native fill, no interactive tag
chrome_slots.attachHint(bp, { slot = chrome_slots.NO_SLOT })  -- not a skin target
```

`mountScrim` learned both, live, under the P5 packages — its comments name the
exact failure ("the invisible catcher wore the installed package's SOLID control
colour across the whole viewport"). `mountPopupCatcher`, written later for the
identical job, was a **second copy of the same construction that inherited none of
the first one's corrections**, and shipped painting.

## Why it read as "over the top of the screen" and not "over everything"

A catcher mounts at `owner.displayOrder - 50`. Measured live in the running
showcase client, mid-defect:

```
LuauUI_ShowcaseChrome        DisplayOrder=10200   <- the demo picker + Settings
LuauUI___popupcatcher__      DisplayOrder=10350   <- the plate
LuauUI_MailActions           DisplayOrder=10400   <- the demo screen
```

The demo screen covers the catcher everywhere it paints; the chrome band above it
does not. So a full-viewport plate showed up as a band across the top, over
exactly the two controls the director named.

## The instrument: the same adapter, both shapes, one session

The catcher had been described as transparent for as long as it existed. The
`GuiObject` dump ends that argument in two lines — same engine, same theme, same
frame, one declared invisible and one not:

```
-- popup catcher, as shipped (no declarations)
TextButton '/__popupcatcher__/catcher'  413x735  bgT=0.00
  ImageLabel 'LuauUIChrome'             413x735  bgT=0.00   <- the package's plate
  TextLabel  'LuauUIChromeText'

-- scrim catcher, scrim="none" (surface="plain" + NO_SLOT)
TextButton '/__scrim__/catcher'         413x735  bgT=1.00
  UIPadding                                                 <- and nothing else
```

`BackgroundTransparency` and the presence of a `LuauUIChrome` child are the whole
measurement. A screenshot would have shown the same thing and proved less.

## The rules this leaves

1. **A second construction of the same private surface is a bug waiting for a
   theme.** The fix was not a third copy of the two declarations — it was one
   `catcherScreen(rootId, surface)` both call sites go through, so a future third
   catcher cannot be born painted.
2. **`surface = nil` is not `surface = "plain"`.** Absent means "classify me";
   `plain` means "paint nothing". Two subsystems read the same field and only one
   of them treats absence as a request.
3. **Assert the classification, not the pixel.** `tests/popup_catcher_paint.spec.luau`
   runs `chrome_slots.classify` on the mounted node — the same oracle
   `screen_chrome.luau`'s `chromeSlotOf` runs on the real adapter — from both live
   `outsideDismiss` owners (a row-actions tray and a `PopupButton`), because the
   defect belongs to the presenter, not to either control.

## See also

- [`decoration-paints-to-the-edges.md`](decoration-paints-to-the-edges.md) — the
  other half of "a catcher is not content".
- [`screen-target-tree-is-flat.md`](screen-target-tree-is-flat.md) — why a stray
  node is findable by name in a live client, which is how this one was caught.

# D2 — `Menu`, and the row recipe three controls now share

**Landed 2026-08-16.** Suite 5773 passed / 0 failed (was 5730 before this stage);
Rascal Rally 3305 passed / 0 failed (was 3297). Gate row `d2-menu`.

Brief: `docs/plans/navigation-and-menus-brief.md` §2 D2. Director call:
`artifacts/navigation-and-menus/additive-vs-net-new.md` §5 — *"D2 **extracts**
`buildMenuRows` instead of authoring menu rows."*

---

## What shipped

| | |
|---|---|
| `LuauUI.newMenu` | a freestanding action menu attachable to **any** blueprint (`src/controls/menu.luau`) |
| `src/controls/menu_recipe.luau` | the ONE menu row and the ONE presentation rule, rendered from by `newMenu`, `newPopupButton` and `newRowActions`' action menu |
| `popup_button.Option` | gained `icon`, gained a `divider = true` item, gained a closed key set |
| `controller.attachContextGestures` | the renderer seam that reaches the normalized touch-gesture stream and the pointer's secondary button by path |
| `adapter.setSecondaryActivate` | a new optional render-target capability — `MouseButton2` on a node, observed, never sunk |
| `contribution.contextTriggers` | which subtrees have claimed the context gesture; the presenter's disclosure carve-out reads it |
| `bindPresent`'s third argument | `presenter.presentAnchored`, additive |

`.contextMenu` moves from **Missing** to **Covered** and `.popover` from
Partial-as-a-construct to **Covered** (`docs/reference/swiftui-parity.md`
§5.2 and the transient-panel row).

## The public API, verbatim

```
LuauUI.newMenu(LuauUI, core, spec) -> { blueprint, api, presentation, dump, dispose }

spec = {
  id?, trigger: Blueprint, items: { Item },
  triggers?: { "activate" | "secondary" | "longPress" | "keyboard" | "gamepad" },
  presentation?: "automatic" | "menu" | "sheet",
  sizeClass?: string | Readable, interactionClasses?: table | Readable,
  onOpen?: () -> (), onClose?: () -> (),
}

Item = { id, label, icon?, role?, enabled?, onSelect }   -- an ACTION
     | { id, label, icon?, role?, enabled?, children }   -- a SUBMENU
     | { divider = true }                                -- a rule between groups

api = { open() -> boolean, close(), closeLevel(), toggle(), select(id) -> boolean,
        handleActivate(path, meta?) -> boolean, diagnostics() -> { string },
        isOpen: Signal, openPath: Signal, presentation() -> string }
```

`blueprint` is **the caller's own trigger node** carrying an input contribution —
no wrapper, no layout change. Declaring both `onSelect` and `children` is a spec
error, and so is declaring neither.

## Decisions that are not obvious from the code

### The long-press collision — measured, then decided the other way

The brief and the director call both anticipated **removing** the disclosure
plate's long-press binding so D2 could take the gesture. The instruction was to
measure first. The measurement says do not remove it:

| Question | Answer, read in source |
|---|---|
| What owns touch long-press today? | The full-value disclosure plate, and only it. `renderer.luau:1264` (mount) and `:3239` (mid-session retrofit) wire `adapter.enableDisclosure`'s `longPress` half on any node declaring `disclose`/`reveal`; it lands on `presenter._discloseLongPress`. The recognizer is a hand-rolled 0.4 s / 12 px press timer in `screen_target.luau:2557-2630` — it does **not** go through `touch_gestures.luau`, and it does **not** sink the press |
| Is there another touch route to a truncated label's full value? | One, and it is weak. `UI.Text{ reveal = "auto" }` is opt-in, accepted on `UI.Text` **only**, capped at one live strip per presentation, and **disabled entirely under reduced motion** — where `text_reveal.luau:22` names the plate as its own fallback. A disclosing `UI.Toggle` label or `newTable` cell has no marquee even in principle |
| Would the focus route cover touch? | No. `presenter.luau:1119` bails when `focusVisible` is false, and a tap sets `focusOrigin = "pointer"` → `focusVisible = false`, deliberately (*"a plate popping up under every tap is the tooltip-on-click behaviour nobody wants"*) |
| Would any check have caught the removal? | No. `text_audit.clippedEssential` (`text_audit.luau:279-281`) accepts the **declaration** `disclose = true`; it never asks whether the gesture that reaches it still exists |

So: **the plate keeps long-press.** `newMenu` claims it only inside its own
trigger subtree, through `contribution.contextTriggers` →
`handle.contextTriggerOwns` → an early return in `presenter._discloseLongPress`.
A menu declared without `longPress` or `secondary` claims nothing at all.

The premise that made removal look necessary — *"two constructs fight for one
gesture"* — is only true where one node is both a menu trigger and a truncated
disclosing label. That case is real (it is `r1`'s own list row), and it now has a
stated winner instead of two handlers firing off one unsunk press.

**D3a is unaffected and its rule is unchanged:** `help` binds **no** gesture,
matching Apple. `tests/menu.spec.luau` carries a source sweep that fails the day
a third file in `src/` learns the word `longPress`.

### The trigger half consumes what already shipped

`swiftui-parity.md` §5.2 said the blocker was *"the adaptation layer is built,
tested, and exported, and nothing consumes it as a trigger."* Long-press is read
off that layer (`adapter.setTouchGestureHandlers` → `kind == "longPress"`,
`state == "began"`), not re-recognized. The one channel that genuinely did not
exist is the pointer's secondary button: `Button`'s `Activated` fires for the
primary button and touch only, so `MouseButton2` needed its own optional
capability. Both reach a control through one nilable renderer seam, so an adapter
missing either degrades by name and the other triggers still open the menu.

### Submenus: unbounded, and diagnosed

`validate()` recurses with a `depth` counter and never refuses on it. At
`depth + 1 >= 2` — a submenu inside a submenu — it appends a diagnostic quoting
the HIG. `api.diagnostics()` and `dump().diagnostics` carry it. One level is
silent, because one level is what the HIG advises.

Two more authoring-time rules live in the recipe: icons are **per-group
all-or-nothing** (a refusal, groups separated by dividers) and a group of more
than five actionable items is **advice**. A destructive item that is not last is
advice too.

### `sheet` replaces, `menu` stacks

One branch, in `ops.enter`, resolved from `menu_recipe.resolvePresentation` —
size class + live interaction classes, never a device name. Under `sheet` the
current panel is dismissed before the next is presented and the new panel grows a
leading Back row; `dump().surfaces` is 1 at any depth. Under `menu` each level is
its own `presentAnchored` surface anchored to its **parent row**, `edge =
"trailing"`, and the count grows with the chain.

The presentation is a **memo** over the caller's Readables rather than a read at
open time, so a live class flip while a submenu is open rebuilds the surfaces in
the new idiom at the depth the player had reached. Cancelling the chain instead
would close a menu under a player who did nothing but rotate the device.

## The extraction

`row_actions.buildMenuRows`' per-row body and `popup_button.resolvePresentation`
moved to `menu_recipe.luau` unchanged. `popup_button.resolvePresentation` is now
an **alias assignment**, so it is the same function object — a spec asserts
identity rather than equal answers, and the gate's own
`grep -q "resolvePresentation" src/controls/popup_button.luau` still matches.

The leaf row's props are byte-identical to what `row_actions` shipped, because
two of its own cases pin the tree: the menu-flip prediction is exact only while
`MenuRows` stays *"a padding-free VStack of fixed-height rows"*, and its
large-text case reads `controller.textAt(<row path>)` for the row's own label.
Both still pass, along with the rest of `row_actions_input.spec` — that is the
proof the migration is behaviour-neutral. Only a **submenu** row takes the
content-button form, and `row_actions` has no submenus.

**Size, measured rather than assumed.** `row_actions.luau` went 192,931 → 193,002
— it *grew* by 71 bytes. The row-building code left, but the comment that
explains where it went and which two shipped cases pin the props is longer than
the code was, and that comment is the thing that keeps the next agent from
re-inlining it. `renderer.luau` went 197,290 → 198,356 for the one new controller
seam, leaving 1,644 bytes of headroom, which is the number to watch before the
next renderer edit. `check_source_size` PASS, `KNOWN_OVER` empty.

## Mutation ledger — eleven, every one seen to fail

| # | Mutation | Reddened |
|---|---|---|
| M1 | `if depth + 1 >= DEPTH_ADVICE` → `if false` | `a three-level tree BUILDS, and depth >= 2 is diagnosed…` |
| M2 | `children` + `onSelect` accepted instead of refused | `declaring BOTH children and onSelect is a spec error…` |
| M3 | `open()` returns early when no item is enabled | `a wholly unavailable menu opens…` + `selecting a disabled item does nothing…` (2) |
| M4 | the sheet stacks a second panel instead of replacing | `under \`sheet\` a submenu REPLACES the sheet's contents…` |
| M5 | Cancel calls `closeAll()` instead of `back()` | `the gamepad menu button opens it, and ButtonB closes ONE level` |
| M6 | `mixedIconGroup` never reports a mixed group | the Menu lint case **and** the popup_button lint case (2) |
| M7 | the presenter's context-trigger carve-out deleted | `…inside a Menu trigger the MENU owns it` |
| M8 | the disclosure's `longPress` half unwired in the renderer | `a pointer world wires hover; a pure-touch world wires long-press instead` (`text_disclosure.spec`) — the a11y alarm |
| M9 | `resolvePresentation` forked back into `popup_button` | `\`resolvePresentation\` lives in ONE place…` |
| M10 | an outside-tap dismiss unwinds one level instead of all | `tap-away closes EVERY level, not just the innermost` |
| M11 | a new `src/present/help_probe.luau` mentioning `longPress` | `exactly two constructs know the word long-press…` |

Three more against the Rascal Rally rider, each reddening its own case: deleting
the carve-out, forking `resolvePresentation`, and a `newMenu` mention landing in
the game's `src/`.

## Rascal Rally

`tests/luauui_menu_contract.spec.luau`, 8 cases, registered in `tests/run.luau`.
No production caller changed and none should have — nothing in the game builds a
menu, and its only structural dependency on `row_actions` is the module table
(`ROW_KEYS`, `ROW_KEY_PRIORITY`, `build`, `buildHosted`), which is untouched. The
rider proves the construct is live on the game's own require path, that both new
sibling modules resolve there (both Rojo projects mount `src` by directory, so a
new sibling arrives with no project edit — a claim until something requires it
from that side), that the extraction shares one function object rather than two
copies, that the row props its hosted lists were written against are unchanged,
that nothing there consumes any of it yet, and — the case that matters most for
the ten shipped Sponsor surfaces declaring `UI.Text{ disclose = true }` — that the
truncated-label plate still owns touch long-press everywhere outside a menu
trigger.

## Owed

Every gesture trigger is a **physical-device** row (acceptance `NM-X1`, `NM-X2`).
Studio cannot synthesize a real touch or gamepad input class, and an injected
pointer event arrives as `Touch` rather than `MouseButton2` — filtering it wrong
manufactures a false positive that agrees with you. What is proved here is the
routing and the decisions, headlessly, through the real adapter seams; what is
not proved is native arbitration:

- touch **long-press** opening a menu on hardware, and not also firing the plate;
- pointer **right-click** with `MouseButton2` arbitration;
- the gamepad trigger with `PreferredInput == Gamepad`.

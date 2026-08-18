# A write of the class default never claims the property

**2026-08-15, director report on the `canvas-group` demo:** *"in one fade, or
three, i see a fade happen when i click the button, but changing the opacity
doesn't seem to change anything else."*

Every hop of that control was alive. The chip fired, the signal moved, the memo
re-rendered the status line, the renderer re-wrote all four
`CanvasGroup.GroupTransparency` values on the same frame. **The three plates the
group was fading had never been painted at all.** A fade of nothing looks
exactly like a dead slider.

## The engine fact

`StyleSheets` hand a property back the moment an *explicit* write takes it — and
the engine decides "explicit" **by value**. A write whose value equals the
instance's **class default** does not mark the property explicit, so the rule
keeps ownership and the write is a silent no-op.

Measured live in Studio on the shipped plate (`Frame`, class default
`BackgroundTransparency = 0`, under the sheet's `Frame default` rule which sets
it to `1`):

| step | `.BackgroundTransparency` | `:GetStyled("BackgroundTransparency")` |
|---|---|---|
| as shipped (the framework wrote `0`) | `0.0000` | **`1.0000`** — the rule still owns it |
| write `0.001` | `0.0010` | `0.0010` — now explicit |
| write `0` again (the class default) | `0.0000` | **`1.0000`** — ownership goes BACK |

The third row is the one to keep, and it is a second measured fact worth its own
line: **rule ownership comes BACK when the class default is written again.** A
claim is not permanent against the value — it is permanent against every value
except the default. **`GetStyled` is the only instrument that can see any of
this**: every plain read said `0`, and every headless check agreed, because a
fake adapter models the write and not the engine's refusal of it.

## What it broke

`screen_paint.applyTint`'s GuiObject branch. A `tint` is the continuous-colour
channel: the colour must be an explicit **claim** because no rule can carry
per-node data, and the file already knew the fill had to come with it —

> *"a Frame is transparent until a surface says otherwise … so a tint that only
> set `BackgroundColor3` would paint an invisible fill — accepted and ignored,
> the failure class this framework keeps closing. A tinted Box paints."*

— and then wrote `instance.BackgroundTransparency = alpha` with `alpha = 0`,
which is the class default, which claims nothing. So **every tinted `Box`/`ZStack`
with no `surface` and no declared `tint.transparency` painted nothing in native
mode**, for as long as the channel has existed. Not one demo: `canvas_group`'s six
plates, `virtual_grid`/`virtual_hgrid`'s cell faces (16 of them on the first
screen), `hud`'s task marks. Each of those fixtures had swept green and been
reviewed; the invisible plate is not a thing a measurement of *geometry* can see.

## The fix, and the rule it generalises to

A property a sheet owns is taken with a **tag**, never with a value the class
already has. `facet-tint-fill` + one `Tint fill` rule in the `base` group of both
sheet builders, so a surface, a value slot and a scrim all still out-rank it —
the fill is a *floor under an otherwise invisible node*, not a new authority.
The colour stays a claim, because a rule cannot carry data. That split is not new:
`gripFocus` has ridden a tag since 2026-07-24 for the identical reason, recorded
in `ClassifyInput` as *"the bespoke explicit write would permanently defeat the
Frame-default rule in native mode"*.

**The rule:** before writing a `NATIVE_SHEET_OWNED` property, ask what the
engine's class default for it is. If your value can equal it, the write cannot
carry your intent and the intent belongs on a tag. Claims are for values a rule
could never express; they are not for values a rule already expresses better.

## What the original verification missed, and why

The demo shipped hours earlier as "verified live — four real engine
`CanvasGroup`s confirmed at `GroupTransparency = 0.6`". That reading was true and
it proved the wrong thing: **that a value could be set, not that anything
downstream of it was visible.** A property probe walks the tree and reports
numbers; it cannot report an empty rectangle. The cheap discriminator is one
screen capture of the surface under test — the defect was obvious in the first
one taken, after several hundred correct property readings had failed to find it.

See also: `docs/lessons/an-invisible-surface-declares-its-invisibility.md`,
`docs/lessons/measure-the-requirement-not-the-render.md` (the "painted at a size
nobody measured" family — this is its sibling, *painted in a colour nobody could
see*), ADR-0022 Decision 6 (the tint channel), ADR-0029 (why `GetStyled` returns
your own write from the first explicit write onward).

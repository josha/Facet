# ADR-0035 live probes — the Background Transparency preference reaching paint

**2026-08-15**, Studio `LuauUI-Showcase.rbxl`, Rojo-connected, Play session.
Every number below was produced by `execute_luau` in the **Client** datamodel in this
session. Nothing here is quoted from a commit message or from another agent.

Tiers used throughout: **MEASURED** = a value read back out of the running engine in
this session; **SOURCE** = a static contract asserted headlessly; **NOT DRIVEN** =
named because it could not be exercised, with the reason.

---

## 0. Freshness, two-sided, before anything was believed

`require` is cached per datamodel and a marker present in both the old and the new
source proves nothing (`docs/lessons/a-freshness-marker-must-discriminate.md`). So
every probe was gated on a token that exists **only** in the new version, paired with
the token it **replaced**, plus `#Source` against the bytes on disk.

Edit datamodel (what the next Play session will copy):

```
tokens.sheet_model      #Source=130802  backdropTransparency=true  PREFERENCE_RULE_PROPS=true
client.screen_target    #Source=180401  applyBackdropPreference=true
client.screen_paint     #Source=51753   refreshBackdropPaint=true
                                        BackgroundTransparency = style.extra.scrimOpacity = FALSE   <- the OLD line is gone
client.native_style     #Source=24407   native_style.ruleProperty=true
render.renderer         #Source=191971  adapter.setPreferredTransparency=true
LuauUIScenarios.preferred_transparency  exists  #Source=10278
```

Client datamodel, inside the Play session the probes ran in:

```
freshness screen_target #Source=180401  new(applyBackdropPreference)=true  old(bare scrimOpacity write)=false
```

`#Source` matches `wc -c` on disk for `sheet_model` (130802), `screen_target`
(180401), `screen_paint` (51753), `native_style` (24407) and the new fixture (10278).
The fixture file **did not exist before this task at all**, which is the strongest
discriminator available.

The strongest evidence is still behavioural, and §2–§4 are that: a value the old
source structurally cannot produce.

---

## 1. The engine property is not scriptable — MEASURED

Probed in Edit before anything was built, because the whole shape of the fixture
depends on the answer:

```
GuiService.PreferredTransparency = 1
set GuiService directly: ok=false  err=Unable to assign property PreferredTransparency. Property is read only
UserGameSettings.PreferredTransparency read  ok=false  "lacking capability RobloxScript"
UserGameSettings.PreferredTransparency write ok=false  "lacking capability RobloxScript"
```

**Consequence for every claim below.** The engine → `preferredTransparency` half of the
chain cannot be driven from a script in this environment. `src/client/roblox_env.luau`
reads the property and subscribes to its change signal; that half is **NOT DRIVEN**
here, and it is the same half `preferred_text`'s fixture cannot drive either. What
follows drives the environment fact the adapter publishes, and everything downstream
of that fact is production code.

---

## 2. NATIVE mode, isolated probe world — MEASURED

A real `screen_target.new({ nativeStyle = { host = <own Folder> } })` — an isolated
sheet host, so this probe could not touch the running showcase's own sheet. One
screen carrying an author-declared `surface = "scrim"` swatch, an opaque `raised`
panel and a `UI.ZStack{ opacity = 0.5 }`, plus a presented modal so the presenter
synthesizes its own scrim.

```
native mode active = true
adapter.setPreferredTransparency present? true
instances: scrim=true swatch=true panel=true fade=true(CanvasGroup)

                   rule      scrim styled  scrim raw   swatch styled  panel styled  authored fade GroupT
pref 1.00 default  0.4500    0.4500        0.0000      0.4500         0.0000        0.5000
pref 0.50          0.2250    0.2250        0.0000      0.2250         0.0000        0.5000
pref 0.25          0.1125    0.1125        0.0000      0.1125         0.0000        0.5000
pref 0.00          0.0000    0.0000        0.0000      0.0000         0.0000        0.5000
pref 1.00 restored 0.4500    0.4500        0.0000      0.4500         0.0000        0.5000
```

`rule` is the live `StyleRule "Scrim backdrop"`'s `GetProperties().BackgroundTransparency`.
`styled` is `Instance:GetStyled("BackgroundTransparency")` — the **engine's** answer.

What each column settles:

- **`styled` moves with the preference** → the engine really paints it; this is not a
  number the framework told itself.
- **`raw = 0.0000` at every step** → no explicit write happened. The rule is still the
  single writer of that property and ADR-0029's permanent defeat never occurs. This is
  the one-writer claim, measured rather than argued.
- **the swatch and the presenter's scrim move together** → a consumer's
  `surface = "scrim"` is honoured by the same one writer as framework furniture.
- **`panel styled = 0.0000` throughout** → an already-opaque background is untouched;
  the multiply is scoped, not swept.
- **`authored fade GroupT = 0.5000` throughout** → ADR-0035 Decision 2, measured. The
  author's number does not move, at any setting, including fully opaque.
- **restoring to 1 returns exactly `0.4500`** → the base is not being re-read from the
  composition's own output. No drift, no tail (ADR-0029 probe L4's failure mode).

---

## 3. BESPOKE mode, the other writer — MEASURED

Same shapes, `screen_target.new({ nativeStyle = false })`, where the adapter's own
explicit write owns the property and there is no rule to move:

```
native mode active = false
                   scrim raw   swatch raw   panel raw
pref 1.00 default   0.4500      0.4500       0.0000
pref 0.50           0.2250      0.2250       0.0000
pref 0.25           0.1125      0.1125       0.0000
pref 0.00           0.0000      0.0000       0.0000
pref 1.00 restored  0.4500      0.4500       0.0000

late-created scrim node raw = 0.1125   (created while the preference was 0.25)
```

Identical numbers to §2 — the two paint vocabularies agree because they call one
composition function. The last line matters on its own: a node **created after** the
preference moved is born composed, so the value is applied at paint time and not only
by the refresh sweep.

---

## 4. The shipped fixture, driven by its own steps — MEASURED

`ReplicatedStorage.LuauUIScenarios.preferred_transparency` (`#Source=10278`), built
through the scenario contract onto a real native-mode target, with its dialog open, so
the modal scrim in the table is the presenter's own — nothing in the fixture declares
it. Search scoped to the probe's own roots (an earlier pass read the *picker's* copy of
the same fixture, which is a measurement artifact worth recording: two fixtures with
the same node names were in `PlayerGui` at once).

```
           effective  backdrop swatch  modal scrim (raw)  raised panel  authored opacity 0.5
start        1          0.4500          0.4500 (0.0000)     0.0000        0.5000
setHalf      0.5        0.2250          0.2250 (0.0000)     0.0000        0.5000
setOpaque    0          0.0000          0.0000 (0.0000)     0.0000        0.5000
setFull      1          0.4500          0.4500 (0.0000)     0.0000        0.5000

report.scrimPath = /__scrim__/catcher
```

---

## 4b. The relink branch: a whole-target sheet swap re-bases — MEASURED

The branch the design most easily gets wrong. A theme controller relinks every root
onto a sheet **it** built, carrying that designer's dim and none of the player's
preference. Driven the way the controller drives it — a second sheet authored at
`scrimOpacity = 0.8`, materialized through `native_style.ensure` and handed to
`adapter.relinkThemeSheet`:

```
own sheet, pref 0.50            swatch styled=0.2250   (own dim 0.45 -> 0.45 x 0.50)
second sheet's AUTHORED dim   = 0.8
after relink, pref STILL 0.50   swatch styled=0.4000   (new dim 0.80 -> 0.80 x 0.50)
  second sheet's rule now     = 0.4
back to pref 1.00               swatch styled=0.8000   (the new sheet's OWN number, un-drifted)
```

Two things this settles that nothing else could:

- **The patch follows the linked sheet, not this target's handle.** Had it patched
  `nativeHandle`, the middle row would read `0.8000` — the new sheet untouched — while
  a real rule on a sheet nobody is wearing changed.
- **The base re-bases to the new designer's number, and the last row proves it is not
  being read back from our own output.** Returning to preference 1 gives exactly
  `0.8000`, not `0.4000` and not something drifting toward invisible.

### Cleanup note, recorded rather than tidied away

The first attempt at this probe errored on `attempt to modify a readonly table`
(the shipped styles are frozen) **after** it had mounted, and left `O26SwapHost` and
`LuauUI_O26S` behind. The successful run's own cleanup then reported them as leftovers
— correctly, because its "destroy what I mounted" set was computed as *roots that did
not exist before I started*, and those two did. Both were removed in a follow-up call
and absence re-verified:

```
removed: O26SwapHost, LuauUI_O26S, O26SwapHost, LuauUI_O26S
leftovers: NONE
PlayerGui: LuauUIStyle, LuauUI_ShowcaseBackdrop, LuauUITheme studio-neutral,
           LuauUI_ShowcaseChrome, BubbleChat, Chat, Freecam, LuauUI_PreferredTransparency
```

---

## 5. The fixture is reachable in the shipped place — MEASURED

Through the showcase's own catalogue, not by workspace attribute:

```
LuauUIShowcaseAPI.list  ->  has "preferred-transparency" in catalogue: true
showNext x22            ->  current: {"current":"preferred-transparency"}
PlayerGui roots         ->  ..., LuauUI_PreferredTransparency
18 fixture text nodes on screen, including:
  /PreferredTransparency/Page/Title            = Background Transparency
  /PreferredTransparency/Page/Stops/Opaque     = 0 opaque
  /PreferredTransparency/Page/Readout          = Setting: 1.00
  /PreferredTransparency/Page/Swatches/BackdropSwatch/Hint = answers the setting
  /PreferredTransparency/Page/Swatches/FadeSwatch/Hint     = the author's 0.5, untouched
```

A screen capture of that surface was taken in the same session.

**NOT DRIVEN: the chip press itself.** Injected mouse input did not activate the chip —
two attempts, by instance path and by computed screen centre `(328, 206)`, both
returned `Success` from the injector and left `readout = Setting: 1.00`. This is the
place's standing injected-input limitation (`XP-B3`, named in
`examples/gallery/client/init.client.luau`), not a property of this feature: the same
`apply()` the chip calls is what §4 drives, on the same fixture module, and it paints.

---

## 6. Cleanup

Every probe destroyed what it mounted and **verified absence in the same call**:

```
leftovers: NONE            (§2)
leftovers: NONE            (§3)
leftovers: NONE            (§4)
PlayerGui after: LuauUIStyle, LuauUI_ShowcaseBackdrop, LuauUITheme studio-neutral,
                 LuauUI_ShowcaseChrome, BubbleChat, Chat, Freecam, LuauUI_PreferredTransparency
```

The one remaining `LuauUI_PreferredTransparency` root is the **showcase's own** copy,
mounted by the demo picker in §5 and left exactly as the running session had it.

An earlier run errored on a `core:dispose()` that does not exist and left its host
folder behind; it was removed in a follow-up call and the absence re-verified before
any measurement was taken. Recorded because the tidy version of this file would not
mention it.

---

## 7. What is asserted headlessly instead — SOURCE

- both paint sites go through `sheet_model.backdropTransparency` rather than a bare
  token read (`src/client/*` reaches engine globals at load and cannot run in Lune);
- the declared patch scope equals the measured set of translucent backgrounds in a
  freshly built sheet, in both directions;
- the renderer pushes the fact at attach and on every change, and a garbage fact never
  reaches an adapter.

`tests/preferred_transparency.spec.luau`, 15 cases. Mutation evidence in
`artifacts/adr-0035-preferred-transparency/mutation-evidence.md`.

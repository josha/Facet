# `UI.Foreign` — live Studio verification

**ADR-0034.** This is an adapter feature: the fake target models the *handler
wiring*, not the engine, so the half that matters — a real `GuiObject` inside a
real `Frame`, the engine's own clip, and the destroyed-instance detection that has
no headless equivalent — can only be verified live. Session: `LuauUI-Showcase.rbxl`,
2026-08-15.

## 0. The datamodel really carries the source, and reading it is not running it

`require` is cached per datamodel, so "the Explorer shows the right source" proves
the file synced, never that the session executed it. Both were checked.

**Synced** (`Edit`, after the 200k-cap check — `screen_target` is 175,064 chars, so
it live-syncs):

```
render.foreign_content   len=4967    carries "a LayerCollector and cannot be a"   = true
client.screen_target     len=175064  carries authority.assertWrite("Foreign", …)  = true
render.authority         len=19206   carries Foreign = { Parent = "host" }        = true
blueprint                len=76653   carries function blueprint.Foreign           = true
blueprint_schema         len=108694  carries REFUSED_BY_CLASS                     = true
```

**Executed**: every result below is an observable only the new code can produce —
a `foreignHost` handle, the exact refusal sentences, a `ClipsDescendants` a plain
Frame does not have by default. A cached older module produces none of them.

## 1. The container is what the ADR says it is

Probe 1, `Client`, a `screen_target` built over a temporary `ScreenGui`:

```
container = Frame   clips = true   size = {0, 260}, {0, 120}   (the declared box, exactly)
foreignHost = true  cached = true  adopt = true  contentRoot = false
```

`contentRoot = false` is Decision 2 confirmed on the shipped adapter: the seam
hands back **no framework-owned instance**.

## 2. A real GuiObject, and one property written

A `TextLabel` with `RichText = true` — something `UI.Text` cannot express:

```
ADOPT ok: parent == container = true   richText = true   name = TextLabel
container children: UICorner 'UICorner', UIStroke 'Hairline', TextLabel  ← exactly ONE GuiObject
```

The two extras are LuauUI's own `surface = "raised"` modifiers on the container it
owns; the caller's instance is the only `GuiObject` child.

## 3. The refusal ladder, verbatim, on the engine

```
PART      -> LuauUI foreignHost.adopt on '/P/Pane': a Part is not a GuiObject, so this box
             — which is 2-D layout — can never draw it. For a Part/Model/Beam (the 3-D
             case) use UI.Stage and controller.stageHost(path).contentRoot(); see ADR-0024.
SCREENGUI -> LuauUI foreignHost.adopt on '/P/Pane': a ScreenGui is a LayerCollector and
             cannot be a child of a GuiObject, so it can never render inside this box. …
NIL       -> LuauUI foreignHost.adopt on '/P/Pane': no instance was passed. Pass the
             GuiObject you created — LuauUI reserves the box and never creates the content.
DESTROYED -> LuauUI foreignHost.adopt on '/P/Pane': that TextLabel has already been
             destroyed. The content is yours to own and to keep alive; …
container children after 4 refusals: 3   ← unchanged; every refusal ran before any write
```

The **destroyed** rung is the one with no headless equivalent: Roblox offers no
`IsDestroyed`, so the probe *is* the guarded `Parent` write, and it fired correctly
on a real corpse.

## 4. "LuauUI writes nothing else" — with a control that actually moves

The first attempt at this was **a check that proved nothing**: a fixed-px box in an
`edgeToEdge` screen does not move when the viewport changes, so "the adopted
instance is unchanged" was true of a frame in which *nothing happened*. Rebuilt
with a `fill`-width box and a reactive `surface`, so the framework demonstrably
rewrites its own container in the same window:

```
CONTROL — LuauUI DID rewrite its own container: true
  before Size={0, 784},{0,120}  BG=0.110,0.122,0.157
  after  Size={0, 464},{0,120}  BG=0.173,0.384,0.824
ADOPTED INSTANCE untouched by all of it: true
  before/after  Size={2,0},{2,0} Pos={0,-20},{0,-20} BG=0.769,0.361,0.251 BGT=0 Z=1 Vis=true
CLIP still holds: container abs = 464,120   adopted abs = 928,240 (2x, cropped)
```

## 5. Teardown, verified absent in the same call

```
stale handle refuses: true
  LuauUI foreignHost: the Foreign node '/Q/Pane' has been disposed — its handle is dead.
  Ask controller.foreignHost(path) again after the node remounts.
adopted content died with the box: true
probe guis left in PlayerGui: 0
```

## 6. The showcase demo, through the shipped host and a real mouse

Not the scenario runner — the **demo picker path a player takes**: chip → row →
`mountDemo`'s fixture branch. All three panes materialized:

```
surfaces: LuauUI_ShowcaseBackdrop, LuauUI_ShowcaseChrome, LuauUI_ForeignContent
/ForeignContent/Page/Panes/Rich/Pane    Frame clips=true 220x96  children=[TextLabel*]
/ForeignContent/Page/Panes/Engine/Pane  Frame clips=true 220x96  children=[ScrollingFrame*]
/ForeignContent/Page/Panes/Clip/Pane    Frame clips=true 220x96  children=[Frame*]
```

A real left-click on **Adopt a Part (refused)** put the framework's own sentence on
screen and adopted nothing:

```
/ForeignContent/Page/Refusal
  REFUSED — LuauUI foreignHost.adopt on '/ForeignContent/Page/Panes/Rich/Pane': a Part is
  not a GuiObject, … use UI.Stage and controller.stageHost(path).contentRoot(); see ADR-0024.
Rich pane children: [TextLabel]     ← the Part never landed
```

A real click on **Re-adopt all three** drove the live seam:

```
STATUS: Clip: adopted a Frame | Engine: adopted a ScrollingFrame | Rich: adopted a TextLabel
```

**This is also what caught the `init.client.luau` gap.** The demo-picker branch
builds fixtures with a *minimal ctx* and had no `foreign` seam and no
`foreignContent` pass, so the shipped showcase would have mounted three empty
panes while the scenario runner and the overflow sweep showed them full — the same
"test rig more correct than the shipped host" defect this file's own `present`-opts
comment records from 2026-08-12. The materializer was extracted into
`examples/gallery/scenarios/foreign_instances.luau` and both hosts now call it.

## 7. The finding: the theme sheet reaches content the framework does not write

The clip pane mounted **empty**. Measured, not inferred:

```
adopted Frame:  raw BackgroundTransparency = 0
                GetStyled("BackgroundTransparency") = 1
```

A native-mode surface links a theme `StyleSheet` at its root; a `StyleLink` is
ambient in the DataModel and selects by class; LuauUI's sheet carries class-default
transparency rules for the seven GuiObject classes it renders. A rule loses to an
explicit write — but the engine decides *explicit* **by value**:

```
start:            raw=0    styled=1
write 0.5:        raw=0.5  styled=0.5     ← the rule is defeated
write 0 again:    raw=0    styled=1       ← and un-defeated, because 0 IS the class default
```

**A class-default value cannot be held against a rule at all.** The demo now writes
`0.02`; the fix was confirmed live (`raw = 0.02, styled = 0.02`) and the pane paints,
cropped square at the box edge with its 28px corner rounding gone — which is the
clip proof. `tests/foreign.spec.luau` pins the materializer against reverting to a
class default (mutation M11 bites).

Whether this is an authority leak is answered in ADR-0034 Decision 7: it is not —
`GetStyled` and the raw property disagreeing is itself the proof that nobody wrote
it — but the disclaimer is narrowed in `api.md` where a caller will hit it.

## 8. Probe hygiene

Every instance mounted by a probe was destroyed and verified absent **in the same
call** (§5). Play was stopped at the end of the session.

# Plan — `compactLabel`: a button says less when it has less room

**Status: DELIVERED 2026-07-27.** Suite 2008 → **2038**; all four gates PASS;
`check_flat_baseline`, `check_prop_parity`, `check_registration`, `check_docs`
PASS; stylua clean; the built showcase contains the code. The icon set is
uploaded — 11 assets, all **Approved** and all **`Image`**. Outcome, decisions and
the one claim that was withdrawn are written up in
`docs/handoff/SHOWCASE_DEVICE_PASS.md` §3f; the two device rows it owes are
`CL-P1` / `CL-P2` in `artifacts/cross-platform-proof/review-packet.md` §7.

Director rulings taken during the build, which override §4.1 and §5 below:
* **`{ icon = … }` landed now**, not "later". `tintRole` lives on the asset record
  *inside a package*, so only the named path carries it — ship the set without the
  named form and a raw `{ image = … }` silhouette stays untinted white, i.e.
  invisible on the five light theme variants.
* **The set fills in** below package art (not opt-in), with
  `identity.standardIcons = false` as the per-package opt-out.
* **`edit`'s ASCII fallback is `/`.**
* **The table's Edit/Done toggle was wired this mission.**

The plan as briefed follows, unchanged, for the record.

---

## 1. What the director asked for

Two decisions, both explicit:

1. **A button may declare a compact representation** to use when its full label
   does not fit. Two forms, decided 2026-07-27: **a shorter string** and **an
   image**. A `glyph`/emoji form was considered and **deferred** — see §4.3;
   design the grammar so it can be added later without a breaking change.
2. **If a compact representation exists, never ellipsize.** The `…` is the
   fallback for a button that has nothing better to say; a button that *does*
   have something better must use it instead.

So the ladder, in order, is:

```
full label fits            -> draw the full label
full label does not fit    -> draw the compact representation
no compact representation  -> today's behaviour (see §2)
```

## 2. What is already true (do not re-derive this)

The label-fitting rules landed on 2026-07-27 (director round 13,
`docs/handoff/SHOWCASE_DEVICE_PASS.md` §3e). Read that section first. In short:

* A content-sized Button is measured to **exactly** its label — under
  fantasy-parchment, fantasy-ornate and glossy-touch the reserved column and the
  drawn text come out equal to the pixel. There is no slack.
* Therefore **a word is never broken and a phrase is wrapped**:
  * `src/render/renderer.luau` — `isSingleWord(props.label)` sets
    `layoutNode.singleLine` for a label-driven Button;
  * `src/client/screen_target.luau` — at the `text`/`label` **write site**,
    `instance.TextWrapped` is set from whether the label contains whitespace.
    It rides the write and not creation because the label is a reactive binding
    (the table's Edit/Done toggle flips it live);
  * the Button create branch sets `TextTruncate = AtEnd`.
* Pinned by `tests/button_shape.spec.luau`, "a Button's label wraps only where a
  break is legal".

`compactLabel` sits **on top of** that: it changes what happens when the label
does not fit, and it must not disturb either existing branch.

## 3. Existing machinery to build on — use it, do not reinvent

| Need | What already exists |
|---|---|
| Choose a layout by measuring candidates | **`UI.ViewThatFits`** — "chooses among candidate layouts by MEASURING them against the space it received; losing candidates stay mounted but are hidden and excluded from focus order" (`src/controls/contract.luau`) |
| A semantic icon a theme can repaint | `chrome_slots.attachHint(node, { slot, icon, iconSize })`. `syncIconArt` (`src/client/screen_chrome.luau`) reads `handle.decorationHint.icon`, resolves it with `themePackage.resolveIcon`, and parents theme art **over** the control's own character. `slot = chrome_slots.NO_SLOT` means "icon, but no decoration surface" |
| The framework's own glyphs | `themePackage.iconGlyph(name)` / `package.ICON_FALLBACK_GLYPHS` — **plain ASCII by construction**, enforced by a test ("the fallback glyph table can never be tofu") |
| An icon-or-short-text button content path | `UI.Button{ shape = "circle" }` already accepts "one semantic icon or up to three characters" — see `tests/button_shape.spec.luau`. **Read how it does this before designing anything** |
| Images | `UI.Image`, and `Facet.newAsyncImage` for a loaded one |
| A Button with custom content | already supported: children make it a CONTENT button (`kind = "hstack"`, sizes from children). **A focusable inside that content is a build error** |

## 4. The design questions to settle first

Answer these in the plan you write before touching code:

1. **Prop shape.** ONE prop with a closed, validated grammar — not four props.
   The two forms to support now are a shorter string and an image:
   `compactLabel = "Ed"` | `{ image = "rbxassetid://…" }`. Reject an unknown
   shape at construction (`enum-props-accept-any-string` is a lesson in this
   repo, and `blueprint_schema` is where that boundary lives), and leave room
   for `{ glyph = … }` / `{ icon = … }` to join the same table later.
2. **ViewThatFits or a renderer-side swap?** ViewThatFits is the sanctioned
   primitive and costs a mounted-but-hidden second subtree per button. Measure
   that cost before committing: a Button is not a table row, but `compactLabel`
   is a general prop and someone will put it on a list of fifty.
3. **The ASCII rule.** `ICON_FALLBACK_GLYPHS` is ASCII by construction because
   it answers for names a *package* declined to draw. A **caller-supplied**
   character is a different thing and the repo has precedent for non-ASCII
   there: `text_input`'s clear `×` (U+00D7) and `rating`'s `★`/`☆`. So a caller
   may pass an emoji; the framework may not default to one. **Emoji rendering
   in Roblox `TextLabel`s is not uniform across fonts** — call that out in the
   docs and get it on the device-verification rider, do not assert it works.

   **ALREADY ASKED AND ANSWERED (director, 2026-07-27): "if a user sets an
   emoji, could we use a font for just that control?"** Do not build this as
   part of `compactLabel`. Three reasons, all checkable:

   * `Text.font` is **deprecated for precisely this** — `blueprint_schema.luau`:
     *"reached the text-metrics measure seam but no paint seam, so an authored
     font silently made measured and painted bounds disagree."* A per-node font
     has been tried in this framework and removed.
   * `FontFace` is in `NATIVE_SHEET_OWNED` (`render/authority.luau`), so the
     adapter may not write it; a per-control font has to arrive as a **generated
     sheet rule keyed on a tag**, the way every other native paint does.
   * No emoji family is shipped or referenced anywhere — only BuilderSans,
     GothamSSm, SourceSansPro and Balthazar. Choosing one means naming an asset
     and hoping, per platform.

   **DECIDED: use `image`.** It renders identically everywhere, needs no font,
   no measurement guess and no sheet fight. The `glyph` form is **deferred, not
   rejected** — a caller-supplied verified character is legitimate and can join
   the grammar later. A per-control font, if ever wanted, is its own plan
   (measure seam + a tag-keyed sheet rule + a metric for the family), never a
   rider on this one.
4. **What `singleLine` does when the compact form is showing.** A compact form
   is a word or a glyph, so it is single-line already — but state it, and make
   sure the two seams still agree.
5. **Does `TextTruncate` come off?** The director's rule is "if there's a
   compact representation, don't use `…` at all". Decide where that is enforced
   — the adapter, the renderer, or by construction (the compact form always
   fits, so truncation never fires). Prefer by construction if you can prove it.

## 5. The first consumer, and the trap it carries

`src/controls/table.luau`'s auto Edit/Done toggle is the case that started this.
It lives in a **toolbar row** inside `/Main` at
`/…/Main/ToggleWhen/then/Toolbar/EditToggle`.

> ⚠️ **The table matches its own control by `$`-anchored path suffix**, in two
> places (its activate router and its focus-group builder). Moving or wrapping
> that node silently breaks both — the button renders, focuses, and does
> nothing. That exact bug cost a round on 2026-07-27. **Grep `table.luau` for
> its own path patterns before you run anything.**

"Who supplies the pencil?" was open, and the director answered it on 2026-07-27:
**the framework will ship a standard icon set of its own.** That is new — see §7
— and it is what makes a built-in compact form possible for this toggle.

Sequencing that matters: the toggle is **not** blocked on the icon set. It
already grows to fit its label in all nine packages (56 → 108 under Glossy
Touch), so nothing about it is broken today. Ship `compactLabel` first, prove it
in the gallery, and give the toggle a compact form once the set exists.

## 7. The standard icon set (director, 2026-07-27)

`compactLabel = { image = … }` is useless without pictures, so the framework
gains its **own** art for the first time. Everything about art in this repo is
currently per-PACKAGE, so this needs decisions, not just files.

### 7.1 One silhouette, not black + white — check this first

The director's instinct was "we might need both black and white versions for the
different themes." **Probably not, and proving it halves the work.** The icon
path already carries a **`tintRole`**: `themes.define` stores it on the asset,
`resolveIcon` returns it, and `syncIconArt` keys the painted `ImageLabel` on
`contentId#px#tintRole#pixelUnit` (`src/client/screen_chrome.luau`). The
existing packages already use it (`ornate_icon_*`).

An `ImageColor3` tint **multiplies**, so a WHITE (or alpha-only) silhouette can
become any colour a theme wants, including black — while a BLACK source can only
ever get darker. So author **white-on-transparent** and let the tint role carry
light-vs-dark.

Verify that end to end on a light package (glossy-mobile) and a dark one
(scifi-hud) before authoring the whole set. Two versions are only warranted for
an icon with internal shading, which a UI glyph should not have.

### 7.2 The set

Start from the names the framework already knows, because each has a working
ASCII fallback and a resolution path today
(`package.ICON_FALLBACK_GLYPHS`): `chevron.leading` / `chevron.trailing` /
`chevron.up` / `chevron.down`, `checkmark`, `close`, `increment`, `decrement`,
`menu`, `more`. Then add the one that started this: **`edit`** — and note it is
the ONLY new name, so it is the only one needing a new ASCII fallback invented
for it. Propose that fallback explicitly and get it agreed.

### 7.3 Where framework art lives, and how it ships

Per-package art lives at `assets/themes/<package>/` with three things beside the
PNGs: `source/`, `provenance.md`, and an `upload-manifest.json`
(`"schema": "facet-theme-assets/1"`, mapping each asset name to its
`contentId`). **Framework-owned art has no home yet** — pick one (`assets/icons/`
is the obvious candidate), give it the same three companions, and check whether
`tools/lune/check_docs.luau` needs extending: it currently enforces provenance
and manifest agreement for EXAMPLE PACKAGES, and a framework set that nothing
checks is a set that rots.

### 7.4 Getting a content ID — Open Cloud works, with `assetType = "Image"`

A Roblox image is only usable once uploaded. There are two routes and, contrary
to every doc page, **the headless one works.**

**Open Cloud (`assetType = "Image"`) — PROVEN by experiment, 2026-07-27.**

```
POST https://apis.roblox.com/assets/v1/assets
  x-api-key: <key with scope `assets`, read + write>
  multipart:
    request     = {"assetType":"Image","displayName":"…","description":"…",
                   "creationContext":{"creator":{"userId":"<id>"}}}
    fileContent = <the .png>;type=image/png
-> {"path":"operations/<id>","operationId":"<id>","done":false}

GET https://apis.roblox.com/assets/v1/operations/<id>
  x-api-key: <same>
-> {"done":true,"response":{
     "assetId":"136048244502672","assetType":"Image",
     "moderationResult":{"moderationState":"Approved"},"state":"Active"}}
```

**Do not trust the documentation on this point.** The usage guide uses
`"Decal"` for pictures; the widely-cited community reference states the
supported types are "Audio, Decal and Model"; the October 2025 "more asset
types" announcement does not mention images. All of that is stale. A live POST
with `"assetType":"Image"` returns an asset whose `assetType` comes back as
`Image`, moderated and Active — **not** a Decal.

That matters because it sidesteps the trap the whole route was written off for:
uploading as `Decal` hands back a DECAL id, `ImageLabel.Image` needs the
underlying IMAGE id, and there is no stable Open Cloud API for that conversion
(an open developer request with no staff answer). Asking for an `Image` in the
first place appears to skip the problem entirely.

**Confirmed in Studio the same day.** `MarketplaceService:GetProductInfo` on
the Open-Cloud-uploaded asset returns **`AssetTypeId = 1` (Image)** — byte-for-
byte the same classification as `81048500362779` (`ornate_panel_fill`), which
was uploaded through the Studio MCP route and is rendering in the shipped
fantasy-ornate package right now. Same type, same creator, moderation Approved,
state Active.

**So the icon pipeline can be fully headless.** A script can upload the whole
set, poll each operation, and write `upload-manifest.json` with no Studio and no
human step — strictly better than how the existing 11 assets shipped.

Everything it needs is already in place:

* **`ROBLOX_API_KEY`** is in `GameStudio/tools/API_KEYS.txt` (scope `assets`,
  read + write), and documented in `API_KEYS.txt.example`. Load it the way the
  studio's other tools do — `GameStudio/tools/manifest.py` is the shared key
  loader, and a real env var of the same name wins.
* **`creationContext.creator.userId` is `1364639953`.** Do not hardcode it in a
  committed script; take it from config or an env var with that as the default,
  the same way the key is handled.
* Keep the `method` field of each `upload-manifest.json` honest about which
  route an asset actually took, so a later reader can tell the headless ones
  from the eleven that went through Studio.

> ⚠️ **`IsLoaded` is not readable evidence in the Edit datamodel.** The first
> attempt to verify this rendered an `ImageLabel` into `CoreGui` and read
> `IsLoaded` — it came back `false`, which looked like proof the asset was
> broken. It was not: a **known-good control asset, one the shipped theme draws
> every frame, read `false` too.** The instrument was wrong, not the asset.
> `ContentImageSize` is `RobloxScript`-capability locked and cannot be read from
> a plugin thread either. When an image question can be answered by ASSET
> IDENTITY (`GetProductInfo().AssetTypeId`) rather than by decode state, ask
> that instead — and always put a known-good control in the probe, because it is
> the only thing that catches a broken instrument.

On "we'd need to set open permissions on the asset": the Open Cloud asset
documentation says nothing about permissions or distribution, and the probe
asset came back `Active` with no permission step at all. For art used in the
SAME creator's own experiences it appears unnecessary; it becomes a question the
day another creator consumes this framework's art.

**Either way, do not block on it.** Make the feature degrade correctly when an
icon has no content ID: an unresolved icon name already falls back to the
control's own ASCII character, and there is an asset-failure → fallback-tag
path. Land `compactLabel` and the tests green **without any upload**, then treat
the upload as its own step with its own evidence.

### 7.5 Two constraints on the art itself

* **Pixel packages.** Pixel Quest declares `rendering = "pixel"` with a
  `pixelUnit`, integer `SliceScale` and `snapToPixelUnit`. A smooth icon in a
  pixel theme reads as a mistake. Decide whether the set needs a pixel variant
  or whether pixel packages keep overriding with their own art (they already
  ship `pixel_icon_*`), and say which.
* **Generation.** `GameStudio/tools/image_generate.py` exists and the studio has
  a creative-director role, but **AI raster generation is a poor fit for a
  16–24px UI glyph** — it will not come back crisp or pixel-aligned. Consider
  authoring these as flat geometry instead: the framework already has `UI.Path`
  (Path2D) and `src/controls/path_shapes.luau`, and a chevron, a checkmark, a
  plus and a minus are all trivially strokable paths with no asset, no upload
  and no tint question at all. Weigh that against the image path before
  generating anything, and tell the director which you chose and why.

## 8. Done means

* `./tools/test.sh` green at the new floor, and the floor updated in **all
  three** places: `tools/lune/gate_manifest.luau`, the acceptance ledger, and
  the review packet (`docs/handoff/SHOWCASE_DEVICE_PASS.md` §7 lists this trap).
* `./tools/gate.sh cross-platform-proof` PASS (the other three gates too:
  `rich-skinning-v2`, `theme-packages-and-skinning`, `native-stylesheets`).
* `lune run tools/lune/check_flat_baseline` PASS. A deliberate geometry change
  needs a characterized entry **with a reason**; a prop appearing on every
  Button needs an `ALLOWED_ADDED_PROPS` entry.
* `check_prop_parity` PASS — a new prop must agree across `blueprint_schema`,
  `render/authority.luau`, the renderer's write site, the adapter's `setProp`,
  and `docs/reference/api.md`.
* `check_registration` / `check_docs` PASS.
* `stylua --check src/ tests/ examples/ tools/` clean.
* `./tools/build_places.sh`, then **verify the build actually contains the new
  code** — the binary `.rbxl` is compressed and `strings` on it is unreliable:
  `rojo build examples/showcase.project.json -o /tmp/x.rbxlx && grep -c compactLabel /tmp/x.rbxlx`.

## 9. Standing rules for this repo

* Every literal in a reusable control is a theme metric or a documented
  exception (`check_theme_drift` enforces it).
* A fixed dimension on anything a theme may paint a frame on is a **floor**
  (`minMax` min), never a cage — `docs/lessons/a-fixed-box-cannot-hold-a-themes-frame.md`.
* A public word that two subsystems read has ONE meaning, and something must
  assert that — `docs/lessons/one-word-two-subsystems.md`.
* `later locals are not upvalues` — a `local function` declared after a closure
  that calls it is a nil global read.
* Nothing is "verified" until it is measured. Headless measurement against the
  real theme packages is cheap and has caught every defect of the last four
  rounds; opinions have caught none.

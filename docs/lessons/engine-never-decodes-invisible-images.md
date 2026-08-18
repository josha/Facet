# The engine never DECODES an image the player cannot see — so silence is not failure

**Found:** five times between 2026-07-25 and 2026-07-26, all in
`src/client/screen_chrome.luau`'s chrome-asset watcher. The fifth (RS-A16-D5) is
what turned the pattern into a lesson.

`ImageLabel` has **no `LoadingImageFailed`** (native-substrate spike m10). A decode
SUCCESS arrives as an `IsLoaded` property change; a decode FAILURE arrives as
**silence**. So a client target that wants to fall back on a broken asset has to
infer failure from silence at a grace deadline — and that inference is only sound
where the engine was actually **asked** for the picture.

The engine draws nothing it cannot see and decodes nothing it does not draw. Five
ways art goes undrawn, every one of them found live, four of them after a fix for
the previous one:

| Face | The art is | Found |
|---|---|---|
| `detached` / `hidden` | under a hidden ancestor — a losing `ViewThatFits` candidate, a collapsed disclosure | TP matrix, 2026-07-25: three hidden action-column buttons condemned a shared asset that every visible consumer had loaded |
| `transparent` | at `ImageTransparency ≥ 1` | 2026-07-25, layered stacks |
| `zeroArea` | 0 wide or 0 tall — a bar's art before its track is laid out, or at 0% | 2026-07-25, the bar assembly |
| `noSource` | `Image == ""` — the window between a target being built and its package sheet being linked, where every decoration is tagged, rule-owned and therefore blank | 2026-07-25 |
| `clipped` | **entirely outside an ancestor whose `ClipsDescendants` is true** — a ScrollView's off-window rows | RS-A16-D5, 2026-07-26 |

**Rule: before reading silence from an image as evidence about its asset, prove
the engine was asked to decode it.** Not "is this instance visible" — the whole
ancestor chain decides, on four separate axes (attachment, `Visible`, effective
transparency/source, and every clipping rect above it).

`src/tokens/chrome_slots.judgeArt` is that decision, pure and clause-ordered; the
adapter's job is one ancestor walk that gathers the facts. It returns the FIRST
failing clause as `reason`, so a live probe reports *why* art was spared instead of
only that it was.

## Why the fifth face hid for four rounds

Off-window art is `Visible`, opaque, sized and sourced — it passes every earlier
clause. It only appears when the ENGINE viewport is small enough for the scroll
region to hide most of the fixture, and every earlier phone row had been driven
through the framework's own `setEnv` seam while the engine viewport stayed
desktop-sized. **A framework-side viewport fact does not clip anything.** Device
rows need a real device preset (`StudioDeviceSimulatorService`) or they are not
device rows.

Measured once a real preset ran (`samsung_galaxy_a06`, fantasy-ornate, 705×338): a
673×169 scroll window over a 673×507 canvas, 98 of 140 image nodes undecoded, 88
of them entirely off-window — and the framework condemned 7 assets and 4 slots, so
the ON-screen consumers of those assets went flat too. Package-independent
(pixel-quest flipped `control`, i.e. every button plate; glossy-touch flipped the
bar).

## The second half: a hide is also a "do not decode", so a false positive was permanent

The fallback repaints a slot by putting its art at `ImageTransparency = 1`. That is
face 2 of the same rule — **the framework's own hide silenced the only instrument
that could report a recovery**:

- the art never decodes, so `IsLoaded` never changes, so the change signal that
  clears the ledger can never fire;
- the grace deadline is one-shot and has already passed.

Measured: a real injected scroll decoded 65 previously-off-window nodes, and the 10
already flipped stayed `IsLoaded = false` at styled transparency 1 through two later
re-reads. Scrolling back left the bar's crown flat for the session.

**Rule: never enter a state whose own paint destroys the evidence that would leave
it.** The fix splits the fill from the hide onto two tags
(`facet-chrome-fallback` = "this slot draws its declared native treatment", carrying
the fill; `facet-chrome-mute` = "and this art instance must not draw over it",
carrying `ImageTransparency = 1`) and applies the mute to every art instance in the
slot EXCEPT the condemned asset's own **undecoded** art. Undecoded art draws
nothing, so sparing it costs no pixels and keeps its `IsLoaded` armed; art the
engine has already decoded is no instrument (its signal cannot change again), so it
hides exactly as before.

## And the deadline defers rather than skips

"Not judgeable" is not a verdict of healthy. If the deadline simply skipped
off-window art, a package whose art really is broken would leave the nodes it skins
drawing **nothing at all** — a skinned node's own plate is suppressed under the art.
So an unjudgeable decoration re-arms the same grace window and is judged the moment
it becomes judgeable (scrolled in, un-collapsed, laid out, sourced, un-muted). The
chain terminates when the decoration dies or when ANY decoration of that asset has
reached a verdict.

## The no-oscillation property, which makes a re-arming deadline safe

A node that flips to fallback and back every grace period is worse than either
steady state, so the ledger the deadline can drive is a **monotone lattice**:

    unknown --(observed silence)--> failed --(decode)--> loaded (terminal)

`state.observeAssetFailed` (the target's own inference) is refused once the asset
has ever been observed loaded, because **positive decode evidence is durable** — a
picture the engine decoded once is resident for the session, so later silence from
some drawn instance is never evidence that the asset is broken. Each asset therefore
moves at most twice per installed package and a decoration is tagged and untagged at
most twice; a cycle is unreachable rather than merely unlikely. The app's resource
provider keeps the unconditional `setAssetLoaded` edge — it is authoritative and is
not an inference. A package swap clears both ledgers.

## Detection that would have caught these

- A pure spec per clause with real geometry, not a source-text assertion: the
  decision is a function of facts, so the facts belong in the test
  (`tests/theme_asset_judgement.spec.luau`).
- A live probe that pairs the framework's own failure ledger with a judgement over
  every art instance it owns (`adapter.chromeArtJudgement`, scenario step
  `artJudgement`). `undecodedJudgeable` is the number that matters: art the target
  is entitled to call broken. On a phone under an ornate package it must be 0 while
  `byReason.clipped` is large — that pair is the D5 signature, present or gone.
- Device rows driven from real presets, never from a framework-side viewport seam.

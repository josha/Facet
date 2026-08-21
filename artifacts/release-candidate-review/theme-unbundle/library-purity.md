# THEME-UNBUNDLE — the library-purity guard, and the two defects it found

`python3 tools/check_library_purity.py` — green.

## The claim

Facet ships studio-neutral. `build/Facet.rbxm` is the engine and its own theme;
the eight player-facing skins are separate artifacts. That was already
structurally true — the model maps `src/` and nothing else — and structurally
true by accident is the state before a guard.

## What it scans, and the one distinction that matters

- `src/**/*.luau`, and every script inside the BUILT model. The model is read
  from its `.rbxmx` twin, produced by `tools/build_model.sh <output>` (the same
  project mapping, a different `-o`), because a binary `.rbxm` is LZ4-chunked and
  a byte grep over it proves nothing — the reason `check_brand_drift` builds its
  places.
- **Comments are exempt, deliberately.** This framework's comments are
  measurements: "found live under fantasy-ornate", "under classic-desktop (13 px
  BuilderSans) that is far too". Deleting the package name would delete the
  measurement, and the measurement is why the code is shaped as it is. Nothing a
  comment says can create a dependency.
- **Code is not exempt, including strings.** A diagnostic is prose that SHIPS.
- **The stamp**, which is the positive half: the model declares exactly one
  package identity, and it is `studio-neutral`.

The vocabulary is DERIVED from `examples/themes/` — every module filename plus
each module's declared `id` and `displayName` — so a package added tomorrow is
covered without editing the guard, and a renamed one leaves no stale pattern.

## The two defects it found on its first run

Both in `src/themes/package.luau`, both rewritten rather than allowlisted:

1. **line 1224** — `need("identity.id", …, 'a stable slug, e.g. "fantasy-parchment"')`.
   A shipped message telling an author their package id should look like an
   optional package they may not have installed. Now `"my-game-theme"`.
2. **lines 2099-2101** — the layered-`barFill` refusal ended
   `the \`glossy-touch\` package (examples/themes/glossy_touch.luau) is the
   shipped precedent`. That sends a consumer to a FILE THAT IS NOT IN THE
   DISTRIBUTION. The message now states the move itself: put the decorative
   layers on `barTrack`, keep `barFill` whole sliced art the percent window
   clips. The precedent survives in the comment beside it, where it belongs.

`tests/theme_layers.spec.luau` pinned the old sentence; its case now asserts the
fix names the move AND does not name a package, which makes the suite the echo of
the guard at the one message that carried the defect.

## The false positives the first pattern produced

The stamp rule began as `id = "<kebab-slug>"` anywhere in the code and reported
six: `desktop-standard`, `console-ten-foot`, `tablet-landscape`,
`compact-phone-portrait`, `compact-phone-landscape`, `phone-keyboard-occluded` —
`src/preview/device_profiles.luau`'s VIEWPORT names, which are not packages and
never were. A theme package's identity is an `identity = { … }` table, so the
stamp is read from inside one (and from an `identity.id = …` assignment) and from
nothing else.

## The negative controls

`python3 tools/check_library_purity.py --selftest`, four plants against a scratch
copy of `src/` and a scratch copy of the built model — the working tree is never
modified:

      selftest control: src/ and the built model are clean
      [BITES] a require of a reference package in src/
          -> src/themes/package.luau:1: the shipped library names 'fantasy_ornate' in CODE. The library is studio-neutral and 'fantasy_ornate' is an optional artifact a consumer may never have installed — say what the rule IS, or move the mention into a comment, where a measured story belongs
      [BITES] a package id inside a diagnostic STRING
          -> src/themes/package.luau:47: the shipped library names 'pixel-quest' in CODE. The library is studio-neutral and 'pixel_quest' is an optional artifact a consumer may never have installed — say what the rule IS, or move the mention into a comment, where a measured story belongs
      [EXEMPT] a package id inside a COMMENT (the exemption — this must NOT fire)
      [BITES] a second package stamp in the built model
          -> build/Facet.rbxm: the model stamps a second package, 'another-shipped-theme'. Studio Neutral is the only theme the library ships; every other package is its own artifact under build/themes/

**The third must NOT fire, and that is the point of listing it.** An exemption
nobody has watched hold quietly becomes a rule. The fourth plants a slug the
vocabulary does not know (`another-shipped-theme`) on purpose: planting a
reference package's id there would redden the run through the identifier rule and
prove nothing about the stamp rule — a check agreeing with you for the wrong
reason.

## The vocabulary it enforces

    check_library_purity forbids these identifiers in the library's CODE (comments exempt):
      classic_desktop: Classic Desktop, classic-desktop, classic_desktop
      compact_pointer: Compact Pointer, compact-pointer, compact_pointer
      content_alias_test: Content A/B, content-ab-test, content_alias_test
      custom_control: custom_control
      fantasy_ornate: Fantasy Ornate, fantasy-ornate, fantasy_ornate
      fantasy_parchment: Fantasy Parchment, fantasy-parchment, fantasy_parchment
      fantasy_parchment_stub: Fantasy Parchment (stub), fantasy-parchment-stub, fantasy_parchment_stub
      glossy_mobile: Glossy Mobile, glossy-mobile, glossy_mobile
      glossy_touch: Glossy Touch, glossy-touch, glossy_touch
      layered_test: Layered Test, layered-test, layered_test
      ornate_gauge: ornate_gauge
      pixel_quest: Pixel Quest, pixel-quest, pixel_quest
      scifi_hud: Sci-Fi HUD, scifi-hud, scifi_hud
      plus any of: examples/themes, examples/gallery, examples/performance
      ...and the only package stamp the model may carry is 'studio-neutral'.
    
    REWRITTEN RATHER THAN ALLOWLISTED (wave THEME-UNBUNDLE, 2026-08-21):
      src/themes/package.luau's identity.id hint used 'fantasy-parchment' as its example slug;
      its barFill refusal sent the reader to examples/themes/glossy_touch.luau, a file that is
      not in the distribution. Both now state the rule instead of naming a package.

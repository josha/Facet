# Changelog

All notable changes to Facet are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Facet's version
numbers follow the policy in
[ADR-0011](docs/adr/ADR-0011-semver-and-deprecation.md): while the library is
pre-1.0, a minor bump may change public behavior, and every retiring surface is
listed in `Facet.DEPRECATIONS` with its replacement and the earliest version that
may remove it.

The version string lives in exactly one place, `src/init.luau`, and is readable at
runtime as `Facet.VERSION`.

## [Unreleased]

### Added

- **A Roblox Package distribution channel.** Facet is now published as one Roblox
  Package asset, which is the recommended install for creators who work in Studio
  without a file sync. The asset id does not exist yet; it is recorded in
  `package/facet-package.json` when the asset is created, and the maintainer
  interface is `tools/package.sh` with `package/README.md` as its reference.
  Installing, updating, and version checking are described in
  [guide 8](docs/guide/08-without-rojo.md).
- **A standalone consumer project**, `examples/consumer/`, that builds the
  five-minute screen from the public API alone and is proved headlessly by
  `tests/consumer_standalone.spec.luau`.
- **Public project files**: `LICENSE`, `THIRD_PARTY_NOTICES.md`, this changelog,
  [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md),
  [`AGENTS.md`](AGENTS.md), a `skills/use-facet/` skill, and continuous
  integration plus issue and pull-request templates under `.github/`.

### Changed

- **Facet is licensed under the MIT License.** Material this repository did not
  create is listed with its own notice in
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- **Verification runs in four named tiers** — affected, fast, full, and release —
  through one command, `tools/verify.sh`. An ordinary change runs affected or
  fast; a change about to merge runs full; a release runs the release tier.
  `./run-tests.sh` and `./run-tests.sh --fast` still work and still mean the same
  thing.
- **The public documentation was refreshed end to end**: the README, the guide
  index and capability catalog, installation and upgrade instructions, the
  extension playbooks, and every link that pointed at internal material.

### Removed

- **The vendored copy of another reactive library, and its adapter.** Both were
  bake-off arms kept from the foundation decision recorded in ADR-0002; neither
  ever shipped in Facet's runtime, model, or Package. Facet's reactive core is
  and remains its own, in `src/core/`.

## [0.10.0] — not yet published

The version this tree reports as `Facet.VERSION`. It has not been published, so
the deprecation window ADR-0011 promises begins at its first release; until then,
[ADR-0040](docs/adr/ADR-0040-unreleased-breaking-changes.md) is the record of
every behavior change riding this version, row by row, with the spec that pins
each one.

### Added

- `Facet.Controls`, a frozen namespace of typed control constructors called as
  `Facet.Controls.<Name>(core, spec)`. Every older `Facet.new<Name>(Facet, core,
  spec)` builder still works and is listed in `Facet.DEPRECATIONS`.
- The world-fixed surface render target, `client.surface_target`
  ([ADR-0063](docs/adr/ADR-0063-surface-render-target.md)): the same flat
  two-dimensional Facet screen on a `SurfaceGui` a player walks up to.

### Changed

- **Adaptation answers for itself.** Controls that need device facts and cannot
  find an environment now refuse to construct instead of quietly assuming a
  large screen with a pointer. A `UI.Grid` given neither `columns` nor
  `minColumnWidth` lanes itself from the box it was given, and
  `UI.AdaptiveStack` requires its `axis`.
- **The ten-foot display class scales type, theme metrics, and paint**, so a
  screen written the ordinary way is legible on a television
  ([ADR-0039](docs/adr/ADR-0039-ten-foot-metric-ladder.md),
  [ADR-0058](docs/adr/ADR-0058-physical-size-aware-ten-foot.md)).
- **Roblox `StyleSheet` paint is the default render path** rather than an opt-in.
- The library is named Facet, and its call shapes moved with the name
  ([ADR-0036](docs/adr/ADR-0036-facet-rename.md),
  [ADR-0037](docs/adr/ADR-0037-public-call-shapes.md)).

`docs/adr/` holds the full decision record for each of these, and
[ADR-0040](docs/adr/ADR-0040-unreleased-breaking-changes.md) holds the complete
list rather than this summary.

## Earlier versions

Versions 0.4.0 through 0.9.0 predate this file. Their decisions are recorded as
architecture decision records under [`docs/adr/`](docs/adr/), and the version each
one landed in is named in
[ADR-0011](docs/adr/ADR-0011-semver-and-deprecation.md).

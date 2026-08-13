# LuauUI shareability and agent onboarding

**Status:** Planned after the release-candidate review.

## Purpose

Prepare LuauUI to be shared as clean source with excellent human and AI-agent
onboarding. Roblox's Package system is not a required distribution mechanism or gate.
An allowlisted source export, direct Rojo source mapping, or ordinary source copy may
be the primary path; the existing `.rbxm` build may remain a convenience.

This stage does not publish, upload, push, create a public repository, choose a
license, create a Roblox Package, or obtain a package/model ID.

## Audience and source boundary

Define three audiences before moving files:

1. **library users** need source, public types, a quick start, guides, API reference,
   examples, theme authoring, compatibility, and upgrades;
2. **contributors** need architecture, extension guides, tests, development commands,
   decisions, and current platform constraints;
3. **internal maintainers** may keep plans, raw reviews, gates, profiler data, and
   historical handoffs, but those do not belong in the shared source tree.

Prefer an explicit allowlist over deleting provenance. Consolidate durable lessons
into public guides, architecture, ADRs, or contributor docs. Keep historical evidence
in an excluded internal/archive area instead of rewriting or destroying it.

Preserve Step 13's product-language boundary and clear-writing standard. The clean
tree must not restore a retired vendor comparison, branded path, internal shorthand,
or unclear legacy paragraph. If the dedicated comparison reference ships, keep it
separate from the Roblox-first guide. Guide comparisons remain optional, labeled,
and non-authoritative.

## Supported sharing forms

The required output is a reproducible clean source tree with:

- the minimal runtime, public types, required assets, and vendor notices;
- a documented direct-source/Rojo path and ordinary source-copy path;
- the rebuildable `.rbxm` route where it remains useful;
- version, compatibility, deprecation, provenance, manifest, and checksum data;
- README, installation, five-minute example, concepts, complete guide/API catalogs,
  extension/theme guidance, troubleshooting, changelog, and upgrades; and
- one small standalone consumer project/place proving mount, theme, input, adaptive
  layout, teardown, and no RascalRally or monorepo-internal imports.

A Roblox Package, published model, registry, archive format, or hosted repository may
be documented as a later option, but none is required for PASS. Do not invent a
license. If no license is approved, finish technical preparation and mark public
release pending with a short options packet.

## Agent onboarding kit

Create `GameStudio/ui/LuauUI/AGENTS.md` and include it at the root of the shared
source tree. It is the portable baseline for agents working in LuauUI or using it in
a Roblox game. Keep it concise and link to public sources of truth. It must tell an
agent:

- where the quick start, categorized capability catalog, API reference, examples,
  architecture, styling/themes, input, device verification, and extension guides are;
- how to choose public layouts and controls, bind reactive state, style through
  native StyleSheets/theme packages, and rely on LuauUI for adaptation, focus, input,
  accessibility, motion, scrolling, and lifecycle;
- how to keep domain state/content in the game and reusable mechanisms in LuauUI;
- the normal build, test, documentation, Studio, and Rascal Rally consumer-lockstep
  workflow; and
- the forbidden shortcuts: internal imports for ordinary use, raw GuiObject
  substitutes, screen-local input/focus/layout systems, device-name branches, and
  game-local workarounds for framework promises.

Also create a thin Agent Skills-compatible `skills/use-luauui/SKILL.md` for agents
whose host supports skills. Its frontmatter must trigger for building, changing,
debugging, styling, or testing Roblox UI with LuauUI. The body contains only the
essential consumer workflow and routes detailed questions to public guide/reference
files; it must not copy the catalog or become a second manual. Add host metadata only
when a target requires it. Keep frontmatter to `name` and `description`, use concise
imperative instructions, stay well below 500 lines, and create no auxiliary skill
README or duplicate reference corpus. `AGENTS.md` remains sufficient when skill
discovery is unavailable.

At stage start, verify the current discovery and validation conventions of the
targeted agent hosts. Keep the portable files authoritative and treat host-specific
metadata as a thin adapter, not a new source of truth.

## Cleanup and drift checks

The shared tree must contain no internal plans, raw artifacts/reviews, prompt
transcripts, private/absolute paths, secrets, universe/place IDs, `.DS_Store`, caches,
stale builds, or RascalRally code/copy. Public commands and relative links must work
outside the monorepo.

Add allowlist/drift checks for accidental internal additions, missing public files,
stale agent links, undocumented public-surface changes, and artifact-size growth.
Run Step 13's language-boundary and clear-document checks against the exported tree.
Verify third-party licenses and asset provenance.

## Clean-context verification

Export the clean source tree twice and compare manifests/checksums except documented
nondeterminism. Test it from a temporary directory without internal imports. Run the
quick start, standalone consumer, relevant tests, docs/links, boundary checks, and
install/upgrade smoke where an older supported version exists. Use the real Roblox
adapter for mount, input, theme, geometry, adaptation, and teardown evidence.

Forward-test the agent kit with fresh agents that receive only the clean tree,
`AGENTS.md`, the optional skill, and public docs. At minimum:

1. have one agent build a small adaptive, themed, stateful screen using public APIs;
2. have another diagnose or extend a bounded UI behavior through the documented
   extension/test workflow.

The agents must find the right documentation, avoid forbidden shortcuts, produce
valid LuauUI, choose proportionate tests, and explain physical evidence honestly.
Revise and repeat when instructions—not the task itself—caused failure.

## Gate

Register `distribution-readiness`. It passes when the clean source export is minimal,
reproducible, usable outside the monorepo, documented, provenance-checked, and proven
through the real adapter; `AGENTS.md` and the thin skill pass clean-context tasks;
internal history remains available but excluded; Rascal Rally remains synchronized;
and legal, physical, or human pendings are precise. No package creation or publishing
action is part of PASS.

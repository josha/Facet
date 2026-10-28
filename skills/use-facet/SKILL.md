---
name: use-facet
description: Design, build and refine Roblox game UI and Studio plugin interfaces with Facet, including touch, pointer and controller use.
---

# Use Facet

**Find the capability first: Facet → Compose → native Roblox → custom code.**
Search Facet controls, options and helpers. Use Compose for composition, state
and lifetime, then native Roblox for an unmet need. Build custom behavior only
for the remaining gap.

## Start with a complete task

Read the brief and existing game. Identify the player's decision, its accepted
outcome and the return path. Preserve required behavior and working routes.
Default to a visually authored game interface. Derive concrete type, material,
silhouette and subject cues from its world and existing art. A color swap on
uniform rounded cards is insufficient. Give every item, record and stat a visual by default: its image or model, else a
theme glyph, emblem, swatch, pips or bar. Choose text-only deliberately when
words serve the decision better; give it expressive type, hierarchy and composition.
Never join facts in one caption: a value leads in `numeral` and its label follows.

| First task | Read and adapt |
| --- | --- |
| Game screens: hub, shop, garage, customize, HUD, tutorial | [Game screens](references/game-screens.md): the page shell and tested code for each screen, and the rules every screen shares. Read it before the first screen |
| Browse records, products or equipment | [Collection](examples/collection.luau): supply game image/model subjects; use `false` with an `icon` glyph per record when no art exists. [Riverbank](assets/riverbank-theme.luau) is one example identity. |
| Inspect a selected object | [Inspection](examples/inspection.luau) with its [Field Station theme](assets/field-station-theme.luau): useful subject scale beside a decision |
| Use image-based surfaces and subjects | [Game themes](references/game-themes.md): optional Pixel Quest theme builder with Collection's subject renderer |
| Show stats, ranks, records, prices or progress | [Information display](references/information-display.md) recipes and the [Standing](examples/standing.luau) card |
| Act during play, then open brief help | [Exploration](examples/exploration.luau), using the same Riverbank app/theme as Collection |
| Another task | [Patterns](references/patterns.md): choose its information relationship and example |

Give the theme a display family on `title`, `heading` and `numeral` (and on
`label` or `control` for short labels), an accent for action, a `selection`
color for the current choice, and one visible edge or material on every panel
through a theme rule; resolve `report.advice` before the first capture. Keep
the world in view around bounded pages. [Neon Circuit](assets/neon-circuit-theme.luau)
is one example for a night-time sci-fi game; [game themes](references/game-themes.md)
explains what makes an identity visible and lists fonts that load.

Read [runtime essentials](references/runtime.md) once. Transfer the example's
relationships and ownership, then supply this game's identity, records and
callbacks. Keep a fitting existing theme. Examples are alternatives, not required
skins or decoration quotas. Read only the chosen route; subject-art implementation
can remain outside the layout-reading context.

For phone support, use [compact compositions](references/compact-compositions.md)
before building the first form. Budget the body after navigation and native
controls so useful content and its action appear before a long introduction.

Use [capability routes](references/choose.md) for the exact contract needed;
search unknown names with `lute run tools/facet docs --search TERM`.
Retain answers. Do not read the whole manual or guess filenames.

For richer navigation, forms or spatial UI, use
[advanced compositions](references/advanced-compositions.md) as needed.

Use typed constructors and reactive callbacks. Keep durable selection, drafts
and accepted state outside disposable pages. Give unrelated tasks separate
scroll state. Connect request, pending, rejection, retry and acceptance to real
game behavior. Demonstration callbacks do not implement a production transaction.

## Author in Studio without a filesystem

When Studio MCP is the only tool, every byte you send or read back stays in
context and is paid again on each later call.

- Put each screen in its own ModuleScript (one folder of them, each under
  about 250 lines) and keep the client script to mounting and routing.
- Write a script once. Change it afterwards with an exact-text patch; never
  resend a whole Source or return one. Find text with a line-range read.

```luau
local function patch(target: LuaSourceContainer, old: string, new: string)
    local source = target.Source
    local first, last = string.find(source, old, 1, true)
    assert(first ~= nil and last ~= nil, "patch: no match")
    assert(string.find(source, old, last + 1, true) == nil, "patch: more than one match")
    target.Source = string.sub(source, 1, first - 1) .. new .. string.sub(source, last + 1)
end
```

- Return small probe results: counts, a few names, one error line. Never return
  `GetChildren()`, a whole tree or a dump.
- Read the documents for a route in one call, then retain them.

## Correct the task before sharing its layout

Capture the first complete task in its real world at wide, portrait and short
sizes before extracting a common page shell or repeating it across destinations.

Reject generic or bland results: could this capture belong to an unrelated game?
Run the [critique-ui skill](../critique-ui/SKILL.md): it collects captures and
`Facet.review` findings and has a fresh reviewer score them. In Studio only, run
`return Facet.review.screen().text` in the Client data model. Correct the
largest cause before copying the layout, then compare actual before/after
captures. State what visibly changed; a correction to a HUD
does not validate a catalogue. Missing captures leave this step unverified.

Share theme, controls and accepted-state behavior. Give each task its own
footprint: a subject and decision, useful collection space, or a brief floating
confirmation. Keep sequential steps inside one stable navigation surface.

Exercise acceptance, rejection, cancellation and return through real input.
Inspect restored subjects and state. Check affected compact forms, large text,
focus and native-control clearance using runtime essentials. Measure performance
after successful returns. Report tested scope; missing evidence stays unverified.

For a Compose Design module, read [the design editing contract](../compose/references/design.md)
before changing it. Keep its design shapes and run `lute run tools/facet design check <module>`
so the Studio editor stays in sync.

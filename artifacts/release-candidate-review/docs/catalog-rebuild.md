# Guide catalog rebuilt from the live surface — wave T12

**What this file records:** how `docs/guide/README.md` was rebuilt, what the new
drift check enforces, and the before/after numbers.

## The source of truth

The catalog was derived from the live exported table, not from the old prose:

```sh
lune run tools/lune/_probe_public_surface        # 240 lines: every export, every
                                                 # namespace member, the ledger
lune run tools/lune/check_registration_cli       # api.md vs the live surface
```

The surface at 0.10.0: 19 `Controls.*` members, 51 `UI.*` members, 13 top-level
functions that are not on their way out, 15 namespace tables, `VERSION`,
`DEPRECATIONS`, and 7 extension playbooks. The 19 `new<Name>(Facet, core, spec)`
aliases are deprecated in `Facet.DEPRECATIONS` and are deliberately NOT catalog
rows: the catalog teaches the shape a new author should write, which is
`Facet.Controls.<Name>(core, spec)`.

## Before and after

| | Before | After |
|---|---|---|
| Composite controls named in the index | 5 of 19 | 19 of 19 |
| `UI.*` members named | ~12 of 51 | 51 of 51 |
| Top-level exports named | ~14 | all 30 non-deprecated |
| Extension playbooks linked | 6 of 7 (`new-primitive` missing) | 7 of 7 |
| Links into `docs/reference/api.md` | 3 | 71, every one anchor-checked |
| Catalog entries a checker verifies | 0 | 107 |
| Stale entries removed | — | the spec-timing pointer into a retired plan document |

The six categories are the ones the release plan names: layout and composition;
display, input and value controls; collections, scrolling, selection, reorder and
drag/drop; presentation, navigation, focus, input, adaptation and accessibility;
styling, theme packages, rich skinning, animation and feedback; reactive state,
lifecycle, async resources, replication, render targets and tools.

Each row states in one plain sentence what the capability does and links its
reference section. Availability and evidence limits stay in the index's own
"What the evidence does and does not cover" section, in ordinary words: strict
authoring since 0.5.0, headless performance scenes that screen trends only,
empty device slots, and the standing physical-device input gate.

## The drift check (check_docs obligation 10)

`tools/lune/check_docs.luau` now requires the live table and fails in four
directions. It reads `Facet.DEPRECATIONS` to skip retiring surfaces, so an alias
on its way out does not have to be advertised.

| Direction | Failure it catches |
|---|---|
| a. every live capability is named | a shipped control the index does not mention |
| b. every named capability still exists | a row for an export that has been removed |
| c. every api.md link resolves | a catalog link to a heading api.md does not have |
| d. every playbook is linked | an extension playbook nobody can find |

### Proof that it bites

Run against the live tree with one synthetic edit each (the checker's
`fileOverrides` seam, the same one its other rules use):

```
live ok: true   catalogEntries: 107   links: 162
dropped `Controls.Chip` row      -> ok: false, 1 problem:
    docs/guide/README.md: the capability catalog does not name 'Controls.Chip'
invented `UI.Sparkle` row        -> ok: false, 1 problem:
    docs/guide/README.md: the capability catalog names 'UI.Sparkle', which the
    library no longer exports
api.md#no-such-heading link      -> ok: false, 1 problem:
    docs/guide/README.md: links docs/reference/api.md#no-such-heading, which is
    not a heading in that document
unlinked new-primitive.md        -> ok: false, 1 problem:
    docs/guide/README.md: the extension-playbook list does not link new-primitive.md
```

The same four are cases in `tests/theme_docs.spec.luau`, so they run on every
suite rather than on a command somebody remembers to type.

## api.md exhaustiveness

`check_registration` already required api.md to document every public export and
every namespace member under its own `###` heading, in both directions. It passes
unchanged (38 controls, 99 exports documented). No export was missing, so this
wave added no api.md entries for coverage; the api.md edits in it are the
product-language sweep, recorded separately.

# Facet API and architecture consistency

**Status:** Planned after the parallel Sponsor build and before new public features.

## Purpose

Facet should feel like one framework. After learning one primitive, control, or
extension workflow, an author should be able to predict how the next one is named,
constructed, bound to state, styled, adapted, tested, and disposed.

This stage creates the written rules future work must follow, audits the existing
surface against them, and adds automated checks where a rule can be checked. It does
not redesign a working API merely to make every signature look identical.

## Required outcome

Publish one concise API constitution that covers:

- names, argument order, return shapes, and when a feature is a blueprint primitive,
  composite control, modifier, service, or adapter;
- public spec types, required versus optional fields, defaults, validation errors,
  and the use of reactive values;
- state ownership, identity, scopes, cleanup, error containment, and server/client
  boundaries;
- semantic actions, focus contributions, adaptive behavior, accessibility intent,
  localization, theme roles, and property authority;
- how engine-backed behavior stays at the Roblox adapter edge while deterministic
  decisions remain testable in plain Luau;
- extension, naming, namespacing, versioning, deprecation, and compatibility rules;
- the minimum tests, Studio evidence, documentation, and registration required for
  each kind of public addition.

The rules must use current Facet examples rather than abstract slogans. Explain each
approved exception and why making it uniform would make the API worse.

## Consistency audit

Inventory every public export, blueprint constructor, composite control, service,
modifier, callback, result object, and extension seam. For each, record:

1. the pattern it follows;
2. any inconsistency and its user cost;
3. whether it is an intentional exception, a compatible repair, a deprecation, or a
   future breaking-change candidate;
4. the tests and documentation that prove its contract.

Pay particular attention to inconsistent constructor shapes, unnecessary `any` at
public boundaries, duplicate vocabulary, callbacks with different meanings under the
same name, undocumented lifecycle ownership, accepted-but-ignored properties, and
features that require internal imports.

Fix small, clearly compatible defects in this stage. Use the existing deprecation
policy for migrations. Do not perform broad renames or a breaking API cleanup. Put
larger proposals in a decision ledger with a recommendation and migration cost.

## Agent-friendly enforcement

Turn stable rules into useful tooling rather than relying only on prose:

- extend the public-surface and documentation drift checks;
- make scaffolds and extension guides emit the canonical shape;
- add focused checks for patterns that can be detected reliably;
- ensure errors name the broken rule and the intended fix;
- run a fresh-author exercise in which an agent with only public documentation adds
  one small composite control without importing internals.

Do not write brittle style checks for judgment that needs review. The goal is to make
the right pattern easy to discover and hard to violate silently.

## Evidence and gate

Register `api-architecture-consistency`. Its evidence includes the constitution,
complete surface ledger, compatible fixes and deprecations, decision packets,
tooling checks, the fresh-author exercise, full suite, documentation check, and
fresh-context architecture and phase-gate reviews. Use Studio only where a fix can
change visible, input, layout, adapter, or lifecycle behavior.

The gate passes when every current public item is classified, the rules are linked
from the guide and extension docs, compatible defects are fixed, larger changes are
not smuggled in, and a future agent has one authoritative place to learn how a new
Facet feature should fit.


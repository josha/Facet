# The private Package, proven (DR-33) — 2026-08-31

**Asset 106883918130790**, created privately for user 1364639953 through
`tools/package.sh create --confirm` at commit `3be1344` with all 15 guards
evaluated and passing; receipt `package/receipts/0.10.0-3be1344.json`
(revision 1, moderation Approved, route open-cloud).

**Inserted by id into a clean place and probed (Studio, 2026-08-31):** the root
is the `Facet` ModuleScript carrying a genuine `PackageLink` (VersionNumber 1);
`Distribution` attributes byte-match the receipt — Version `0.10.0`,
SourceCommit `3be13441f88a…`, SourceHash `c34d2a3172f0…`, BuildSchema
`facet-package/1` — with the `LICENSE` and `THIRD_PARTY_NOTICES` values inside;
171 ModuleScripts (170 descendants + root), 16 Folders, no `vendor`, no
`fusion_adapter`, no `imperative`, no spec files; `require` succeeds and the
reactive core runs (probe returned 42).

**Same-id update mechanics:** proven end to end on the spike twin asset
83627005624999 — a distinct `.rbxm` PATCHed to revision 2 through the same
API; byte-identical content is silently deduplicated, which is why the publish
guard demands a positive version edge (`spike/spike-package.md`).

**Declared, with their closing procedure, for the first real release
(`tools/release.sh`):** publishing revision 2 of THIS asset (no honest content
delta exists today, and identical bytes make no revision), then in Studio:
an unmodified copy with AutoUpdate ticked receives it; a locally modified
copy reports rather than updates. Both are one release plus two Properties-
panel checks away, and the release command's checklist names them.

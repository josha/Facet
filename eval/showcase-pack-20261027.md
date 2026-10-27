# Adventurer's Pack completion evidence

This change is separate from the guide publication in #271 and capture retention
in #276. Both are merged. The Pack uses existing equipment art and the selected
showcase theme. It does not make image-heavy themes a requirement for authors.

## Change

The collection pairs recognizable equipment with names, decisive facts and
equipped state. Inspection centers a bounded subject and comparison, with an
emphasized Equip action. Filters use a child page in the existing navigation
stack. Compact forms retain the loadout sheet and explicit hotbar assignment.

Actual short-landscape captures prompted removal of the repeated objective and
warmth summary from the short catalogue; the loadout retains both. Two useful
columns fit where space permits. Separating Move from the item button preserves
inspection activation. Move appears only beside a visible loadout drop target.
The active category remains visible on Filters, and reset clears collection
scroll even when query and category already have their default values.

The implementation uses existing Facet controls, native scrolling, the public
collection scrollReset option, and Compose conditional ownership. It adds no
layout system, test harness, theme assets or dependency changes.

## Native evidence and limits

Raw evidence is retained locally under
`artifacts/showcase-pack-finish-20261027/`, including failed attempts. These are
showcase checks, separate from the bounded author assessment. Only newly owned
Studio instances were operated; CozyMower was not touched.

At Pack source SHA256
`5cd198417d07141458b50a272f7f7da08d76d87a63e69b4d8156d5b6efea1e74`,
`task-final-native/report` records complete desktop and portrait tasks passing:
inspect, equip, Back and reopen, retained query, empty search, category filter,
explicit hotbar assignment and activation, cave entry and reset. Actual captures
are in that run's `capture-review` directory. The earlier source and failures
remain in `before/`, `task-native/` and other dated run directories.

The same run failed to reveal a later Equip action in short landscape.
`landscape-swipe-native/report` then reached hotbar activation but failed its
visible acknowledgement assertion. The full landscape task is incomplete;
neither failure is promoted to a proven product defect. The Mac locked during
this work and blocked the remaining native inspection and keyboard-driven
Studio Controller Emulator check.

Final source `879fb3ed72c17d1a3b2534a53cfa5b4732d6678fdc799277b7bf075fcb94cee1`
adds the reviewed filter label, empty-state wording and compact Move/hint fixes
after those captures. Those last changes do not yet have a native pass. Controller,
direct drag, large-text, reduced-motion and complete transition coverage remain
unverified. The screenshots demonstrate actual themed subjects and a distinct
Equip action; broader aesthetic quality remains a subjective judgment.

## Automated validation

Code commit: `6ee25cfec68089a06f81e71d928266927cb4c334`, based on merged main
`2721d185b051c9c07deb0baa461fd23a7b9a0d0b`. The existing registered showcase
spec now checks retained equipment, acknowledged slot assignment, navigation,
active category and complete reset including native collection scroll.

The full gate ran after pinned tools and type definitions were prepared. All
2,664 suite cases, 776 tool cases and 201 negative type probes passed; 1,312
type-check targets had no blocking diagnostics. The only failed producer was
the inherited NavigationStack reference budget: main also had 4,199 bytes
against a 4,096-byte limit. Commit `14c6a31ae50d8818bfe7c501124f5c365a91a805`
compressed equivalent wording to 4,077 bytes. The focused docs-nodes check then
passed with zero findings. The full gate was not repeated after this prose fix.

The gate selected 40 of 43 producers: 37 passed, one failed and two deferred
(reference-host timing and native Studio); three release producers were not
selected. The standalone benchmark ran alone and passed. Its
heap observations do not prove retained memory. Logs are retained under
`artifacts/showcase-pack-finish-20261027/final-gate/`. This receipt does not claim
a full native or release pass.

Local package build/status completed for Facet 0.12.0 (381 modules). Status
correctly reports native Studio pending and that the earlier failed gate does
not attest the final tree. No package was published. All 12 generated place
files were archived with hashes and restored to their initially clean state.
Original dirty worktrees and frozen assessment evidence were preserved.

## Author assessment

No additional author run or Plain rerun was started for the showcase. The prior
bounded Sol 6.1 Medium run retained its 1,800-second deadline and used 10,449,057
total tokens versus historical Plain's 6,830,115: 1.530 times Plain, above the
1.30 target. The latest guide changes remain improvement hypotheses. Frozen
assessment sources, submissions and evidence remain unchanged.

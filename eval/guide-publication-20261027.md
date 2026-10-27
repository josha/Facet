# Guide publication scope and evidence

This revision publishes the guide improvements after the bounded assessment.
It does not claim that the guide has beaten Plain or that its new visual bias
has received an independent author assessment.

## Authoring direction

The skill now defaults to a visually authored game interface. It directs authors
to derive type, material, silhouette and subject cues from the game, prefer useful
existing images/models, and reject uniform recolored cards as sufficient identity.
Text-only remains an intentional choice for decisions served by words or numbers;
it still needs deliberate typography, hierarchy and composition. Image-heavy
themes and new art production are optional.

Capture/correct requires finding and fixing a visible cause of a generic result
before copying its layout. Separate tasks may use different footprints;
sequential steps keep a stable navigation surface. The four core guidance files
total 3,496 words, 41 fewer than the preceding revision.

## Included changes

- Complete Collection, Inspection and Exploration examples with Riverbank and
  Field Station identities, distinct subject/facts/ownership/action treatment,
  and bounded task compositions.
- Collection accepts a fresh reactive subject renderer or explicit text-only
  mode. Browse and detail share outer surface geometry; the caller retains
  navigation, accepted state and transactions.
- The author kit exposes skill examples/assets and existing theme builders as
  native StringValue source, alongside Markdown. Its integration test builds a
  real Rojo place and verifies normalized source contents and classes.
- Stage respects effective GUI visibility, retains its scene/camera while hidden
  and restores its camera on return. Native GUI visibility/ancestry and Compose
  observation/ownership supply this behavior; no new lifecycle facade is added.
- Card collection wrappers auto-size on the main axis, preserving the allocated
  cross extent and existing animation clearance. Native AutomaticSize and the
  existing collection measurement path are sufficient; no new layout mechanism
  or dependency change is introduced by this fix.

The local Adventurer's Pack showcase redesign is excluded. Its short-landscape
layout and some later input assertions remain incomplete. Pixel Quest is offered
as an optional theme builder paired with Collection, not as that unfinished
showcase task. The separate evaluator capture-review change remains PR #276.

## Demonstrated native evidence

Evidence predates integration with current main and is retained in the original
guide worktree's ignored artifacts. It is targeted evidence, not full native
coverage of the integrated publication tree.

- The original Pack reproduced an empty collection after equip/Back. A hovered
  card grew from 280 to 4,499 pixels wide inside a 225-pixel row, inflating the
  viewport clearance until no rows remained. Bounding both wrappers corrected
  the same original fixture, independently of the excluded showcase redesign.
- Stage return and effective-visibility checks, and Collection's portrait
  default/custom-image flows, exercised restored subjects. Custom-image portrait
  acceptance and two returns retained query, selection, subject and ownership.
- Text-only initially exposed a grid-only option passed to VirtualList. The
  corrected portrait case exercised cancellation, rejection/retry, acceptance
  and two returns, with no art allocation.
- The user identified mismatched navigation heights. Actual portrait headers
  shifted 96 pixels for text-only and 6 for images between browse and detail.
  The final shared surface layout measured the same x24/y129/341-by-44 header
  rectangle through browse, detail and Back in both modes. The final traces
  showed no Y/height changes. This does not establish all device forms or every
  animated descendant.

Detailed receipts are under `artifacts/guide-themed-path-20261027/`,
`artifacts/pixelquest-repair-20261027/` and the earlier guide validation artifact
directories. They retain failed attempts and exact source coverage. No frozen
evaluation input, submission or capture was rewritten. No CozyMower window was
operated.

## Assessment outcome

The preceding bounded Facet author used Sol 6.1 Medium and the unchanged
1,800-second deadline. It completed in 1,795.832 seconds, using 10,449,057 total
tokens versus the existing Plain run's 6,830,115: 1.530 times Plain, above the
1.30 target. Custody checks passed. Missing controller/native-chrome evidence
remained incomplete; no visual-judge win was inferred. Plain was not rerun.

The latest guidance changes are improvement hypotheses. They have not received
another author run, and no larger assessment batch was started.

## Publication validation

Current-main integration and repository checks are recorded under
`artifacts/guide-publish-20261027/` in the isolated publication worktree.

- Pinned tools and type definitions were prepared before the full gate. Types
  passed for 1,311 targets with no blocking diagnostics and 201 negative probes.
- The full gate selected 40 of 43 producers: 36 passed, two failed on the same
  NavigationStack documentation byte budget, and two were deferred (reference
  host timing and native Studio). Three release producers were not selected.
- The node was compressed to its 4,096-byte limit. The docs check and both failed
  tool cases then passed. The final kit integration case also passed after its
  source comparison was corrected for normalized CRLF contents. These focused
  reruns do not constitute a new complete full-gate pass.
- All 89 strict documentation samples, skill validation, links, format and diff
  checks passed. The standalone benchmark ran alone and passed. Local package
  build and status completed; no package was published.
- The 12 initially clean generated places were archived with hashes and restored.
  No showcase source change is included in this publication revision.

Fresh pull-request CI is required before merge. A main-branch merge does not
turn targeted native coverage into complete release evidence. The dated evidence
above supersedes earlier receipts only for the scope and snapshots it describes.

The first fresh CI run caught a Linux kit-test setup failure: the Rokit shim
could not locate Rojo from the temporary kit directory, which has no toolchain
manifest. The test now launches the pinned tool from the repository and passes
absolute kit project/output paths. This retains the exported-place assertions.

# Verify UI fixture adoption receipt

Facet uses the same testing library as Compose for shared engine test mechanisms.
This change removes Facet's implementations of clone allocation and reference
remapping, tags, class and ancestor lookup, focus state, style maps and path storage. Verify also supplies reflection
registration, datatype validation and the structural engine adapter. Two benchmark
entry points use `Verify.performance.summarize` instead of local percentile code.

The baseline is Facet `ca576200f8b30f003b920f885885ac83f701a895`, after PR 71.
Verify is `ffff3ac8ce0df72b5669657fdf293f60cbab5933`.
Compose is `49668e8cb27d5e2b273be8fe057145a44ffde562`.
Both snapshots use the existing offline archive and hash checks.

The native engine fixture has 562 lines, down from 634. This is a net reduction
of 72 fixture lines. The count excludes new tests, documentation and generated
snapshots. It is not the net line count of the pull request.

## Remaining adapter code

Lune reflection does not supply every native default or every current UI class.
The fixture keeps explicit defaults, UIShadow and corner schemas, native datatype
constructors and geometry, text and input injection. Read-only text-fit and
transparency probes accept fault inputs used by defensive tests. It adapts signal arguments
and preserves instance identity between fixtures. Animated page changes remain
an explicit instant fake. A clone adapter retains style and path fake state
and clears the viewport camera. Verify owns allocation and reference remapping. These contracts do not prove rendering or animation.

The drag fixture uses a declared Camera with an injected ray method. Topbar
inset probes use Rect. Alignment bindings start with a valid native enum. Editor
tests reopen the editor before focus, and search tests release focus through the
engine method. Existing assertions remain; reuse and alignment checks are added. The integration check covers cloned references,
nonarchivable descendants, tags, attributes, focus, isolated style maps, path
storage and connection cleanup. Existing case IDs and examples remain. Hover assertions keep the centering
contract through native AnchorPoint.

## Hover behavior

Roblox `UIScale`, `GuiObject.AbsoluteSize` and `GuiObject.AnchorPoint` supply native
scale and centering. A one-unit native Frame reports the scale applied by the
engine. Collection measurements use that observation instead of dividing delayed
geometry by a newly assigned scale or row height. Integer position offsets no
longer step during hover. Empty action plates no longer paint over the next row.
Compose owns reactive bindings and cleanup. Facet uses its existing batched
geometry observation mechanism. Motion values stay in theme tokens.

Live Studio reproduces the row feedback loop on merged main and before PR 70.
The strengthened collection case fails on unchanged main and passes with the fix.
At 1279 by 720, four themes and rapid Lantern Oolong to Amber Harvest transitions
keep mounted card rectangles steady. In the final pixel comparison, Mistral Mint
and Copper Chai are identical at rest and with either top card hovered.

The registration census retains all 3,765 IDs. The native full plan selects 150
sources and 3,731 cases. The separate Toast source and existing release-only skip
remain. Historical assertion parity and complete Studio/device coverage remain
not established. See [verification scope](../docs/guide/18-verification-scope.md).

The latest Verify runner targets Lute. Facet keeps its Lune host adapter and
committed producer plan. Moving hosts is outside this adoption change.

## Validation at PR creation

The full behavioral suite reports 3,730 passed, zero failed and one existing
release-only skip. Type analysis reports 712 targets and zero blocking
diagnostics. All 181 public negative probes are rejected. Package build,
status, verify, canary and purity checks pass. The full gate is still running
its final performance and evidence producers.

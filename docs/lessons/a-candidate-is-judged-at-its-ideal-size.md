# A candidate is judged at its ideal size, not at the size it could be squeezed into

**2026-08-14 · `ViewThatFits` × `shrinkWeight` · ruling 2, director: "follow the declarative behaviour"**

## The symptom

Adding `shrinkWeight = 1` to a `ViewThatFits` candidate's **children** changed
which candidate won. Swept 150→420 px in 10 px steps on a two-candidate fixture,
the winner flipped at **10 of the 28 widths (290–380)**.

Nothing about the candidate had changed. The prop was declared one level *down*,
by whoever authored the row — often not the person who wrote the `ViewThatFits`.

## The mechanism

`chosenCandidate` picks the first candidate whose `measure` fits the offer.
PASS 1.5 — the measure-side shrink, landed 2026-08-12 — makes a stack that can
absorb its own deficit **report the squeezed extent** rather than the natural
one. So a candidate that did not fit reported a number that did, `fitsW` went
true, and it won.

This also falsified a sentence already shipped in `docs/plans/parity-round2.md`
§2.4: that `ViewThatFits` "picks its candidate before any of this and is
therefore unaffected". True of the arrange-only shrink it was written for; false
from the day the measure-side mirror landed.

## What the reference framework actually does — the evidence

The ruling was to follow that framework, so the first job was finding out what it
does rather than assuming it.

**The vendor's own reference** for `ViewThatFits`
(cited in the comparison document, §16):

> "ViewThatFits evaluates its child views in the order you provide them to the
> initializer. It selects the first child whose **ideal size** on the constrained
> axes fits within the proposed size."

An *ideal size* is defined by the layout protocol as the size a view reports when
its parent proposes **nothing** (`ProposedViewSize.unspecified`). Fatbobman's
"Mastering ViewThatFits" (<https://fatbobman.com/en/posts/mastering-viewthatfits/>)
states the mechanism and both of its halves:

> "ViewThatFits queries each subview for its ideal size (the required size
> returned based on the unspecified proposed size)."

> "ViewThatFits makes judgments based on ideal sizes, but the selected child view
> is not rendered in its ideal state during final display."

> "ViewThatFits passes the proposed size provided by the parent view to the
> selected subview as its own proposed size."

> "If none of the subviews meet the condition, then the last subview in the
> closure is selected."

The last point is corroborated independently by Nil Coalescing
(<https://nilcoalescing.com/blog/AdaptiveLayoutsWithViewThatFits/>): *"If none of
the given views fit in the space, the last view will be displayed even if it
doesn't fit."* — which is already this framework's rule 8.

**The consequence that matters here.** Because judgment happens at the ideal
size, every mechanism that makes a view *smaller than its ideal* is invisible to
the choice: text truncation, `lineLimit`, `minimumScaleFactor`. This is the
famous `ViewThatFits`-with-`Text` gotcha — the whole reason articles exist
teaching a hidden-measurement workaround for it. That framework does **not** consider
"but it would fit if it truncated".

`shrinkWeight` is this framework's member of exactly that family: a declared
willingness to be compressed below the natural size. So its answer to the
ruling is unambiguous, and it happens to agree with the recommendation that was
offered as a hypothesis: **measure candidates unshrunk**.

## The fix

`ctx.fitProbe` — true only while `chosenCandidate` is asking its question. It
suppresses PASS 1.5 and nothing else, and it is the **fifth writer** of
`ctx.scopeKey`, because the probe is a different question about the same node at
the same offer and must not share a memo entry with the real measure.

Picking is unshrunk; showing is not. The probe is off again before the winning
candidate is measured and arranged, so the winner still receives the real offer
and compresses normally — the second half of that rule.

## Where this framework still differs, on purpose

`chosenCandidate` measures candidates against **the container's own definite
box** (a finite offer), not against an unspecified proposal. So a wrapping `Text`
inside a candidate reports a *wrapped* width — never wider than the box — and the
candidate is rejected on its **height** instead of its width. That framework would
reject it on width.

The two end up rejecting the same candidates in the shapes that ship, and the
finite-box rule is itself a fix from director round 2026-07-24 (measuring against
the parent's larger offer made measure and arrange disagree about the winner).
It is recorded here as a **known, deliberate divergence** rather than left to be
rediscovered: if a future case needs true ideal-size measurement, this is the
line to change, and this paragraph is why it was not changed today.

## The general lesson

When a container asks "does this fit?", **the answer must not depend on how much
the thing could be made to suffer.** A compression mechanism is a promise about
what to do *after* a decision, and letting it participate in the decision makes
the decision depend on props the deciding author does not own.

And: the sweep is the assertion. The pinned test walks **all 28 widths** and
names any width where the two runs disagree. Three spot checks would have passed
while the divergence band merely moved — and the band did move (150–380 after a
concurrent change to the shrink floor) before the fix landed.

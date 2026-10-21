# Sol 6.1 Medium slice, fourth pair

Facet again passed all 13 universal checks, compared with 1 for Plain.
It used 1.426 times Plain's tokens and 1.084 times its author wall time.
The efficiency targets remain unmet. Required-check success does not mean
that all diagnostic requirements or headline rules passed. The completed
blind judge preferred Plain on both devices in both image orders.

Both arms ran fresh at source `6a47270c1a9669cd2098d2cba8b22b652af1fd5b`,
one task, seed 1, sequentially, with Sol 6.1 Medium. The evidence directory is
`artifacts/facetbench/slice-sol61-medium-4`. Both authors completed successfully.
Historical evidence is unchanged.

| Measurement | Plain | Facet |
| --- | ---: | ---: |
| Author status | completed | completed |
| Required run checks and budgets | fail | pass |
| Universal checks | 1 / 13 | 13 / 13 |
| Diagnostic spec checks | 28 / 49 | 34 / 49 |
| Desktop diagnostic checks | 14 / 24 | 17 / 24 |
| Phone portrait diagnostic checks | 13 / 24 | 16 / 24 |
| Strict type errors | 0 | 0 |
| Author wall time | 1120.778 s | 1215.301 s |
| Total tokens | 3,710,399 | 5,292,171 |
| Uncached input tokens | 123,143 | 151,897 |
| Cached input tokens | 3,546,624 | 5,108,608 |
| Output tokens | 40,632 | 31,666 |
| Completed CLI turns | 1 | 1 |
| Observable CLI turn duration | 1119.411139 s | 1214.131357 s |
| Tool calls | 145 | 140 |
| Tool time, union | 388.848 s | 758.335 s |
| Tool errors | 8 | 12 |

The observable turn is the interval from `turn.started` to `turn.completed`.
It includes tools and waits, not isolated model thinking. Facet's interval
is 1.085 times Plain's. One turn per arm supplies no latency distribution.
The token target is at most 0.5 and the wall-time target at most 0.6; both
fail here. The lower-turn-duration goal is also unmet. One task cannot
establish the five-task headline or its confidence bounds.

Compared with the [third pair](slice-sol61-medium-3.md), Facet tokens fell
from 8,815,592 to 5,292,171 and wall time from 1719.399 to 1215.301 seconds.
Its tool calls fell from 166 to 140. Plain tokens rose from 1,929,811 to
3,710,399 and wall time from 561.549 to 1120.778 seconds. Thus both a shorter
Facet run and a longer Plain run contribute to the closer paired ratios.
These are fresh authored outputs at different source revisions, one seed
each; the comparison does not isolate a causal effect of the shared changes.
Facet diagnostic coverage remains 34/49; Plain improves from 23/49 to 28/49.

## Native measurements

The universal and diagnostic passes are separate observations. The following
universal values come from `scores["play.perf.<device>.<metric>"]` in the
indexed results.

| Device | Universal metric | Plain | Facet |
| --- | --- | ---: | ---: |
| Desktop | Mount, s | 6.126 | 2.231 |
| Desktop | Final Lua heap, KB | 651 | 584 |
| Desktop | Final GUI memory, MB | 32.893 | 33.567 |
| Desktop | Heap return ratio | 1.269 | 0.762 |
| Desktop | GUI return ratio | 1.020 | 0.988 |
| Phone portrait | Mount, s | 12.141 | 2.234 |
| Phone portrait | Final Lua heap, KB | 557 | 688 |
| Phone portrait | Final GUI memory, MB | 33.245 | 33.614 |
| Phone portrait | Heap return ratio | 0.872 | 0.882 |
| Phone portrait | GUI return ratio | 1.021 | 0.944 |

Facet's universal phone heap is 1.235 times Plain's, above the 1.05 limit.
Universal GUI memory ratios are within 1.05 on both devices. Plain's desktop
heap return ratio exceeds the per-arm 1.05 limit. These results still do not
meet all overhead rules.

The diagnostic values below use `spec.perf` scores. Missing values are not
zero and cannot pass a comparison.

| Device | Diagnostic metric | Plain | Facet |
| --- | --- | ---: | ---: |
| Desktop | Mount, s | 3.114 | 2.239 |
| Desktop | Final Lua heap, KB | 742 | 836 |
| Desktop | Final GUI memory, MB | 30.159 | 34.047 |
| Desktop | Heap return ratio | 1.208 | 1.156 |
| Desktop | GUI return ratio | 0.893 | 1.016 |
| Desktop | Idle frame p50 / p95, ms | 4.029 / 5.480 | 4.049 / 5.591 |
| Desktop | Active frame p50 / p95, ms | 4.075 / 5.606 | 4.103 / 5.563 |
| Desktop | Returned to root | 1 | 1 |
| Desktop | GUI object delta | 23 | 1 |
| Desktop | Total UI instance delta | 50 | 151 |
| Phone portrait | Mount, s | 2.951 | 2.302 |
| Phone portrait | Final Lua heap, KB | missing | 612 |
| Phone portrait | Final GUI memory, MB | missing | 34.130 |
| Phone portrait | Heap return ratio | missing | 0.940 |
| Phone portrait | GUI return ratio | missing | 1.002 |
| Phone portrait | Idle frame p50 / p95, ms | 4.063 / 5.237 | 4.065 / 5.470 |
| Phone portrait | Active frame p50 / p95, ms | 4.079 / 5.571 | 4.079 / 5.581 |
| Phone portrait | Returned to root | 0 | 1 |
| Phone portrait | GUI object delta | missing | 1 |
| Phone portrait | Total UI instance delta | missing | 135 |

Plain failed the diagnostic phone return to root, so that pass has no final
memory sample. Facet's diagnostic desktop heap and GUI memory exceed Plain's
by 12.7% and 12.9%, respectively. Both desktop heap return ratios exceed
1.05. Do not substitute the better universal sample to hide these findings.

Facet's diagnostic total UI census grows from 155 to 306 instances on desktop
and from 158 to 294 on phone. GUI objects grow only from 75 to 76 on each;
most growth is in the unclassified `other` category, from 33 to 181 and
32 to 165. The root count also grows from one to two. These finite counts
do not identify retained classes or establish an unbounded leak.

Frame samples are `RenderStepped` deltas and measure cadence. This pair's
listed medians are near 4.1 ms. Earlier runs switched between roughly 60 Hz
and 240 Hz; unrelated host work can also affect samples. The closer cadence
values here do not prove lower UI CPU/GPU cost or causal rendering overhead.
The configured bounds remain unchanged.

## Blind judge

The indexed `judgments.json` contains two successful comparisons and no
failed comparisons. The judge used Sol 6.1 Medium through the OpenAI CLI.
Both comparisons are consistent across image order.

| Device | Image order | Overall | Polish |
| --- | --- | --- | --- |
| Desktop | Facet, Plain | Plain | Plain |
| Desktop | Plain, Facet | Plain | Plain |
| Phone portrait | Plain, Facet | Plain | Plain |
| Phone portrait | Facet, Plain | Plain | Plain |

Plain also wins hierarchy, clarity and consistency in all four presentations.
Device fit favors Plain in three presentations, with one phone tie. Fitness
favors Facet in three presentations, with one phone tie. Facet wins 0/2
device comparisons; the 70% preference target remains unmet.

The desktop critiques favor Plain's readable HUD and dock, larger headings,
quest progress bars, currency colors and cohesive styling. They identify
Facet's small shop text and almost full-height shop as weaknesses. On phone,
the judge describes Facet's quest and shop panels as crowded against the
screen edges, and favors Plain's readable card text, grouping and larger
Close and category controls. Both interfaces clip some scrolling content.

The judge credits Facet's compact boost and offer panels, greater world
visibility in those panels, repeated wallet balances and explicit purchase
shortfalls on desktop. Plain still wastes space in simple panels and needs
more scrolling. Phone critiques find insufficient visible affordability
explanation in both outputs, including an apparently enabled 99-Gem offer
with a 40-Gem balance. These are screenshot judgments, not proof that the
purchase logic accepts an unaffordable transaction.

These judgments apply to the saved outputs of this one task and seed. They
do not establish general library quality or replace the behavioral checks.
This pair does not establish the full or extended suite goals.

## Diagnostic limits and trace changes

Some item-specific diagnostic outcomes do not establish the intended item's
behavior. In the saved phone Amber attempt, raw Studio outputs 309–313 under
`checks/spec/studio/run-1792533440-1/mcp` locate Amber at y = 895.33 and
report failed reveal, then activate Lucky Charm instead. The server records
that Lucky Charm purchase and a gem balance change from 40 to 30. A desktop
Rainbow refusal attempt likewise records `road_wheels` at log line 106.
The shared tap implementation could fall through to another matching button
after the selected target was unreachable. Thus an activated tap did not
prove that the requested item was exercised. The correction and its tests
are separate work; the scores and saved evidence here remain unchanged.

The filtered systems scenario omits the control-return observations required
by coherence, but still runs that check. Two coherence failures therefore
lack their required observations. Copy-sensitive assertions and later steps
can also produce diagnostic cascades. These limits require case-by-case
review; they do not show that all diagnostic failures are false positives
or that the missing task behavior is correct.

The repeated `purchaseCard` clipping repair seen in pair 3 did not recur in
this author's trace. Full device sweep command time fell from 535.95 seconds
to 316.11 seconds. The previously observed cleanup ownership misuse also
did not recur in the trace. These are narrower observations than proof of
all layout or resource-lifetime behavior, and do not isolate why the paired
efficiency ratios changed.

Candidate-only native rechecks are saved separately under
`artifacts/facetbench/sol61-preflight/pair4-targeting-phone` and
`pair4-fill-phone`. Each reports 18 passed and 7 failed out of 25 selected
checks, not a new paired author result. Both pass coherence. The candidate
records return-control observations during filtered system dumps; both saved
`coherence.json` files contain zero X and Y return-control spread. This fills
an observation gap rather than changing the historical scores or limits.

The targeting recheck fails safely on Amber instead of activating Lucky
Charm. Its raw MCP output 94 identifies the `amber_wheels` Buy button at
y = 943.33; outputs 95–96 report failed reveal, with no purchase tap before
the next case. The fill recheck also fails Amber reveal. It does activate
the intended `rainbow_trail` and `gold_paint` buttons, then fails their
copy-sensitive explanation checks. A later Quests tap is correctly rejected
as covered by the open modal's dismiss target. Remaining failures therefore
include unresolved reachability and possible copy or state cascades; they
cannot all be assigned to the old fallback bug.

The correction removes fallback after selection. It does not turn `near`
into an item-identity selector: `search` still ranks all matching controls
by minimum tree distance to matching text anchors, then geometric distance.
Ambiguous anchors or an absent intended candidate can still rank another
control first before reveal. The saved Amber candidate above is the correct
row, so these rechecks do not demonstrate that earlier-selection failure.
They also do not prove that heuristic selection is correct for every layout.

A further disposable-workspace candidate is saved under
`artifacts/facetbench/sol61-preflight/pair4-type-role`. It changes only the
theme to the current complete text-role font and size map. The original
interface initializer was restored, without the `UI.fill` experiment. Its
native diagnostic run records 37/49 selected checks passed: 18/24 desktop,
18/24 phone portrait, plus the workspace build check. Twelve checks still
fail. The saved scores and `play.log` describe this candidate, not a revised
score for the historical pair.

The maintainer's review of its saved desktop and phone shop captures found
a consistent typeface and larger item names. Bright action controls still
dominate, and the phone shop remains crowded. This is a limited visual
observation, not a blind judge win or proof that the layout goals passed.
None of these candidate rechecks is a fresh paired author run, a full
repository gate, or evidence of current CI status. The indexed pair 4
results and judge outcomes above remain unchanged.

The separate `pair4-reverse-scroll/native-trace.json` and
`native-reset-candidates.json` retain a known touch-reveal limitation:
touch fling can retire a virtualized target. An immediate
`ResetScrollVelocity` candidate failed. A candidate that waited one frame
before resetting first revealed Amber in four steps, but a later reverse
reveal still failed after 32 steps while retaining the same row object.
Thus target retirement does not explain every failed reveal. Both reset
candidates were rejected and reverted; no runtime or probe nudge change
was retained. These traces add no passing cases to the historical pair.

The separate `UI.fill` candidate did establish a viewport geometry correction:
the inner scrolling region at y = 452 changed from height 576 to height 319,
with its bottom at 771. That bounded viewport pattern is now in the recipe.
It does not establish a general touch-reveal fix or change the scores above.

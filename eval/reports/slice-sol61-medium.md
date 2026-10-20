# Sol 6.1 Medium slice, first pair

The first fresh pair improves required behavior but does not meet the efficiency
or memory goals. Do not advance to the full suite from this result.

The run used `eval/slice.json` at Facet `6813bcd9`, one task, seed 1, and
sequential Sol 6.1 Medium agents. Both author Studios were maximized. The hidden
checks used desktop and phone portrait. The Facet author also ran its own five-device
checks. That author evidence is separate from the hidden checks.

Evidence: `artifacts/facetbench/slice-sol61-medium`. Historical Claude results
remain in `artifacts/facetbench/slice` and are not paired with these runs.

| Measurement | Plain | Facet | Facet / Plain |
| --- | ---: | ---: | ---: |
| Required universal cases | 1 / 13 | 13 / 13 | — |
| Diagnostic spec cases | 22 / 49 | 34 / 49 | — |
| Total tokens, including cached input | 3,087,391 | 10,366,176 | 3.36 |
| Author wall seconds | 948.62 | 1,872.11 | 1.97 |
| Tool calls | 72 | 187 | 2.60 |
| Time covered by tool intervals, seconds | 145.56 | 1,237.19 | 8.50 |

Facet made 50 documentation calls and 14 verification or report calls.
Verification commands covered about 904 seconds. These categories overlap;
do not add them to estimate wall-time savings. Early checks failed to mount
because of connection cleanup and input ownership errors. Repeated console
focus findings caused more checks and source inspection. Meaningful final
geometry and transaction checks remain necessary.

Plain's label helper gave every label its parent's full width, then offset
several labels to the right. The native boxes extended beyond the screen even
when the short visible words fit. Shop's failed audit prevented normal Back
from running. Its unnamed `×` control also prevented recovery. Later missing
dock actions are cascades, not independent evidence that each action is absent.

## Native overhead

These are the universal checks' samples. Do not substitute diagnostic spec
samples. Both Facet devices recorded successful returns and complete final
memory samples. Its final GUI-object count equals its initial count. Plain's
final state still contains panel objects, so its cleanup defect limits the
memory comparison.

| Facet / Plain | Desktop | Phone portrait |
| --- | ---: | ---: |
| Idle frame p50 | 1.015 | 1.006 |
| Idle frame p95 | 1.025 | 1.019 |
| Active frame p50 | about 1.00 | about 1.00 |
| Active frame p95 | about 1.01 | about 1.01 |
| Final heap usage | 0.796 | 0.761 |
| Final GUI memory usage | 1.062 | 0.943 |

The observed frame ratios are below 1.05. Desktop final GUI memory is above
1.05. Facet phone heap grew from 478 KB to 556 KB, and GUI memory grew from
31.489 MB to 33.386 MB. These exceed their existing return-growth limits.
One pair does not establish a confidence interval across tasks. Keep the
declared limits and the five-task minimum.

## Missing and invalid evidence

The Claude CLI judge returned a weekly quota error until October 24. Neither
presentation order produced a verdict on either device. These comparisons are
missing, not losses for either arm. There is no blind preference result.

This Verify revision counts Codex tool-event gaps as model turns. The recorded
turn-latency percentiles are invalid evidence of model response speed. The
upstream correction uses the observable `turn.started` to `turn.completed`
duration, including tools. Do not silently rewrite the saved result or compare
that definition with Claude's response-gap timing.

Plain's scoped capture stopped answering. The proxy waited against the whole
run deadline, blocking later requests. The upstream fix bounds each request,
discards its transport after a timeout, and never replays the uncertain action.
It does not claim to fix the engine's missing capture response.

## Changes after this pair

Verify `281b4135` passed all 21 native gate producers. It includes the bounded
request and Codex timing corrections. Its native test reports an eight-second
action as uncertain after five seconds, then observes that it ran exactly once
through a fresh transport to the same Studio.

The original toast pattern also fails in an isolated seven-line example. An
explicit callback return type and a named Text constructor pass. The shared
recipe now uses that form. State and option guidance now cover native connection
cleanup, Toast's action requirement and typed Picker options.

A valid native console probe found KeyboardAndMouse input under the Xbox
simulator preset. Selecting a control left the ring transparent. One emulated
directional input made it visible without changing Facet. The host now sends
that input before console settling and captures. Native replay changed all
three probe controls from hidden to visible indicators. The audit rule is unchanged.

Failed-case cleanup now uses Verify's deferred cleanup, including an unnamed
`×` fallback. It retains the original failure and records cleanup failures
separately. Normal Close and focus-return checks are unchanged.

Preserve this pair, then run both arms again with fresh evidence. None of these
post-run changes has yet established an efficiency or overhead improvement.

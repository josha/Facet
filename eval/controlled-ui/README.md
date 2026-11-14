# Controlled UI comparison: Abyss Relay

The new guidance did not produce a consistent visual improvement in this
study. Every image-enabled author still made a native interface, with no
image-generation or upload attempt. All four Facet submissions passed the
independent interaction checks. Plain Sol with images available failed the
portrait surfacing route where its button overlapped Roblox's jump control.

This is one task with one fresh author per arm, run on 14 November 2026 UTC.
It does not establish a general model ranking or a causal effect across tasks.
The user omitted Opus after authentication failed before model work.

## What was held constant

Six Sol 6.1 Medium authors received the same supplied underwater world,
equipment models, camera, server state, actions and outcomes. They built only
the survey HUD, equipment decisions and expedition report. Each received up
to 1,200 seconds, including its own inspection and repairs. No operator
coached or repaired a scored submission.

The conditions were plain Roblox, old Facet guidance, and new Facet guidance,
each with and without an advertised image-generation tool. All Facet arms
used runtime `2703edb3f116954ff98e9d2b96d65aec9930f1da`. Old guidance came
from `c8ae0b9b80eb91d1cbcf1710cc4775bc25975f84`; new guidance came from
`2703edb3f116954ff98e9d2b96d65aec9930f1da`. The supplied game fingerprint
matched in all six submissions. Persistent inventories also matched after
their initial independent evaluations.

## Blind visual comparison

Sol 6.1 Medium judged anonymous matching states in both presentation orders.
Each pair had 20 matched captures: eight desktop states and six in each phone
orientation. New Facet versus plain Sol with images available had 19 because
the plain portrait report was not reached. Supplied world and model detail
earned no UI craft credit. A winner below won in both orders; every
"inconsistent" result changed winner with order.

| Comparison | Desktop | Portrait phone | Landscape phone |
| --- | --- | --- | --- |
| New vs old Facet, no image tool | Inconsistent | Old | Old |
| New vs old Facet, image tool available | Inconsistent | New | Inconsistent |
| New Facet vs plain Sol, no image tool | Inconsistent | Facet | Plain |
| New Facet vs plain Sol, image tool available | Plain | Facet | Plain |

Portrait preference favored the newer image-enabled Facet submission's
readable values, explicit credit shortfalls and actions above native touch
controls. Plain Sol often had stronger typography and clearer equipment
comparisons on desktop and landscape. Old native Facet used more compact
equipment records and grouped task facts more economically than new native
Facet. Small desktop labels and clipped context in scrolled equipment lists
remain weaknesses. A clipped row in a scrollable list is not, by itself, an
unreachable action: the separate input checks matter.

## Interaction and image use

The independent player checked cancellation, buying, equipping, departure,
two scans, surfacing, accepted payout and return with ownership preserved.
It also checked desktop engine selection. All four checks passed for plain
Sol without images and for every Facet arm. Plain Sol with images available
passed desktop, landscape and engine selection; its portrait Surface button
did not respond to two center taps. The native jump control visibly overlaps
it. This proves the tested route failed, not that every possible activation
point is unreachable.

All three image-enabled sessions advertised the generator in their actual
tool definitions. None called it, attempted an upload, or referenced an
uploaded UI image. Upload permission had passed preflight. There is no failed
generation or refused upload that explains these choices. Authors selected
flat instrument-panel concepts in Studio and refined those native targets.
They did not supply an image-versus-native comparison demonstrating that
authored detail survived. Native implementation is allowed; this study does
not show that the new decision guidance changed the choice or improved it.

The shared study prompt restricted work to the owned Studio through Studio
MCP while its brief allowed an image generator when present. That wording
may be ambiguous. The frozen study was not changed after authoring began,
and the traces do not establish that ambiguity as the reason for zero calls.
Separately, the repository's plain-arm instructions incorrectly said Studio
MCP was the only tool despite an image-enabled profile. That contradiction
is corrected for future runs; this study does not evaluate that correction.

## Author time and usage

Input columns separate uncached input from cached input. Values are thousands
of tokens, rounded. Output includes the model's reported output usage.
These are usage counts, not dollar costs.

| Arm | Time | Completion | Uncached input | Cached input | Output |
| --- | ---: | --- | ---: | ---: | ---: |
| Plain, native | 8m 25s | Finished | 73.2k | 2,094.2k | 13.8k |
| Old Facet, native | 15m 14s | Finished | 125.4k | 3,987.3k | 25.6k |
| New Facet, native | 20m | Timed out | 127.4k* | 5,405.7k* | 32.2k* |
| Plain, images available | 9m 24s | Finished | 101.0k | 2,028.7k | 17.2k |
| Old Facet, images available | 20m | Timed out | 136.3k* | 5,130.0k* | 32.2k* |
| New Facet, images available | 13m 20s | Finished | 147.7k | 5,048.2k | 20.4k |

*Timed-out usage is the last recorded cumulative session count and may omit
the unfinished request. The CLI's zero-token timeout summary is not used as
zero cost. Invalid infrastructure pilots are excluded from this table.

## Measurement fixes and evidence

Two early pilots inherited repository instructions and host skills. They
were interrupted and preserved. All scored Codex authors restarted with
automatic instruction discovery disabled and explicit frozen arm guidance.
Judges use the same instruction isolation.

The input probe also skipped an `Active=false`, `ScrollingEnabled=true`
native scroller and treated its backdrop as an input blocker. Native drag
scrolling worked on that scroller. The probe now recognizes it as a drag
receiver. The affected frozen submissions were repeated without UI changes.
A live Verify regression checks scroll movement and native activation while
`Active` remains false. Evaluator selector corrections are retained and
excluded from scored attempts.

[The evidence packet](evidence.zip) contains the frozen protocol and prompts,
fixture source, native service-root archives and parent maps, UI source,
input reports, all blind judgments, hashes, and four selected original Studio
captures per arm. Full captures, transcripts, invalid pilots, diagnostics and
the interactive comparison gallery remain in
`artifacts/facetbench/session-20261114-controlled-ui`.

Phone input used Studio device emulation and native pointer events translated
by that emulator, including touch-style drag scrolling. Engine selection used
keyboard navigation. No physical touch device or controller was tested.
Plain Sol also passed all four checks with the final shared driver after a
native archive reload whose inventory exactly matched the frozen submission.
Its original matching captures remain the blind-judgment source.
Devices, states and presentation orders are repeated observations of this
one task. The study supports retaining the measurement fixes and investigating
concept choice and compact equipment layouts; it does not support claiming a
general visual-quality win for the new guidance.

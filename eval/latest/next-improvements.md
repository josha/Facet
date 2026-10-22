# What to improve next

The largest measured gap is the cost of getting a complete game to work.
Facet produced a shorter client script, but needed twice as many tool calls
and substantially more repeated context. More controls alone would not
address that result.

## Evidence from the author traces

| Diagnostic | Plain | Facet |
| --- | ---: | ---: |
| First completed Play call | 504.40 s | 504.91 s |
| Edit or build calls | 15 | 26 |
| Inspect or test calls | 19 | 34 |
| Console checks | 20 | 37 |
| Native input calls | 17 | 32 |
| Screen captures | 15 | 21 |
| Play start or stop calls | 20 | 32 |
| Documentation calls | 0 | 36 |
| Final client source characters | 60,827 | 43,738 |

The [trace summary](trace-summary.json) uses heuristic classifications.
An execute call can combine inspection, editing, and testing. These counts
identify investigation targets; they do not assign exact token costs to each
activity. Most of the wall-time difference came after the first Play call.

Facet's documentation calls returned 87,699 text characters. One combined
read of the workflow, game-flow guide, and map returned 28,225 characters;
the design guide returned 11,368. Repeated context processing includes these
reads, but character counts do not prove a particular token attribution.

## Priorities

1. **Reduce integration failures before adding components.** The Facet author
   hit an unsupported `bag` icon, a function supplied where Region requires
   a concrete GuiObject form, and more than two Callout actions. These errors
   interrupted construction or interactions. The icon documentation says an
   unknown name shows no icon, while this run threw an error. Correct that
   contract mismatch. Give Region invalid values a clear boundary error;
   teach a stable form root with reactive content inside it. Show tutorial
   Back and Next actions with a separate dismissal affordance. Preserve
   useful contracts instead of accepting invalid values silently.
2. **Make the shortest successful path sufficient.** Keep the skill centered
   on player tasks, hierarchy, compact forms, and visible feedback. Make one
   bounded structure recipe enough to start a working screen. The author
   already receives a rule against reading every recipe; another warning
   alone will not reduce the actual material it needs. Audit overlap between
   required guidance and reference nodes, and test whether their examples
   work when copied through Studio MCP.
3. **Verify a complete interaction before multiplying it.** Both authors spent
   time repairing driving input. Facet also spent time repairing UI mounting
   and individual destinations. Establish one state-to-action-to-result flow,
   inspect its rendering, and then reuse it. Prioritize game state and the
   rendered result over repeated console-only checks. Do not reduce the
   required game scope or conceal failing destinations.
4. **Measure beauty and platform behavior independently.** Use the sealed
   games for matched Hub, Shop, Garage, Livery, Race, Results, and Tutorial
   captures across the five devices. Use a blind judge with swapped order.
   Test navigation, touch, controller, safe areas, stable layout, and every
   required player outcome. This pair has no independent visual winner yet.
5. **Measure the actual performance target.** Compare matched frame-time and
   retained-memory workloads on each device. The library resource ceilings
   and native-double benchmark cannot establish the game's less-than-5%
   overhead requirement.

## Separate common game costs from Facet costs

The traces also contain ordinary Luau syntax errors, a Terrain deletion
attempt, a wrong audio asset type, PlayerModule/input conflicts, and reserved
CoreGui input rejection. These do not all indicate missing Facet controls.
Inspect the exact failed operation before changing the library.

Both authors described session-only state and incomplete physical-controller
verification. Plain's damage setting appears to be stored without a game
consumer. These are investigation findings, not a complete functional review.
A custom anchored kart moved with PivotTo is not automatically a failed game:
the acceptance check must test real steering, progression, and consequences,
not require an unrelated VehicleSeat implementation.

No next author run is part of this PR. Keep these priorities for the next
explicitly authorized hill-climbing session. The eval thresholds stay intact.

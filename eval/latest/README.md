# Latest checkpoint evidence

This checkpoint does **not** pass the eval. It preserves the latest Facet
submission and the most recent Studio-only Plain baseline. Older submissions
and Opus evidence are not part of this checkpoint.

## Author results

| Arm | Author | Limit | Recorded duration | Total tokens | Tool errors |
| --- | --- | --- | --- | --- | --- |
| Facet | Sol 6.1 Medium | 600 seconds | 398.90 seconds | 1,167,736 | 2 |
| Plain | Sol 6.1 Medium | 600 seconds | 600.16 seconds; timed out | Unavailable | 9 |

Facet tokens include 1,076,608 cache-read tokens, 69,974 uncached input tokens,
and 21,154 output tokens. Plain's zero counters in its original result mean
unavailable usage, not zero cost. Its missing final turn also prevents a turn
latency comparison. This evidence does not establish the efficiency thresholds.

Both authors started from blank places and had Studio tools only. Facet added
the installed library and public consumer guidance. The Plain baseline used
the earlier scoped tool descriptions. Facet used the corrected argument schemas
and native input examples. This is an iterative diagnostic comparison, not a
fresh matched pair under identical tooling.

The next comparison uses a 1,800-second limit for both arms. That change does
not extend, resume, or relabel these historical submissions.

## Blind visual judgment

The Sol 6.1 Medium judge compared desktop Hub and Garage captures in both
presentation orders. It preferred Plain in both orders and on all six criteria.
Four other device comparisons were skipped because matched captures were not
supplied. This is one comparison containing two screens, not two independent
wins. It does not establish a whole-game preference rate.

The judge cited Plain's clearer primary race action, labeled filters, stronger
typography, and consistent spacing. Facet's ambiguous repeated `All` selectors,
small statistics, competing scrollbars, and panel reaching the screen edge were
the main defects. The full judgments are in `judge/observations`.

The judge used the current full-game brief, whose time limit now says 30 minutes.
Both pictured submissions were authored under the earlier 10-minute limit.
Treat the judgment as a diagnostic of the displayed UI, not a verdict on the
upcoming 30-minute comparison.

## Player evidence

The frozen places and integrity reports are retained under each arm. Player
checks operate on instrumented copies. The author result is preserved verbatim;
its initial missing-seal failure precedes the later independent evaluation.

The attached player checks are diagnostic subsets, not the full acceptance
suite. They must not be reported as complete game coverage. Initial Facet checks
included an incorrect case-sensitive search pattern and did not follow the
compact Menu route. Those evaluator failures are superseded by the final checks.
Source for the checks is retained as `player.luau.txt`.

The corrected Facet report has **8 passed and 3 failed cases**, including one
build pass. Garage search and clear pass on desktop, portrait phone, tablet,
and console. Livery entry and return pass on desktop, portrait phone, and tablet.
Landscape cannot reach Menu for either task. Console reaches Livery but cannot
close it. Console actions use the existing gamepad selection driver. These
checks do not cover the complete Garage or Livery acceptance rows.

## Gaps to close

- Complete all acceptance rows, rejection paths, and return paths across five
  devices. A preview or editor mounting does not prove its complete task.
- Improve visual hierarchy and density. Use labeled filters, readable comparison
  statistics, meaningful glyphs, and a clear primary commitment.
- Fix the reported track-vote Card hover expansion. It is not yet independently
  reproduced or fixed in this checkpoint.
- Apply settings to actual game effects, provide distinct voted track outcomes,
  anchored onboarding, and complete crate reveal behavior. The author reported
  these as incomplete.
- Verify selected previews, livery effects, driving, rewards, and repeated play
  independently. Author claims and server calls are not player-flow evidence.
- Collect a fresh matched Plain/Facet pair, complete author usage, and blind
  judgments for equivalent states across all devices.
- Establish frame-time and retained-memory overhead below 5%. Current observations
  are insufficient; repository checks and screenshots cannot prove this claim.

No submitted game was repaired after authoring. Library and guidance changes
after a submission apply only to later attempts.

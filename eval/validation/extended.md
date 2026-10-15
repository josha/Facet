# Extended racing hub handoff

`eval/extended.json` has 11 tasks, two arms, three seeds, and five devices. One seed has 22 agent runs. Three seeds have 66. The arms, agent, budgets, and device definitions match `eval/games.json`. The headline suite and its task files are unchanged.

The four configurations in `eval/tasks/extended` use the existing briefs and checks. They chain Shop categories, Garage search and sort, Settings reset, and Scoreboard. Their scenarios retain earlier cases. They also correct the contract command's target to the output workspace. The original follow-up contract commands compare two source paths. The livery turn starts from the chained scoreboard output. Each later new turn starts from the preceding new turn and retains all its cases and audits.

Each reference directory contains only changed interface files. The fixture suite for a turn uses strong references for all preceding turns. Its final turn uses either the strong or weak file. Thus a weak reference has one deliberate fault. Preparation derives `followups/strong` from the racing-hub reference and three patches. It also derives fixture task configurations from the canonical task files. Verify scopes task overlays to declared arm names: the agent suite has `plain` and `facet`, and the fixture suites have `strong` and `weak`. Verify has no suite-level mapping for these task arm names. The derived configurations keep all checks, resolve command paths to the canonical task directory, and map the overlay to the fixture arms. Generated files are ignored by Git.

| Turn | Checks on every device | Deliberate weak fault |
| --- | --- | --- |
| Livery editor | Body and accent swatches, shade, decal grid, dirty preview summary, unsaved state before Save, saved decal and shade, reopen, Revert question, Cancel, discard, dirty Close or B. | Revert skips the discard question and keeps the draft. |
| Track vote | Three cards, changing countdown, first vote, own-vote mark, changed vote with old count removed, remote count change, highest-count winner, locked actions. | Vote actions remain enabled after time ends. |
| Quick chat | Eight reachable wheel choices, one send, visible message, preserved cooldown, disabled send, send after cooldown, return navigation. Desktop opens with Q. | Send choices stay enabled during cooldown. The server still rejects a second send. |
| Upgrades | Both prices, disabled purchase with Coins but no Gems, Cancel, one charge in each currency, updated rating readout, separate kart levels. | The enabled state ignores Gems. The server still rejects the purchase. |
| Party invite | Three presence states, case-insensitive search, empty state, Clear, offline action disabled, Pending, Accepted, Declined, correct party strip. | Clear keeps the filter text. |
| First-time tutorial | Three ordered steps, Back, Skip, final Next, target activation while help is visible, return to the same step, recorded dismissal. | Back keeps the current step. |

| Device | Additional input and geometry evidence |
| --- | --- |
| Desktop | Mouse activation, Q entry, visible text fit, viewport bounds, screenshots and interface audits. |
| Phone portrait | Touch activation, scrolling to offscreen choices, 44-pixel target checks, text fit, safe-area audits. |
| Phone landscape | The same checks at the short landscape height. This is a separate session, not a rotation test. |
| Tablet | Touch activation and scrolling at the tablet size, target and text-fit checks. |
| Console | Engine selection routes to actions, Return activation, Backspace as B, and focus return. Real gamepad button events remain manual evidence. |

The references use native UIListLayout, UIGridLayout, ViewportFrame.CurrentCamera, ScrollingFrame, GuiService.SelectedObject, and ContextActionService.BindActionAtPriority. These APIs cover their layout, preview, selection, and input needs. Compose runtime constructors, structural ownership, and reactive state APIs were checked in the upstream API reference. These plain references require no UI package, so they do not mount Compose. No shared testing mechanism or vendor file changed.

## Headless commands

```sh
lute run tools/facet facetbench prepare
lute run eval/tools/check.luau
lute run tools/facet check facetbench-references
lute run tools/facet check facetbench-references --selftest
lute run tools/vendor/verify/tools/agent-eval.luau plan --suite eval/extended.json
```

The reference check assembles each turn under `artifacts/facetbench/reference-headless/<turn>/<arm>`. It checks the unchanged contract, strict client/server/shared types, client lint, and a Rojo place build for all 12 assemblies. Command logs and places stay in that directory. This check does not execute player input or prove the strong and weak play verdicts.

Preparation generates `extended.project.json` from the shared reference layout and the six turn modules. Repository type analysis prepares and includes this project. The corpus and reference checks also prepare their inputs. Use the assembled per-turn place for play. The analysis project is not a game place.

## Studio commands still required

Run these fixture suites in order. They start no coding agent. Keep Studio available for one host at a time. Inspect the final turn of each suite: the strong play check must pass; the weak play check must fail the stated case. The agent-eval command can exit zero even when a play check fails, so read the check reports.

```sh
lute run tools/facet facetbench prepare
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/hub-livery-editor.json --parallel 1
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/hub-track-vote.json --parallel 1
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/hub-quick-chat.json --parallel 1
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/hub-upgrades.json --parallel 1
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/hub-party-invite.json --parallel 1
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/hub-first-time-tutorial.json --parallel 1
```

For live resize and real gamepad inspection, this command keeps the final strong place open after the checks:

```sh
lute run eval/tasks/hub-first-time-tutorial/hidden/play.luau --workspace artifacts/facetbench/reference-headless/hub-first-time-tutorial/strong --outputs artifacts/facetbench/tutorial-manual/out --captures artifacts/facetbench/tutorial-manual/captures --report artifacts/facetbench/tutorial-manual/report.json --run tutorial-manual --scores artifacts/facetbench/tutorial-manual/scores.json --devices phone-portrait --keep
```

In Studio play mode, open Tutorial. Rotate portrait to landscape and back during each step. Resize the desktop viewport during each step. Scroll the dock. Confirm that the pointer follows the actual target, the help stays inside the safe area, and the target remains usable. Open and close the pointed panel. With a real gamepad, open Quick Chat with Y, send one message, check the cooldown, and test B and focus return for every new panel. Inspect the livery's actual car colors and decal changes and the upgrade bar lengths against their numeric values. The fixed-size scenarios and screenshots do not prove these live visual changes.

The current play host has no in-session resize or rotation operation, and VirtualInput has no gamepad button events. These are general host capability gaps. No Facet runner was added to approximate them. A shared capability must be implemented upstream before an automated check can claim that evidence.

After reference calibration, run the agent suite:

```sh
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/extended.json --seed 1 --parallel 1
```

Omit `--seed 1` to run all three seeds. Do not treat the headline thresholds as calibrated claims for this wider suite.

## Token estimate

The only committed token report is [the historical smoke report](../reports/smoke.md). Its latest completed comparison, run 5, used 381,378 total tokens for plain Shop and 1,603,955 for Facet Shop. These totals include cache tokens as reported by the agent. The report has no complete racing-hub or follow-up token samples.

For a planning estimate, count the 12 base systems and ten follow-up requests as 22 Shop-sized work units. Shared scaffolding can reduce the base cost. Larger follow-up context and retries can increase it. This is a workload estimate, not a measured extended run or a confidence interval.

| Agent-token estimate | Plain | Facet | Both arms |
| --- | ---: | ---: | ---: |
| One seed through all 11 tasks | 8,390,316 | 35,287,010 | 43,677,326 |
| Three seeds through all 11 tasks | 25,170,948 | 105,861,030 | 131,031,978 |

A lower planning scenario of one Shop-sized unit per task gives 4,195,158 plain and 17,643,505 Facet tokens per seed. Use the 22-unit estimate for an initial budget, then replace it with measured extended-suite totals. Judge tokens are excluded.

# Decision packets — `desktop-keyboard-navigation` (roadmap Step 8)

Five things the stage plan could not have known — two platform limits found live
(DKN-1, DKN-2), two defects found and fixed (DKN-3, DKN-4), and one pre-existing
surface inconsistency the architecture review surfaced and this stage deliberately
did not resolve (DKN-5). Each is stated with its evidence, the decision taken,
what it costs, and what would change it.

---

## DKN-1 — Tab is the CoreGui players-list shortcut, and the players list wins

**Status:** decided and shipped, with an honest limit and a probe.
**Escalation:** this is the one finding that materially limits the headline
feature. It is surfaced in the stage report, not buried here.

### Evidence

| Source | Finding |
|---|---|
| Live probe, Studio 0.732, Play session | `VirtualInput:SendKey` refuses exactly two of fifteen keys — **Tab** and **Escape** — with the identical message *"key is permanently bound to a CoreGUI core action"*. Space, Return, all four arrows, Comma, Period, BackSlash, Backquote, LeftShift, F1 and Slash are all accepted. |
| Live probe | `VirtualInputManager:SendKeyEvent` errors *"lacking capability RobloxScript"* — there is no second synthesis path. |
| Live probe | A descendant scan of CoreGui, the LocalPlayer, Workspace and ReplicatedStorage found **exactly one** `InputBinding` with `KeyCode == Tab`: ours. `ContextActionService:GetAllBoundActionInfo()` has **no** Tab binding. So whatever claims Tab is not reachable through either instrument. |
| **Live probe (decisive)** | `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)` makes `SendKey(Tab)` **succeed**. The refusal is **state-aware**, not a static blocklist. |
| create.roblox.com, Input Action System | Tab appears in the *Interface / Inventory* table — *"reserved **unless you disable the respective feature**"* — as **Show/hide players list**. It is deliberately **absent** from the hard table introduced by *"reserved inputs cannot be overridden and will always operate with their intended purpose"* (`Esc`, `F9`, `F11`, `F12`, `PrintScreen`). |
| create.roblox.com, `InputContext` | `Sink`/`Priority` are documented strictly relative to **other contexts**. Nothing documents a developer context outranking CoreGui. |
| create.roblox.com + DevForum 2069353 | Roblox's own keyboard UI navigation is **Backslash** → arrows/WASD → Enter, with PageUp/PageDown/Home/End for scrolling. **Tab is not part of it.** Roblox does not document Tab as a focus-traversal key for developer UI. |

The live probes and the documentation corroborate each other, which is why this is
recorded as a finding rather than a guess — noting that the probes measure the
engine's *synthesis policy* and the developer-visible instance tree, while the
first-party table is what speaks to *delivery*: the players list being enabled is *the* condition,
and disabling it *is* the remedy Roblox names.

### Decision

**Bind Tab, ship it, and state the limit.** Rejected alternatives:

- *Refuse to bind Tab.* It works — proven live — wherever the players list is
  off, which is every UI-only place, menu shell, and any game that already hides
  its leaderboard. Refusing would deliver nothing to them.
- *Pick a different traversal key.* The plan names Tab, and inventing a second
  keyboard convention is exactly the adjacent-feature scope the goal excludes.
- *Disable the players list on the consumer's behalf.* Hiding a game's
  leaderboard to win a key is the same trade `gamepad_contention`'s scope note
  already refuses for avatar controls. LuauUI never does this.

What ships instead: the limit is documented at both the reference and guide
level with the exact one-line remedy, and
`gamepad_contention.traversalKeyContended()` turns a silent loss into a
diagnosable one — the same shape as `legacyStackActive()` for gamepad ButtonA.
Everything else in the stage (Space activation, focused-value arrows,
keep-visible, modal trap, hot-plug) uses uncontended keys and is unaffected.

### Cost, and what would change this

A game that keeps its leaderboard gets no Tab traversal and no warning unless it
calls the probe. If Roblox ever moves Tab into the hard-reserved table, the
binding should be withdrawn and this becomes an ADR the size of Escape's. If
Roblox instead publishes a way for a developer context to outrank CoreGui, the
limit disappears with no LuauUI change.

---

## DKN-2 — keyboard IAS bindings are suppressed while a TextBox holds focus

**Status:** decided; the framework behavior ships, the live row is honest.

### Evidence

Measured live, in sequence, in one session:

| State | Raw Tab event | Semantic action | Focus | Editing |
|---|---|---|---|---|
| TextBox focused (`UserInputService:GetFocusedTextBox()` non-nil) | arrives, `gameProcessed = **true**` | **none** | unmoved | still true |
| same, `Down` instead | arrives | none | unmoved | still true |
| after `ReleaseFocus(false)` | arrives, `gameProcessed = false` | **1 Traverse** | moves | false |

The control row is what makes this diagnostic: the instrument demonstrably works
one call later on the same key. Roblox staff have the same suppression on record
(DevForum 4100260: keyboard `InputBinding`s are suppressed over active UI while
mouse bindings are not). **Read that thread carefully before hoping for a fix**:
the scheduled change moves the *mouse* side to match the keyboard side, not the
other way round. Nothing first-party says the keyboard suppression will be
lifted, so "it engages the day the engine delivers the key" is a statement about
this framework's readiness, not a prediction about Roblox's roadmap.

### Decision

**Keep `handleTraverse` and its commit-then-advance contract; do not add a
`UserInputService` listener to reach the key.** A parallel raw-input path is what
the plan and the constitution both forbid, and it would be a second input system
for one key.

What is true on today's engine, and is what the plan actually requires of the
framework: Tab in a focused field **never types a tab character, never bypasses
validation, and never advances out of an unfinished edit**. What is *not* true
today is that it commits — because the key never arrives. The behavior is
headlessly proven and ready if the engine ever delivers it.

The player's path out of a field is unchanged and works: `Return` commits
(`FocusLost(enterPressed = true)`), then Tab traverses.

### Cost, and what would change this

One documented convention is inert inside a focused field. The row is
`FAIL_ENVIRONMENT` with the exact reproduction stored; **if** the suppression is
ever lifted — which nothing first-party promises, see the evidence above — re-run
`DK17-F` and it should flip to `PASS_AUTOMATED` with no code change.

---

## DKN-3 — `adjustTargets` was handed the screen root (found live, fixed here)

Not a decision packet so much as a recorded defect, because it explains a
behavior change in a shipped seam.

`focusGroups(rootNode)` has always been handed the **contribution's own** mounted
node. `adjustTargets(rootNode)` was handed the **screen** root. Controls that
identify their targets structurally rather than by a unique id therefore claimed
the whole screen: `newStepper` returns *"every Button below here"*, `newRating`
*"every Grip below here"*. On any screen carrying one of those plus another
button, the Adjust keys stayed bound with focus **anywhere** — the precise
gameplay-key shadowing the dynamic binding exists to prevent.

Measured: focus on an unrelated `Save` button, one `Right` press, an `Adjust`
action fired and nothing consumed it. Every headless fixture had put the value
control on a screen by itself, which is why the suite was blind.

**Fixed** by passing `c.node`, making the two seams consistent; `newSlider`'s
stale comment about "the SCREEN root" is corrected and both regressions are
pinned headlessly. The behavior change is a repair in the compatible direction:
a control's claim now stops at its own subtree, which is what its own
documentation already said it meant.

---

## DKN-4 — Space on a non-sinking base screen (consumer collision, fixed in lockstep)

Space-as-Activate binds on any engaged surface that does not pass
`gameplayGuard = false`. RascalRally's results surface binds `Space` itself
(`SkipCelebration` → `results.skipAll()`) on a non-sinking priority-1000 context,
and presents non-sinking for the racer role — so one Space press would have
skipped the celebration **and** activated whichever results CTA the focus ring
happened to be on.

**Decision:** the framework rule stands (the opt-out already existed and is the
declared mechanism), and the consumer declares it. Both results variants now pass
`gameplayGuard = false`, which preserves today's behavior exactly — Space skips,
and only skips — and a new game-side test pins it in both directions (the
declaration is present, the framework honors it by binding no Space, and the same
surface without the declaration does take the key).

---

## DKN-5 — `gamepad_contention` is not a blessed entry point (carried, not resolved)

Raised by the architecture review. `gamepad_contention` is absent from the
constitution §12 blessed client entry-point list, and `check_boundary` records it
as *"not yet a blessed entry point"* — yet `docs/guide/07-input.md` already told
consumers to require it for `legacyStackActive()`, and this stage adds
`traversalKeyContended()` beside it.

The inconsistency **predates this stage**. Keeping the two sibling probes in one
module is the right shape — they answer the same question (*"is a core script
eating this key?"*) for the two keys it happens to. Promoting the module onto the
blessed list, or moving both probes to a blessed seam, changes a closed and
checker-pinned public list, which belongs to the API-consistency ledger rather
than to a keyboard stage.

**Carried to** `artifacts/api-architecture-consistency/decision-packets.md` as
**PKT-14**, with the recommendation (promote the module) and the migration cost
(additive; no behavior moves, nothing is renamed) — and `responder_effects`, which
sits in exactly the same position, named for the same pass. Recorded here so it is
not lost, and so nobody reads the new probe as a new inconsistency rather than an
existing one.

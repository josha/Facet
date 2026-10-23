# Game flows and information

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md).
Design the relationships and recovery across a task. These patterns are starting
points, not fixed screen templates.

## Information architecture

Group destinations by player goals and use consistent game vocabulary. Use
`TabView` for recurring peers, `NavigationStack` for deeper paths and
`NavigationSplitView` for collection-detail relationships. Keep title, selected
section, Back behavior and return state coherent. Frequent tasks need short,
discoverable routes; search, favorites and shortcuts should reach the same
record identities and commands as ordinary browsing.

## HUD, objectives, and interaction prompts

Show information that changes the next decision, rather than every tracked value.

| Question | Treatment |
| --- | --- |
| Can I survive or act now? | Stable resources, availability and useful thresholds; `ProgressView`, direct Button and `ShortcutHint` in protected Regions |
| What next? | One active objective with observable progress; distinguish completed, blocked and optional objectives |
| Where is the target? | Direction/identity tied to relevant space, with offscreen fallback; a `worldAnchor` marker does not establish permission or proximity |
| Can I interact? | Current object, verb, binding and restriction; Menu/RadialMenu only for several meaningful commands |
| What changed? | Brief meaningful emphasis; aggregate routine gains quietly with status, progress trails or Toast |
| What happened earlier? | A deliberate standings Table, objective list or history destination |

Keep target identity stable during commitment. Target loss or timeout invalidates
the action; it must not retarget a press from Open to Purchase. Do not replace
instructions while they are being read. Distinguish cooldown, ready, selected,
executing and other reasons for unavailability with explicit cues.

## Browsing, search, filters, and sorting

Choose grid for recognition, list for descriptions and table for shared-attribute
comparison. Search helps known terms; categories/filters help unfamiliar content.
Use TextInput for a query and Picker, Toggle or Chip for explicit facets. Show
active filters, useful result counts and a clear reset route. A closed filter
Sheet should summarize its effect.

Label sort meaning and direction; keep targets stable enough to operate.
Distinguish an empty collection, no matches and load failure, each with a useful
next action. Preserve query and useful position on return; reset deliberately
when context changes. Search/filter logic belongs to the model, including
rejecting late results from older requests. If filtering hides bulk selections,
make their scope visible and configure `selectionFrom` accordingly. See
[collection editing](COLLECTIONS_AND_ACTIONS.md#collection-editing-and-bulk-actions).

## Inventory, loadouts, crafting, and trade

Separate owned, candidate, equipped, capacity, compatible and pending states.
Preview a candidate and meaningful differences before Equip, including replacement
consequences. A slot needs an understandable purpose. Drag/drop and command
routes must share validation.

Crafting keeps result, ingredients, available amounts, quantity and total cost
together. Explain the missing requirement and update the summary before commit.
Trade distinguishes each party's draft, acceptance and completed transfer. A
change to reviewed terms invalidates confirmation. Coupled fields need one draft
and explicit commitment, not independent blur-to-commit transactions.

## Shops and purchases

Keep identity, contents, eligibility, total cost/currency and ownership outcome
beside the commitment. Separate Preview, Select, Buy, Claim and Equip. Changed
price, quantity or terms require a fresh review. Use confirmation or recovery in
proportion to the consequence; avoid false urgency and misleading defaults.

Show insufficient funds, owned, incompatible, unavailable, pending, accepted and
rejected states clearly. Prevent duplicate consequences during delayed responses;
celebrate only accepted results. Server authority and recoverable drafts follow
the required guide's shared state rules.

## Lobbies, matchmaking, and shared decisions

Show participants, permissions, selected rules, readiness and unresolved Start
conditions. AvatarGroup summarizes a party; a list compares individual readiness
or eligibility. Local intent remains pending until shared acceptance. Rule
changes may invalidate readiness and need an explanation.

Distinguish searching, reserving, waiting, connecting and recovery. Use
indeterminate ProgressView for unknown duration and Timer only for truthful time;
keep valid cancellation available. Match-found prompts must not consume an
unrelated preceding input. Define effects on open drafts/text entry, and durable
recovery for host departure, disband, disconnect or late invitations.

## Pause, settings, and interruption

State whether the world continues while a menu owns input. Do not imply safety
when hazards remain active. Reversible settings can preview immediately; coupled
changes need a draft. Make reset scope clear and accessibility settings reachable
before inaccessible interaction becomes mandatory.

A modal, drag or text edit owns relevant input. Restore useful focus and gameplay
control on exit. Preserve interrupted drafts where possible; explain when a
changed rule or deadline makes submission invalid.

## Results, defeat, and progression

Answer: outcome, explanation, gains/losses, then next action. A scoreboard should
support the personal result. Use VStack for reading order, bounded Table for
comparison and ProgressView for advancement. Reward sequences must preserve
accepted totals and ownership when skipped or dismissed.

Give supported, actionable defeat feedback without inventing a cause. Distinguish
Retry, Spectate, Leave and Continue, naming consequences such as forfeited
rewards. Repeated attempts should not require a long presentation.

## Learning, help, and discovery

Teach one actionable idea at the first useful opportunity. Use Callout for a
contextual introduction, labels/`help` for repeatable explanation and a durable
help destination for required rules. Show the benefit and next action; optional
guidance needs dismissal/skip, meaningful completion and a way back.

Keep the target visible or attach guidance to a stable representation. Stage
complexity through useful tasks without hiding costs or consequences. Beginner
labels and expert shortcuts should invoke the same commands. Detect completion
through the real game action, rather than clicking tutorial Next.

## Text, localization, and player-created content

Use one term per object/action and concrete verbs for consequential commands.
Errors name the failed action, useful reason and recovery, not implementation
codes. Follow the shared keyed LocalizationTable/Translator path. Localize
complete messages, plurals and value order rather than concatenating fragments;
keep player-authored text outside automatic localization.

Test long labels, large numbers, locale formats, mixed-direction and unbroken
strings, and missing art. Truncation needs a way to recover distinguishing
identity. Reserve room for captions/chat without covering controls. Escape
player/server text with `richText.escape` before inserting it into rich formatting.

## Live state and perceived responsiveness

Acknowledge input immediately, show pending work distinctly and make accepted or
rejected results explicit. Optimism needs rollback and must not promise an
unaccepted costly outcome. Reserve loading art space and preserve query,
selection, drafts and scroll position through routine refreshes. Avoid rebuilding
a panel for each tick; follow feed updates only when compatible with reading.

During disconnect, distinguish unavailable commands from local inspection and
keep recovery visible. Reconcile accepted state on reconnect without replaying
all old celebrations. Test response and frame timing with realistic content.

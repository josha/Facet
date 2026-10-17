# Game flows and information

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). A collection of good widgets can still produce a poor game flow. Design the information, decisions, transitions, and recovery across the whole task. The patterns below are starting points to adapt, not fixed screen templates.

## Information architecture

Group destinations by how players understand their goals: play, prepare, socialize, inspect progress, and adjust the experience. Use the game's vocabulary consistently. Do not organize navigation around data tables or implementation modules.

Use `TabView` for recurring peers, `NavigationStack` for deeper paths, and `NavigationSplitView` for collection-detail relationships. Avoid using a fresh modal for every level of a long browsing path. Keep the destination title, selected section, Back behavior, and return state coherent. A player should be able to answer “Where am I?” and “What does leaving preserve?”

Give routine tasks short routes. A nested category may help organize a large catalog but make a frequently changed loadout needlessly slow. Expose a sensible shortcut to frequent work while preserving a discoverable complete route. Keep search, recent items, and favorites tied to the same underlying item identity and commands.

## HUD, objectives, and interaction prompts

Choose HUD information from decisions, not from every value the game tracks.

| Player question | Treatment | Facet starting point |
| --- | --- | --- |
| Can I survive or act now? | Stable current resources, availability, and immediately useful thresholds | `Text`, `ProgressView`, direct `Button`, `ShortcutHint` in protected Regions |
| What should I do next? | A concise active objective with observable progress | Labeled text/progress; optional detail in `CollapsibleView` or a quest destination |
| Where is the threat or target? | Direction/identity tied to the relevant space, with offscreen behavior | Stable HUD cue or `worldAnchor` plus a purposeful marker; keep critical fallback information |
| Can I interact with this object? | Name the object and verb, show the current binding and any relevant restriction | Contextual `Button`/`ShortcutHint`; anchored Menu/RadialMenu only for multiple meaningful commands |
| What changed? | Brief emphasis for meaningful change; quiet aggregation for routine accumulation | Appropriate state paint, `Flash`, progress trail, or `Toast` |
| How does this compare or what happened earlier? | Deliberate access to deeper information | Standings `Table`, objective `VirtualList`, history destination |

Distinguish active, completed, blocked, and optional objectives. A completed objective should not continue to look like the urgent next task. Reveal the next useful step at an appropriate moment; avoid replacing a read-in-progress instruction every time a small condition changes.

Show interaction prompts only for a valid current target, and keep that identity stable during commitment. A prompt changing from Open to Purchase as the player presses is hazardous. Timeouts and target loss should invalidate the action, not silently retarget it. A world marker does not establish proximity or permission; the game owns those rules.

For cooldowns, distinguish “not ready,” “ready,” “selected,” and “actively executing.” A radial fill can show remaining cooldown, but pair important readiness with a stable cue. Do not make players infer whether a button is unavailable because of cooldown, missing resources, or an incompatible target from the same gray paint.

## Browsing, search, filters, and sorting

Use a visual grid when recognition drives choice, a list when descriptions drive it, and a table when shared attributes drive comparison. Then decide how players narrow the set.

- Use a `TextInput` search field for known names/terms. Search is weaker when players do not yet know the vocabulary; provide meaningful categories or filters as well.
- Use `Picker`, `Toggle`, or `Chip` for explicit facets. Show active filters, result count when useful, and a clear reset route. A compact filter `Sheet` should summarize its effect when closed.
- Use a labeled sort picker/menu or Table headings when ordering answers a real question. Say whether lower or higher is better where that is unclear. Keep sort stable enough to operate.
- Distinguish no matches from an empty collection and from load failure. “No parts match these filters” should offer clearing filters; it should not encourage creating or buying a part that already exists.
- Preserve the query and useful position when returning from detail. Deliberately reset to a valid result when a new query changes the task; do not reset on every data refresh.

When filters hide selected records, show whether those records remain part of a bulk operation and configure `selectionFrom` accordingly. Search/filter behavior belongs to the game model; a field alone does not supply it. Keep pending searches from replacing newer results with late older responses.

## Inventory, loadouts, crafting, and trade

Separate ownership, selected candidate, equipped state, capacity, compatibility, and pending changes. A single “active” border cannot communicate all of them.

For loadouts, preview the candidate and its meaningful differences before Equip. Use a detail pane/destination or compact comparison. A slot name should explain its purpose; a silhouette alone may not. Give replacement consequences and a route back. Support drag/drop only when the visible source-destination relationship helps, with the same validation as an Equip command.

For crafting, show the desired result, required ingredients, available amounts, and resulting cost together. Use a `Stepper` or `NumberInput` for quantity, and update the summary before commitment. Explain the specific missing requirement. Do not let a stale ingredient count make a rejected craft look like a completed one.

For trade, make “my offer,” “their offer,” and the final exchange unmistakable. Distinguish drafting an offer, accepting it, and completed transfer. If terms change after review, invalidate the previous confirmation and show what changed. Use a coherent destination or Sheet with explicit commitment rather than a collection of independently committing cell editors. Keep cancellation and authoritative pending state understandable.

## Shops and purchases

The decision requires identity, what is included, eligibility, total cost, currency, and ownership outcome. Place these beside the commitment. A large purchase button cannot compensate for ambiguous terms.

Separate Preview, Select, Buy, Claim, and Equip. A card can open detail; a named Buy action can commit. Show the accepted price and quantity together, including meaningful limits or duration. If those change before confirmation, refresh the review rather than silently applying new terms. Confirm costly or irreversible outcomes proportionately and provide recovery where the game supports it.

Show insufficient funds, already owned, incompatible, unavailable, pending, accepted, and rejected states distinctly. Keep a delayed response from enabling repeated purchases of the same request. Celebration follows acceptance. Do not use false urgency, misleading default selection, or visual ambiguity to increase accidental commitment; understandable choice is part of good UI.

## Lobbies, matchmaking, and shared decisions

Players need to know who is present, who can change settings, what is selected, what remains before starting, and whether time is running out. `AvatarGroup` can summarize a party; use a list when readiness, role, or eligibility must be compared individually.

Show local intent separately from shared confirmation. Pressing Ready is a request until accepted. A host changing the rules may require readiness to be reconsidered; explain that transition. A disabled Start action should name the unresolved condition, not merely appear inactive.

During matchmaking, state whether the game is searching, reserving, waiting on others, connecting, or recovering. Use an indeterminate `ProgressView` when duration is unknown, and `Timer` only for truthful elapsed/deadline information. Avoid invented percentages or countdowns. Keep cancellation available where valid and explain when commitment changes that ability.

A match-found interruption should make the next action and deadline unmistakable without allowing an unrelated prior input to accept accidentally. Define what happens to an open draft, modal, or text entry. Party disband, host departure, connection loss, and a late invitation need coherent outcomes; a disappearing toast is not enough for a state that blocks play.

## Pause, settings, and interruption

State what “pause” means in this game. A local menu may stop input while the shared world continues. Do not imply safety through a paused-looking background when hazards remain active.

Use a destination or Sheet for coherent settings work. Apply reversible audio/visual settings immediately when preview helps; use a draft when changes are coupled. Keep a visible route to restore defaults with clear scope. Put accessibility settings where players can reach them before an inaccessible interaction becomes mandatory.

When text entry, a modal, or a drag begins, define input ownership; when it ends, restore useful focus and gameplay control. Preserve unfinished edits when an external event temporarily interrupts the task if that is possible. If a deadline invalidates a draft, explain why it can no longer be submitted rather than simply removing it.

## Results, defeat, and progression

Answer in order: What happened? Why did it matter? What did I gain or lose? What can I do next? A full scoreboard may support the explanation but should not bury the personal outcome.

Use `VStack` for the reading sequence, a bounded `Table` for comparison, `ProgressView` for meaningful advancement, and restrained sequences/Travel/countUp for rewards. Keep rewarded ownership and authoritative totals correct if the player skips or leaves. Details can remain available through disclosure or a results destination.

For defeat, give actionable feedback when the game can support it: the relevant cause, a useful comparison, or a route to adjust the loadout. Do not invent certainty about the cause. Distinguish Retry, Spectate, Leave, and Continue; name consequences such as forfeiting remaining rewards. A repeated attempt should not require rewatching a long presentation.

## Learning, help, and discovery

Teach at the first useful opportunity, with one actionable idea and immediate feedback. A complete tour before the player has a goal creates memory work. Use `Callout` for contextual introduction, ordinary labels/`help` for repeatable explanation, and a durable help destination when the rules need reference.

Show the benefit and the next action. Let players dismiss or skip optional guidance, remember meaningful completion, and provide a way to find it again. Do not hide required rules in a transient tip. Replace a tutorial overlay that covers the target with guidance attached to a stable representation.

For a new mechanic, stage complexity through coherent tasks, not by concealing costs or consequences. A beginner may need labels and a smaller initial choice set; an experienced player may use shortcuts, favorites, or a radial. Both should act on the same underlying commands. Detect success through the actual game action, not merely through clicking Next in the tutorial.

## Text, localization, and player-created content

Use the same term for the same object/action throughout navigation, buttons, tutorials, and errors. Prefer a concrete verb to “OK” when the consequence matters. Error copy should identify the failed action, useful reason, and recovery. Avoid exposing implementation codes as the player's explanation.

Get every player-facing string from a localization key, fixed words included. Keep the English source in one keyed table that builds the experience's `LocalizationTable`, and read strings through the `Translator` by key. A literal such as `"WRONG WAY"` in UI code depends on `AutoLocalize` finding an entry with exactly that source text. Nothing checks that the entry exists, and a later edit to either copy breaks the match without an error. Keys make a missing translation a failed check instead of English on a translated screen.

Localize complete formatted messages, including plurals and value order; do not assemble translated fragments as if every language shares a sentence structure. Facet's translator integration supports formatted control strings; the game's own messages need corresponding complete localized forms. Keep player names and player-authored text separate from automatic localization.

Test long labels, large numbers, varying date/number formats, mixed-direction text, missing art, and unbroken user strings. Truncate only where recovery preserves the needed identity; two names that become the same prefix are no longer useful choices. Reserve reading room for captions and chat without covering controls. Use `richText.escape` when rendering player/server text inside rich formatting so it cannot alter the intended visual structure.

## Live state and perceived responsiveness

Use immediate pressed/selected feedback to acknowledge input, a distinct pending state for unconfirmed work, and explicit accepted/rejected results. Optimistic updates suit reversible actions with a clear rollback; a costly transaction should not visually promise success before acceptance.

Reserve image/content space during loading. Keep searches, selections, drafts, and scroll position stable through ordinary refreshes. Do not recreate an entire panel for every timer tick or new message. A growing list should follow new content only when that matches the player's current reading position.

When disconnected, distinguish unavailable actions from still-usable local inspection. Keep the recovery route visible through a Notice or task state. On reconnect, reconcile authoritative state, identify relevant changes, and avoid replaying every old reward animation. Performance is part of the experience: test frame timing and response under realistic content, not only an empty catalog.

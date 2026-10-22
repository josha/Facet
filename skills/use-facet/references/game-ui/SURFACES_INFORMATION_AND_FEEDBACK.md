# Surfaces, information, and feedback

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). Good information design makes a state understandable before adding decoration. Good feedback connects an action to its result without taking more attention than the event deserves. A surface should have a clear owner, purpose, lifetime, and way out.

## Choose the interruption deliberately

| Need | Choose | Reason |
| --- | --- | --- |
| Optional detail in the current reading flow | `DisclosureGroup` | Expansion belongs to the page and moves later content |
| Compact summary that expands over neighboring content | `CollapsibleView` | Preserves the layout while exposing a temporary panel |
| Explanation or small contextual interaction attached to a control | `Popover` | Maintains a visible relationship to its source |
| A timely introduction to a specific feature | `Callout` | Connects guidance to that feature and retires when no longer useful |
| Short consequential decision | `Alert` | Concentrates attention on a specific consequence and response |
| Custom bounded modal decision/presentation | `Dialog` | Provides richer content while keeping a narrow purpose |
| A temporary task with content, edits, or several steps | `Sheet` | Gives the task room and a clear return to its origin |
| Substantial independent task or deep browsing | Navigation destination | Gives it durable space, history, and context |
| Continuing condition affecting this content | `Notice` | Remains available while it matters |
| Brief acknowledgement that can safely expire | `Toast` | Confirms without interrupting the task |

Ask whether the player needs to **read**, **decide**, or **work**. “Unsaved tuning will be lost; leave?” is a short decision. Editing the tuning is a task. A full garage with browsing, comparisons, and history is a destination. The amount of available room does not change these meanings.

Modal input capture is independent of a visible dim background. Opening a panel does not automatically pause a game. Define gameplay behavior, control suppression, and dismissal explicitly, including the controls the game implements itself. Avoid a stack of modals for a task that belongs in one navigable surface.

## DisclosureGroup

Use `DisclosureGroup` for a named optional section within the current flow: advanced tuning, reward details, or an explanation beneath a setting. Expansion changes the page layout and pushes later content down.

Keep the collapsed `label` informative; `description` can explain what is inside. Do not hide required errors, transaction terms, or the only essential action in a closed section. Preserve `expanded` state during ordinary updates. `onToggle` should not unexpectedly reset sibling work.

Choose `appearance = "plain"` when spacing already groups the content, `"contained"` when a shared surface helps, `"divided"` for clear section boundaries, or `"outline"` for tree-like rows. `indent` and `chevronPosition` should express structure without consuming the reading width. Use an `Outline` for a real interactive record tree; use a destination for a long independent task.

## CollapsibleView

Use `CollapsibleView` when a compact summary or trigger should expand into a temporary panel without pushing neighboring content: a HUD objective summary or on-demand team details. In Facet it opens on the page's modal layer without dimming the page. It is not inline disclosure.

Keep `label` or `compactLabel` useful in the closed state. `expanded` is the open state; keep the summary synchronized with the content. `initialFocus` should land on the useful starting point. `outsideDismiss` suits easy-to-reopen information; do not rely on it for an unfinished consequential edit. `dismissButton` gives an explicit closing route where needed. Verify cancellation and focus restoration to the trigger.

Use `DisclosureGroup` if the expanded content belongs in the reading flow, `Popover` for a small source-attached explanation, and `Sheet` for a task with a real editing lifecycle. Do not hide an urgent objective behind a collapsed summary that no longer says what the player must do.

## Popover

Use `Popover` for additional information or a small contextual interaction whose source remains meaningful: inspecting a stat definition or adjusting one contextual option. A large task should get a sheet or destination.

- `trigger`/`source` establishes the anchor; `edge`, `align`, `gap`, and `crossOffset` refine placement. Keep the relationship visible and avoid covering the value being explained.
- `compact = "sheet"` permits a usable alternate surface in constrained room; `"popover"` preserves an anchored panel where the content still fits. Do not force an unreadable postage-stamp panel for visual consistency.
- `modal` decides input isolation. Choose whether background interaction is safe, then test it; a tail does not answer that question.
- `cancelPolicy`, `closeButton`, and `onDismiss` define how it ends. Handle `anchorLost`: the information must not remain falsely attached to a different object after recycling or navigation.
- `maxWidth`/`maxHeight` should bound reading and preserve room; use scrolling or a larger surface rather than tiny text. `tail` is useful when it clarifies ownership, unnecessary when the source is already obvious.

Never put required understanding exclusively in hover behavior. The same explanation needs a focus/tap route.

## Callout

Use `Callout` for timely, anchored instruction: the first opportunity to use a new ability or a newly available customization feature. Use a persistent label/help route for information players may need repeatedly, and a `Notice` for a continuing condition.

Choose a stable `anchor`. The text should explain the benefit or next useful action, not narrate every visible control. Use `featureUsed`, `seen`, `sessions`, and `afterSessions` to make teaching relevant; use `onRetire` to preserve retirement. Do not repeatedly reintroduce a feature the player has already used or dismissed.

`priority` arbitrates competing guidance; do not let a tutorial compete with an immediate danger. `steps` should support a short coherent learning task, not a tour of every button. `actions` need clear outcomes, including a usable dismissal. `edge`, `align`, `tail`, and optional `media` should clarify the anchor and instruction without hiding the action it teaches. Suspend or defer guidance when gameplay demands attention.

## Alert

Use `Alert` when a short message and a small set of responses can resolve a consequential interruption. Describe the affected object, concrete consequence, and action. “Leave race and forfeit rewards?” is more useful than “Are you sure?”

`severity = "information"`, `"warning"`, or `"critical"` must correspond to actual consequence. Reserve stronger treatment for stronger stakes. Give `actions` specific verbs, a safe cancel route, and a sensible default. A confirmation should add information, not merely repeat a button label.

Use `item` or `presenting` when the decision belongs to a specific object so the prompt and action keep the same identity through updates. Alert dismisses before its action callback and clears a writable `error` on dismissal. If the interaction must remain open while a request is accepted or rejected, use a controlled `Dialog` or `Sheet` instead of assuming Alert owns that workflow. `suppression` is appropriate for repeatable low-risk information; do not let a previously checked “don't ask again” hide a materially new purchase or destructive consequence.

`surface = "fullScreen"` changes the presentation, not the amount of task an alert should own. Use it only when the bounded decision genuinely needs that treatment. Custom `content` and `maxWidth` should clarify the decision; if they grow into a form or comparison workspace, choose a sheet or destination.

## Dialog

Use `Dialog` for a bounded modal interaction with custom content beyond a short alert: a focused reward claim or a compact decision with an illustration and supporting detail. Use `Alert` when a short consequence and response suffice; use `Sheet` when the player is doing sustained work.

Choose `width` for the reading task, not the largest available option. `hero` should reinforce the object or outcome without pushing the primary decision out of view. `actionLayout = "automatic"` is a good starting point; stacked actions can preserve long labels in narrow room. `contentSelectable` makes an overflowing body a focusable scrolling stop; retain it when that is how keyboard/gamepad users reach the body.

The owner changes `isPresented` in response to `onPresentedChange`; Dialog does not write that state itself. Actions propose closing by default. Use an action's `keepOpen = true` for an Apply/Next action or pending workflow that must remain open, and close only on the appropriate accepted result. `onDismiss` observes closure. Distinguish cancel, outside dismissal, close, and completion where the task requires it. `closeButton` does not replace the need to decide what happens to an unfinished draft. A dialog should not reopen immediately after dismissal because an unchanged condition was treated as a fresh event.

## Sheet

Use `Sheet` for a temporary task that belongs to the current context: filtering inventory, editing a loadout draft, or inspecting and configuring an item. A task with deep history and repeated independent visits deserves a destination.

- `placement = "automatic"` generally docks at the bottom and centers for distant viewing. `"adaptive"` can also use the side when room and input support it. Force `bottom`, `side`, or `center` for an intentional composition; `edge` chooses the side.
- Choose `width = "narrow"`, `"wide"`, or `"automatic"` based on reading and comparison. More width should expose useful relationships, not stretch short labels across empty space.
- `detents` define useful task heights: a summary and an expanded working area, not arbitrary fractions. `medium`, `large`, `hug`, or custom fraction/height entries must each leave the current task intelligible. `detent` preserves the chosen height. A side sheet's detents remain vertical.
- `scrollPolicy = "always"` keeps body content reachable at each height. `"atLargestDetent"` requires expansion before scrolling; use only when that relationship is clear and the expansion route is accessible.
- `header` should identify the task. A `hero` may scroll or stay pinned; a large sticky image can steal the working area. `contentInset = "none"` is for content intentionally owning its interior spacing, not a shortcut to make an overcrowded form fit.
- `actions` are pinned task commands; they do **not** automatically close the sheet. Close after accepted completion when appropriate, and keep rejected work available. `actionLayout` must accommodate full labels and the smallest room.
- `onPresentedChange` guards dismissal. Leave `isPresented` unchanged while asking whether to discard a dirty draft. Route custom Cancel actions and other exits through the same guard. See `Sheet.dismissal` for the state pattern.
- `interactiveDismissDisabled` also blocks Back and backdrop dismissal. Use it only when the task requires protection and explicit actions provide a usable way out. Do not trap a player while a failed request remains pending.

Choose the visible exit after checking the built-in routes. A visible grabber on
a one-detent sheet closes on tap/click, Return or gamepad A. For a read-only task
with interactive dismissal enabled, use `closeButton = false` when a second
visible exit adds no value. A detent is a height, not evidence of an accessible
exit. With several detents, Return/A first expands the sheet. Keep an explicit
Close when a direct exit is needed, the grabber is hidden, or interactive
dismissal is disabled. Do not force a labeled Close merely because a recipe
has one. Test the chosen route and return focus with touch, pointer, keyboard
and gamepad.

Check software-keyboard and short-height layouts. Facet can move pinned regions into a scrolling column when necessary; verify all actions remain reachable. Native gameplay controls may be suppressed by modal presentation, but custom gameplay controls still require correct integration.

## Text

Use `Text` for readable information. Start with the semantic `textRole`: `title` for a destination/outcome, `heading` for a section, `body` for explanation, `label`/`control` for compact UI, `caption` for supporting context, `strong` for emphasis, and `numeral` for values that need rapid reading. Roles should form a visible hierarchy, not simply apply a different style to each line.

`role = "secondary"` reduces emphasis, not importance or the need for legibility. Use `wrap` and a sensible width for explanations. Use `lines`/`truncate` only where the missing text has a clear recovery route. Middle truncation can preserve distinguishing beginnings/endings of identifiers; end truncation fits prose-like titles. Never truncate the decisive part of a cost, warning, or action.

Use bounded text fitting only for content such as a short fixed-format score where it preserves readability. If a sentence needs to shrink to fit, revise the layout or wording. `direction` and start/end alignment support the reading direction. `rich` should provide restrained emphasis, not a different font/color for every statistic. Prevent live numeric changes from shaking neighboring labels through unstable widths.

## Label and ShortcutHint

Use `Label` for a named concept with an optional icon. `presentation = "titleAndIcon"` is clear while symbols are unfamiliar; `"titleOnly"` suits text-led content; `"iconOnly"` saves space only when meaning remains recognizable and a name is available. `iconPosition`, `gap`, and `iconSize` should keep the pair a single unit. A label does not become an action just because it has an icon; wrap interaction in an appropriate control.

Use `ShortcutHint` to display the input for a real action. Prefer an `action`-based hint when available so it follows bindings; explicit `keys` must remain truthful. `label`/`labelPosition` should connect the prompt to the verb. Displaying a key does not bind it. Update prompts with the relevant input without relocating the whole layout on incidental device changes. Show the command's current meaning: a Back prompt must not unexpectedly mean Delete in a different hidden mode.

## Badge and StatusIndicator

Use `Badge` for a compact annotation: rarity, item count, new content, or a short status. `appearance = "standard"`, `"status"`, or `"utility"` should match its role. `status` chooses semantic paint; pair important meaning with words or an icon. `iconPosition`, corners, and size should keep the badge subordinate to the object it describes. Too many badges flatten hierarchy.

Use `StatusIndicator` for a small signal attached to an existing object: presence, unread count, or condition. `form` (`dot`, `ring`, `square`, `dash`) can distinguish signals when color alone is insufficient. `count`/`max` should communicate a meaningful bounded count. Its accompanying name/label context must explain what the signal means. `cutout` and `diameter` should preserve separation from the host icon without obscuring it.

Neither is a substitute for a required warning or a button. If clicking a status should open detail, make that interaction explicit and reachable.

## Notice

Use `Notice` for a condition that continues to matter: disconnected service, unsaved changes, or a restriction affecting the current task. Keep it until resolved or until dismissal is genuinely safe.

`placement = "inline"` associates it with affected content; `"affixed"` keeps a broader condition visible. `severity` and `appearance = "emphasis"` should match urgency. Use `actions` or `link` for useful recovery, not several unrelated commands. `onDismiss` should have an intentional consequence; do not dismiss the only explanation for a blocked action while leaving the block in place. Keep the message concise and specific about what still works and what the player can do next.

## Toast

Use `Toast` for an acknowledgement that can safely expire: a reversible saved preference or a routine completed action. Use `Notice` for unresolved failure and `Alert` for a required decision.

Choose `duration` and `readFloor` so the message can be read; longer text is a reason to redesign, not simply occupy the screen indefinitely. `action` can provide Undo when the game actually supports recovery. Do not make an expiring action the only way to avoid serious loss. `closeButton` allows dismissal without blocking the task.

Use `key` and `priority` to combine or arbitrate repeated events. Match priority to consequence, not to whichever feature was implemented last. `position` should avoid active controls and urgent world information. `width`, `content`, and `fade` must preserve legibility. `onDismiss` distinguishes timeout, replacement, capacity, and action; disappearing due to queue pressure does not prove the player read it. Keep consequential results available in durable history or task state.

## ProgressView

Use `ProgressView` to answer “how much?” or “is work happening?” Use a determinate `value` with truthful `min`/`max` when completion is known. Use `presentation = "spinner"` for unknown duration without fabricating a percentage.

`bar` supports quick magnitude comparison; `circular` fits compact progress attached to an object. `segments` requires a bar and should correspond to meaningful stages or units. `showValue`, `format`, `label`, and `endLabel` should explain what is filling and what completion means. `trail` briefly holds the previous amount after damage, then settles; it snaps on healing or reduced motion. Keep the current value distinguishable from that trail. Choose `diameter` for circular/spinner forms and `thickness` for legibility. Use either the applicable explicit size or `controlSize`, rather than conflicting size settings.

For long waits, explain the operation and provide cancellation or recovery where valid. Do not reset a nearly complete meter to zero without explaining a new stage. A health meter should keep dangerous thresholds readable during action; visual flourish must not delay the actual state update.

## Timer

Use `Timer` for a deadline or elapsed time. Choose `deadline` for a countdown and `start` for elapsed time; use a consistent `now` time source so reconnects or frame timing do not produce a misleading clock. `hours` and `textRole` should fit the duration and urgency.

Use `onComplete` for the UI consequence, while authoritative game state owns actual eligibility and rewards. A displayed zero does not independently authorize a match result. Increase emphasis near a meaningful deadline with multiple cues, not only color or continual flashing. Do not show unnecessary fractions that create visual noise without helping action.

## Skeleton and ErrorBoundary

Use `Skeleton` when the structure of incoming content is known and a stable placeholder helps orientation. `form = "line"`, `"box"`, or `"circle"`, `lines`, and corners should roughly match the expected content. Reserve dimensions to avoid layout jumps. Do not use skeletons as fake content or leave them indefinitely after failure. Use a progress indicator when the structure is unknown and an empty state when loading finished with nothing.

Use `ErrorBoundary` to contain a rendering failure in one region so surrounding navigation and recovery remain usable. `view` builds the region; `fallback(failure, retry)` builds a clear replacement; `onError` reports the failure. Give the fallback useful context and a working retry or route away. It does not handle every server rejection, empty data set, or invalid field: those are ordinary designed task states. Place boundaries at coherent recoverable regions, not around every label.

## Image and AsyncImage

Use `Image` for available visual content. `scaleMode = "fit"` preserves the entire subject; `"crop"`/`"fill"` can create a consistent frame when lost edges are unimportant; `"stretch"` is appropriate only when distortion is intentional. Tile and slice modes suit repeatable textures and framed assets, not arbitrary illustrations. Use `resample = "pixelated"` for intentionally pixel-based art. `shape` and `tint` must preserve identity and meaning.

Use `AsyncImage` when loading/failure is part of the content's lifecycle. `image`, `source`, or `resource` should identify the correct asset; `loader` handles the chosen loading route. Provide `placeholder` for loading/ready/failed states as appropriate and a useful `failureLabel`. Reserve aspect ratio and dimensions while loading. `onStatus` can coordinate surrounding state; the image arriving must not unexpectedly steal focus or resize the primary action. Use `dimmed` only when reduced emphasis conveys a real state. A failed cosmetic preview must not erase the object's name, price, or eligibility.

## Avatar and AvatarGroup

Use `Avatar` for person/player identity. Keep `name` available even when an image is present; similar faces or failed images cannot be the sole identifier. `userId`, `image`/`resource`, and an icon fallback should all refer to the same person. `form`, `diameter`, `backplate`, and background should fit the density without turning identity into decoration.

Use `presence`, `presenceLabel`, and `presenceMark` only for meaningful, truthful presence. “Online” is not automatically “available to join.” `onActivate` should have a clear outcome such as profile or contextual actions. Keep target identity through asynchronous updates.

Use `AvatarGroup` for a compact group summary. `layout = "stacked"` emphasizes membership in a group; `"spread"` supports distinguishing individuals. `max` and `overflow = "count"`/`"ellipsis"` control density, and `onOverflow` with `overflowLabel` must expose omitted members when they matter. Do not hide the only target of an invitation/removal task in an unexplained overlap. A group needing individual comparison deserves a list.

## Stage

Use `Stage` for a 3D preview when viewing the actual form, material, or customization helps a decision. Use an image when a static illustration communicates equally well at less cost.

Choose `camera` and `fieldOfView` to keep the relevant object visible and proportionate. The content lifecycle must be owned through `content(runtime, world, live)`. Use `lazy` deliberately for previews that need not be created until useful, and provide a stable loading representation. Rotation and animation should serve inspection; offer a stable view and preserve reduced-motion expectations. A cinematic camera angle must not hide equipment, exaggerate proportions, or make two variants impossible to compare. Keep price and commitment outside ornamental 3D motion.

## Typewriter

Use `Typewriter` for paced dialogue or narrative reveal when that pace contributes to the experience. Use ordinary `Text` for urgent instructions, errors, menus, and information players need to scan repeatedly.

Provide a finish/skip action using `controls.finish`, then let a subsequent deliberate action advance the dialogue. `controls.revealed` can distinguish those states. `onRevealed` also runs when skipped or shown instantly under reduced motion, so progression must not depend on an animation duration. A new `text` restarts reveal; avoid rebinding the same line through incidental state changes. Preserve rich text as a whole rather than slicing markup. Offer durable access to dialogue when remembering it affects later play.

## Flash and Travel

For when to rely on built-in motion, how to coordinate effects, and how to handle interruption, use [Motion and feedback](MOTION_AND_FEEDBACK.md#choose-the-facet-motion-mechanism). These individual controls are part of that broader decision.

Use `Flash` to draw brief attention to a meaningful change in a known target. `mode = "pulse"` or `"sweep"`, `color`, and `progress` should make the event understandable without repeated visual assault. Do not use flashing as the only indication of danger, success, or a changed value. Favor restrained one-time feedback and respect reduced motion.

Use `Travel` when a visual moving between slots explains ownership or state change: an awarded item arriving in inventory or a selected part moving into an equipment slot. Keep `destination` mounted, choose `path = "straight"` or `"arc"` for clarity, and use `motion = "ease"` or `"spring"` to fit the game's character. `lift`, `stagger`, and transparency can separate simultaneous movement, but excessive sequencing delays understanding.

`onStarted`/`onLanded` can coordinate visual feedback. Authoritative ownership must not depend solely on the animation finishing; interruption and reduced motion must preserve the result. Show the final count or equipped state promptly. The player should not need to follow a flying icon to learn whether an action succeeded.

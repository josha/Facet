# Designing game interfaces with Facet

A good game interface helps players understand the situation, make a decision, act, and recognize the result. Its structure follows the game. Its appearance expresses the game's character. Its behavior stays clear when content grows, space decreases, or the player changes how they interact.

Choose each control for the information or interaction it represents. Choose each container for the relationship between its contents. Decide what deserves attention before deciding where it goes.

For an unfamiliar design, make the choice in this order:

1. Identify whether the player needs to read, choose, act, adjust, or navigate.
2. Identify what the information or action belongs to: the whole game, the current task, or a specific object.
3. Decide whether it stays visible, expands within the layout, appears temporarily over it, or opens another destination.
4. Choose the control that owns that behavior, then choose its placement and compact forms.
5. Compare it with the nearest alternative. State the task-specific reason for the choice, and check the behavior in the rendered interface.

For example: “Use DisclosureGroup because these optional tuning values belong in the settings page and should push later rows down. A CollapsibleView would open a separate panel.” This is a useful design rationale. “Use it because it looks cleaner” does not explain the interaction.

## How to use this guide

This guide begins with the principles that make any interface understandable and satisfying, then applies them to the attention, timing, and control demands of games. The chapters translate those principles into complete flows, visual design decisions, Facet controls, and interaction capabilities. The principles, chapters, and index form one guide.

For a new screen, read the foundations here and the design workflow, then the relevant task chapters. For a local control decision, use the index and compare the nearest alternatives before choosing. Read adaptive interaction for how the task works across input methods, input/focus for ownership and navigation, and motion for how changes are communicated. A capability being available is not a reason to put it on the screen.

| Design question | Chapter |
| --- | --- |
| How do I establish visual direction, develop a screen, and judge its quality? | [Design workflow and critique](game-ui/DESIGN_WORKFLOW_AND_CRITIQUE.md) |
| How do I design a complete HUD, inventory, shop, lobby, onboarding, or results flow? | [Game flows and information](game-ui/GAME_FLOWS_AND_INFORMATION.md) |
| How should information be grouped, arranged, and navigated? | [Layout and navigation](game-ui/LAYOUT_AND_NAVIGATION.md) |
| How should players browse, compare, select, edit, and act on objects? | [Collections and actions](game-ui/COLLECTIONS_AND_ACTIONS.md) |
| How should players choose values, enter information, and commit changes? | [Choices and input](game-ui/CHOICES_AND_INPUT.md) |
| What should interrupt, expand, explain, load, or confirm? | [Surfaces, information, and feedback](game-ui/SURFACES_INFORMATION_AND_FEEDBACK.md) |
| How should acting on visible objects adapt across touch, pointer, keyboard, and gamepad? | [Adaptive interaction and direct manipulation](game-ui/ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) |
| When and how should I animate changes, transitions, or feedback? | [Motion and feedback](game-ui/MOTION_AND_FEEDBACK.md) |
| Who owns input, where does focus go, and how does everyone reach the task? | [Input, focus, and access](game-ui/INPUT_FOCUS_AND_ACCESS.md) |
| When should I use a particular Facet control or interaction capability? | [Control and capability index](game-ui/CONTROL_INDEX.md) |

The control guidance covers the 71 public controls in the inspected Facet 0.12.0 reference, with separate guidance for motion, drag/drop, focus, command scopes, input ownership, environment adaptation, themes, and feedback. It explains design-significant options rather than reproducing every callback, native property, or implementation type. Verify exact signatures against the installed version when implementing. Do not invent a configuration because a familiar pattern usually has one. Coverage is a way to find guidance, not proof that a resulting design is good.

## What makes an interface good

An interface succeeds when players can form the right expectation, recognize their choices, act with appropriate effort, and understand the result. Great interfaces also have rhythm, character, and a sense of care: important moments feel important, routine work feels effortless, and the visual treatment belongs to the game.

These qualities are related. A beautiful surface that conceals the selected item is unclear. An efficient interface that repeatedly causes accidental purchases is poorly controlled. A highly consistent layout that treats every situation as equally urgent has no useful hierarchy.

| Principle | What it asks of the design | Concrete consequence |
| --- | --- | --- |
| Purpose | Every element helps a player understand, decide, act, recover, or enjoy an intentional moment | Remove a statistic that answers no current player question; retain atmosphere that contributes to the experience without obscuring the task |
| Hierarchy | The most important information is noticed at the right moment | One clear outcome before detailed results; an immediate hazard ahead of routine rewards |
| Grouping | Proximity, alignment, similarity, and boundaries communicate real relationships | Keep price beside Buy; use shared columns for comparable attributes; avoid a separate panel around every label |
| Legibility | Content can be perceived under actual viewing conditions | Read text over gameplay, allow long labels, preserve contrast and target size before decorative space |
| Affordance | Appearance suggests what can happen and how | Buttons look actionable; selected state differs from focus; a slider visibly offers adjustment |
| Predictability | Equivalent actions behave consistently and different actions are distinguishable | Keep Back semantics and radial directions stable; distinguish preview from purchase |
| Recognition | Necessary context is visible instead of relying on memory | Show the current loadout beside its proposed replacement; label unfamiliar icons |
| Appropriate effort | Interaction cost matches frequency, complexity, and consequence | Make frequent safe actions direct; give consequential commitments sufficient review |
| Feedback | State changes have timely, proportionate, truthful responses | Show pressed, pending, accepted, and rejected states; do not celebrate merely sending a request |
| Control and recovery | Players can cancel, correct, undo, or leave where the task permits | Preserve drafts after rejection; offer clear exits; prevent accidental destructive gestures |
| Adaptation | The task survives changes in room, input, content, and ability | Compact comparison still supports comparison; every required command remains reachable |
| Character | Visual and interaction choices express a coherent identity | Repeat purposeful shape, type, material, and motion; avoid decorative exceptions that erase meaning |

### Compose a screen rather than decorate components

Establish a small visual vocabulary: type roles, spacing rhythm, surfaces, semantic colors, action emphasis, focus treatment, and motion. Apply it to relationships across the screen. An individually attractive button can still be wrong if it competes with five equally bright secondary actions.

Use alignment to reduce searching. Similar records should put comparable information in the same place. Keep spacing within a group tighter than the gap between groups. A boundary should separate meaningful objects or tasks; excessive nested borders make hierarchy harder to see. Whitespace is useful when it clarifies relationships or gives an important moment room. Empty space that forces essential controls offscreen is not refinement.

Choose density according to the task. Comparison benefits from seeing several relevant records together. Action gameplay benefits from a protected world view and brief glances. A quiet reward moment can support a large illustration. Do not apply one tile size or one minimal layout to all three.

Use visual weight intentionally. Large size, strong contrast, central placement, isolation, and motion all attract attention. If a secondary heading has more of these than the primary decision, change the composition. Preserve a clear reading edge for longer text and stable alignment for changing numbers. A decorative background should not be the strongest signal on a screen whose purpose is choosing equipment.

Establish a coherent aesthetic, then make it serve meaning. Angular panels may express machinery, soft shapes may express playfulness, and restrained animation may express precision. Those choices do not excuse unreadable text, misleading controls, or inconsistent states. Delight is strongest when it reinforces an understandable event, such as an earned upgrade visibly arriving in its slot.

### Spend interaction effort where it buys something

Each opening, focus move, selection, mode switch, and confirmation costs attention. Add a step when it improves understanding, prevents a meaningful error, or permits a richer task. Remove a step when it only repeats what the player already knows.

A menu can reduce clutter but increase discovery and traversal cost. Direct buttons improve access but consume space and focus stops. Selection followed by a command adds a step but supports comparison and deliberate commitment. Inline editing minimizes travel but can expose accidental edits. Choose among these costs explicitly rather than treating fewer visible controls as inherently better.

Use the same reasoning for errors. A reversible filter can change immediately. A permanent deletion needs clearly stated consequences and appropriate confirmation or recovery. Making every action ask for confirmation teaches players to ignore confirmations; making every action immediate creates avoidable loss.

## What changes when the interface is part of a game

The game world is already an information display and interaction surface. UI must compete with motion, sound, targets, goals, other players, and the player's own actions. The right interface depends on the current loop, not only the game's genre.

| Play situation | What matters most | Design response |
| --- | --- | --- |
| Continuous action: driving, aiming, dodging | Fast perception while movement and camera input remain occupied | Stable glanceable HUD, direct urgent actions, restrained notifications, protected sight lines |
| Brief tactical choice during ongoing play | Quick recognition, clear target, predictable cancellation | Small stable command set; shallow menu/radial only if its input and occlusion costs are acceptable |
| Planning, building, inventory, or loadout work | Comparison, precision, and reliable commitment | Collections, tables, previews, useful detail, direct editors, and explicit draft/application boundaries |
| Turn-based decision | Understanding alternatives and consequences before commitment | Show rules, costs, predicted effects, current selection, and a clear commit route; do not hide information merely because time pressure is low |
| Results and progression | Understand outcome, cause, reward, and next opportunity | Outcome first, then decisive explanation, rewards, deeper statistics, and a meaningful next action |
| Narrative or discovery | Pacing, atmosphere, comprehension, and agency | Deliberate reveal and transitions, skip/finish control, readable dialogue, durable access to information needed later |
| Social and collaborative activity | Identity, scope, permission, and timing | Name who an action affects; distinguish personal from group state; show invitation/message status and avoid accidental submission |

An interface can move between these situations in seconds. A racing game may need a glanceable speed display, a precise tuning table, an expressive finish sequence, and a social invitation sheet. Designing all of them as a driving HUD or all of them as a spacious destination menu is equally limiting.

### Preserve the player-world relationship

Decide which information belongs in the world, which belongs on a stable HUD, and which belongs in a task surface. A marker on a target makes ownership clear but may be occluded, offscreen, or moving. Stable HUD information is more consistently readable but can become detached from what it describes. Use the relationship that answers the player's question, and provide a fallback where losing visibility would hide critical information.

Protect the sight lines needed for the game: the route ahead, opponent silhouettes, aiming area, landing zone, or interaction target. Fingers, cursor travel, focus movement, and menu scrims also consume this space. A centered panel can be appropriate during deliberate planning and harmful during an unavoidable hazard.

Explicitly define whether opening a menu pauses local action, releases steering, blocks attacks, or leaves the world running. A modal surface only establishes an input relationship; it does not establish a gameplay rule. In shared live play, the world may continue regardless of the local interface. Make interruption, timeout, target loss, and reconnect behavior understandable.

### Make changing information stable enough to use

Live data should update without constantly rearranging the player's targets. Keep record identity, focus, and pending commands stable through sorting, new items, and changing scores. A leaderboard may animate rank changes, but an open context menu must remain attached to the racer it names. A changing resource total should not move the adjacent Buy button under a finger.

Use transient emphasis for meaningful changes, then let the screen settle. Continual pulses, particle effects, ticking decimals, and repeated banners create attention debt. Combine routine rewards and defer celebration during demanding play. Reserve persistent urgency for conditions that still require attention.

Keep instructional information distinct from fictional presentation when players need reliable guidance. A stylized damaged display can contribute to atmosphere, but essential navigation, captions, and recovery routes must remain usable. Challenge should come from the intended game decisions, not accidental illegibility or unexplained input capture.

## Start with the player's next decision

Describe the task in player language: choose a vehicle, equip an item, find a teammate, understand a defeat, or react to a hazard. “Display inventory data” describes an implementation, not a player task.

Identify four things:

- **Situation:** What is happening, and does gameplay continue while the interface is open?
- **Decision:** What must the player understand before choosing?
- **Action:** What can the player do, and what does that action affect?
- **Result:** How will the player know the action worked, failed, or is still pending?

A vehicle selector might answer: “Choose a vehicle for the next race. Compare handling and speed against the current vehicle. Equip the selection. Show which vehicle is equipped.” That suggests a collection, a comparison area, an Equip action, and a confirmed state. It does not yet imply a grid, a full-screen menu, or a modal sheet.

Also identify the pace of use. A brief glance during a race, a quick equipment change, and a careful loadout comparison need different amounts of information and different navigation costs.

For a small repair, state the broken relationship directly: “The notification covers the action the player still needs.” A large specification is unnecessary when the defect is already clear.

## Establish an attention order

Treat the game world, HUD, menus, feedback, and controls as one composition. They all compete for the player's attention.

For each important state, name what the player should notice first, second, and third. Judge the rendered screen against that order. Do not assume that putting something first in a component tree makes it visually important.

| Information role | Give it this treatment |
| --- | --- |
| Immediate consequence | Show it where the player can notice it in time to act. Use a distinct signal and a clear response. |
| Current task and its main decision | Establish a stable focal area with the information and actions needed to proceed. |
| Supporting context | Group it near the decision it explains, with less emphasis. |
| Optional detail | Make it discoverable without requiring everyone to read it. |
| Decoration and atmosphere | Use it to support identity and mood without competing with meaning. |

Importance changes with the situation. Currency is supporting context while driving and essential decision information before a purchase. A timer may be quiet early in a round and urgent near its end. Establish those changes deliberately; do not make every changing number flash.

Use scale, contrast, placement, spacing, and motion together. Motion is especially demanding: reserve repeated animation for information that deserves repeated attention. If everything is bright, large, outlined, or moving, the screen has no useful hierarchy.

Group an action with the object and consequence it affects. Place an item's cost near its purchase action. Place a setting's value beside its label. Keep an explanation of a blocked action close enough to be found before the player retries it.

One dominant action is a useful default for a decision panel. It is not a rule for all game interfaces. A player may need steering, braking, and an ability at the same time. Preserve the relative importance of those actions instead of forcing them into a single-button hierarchy.

### Protect the game view

During active play, reserve the area needed to see movement, hazards, targets, the player character, and important world feedback. Reserve space for fingers and controls as well as visible UI art.

Choose whether the interface supports a glance, a brief decision, or a dedicated task. A glance should not demand paragraph reading. A detailed management view should provide enough space to compare information. If a panel takes control away from gameplay, that must be an intentional part of the interaction.

World-attached information can make the relationship to a target clear. Use it when the target is visible and the information belongs to that target. Use a stable screen region when the player must read the information regardless of camera angle, distance, or occlusion. A health display attached to a character is not sufficient if critical health becomes unreadable during the actions that consume it.

## Choose what survives when space runs out

Design the narrow form as a complete way to perform the task. Wider forms can expose more context and reduce navigation. Additional space should improve understanding rather than merely enlarge every element.

Classify content by the cost of hiding it:

| Class | What it means | Behavior under space pressure |
| --- | --- | --- |
| Needed now | Missing it prevents a timely action or hides an immediate consequence | Preserve a usable visible form. Do not move it behind another interaction. |
| Needed before commitment | The player must inspect it to choose correctly | Keep it available with the decision. It may move to a detail step before commitment. |
| Useful on demand | It explains, compares, or helps plan, but is not needed continuously | Collapse to a summary or move behind a clearly named entry point. |
| Ambient or decorative | Removing it does not impair understanding or action | Remove it before sacrificing meaningful content. |

Classify the individual information, not just the whole panel. A vehicle panel's title, illustration, price, and statistics can have different priorities.

For each region, specify its **rich form**, **compact form**, **minimum useful form**, and **destination for omitted detail**. Do not confuse a minimum useful form with the smallest rectangle the renderer can produce.

Reduce space in a deliberate order:

1. Remove decorative excess and redundant labels.
2. Reflow related content while preserving reading order.
3. Use shorter meaningful summaries or familiar symbols with accessible names.
4. Move optional detail behind an explicit action.
5. Remove an entire region only when its information can safely wait or has another usable route.

This order is a starting point. A specific task may justify moving optional detail before rearranging an established control group. Preserve text legibility and usable targets throughout.

“Falls off” must mean something concrete: suppressed until later, represented by a summary, or reachable elsewhere. It must not mean silently lost. Critical controls, the current selection, transaction terms, and a way out of an open task need a usable home.

### Express priority with Composition and Region

Use one `Composition` for HUD regions that share the available screen area. Use a `Region` for each coherent group. Its `zone` expresses placement and its `rank` expresses importance: `rank = 1` is most important; larger numbers give way earlier when the relevant area does not fit.

Give each region candidate forms in order from richest to smallest. Facet measures the forms and selects among them. Rank alone cannot make a large region fit, and it does not determine what its compact version means. The designer must supply useful alternatives.

Use `mayDrop = true` only when the entire region can leave the main view. Facet's reveal behavior can expose reduced or hidden content through a popover and reveal affordances. Decide whether that extra interaction is acceptable. A hidden scoreboard can remain useful through reveal; a hidden brake button cannot.

If the game supplies a different route to hidden content, use the region's `form` state to keep that route meaningful. A value of `0` indicates a hidden region. Disable `reveal` only when the reduced form loses no necessary information or a suitable alternative has been provided. Check the alternate route in the actual compact layout.

Keep forms measurable. A form that fills whatever width it receives does not describe how much space its content needs. Fit warnings require a smaller useful form, a better arrangement, or a justified omission; they are not permission to shrink the entire screen.

Within a `Composition` region, let its forms express adaptation. A separate local size switch can make a region's visible result disagree with the alternatives the composition is measuring.

### Worked example: a race HUD

Suppose the HUD contains driving actions, an active hazard warning, placement and lap, a minimap, full standings, and a reward announcement.

| Region | Importance in this race | Rich form | Minimum useful form | What can leave the main view? |
| --- | --- | --- | --- | --- |
| Driving actions | Needed now | Readable actions and supporting state | Usable targets with recognizable labels or symbols | No required action |
| Active hazard | Needed now while the hazard matters | Hazard, direction, and useful timing | Recognizable hazard and direction | Supplementary explanation |
| Race progress | Needed now | Placement, lap, and progress context | Placement and lap | Secondary timing detail |
| Minimap | Depends on whether it supplies essential route knowledge | Map with nearby context | Simplified route cue if that preserves the needed information | Only genuinely optional map detail |
| Full standings | Useful on demand | Several racers and gaps | Player and nearby rivals | Full table, through Standings |
| Routine reward | Can wait | Reward summary | Small acknowledgement or queued result | Celebration, until a safe moment |

Assign lower rank numbers to the protected regions and larger numbers to optional ones. This order belongs to this race design: a navigation-heavy game may need to protect its route display as strongly as its controls.

On a narrow view, the result should still explain the race and allow every immediate action. Removing a minimap is acceptable only if the remaining route information is sufficient. A decorative reward animation should never win space over a hazard warning simply because it mounted later.

## Translate the decision into controls

Choose the behavior before its visual form. A horizontal strip might be a `Picker` value or `TabView` navigation. A row might activate an object, select it for comparison, or expose an editable field. A panel might be optional explanation, a decision, or an entire task. Similar appearance does not imply interchangeable behavior.

Use these decisive questions:

1. **Sequence, collection, or comparison?** Use a stack for ordered sections, a list/grid for repeated browsable objects, and a table when shared attributes must be compared. Use an outline only for a real hierarchy.
2. **Action, selection, or value?** Use a button for a verb, selection for an object under consideration, and a field/picker for a value. Keep focus, selected, equipped, locked, and pending states distinct.
3. **Immediate or deliberate?** Apply safe reversible changes directly. Add preview/review and commitment when comparison, coupled fields, or consequences justify it.
4. **Inline, anchored, modal, or destination?** Use inline disclosure for details that belong in the flow; anchored content for a local relationship; a modal decision/task only when attention must move there; navigation for substantial independent work.
5. **Direct, row-local, contextual, or bulk?** Expose frequent important verbs directly; use row actions for object commands, editors for values, context menus for secondary commands, and explicit selection modes for sets.
6. **Which information survives?** Preserve immediate controls and decision-critical context. Author compact forms and routes to omitted details, then test the actual transitions.

Use the task chapters for the configuration tradeoffs. The [control index](game-ui/CONTROL_INDEX.md) provides a complete route from each Facet control to its design guidance.

### Use the control, not a copy of it

A HUD often grows from native frames: a bar made from two frames, a row of round frames for charge pips, a list of rows for standings, a plate with a word in it for every callout. Each copy works on the day it is written. It does not get the theme's paint and type, scaled metrics at ten feet, reduced motion, an accessible name, a compact form or the next fix to the control. The game then has two visual languages, and the hand-built one drifts.

| What the player reads | Control | Not |
| --- | --- | --- |
| How full: health, charge, energy, a gauge of collected items | `ProgressView`; `segments` for pips or discrete units; `trail` for a loss | Two frames with a scaled fill; a row of circles |
| How long: a countdown, a race clock, a remaining effect | `Timer`, or a `ProgressView` for the time left | A text label set every frame |
| Who is where: standings, results, a scoreboard | `Table`, bounded | Rows of hand-placed labels |
| A short state of an object: safe, new, ready | `Badge` or `StatusIndicator` with a word | A colored frame alone |
| An acknowledgement that can expire | `Toast` with `key` and `priority` | A chip shown by a timer |

Use native objects through `Host` only for content that no control shows: a minimap, a 3D view, illustration. When a control lacks something the game needs, for example a different color for each charge tier, extend the control or its theme rules. That fix then serves every screen. Do not replace the control with a native copy to get one look.

### Worked decisions across different game tasks

| Task | Design reasoning | Control decisions |
| --- | --- | --- |
| Choose and equip a vehicle | Appearance identifies candidates; attributes support comparison; equipping is distinct from browsing | `VirtualGrid`/`Card` for candidates, `NavigationSplitView` for detail when room allows, `Table` for meaningful comparison, separate Equip `Button`; `CellEditor` for a nickname and `Menu` for rare object commands |
| Manage crafting ingredients | Players need exact quantities, valid recipes, and an explicit cost | `VirtualList` or `Table` according to comparison needs; `Stepper`/`NumberInput` for quantities; preview resulting cost; commit Craft once; persistent `Notice` if requirements fail |
| Choose a tactical command on a teammate | Target identity and fast recognition matter; gameplay may continue | An anchored `RadialMenu` only for a small stable set with acceptable input cost; otherwise readable `Menu`; keep the teammate named, invalidate target loss, and preserve a cancel route |
| Sell several items | The operation affects a set and may include restrictions | Collection multiple selection with explicit Select/Done, visible count and eligibility summary, named Sell action, review/confirmation proportional to loss; disable full-swipe commitment for costly deletion |
| Adjust accessibility or audio | Independent values need readable labels, immediate feedback, and safe experimentation | `VStack` of `Toggle`, `Slider`, `Picker`, and precise fields; `DisclosureGroup` for optional details; no table merely because settings are rows; immediate reversible preview where appropriate |
| Plan a route through a skill tree | Connections and spatial relationships matter, but text and costs must remain legible | `ZoomView` and `Path` for the spatial structure, a stable selected-node detail area, explicit Unlock; pan/zoom alternatives, readable selection, no automatic purchase on focus |
| Present a match result | Outcome and cause matter before the full record | `VStack` for the personal result, `ProgressView` for meaningful progression, bounded `Table` for standings, `Travel` only if it clarifies the reward's destination, clear next action |

These are starting decisions, not templates to copy regardless of context. Explain what is true of the particular game that makes the choice appropriate.

## Adapt to input, distance, and pace

Available space, precision, viewing distance, and active gameplay are independent constraints. A large image resolution does not guarantee readable text from far away. A small screen can still have a gamepad. The design must respond to the relevant facts rather than assuming one device label determines them all.

### Touch

Give frequent actions reachable targets with separation from neighboring actions and gestures. Test what the finger covers. Keep essential commands available without hover. Provide an alternative to precise dragging and sustained holds where those would block access.

Do not reduce a required target to preserve an illustration. Use the environment's target sizing and give thumb-operated gameplay buttons the appropriate target treatment. Keep visible art and the effective hit area aligned with what players expect to press.

### Pointer and keyboard

Use pointer precision for direct selection and efficient manipulation. Hover can enrich a preview, but essential information needs a reachable equivalent. Shortcuts should accelerate commands that also have a discoverable path. Text entry and menu input must not unexpectedly trigger gameplay actions.

### Gamepad

Make focus unmistakable and movement predictable. Support digital navigation as well as analog interaction. Preserve focus when opening details and restore it when returning. Show prompts for the current action bindings rather than assuming a particular printed button label.

Use shoulder navigation for peer groups where it reduces repeated traversal; `TabView` supplies this behavior for its pages. Keep an obvious way to move back and leave a task. Avoid making every small adjustment require navigating to a distant Apply button unless the settings really need an explicit commitment step.

A gamepad cursor can help with freeform maps or dense spatial inventories when it demonstrably improves the task. It is not a default replacement for clear focus navigation. Provide a digital route to important functions and compare the effort of cursor travel against discrete selection.

Do not infer gameplay interaction from distant viewing alone. Large focusable tiles may suit a simple destination menu, while a loadout screen needs efficient comparison and rapid repeated actions. Use the necessary density with readable type and clear focus; do not turn every game screen into a sequence of oversized cards.

### Preserve the action while changing its presentation

The same semantic action may be a direct touch button, a keyboard shortcut, and a gamepad binding. The same detail may be an adjacent pane with ample room and a destination with Back in constrained space. Preserve the selected object, terminology, result, and available functionality through those changes.

Direct manipulation also spans input methods. Touch contacts an object directly; a mouse manipulates it through a pointer; keyboard/gamepad can pick it up, navigate to a target, and place it through focus. Keep the operation and its rules consistent while adapting targeting, feedback, and commitment to feel natural. Facet provides these routes for supported controls and manipulation APIs; the game still chooses their meaning and resolves competing intentions. See [Adaptive interaction and direct manipulation](game-ui/ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) for the shared model, automatic behavior, and authored choices.

Use actual layout room and environment facts to choose forms. Input hints can change without rearranging an entire screen. Avoid abrupt layout changes caused by incidental input switching.

### Preserve perception and access

Do not make color, sound, vibration, animation, hover, or a precise gesture the only carrier of required information. Pair a danger color with a readable symbol or message; pair a critical sound with an appropriate visual cue; provide digital routes to required drag or analog interactions. Captions should identify the speaker and relevant sound meaning without covering the active target or dialogue choice.

Give controls meaningful names, coherent reading/focus order, and distinct states. Unavailable and read-only are different: a read-only value may still need selection, copying, and full contrast. Respect preferred text size by reflowing and growing content, then test the resulting task rather than assuming a larger font alone solves readability. Respect reduced motion while preserving the final state and the explanation of what changed.

Test distance independently of input. A gamepad at a desk can support denser comparison than the same gamepad viewed across a room. Distant viewing requires readable type, strong focus, and suitable margins, but it does not remove the game's need for precision, rapid repeated commands, or simultaneous comparison. Large resolution is not evidence of readable angular size.

Use the existing Facet theme's semantic type, spacing, color, surface, target, and motion roles to make these relationships consistent. Change the shared visual language deliberately; avoid overriding individual controls until selected, focused, busy, and disabled states no longer agree across the game.

## Make the visual language coherent

Reuse the game's type roles, spacing, surfaces, shapes, icons, color meanings, and motion. If the game has no visual language yet, establish a small one before designing each screen independently.

Give each visual difference a job. Distinguish selected, focused, equipped, locked, and pending states. Do not encode all of them as different bright border colors. Important color meanings need another cue, such as a label, symbol, or shape.

Keep labels readable against the actual rendered background, including bright effects and busy scenery. Use a backing surface when the scene cannot provide reliable contrast. Keep secondary text quiet without making it illegible. Allow text to wrap and containers to grow where the task permits; do not use automatic shrinking to conceal missing space.

Use consistent alignment and restrained emphasis. Short centered labels can work well on buttons; longer explanations usually need a clear reading edge. A heading, main value, and supporting label should have visibly different roles. Establish a consistent treatment for numbers that players compare quickly.

Express character through deliberate illustration, typography, material, shape, and feedback. Decorative detail should reinforce the game's mood and objects. It should not make unrelated actions look identical or unrelated statuses look urgent.

## Design change, failure, and interruption

Specify normal, empty, loading, unavailable, error, and content-extreme states that the interface can actually encounter. For actions that depend on a server response, distinguish request sent from result confirmed. Optimistic feedback needs an understandable rejection path.

Motion should explain what changed, preserve orientation, or celebrate an event worth celebrating. Keep routine operations responsive. Do not restart an elaborate entrance each time the player switches a familiar tab. Reduced motion must retain the information and clear state changes.

Design competing surfaces together. Decide how notifications, contextual help, menus, text entry, and critical warnings coexist. Keep overlay ownership clear so an input cannot activate both an overlay and the covered control.

For costly or destructive actions, show the object, consequence, and an explicit action verb before commitment. Use confirmation or recovery according to the cost of a mistake. Avoid making every harmless action pay the cost of a warning dialog.

## Design the complete task, not only its successful frame

For each important interaction, specify:

- **Entry and ownership:** what opened it, which object/set it concerns, where focus starts, and whether gameplay continues.
- **Working state:** what can be inspected, previewed, selected, edited, or repeated without commitment.
- **Commitment:** the named operation, its target and cost, eligibility, and the point at which the accepted state changes.
- **Feedback:** immediate input acknowledgement, pending state, confirmed result, and a truthful rejection path.
- **Exit and return:** Back, Cancel, outside dismissal, successful completion, target disappearance, and restored focus/scroll.
- **Adaptation:** the useful minimum form, omitted-detail route, long text, keyboard visibility, input alternatives, and reduced motion.

A minimal interaction specification can be a few sentences. A complex transaction needs more. Do not build an elaborate specification for a one-line label fix, but do not leave a purchase flow's failure state implicit.

Useful empty states distinguish “nothing exists,” “nothing matches,” “not yet loaded,” and “not permitted.” Each needs a different next step: create, clear filters, wait/retry, or explain eligibility. Loading skeletons are not empty-state content. A temporary error is not proof that a collection contains no items.

For live requests, prevent duplicate commitment where it would cause duplicate consequences. Keep accepted state authoritative, preserve drafts on recoverable rejection, and make retry scope clear. After deletion or removal, focus should move to a useful neighboring object or parent action rather than disappear.

## Review the rendered interface

Technical verification and design review answer different questions. Passing types, layout audits, and input checks does not establish a good hierarchy or a coherent visual result.

Use the [design workflow and critique](game-ui/DESIGN_WORKFLOW_AND_CRITIQUE.md#evaluate-comprehension-and-behavior) for evidence to collect, repair priorities, and worked examples. Evaluate the whole task as well as individual controls.

Inspect the actual screen at representative sizes, expanded text, relevant input methods, and the content extremes that can occur. Include real gameplay behind overlays. Verify interactions rather than inferring them from a screenshot.

Ask these questions in order:

1. Can the player understand the situation and identify the next useful action?
2. Does the intended first, second, and third point of attention match the visible screen?
3. Can the player still see and operate everything required during active play?
4. Do container boundaries, alignment, and spacing explain relationships?
5. Does every compact form preserve its purpose and expose omitted detail appropriately?
6. Can the task be completed, cancelled, and recovered using each supported input method?
7. Are states, consequences, and pending results distinguishable?
8. Does the screen belong to the same game as its neighboring screens?

Describe defects concretely: location and state, observed problem, player impact, and repair. “Cluttered” becomes “five bright secondary actions compete with Equip.” “Bad spacing” becomes “the price appears attached to the next item.”

Fix blocked actions, accidental overlap, clipped essential content, unreadable information, misleading state, and focus traps before optional polish. Do not average those defects into a score that can pass because the art is attractive.

After a repair, inspect the affected state and adjacent layouts. For substantial new screens, test the full task with someone who has not memorized the design. A screen is successful when players understand and use it, not when its author can explain how it was intended to work.

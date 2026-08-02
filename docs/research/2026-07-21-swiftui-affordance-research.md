# SwiftUI per-platform affordance research (2026-07-21)

Commissioned for the input-paradigms expansion: SwiftUI is the design
authority for HOW each element adapts per platform/input class. Produced by a
bounded research subagent (WebSearch/WebFetch); persisted verbatim below.
Consumed by the reviewed affordance matrix
(`artifacts/input-paradigms/affordance-matrix.md`) and ADR-0015.

**Sourcing caveat:** Apple's live reference pages (`developer.apple.com/documentation/...`) and current HIG pages are JS-rendered and return empty/403 to automated fetch. Declarations below are corroborated from Apple WWDC sessions, Apple's archived tvOS/parallax guides, and named reputable dev blogs (hackingwithswift, swiftwithmajid, sarunw, avanderlee, useyourloaf, fatbobman). Where Apple publishes no numeric value (notably the tvOS focus scale factor), that is stated explicitly rather than invented.

The unifying model: **one declarative description; SwiftUI resolves the concrete affordance from (a) the compiled platform, (b) environment values, and (c) the surrounding container**, via `.automatic` cases on style-resolution protocols. Everything below is an instance of that.

---

## 1. List — edit mode, reorder, swipe actions, selection

- **`EditButton()` / `editMode`** is an iOS/iPadOS-centric mechanism. `EditButton` toggles the `@Environment(\.editMode)` value (`EditMode`: `.inactive`/`.active`/`.transient`) for its scope; you can also set it programmatically. In edit mode, iOS rows surface selection circles (→ checkmark when selected), delete-minus badges, and `.onMove` **reorder grip handles** (three-line "hamburger" on the trailing edge) ([hackingwithswift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-allow-row-selection-in-a-list); [swiftprogramming](https://swiftprogramming.com/editbutton-swiftui/)).
- **macOS has no EditButton idiom.** Mac users do not enter an "edit mode" to reorder or delete. `.onMove` is expressed as **direct drag-and-drop** of rows (no grip handle needed — the whole row is draggable because pointer scroll is separate, see §8), and deletion is Backspace on the selected row ([swiftprogramming editable list](https://swiftprogramming.com/editable-list-swiftui/)).
- **Swipe actions (touch) vs context menu (pointer).** `.swipeActions(edge:allowsFullSwipe:content:)` is the **touch** idiom, `List`-only, available **iOS 15+/iPadOS 15+/macOS 12+/watchOS 8+/visionOS 1+ — but NOT tvOS**. `edge` defaults `.trailing`; `allowsFullSwipe` (default `true`) auto-runs the first action on a full swipe. `.onDelete` is the swipe-to-delete convenience ([useyourloaf swipe actions](https://useyourloaf.com/blog/swiftui-swipe-actions/); [peterfriese](https://peterfriese.dev/blog/2021/swiftui-listview-part4/)). The **input-agnostic counterpart is `.contextMenu`** — same declaration, but SwiftUI picks the trigger per input class: long-press on touch, right-click/control-click on pointer/macOS (see §3). Cross-platform pattern: mirror destructive/primary commands in **both** `swipeActions` and `contextMenu` so pointer/macOS/tvOS still reach them ([useyourloaf](https://useyourloaf.com/blog/swiftui-swipe-actions/)).
- **Selection idioms.** `List(selection:)` takes an **optional ID** for single-select, a **`Set<ID>`** for multi-select. iOS 15-: selection requires edit mode (checkboxes). **iOS 16+: single-select works on plain tap without edit mode; multi-select without edit mode works on keyboard+pointer devices** (iPad/Mac). macOS uses desktop idioms with no edit mode: **click = select one, ⌘-click = toggle one into the set, ⇧-click = extend contiguous range** ([sarunw single](https://sarunw.com/posts/swiftui-list-selection/); [sarunw multiple](https://sarunw.com/posts/swiftui-list-multiple-selection/); [serialcoder macOS](https://serialcoder.dev/text-tutorials/swiftui/enabling-selection-double-click-and-context-menus-in-swiftui-list-on-macos/)).
- **tvOS list behavior.** Rows become **focusable**; move focus with the remote, click to activate/select. **No edit mode, no swipe actions, no reorder grips** — selection is expressed through focus + activation, not checkboxes or swipes. (Inferred from `swipeActions`/`editMode` platform-availability and focus-driven interaction; Apple does not state it as one sentence.) ([blakecrosley](https://blakecrosley.com/blog/tvos-focus-engine-swiftui))

**LuauUI implication:** Model a list command as an abstract *row action set* + a *selection model*, and let the platform layer choose the surface — swipe on touch, context menu / right-click on pointer, focus-activate on gamepad/TV — with reorder as edit-mode grips on touch but naked drag on pointer. Never make swipe the only path to a command.

---

## 2. Picker — automatic style resolution

- Concrete styles: **`.menu`** (pop-up on tap), **`.wheel`** (spinning drum, fixed height), **`.segmented`** (horizontal tabs, few options), **`.inline`** (options placed inline in a Form/List), **`.navigationLink`** (pushes a selection sub-screen; needs a `NavigationStack`), and **`.automatic`** ([sarunw form pickers](https://sarunw.com/posts/swiftui-form-picker-styles/); [avanderlee](https://www.avanderlee.com/swiftui/picker-styles-color/)).
- **`.automatic` resolves by platform AND OS version AND container.** iOS 16+: a standalone picker (e.g., in a VStack) defaults to **`.menu`**; inside a **Form/List** it commonly resolves to a **navigation/inline** row that opens the option list. Older iOS defaulted to wheel. Because `Form` applies platform-specific styling, the *same* picker renders differently in vs. out of a Form and across platforms ([sarunw](https://sarunw.com/posts/swiftui-form-picker-styles/); [swiftyplace](https://www.swiftyplace.com/blog/swiftui-picker-made-easy-tutorial-with-example)).
- **tvOS:** the picker resolves to a focus-navigable presentation (segmented/menu-like row the focus engine steps through); the wheel idiom is not a TV interaction. Apple docs are light on the exact tvOS resolution table — treat as "focus-navigable option list," ambiguous at the pixel level.

**LuauUI implication:** Expose a single `Picker(selection, options)` and resolve presentation from context — inline/menu for few options on pointer/touch, a push-to-subscreen or focus-steppable row on gamepad/TV — rather than committing the caller to a widget shape.

---

## 3. Menu / context menus — trigger adaptation

- **`Menu`** = a button that, when **tapped/clicked**, drops a list of actions (primary affordance). **`.contextMenu`** = attached to a view and triggered by the **platform-native secondary gesture**: **long-press on touch (iOS/iPadOS)**, **right-click / control-click on pointer/macOS** — one declaration, SwiftUI picks the gesture ([hackingwithswift context menu](https://www.hackingwithswift.com/quick-start/swiftui/how-to-show-a-context-menu); [swiftyplace menu](https://www.swiftyplace.com/blog/swiftui-menu-and-context-menu-buttons-with-dropdown-lists)).
- **tvOS** is the ragged edge: context menus are surfaced via the **Play/Pause button** (and, in code, detecting `.onLongPressGesture` / menu-button presses on a focused element), not a universal long-press. Documented pitfall: on tvOS a `.contextMenu` on a `Button` **works with the default button style but is ignored when a custom `ButtonStyle` is applied** ([Apple forum 705804](https://developer.apple.com/forums/thread/705804)). Behavior is fiddly and partly undocumented — flag as ambiguous.

**LuauUI implication:** Treat "secondary actions on an element" as one intent; bind it to long-press (touch), right-click (pointer), and a dedicated button (gamepad/TV), and never assume long-press exists on TV. Keep primary vs. secondary actions distinct so gamepad can map them to different buttons.

---

## 4. Slider vs Stepper — and the tvOS Adjust idiom

- **Preference by platform:** Slider (continuous drag along a track) suits **pointer (macOS) and touch (iOS/iPadOS)**. Stepper (discrete ±) suits **anything focus-driven** and small/coarse values.
- **tvOS has no usable Slider.** UIKit's `UISlider` is unavailable on tvOS, and the track-drag model doesn't fit focus navigation; the platform substitutes the **focus + swipe "Adjust" idiom** — focus the control, then swipe left/right on the remote touch surface to change the value ([createwithswift sliders/steppers](https://www.createwithswift.com/mastering-forms-in-swiftui-sliders-and-steppers/); [Stepper as tvOS alternative](https://medium.com/devtechie/stepper-in-swiftui-67ed8d7a8466)). Precise SwiftUI-level availability of `Slider` on current tvOS is ambiguous in docs; the durable fact is the **Adjust-by-swipe model replaces track-drag** on TV.
- **Keyboard adjustment (macOS/pointer):** a focused Slider/Stepper responds to **arrow keys** for increment/decrement ([hackingwithswift keyboard shortcuts](https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-keyboard-shortcuts-using-keyboardshortcut)).
- **watchOS Digital Crown is the Adjust analog:** bind a value with **`.focusable()` + `.digitalCrownRotation()`** (order matters — `focusable()` must precede/enable crown delivery). This is functionally the same "focus an element, then rotate/swipe to adjust" pattern as tvOS ([hackingwithswift crown](https://www.hackingwithswift.com/quick-start/swiftui/how-to-read-the-digital-crown-on-watchos-using-digitalcrownrotation); [kodeco watchOS crown](https://www.kodeco.com/books/watchos-with-swiftui-by-tutorials/v1.0/chapters/3-digital-crown)).

**LuauUI implication:** Define a `ValueAdjuster(value, range, step)` control that renders as a drag-track on pointer/touch but as a **focus-then-directional-adjust** (swipe/arrows/analog stick) with visible ± affordance on gamepad/TV — the "Adjust idiom." Track-drag must never be the only way to change a value.

---

## 5. TextField — focus, keyboards, submit

- **First-responder model via `@FocusState`** (iOS 15+): a `Bool` form (`.focused($isFocused)`) or an enum/optional form (`.focused($field, equals: .username)`) that both *reads* focus and *drives* it (assigning moves the responder). "In iOS the focused view takes responsibility for the keyboard; in macOS and tvOS the focused view is visually distinct." ([fatbobman](https://fatbobman.com/en/posts/textfield-event-focus-keyboard/))
- **On-screen keyboard (touch):** appears on focus; dismiss by setting focus to `nil`/`false` or `.scrollDismissesKeyboard(.immediately)` (iOS 16+). **macOS:** hardware keyboard, Tab moves between fields, no on-screen keyboard.
- **tvOS text entry** is deliberately heavyweight: the focused field shows a fixed-height rounded box; clicking presents a **separate full-screen on-screen keyboard** (linear/grid keyboard navigated by focus). Apple explicitly advises **using text entry sparingly** — prefer selection lists/buttons over multiple text fields because keyboard entry is tedious ([Microsoft/Xamarin tvOS text fields](https://learn.microsoft.com/en-us/xamarin/ios/tvos/user-interface/text-fields-and-search); [abdulkarim tvOS SwiftUI](https://medium.com/@abdulkarimkhaan/building-swiftui-app-for-tvos-2024-episode-1-introduction-and-user-interaction-guide-26f961eedad4)).
- **`submitLabel`** (`.done/.next/.send/.search/.go`…) is a **hint** that relabels the Return key on touch keyboards; **`keyboardType`** (`.emailAddress/.numberPad/.decimalPad/.phonePad`…) is a **hint** that restricts the on-screen keyboard layout — both are meaningless-but-harmless on hardware keyboards. `onSubmit` fires on Return; propagates outer→inner, `.submitScope()` blocks it ([fatbobman](https://fatbobman.com/en/posts/textfield-event-focus-keyboard/)).

**LuauUI implication:** Text input is a first-responder abstraction, not a widget: expose `keyboardType`/`submitLabel` as **hints** the platform may honor or ignore, route submit through one `onSubmit`, and on gamepad/TV present a **full-screen virtual keyboard** while designing flows to minimize text entry entirely.

---

## 6. Toggle — switch vs checkbox

- Styles: **`.switch`** (leading label + trailing switch), **`.checkbox`** (checkbox + label — **macOS only**), **`.button`**, **`.automatic`**. **`.automatic` resolves to checkbox on macOS and switch on iOS/iPadOS/tvOS/watchOS/visionOS.** Checkbox is not available off macOS ([avanderlee toggle guide](https://www.avanderlee.com/swiftui/toggle-switch-a-complete-guide/); [Apple CheckboxToggleStyle](https://developer.apple.com/documentation/swiftui/checkboxtogglestyle)).
- tvOS renders the switch style, activated by focus + click.

**LuauUI implication:** A boolean control is semantic, not visual — resolve to a switch on touch/TV and a checkbox in dense pointer/desktop forms, driven by one `Toggle(isOn:)` binding.

---

## 7. Button / tap targets, hover, focus lift, keyboard defaults

- **Minimum hit target: 44×44 pt** on touch (Apple HIG, since the original iPhone). The *visible* control may be smaller than the 44pt tappable region ([multiple, e.g. Deque/Brilworks summaries](https://dequeuniversity.com/rules/attest-ios/1.0/touch-target-size)). tvOS focus targets and 10-foot targets are effectively larger (see §11).
- **`ButtonStyle .automatic`** resolves to **`.borderless` on iOS**, **`.bordered` on macOS/tvOS/watchOS**; built-ins include `.plain/.borderless/.bordered/.borderedProminent` ([sarunw button styles](https://sarunw.com/posts/swiftui-button-style-examples/); [useyourloaf button styles](https://useyourloaf.com/blog/swiftui-button-styles-and-shapes/)).
- **Pointer hover (iPadOS/macOS):** `.hoverEffect(_:)` with `HoverEffect` cases **`.automatic`** (default; content-adaptive, not a mere switch of the others), **`.highlight`** (pointer morphs into a platter behind the view + light source), **`.lift`** (view scales up + soft shadow, pointer slides under and hides). Also `.defaultHoverEffect`, `.hoverEffectDisabled`, and `.onHover { }` to observe state ([swiftwithmajid hover](https://swiftwithmajid.com/2020/03/25/hover-effect-in-swiftui/)).
- **tvOS focus lift/parallax:** focused items **scale up + drop shadow + parallax tilt** tracking small circular remote-surface motions; images use layered parallax (§9). Apple's guidance is qualitative — **no official numeric scale factor** (community convention ~1.05–1.1×) ([blakecrosley](https://blakecrosley.com/blog/tvos-focus-engine-swiftui); [devsign focus effects](https://devsign.co/notes/custom-focus-effects-in-tvos)).
- **Keyboard default/cancel:** `.keyboardShortcut(.defaultAction)` = **Return**, no modifiers (the default button); `.keyboardShortcut(.cancelAction)` = **Escape** (dismiss/cancel). macOS caveat: `.defaultAction` on a Button may not fire while a TextField holds focus — use `onSubmit` there ([sarunw keyboard shortcuts](https://sarunw.com/posts/swiftui-keyboard-shortcuts/); [Apple cancelAction](https://developer.apple.com/documentation/swiftui/keyboardshortcut/cancelaction)).

**LuauUI implication:** Enforce a 44pt minimum touch target as a floor; give every actionable element **three feedback layers** — pointer hover (highlight/lift), focus lift/scale+glow for gamepad/TV, and pressed — and bind logical **Confirm→Return/A** and **Cancel→Escape/B** so default and cancel actions exist on every input class.

---

## 8. ScrollView vs drag priority — gesture arbitration

- **Touch (iOS/iPadOS): scroll owns the naked pan.** A `ScrollView`/`List` pan gesture wins a bare finger drag. A content `DragGesture` with `minimumDistance: 0` will hijack scrolling; the fix is to raise `minimumDistance` (~20pt) so a small pan scrolls and only a deliberate drag reorders — i.e., **drag needs a threshold, a handle, or a long-press "lift."** SwiftUI notably **cannot programmatically fail a gesture** the way UIKit can (`state = .failed`), so arbitration is threshold-based, not cancel-based ([darjeelingsteve](https://darjeelingsteve.com/articles/Preventing-Scroll-Hijacking-by-DragGestureRecognizer-Inside-ScrollView.html); [Apple forum 811434](https://developer.apple.com/forums/thread/811434)). Reorder (`.onMove`) therefore requires edit-mode grip handles or a long-press lift on touch.
- **macOS: no scroll/drag conflict.** Scrolling is a **separate channel** — mouse wheel or **two-finger** trackpad scroll — distinct by finger count/device from a **one-finger click-drag** (direct manipulation). Because the pan input for scrolling and the press-drag input for dragging are physically different, **a row can be directly draggable with no handle/long-press** ([Apple Multi-Touch gestures](https://support.apple.com/en-us/102482)).

**LuauUI implication:** On touch, scroll always wins a naked pan — require a drag **handle or long-press-lift** before any pan-to-reorder/pan-to-drag, and pick a movement threshold. On pointer, scroll is a separate channel so direct drag needs no handle. Bake this asymmetry into the drag-source abstraction.

---

## 9. Focus system (tvOS + cross-platform)

- **Vocabulary:** `.focusable([Bool][, interactions:])`, `@FocusState` + `.focused(_:equals:)`, **`.focusSection()`** (tvOS/macOS — groups focusables into one two-tier navigation block; fixes diagonal/column skips), **`.focusScope(_:)` + `.prefersDefaultFocus(_:in:)`** (declare initial focus for a screen/sheet/tab, bounded by a `@Namespace`), `@Environment(\.resetFocus)` (`resetFocus(in:)`), and `.focusEffectDisabled()` ([blakecrosley](https://blakecrosley.com/blog/tvos-focus-engine-swiftui); [swiftwithmajid focus mgmt](https://swiftwithmajid.com/2020/12/02/focus-management-in-swiftui/); [WWDC21 Direct and reflect focus](https://developer.apple.com/videos/play/wwdc2021/10023/)).
- **Automatic vs manual focusability:** built-in interactive controls (Button, List rows, TextField) are **focusable for free**; arbitrary `Text`/`Image`/containers must be marked `.focusable()`.
- **Directional navigation is derived from layout geometry:** the engine reads the swipe/D-pad direction and picks the **geometrically nearest focusable along that axis**, biased toward center-alignment with the current item — so *visual* layout, not just hierarchy, determines navigation. `.focusSection()` corrects cases raw geometry would skip ([brightec focus engine](https://www.brightec.co.uk/blog/tvos-focus-engine); [blakecrosley](https://blakecrosley.com/blog/tvos-focus-engine-swiftui)).
- **Focus visibility is mandatory** on tvOS: scale-up + shadow/lift + **parallax** (driven by **layered images**, 2–5 layers, 2-layer minimum for icons; UIKit auto-parallaxes layered images on focus, `adjustsImageWhenAncestorFocused = true`) ([Apple archived layered images](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/CreatingParallaxArtwork.html)). No Apple-published pixel-shift/scale numerics.
- **Focus memory:** the UIKit focus engine restores the last-focused item when you return to a container, but this is **not clearly contracted in SwiftUI reference docs** and forum reports call it inconsistent — for determinism, drive it with `@FocusState`/`prefersDefaultFocus`/`resetFocus` ([Apple forum 663936](https://developer.apple.com/forums/thread/663936)). Flag as ambiguous.

**LuauUI implication:** Ship a first-class focus engine: derive directional moves from on-screen geometry (not tree order), provide focus-section grouping for grids/sidebars, an explicit default-focus + focus-memory API (don't rely on implicit restore), and require every focusable to render a visible scale/glow/lift state.

---

## 10. Cross-cutting — how SwiftUI chooses automatically & hybrid input

- **Environment values driving adaptation:** `\.editMode` (list edit affordances), **`\.controlSize`** (`ControlSize`: `.mini/.small/.regular/.large/.extraLarge`; `.mini`≡`.small` on iOS but distinct on macOS; `.extraLarge`→`.large` off visionOS), **`\.horizontalSizeClass`/`\.verticalSizeClass`** (`UserInterfaceSizeClass?` = `.compact`/`.regular`, updates on rotation/Split View). Style-resolution protocols — `ButtonStyle/ToggleStyle/PickerStyle/LabelStyle/ListStyle/TextFieldStyle` — each carry a **`.automatic`** case meaning "SwiftUI chooses per platform + context" ([sarunw button size / ControlSize](https://sarunw.com/posts/swiftui-button-size/); [fivestars size classes](https://www.fivestars.blog/articles/adaptive-swiftui-views/); [swiftui-lab custom styling](https://swiftui-lab.com/custom-styling/)). Apple states the *contract*; the concrete per-platform mapping tables are dev-blog reverse-engineering and shift by OS version.
- **Hybrid iPad (trackpad/mouse + touch simultaneously):** since iPadOS 13.4 **both input modes are live at once** — no mode switch. The pointer is **adaptive** (morphs/snaps to the control under it), hover effects (`.hoverEffect`) activate when a pointer is present, and touch continues to work concurrently. Pointer accessories/snapping are richer in UIKit (`UIPointerInteraction`/`UIPointerStyle`) than SwiftUI, which surfaces the common cases via `hoverEffect`/`contentShape` ([WWDC20 Build for the iPadOS pointer 10093](https://developer.apple.com/videos/play/wwdc2020/10093/); [WWDC20 Handle trackpad and mouse input 10094](https://developer.apple.com/videos/play/wwdc2020/10094/)).
- **Mid-session input arrival:** the documented low-level signal is the **GameController framework connect/disconnect notifications — `GCKeyboardDidConnect`/`DidDisconnect`, `GCMouseDidConnect`/`DidDisconnect`** — which fire live so input can be re-routed immediately ([Apple GCKeyboardDidConnect](https://developer.apple.com/documentation/foundation/nsnotification/name/3626175-gckeyboarddidconnect); [WWDC20 keyboard/mouse gaming 10617](https://developer.apple.com/videos/play/wwdc2020/10617/)). At the UI layer there is **no single SwiftUI "pointer connected" callback** — the framework adapts by pointer-driven effects becoming active and the on-screen keyboard yielding to hardware. Flag as ambiguous: input-arrival is observed indirectly (effects activating), not via a first-class SwiftUI event.

**LuauUI implication:** Resolve affordances from explicit context values (size class, control size, active input set), keep **multiple input modes simultaneously live** (pointer effects + touch + gamepad focus coexisting, not mutually exclusive), and treat mid-session device arrival as a **first-class live event** the UI reacts to immediately — an area where SwiftUI is notably weak and LuauUI can do better with an explicit `PreferredInput`/input-arrival contract.

---

## 11. 10-foot UI principles (tvOS HIG)

- **Overscan-safe margins:** keep all content inside the TV-safe area — commonly cited as **60pt top/bottom** and **90pt left/right** insets (older TVs overscan/clip edges; text within the tighter safe-**title** margin, other important elements within safe-**action** margin) ([tvOS design summaries](https://medium.com/bpxl-craft/getting-started-with-apple-tv-human-interface-guidelines-4d991737ddec); [Wikipedia 10-foot UI](https://en.wikipedia.org/wiki/10-foot_user_interface)).
- **Type scale at distance:** body text **≥ ~29pt**; avoid thin fonts and hairline borders (they vanish under distance, motion blur, compression); use **medium/semibold minimum** ([smashing designing for TV](https://www.smashingmagazine.com/2025/09/designing-tv-principles-patterns-practical-guidance/)).
- **Focus visibility:** every interactive element needs an unmistakable focus state (scale ~1.05–1.1× community convention, elevation/shadow, brightness, parallax) — the focused item must be obvious across the room.
- **Layout density:** spacious, generous padding, few large targets — "a single row of 5–7 cards beats a dense grid of 20+ thumbnails." Design for **lean-back** interaction and minimal text entry ([uxstudio TV UX](https://www.uxstudioteam.com/ux-blog/best-practices-for-designing-tv-interfaces); [pascalpotvin 10ft UI](https://pascalpotvin.medium.com/designing-a-10ft-ui-ae2ca0da08b7)).

**LuauUI implication:** Ship a console/TV "10-foot" profile that auto-applies overscan-safe margins (~60/90pt-equivalent), a larger type ramp with min-weight enforcement, low layout density (few large focusable cards), and mandatory high-contrast focus visuals — activated by a display-size/overscan signal (`ViewportDisplaySize==Large` console profile), independent of whether the input is a gamepad.

---

### Cross-cutting takeaways for the affordance matrix
1. **Separate intent from surface.** Every control is a semantic binding (`selection`, `isOn`, `value`, `action set`); the platform layer chooses switch/checkbox, slider/stepper/adjust, swipe/context-menu/focus-activate.
2. **Three input classes need three feedback layers** — hover (pointer), focus lift/scale+glow (gamepad/TV), pressed (all) — plus a 44pt touch floor.
3. **Gesture arbitration is input-dependent:** scroll owns naked pan on touch (drag needs handle/lift/threshold); pointer scroll is a separate channel so direct drag is free.
4. **Focus is a first-class engine**, geometry-derived, with explicit default/memory/section APIs and mandatory visible state.
5. **Multiple inputs coexist and can arrive mid-session** — the weakest, most-ambiguous area in Apple's own stack, and the clearest place for LuauUI's three-axes (UI/input/paradigm) contract to exceed SwiftUI.

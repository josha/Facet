# React-Lua ↔ Facet: two declarative frameworks for the same engine

Facet is a declarative UI framework for Roblox. So is React-Lua — Roblox's own
port of React, maintained by Roblox, used by Roblox for its Studio plugins and
its Universal App ([RL-23]). It is the only other declarative UI framework on
this platform with a first-party publisher behind it, which makes it the most
useful thing to hold Facet up against for a reader deciding what to build with.

The companion document, [`the comparison document`](the comparison document), measures Facet
against another declarative framework — the most complete one in wide production
use. That is a *ceiling* comparison: what does a mature framework offer that we
do not. This one is different. React-Lua and Facet are peers on the same engine,
solving the same problem, and they **disagree** — about what a component is, who
owns layout, what a property write means, and whether a frame may be interrupted.
The interesting content is the disagreements, not a score.

Neither framework is the yardstick here. Both columns carry verdicts.

---

## 1. What this document is, and how to read it

### The verdicts

| Verdict | Means |
|---|---|
| **Ships** | A first-class equivalent exists, is public, and works. |
| **Ships, with caveats** | It exists and works, with named behaviour gaps a consumer will hit. |
| **Composable** | Not a construct, but buildable today from the public surface with no framework change. The recipe is named. |
| **Absent** | No construct and no honest recipe. |
| **N/A by design** | The other framework's architecture makes the question meaningless on this side. Said in those words, never used to hide a gap. |

### Every claim about React-Lua carries a citation

Claims about Facet are guarded by checkers (`check_docs`, `check_prop_parity`,
`check_registration`, `check_surface_ledger`, `check_boundary`) and, more
importantly, were read **from `src/`** for this document rather than from
Facet's own documentation. Nothing guards the React-Lua side, so every row that
asserts something about React-Lua's behaviour carries a bracketed id — `[RL-05]`
— resolved in **§7**, with the URL, the sentence quoted verbatim, and the date
the page or file was read.

**The dates are load-bearing, and this project has been burned without them.**
Three facts about that framework were once asserted from memory here and all
three were wrong. So: nothing below is recalled. If you are reading this months
later, open the URL. Source files move faster than docs — several rows below
exist *because* React-Lua's documentation and its source disagree today.

**A citation proves a sentence, not a behaviour.** It cannot tell you the
sentence was read correctly, and where React-Lua's docs are silent this document
says so rather than inferring.

### One naming trap before anything else

`github.com/Roblox/react-lua` **301-redirects to `github.com/Roblox/react-luau`**
([RL-24]). They are one repository under two names. The project brands itself
"React Luau", its documentation calls the umbrella "Roact 17+", the Wally scope
is `roblox/react`, and the Creator Store asset is named "ReactLua". This document
uses **React-Lua** throughout for the thing the director asked about, and quotes
whichever name a source uses.

There is also a **community fork**, `jsdotlua/react-lua`, whose documentation
sites (`jsdotlua.github.io/react-lua`, `react.luau.page`) rank highly in search.
Nothing in this document is sourced from the fork.

### What this document does not cover

- **It is not a completeness audit.** `the comparison document` §1 measures its own
  blind spots against a 365-group denominator. This document has no such
  denominator: React-Lua's API *is* React 17.0.1's API, and §4 reads it from the
  literal export table, but the capability areas in §4 were chosen for
  what a Roblox game author would compare, not by a mechanical sweep. **Silence
  outside §4 is not evidence.**
- **Fusion is a separate document.** The director's question spans React and
  Fusion; [`fusion-comparison.md`](fusion-comparison.md) covers Fusion, and §5
  confines itself to candidates that come from React-Lua. Three candidates appear
  on both lists from different directions, and §5's preamble reconciles them
  rather than leaving the reader to notice.
- **Distribution is out of scope but not out of mind.** React-Lua ships on Wally
  and the Creator Store ([RL-25], [RL-26]); Facet 0.9.0 has no public
  distribution at all. That is the single largest practical difference between
  the two projects today and it is
  [`distribution-readiness.md`](../plans/distribution-readiness.md)'s to close,
  not §5's.

### Vocabulary

React-Lua's terms, and Facet's, side by side where an analogue exists:

| React-Lua | Facet | What it is |
|---|---|---|
| **Element** (`React.createElement`) | **Blueprint** (`UI.VStack{…}`) | A plain table describing what should be on screen. React's carries a `type` that is either a component function or a Roblox `ClassName`; Facet's carries one of 26 framework class names. |
| **Component** | *(no equivalent)* | A function that takes props and returns elements, and may hold state via hooks. Facet has no unit of this kind — see §2.3. |
| **Host element** | *(no equivalent)* | An element whose `type` is a Roblox class name, rendered by `Instance.new(type)`. Facet's classes are not engine class names. |
| **Reconciler / fiber tree** | **Mounted node graph** (`src/mount.luau`) | React's is rebuilt and diffed; Facet's is built once and mutated in place. |
| **Binding** | **Signal / Memo** | A value that updates a property without re-rendering. React-Lua added Bindings for exactly the case Facet's whole core is ([RL-02], [RL-12]). |
| **Root** (`createRoot`) | **Surface** (`presenter.present`) | One independently mounted tree. A React root "take[s] complete control of the provided container, deleting all existing children" ([RL-21]); a Facet surface creates its own `ScreenGui`. |
| **`ReactRoblox` host config** | **Render target** (`src/render/target_contract.luau`) | The layer that turns the framework's output into Roblox Instances. Both are swappable; only Facet's is a written contract with named degrades. |
| *(no equivalent)* | **Solver** | Facet's headless layout engine: measures the blueprint, arranges it into rectangles, with no engine objects involved. React-Lua has nothing of this kind — see §2.2. |

---

## 2. The philosophical difference, in plain language

### 2.0 They start from the same complaint

Before the disagreements, the agreement, because it is real and it is the reason
both exist.

Roblox's native UI is a tree of Instances you build by hand and mutate by hand.
A health bar is a `Frame` you found by name, whose `Size` you wrote in a
callback. When the player's health changes in three places, three pieces of code
write that `Size`, and when one of them is wrong nothing tells you. Roblox's own
UI documentation describes the native story as "built-in UI objects" plus
"layout structures like list/flex and grid" plus a stylesheet system ([RL-30]) —
and every one of those is a thing you *set*, imperatively, from somewhere.

Both frameworks reject that. Both say: **describe what the screen should look
like as a function of your data, and let the framework work out which Instances
to touch.** Everything below is downstream of that shared premise.

Notably, Roblox's own UI documentation does not mention React, React-Lua, Roact,
or any third-party framework at all ([RL-30]), and the Creator Store asset is
marked `isEndorsed: false` ([RL-26]). React-Lua is published by Roblox and used
by Roblox; it is not presented to creators as the recommended way to build UI.
Neither framework has the platform's blessing. Both are opinions.

### 2.1 "What changed?" — a re-render versus a subscription

This is the deepest split, and everything else follows from it.

**React's answer is: run your code again and compare.** You changed some state.
React re-runs the component function that owns it, gets a new tree of elements,
compares that tree against the previous one, and works out the minimum set of
Instance property writes that turns the old screen into the new one. That
comparison is what "reconciliation" means.

That paragraph is the widely-published description of React's model, and it is
worth being precise about its status here: **React-Lua's own documentation states
the effect, not the mechanism** — "React will efficiently update and render just
the right components when your data changes" ([RL-01]) — and says explicitly that
it does not re-document React, serving instead "as a comprehensive guide to the
_differences_" ([RL-03]). What *is* visible in the API are the two dials that
exist to tune reconciliation: `React.memo`, which React-Lua's page documents only
as something to "use … only as a performance optimization" ([RL-40]), and keys,
which exist so the reconciler knows the third row is still the *same* row it was,
just moved ([RL-09]).

The trade is a good one and it is why React won: **you never have to say what
changed.** You write the whole screen as a function of the whole state, every
time, and the framework figures out the difference. The cost is that the
framework has to do work proportional to the size of the tree you re-described,
not to the size of the change.

**Facet's answer is: nothing runs again; the one thing that reads that value
gets told.** A blueprint node is materialized exactly once — `src/mount.luau`
calls this *factory-once*, and the mounted node carries `factoryRuns = 1` so a
test can prove no re-run happened. A reactive prop is not compared; it is
*subscribed*. When you write `health:set(0.4)`, the observer that a single `Text`
node registered for that signal fires, writes the new value into that node, and
pushes one entry onto a dirty queue tagged with what kind of dirt it is —
`paint`, `measure`, `arrange`, `structure`, `navigation` or `semantics`. Nothing
above it, beside it, or below it is visited.

The trade is the mirror image. **You never pay for what did not change** — the
framework's own regression suite pins that a single bound-value change costs the
same at 100, 800 and 3200 rows. The cost is that a value only propagates if it
was a `Signal` or a `Memo` in the first place. Hand a control a plain number and
it is frozen at that number forever, and Facet's answer is to *refuse it at
construction* rather than let you find out later:

> `Facet UI.Text.text does not accept a Signal/Memo (it is read once at mount).
> Pass a plain value, or rebuild the subtree through UI.When/UI.ForEach.`
> — the inverse message, from `src/blueprint.luau`, for a reactive value passed to
> a static prop.

**Where they meet.** React-Lua *also* has a per-value channel, and it invented
one for the same reason Facet's core exists. Bindings are, in the README's own
words, "a form of signals-based state that doesn't re-render, for highly-efficient
animations driven by React" ([RL-02]), and the deviations page calls a binding "a
unidirectional data binding that can be updated outside of the render cycle"
([RL-12]). A React-Lua author animating a bar writes a Binding, not `useState`,
precisely to bypass reconciliation.

So the honest framing is not "React re-renders and Facet does not." It is:
**React-Lua has two update channels and you choose per value; Facet has one, and
it is the fine-grained one.** React-Lua's default is the coarse channel and its
fast path is opt-in. Facet has no coarse channel at all, which is a strength
until you want one — see the `When` gap in §5.

**What Facet keeps of reconciliation, and where.** Structure still has to
change: rows appear, panels open. Facet's answer is that **only three classes
may mount or unmount anything** — `UI.When`, `UI.ForEach`, `UI.ErrorBoundary`
(`src/mount.luau`, `UI-RUNTIME-002`). Inside a `ForEach` the algorithm is exactly
React's keyed children reconciliation: build the wanted key set, remove what is
gone, add what is new, reorder in place, and **a duplicate key is a hard error**
rather than a warning. What is missing is the walk *above* it — no parent is
re-run to discover that the `ForEach` changed.

React-Lua supports two spellings of the same idea, both documented as valid and
equivalent: a table whose keys are the stable keys (legacy Roact's shape, "since
order has no inherent meaning in Roblox's DOM"), and the reserved `key` prop
([RL-09]). Using both at once is a Dev-Mode warning, not an error.

### 2.2 "Who owns the pixels?" — the engine's layout versus a solver

**React-Lua does not have a layout system.** This is not a criticism; it is the
architecture, and it is exactly ReactDOM's. ReactDOM does not lay out either — it
writes DOM properties and CSS does the rest. React-Lua writes Roblox Instance
properties and `UIListLayout` does the rest.

The evidence is structural rather than quoted, and it is threefold. The `React`
package's export table contains no layout API of any kind ([RL-08]). The
monorepo contains no layout package ([RL-34]). And the renderer's element
vocabulary is `Instance.new(type_)` on the element's type string ([RL-15]) — so
the only things you can write are Roblox classes, and the only way to get a
vertical list is to declare a `UIListLayout` as a child element. The README's own
example is the shape: `AnchorPoint`, `Position`, `AutomaticSize` set as plain
props on a `"TextLabel"` ([RL-01]).

`useLayoutEffect` — React's measurement hook — is documented as having no clear
purpose here at all:

> "In React JS, `useLayoutEffect` is most often used to measure and position
> elements before the browser repaints them. **It's not yet clear how this use
> case translates to roblox usage**, and this hook should be used with caution
> until performance is investigated in detail and best practices emerge."
> ([RL-28])

**Facet measures and arranges itself, and materializes no engine layout object
at all.** There is not one `Instance.new("UIListLayout")`, `UIGridLayout`, or
`UITableLayout` anywhere in `src/`. The solver is a headless measure-then-arrange
pass over the blueprint that produces absolute rectangles, and the renderer
writes exactly two engine properties for geometry — `Position` and `Size`, both
as `UDim2.fromOffset`, at one call site (`src/client/screen_presentation.luau`).
Pure pixels; no scale component anywhere.

**The consequence people notice first is that Facet's Instance tree is FLAT BY
DEFAULT.** A `VStack` inside a `VStack` inside a `ZStack` still produces no
nested Frames unless one of them is registered as a *host* — a real engine
parent for its own subtree. The render-target seam still *cannot express
hierarchy as a renderer capability*: `create(rootHandle, path, class, …)`
receives the root and a path string and no parent handle
(`src/render/target_contract.luau`, six required methods, none of them a
`setParent`). Nesting is not a renderer decision at all — it is a registration
policy the adapter runs internally
([ADR-0032](../adr/ADR-0032-nested-instance-tree.md)):

```
-- src/client/screen_target.luau
-- clip-host parenting: descendants of a clip host live INSIDE it so
-- the engine crops them; everything else stays flat under the root
```

That comment names the oldest of the reasons a node registers; the registry
behind it (`instanceHosts`, renamed in this round from `clipHosts`) now answers
to a wider rule, and **four** things create a real engine parent today, every
one of them because the engine can carry something down that node's subtree
that the framework would otherwise compute per descendant:

- a `ScrollView` (a clip host *by construction*),
- any node declaring `clipChildren`,
- an opt-in `CanvasGroup` (`canvasGroup = true` or an authored `opacity`, which
  needs a real render buffer), and
- **since 2026-08-16**, a container whose own authored `scale` or `rotation`
  reaches children it actually has — a plain `Frame`, no buffer, registered
  only because the engine can compose those two terms for a subtree it can see
  ([ADR-0032](../adr/ADR-0032-nested-instance-tree.md) Decision 4). Measured
  through the real framework: a `UI.ZStack{ rotation = 30, scale = 1.5 }`
  around an 80×40 `UI.Box` re-parents the box inside it, and the box comes out
  **120×60 at `AbsoluteRotation = 30`** while its own `Rotation` stays `0.0`
  and it grows no `UIScale` of its own — the engine composed both terms, no
  framework code did.

Nothing else registers. A `VStack` with children and neither prop still
produces no Instance of its own if it paints nothing, so elision is untouched —
which is the whole point of the rule: register only where nesting pays, never
"every container with children".

**And a container that paints nothing produces no Instance at all.** Six classes
— `VStack`, `HStack`, `ZStack`, `Grid`, `Anchor`, `Spacer` — are *elidable*: if
the node carries no decoration and is not a canvas group, `create` returns a
handle with no Instance behind it, and materializes one lazily only if something
later needs to write to it. The measurement that motivated it, from the source:

> "MEASURED on the performance lab: of 137 GuiObjects on a five-row surface, **55
> (40%) are completely inert** — they do not paint, do not clip, are not
> interactive, carry no modifier children and hold no text or image. And in
> Facet's FLAT tree they are not even the engine parent of their children."

An elided container in React-Lua is not expressible. A `Frame` with a
`UIListLayout` child *is* the layout; it cannot be removed, because removing it
removes the arrangement.

**The trade, stated plainly.** Facet's way costs a whole layout engine to build
and maintain, and every layout capability the engine has must be re-implemented
before you can use it (flow-wrap, which is one `UIListLayout` boolean natively,
was its own solver mission). In exchange it gets: layout that runs headlessly in
tests with no Roblox present; layout that can be *diagnosed* (an overflowing
child is named, an inert placement prop is reported); incremental re-solve of
only the affected subtree; and a vocabulary the engine does not have at all —
priority tiers, ranked region degradation, `ViewThatFits`. React-Lua's way costs
nothing to build, works with everything Roblox ships the day Roblox ships it, and
gives you no answer at all to "why is this the wrong size" beyond reading
`AbsoluteSize` in the Explorer.

### 2.3 "What is a component?" — hooks versus scopes

**In React-Lua, any function is a component**, and hooks give it state that lives
as long as the component is mounted. `local value, setValue = React.useState(0)`
— note the Luau deviation, two return values rather than a destructured array
([RL-32]). The state is keyed by call order within that component instance, which
is why the rules of hooks exist.

**Facet has no component abstraction at all.** There is no unit smaller than a
blueprint node, and blueprint nodes hold no state — they hold `Readable`s the
caller created. A repository-wide search for `useState`, `withState`,
`createSignal` returns nothing.

What it has instead is **scopes**. A scope is an explicit ownership token:
`scope:own(resource)` registers something for disposal, `scope:child(label)`
nests one, and disposing a scope releases everything under it in reverse order,
idempotently, with a throwing cleanup quarantined rather than aborting the walk
(`src/core/scope_impl.luau`). Facet's shipped controls are the pattern: each
`build(Facet, core, spec)` opens its own scope, creates its own signals and
memos inside it, and returns a blueprint plus an imperative handle. That *is*
component-local state; it is written by hand instead of inferred from call order.

The scope is strict in a way a hook is not. `scope:own` **refuses** anything with
no `dispose()`, and the reason is recorded in the source:

> "`own` used to insert whatever it was handed, and the dispose walk below falls
> through anything it cannot release — so `scope:own(thing)` over a table with no
> `dispose` read as correct, reviewed as correct, and did nothing at all. That is
> the accepted-but-ignored class, and it shipped inside the framework's own
> gallery scenario."

**Where this genuinely costs the author.** React's ergonomics here are better and
it is worth saying without hedging. A React-Lua author writes `useState` inside a
conditionally-rendered component and gets per-instance state that appears and
disappears with the component, for free, with no ceremony. In Facet:

- A **`ForEach` row** gets this. The row factory's signature is `(item,
  itemScope) -> Blueprint`, and the item scope is the row's lifetime — signals
  owned there die exactly when the row does.
- A **`When` branch does not.** `When.thenView` is `() -> Blueprint` with no
  second argument (`src/blueprint_schema.luau`), even though the mount layer
  creates a `branchScope` for exactly that lifetime one line away
  (`src/mount.luau`). So a panel that opens, owns a signal and an async handle,
  and closes has nowhere to put them. This is a real, small, closable asymmetry
  and it is §5's second-ranked item.

**Which model is easier to reason about is genuinely contested.** React's hooks
are less to write and have famous failure modes (stale closures, dependency
arrays, the rules of hooks). Facet's scopes are more to write and fail loudly.
React-Lua inherits the dependency-array problem and adds a Luau-specific twist to
it: because `#{"A","B",nil} == #{"A","B"}` is true in Luau, a dependency array
that shrinks is indistinguishable from one containing a trailing `nil`, so
React-Lua **always re-runs on a length change and suppresses the warning**
([RL-11]). That is a correctness-preserving choice that quietly removes a
diagnostic React JS gives you.

### 2.4 "What may you write?" — an open bag versus a closed set

This is the difference an author feels within five minutes.

**React-Lua's props are an open bag, and the renderer assigns them straight to
the Instance.** The entire mechanism, verbatim from the renderer ([RL-16]):

```lua
local function setRobloxInstanceProperty(hostInstance, key, newValue): ()
	if newValue == nil then
		local success, _ = pcall(hostInstance.ResetPropertyToDefault, hostInstance, key)
		if success then
			return
		end
		local hostClass = hostInstance.ClassName
		local _, defaultValue = getDefaultInstanceProperty(hostClass, key)
		newValue = defaultValue
	end

	-- Assign the new value to the object
	hostInstance[key] = newValue
end
```

There is no allowlist, no name translation, no validation. Anything that is not
`ref`, `children`, an `Event`/`Change` symbol, a Binding or `Tag` is assigned by
name. This is a genuine strength: **every Roblox property, on every Roblox class,
today, including ones shipped after the framework was written.** A typo produces
a Roblox property error at write time rather than at authoring time.

Two Roblox-specific keys ride the same mechanism and are worth knowing because
they are good: `[React.Event.Activated] = fn` connects an Instance event and
disconnects it on unmount, and `[React.Change.CanvasPosition] = fn` does the same
for `GetPropertyChangedSignal` ([RL-17]). `[React.Tag] = "a b"` applies
CollectionService tags ([RL-18]). One ergonomic wart: an event callback's first
argument is the Instance, not the event's own first argument ([RL-17]).

**Facet's props are a closed set per class, and an unknown one is a construction
error.** Twenty-six classes are registered in `src/blueprint_schema.luau`, each
with an explicit prop table. Every public constructor funnels through one `make()`
that walks the spec and errors on the first key it does not know, with a
Levenshtein suggestion and the full legal set enumerated. Beyond "unknown", there
is a second category — **refused, with the reason**:

> `Facet UI.Button.label: 'Continue to checkout' cannot be the drawn content of
> shape = "circle" — a disc holds ONE icon or up to 3 characters with no spaces,
> and a longer label has nowhere to go inside a 1:1 target. Fix: pass icon =
> "<semantic name>" (e.g. "more", "close", "menu"), shorten the label, or drop
> shape = "circle" for the default rectangular Button.`

> `Facet UI.Button: custom content must stay inside one activation surface, but
> it contains a focusable UI.Toggle ('Mute'). Put the control beside the Button,
> not inside it.`

> `Facet UI.HStack: 'align = "stretch"' has two readings on a wrapping stack —
> "each child fills its line" and "the lines fill the container" — so it is
> refused. Put 'lineAlign = "stretch"' on the children that should fill their
> line, and use 'align' (start|center|end) for where the block of lines sits.`

The resulting blueprint is then **deep-frozen** — `table.freeze` on the props, the
children array, and the node — after a bug where a shared template reused across
rows was mutated in place through `bp.props`.

The same discipline extends past blueprints: `src/spec_guard.luau` applies closed
key sets to control specs and options tables too, and its header names the gap it
closed — `newSlider(…, { tapToPositon = false })` used to build a slider that
silently ignored the option.

**The cost is stated at the top of §5 because it is the most important thing in
this document: Facet has no escape hatch.** The adapter's class map is closed
(`CLASS_TO_INSTANCE`, seven entries, everything else becomes a `Frame`), and
there is no blueprint class that takes an engine class name or an engine
Instance. `UI.Stage` hands you a `ViewportFrame`'s 3D content root; that is the
only door, and it opens onto a 3D scene rather than onto GuiObjects. If your game
needs a `VideoFrame`, an `EditableImage` surface, or a vendor's GUI widget inside
a Facet layout, there is currently no way to say so.

### 2.5 "Who owns a property?" — the thing React has no concept of

This is the disagreement the director named, and it is the one with the sharpest
evidence, because Roblox is a **co-owner of the render tree**.

Roblox ships StyleSheets — its own CSS-like system, described on Roblox's UI page
as "a Roblox solution to stylesheets, similar to CSS, that lets you declare and
globally apply overrides to UI instance properties" ([RL-30]). Two things can
therefore decide a `Frame`'s `BackgroundColor3`: a StyleRule, and a script. And
the engine does not arbitrate. Facet's manifest opens by stating what a Studio
spike measured:

```lua
-- src/render/authority.luau
-- Property-authority manifest (design §7.3, UI-STYLE-001): exactly one
-- authority per engine render property per class. The Studio spike proved the
-- engine will NOT police this (an explicit write silently defeats StyleRules
-- and fires no signals), so the renderer asserts it at the ONLY write site.
```

An explicit write does not merely win this frame — it **permanently defeats the
rule**, and nothing fires. That is a bug class with no symptom until a theme
swap or a state change fails to repaint.

**Facet's answer is a static manifest of exactly one authority per property per
class**, with five names — `layout`, `style`, `binding`, `presentation`, `host` —
and a hard assertion at the single write site:

```lua
function authority.assertWrite(class: string, prop: string, writer: Authority)
	local owner = authority.authorityFor(class, prop)
	if owner == nil then
		error(`Facet authority: no declared authority for {class}.{prop} (declare it in the manifest)`, 0)
	end
	if owner ~= writer then
		error(`Facet authority: {writer} tried to write {class}.{prop} owned by {owner}`, 0)
	end
end
```

Both branches are errors: an **undeclared** property is as illegal as a
**wrongly-claimed** one. The manifest is not decorative — it encodes real
decisions. `Text.textFont` is *layout* authority rather than style, because the
solver measures with that font descriptor and a second writer for the face would
reopen the measure/paint split. `CanvasPosition` is *deliberately absent*, and the
comment says why: "the ENGINE co-authors it (user scrolling) and the framework's
scrollTo is a request, not an owned property". Three further gates sit in the same
file — nineteen engine property names that transfer to the DataModel StyleSheet in
native mode and which the adapter must therefore never write; a frozen allowlist
of thirteen adapter-created child Instance names ("being on this list buys the
right to EXIST, not the right to paint"); and six seam-owned properties on
adapter-owned Instances gated by a second assertion. The fifth authority name,
`host`, is declared and **unused**, and the file says so on the record: the
custom-control seam it was reserved for never shipped.

**React-Lua has no concept of this, and the absence is verifiable.** `StyleSheet`,
`StyleRule` and `GetStyled` each occur **zero times** in the entire react-luau
repository ([RL-31]). There is no manifest, no assertion, and no diagnostic. The
model is simply "the component that declared the prop writes the prop", which is
sound as long as exactly one component declares it and no StyleRule is aimed at
the same Instance.

Be precise about what this does and does not mean. React-Lua's model is *not*
broken: each host element owns its own Instance, so two React components cannot
contend for one property in the ordinary case. What is unguarded is the
*engine-versus-script* boundary — a project that adopts Roblox StyleSheets
alongside React-Lua gets no warning when a prop write silently kills a rule, and
a project that uses `refs` to write properties imperatively gets no warning at
all. Facet treats that boundary as the framework's problem; React-Lua treats it
as yours.

There is one live correctness issue in the same layer worth recording rather than
editorializing about. The renderer's binding cleanup is gated behind a Roblox
FastFlag whose declared default is `false`, and the ungated path drops the
per-Instance binding table **without calling the stored disconnect functions**
([RL-29]). The fix exists in the source. FastFlags are set by Roblox at runtime,
so the source's default does not tell you the live value — what can be verified
here is only that the code declares `false` and that the unflagged branch leaks.

### 2.6 "May a frame be interrupted?" — a scheduler versus a settle phase

**React-Lua is genuinely concurrent, and this is its most underrated strength on
this platform.** `ReactRoblox.createRoot` is Concurrent Mode; the migration guide
says the model "allows it to divide work across multiple frames and preserve high
framerate and interactivity", and that Concurrent Mode is the **default**
([RL-14]). This is not aspirational: the scheduler is a real time-slicing
implementation with a `shouldYieldToHost` deadline check, a configurable yield
interval (default 15 ms), desired and minimum frame-rate targets, and a
`RunService.Heartbeat` connection for frame markers ([RL-33]). A 2000-element
first render can be spread across frames instead of dropping one.

**The catch is that the user-facing concurrent API does not exist.** The React
package's export table carries these lines verbatim ([RL-08]):

```lua
	-- Concurrent Mode
	-- ROBLOX TODO: useTransition,
	-- ROBLOX TODO: startTransition,
	-- ROBLOX TODO: useDeferredValue,
	-- ROBLOX TODO: REACT_SUSPENSE_LIST_TYPE as SuspenseList,
```

So "concurrent React on Roblox" means the scheduler, not the API. You get
interruptibility; you cannot mark an update low-priority, and you cannot keep a
stale value visible while a new one computes.

It also has a testing cost that is worth knowing before you adopt it. Because
rendering is asynchronous, tests must drive a mocked scheduler through
`ReactRoblox.act` — and the configuration page states flatly that "Since Roact 17
uses concurrent rendering by default, you will always need this global to be set
to `true`" ([RL-19]). `act` itself "will not be available" in production and is
gated behind a second global ([RL-20]).

**Facet is completely synchronous, deliberately, and says so in the source:**

```lua
-- src/render/renderer.luau, at the end of controller.refresh()
-- LAST, after the solve, so a hook can read its own rect (see the queue's
-- declaration). Nothing has reached the screen yet: this whole call is
-- synchronous, and the engine renders after it returns.
```

There is no time slicing, no priority, no interruption. `task.defer` and
`task.spawn` appear **zero times** in `src/`; `task.delay` appears twice, in
async-resource retry backoff and a paint timer, neither on the render path.
Facet never schedules itself at all — the game host calls `presenter.refresh()`
and `presenter.tick(dt)` from its own frame connection.

What Facet has instead is **`settle`**, and it is the piece of the reactive
contract with no React analogue. From `src/core/contract.luau`:

> "a flush SETTLES before it ends. `settle` registers terminal work — the
> expensive, externally-visible half of a change (the shipped case is a surface's
> layout solve and the geometry it feeds back to its consumer). Settle callbacks
> run after propagation quiesces, in REGISTRATION order; a callback that writes
> ends the pass, propagation drains, and the pass RESTARTS from the first
> callback, so every settle callback observes every other one's publication.
> Passes repeat until one writes nothing… Settle is NOT an observer: it receives
> no value, it is not part of glitch-freedom, and it runs inside the flush — so a
> top-level write still returns with all of its consequences applied."

React's nearest neighbour is `useLayoutEffect`, and it is not the same shape: a
write from a layout effect schedules a **new** render pass. Facet's settle phase
converges *inside* the current flush, which is the two-pass shape it was built to
eliminate — the source records the measurement, 4 solves and 2 reactive flushes
per geometry change before, 2 and 1 after.

**The honest trade.** Facet's synchrony buys exactness (`env:set` returns with
the surface solved), trivially deterministic tests with no `act` and no mock
scheduler, and one clock. It buys those by putting the entire cost of a change on
one frame. Its answers to a large mount are all *reduce the work* rather than
*spread the work*: virtualization, incremental layout (~17× fewer arranged nodes
for a one-value change), container elision (−34 % instances), instance recycling.
Those are measured — headlessly. **No Facet number in this document or any other
comes from a physical device.** React-Lua's slicing is a structurally different
answer to the same problem and Facet has no counterpart to it.

### 2.7 The difference that decides adoption: a renderer versus a UI kit

Everything above is architecture. This one is scope, and for most readers it
matters more.

**React-Lua is a renderer.** It gives you a component model, a reconciler, a
scheduler, and a way to turn elements into Instances. It does not give you a
button. It does not give you a theme, a focus system, a gamepad story, a modal
presenter, a slider, a virtualized list, a spring, an accessibility contract, or
a layout vocabulary. Everything you see on screen, you draw. That is ReactDOM's
scope and it is a coherent choice — the web ecosystem fills that gap with a
hundred component libraries. **On Roblox, there is no such ecosystem, so the gap
is yours to fill.**

**Facet is a UI kit with a framework under it.** Its conformance registry holds
59 rows — 32 composite classes and 27 leaves — and `check_registration` reports
**19 of 19** interactive controls carrying an automated proof that they work with
mouse, touch, keyboard *and* gamepad, plus a device-idiom proof. It ships theme packages that
own typography, metrics, radii and asset chrome; a focus graph with grouped
scopes and directional navigation; a presenter with modals, toasts, popovers,
focus traps and layering bands; a motion system with named spring classes and a
Reduce Motion policy; drag and drop across four input classes.

If you are building a Roblox game UI and you pick React-Lua, your first month is
spent building the things in the previous paragraph. If you pick Facet, your
first month is spent finding out which of the 26 classes can express your design
and what to do about the parts that cannot — because there is no escape hatch.

Those are different risks, not different amounts of risk.

### 2.8 Could a React reconciler sit under Facet's core contract?

The director asked this directly, and it deserves a real answer rather than a
shrug, because Facet's core **is** deliberately swappable and there is proof.

`src/core/contract.luau` is a pure type module — it ends `return nil` — declaring
an eleven-member `Core` interface (`signal`, `memo`, `observe`, `effect`,
`settle`, `transaction`, `flush`, `scope`, `counters`, `lastError`, `name`) plus
about forty lines of stated semantics. Every consumer takes `core` as a
parameter: `mount(core, …)`, `renderer.attach(core, …)`, `presenter.new(core, …)`,
`environment.new(core)`. **Three implementations of that contract exist in this
repository** — `custom` (the shipped one), `fusion_adapter` (over vendored Fusion
0.3), and `imperative` (a baseline) — and one conformance suite of 46 checks runs
identically against all three, writing a scorecard per candidate:

| Core | Result | Named failures |
|---|---|---|
| `custom` | **46 / 46 PASS** | — |
| `fusion` | **37 / 46 FAIL** | `transaction-batches-observer-to-one-fire`, `custom-equality-respected`, `cycle-reported-not-hung`, `write-during-memo-is-error`, `settle-runs-after-propagation-and-converges-in-one-flush`, `settle-that-never-converges-hits-the-iteration-cap`, `memo-error-quarantined`, `transaction-revert-produces-no-fire`, `micro-live-hud-value` |
| `imperative` | **40 / 46 FAIL** | `dynamic-dependencies-swap-atomically`, `write-during-memo-is-error`, `transaction-revert-produces-no-fire`, `nan-equal-write-skipped`, `observer-disposed-by-sibling-does-not-fire`, `observer-added-mid-flush-fires-next-flush-only` |

(`artifacts/conformance-*.json`, regenerated by `tests/conformance/cli.luau`.)

So "swappable" is precise rather than aspirational, and it is also honest about
what swapping costs: the Fusion adapter is *shaped* like a `Core` and fails nine
semantic checks. It does not pretend otherwise — it declares
`cycleDetection = false` and `writeDuringMemoError = false` in its factory, the
CLI refuses a factory that claims a semantic its scorecard fails, and the adapter
comments say what it cannot do rather than faking it:

> "ONE pass is all this substrate can distinguish — with eager propagation there
> is no write set to test for quiescence, so 'repeat until a pass writes nothing'
> is not implementable and **is not faked**."

**Now the question. Could React sit here?**

**As a *consumer* of the contract, yes, and trivially** — a React component can
subscribe to a `Signal` and call `setState`. That is the `useSyncExternalStore`
pattern, and although React-Lua at 17.0.1 has no such hook, `useState` plus
`useEffect` plus `core:observe` is five lines.

**As an *implementation* of the contract, no — and the obstruction is structural
rather than a matter of effort.** Four of the contract's requirements have no
React expression:

1. **A `Memo` is a first-class value you can hold, pass, and read from anywhere.**
   `Readable<T>` is `Signal<T> | Memo<T>`, and `memo:get()` is callable from any
   code at any time — from a solver, from an adapter, from a test with no tree
   mounted. A React hook is not a value and cannot be called from a solver, and
   React-Lua's own source says so in the error it raises: "Invalid hook call.
   Hooks can only be called inside of the body of a function component."
   ([RL-42]) — every hook resolves through `ReactCurrentDispatcher.current`,
   which is `nil` outside a render. There is no way to hand `useMemo`'s result to
   a layout solver that is not a component.

2. **`transaction` must batch writes and publish once, and a reverted
   transaction must fire nothing.** The conformance suite pins both
   (`transaction-batches-observer-to-one-fire`,
   `transaction-revert-produces-no-fire`), and Facet's core implements the second
   by de-duplicating each observer against a `lastSeen` value. React-Lua at 17.0.1
   exposes no transaction verb at all — there is no `withTransaction` in the
   export table ([RL-40]) — so a core built on it would have to synthesize the
   grouping outside React's own update mechanism. Note that `fusion` fails both
   of these checks too, so this is a bar a real reactive library already misses
   rather than a React-specific complaint.

3. **`settle`, which is the load-bearing one.** The contract requires terminal
   work that runs *inside* the flush after propagation quiesces, in registration
   order, restarting on any write, until a pass writes nothing, under a bounded
   iteration cap — with the guarantee that "a top-level write still returns with
   all of its consequences applied." React-Lua has no phase with that contract.
   Its nearest neighbour, `useLayoutEffect`, is documented here as running
   "_during_ an update in between rendering and reconciliation" ([RL-28]) — which
   is a *position in the pipeline*, not a convergence guarantee — and rendering
   itself is asynchronous and interruptible by default ([RL-14]). A React core
   could not make `env:set(…)` return with the surface solved, and Facet's
   renderer, presenter and every test depend on exactly that.

4. **`scope`, `counters` and disposal as first-class verbs.** The contract
   requires reverse-order idempotent disposal, double-dispose detection, and live
   counters that return to baseline (the `memory-neutral-churn` check). React
   ownership is per-component-instance and implicit, and React-Lua's export table
   contains nothing that returns a disposable scope or a live resource count
   ([RL-40]) — so there is no handle to hand back and nothing to count.

**The honest conclusion.** Facet's core contract is not a general "reactive
library" interface — it is a *synchronous, glitch-free, convergent-within-a-flush*
interface, and the settle clause in particular was written for a layout solver
that must publish geometry and read it back before the frame ends. React's
reconciler is a different answer to a different question, and the two are not
substitutable in this direction. That is a finding about the contract's shape, not
a criticism of React: it means Facet's swappability is real but bounded, and the
boundary is *synchrony*.

One consequence is worth naming for the record: **`src/init.luau` hardcodes the
custom core** (`newCore = customCore.new`), and `fusion_adapter` is required by
nothing in `src/`. The contract is swappable by parameter injection — every
consumer takes `core` as an argument — but the library ships no switch.

---

## 3. Pros and cons, in plain language

Honest both ways. Read both columns before deciding either.

### React-Lua — what is genuinely good

**A mental model hundreds of thousands of people already have.** This is the
single largest advantage and it is not close. If you have written React, you can
write React-Lua on day one; the deviations page is short enough to read in ten
minutes ([RL-04] through [RL-12]). If you have not, every React tutorial, blog
post, Stack Overflow answer and mental model on the internet still applies, and
React-Lua's own documentation is explicit that this is the plan: it tells you to
learn React JS first and treats its own site as "a comprehensive guide to the
_differences_" ([RL-03]).

**Roblox maintains it and Roblox ships on it.** A guide in the DevForum's *Roblox
Staff* category — whose own description is "This category contains articles
authored by Roblox staff" — states that "React-lua is maintained by Roblox. Currently most studio plugins and
the Roblox Universal App (the desktop console and mobile app where you browse for
your favorite Roblox games) are all written in react-lua" ([RL-23]). Whatever
else is true, it is load-bearing for Roblox's own products.

**Every Roblox property works, forever, with no framework update.** Because props
are assigned by name ([RL-16]) and elements are `Instance.new(ClassName)`
([RL-15]), a Roblox class or property shipped tomorrow works today. There is no
"the framework doesn't support that yet."

**You can install it.** Wally (`roblox/react`, current `17.3.11`) and a Creator
Store package published by Roblox itself ([RL-25], [RL-26]). Real dependency
management, real versioning.

**Concurrent rendering is real.** A large tree can be built across frames rather
than in one hitch ([RL-14], [RL-33]). Facet has no counterpart to it, and §5
rank 7 explains why it declines to build one.

**A serious testing and tooling ecosystem.** React DevTools, Fast Refresh,
`jest-react`, a test renderer, a shallow renderer and a noop renderer all ship in
the monorepo ([RL-34]).

**Bindings are a genuinely good invention.** The framework noticed that
re-rendering per animation frame is absurd and added a per-value channel that
bypasses reconciliation ([RL-02], [RL-12]) — and then implemented refs on top of
it, which solves a real Roblox problem (assigning `NextSelectionRight` to a
sibling's ref that does not exist yet) elegantly.

### React-Lua — what it costs you

**It is React 17, and it has been for a while.** Alignment is pinned at 17.0.1
([RL-03]). One GitHub release has ever been published, `v17.0.1`, in January 2024
([RL-35]). 2026 commit activity is real but is mostly packaging and registry
plumbing ([RL-24]). No React 18 port exists.

**Error boundaries do not fully work.** Verbatim: "Error boundaries are not yet
fully supported due to a limitation in Luau around recursive `pcall` depth"
([RL-05]). For a *game*, where a UI crash and a player losing their session are
the same event, this is the most consequential single line in React-Lua's
documentation.

**Suspense is shipped and unusable.** "**While `React.Suspense` is technically
implemented, it should be considered unusable as of version `17.0.1`.**" ([RL-06])
— same root cause. `React.lazy` is implemented and then discouraged in its own
documentation ([RL-36]).

**The concurrent hooks are absent** — `useTransition`, `startTransition`,
`useDeferredValue` are commented-out TODOs ([RL-08]).

**`defaultProps` and `propTypes` do not work on function components** ([RL-10]),
which is the component style the documentation tells you to prefer.

**The official documentation site does not resolve.** `react-luau.dev` is
registered to Roblox nameservers and has **no A record** — verified against both
`8.8.8.8` and `1.1.1.1` on 2026-08-15 ([RL-27]). The README links it four times.
The docs are readable at `roblox.github.io/roact-alignment/` and in the repo's
`docs/` folder, and a first-time reader has to work that out.

**The repository is a read-only mirror** ([RL-24]) and does not accept community
contributions, which is why a community fork exists.

**The docs lag the source.** `useDebugValue` is listed as "Not yet implemented"
([RL-07]) while the source exports and implements it ([RL-37]). Treat the docs as
a floor.

**No layout, no controls, no theme, no input model, no accessibility story.** You
build all of it ([RL-08], [RL-34], and §2.7).

**There is no property-authority concept**, so mixing React-Lua with Roblox's own
StyleSheets is unguarded ([RL-31]).

**There are no published benchmarks.** `docs/bench.md` is an empty chart shell
whose data renders on the dead domain ([RL-38]).

### Facet — what is genuinely good

**It is a UI kit, not a renderer.** 51 registered rows; 16 of 16 interactive
controls carry an automated four-input proof *and* a device-idiom proof. You do
not build a slider.

**Work scales with what changed, not with what exists.** No re-render, no tree
diff; a bound-value change costs the same at 100 and 3200 rows, enforced as a
ratio test.

**Layout is a real engine and it is diagnosable.** A strict superset of Roblox's
own flex controls in every respect but one deliberate divergence, plus priority
tiers, ranked region degradation, `ViewThatFits`, incremental re-solve — and it
runs headlessly, so layout is unit-testable with no Roblox present.

**The framework refuses mistakes at construction with a message that names the
fix.** Unknown props, refused props, reactive values on static props, focusables
inside a Button, `align = "stretch"` on a wrapping stack — each is an error at
the call site with the reason and the route.

**Error boundaries work.** `UI.ErrorBoundary{ view, fallback }` catches a throw
at mount or during any structural rebuild in its subtree and swaps to the
fallback; `presenter.presentCritical` does the same for a whole screen. This is
precisely the capability React-Lua's own documentation says it does not have
([RL-05]).

**Property authority is enforced**, and the engine-versus-script boundary
Roblox's StyleSheets create is treated as the framework's problem (§2.5).

**Everything is synchronous**, so tests need no `act`, no mock scheduler, and no
reasoning about which frame a change lands on.

**The maintenance machinery is unusual.** Checkers reconcile six independent
views of every property; a control cannot ship unregistered; documentation cannot
drift from the export table without a gate going red. Three of the four suite
failures in the run recorded in §6 are the repository policing *itself*.

### Facet — what it costs you

**There is no escape hatch.** Twenty-six classes; no way to render an arbitrary
Roblox class. If your design needs something the framework has not modelled, you
stop. This is the top of §5 for a reason.

**You cannot install it.** No Wally package, no Creator Store asset, no tagged
release. Version `0.9.0`, private repository.

**Nobody else knows it.** Every concept — blueprint, solver, surface, scope,
authority, contribution — is local to this codebase. A new hire's React knowledge
transfers to React-Lua on day one and to Facet not at all.

**No screen-reader support of any kind.** A blind player cannot use a Facet
interface. (React-Lua has none either; neither does Roblox. This is a platform
hole, not a differentiator — but it is a hole.)

**No right-to-left or bidirectional support anywhere.**

**Nothing has ever been confirmed on physical hardware.** Every four-input,
haptics and performance claim is a headless test run or a Studio emulator drive.

**One long frame is one long frame.** No time slicing (§2.6).

**No live tree inspector and no hot reload.** React DevTools and Fast Refresh
have no Facet counterpart; the answers are deterministic dumps, a diagnostics
surface and scripted Studio drives — all batch, none interactive.

**One person and a set of agents maintain it**, against a framework Roblox
maintains and ships its own products on.

---

## 4. Feature comparison

Capability, status on each side, evidence. React-Lua rows cite §7; Facet rows
cite source files, which is where they were read from.

### 4.1 Element and component model

| Capability | React-Lua | Facet | Evidence |
|---|---|---|---|
| Declarative element construction | **Ships.** `React.createElement(type, props, children)`. **No JSX** — "The Luau ecosystem does not yet have the tooling to support JSX" ([RL-04]) | **Ships.** `UI.VStack{ children = {…} }` — a table literal per class, so there is no `createElement` ceremony and no children-vs-props argument order to remember | [RL-04]; `src/blueprint.luau` |
| Arbitrary Roblox class as an element | **Ships**, and it is the whole model: the element type string is passed to `Instance.new(type_)` ([RL-15]) | **Absent.** 26 registered classes; the adapter's `CLASS_TO_INSTANCE` map has seven entries and everything else becomes a `Frame`. No blueprint class takes an engine class name or Instance. §5 rank 1 | [RL-15]; `src/blueprint_schema.luau`, `src/client/screen_target.luau` |
| Unknown property | **Ships as a runtime error at write time** — the prop is assigned by name to the Instance and Roblox raises ([RL-16]) | **Ships as a construction-time error** naming the class, the property, up to three Levenshtein suggestions, and the full legal set. A *refused* prop gets the reason instead | [RL-16]; `src/blueprint.luau` (`make`, `unknownPropError`), `src/blueprint_schema.luau` (`suggest`, `refusal`) |
| Function components | **Ships**, and are the preferred style — but "function components do not support the `defaultProps` feature" and the same for `propTypes` ([RL-10]) | **N/A by design.** No component unit exists; a reusable piece is a plain Luau function returning a blueprint, or a `build(Facet, core, spec)` control | [RL-10]; §2.3 |
| Class components with lifecycle | **Ships** via `React.Component:extend(name)`; `init` replaces the constructor, and `setState` is legal there ([RL-39]) | **N/A by design** | [RL-39] |
| Immutable elements | **Ships** by convention (React elements are not frozen in Luau) | **Ships, enforced.** `table.freeze` on props, children and the node — added after a shared row template was mutated in place through `bp.props` | `src/blueprint.luau` |
| Fragments (several siblings, no wrapper) | **Ships.** `React.Fragment` ([RL-40]) | **Ships, differently.** `UI.When` and `UI.ForEach` splice their children into the parent's flow; there is no bare fragment class, and none has been needed | [RL-40]; `src/mount.luau` |
| `memo` / render bail-out | **Ships.** `React.memo` ([RL-40]) | **N/A by design.** There is no render to skip — a prop change writes into the mounted node and nothing above it is visited | [RL-40]; `src/mount.luau` |
| Typed public surface | **Ships, with caveats.** Luau types throughout; `propTypes`/`validateProps` are class-component-only ([RL-10]) | **Ships.** 59 exported `*Spec` types; closed key sets on specs and opts tables too (`src/spec_guard.luau`) | [RL-10]; `src/init.luau` |

### 4.2 State and data flow

| Capability | React-Lua | Facet | Evidence |
|---|---|---|---|
| Component-local state | **Ships.** `useState`, returning two values rather than a destructured array ([RL-32]) | **Ships, with caveats.** State is caller-owned signals in an explicit scope. A `ForEach` row receives an `itemScope`; **a `When` branch receives no scope at all** — §5 rank 2 | [RL-32]; `src/mount.luau`, `src/blueprint_schema.luau` |
| Fine-grained value subscription (no re-render) | **Ships** as a second, opt-in channel: Bindings — "signals-based state that doesn't re-render" ([RL-02], [RL-12]) | **Ships** as the *only* channel: `core:signal` / `core:memo` with per-value dependency tracking | [RL-02], [RL-12]; `src/core/custom.luau` |
| Derived / computed state | **Ships.** `useMemo`, with the Luau dependency-array deviation ([RL-11]) | **Ships**, glitch-free: eager stale-marking plus pull-based recompute, so a diamond dependency never fires an observer with inconsistent inputs | [RL-11]; `src/core/custom.luau`, conformance `glitch-free-diamond` |
| Reducer | **Ships.** `useReducer` ([RL-40]) | **Composable.** A memo over a signal plus a dispatch function; no construct | [RL-40] |
| Batched writes / transactions | **Ships** as automatic batching inside React's own update mechanism; no user-facing transaction verb at 17.0.1 | **Ships** as `core:transaction(body)` — many writes, one observer fire; a reverted transaction fires nothing | `src/core/contract.luau`, conformance `transaction-batches-observer-to-one-fire`, `transaction-revert-produces-no-fire` |
| Effects | **Ships.** `useEffect` (after commit) and `useLayoutEffect` (before Instance reconciliation), the latter with no clear Roblox use case per its own docs ([RL-28]) | **Ships.** `core:observe` (post-flush, value-carrying, de-duplicated), `core:effect` (tracked), and `core:settle` (terminal, converges inside the flush — §2.6). `core:effect` is used **once** in the whole framework, `core:settle` once | [RL-28]; `src/core/contract.luau`, `src/present/presenter.luau`, `src/render/renderer.luau` |
| Tree-scoped context | **Ships.** `React.createContext` + Provider/Consumer + `useContext` ([RL-40]) | **Absent as a general mechanism.** `Env` is one per application, shared across every surface, with per-key signals so a keyboard-occlusion change never touches a colour-only subscriber. The only tree-scoped inheritance is one static string, the `sensoryFeedback` activation verb. §5 rank 6 | [RL-40]; `src/env/environment.luau`, `src/mount.luau` |
| External-store subscription hook | **N/A.** `useSyncExternalStore` is a React 18 API and does not exist at 17.0.1 alignment ([RL-08]) | **N/A by design** — everything is the store | [RL-08] |
| Cycles in derivation | **Absent as a concept** (a render loop hits React's update-depth guard) | **Ships** — a dependency cycle raises with the full path rather than recursing | `src/core/custom.luau`, conformance `cycle-reported-not-hung` |
| Writing state during a derivation | **Absent as a concept** | **Ships** — illegal by construction: `Facet: writing state during memo evaluation is an error` | `src/core/custom.luau`, conformance `write-during-memo-is-error` |
| Runaway-effect protection | **Absent** as a named public behaviour | **Ships.** A 100-round flush cap turns an effect or settle feedback loop into a readable error with the count of discarded writes | `src/core/custom.luau`, conformance `feedback-loop-hits-iteration-cap` |
| Deterministic notification order | **N/A by design** (order is tree order, rebuilt each render) | **Ships, with a stated limit.** Observers fire in node **creation** order — a total order across nodes. The contract states plainly that **effect ordering is not yet promised** | `src/core/contract.luau`, `src/core/custom.luau` |

### 4.3 Layout

| Capability | React-Lua | Facet | Evidence |
|---|---|---|---|
| A layout system | **Absent by design.** No layout API in the export table, no layout package, and the element vocabulary is Roblox class names — so layout is `UIListLayout`/`UIGridLayout`/`UIPadding` declared as child elements, exactly as ReactDOM defers to CSS | **Ships.** A headless measure-then-arrange solver producing absolute rects; the renderer writes only `Position` and `Size`, as `UDim2.fromOffset`, at one call site | [RL-08], [RL-34], [RL-15]; `src/layout/solver.luau`, `src/client/screen_presentation.luau` |
| Engine layout objects materialized | **Ships** — they are the mechanism | **Zero.** Not one `Instance.new("UIListLayout")`, `UIGridLayout` or `UITableLayout` in `src/`. `UIPadding` is created twice, both for a single control's own engine text inset | `src/` (searched); `src/client/screen_target.luau` |
| Instance-tree shape | **Nested**, mirroring the element tree | **Flat by default, with four registered exceptions.** The render-target seam still takes no parent handle — nesting is a registration policy the adapter runs, not a renderer capability. A `ScrollView`, a declared `clipChildren`, a fade group (`canvasGroup`/`opacity`), and — since [ADR-0032](../adr/ADR-0032-nested-instance-tree.md) — a container whose own authored `scale`/`rotation` reaches children it has, each register as a real parent for exactly the subtree the engine can carry for it; everything else still parents under the one `ScreenGui` | `src/render/target_contract.luau`, `src/client/screen_target.luau`, `src/render/instance_boundary.luau` |
| Containers that cost nothing | **Absent** — a layout container is a `Frame` and cannot be removed | **Ships.** Six elidable classes produce **no Instance at all** when they paint nothing, materialized lazily if ever written to. Measured: 55 of 137 GuiObjects on a five-row surface were completely inert | `src/client/screen_target.luau` |
| Headless (no-engine) layout testing | **Absent** — layout is the engine's, so there is nothing to test without it | **Ships** — the solver has no engine types; layout is unit-tested in Lune | `src/layout/`, `tests/` |
| Layout diagnostics | **Absent** | **Ships.** `controller.diagnostics()` reports overflow, unbounded percent, mixed grid children, inert placement props, HUD-zone collisions and cross-surface overlap | `src/render/renderer.luau` |
| Incremental relayout | **N/A by design** (the engine relayouts) | **Ships.** A changed value re-solves only the smallest enclosing subtree; measured 141 arranged nodes down to 8 | `src/render/renderer.luau`, `tests/incremental_layout.spec.luau` |
| Priority / degradation vocabulary | **Absent** — `UIFlexItem` is the engine's only dial | **Ships.** `layoutPriority` tiers × `shrinkWeight`, `ViewThatFits`, `UI.Composition`/`UI.Region` ranked region ladders, `containerRelativeFrame` | `src/layout/`, `the comparison document` §4 |
| Lazy / virtualized collections | **Composable** — you write the windowing | **Ships.** `newVirtualList`, `newTable{ virtualized = true }`, `newVirtualGrid` on both axes, sharing one prefix-sum extent index | `src/controls/`, `src/virtual_extents.luau` |

### 4.4 The engine boundary

| Capability | React-Lua | Facet | Evidence |
|---|---|---|---|
| Property write model | **Ships** as `hostInstance[key] = newValue`, no allowlist, no validation. `nil` calls `ResetPropertyToDefault` with a default-table fallback ([RL-16]) | **Ships** as a gated write: `authority.assertWrite(class, prop, writer)` before every engine write, with exactly one authority per property per class and an error on both undeclared and wrongly-claimed | [RL-16]; `src/render/authority.luau` |
| Awareness of Roblox StyleSheets | **Absent.** `StyleSheet`, `StyleRule` and `GetStyled` occur **zero** times in the repository ([RL-31]) | **Ships.** 19 engine properties declared native-sheet-owned and forbidden to the adapter in native mode, because "an explicit write silently and permanently defeats the rule" | [RL-31]; `src/render/authority.luau`, `src/client/native_style.luau` |
| Engine events | **Ships.** `[React.Event.X]` and `[React.Change.X]`, auto-connected at mount and auto-disconnected at unmount. Callback's first argument is the Instance ([RL-17]) | **Ships, differently.** Blueprint handler props (`onActivate`, pointer handlers) routed through the render-target contract; raw engine event access is not a consumer surface | [RL-17]; `src/render/target_contract.luau` |
| CollectionService tags | **Ships.** `[React.Tag] = "a b"` ([RL-18]) | **Ships, internally only.** `facet-*` tags classify instances for the native stylesheet cascade; not a consumer prop | [RL-18]; `src/client/native_style.luau` |
| Reference to the underlying Instance | **Ships.** `createRef`, callback refs, `useRef` — implemented on top of Bindings, which solves the sibling-ref ordering problem ([RL-12]) | **Ships, barely.** `adapter.getInstance(path)` exists but is not on the render-target contract, is not reachable through `Facet.*` or the controller, returns `nil` for an elided node, and every in-repo consumer is a test or gallery scenario. The sanctioned handle is `controller.stageHost(path)` for `UI.Stage` | [RL-12]; `src/client/screen_target.luau`, `src/render/renderer.luau` |
| Swappable render target | **Ships.** `react-reconciler` plus host configs; `react-noop-renderer` and a test renderer ship ([RL-34]) | **Ships**, as a written contract: 6 required methods, 25 optional (each absence one named non-crashing degrade), 5 theme. Two shipping targets (`ScreenGui`, `BillboardGui`) plus a headless fake | [RL-34]; `src/render/target_contract.luau` |
| Coexisting with existing Roblox GUI | **Ships, with caveats.** A root "take[s] complete control of the provided container, deleting all existing children", so the documented pattern is to mount into a dedicated `Folder` and portal out ([RL-21], [RL-22]) | **Ships.** Each surface creates its own `ScreenGui` under `PlayerGui`; existing GUI is untouched. What is **absent** is the reverse — you cannot mount a Facet subtree inside an existing `Frame` | [RL-21], [RL-22]; `src/client/screen_target.luau` |

### 4.5 Structure, lifecycle and errors

| Capability | React-Lua | Facet | Evidence |
|---|---|---|---|
| Keyed list reconciliation | **Ships**, both spellings: a keyed table of children (legacy Roact's shape) and the reserved `key` prop; using both warns in Dev Mode ([RL-09]). The key also becomes the Instance's `Name` ([RL-15]) | **Ships.** `UI.ForEach{ key, row }`: add / remove / move only, with **duplicate keys a hard error**, per-key child scopes, and a row removed and re-added mid-exit resuming the same mounted subtree and instances | [RL-09], [RL-15]; `src/mount.luau` |
| Conditional subtrees | **Ships** — return `nil` or a different element from render | **Ships.** `UI.When{ condition, thenView }`, one of exactly three classes permitted to mount or unmount | `src/mount.luau` |
| Error boundaries | **Ships, broken.** "Error boundaries are not yet fully supported due to a limitation in Luau around recursive `pcall` depth" ([RL-05]) | **Ships.** `UI.ErrorBoundary{ view, fallback }` catches a throw at mount or during any structural rebuild inside the subtree and swaps to `fallback(err)` once; errors inside the fallback stay hard, deliberately. `presenter.presentCritical` is the surface-level twin | [RL-05]; `src/mount.luau`, `src/present/presenter.luau` |
| Suspense / streaming | **Ships, unusable.** "should be considered unusable as of version `17.0.1`" ([RL-06]) | **Absent**, and not planned. The async story is `newResourceProvider` — scope-owned handles with generation-counter stale-completion rejection and bounded retry | [RL-06]; `src/async/resources.luau` |
| Lazy component loading | **Ships, discouraged** by its own documentation: "This is rarely a concern in the context of Luau projects" ([RL-36]) | **Absent**, for the reason React-Lua's own docs give | [RL-36] |
| Portals | **Ships.** `ReactRoblox.createPortal` ([RL-13]) | **Absent as tree escape.** The answer is separate surfaces — `presentModal`, `presentToast`, and `bindPresent` for a control-owned floating surface that contributes **zero** to any ancestor's measured size | [RL-13]; `src/present/presenter.luau`, `src/input/contribution.luau` |
| Mount / unmount hooks | **Ships.** `useEffect` with an empty dep array; class lifecycle methods | **Ships.** `onAppear` / `onDisappear` as shared props on every rendered class, with exact ordering: appear fires **after that frame's layout solve** (so the callback can read its own rect) and still before anything reaches the screen | `src/blueprint_schema.luau`, `src/render/renderer.luau` |
| Resource ownership and disposal | **Ships** implicitly, per component instance | **Ships** explicitly. `scope:own` / `use` / `child` / `dispose`, reverse-order and idempotent, refusing anything with no `dispose()`, with double-dispose detected and cleanup errors quarantined. Live counters (`signals`, `memos`, `observers`, `effects`, `scopes`, `settles`) return to baseline, enforced by a conformance check | `src/core/scope_impl.luau`, conformance `memory-neutral-churn` |

### 4.6 Scheduling

| Capability | React-Lua | Facet | Evidence |
|---|---|---|---|
| Interruptible / time-sliced rendering | **Ships**, and is the default. A real scheduler with a yield deadline, configurable yield interval (default 15 ms), frame-rate targets and a `Heartbeat` connection ([RL-14], [RL-33]) | **Absent.** `refresh()` is one synchronous call; zero `task.defer`, zero `task.spawn` in `src/`. The framework never schedules itself — the host drives `refresh()` and `tick(dt)` | [RL-14], [RL-33]; `src/render/renderer.luau` |
| Priority / transitions API | **Absent.** `useTransition`, `startTransition`, `useDeferredValue` are commented-out `ROBLOX TODO`s ([RL-08]) | **Absent** | [RL-08] |
| A write returns with its consequences applied | **Absent by design** (asynchronous commit) | **Ships.** The `settle` phase runs *inside* the flush, restarting until a pass writes nothing, under the same iteration cap — so `env:set(…)` returns with the surface solved | `src/core/contract.luau`, `src/render/renderer.luau` |
| Testability of scheduling | **Ships, with ceremony.** Tests need `ReactRoblox.act` plus a mocked scheduler; "you will always need this global to be set to `true`", and `act` is unavailable in production ([RL-19], [RL-20]) | **N/A by design** — synchronous, so tests assert immediately after the write | [RL-19], [RL-20] |

### 4.7 What is only on one side

| Capability | React-Lua | Facet | Evidence |
|---|---|---|---|
| Shipped, proven controls | **Absent.** No button, slider, table, picker, or anything else | **Ships.** 51 registered rows; `check_registration` reports 16 of 16 interactive controls carrying an automated mouse/touch/keyboard/gamepad proof plus a device-idiom proof | `tests/conformance/controls_registry.luau`; `tools/lune/check_registration_cli` |
| Theming | **Absent** | **Ships.** Theme packages owning typography, spacing, control heights, radii, strokes, solver-visible insets and asset chrome; installed or swapped in one transaction; dark/light on native StyleSheets with no remount | `src/themes/`, `src/client/theme_controller.luau` |
| Focus, keyboard traversal, gamepad navigation | **Absent** (bindings make `NextSelection*` wiring tractable, which is a different thing) | **Ships.** `newFocusGraph` with grouped scopes, per-group axis/wrap/entry/exit, directional navigation and Tab traversal in document order | `src/focus/focus_graph.luau` |
| Modal / toast / popover presentation | **Absent** | **Ships.** `presenter` with focus traps, priority bands, four named display-order layers, typed toast dismiss reasons and a cross-surface overlap alarm | `src/present/presenter.luau`, `src/render/surface_overlap.luau` |
| Motion system | **Composable** via Bindings — you write the springs | **Ships.** Named spring classes (inline literals refused), retarget-preserving velocity, `withAnimation` over the solver's whole output, structural transitions, and an information-preserving Reduce Motion policy | `src/motion/` |
| Dynamic Type / preferred text size | **Absent** | **Ships.** The player's Roblox text-size preference is first-class layout input, using measured per-preference pixel offsets | `src/env/environment.luau` |
| Live tree inspector | **Ships.** React DevTools, in the monorepo ([RL-34]) | **Absent.** Deterministic `dump()`, `controller.diagnostics()`, `theme_controller.inspect()` and scripted Studio drives — all batch. §5 rank 4 | [RL-34]; `src/render/renderer.luau` |
| Hot reload | **Ships.** `react-refresh` ([RL-34]) | **Absent** | [RL-34] |
| Package distribution | **Ships.** Wally `roblox/react@17.3.11`; Creator Store package published by Roblox ([RL-25], [RL-26]) | **Absent.** Version 0.9.0, private repository, no published artifact | [RL-25], [RL-26]; `src/init.luau` |
| Screen-reader / assistive technology | **Absent** | **Absent** | — |
| Right-to-left / bidirectional | **N/A** — layout is the engine's, which does not mirror either | **Absent** | — |
| Physical-device verification | **Not published** — no benchmarks are reachable ([RL-38]) | **Absent.** Every claim is headless (E1) or Studio emulator (E3); no E4 evidence exists | [RL-38]; `artifacts/phase-4/perf.json` |

---

## 5. Ranked gap analysis — what to take from React before first release

The director's question: *are there features in React we should implement before
our first release?* This section answers it. **Nothing here was implemented when this
list was written. Ranks 1 and 2 were both built on 2026-08-15 — `UI.Foreign`
(ADR-0034) and the `UI.When` branch scope — and are marked BUILT below; the rest
stand as written.**

The ranking is by **what a real game author would miss**, not by effort and not
by architectural interest. Each row gives what it is, what it would cost, whether
Facet already answers it differently, and one of three recommendations:

- **BUILD NOW** — a first release without it is materially worse.
- **DEFER** — real, but the trigger that should lift it is named.
- **DECLINE** — with the reason, so it is not rediscovered.

One candidate is deliberately not on this list because it is not §5's:
**distribution** (Wally/Creator Store — [`distribution-readiness.md`](../plans/distribution-readiness.md)
owns it).

**Where this list meets the Fusion document's.** [`fusion-comparison.md`](fusion-comparison.md)
§5 was written in parallel against the same framework, and three items touch.
They are named here so a reader dispatching from both lists is not reconciling
them by hand:

| This list | Fusion §5 | Are they the same thing? |
|---|---|---|
| **Rank 1**, a foreign **GuiObject** inside a Facet layout | **G-7**, driving arbitrary Roblox instances (`New "Part"` — a `Part`, a `Beam`, a `Sound`) | **No.** G-7 is the 3D/world-instance question and it is already decided by [`ADR-0024`](../adr/ADR-0024-declarative-3d.md) — a sibling scene system on the shared kernel, build waiting for a consumer. Rank 1 is the *2-D* question: a GuiObject class the solver must lay out. ADR-0024 does not cover it |
| **Rank 1** (again) | **G-2**, an instance escape hatch (`Ref`/`Out`) — **DEFER** | **Adjacent, and the distinction is the whole design.** G-2 is *handing out the `GuiObject` Facet created*, and its argument for deferring is exactly right: a writable handle to a framework-owned instance is the second-writer hole §2.5 exists to close. Rank 1 hands out **nothing Facet owns** — it is a container the *caller* creates the instance inside, so the framework claims one authority (the container's rect) and disclaims the rest by construction. Rank 1 does not weaken G-2's refusal and should not be read as overturning it |
| **Rank 6**, subtree-scoped environment overrides | **G-4**, consumer-defined environment values (`Contextual`) — **DEFER** | **Two halves of one hole.** G-4 is *new keys a consumer defines*; Rank 6 is *existing framework keys overridden for a subtree*. Either build should look at both before choosing a shape |

One disagreement is worth stating plainly rather than smoothing over: this
document ranks the escape hatch **BUILD NOW** and the Fusion document ranks its
nearest neighbour **DEFER**. The reason for the difference is the scope above —
G-2 defers handing out a framework-owned instance, which this list also does not
propose. Nothing here asks for `Ref`.

---

### Rank 1 — A bounded escape hatch to a foreign Roblox Instance · ~~BUILD NOW~~ — **BUILT 2026-08-15**, ADR-0034

**What it is.** React-Lua's entire element model is
`createElement("<AnyRobloxClassName>", props)` → `Instance.new(type_)` ([RL-15]),
so every Roblox class ever shipped is reachable. Facet has 26 classes and a
seven-entry class map; anything else becomes a `Frame`. There is no way to put a
`VideoFrame`, an `EditableImage` surface, a vendored widget, or a class Roblox
ships next month inside a Facet layout.

**Why it ranks first.** Every other row on this list makes Facet worse to use.
This one makes it *unusable* for a specific project, discovered late, with no
workaround — and it is the first thing an evaluating developer tests. A framework
with no escape hatch is a bet that its 26 classes cover everything; that bet
cannot be won.

**What Facet already answers differently, and why it is not enough.** `UI.Stage`
already proves the pattern exists: the solver treats it as an ordinary content
leaf, the framework owns the box and the lifecycle, and `controller.stageHost(path)`
hands the caller a content root to parent into, with an engine-type-free boundary
(`{x,y,z}` tables rather than `CFrame`). That is precisely the shape needed —
**it just opens onto a `ViewportFrame`'s 3D scene rather than onto a GuiObject.**

**The cost, honestly.** The naive version — `UI.Native{ class = "VideoFrame",
props = {…} }` — costs the three things that make Facet what it is, and should
be refused: it reopens the closed key set (the schema cannot validate props it
has never heard of), it defeats property authority (the manifest has no entry for
a class it does not know), and it breaks the elision and hosting invariants and
the measure model (an `AutomaticSize` child measures itself, which the solver
cannot see).

The bounded version costs much less and keeps all three. A leaf class — call it
`UI.Foreign` — that:
- takes **no engine props at all**, only the shared box vocabulary the solver
  already owns, so the closed key set is intact;
- is a **content leaf** to the solver with a declared size, exactly like `UI.Stage`;
- is **never elidable** and always a real instance parent, unconditionally
  rather than by the registration rule every other class follows
  ([ADR-0032](../adr/ADR-0032-nested-instance-tree.md)), because the caller's
  foreign content has to land somewhere real whether or not it would otherwise
  have earned a host;
- hands the caller a container through a `controller` seam, so the *caller* owns
  the foreign instance's properties and lifetime and property authority is not
  claimed at all — the framework declares one authority (`layout`, for the
  container's rect) and disclaims the rest by construction. The `host` authority
  name had been sitting reserved and unused in `src/render/authority.luau` for
  exactly this seam.

That is one blueprint class, one render-target optional method (with a named
degrade), and one solver content-leaf branch. `UI.Stage` is the working
precedent for every part of it.

**What this is not.** It is not
[`ADR-0024`](../adr/ADR-0024-declarative-3d.md)'s question — that record decided
the *3-D/world-instance* case (a `Part`, a `Beam`, a `Sound`) in favour of a
sibling scene system on the shared kernel, with the build waiting for a consumer.
This is the 2-D case: a `GuiObject` class the solver has to lay out. And it is not
`fusion-comparison.md` §5's `Ref` — nothing here hands out an instance Facet
created, which is why the authority argument that defers `Ref` does not defer
this. See §5's preamble table.

**Recommendation: BUILD NOW.** — **DONE, 2026-08-15 (ADR-0034, `UI.Foreign`).**
Bounded form only. The refusal of the unbounded
form should ship with it, as a construction error naming the reason — the same
way `opacity` on a leaf is refused with an argument rather than a shrug. Both
shipped: the unbounded form is refused by name, and the seam INVERTED on the way
in — `controller.foreignHost(path)` takes the caller's instance rather than
handing a Facet-owned one out, which is why `Ref` stays deferred.

---

### Rank 2 — A branch scope for `UI.When` · ~~BUILD NOW~~ — **BUILT 2026-08-15**

**What it is.** In React, a conditionally-rendered component owns state that
appears and disappears with it: `useState` inside it, done. In Facet, a
`ForEach` row gets this — `row(item, itemScope)` — but `When.thenView` is
`() -> Blueprint` with no second argument, even though `src/mount.luau` creates
a `branchScope` for exactly that lifetime one line before calling the factory.

**Why it ranks second.** "A panel that opens, owns a signal and an async handle,
and closes" is the single most common stateful UI shape there is. Today the
author must hoist that state into an outer scope, where it outlives the panel and
must be reset by hand — which is a leak the framework's own counters would flag
in a test but nothing flags in a game.

**Cost.** One added parameter at the call site, one schema doc string, one test.
The scope already exists and is already disposed correctly on branch exit and on
re-entry mid-transition. This is the cheapest item on the list by a wide margin.

**Recommendation: BUILD NOW.** — **DONE, 2026-08-15.** It is an asymmetry, not a
design decision — the sibling structural region already does it. `thenView` is
handed the branch scope; there is deliberately no `elseView` to hand a second one
to (`src/mount.luau`, and `api.md`'s `UI.When` section carry the refusal).

---

### Rank 3 — Mounting a Facet surface into a caller-supplied container · **DEFER**

**What it is.** Every Facet surface creates its own `ScreenGui` under
`PlayerGui`. A studio with an existing UI cannot put a Facet subtree inside an
existing `Frame` and adopt the framework one screen at a time. React-Lua's story
is the inverse and it is *documented as a hazard*: a root "take[s] complete
control of the provided container, deleting all existing children" ([RL-21]), so
you mount into a `Folder` and portal out ([RL-22]).

**What Facet already answers differently.** Coexistence is already better:
Facet never touches GUI it did not create, and `screen_target.new({ parent })`
already accepts a parent override (used today for the Studio Edit preview). What
is missing is the finer grain — a surface rooted at an arbitrary `GuiObject`
rather than at `PlayerGui`.

**Cost.** Moderate and mostly unknown. The surface's root rect currently comes
from the viewport; rooting inside a foreign `Frame` means the root's box is
somebody else's `AbsoluteSize`, which must be observed and fed to the solver —
and the framework has no seam that reads an engine size as a layout input.
Safe-area insets, `platformChrome` and the edge-to-edge root policy all assume a
window-space root.

**Recommendation: DEFER.** The trigger: **the first external adopter, or the
first Rascal Rally screen, that must live inside an existing GUI hierarchy.**
Until there is one, this is speculative work against an unmeasured seam. Note it
becomes cheap if Rank 1 ships, because a foreign container and a foreign-parented
root are the same "engine size is a layout input" problem.

---

### Rank 4 — A live tree inspector · **DEFER**

**What it is.** React DevTools ships in React-Lua's monorepo ([RL-34]): a live
tree with props, state and a highlighter. Facet has deterministic `dump()`,
`controller.diagnostics()`, `theme_controller.inspect()`, five reference apps and
a scripted Studio driver — all excellent, all **batch**.

**Why it matters more than it looks.** Facet's whole selling point in §2.4 is
that mistakes are refused early with a message that names the fix. That covers
*authoring* mistakes. It does not cover "the layout is not what I expected and I
cannot see why", which is the daily experience of building UI, and which the
still-mostly-flat instance tree makes *harder* than in React-Lua — outside a
`ScrollView`, a clip host, a fade group, or an authored `scale`/`rotation`
container ([ADR-0032](../adr/ADR-0032-nested-instance-tree.md)), the Roblox
Explorer shows you a flat pile of Frames with no structure to read.

**What Facet already answers differently.** `controller.diagnostics()` is
genuinely strong and the project has a recorded case of it naming a shipped
layout defect a screenshot review had missed
([`the-solver-already-told-you`](../lessons/the-solver-already-told-you.md)). The
gap is that you must know to call it.

**Cost.** A real Studio plugin is a mission. A much cheaper first rung exists: a
scenario-driven overlay or a `controller.explain(path)` that prints one node's
solved rect, its offer, its floors, its authority writes and its diagnostics —
which is assembling data the framework already has.

**Recommendation: DEFER**, and pick up the cheap rung opportunistically. The
trigger: **first release with external users**, where "I cannot see my tree" is
an onboarding cost paid by people who cannot read the source.

---

### Rank 5 — Hot reload / an interactive authoring loop · **DEFER**

**What it is.** `react-refresh` ships in React-Lua's monorepo ([RL-34]).
the comparison ledger already scores the equivalent preview macro as Missing.

**Cost.** Large and mostly outside the framework: it needs a Studio-side host
that can tear down and rebuild a surface while preserving state, which is a
plugin and a protocol as much as a framework feature.

**Recommendation: DEFER.** The trigger is the same as Rank 4's and it should
follow it — an inspector is the prerequisite for a preview loop worth having, and
they share the Studio-side host.

---

### Rank 6 — Subtree-scoped environment overrides · **DEFER**

**What it is.** React's `createContext` + Provider lets a subtree see a different
value for something an ancestor provides. Facet's `Env` is one object per
application, shared by every surface.

**Why it is lower than it looks.** For *author* data, the honest answer is that
React needs Context because components are opaque function boundaries, and
Facet does not, because **a blueprint is built by ordinary Luau code and lexical
scope already is the context mechanism.** Passing a value down three levels is
three parameters in a function you wrote — not a prop-drilling problem through
framework-owned components.

**Where it is a real gap** is narrower and specific: environment facts the
*framework itself* reads. `sizeClass`, `typographyScale` and `effectiveTransparency`
are global, so a modal cannot render as though it were on a compact screen while
the screen behind it is regular, and a dense panel cannot locally opt out of a
typography scale. Two controls (`popup_button`, `picker`) already take a size
class as a **spec parameter** rather than reading the key, which is the
workaround, done by hand, twice.

**Cost.** Moderate and it is not the plumbing — it is the semantics. Every
derived memo in `src/env/environment.luau` is built once over the fact signals;
per-subtree overrides mean per-subtree memos, and the mounted tree would need an
override chain resolved the way the `sensoryFeedback` activation verb already is.
That cascade exists and works, but it carries one static string; carrying live
`Readable`s through it is a different thing.

**Recommendation: DEFER.** The trigger: **the third control that has to take an
environment fact as a spec parameter.** Two have; a third means the workaround is
the pattern and the pattern should be the mechanism. Whoever picks this up should
read [`fusion-comparison.md`](fusion-comparison.md) §5 G-4 first — that is the
other half of the same hole (consumer-*defined* keys, where this is consumer-
*overridden* ones), and one shape should answer both.

---

### Rank 7 — Interruptible / time-sliced rendering · **DECLINE**

**What it is.** React-Lua's headline capability: spread a large render across
frames instead of dropping one ([RL-14], [RL-33]).

**Why decline.** It is incompatible with the contract Facet is built on. §2.8
sets it out: `settle` requires terminal work to converge *inside* the flush so
that a top-level write returns with all consequences applied, and the renderer,
the presenter and effectively every test depend on that. Slicing would make
`env:set` return before the surface is solved. This is not a feature that could
be added; it is a different framework.

**What Facet answers instead**, and it is a real answer: reduce the work rather
than spread it — virtualization on lists, tables and grids; incremental layout
(~17× fewer arranged nodes for a one-value change); inert-container elision
(−34 % instances); instance recycling.

**The honest residue, and it should be written down rather than argued away:**
those numbers are **headless**. Nobody has measured what a large Facet mount
costs on a real phone, and React-Lua's slicing is a structurally better answer to
exactly that risk. If a device capture ever shows a mount blowing a frame budget
that virtualization cannot fix, this row is wrong and should be revisited on that
evidence. The device capture is already owed
(`bench/perf_budgets.json` `skippedDeviceBudgets`).

---

### Rank 8 — `React.memo` / render bail-out · **DECLINE**

Meaningless here: there is no render to skip. A prop change writes into the
mounted node and nothing above it is visited. Recorded so it is not re-proposed.

---

### Rank 9 — Suspense, `lazy`, and async component loading · **DECLINE**

React-Lua ships both and its own documentation says Suspense "should be
considered unusable" ([RL-06]) and that `lazy` addresses a problem that "is
rarely a concern in the context of Luau projects" ([RL-36]). Facet's async story
— `newResourceProvider` with scope-owned handles, generation-counter
stale-completion rejection and bounded retry — covers the case that actually
occurs (an image or a request arriving late).

---

### Rank 10 — Hooks as an ergonomic layer over scopes · **DECLINE**

**What it is.** A `withState`-style helper that hides scope creation, so a
consumer writes less ceremony.

**Why decline.** Hooks work because React owns a call stack and can key state by
call order within a component instance. Facet has no component instance and no
render call to be inside, so any hook-shaped API here would be a lookalike with
different rules — which is the parity-claim-the-code-does-not-honour defect the
API constitution rates as severe. The ceremony is real; the answer to it is Rank
2 (give `When` its scope), not a borrowed vocabulary.

---

### Rank 11 — Class components, `propTypes`, `defaultProps` · **DECLINE**

`propTypes` and `defaultProps` do not work on React-Lua function components
anyway ([RL-10]), and Facet's construction-time closed key sets with required
fields, typed `*Spec` exports and did-you-mean errors are a strictly stronger
answer at authoring time.

---

### Rank 12 — Bindings as a distinct concept · **DECLINE**

React-Lua invented Bindings to bypass reconciliation for values that change every
frame ([RL-02], [RL-12]). Facet's `Signal`/`Memo` *is* that channel, for every
value, with no second concept and no `getValue`-is-stale-inside-render caveat
([RL-41]). Nothing to take.

---

### Summary table

| # | Candidate | Recommendation | Trigger, if deferred |
|---|---|---|---|
| 1 | Bounded foreign-Instance escape hatch (`UI.Foreign`) | ~~BUILD NOW~~ — **BUILT 2026-08-15**, ADR-0034 | — |
| 2 | Branch scope for `UI.When` | ~~BUILD NOW~~ — **BUILT 2026-08-15** | — |
| 3 | Surface rooted in a caller-supplied container | DEFER | First adopter or Rascal Rally screen that must live inside existing GUI |
| 4 | Live tree inspector | DEFER | First release with external users |
| 5 | Hot reload / interactive preview | DEFER | Follows #4; shares the Studio-side host |
| 6 | Subtree-scoped environment overrides | DEFER | The third control forced to take an env fact as a spec parameter |
| 7 | Interruptible / time-sliced rendering | DECLINE | Revisit only on a device capture showing a mount blowing frame budget |
| 8 | `React.memo` / render bail-out | DECLINE | — |
| 9 | Suspense / `lazy` | DECLINE | — |
| 10 | Hooks over scopes | DECLINE | — |
| 11 | Class components / `propTypes` / `defaultProps` | DECLINE | — |
| 12 | Bindings as a distinct concept | DECLINE | — |

---

## 6. Verification appendix

| | |
|---|---|
| Facet version | `0.9.0` (`src/init.luau`) |
| React-Lua baseline | `Roblox/react-luau` at `main`, commit stream read 2026-08-15; latest commit `2026-07-30`; Wally `roblox/react@17.3.11`; alignment React JS **17.0.1** ([RL-03], [RL-24], [RL-25]) |
| Audit date | 2026-08-15 |
| Facet method | **Source only.** `src/core/contract.luau`, `src/core/fusion_adapter.luau`, `src/core/custom.luau`, `src/core/scope_impl.luau`, `src/render/authority.luau`, `src/render/renderer.luau`, `src/render/target_contract.luau`, `src/render/presentation.luau`, `src/client/screen_target.luau`, `src/client/screen_presentation.luau`, `src/mount.luau`, `src/blueprint.luau`, `src/blueprint_schema.luau`, `src/env/environment.luau`, `src/init.luau`, `src/spec_guard.luau`, `src/controls/`, `src/layout/`, `src/present/`, plus `tests/conformance/` and `artifacts/conformance-*.json`. **No claim below was taken from Facet's own documentation** — the last two rewrites of the sibling parity document found nine and then several more stale or false claims sourced that way, including a citation to a source comment that existed nowhere in the file or its history |
| React-Lua method | Raw source and docs fetched from `raw.githubusercontent.com` (not the rendered docs site, which does not resolve — [RL-27]), plus the GitHub, Wally and Roblox toolbox APIs. Every quote in §7 was read from the payload named there on the date given |

**Suite state at the time of writing.** `./run-tests.sh` → **5438 passed, 0
failed**. This document changes no code and adds no spec, so it moves neither
number; the count is above the brief's 5395 baseline because four other agents
were landing work in this tree while it was written. (An earlier run during
drafting showed 4 failures — `text.lineBox`/`text.facts` undocumented, and two
`expected 2 to be 0` four-input/paradigm proofs — all of them those agents'
in-flight state, and all green by the time this was committed.)

The five checkers were run live for this revision:

```bash
lune run tools/lune/check_docs_cli          # PASS — 9 documents, 81 surface anchors,
                                            #   137 comparison citations, 64 local links
lune run tools/lune/check_registration_cli  # PASS — 25 controls, 91 exports documented,
                                            #   203 specs registered, 16/16 four-input + paradigm
lune run tools/lune/check_prop_parity_cli   # PASS — 26 classes, 643 properties, 680 typed fields
lune run tools/lune/check_surface_ledger    # PASS
lune run tools/lune/check_boundary          # PASS — 122 src files, 398 consumer files
```

This document is **not** among the nine `check_docs` reads, so no citation here is
mechanically checked. That is the same limitation `the comparison document` §15 records
about its own prose, one level worse: there, table rows are enforced to carry a
cited URL, quote and date. Here the §7 convention is followed by hand.

**What this document could NOT verify, recorded rather than assumed.**

- **React-Lua's actual runtime behaviour.** Everything on that side is read from
  its source and documentation. Nothing was executed. Where source and docs
  disagree — `useDebugValue` ([RL-07] vs [RL-37]) — both are cited and the
  disagreement is the finding.
- **The live value of `ReactFixBindingMemoryLeak`.** The source declares a default
  of `false` ([RL-29]). Roblox FastFlags are set by the platform at runtime, so
  the shipped value is not knowable from source. What is verified is that the code
  declares `false` and that the unflagged branch drops the binding table without
  calling its disconnect functions.
- **Any React-Lua performance number.** None is published in a reachable place
  ([RL-38]).
- **Whether Roblox recommends React-Lua.** Roblox's own UI documentation does not
  mention it, or Roact, or any third-party framework ([RL-30]), and the Creator
  Store asset is `isEndorsed: false` ([RL-26]). No Creator Hub page recommending
  it was found, and its absence is not proof of one not existing.
- **Any React-Lua roadmap.** No statement about a React 18 port, or about
  deprecation, was found on any first-party source.
- **Anything on physical hardware, on either side.**
- **Facet's own performance figures were not re-run for this document.** The
  `55 of 137` inert-container measurement is quoted verbatim from the source
  comment in `src/client/screen_target.luau`; the `~17×` incremental-layout and
  `−34 %` elision figures are the numbers
  [`the comparison document`](the comparison document) §10 records, carried over rather than
  re-measured. All are headless (evidence level E1) and none is a device claim.

**On line numbers.** Evidence cells name files, not line numbers, for the reason
the sibling document gives: line references rot faster than anything else in a
document that is re-read months later, and a stale pointer is worse than none
because it looks precise. React-Lua citations name a file path in the repository
at `main`, which moves — hence the dates.

---

## 7. Citations — what React-Lua's own sources actually say

Every `[RL-nn]` used above resolves here: the URL a reader should open, the
sentence the claim rests on quoted verbatim from that source, and the date it was
read. Two conventions:

- **The repository is the source of truth, not the docs site.** `react-luau.dev`
  does not resolve ([RL-27]), so every documentation citation names the raw file
  in the repository. The same content renders at
  `https://roblox.github.io/roact-alignment/`, which is generated from an older
  project path and may lag.
- **Where source and documentation disagree, both are cited**, and the row that
  uses them says which is which.

| Id | Source | The sentence the claim rests on | Read |
|---|---|---|---|
| **RL-01** | [`README.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/README.md) | "A comprehensive, but not exhaustive, translation of ReactJS 17.x into Luau." … "It's a highly-tuned translation of ReactJS and currently based on React 17." The example sets `AnchorPoint`, `Position`, `AutomaticSize` as plain props on `e("TextLabel", {…})` | 2026-08-15 |
| **RL-02** | [`README.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/README.md) | "React Luau introduces Bindings, a form of signals-based state that doesn't re-render, for highly-efficient animations driven by React." | 2026-08-15 |
| **RL-03** | [`docs/index.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/index.md) | "This documentation refers to the initial release of this version of Roact as **Roact 17** (because it aligns its implementation to React JS version 17.0.1) or **Roact 17+** (to include future releases)." … "This documentation site serves as a comprehensive guide to the _differences_ between Roact and React." | 2026-08-15 |
| **RL-04** | [`docs/deviations.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/deviations.md) | "The Luau ecosystem does not yet have the tooling to support JSX. Instead, use `React.createElement` as your primary tool for building UIs with Roact 17." | 2026-08-15 |
| **RL-05** | [`docs/deviations.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/deviations.md) | "Error boundaries are not yet fully supported due to a limitation in Luau around recursive `pcall` depth. Future updates to React will unravel the recursive traversal and enable these features." | 2026-08-15 |
| **RL-06** | [`docs/api-reference/react.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react.md) | "**While `React.Suspense` is technically implemented, it should be considered unusable as of version `17.0.1`.** This is due to a limitation in Luau around recursive `pcall` depth." | 2026-08-15 |
| **RL-07** | [`docs/api-reference/react.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react.md) | "The following API members are notable absences relative to React JS 17.0.1: * `React.createFactory` - Considered legacy and will likely not be included * `React.useDebugValue` - Not yet implemented" | 2026-08-15 |
| **RL-08** | [`modules/react/src/React.lua`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/react/src/React.lua) | The export table carries, verbatim: `-- Concurrent Mode` / `-- ROBLOX TODO: useTransition,` / `-- ROBLOX TODO: startTransition,` / `-- ROBLOX TODO: useDeferredValue,` / `-- ROBLOX TODO: REACT_SUSPENSE_LIST_TYPE as SuspenseList,`. `useSyncExternalStore` and `useId` do not appear — correctly, as both are React 18 APIs. No layout API of any kind appears | 2026-08-15 |
| **RL-09** | [`docs/deviations.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/deviations.md) | "Since order has no inherent meaning in Roblox's DOM, legacy Roact generally expected children to be provided as a _map_ instead of an array… Roact 17+ supports _both_ methods for providing keys. Both of the following examples are valid and equivalent." | 2026-08-15 |
| **RL-10** | [`docs/deviations.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/deviations.md) | "For the time being, function components do not support the `defaultProps` feature." … "For the time being, function components do not support the `propTypes` feature." … "With the introduction of Hooks, function components are the preferred style of component definition." | 2026-08-15 |
| **RL-11** | [`docs/deviations.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/deviations.md) | "If a dependency array changes in length, **a re-render will always be triggered**… If a dependency array changes in length, we assume the developer provided an array ending with one or more nil-able values, and we **suppress the warning**". Cause: `print(#{"A", "B", nil} == #{ "A", "B" }) -- prints: true` | 2026-08-15 |
| **RL-12** | [`docs/deviations.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/deviations.md) | "Roact introduces a bindings feature that provides a unidirectional data binding that can be updated outside of the render cycle (much like refs could)." … "Roact supports callback refs, refs created using `React.createRef`, and refs using the `React.useRef` hook. However, under the hood, Refs are built on top of a concept called Bindings." | 2026-08-15 |
| **RL-13** | [`docs/api-reference/react-roblox.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react-roblox.md) | "The ReactRoblox package is the entry point for any Roblox-opinionated logic. It can be thought of as the equivalent of the ReactDOM package in React JS." … "## ReactRoblox.createPortal / Refer to [`ReactDOM.createPortal` documentation]" | 2026-08-15 |
| **RL-14** | [`docs/migrating-from-1x/adopt-new-features.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/migrating-from-1x/adopt-new-features.md) | "Roact 17 introduces a paradigm shift to the underlying rendering behavior that allows it to divide work across multiple frames and preserve high framerate and interactivity." … "**Roact 17 will use Concurrent Mode by default in its `mount` compatibility layer.**" … "In new code, you should always use `ReactRoblox.createRoot`" | 2026-08-15 |
| **RL-15** | [`modules/react-roblox/src/client/ReactRobloxHostConfig.lua`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/react-roblox/src/client/ReactRobloxHostConfig.lua) | `exports.createInstance = function(type_: string, props: Props, …)` … `local domElement = Instance.new(type_)` … `-- ROBLOX deviation: compatibility with old Roact where instances have their name set to the key value` / `if internalInstanceHandle.key then domElement.Name = internalInstanceHandle.key` | 2026-08-15 |
| **RL-16** | [`modules/react-roblox/src/client/roblox/RobloxComponentProps.lua`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/react-roblox/src/client/roblox/RobloxComponentProps.lua) | `local function setRobloxInstanceProperty(hostInstance, key, newValue): ()` … `-- Assign the new value to the object` / `hostInstance[key] = newValue`, with the `nil` branch calling `pcall(hostInstance.ResetPropertyToDefault, hostInstance, key)` | 2026-08-15 |
| **RL-17** | [`docs/api-reference/react.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react.md) | "A special key that can be used to interact with events on Roblox Instance objects." … "The event connection will be automatically created when the host element is mounted and automatically disconnected when the element is unmounted." … "Event callbacks receive the Roblox Instance as the first parameter, followed by any parameters yielded by the event." | 2026-08-15 |
| **RL-18** | [`docs/api-reference/react.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react.md) | "A special key that can be used to apply `CollectionService` tags to a host component." … "Multiple tags can be provided as a single space-delimited string." | 2026-08-15 |
| **RL-19** | [`docs/configuration.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/configuration.md) | "Since Roact 17 uses concurrent rendering by default, you will always need this global to be set to `true`" (of `__ROACT_17_MOCK_SCHEDULER__`). Of `__DEV__`: "**Dev Mode is _not_ meant to be enabled on production.** While it exposes a great deal of useful information and introduces extra assurances, it pays a hefty performance cost to do so." | 2026-08-15 |
| **RL-20** | [`docs/api-reference/react-roblox.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react-roblox.md) | "In production, `ReactRoblox.act` will not be available. Set the global value `_G.__ROACT_17_INLINE_ACT__` to `true` in order to enable this behavior in tests." | 2026-08-15 |
| **RL-21** | [`docs/api-reference/roact-compat.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/roact-compat.md) | "React's roots take complete control of the provided container, deleting all existing children. Legacy Roact does not tamper with existing children of the provided container. To mimic the legacy behavior, we use a `Portal` to mount into the container instead of providing it directly to the root." | 2026-08-15 |
| **RL-22** | [`docs/migrating-from-1x/convert-legacy-conventions.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/migrating-from-1x/convert-legacy-conventions.md) | `-- Roact 17 roots will take full ownership of the instance provided to them,` / `-- so we should not create a root using PlayerGui directly` / `local container = Instance.new("Folder")`. Also: "while RoactCompat is backwards compatible with with Legacy Roact, **it does not export new Roact 17 features like hooks.**" | 2026-08-15 |
| **RL-23** | [DevForum, *How To: React + Roblox*](https://devforum.roblox.com/t/how-to-react-roblox/2964543) (topic JSON) | "React-lua is maintained by Roblox. Currently most studio plugins and the Roblox Universal App (the desktop console and mobile app where you browse for your favorite Roblox games) are all written in react-lua." Posted by `minimapletinytools`, `created_at` `2024-05-10T15:30:40.778Z`, in category 278, whose own description is "This category contains articles authored by Roblox staff." The same post also says "JS.Lua hosts the community maintained fork of react-lua and is also the source from which the React Wally packages are built from" — which is **historical**: `roblox/react`'s own `wally.toml` now ships in the Roblox repository ([RL-25]) | 2026-08-15 |
| **RL-24** | [GitHub API `repos/Roblox/react-luau`](https://api.github.com/repos/Roblox/react-luau) | `"description": "A comprehensive, but not exhaustive, translation of ReactJS 17.x into Luau. This is a read-only mirror."`, `"archived": false`, `"pushed_at": "2026-07-31T00:26:54Z"`, `"license": {"spdx_id": "MIT"}`, `"homepage": "https://react-luau.dev"`. `api.github.com/repos/Roblox/react-lua` returns `{"message": "Moved Permanently"}` to this repository. Recent commits are packaging work: "Fix package versions across registries (#507)", "Remove Wally from internal dependencies (#506)", "Onboarding to New Mirroring Flow (#501)" | 2026-08-15 |
| **RL-25** | [`modules/react/wally.toml`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/react/wally.toml) and [Wally API](https://api.wally.run/v1/package-metadata/roblox/react) | `name = "roblox/react"` / `description = "A translation of React 17 into Luau, tuned for Roblox."` / `authors = ["Roblox <no-reply@roblox.com>"]`. Wally's latest published version is `17.3.11` | 2026-08-15 |
| **RL-26** | [Roblox toolbox API, asset 15621638430](https://apis.roblox.com/toolbox-service/v1/items/details?assetIds=15621638430) | `"name": "ReactLua"`, `"assetSubTypes": ["Package"]`, `"isEndorsed": false`, `"updatedUtc": "2026-07-30T22:52:49.47Z"`, `"creator": {"id": 1, "name": "Roblox", "type": 1, "isVerifiedCreator": true}` | 2026-08-15 |
| **RL-27** | DNS, `react-luau.dev` | `dig +short @8.8.8.8 react-luau.dev A` and `@1.1.1.1` both return **empty**; `dig NS` returns `nspx1.roblox.com.`, `nspx2.roblox.net.`, `nspx3.roblox.us.`, `nspx4.roblox.co.uk.`. The domain is Roblox's and has no A record, so the site the README links four times does not resolve. `https://roblox.github.io/roact-alignment/` returns `200` | 2026-08-15 |
| **RL-28** | [`docs/api-reference/react.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react.md) | "In React JS, `useLayoutEffect` is most often used to measure and position elements before the browser repaints them. **It's not yet clear how this use case translates to roblox usage**, and this hook should be used with caution until performance is investigated in detail and best practices emerge." | 2026-08-15 |
| **RL-29** | [`modules/react-roblox/src/client/roblox/RobloxComponentProps.lua`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/react-roblox/src/client/roblox/RobloxComponentProps.lua) | `local _, FFlagReactFixBindingMemoryLeak = xpcall(function() return game:DefineFastFlag("ReactFixBindingMemoryLeak", false)`. The guarded branch is `if FFlagReactFixBindingMemoryLeak then cleanupBindings(domElement) else if instanceToBindings[domElement] ~= nil then instanceToBindings[domElement] = nil end end` — the `else` path drops the table without calling the stored `disconnectBinding()` functions that `cleanupBindings` iterates | 2026-08-15 |
| **RL-30** | [Roblox Creator Hub, *User Interface*](https://create.roblox.com/docs/ui) | "You can quickly create high-quality graphical user interfaces with minimal scripting requirements using built-in UI objects." … "Universal styling is a Roblox solution to stylesheets, similar to CSS, that lets you declare and globally apply overrides to UI instance properties." … "Beyond basic properties for adjusting position and size, Roblox also provides layout structures like list/flex and grid, as well as size modifiers and appearance modifiers." **The page does not mention React, React-Lua, Roact, or any third-party UI framework.** Headings: On-screen UI, In-game UI, UI objects, Layout and design, Universal styling, Interactive frameworks, Proximity prompts, UI drag detectors, 3D drag detectors | 2026-08-15 |
| **RL-31** | GitHub code search, `repo:Roblox/react-luau` | `StyleSheet` → `total_count: 0`. `StyleRule` → `0`. `GetStyled` → `0`. `UIListLayout` → `1`, and the single hit is `modules/react-devtools-shared/src/backend/views/Highlighter/Overlay/OverlayTip.lua` — the DevTools overlay's own UI, not the renderer. (Control query `createRoot` → `43`, so the index does cover this repository) | 2026-08-15 |
| **RL-32** | [`docs/deviations.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/deviations.md) | "`React.useState` returns two values rather than an array containing two values." … "it _does_ support multiple return values, so we can support a very similar usage: `local value, setValue = React.useState(0)`" | 2026-08-15 |
| **RL-33** | [`modules/scheduler/src/forks/SchedulerHostConfig.default.lua`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/scheduler/src/forks/SchedulerHostConfig.default.lua) | `-- ROBLOX deviation: This module in React exports a different implementation if it detects certain APIs from the DOM interface. We instead attempt to approximate that behavior so that we can access features like dividing work according to frame time`. Flags: `SafeFlags.createGetFInt("ReactSchedulerYieldInterval2", 15)`, `ReactSchedulerDesiredFrameRate` default `60`, `ReactSchedulerMinFrameRate` default `30`. `local function shouldYieldToHost() return getCurrentTime() >= deadline end`; `heartbeatConection = game:GetService("RunService").Heartbeat` | 2026-08-15 |
| **RL-34** | [GitHub API `repos/Roblox/react-luau/contents/modules`](https://api.github.com/repos/Roblox/react-luau/contents/modules) | The complete `modules/` listing: `TestRunner`, `example-app`, `jest-react`, `react-cache`, `react-debug-tools`, `react-devtools-core`, `react-devtools-extensions`, `react-devtools-shared`, `react-devtools-timeline`, `react-devtools`, `react-globals`, `react-is`, `react-noop-renderer`, `react-reconciler`, `react-refresh`, `react-roblox`, `react-shallow-renderer`, `react-telemetry`, `react-test-renderer`, `react`, `roact-compat`, `scheduler`, `shared`. **There is no layout package** | 2026-08-15 |
| **RL-35** | [GitHub API `repos/Roblox/react-luau/releases`](https://api.github.com/repos/Roblox/react-luau/releases) | Exactly one release: `"tag_name": "v17.0.1"`, `"published_at": "2024-01-18T20:57:56Z"`. Tags go further (`v17.1.3`, `v17.1.2`, `v17.1.0`, `v17.0.7`, …) | 2026-08-15 |
| **RL-36** | [`docs/api-reference/react.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react.md) | "Though `React.lazy`'s functionality is implemented, it may not be especially useful without complete support for `React.Suspense`." … "The `lazy` utility is designed an ecosystem where loading modules can be expensive. **This is rarely a concern in the context of Luau projects.**" | 2026-08-15 |
| **RL-37** | [`modules/react/src/React.lua`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/react/src/React.lua) and [`modules/react/src/ReactHooks.lua`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/react/src/ReactHooks.lua) | `React.lua` exports `useDebugValue = ReactHooks.useDebugValue,`; `ReactHooks.lua` implements `local function useDebugValue<T>(value: T, formatterFn: ((value: T) -> any)?): () if ReactGlobals.__DEV__ then … end return nil end` / `exports.useDebugValue = useDebugValue`. It is implemented, DEV-mode only — which contradicts [RL-07] | 2026-08-15 |
| **RL-38** | [`docs/bench.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/bench.md) | The file is an empty chart shell: `# Benchmarks` followed by `<header id="header">…<span id="last-update"></span>…</header>`, `<main id="main"></main>`, and a `chart.js` script tag. No data is in the repository, and the rendered page lives on the domain that does not resolve ([RL-27]) | 2026-08-15 |
| **RL-39** | [`docs/deviations.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/deviations.md) | "Luau does not currently have ES6's `class` semantics. For class components, Roact exposes an `extend` method to provide equivalent behavior." … "Since Luau currently lacks a `class` feature, there are also no inheritable constructors; instead, Roact provides a lifecycle method called `init` that takes the place of the constructor" … "Roact 17 allows both direct assignment and use of `setState`" in `init` | 2026-08-15 |
| **RL-40** | [`modules/react/src/React.lua`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/react/src/React.lua) | The export table lists, among others: `Fragment`, `Profiler`, `StrictMode`, `Suspense`, `memo`, `lazy`, `createElement`, `cloneElement`, `isValidElement`, `useCallback`, `useContext`, `useEffect`, `useImperativeHandle`, `useDebugValue`, `useLayoutEffect`, `useMemo`, `useMutableSource`, `useReducer`, `useRef`, `useBinding`, `useState`. (`createContext`, `createRef`, `forwardRef`, `Children`, `Component`, `PureComponent`, `createBinding`, `joinBindings`, `None`, `Event`, `Change`, `Tag` are documented in [`docs/api-reference/react.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react.md) under the same package.) **The table contains no transaction verb, no ownership/scope verb, and no resource-count verb.** Of `memo`, the API page's whole guidance is: "Use this only as a performance optimization, and only when relevant to the use case." | 2026-08-15 |
| **RL-41** | [`docs/api-reference/react.md`](https://raw.githubusercontent.com/Roblox/react-luau/main/docs/api-reference/react.md) | On `Binding:getValue`: "Using `getValue` inside a component's `render` method is likely to result in using stale values! Using the unwrapped value directly won't allow Roact to subscribe to a binding's updates." | 2026-08-15 |
| **RL-42** | [`modules/react/src/ReactHooks.lua`](https://raw.githubusercontent.com/Roblox/react-luau/main/modules/react/src/ReactHooks.lua) | `local function resolveDispatcher(): Dispatcher` / `local dispatcher = ReactCurrentDispatcher.current` … the `nil` case reports "Invalid hook call. Hooks can only be called inside of the body of a function component." Every hook in the package resolves through this function | 2026-08-15 |

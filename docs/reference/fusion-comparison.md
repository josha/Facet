# Fusion ↔ LuauUI: two ways to build a Roblox interface

Fusion is the reactive UI library most Roblox developers reach for. LuauUI is a
declarative UI framework for the same platform. They overlap enough that a
developer picking one has a real decision to make, and they differ enough that
the decision matters — so this document is that comparison, capability by
capability, with a citation on every claim about Fusion.

It is a sibling of [`swiftui-parity.md`](swiftui-parity.md), which measures
LuauUI against the most complete declarative UI framework in wide production
use. This one measures it against the framework it is actually competing with on
this platform. Read that one for *how good is this, as a UI framework*. Read this
one for *which of these two should I use for my Roblox game*.

**One thing makes this comparison unusually cheap to verify, and it should be
said up front.** LuauUI ships a working Fusion adapter — `src/core/fusion_adapter.luau`
implements LuauUI's reactive contract (`src/core/contract.luau`) **over Fusion's
own primitives**, and the shared conformance suite runs against it on every
build. That is not a paper comparison of two design documents. It is one
framework's reactive semantics re-expressed in the other's substrate by somebody
who had to make it actually run, with a scorecard recording exactly which
semantics survived the translation and which did not. Where this document says
Fusion cannot do a thing, in most cases what that means is: somebody tried, and
the check is red, and you can re-run it in four seconds.

---

## 1. How to read this

### Which Fusion, and why it matters

**Fusion 0.2 and Fusion 0.3 are different enough that a claim about one is often
false about the other.** Conflating them is the single easiest way to write a
wrong sentence about this framework, so every claim below is tagged.

- The director's link is **Fusion 0.2** ([FU-01]). It is still the version a
  large amount of shipped Roblox code runs, and its documentation is still live.
- **Fusion 0.3** shipped in August 2024 ([FU-17]) and changed the memory model,
  the state-reading API, and — the part nobody's documentation states — the
  evaluation strategy. It is the current release.
- **LuauUI's vendored copy is 0.3** (`vendor/Fusion/init.luau` declares
  `version = {major = 0, minor = 3, isRelease = true}`), so every claim that
  rests on the adapter or on the conformance run describes **0.3**.

Where the two versions differ, both are stated. §2.4 and §6 are where the
differences are largest.

| | Fusion 0.2 | Fusion 0.3 |
|---|---|---|
| Reading a state object | `obj:get()` | `use(obj)` inside a derivation, `peek(obj)` outside; `:get()` raises with a message pointing at the change [FS-09] |
| Memory model | destructor callbacks per object; `Fusion.cleanup` [FU-06] | **scopes** — an array of things to destroy in reverse order, passed as every constructor's first argument [FU-16] |
| Derived values | recomputed **eagerly** on every write [FS-08] | recomputed **lazily**, on demand [FS-03] |
| Observers | fire synchronously per write [FS-08] | fire synchronously per write, sorted by creation order [FS-01] |
| A bound instance property | coalesced to **one write per resumption step** by a latch [FS-08], [FU-07] | re-assigned **synchronously on every change** [FS-10], [FU-18] |
| Cycle / infinite-loop detection | **none documented and none in source** [FU-12] | a wall-clock guard, one second [FS-01] |

### The four verdicts

Each area below opens with plain framing, then a table, then the caveats that did
not fit in a cell. The verdicts are the same four `swiftui-parity.md` uses, and
they read in one direction — **what LuauUI's answer to a Fusion capability is**:

| Verdict | Means |
|---|---|
| **Covered** | A first-class equivalent ships, is exported, and its tests pass. |
| **Partial** | It ships and works, with named behaviour gaps a consumer will hit. |
| **Composable** | Not a shipped construct, but buildable today from the public surface with no framework change. The recipe is named. |
| **Missing** | No construct and no honest recipe. |

Rows that run the other way — where LuauUI has something Fusion does not — are
marked **no Fusion equivalent** and carry the same evidence discipline. There are
a lot of them, which is why §3 exists: a raw count of "things LuauUI has that
Fusion doesn't" is not a verdict on which framework you should use, and this
document is not going to pretend it is.

### Every claim about Fusion carries a citation

Claims about LuauUI are guarded by checkers (`check_docs`, `check_prop_parity`,
`check_registration`, `check_surface_ledger`, `check_boundary`). Nothing guards
the other side, which is the side the whole comparison rests on — and this
project's own history is why that matters: `swiftui-parity.md` once carried ten
uncited assertions about SwiftUI and a later citation pass found every one of
them wrong.

So, following the §16 convention that `check_docs` enforces on the SwiftUI
document:

- **`[FU-nn]`** resolves in §8 to a page on `elttob.uk/Fusion`, the sentence the
  claim rests on quoted verbatim, the Fusion version, and the date the page was
  read.
- **`[FS-nn]`** resolves to Fusion's **source**, by file and by tag, for claims
  the documentation does not make. Several of the most load-bearing facts in this
  document are in that category — Fusion's docs do not state whether Computeds
  are lazy, and neither version's docs state what happens to a hundred writes in
  one frame.

**The dates are load-bearing.** If you are reading this well after the dates in
§8, treat every Fusion-side claim as *unverified* rather than as wrong: open the
URL, and if the page still says what §8 quotes, move the date. A source citation
rots differently — pin it to the tag, not to `main`.

### The rule this document holds itself to

This document lives in LuauUI's repository and is written by LuauUI's authors.
That is a structural reason to distrust it, and the only useful answer is to be
specific about where Fusion wins and to make those sentences actionable rather
than gracious. §3 names four jobs where Fusion is the better choice and says so
in plain words. §6 records two things the adapter revealed that make **Fusion**
look better than its own documentation does. If you find a row here that reads as
marketing, it is a defect — file it.

---

## 2. The philosophical difference, in plain language

**Read this if you have used neither.** No jargon is assumed. Concrete thing
first, principle second, throughout.

### 2.1 What they agree on

Both are **declarative**. You do not build the screen by hand and then remember
to update it. You write a description — "a label showing the player's coin
count" — and the library keeps the real screen matching the description as the
count changes. Neither one asks you to write `label.Text = tostring(coins)` in
five places and hope you found them all.

Both track dependencies **per value**, not per component. When you read a value
inside a derivation, the library notices, and only the derivations that actually
read a changed value are affected. Neither one re-runs your whole UI function and
diffs the result the way React does.

Everything below is a difference *inside* that shared idea.

### 2.2 In Fusion the graph **is** the UI; in LuauUI it is only the first of four layers

This is the whole difference, and every other one falls out of it.

Here is Fusion's own player-list example, unedited, from its cookbook ([FU-14]):

```lua
New "Frame" {
    Name = "PlayerList",
    Size = UDim2.fromOffset(300, 0),
    AutomaticSize = "Y",
    [Children] = {
        New "UICorner" {},
        New "UIListLayout" {
            SortOrder = "Name",
            FillDirection = "Vertical"
        },
        ForPairs(props.PlayerSet, function(player, _)
            return player, PlayerListRow { Player = player }
        end, Fusion.cleanup)
    }
}
```

Look at what that is. `New "Frame"` **creates a real Roblox `Frame` right now**
and hands it back to you. The reactive objects you pass in bind directly to that
instance's properties. And the layout is done by `New "UIListLayout"` — an actual
Roblox layout object, parented into the frame, doing what it has always done.

So Fusion's model is: *a reactive graph whose leaves are Roblox instance
properties.* There is no layer between your description and the engine. Fusion's
own one-line description of itself is honest about the scope — "a UI, state
management and animation library for Roblox" ([FU-01]) — a **library**, three
jobs, and layout is not one of them, because Roblox already ships layout.

LuauUI splits the same job into four pieces that are not allowed to know about
each other:

| Layer | What it does |
|---|---|
| **Blueprint** | A tree of plain Lua tables describing what should be on screen. It is data. Nothing is created. |
| **Solver** | Measures the blueprint, then arranges it into plain rectangles. **No engine object is involved**, so all of layout runs in a terminal with no Roblox. |
| **Renderer** | Turns solved rectangles into real `GuiObject`s, through a written target contract. Swappable — that is what lets the solver be tested headlessly. |
| **Adapter** | The Roblox-specific end of that contract. Also swappable; a second one drives billboards. |

The consequence a beginner feels first: **LuauUI owns layout and does not use
`UIListLayout` at all.** It materializes no `UIListLayout`, no `UIGridLayout`, no
`UITableLayout` anywhere. Every node is positioned by an absolute rectangle the
solver computed, and the instance tree is flat by default — objects are not
parented to their container unless a registration rule says the engine can carry
something down that subtree for free. Four things register: a `ScrollView`, a
declared `clipChildren`, a fade group (`canvasGroup`/`opacity`), and — since
[ADR-0032](../adr/ADR-0032-nested-instance-tree.md) — a container whose own
authored `scale` or `rotation` reaches children it actually has. Nesting is a
registration policy on top of the same flat render seam, not a second renderer;
an ordinary `VStack`/`HStack`/`ZStack` with none of those four reasons still
produces no Instance of its own if it paints nothing.

That is a big thing to take on, and it needs to buy something. What it buys:

- **Layout is testable without the engine.** Several thousand layout assertions
  run in seconds in a terminal.
- **Layout can say no.** Because the solver knows what it was asked for and what
  it produced, it can *complain*: this text overflows its box, this percentage
  has no bounded parent, this grid has mixed children, these two HUD zones
  collide, these two surfaces are painting over each other. `UIListLayout` has no
  channel for any of that; it silently does something.
- **A property the layout mode will never read is a reported complaint**, not a
  silent no-op. Roblox ignores `HorizontalFlex` under a vertical `FillDirection`
  and tells you nothing.
- **The vocabulary is a strict superset** of `UIListLayout` + `UIFlexItem` in
  every respect but one deliberate divergence (declaration order is the only
  order; there is no `LayoutOrder` analogue). `swiftui-parity.md` §4.1 has the
  row-by-row scorecard.

And what it costs: a great deal more machinery. The vendored Fusion 0.3 in this
repository is **5,153 lines across 67 files**. LuauUI's `src/` is **83,801 lines
across 122 files** — sixteen times as much. That number is the honest headline of
this whole comparison, and §3 is about what you get for it and when you do not
want it.

### 2.3 Who is allowed to write a property

A Roblox screen object has more than one author: Roblox's own StyleSheets, the
player's CoreGui, engine defaults, and any game code that reaches in. **Two
writers on one property is not a disagreement to be resolved by a precedence
rule. It is a bug that leaves no trace.** Measured in Studio: an explicit
property write silently defeats a StyleSheet rule, fires no signal, and the rule
never comes back.

Fusion's model on this is simple and permissive, and it is the right model for a
library: whoever passes the property table owns the property. `New "TextLabel" {
Text = someValue }` binds `Text`, and Fusion refuses only the mechanical
mistakes — a property that does not exist, a key used twice in the same table, a
wrong type ([FU-12]). If two different Fusion components bind the same property
of the same instance, or if a StyleSheet rule already owned it, Fusion neither
knows nor could.

LuauUI keeps a manifest — `src/render/authority.luau` — that names, for every
engine property of every class, the **one** part of the framework allowed to
write it. Rects are written by layout. Token paint by style. A data-driven colour
by binding. A transient fade or slide by presentation. Every write goes through
one site and that site checks the manifest.

The interesting part is what happens when an author legitimately wants to set
something the framework already writes. The answer is not "let the author write
it too". Authored `opacity`, `scale` and `rotation` are composed as a second
**term** inside the one writer's arithmetic: the engine receives
`compose(what the framework is doing, what you asked for)`, resolved at a single
write site, and **nothing writes an engine property called "opacity" at all**.
The manifest asks how many *functions* may write a property. It never asks how
many *facts* that one function may read.

This is a real philosophical fork, and neither side is obviously right. Fusion's
position is that the developer knows what they are doing and the library should
not stand between them and the instance. LuauUI's is that on a platform where a
double write is invisible, the framework has to be the one thing that cannot make
that mistake — at the cost of a vocabulary you must work within rather than
around.

### 2.4 Eager and lazy, and the boundary that is the real difference

This is the section the Fusion adapter exists to make truthful, so it is worth
reading slowly.

**Fusion 0.2 is eager.** `Value:set()` calls `updateAll`, which walks the entire
transitive graph of everything depending on that value and **recomputes all of
it, right now, inside your `set` call** ([FS-08]). It is a genuinely good
implementation of that — a two-pass topological walk, so each object is updated
exactly once, only after all of its own dependencies, and skipped entirely if its
dependencies did not meaningfully change. But it is eager: a `Computed` you have
not read in ten minutes recomputes anyway.

**Fusion 0.3 is lazy, with eager observers.** A `Computed` is declared
`timeliness = "lazy"` and an `Observer` `timeliness = "eager"` ([FS-03], [FS-04]).
`Value:set()` now walks the dependent graph marking everything **invalid**, then
evaluates only the eager nodes — the Observers — and a Computed recomputes when
something actually reads it, through `use()` or `peek()` ([FS-01], [FS-02]). That
is the same pull-based, glitch-free strategy LuauUI's own core uses, arrived at
independently.

**Neither version has a boundary.** That is the sentence. In both versions, every
single `set` is its own complete propagation: the graph settles and your
observers run before `set` returns. There is no "and now apply all of that", no
transaction, no flush, no frame. This is what `src/core/fusion_adapter.luau` says
in its own comment, and it is the most load-bearing sentence in this document:

> Fusion propagates EAGERLY and has no flush boundary at all — `flush` below is a
> no-op for exactly that reason — so there is no "after propagation quiesces"
> moment to hang the phase on. […] with eager propagation there is no write set
> to test for quiescence, so "repeat until a pass writes nothing" is not
> implementable and is not faked.

Here is what that means with numbers. The conformance suite has a tiny
production-shaped check called `micro-live-hud-value`: a speed signal, a memo
formatting it as text, an observer counting how many times a renderer would have
to write. It sets the speed a hundred times individually, then sets it a hundred
more times **inside one transaction**.

- LuauUI's core: 100 writes, then **1**.
- Fusion, through the adapter: 100 writes, then **100**.
  (`expected exactly 1 batched render write, got 100` — re-run 2026-08-15.)

**Now the honest half, because this is the row most likely to be unfair.** Three
qualifications, each of which makes Fusion look better than the bare number:

1. **The adapter is deliberately thin.** Its own header says it "does NOT
   reimplement semantics Fusion lacks […]: the conformance scorecard records
   those differences as rubric evidence." An adapter *could* buffer notifications
   during a transaction and fire each observer once at close. Nobody claims no
   adapter could pass this check. What the red check measures is Fusion's
   **native** semantics, which is the thing a Fusion user actually gets.
2. **Fusion 0.2 coalesces the write that matters most.** A bound instance
   property in 0.2 does not update synchronously — `bindProperty` sets a
   `willUpdate` latch and `task.defer`s the assignment, so a hundred sets in one
   frame produce **one** property write on the next resumption step ([FS-08]).
   That is what the documentation means by "the property will update to match on
   the next resumption step" ([FU-07]), though it never says the word coalesce.
   So in 0.2 the un-batched cost lands on *your* observer callbacks and on every
   intermediate `Computed`, not on the engine.
3. **Fusion 0.3 removed that latch.** `bindProperty` in 0.3 is
   `Observer(scope, value):onBind(function() setProperty(instance, property, peek(value)) end)` —
   synchronous, every change, no defer ([FS-10]). Fusion 0.3's `New` page says
   only that the property "is re-assigned every time the value of the state
   object changes" and states no timing at all ([FU-18]). Neither page in either
   version tells you this changed.

So the honest form of the claim is: **Fusion has no way to say "these fifteen
changes are one change", and 0.3 removed the one place it used to compensate for
that.** LuauUI's `transaction` is that boundary, and it is why LuauUI can promise
that a screen never paints a half-applied state.

### 2.5 Cleanup: the same destination, from opposite directions

**Fusion 0.2**'s answer is *destructors*. A `Computed` that produces something
needing cleanup — an Instance, a connection — takes a destructor function that
"clean[s] up old values when they're no longer needed" ([FU-06]), and
`Fusion.cleanup` is a general "destroy whatever this is" helper. The `For` objects
each take one too, which is why five of the thirty-five documented 0.2 errors are
`destructorNeeded*` and `*DestructorError` ([FU-12]).

**Fusion 0.3** replaced that with *scopes*: "When you create many objects at once,
you often want to destroy them together later" ([FU-16]). A scope is an array;
every constructor takes one as its first argument; `doCleanup(scope)` destroys the
contents **in reverse order** ([FU-16]). Three details in the source are better
than the documentation suggests:

- A cleaned-up scope is **poisoned** — its metatable is replaced so any later
  index or assignment raises `"Attempted to use a scope after it's been
  destroyed"` rather than silently doing nothing [FS-06].
- `doCleanup` refuses to clean the same thing twice, by name:
  `"doCleanup() was given something that it is already cleaning up"` [FS-06].
- **Lifetimes are checked.** Every `use()`, and every property, attribute and ref
  binding, calls `checkLifetime.bOutlivesA` and complains if the thing you used
  will be destroyed before the thing using it [FS-07]. That is a whole class of
  bug caught at the moment you write it.

**LuauUI** has scopes too, and they landed by the same reasoning: `scope:own()`,
`scope:child()`, reverse-order idempotent disposal, double-dispose detection, a
releasability check that raises immediately if you hand `own()` something with no
`dispose()`, and quarantined cleanup errors so one bad teardown does not skip its
siblings. Two differences worth knowing:

- LuauUI **asserts** on `own()` and `child()` into a disposed scope, which covers
  the two operations that matter; it does not poison the handle the way Fusion
  does, because a LuauUI scope is an opaque object rather than an array you index.
- LuauUI has **no cross-scope lifetime check**. A memo in a long-lived scope may
  `use()` a signal owned by a short-lived one and nothing complains until the read
  fails. This is a real Fusion 0.3 lead and it is item G-6 in §5.

### 2.6 What each one thinks a mistake is

Fusion's error catalog is about **mechanical** mistakes: this class has no such
property, this handler is not a function, this spring's damping is negative, this
key was written twice ([FU-12]). Thirty-five of them in 0.2, and — this is worth
sitting with — **not one of them is about a cyclic dependency, an infinite update
loop, or a derivation that never converges.** Fusion 0.2's documented error list
contains no such entry and its source contains no such check. Fusion 0.3 added
one, and it is a **wall-clock timer**: `change` gives itself one second, and if
the graph is still churning it reports `"Detected an infinite loop"` ([FS-01]).
That means a real cycle costs you a full second of frozen frame before you are
told, and the message cannot name the path.

LuauUI's core treats a *semantic* mistake as the interesting kind. A dependency
cycle is reported **with its path** instead of recursing. Writing to state during
a derivation is refused by construction. A feedback loop between effects hits a
bounded round cap — a hundred generations, not a wall-clock second — and reports
how many writes it discarded. A memo that throws is quarantined and the error is
readable through `core:lastError()`. All four are conformance checks, and all four
are red on the Fusion adapter (§4.1), for one shared underlying reason that §6
gets to: Fusion's diagnostics are *printed*, not *returned*.

---

## 3. Pros and cons, in plain words

No hedging in this section. Both lists are meant to be usable by somebody
deciding today.

### Fusion, the good parts

- **You can hold the whole thing in your head.** Fusion's entire documented API
  is **26 members** — twelve State, eleven Instances, three Animation ([FU-13]).
  You can read all of it in an afternoon and you will not be surprised later.
  LuauUI has 45 top-level exports over 83,801 lines and a reference document
  measured in hundreds of kilobytes.
- **Nothing stands between you and Roblox.** `New "Frame" { … }` gives you a
  `Frame`. If you need to hand that instance to `TweenService`, to
  `GuiService.SelectedObject`, to a plugin, to a `BillboardGui.Adornee`, or to
  some library written in 2019, you just do. LuauUI does not expose the instances
  it creates at all.
- **It works on anything, not just UI.** `New` takes any class name. Fusion will
  reactively drive a `Part`, a `Beam`, a `Sound`, a `Highlight` — the same graph
  that runs your menu can run your world. LuauUI renders 21 declared UI classes
  through a target contract and nothing else.
- **`Hydrate` lets you adopt UI you did not write** — "Given an instance, returns
  a component which modifies that instance" ([FU-08]). You can make a
  Studio-authored screen reactive one property at a time. LuauUI is all-or-nothing
  per surface.
- **You already know the layout system.** It is `UIListLayout`. There is nothing
  to learn, nothing to port, and everything a Roblox tutorial says still applies.
- **You get moving fast.** A working reactive player list is the twenty-line
  example in §2.2. That is a real and underrated property.
- **Time-based animation is built in.** `Tween(goal, tweenInfo)` takes a plain
  Roblox `TweenInfo` ([FU-10]), so a designer's "400 ms, quad ease-out" is one
  line. LuauUI has no easing curves at all (§5, G-1).
- **0.3's lifetime checking is genuinely ahead.** Using a value that will die
  before its user is caught where you wrote it, not where it breaks [FS-07].

### Fusion, the costs

- **There is no way to say "these are one change."** Fifteen writes are fifteen
  propagations, and in 0.3 fifteen instance writes (§2.4). If your HUD has a
  frame where three related numbers all change, Fusion has no spelling for
  "publish them together", and a screen that reads two of them will see the
  intermediate state.
- **A cycle costs you a frozen second and tells you nothing about where.** In 0.2
  it is not detected at all [FU-12], [FS-01].
- **The errors go to the output window, not to your code.** There is no
  `lastError()`. Something a Computed does wrong is printed and swallowed; the
  Computed keeps its old value and reports "not changed", so downstream never
  learns anything went wrong [FS-03]. If you are writing tests, or a health
  check, or an agent, this matters a great deal.
- **You own layout, and layout is where UI bugs live.** `UIListLayout` will
  cheerfully lay content outside a box, ignore a property that does not apply to
  the current fill direction, and tell you neither. Everything LuauUI's
  diagnostics channel reports is, in Fusion, something you find in a screenshot.
- **Nothing is provided above the primitive.** No focus system, no keyboard or
  gamepad navigation, no theming, no controls, no virtualization, no safe areas,
  no text-size handling, no modal/toast presentation. Fusion's API index has no
  entry for any of them ([FU-13]) — correctly, because it is a library and never
  claimed otherwise. But those are the things that take the last 70% of a shipping
  UI, and you will write all of them.
- **No custom equality.** Fusion's similarity test treats any plain (non-frozen,
  metatable-less) table as never similar to anything [FS-05], and its own
  documentation states the consequence: "Updates are always sent out when setting
  a table value" ([FU-02]). If your state is a table, every `set` fires.
- **0.2 and 0.3 are different frameworks wearing one name.** The `:get()` you
  learned is gone; the destructor you wrote is gone; the write coalescing you were
  implicitly relying on is gone. Plan the migration, do not drift into it.

### LuauUI, the good parts

- **Layout that answers back.** Overflow, unbounded percentages, containers with
  no bound, mixed grid children, inert placement properties, HUD zone collisions,
  two surfaces painting over each other — all reported through one
  `controller.diagnostics()` call. Project history records this channel naming a
  shipped layout defect that a human screenshot review had missed.
- **A boundary.** `transaction` means many writes, one publication. A theme swap
  repoints the stylesheet and commits new metrics in one transaction, so paint and
  geometry cannot disagree for a frame — and mount identity, focus, scroll
  position, selection and half-typed text all survive it.
- **The last 70% is already there.** 51 registered conformance rows; sixteen
  interactive controls, every one of them carrying an automated proof that it
  works with mouse, touch, keyboard **and** gamepad; a focus graph with grouped
  scopes and document-order Tab traversal; theme packages that own typography,
  metrics, radii, insets and art; virtualized lists, tables and grids; safe areas;
  the player's text-size preference as a first-class layout input; modals, toasts,
  popovers with focus traps.
- **Layout runs without Roblox.** The solver is pure. Thousands of layout
  assertions run in seconds in a terminal, which changes what it is like to work
  on this.
- **It is built to be maintained by agents.** Unknown properties are refused with
  a did-you-mean and the full legal set. A family of checkers reconciles
  documentation, the export table, property authority and the tests so they cannot
  drift apart without something going red.
- **Fine-grained invalidation, measured.** One changed value re-solves only the
  smallest enclosing subtree it can affect — 141 arranged nodes down to 8 on the
  framework's own instrumented surface.

### LuauUI, the costs

- **It is sixteen times the code, and you will feel it on day one.** There is a
  vocabulary — blueprint, solver, surface, contribution, authority, decoration
  slot, motion class — and you have to learn it before the second screen.
- **You cannot try something and see what happens.** A property the framework has
  considered and declined raises at construction with a route, not a silent
  no-op. This is deliberate and it is genuinely slower at the start.
- **You cannot reach the instances.** There is no `Ref`, no `Out`, no handle. The
  public controller surface is `rectOf`, `screenRectOf`, `diagnostics()`,
  presentation writes — and nothing that returns a `GuiObject`.
- **It only does UI.** No `New "Part"`. Declarative 3D has an accepted decision
  record ([`ADR-0024`](../adr/ADR-0024-declarative-3d.md)) and no implementation.
- **No time-based easing anywhere.** Springs, a beat-sequenced timeline, a chase,
  a counter, a timer — and no duration-plus-curve. §5, G-1.
- **No assistive-technology bridge of any kind.** Nothing talks to a screen
  reader. A blind player cannot use a LuauUI interface. Fusion has none either,
  but Fusion is a library and LuauUI is the one claiming to be a framework, so
  this is a hole on LuauUI's side of the ledger and not on Fusion's.
- **No right-to-left or bidirectional support.** Same asymmetry.
- **Nothing here has ever run on a physical device.** Every claim is a headless
  test run or a scripted drive of Roblox Studio's emulator.
- **It has one production consumer.** Fusion has years of shipped games behind it
  and a community that has hit the sharp edges already. LuauUI has Rascal Rally.

### So which one

| If your situation is… | Use |
|---|---|
| A jam game, a plugin, a tool, a prototype, one HUD | **Fusion.** You will be done before you finish reading LuauUI's guide. |
| You need to reactively drive Parts, Beams, Sounds — not just UI | **Fusion.** LuauUI does not do this and has not decided to yet. |
| You have existing Studio-authored UI you want to make reactive without rewriting | **Fusion.** `Hydrate` is exactly this and LuauUI has no answer. |
| You must hand a `GuiObject` to some other Roblox API | **Fusion**, unless the thing you need is one LuauUI already wraps internally. |
| A shipping game's full UI: settings, store, results, HUD, on phone and console and desktop | **LuauUI.** The four-input conformance, adaptive composition, theming and focus systems are the parts you would otherwise be writing for six months. |
| Long lists, tables, grids of thousands of rows | **LuauUI.** Windowing is shipped and measured; Fusion has no virtualization. |
| Your interface must adapt from a 320×640 phone to a TV with no device-name branches | **LuauUI.** `Composition`/`Region` is what that is for. |
| You are an agent, or a small team who will not be reading this code in six months | **LuauUI**, for the checkers and the diagnostics. |
| You need a value to change over exactly 400 ms with a designer's easing curve | **Fusion today.** See G-1. |

---

## 4. Feature comparison

Reading direction: each row names a **Fusion** capability and verdicts **LuauUI's
answer to it**. Rows marked *no Fusion equivalent* run the other way.

### 4.1 The reactive core

This is the area the adapter measures directly, so it is the area with the
hardest evidence in the document. The scorecard below is a re-run from
2026-08-15: the identical 46-check conformance suite against LuauUI's own core
and against Fusion 0.3 through the adapter.

**LuauUI custom core: 46/46. Fusion adapter: 37/46.**

| Fusion capability (version) | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `Value` — a mutable observed value ([FU-02], 0.2/0.3) | **Covered** | `core:signal(initial, eq?)` | `src/core/custom.luau`; check `signal-read-write` PASS on both cores |
| `Computed` — a derived, cached value ([FU-03], 0.2/0.3) | **Covered** | `core:memo(compute, eq?)`. Same idea, and in 0.3 the same *strategy*: both are pull-based and recompute on demand | `src/core/custom.luau`; [FS-03]; check `memo-derives-and-updates` PASS on both |
| Automatic dependency detection, dynamically ([FU-03], 0.2/0.3) | **Covered** | `use()` inside a memo registers the dependency; the dependency set is replaced atomically after a successful evaluation. Fusion's own page states the same intent — "the dependencies will be updated to reduce unnecessary updates" ([FU-03]) | check `dynamic-dependencies-swap-atomically` **PASS on both** |
| Glitch-freedom (a diamond never fires an observer with inconsistent inputs) | **Covered** | Eager stale-marking plus pull-based recompute. 0.2 achieves it by topological ordering [FS-08]; 0.3 by invalidate-then-evaluate [FS-01] | check `glitch-free-diamond` **PASS on both** |
| Skipping an equal write ([FU-02], 0.2/0.3) | **Covered** | Default equality is NaN-safe (`NaN ~= NaN` would otherwise refire forever) | checks `equal-write-skipped`, `nan-equal-write-skipped` PASS on both |
| Per-value custom equality | **Covered** — **no Fusion equivalent** | `core:signal(v, eq)` and `core:memo(f, eq)` take an equality function. Fusion has none, and its documentation states the consequence: "Updates are always sent out when setting a table value" ([FU-02]); the source treats any non-frozen metatable-less table as never similar [FS-05] | check `custom-equality-respected` — **PASS custom, FAIL fusion** (`eq-equal table write fired observer`) |
| **Write batching** — many writes, one publication | **Covered** — **no Fusion equivalent**, and this is the load-bearing one | `core:transaction(body)`. §2.4 has the argument and the number | checks `transaction-batches-observer-to-one-fire`, `transaction-revert-produces-no-fire`, `micro-live-hud-value` — **all PASS custom, all FAIL fusion** |
| Cycle detection | **Covered** — reported *with its path* | A dependency cycle raises readably instead of recursing. Fusion 0.2 documents no such error and has no such check [FU-12]; 0.3 has a **one-second wall-clock** guard whose message cannot name the cycle [FS-01] | check `cycle-reported-not-hung` — **PASS custom, FAIL fusion** (`cycle produced no diagnostic`); the adapter's factory declares `cycleDetection = false` rather than claiming it |
| Refusing a write during a derivation | **Covered** | Illegal by construction. Fusion's documentation warns about side effects in a Computed — "you must return the value immediately" ([FU-04]) — but nothing enforces it | check `write-during-memo-is-error` — **PASS custom, FAIL fusion** |
| A failed derivation is *queryable* | **Covered** — **no Fusion equivalent** | `core:lastError()` returns the quarantined error string. Fusion's Computed `xpcall`s its processor, routes the error to `logErrorNonFatal`, keeps the old value and returns "not changed" — so the error is printed and the graph never learns [FS-03] | check `memo-error-quarantined` — **PASS custom, FAIL fusion** |
| Bounded feedback-loop protection | **Covered** | A hundred effect-write generations, then a report naming how many writes were discarded — a *round* cap rather than a wall clock, so it is deterministic and testable | check `feedback-loop-hits-iteration-cap` — **PASS on both**, by different mechanisms |
| Effects (a tracked side-effecting run) | **Covered** | `core:effect(run)`. Fusion has no effect primitive; the adapter emulates one with an eager Observer over a Computed that performs the tracked run | `src/core/fusion_adapter.luau`; check `effect-runs-post-commit-and-writes-schedule-later-round` PASS on both |
| Observers ([FU-05], 0.2/0.3) | **Covered** | `core:observe(source, onChange)`. **Both frameworks notify in node creation order** — LuauUI by sequence number, Fusion 0.3 by sorting its eager list on `createdAt` [FS-01]. §6 is about that convergence | checks `observer-*` PASS on both |
| `Observer:onBind` — run now, then on change (0.3) | **Covered** | `core:effect` is exactly this: the tracked body runs immediately at registration and re-runs on dependency change | `src/core/contract.luau` |
| A settle phase — terminal work that runs after propagation quiesces, repeating until nothing moves | **Covered** — **no Fusion equivalent** | `core:settle(run)`. Registration-ordered, restarts when a pass writes, and counts against the same bounded cap. This is where a surface's layout solve lives. The adapter can offer the convergence half and not the joining half, for exactly the reason in §2.4 | checks `settle-runs-after-propagation-and-converges-in-one-flush`, `settle-that-never-converges-hits-the-iteration-cap` — **PASS custom, FAIL fusion**; `settle-callbacks-never-see-a-half-propagated-graph` PASS on both |
| Scope ownership and reverse-order disposal ([FU-16], 0.3) | **Covered** | `scope:own/use/child/dispose/isDisposed`, idempotent, reverse-order, with double-dispose detection, quarantined cleanup errors, and a releasability check at `own()` | checks `scope-dispose-reverse-order-idempotent`, `double-dispose-detected`, `memory-neutral-churn` — **PASS on both** |
| Scope poisoning — using a destroyed scope crashes loudly (0.3) [FS-06] | **Partial** | LuauUI asserts on `own()` and `child()` into a disposed scope, which is the same protection for the two operations that mutate one. It does not poison the handle, because a LuauUI scope is opaque rather than an array the consumer indexes | `src/core/scope_impl.luau` |
| Lifetime checking — using a value that will outlive its user is an error (0.3) [FS-07] | **Missing** | No cross-scope lifetime check exists. See §5, G-6 | verified absent by search of `src/core/` |
| A derivation that owns per-value resources (0.3's `Computed(scope, fn(use, scope))`; 0.2's destructor parameter [FU-06]) | **Partial** | The UI-shaped case is covered elsewhere and better: `UI.ForEach`'s `row(item, itemScope)` gives a genuine per-item scope, and `newResourceProvider` gives scope-owned handles with generation-counter stale-completion rejection. The **core-shaped** case is not: `Core.memo`'s compute receives `use` and nothing else. §5, G-5 | `src/core/contract.luau`; `src/blueprint.luau` (`ForEachSpec`) |
| Live counters over the reactive graph | **Covered** — **no Fusion equivalent** | `core:counters()` returns live signal/memo/observer/effect/scope/settle counts, which is what makes "this churn is memory-neutral" an assertion rather than a hope | `src/core/contract.luau`; check `memory-neutral-churn` |

**Cost, measured.** Headless Lune, evidence class **regression signal** — never a
device claim (`artifacts/bench.json`, 2026-08-15). Two hundred independent
signal→memo→observer chains, one of them written:

| scenario | LuauUI core | Fusion 0.3 adapter | imperative baseline |
|---|---|---|---|
| `sparse-update-under-load` p50 | 0.0010 ms | 0.0020 ms | 0.0172 ms |
| `hud-binding-storm` p50 | 0.1651 ms | 0.2936 ms | **0.0478 ms** |

Read those honestly. Fusion is about **2× LuauUI on the sparse update**, which is
close, and both are an order of magnitude better than recompute-everything —
which is the comparison that actually matters, because recompute-everything is
what hand-written Roblox UI code does. On `hud-binding-storm`, where nearly
everything changes every frame, the dumb baseline **beats both**, and the fine-
grained cores pay for bookkeeping they cannot amortize. Neither of those numbers
is a reason to pick a framework; the adapter carries the cost of translating
between two object models, so its arm is not a clean measurement of Fusion
either.

**Caveats.**

- **The nine red checks are a measurement of Fusion's native semantics, not a
  ceiling.** §2.4 explains what a thicker adapter could and could not recover.
- **The bake-off is on record and it is old.** [`ADR-0002`](../adr/ADR-0002-foundation-core-selection.md)
  chose LuauUI's custom core over the Fusion adapter and an imperative baseline
  in July 2026, weighted 144 / 91 / 108 against a 26-check suite where Fusion
  scored 19. The suite has since grown to 46 and the adapter has gained a settle
  implementation, so **use the 37/46 above, not the ADR's number.** The ADR's
  reasoning is still the right one to read: Fusion lost on diagnostics and
  batching, not on speed.
- **`lastError()` is sticky.** It answers "was this core ever quarantined",
  never "is it healthy now."

### 4.2 Instances and rendering

The area where Fusion is a library and LuauUI is a framework, with everything
that implies in both directions.

| Fusion capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `New "ClassName" { … }` — create **any** Roblox instance, with reactive properties ([FU-07]) | **Partial**, narrower on purpose | Twenty-one declared UI classes, rendered through a written target contract. LuauUI cannot create a `Part`, a `Beam` or a `Sound`. Declarative 3D is an **accepted decision with no implementation**: a sibling scene system on the shared reactive kernel, built when a consumer arrives | [`ADR-0024`](../adr/ADR-0024-declarative-3d.md); `src/render/target_contract.luau` |
| Reactive property binding | **Covered**, with a stricter rule | Eleven style properties are re-applied on reactive change in a declared order, and binding-authority properties are written by exactly one writer per class per property (§2.3). Fusion binds whatever you pass | `src/render/authority.luau`; `src/render/renderer.luau` (`STYLE_PROP_ORDER`) |
| `[Children]` — declarative parenting ([FU-14]) | **Covered**, and differently | `children` is an ordinary blueprint field. But LuauUI's **instance tree is flat by default**: a node is not parented to its container unless the container registered as a real engine parent — a `ScrollView`, `clipChildren`, a fade group, or an authored `scale`/`rotation` on children it has ([ADR-0032](../adr/ADR-0032-nested-instance-tree.md)) — because every node is placed by an absolute solved rect regardless, and registering only pays where the engine can carry something down the subtree for it | `src/render/renderer.luau`; `src/render/instance_boundary.luau` |
| `Hydrate` — bind onto an instance you did not create ([FU-08]) | **Missing** | No public seam. `adapter.adopt` exists but is the internal recycling path, not a hydration API. §5, G-8 has the argument for why this is a *decline* rather than a gap | verified absent by search of `src/` |
| `Ref` / `Out` — get the instance, or read a property back ([FU-13]) | **Missing** | The public controller surface is `rectOf`, `screenRectOf`, `diagnostics()` and the presentation writes. Nothing returns a `GuiObject`. §5, G-2 | `src/render/renderer.luau`; verified by search |
| `OnEvent` / `OnChange` — connect to an instance's events ([FU-13]) | **Covered** for UI events, **Missing** as a general seam | Blueprint props (`onPress`, `onPointerDown`, `onScrollWheel`, `onAppear`, `onDisappear`, …) cover the events a UI needs; there is no "connect to any signal on the instance" | `src/blueprint_schema.luau` |
| `SpecialKey` — a user-extensible property-table key ([FU-13]) | **Missing**, deliberately | LuauUI's property set is closed and validated at construction: an unknown property is refused with a did-you-mean and the full legal set. A user-defined key is exactly the second-authority case §2.3 exists to prevent | `src/blueprint_schema.luau` |
| `Component` — a reusable piece of UI ([FU-15]) | **Covered** | Both answers are the same: a plain Lua function that returns a description. Fusion's returns an instance; LuauUI's returns a blueprint table | `src/blueprint.luau` |
| Default properties (opting out of unhelpful engine defaults) ([FU-07]) | **Covered**, and far wider | Theme packages own typography, spacing, control heights, radii, strokes, solver-visible content insets and asset chrome; native StyleSheets carry the state selectors | [`ADR-0019`](../adr/ADR-0019-theme-packages.md) |
| — | **No Fusion equivalent** | **Instance recycling.** A retiring node's Roblox instances are handed to the next node of the same shape rather than destroyed and recreated | `src/render/renderer.luau` |
| — | **No Fusion equivalent** | **A swappable render target.** The solver has never seen a Roblox object, so the same tree renders to a screen, a billboard, or a test harness | `src/render/target_contract.luau` |

### 4.3 Layout

Fusion has none, correctly and by design — its answer is that Roblox already
ships layout, and the cookbook uses `UIListLayout` directly ([FU-14]). So this
whole table is one-directional, and the fair reading is not "LuauUI wins" but
"these are different products". `swiftui-parity.md` §4.1 is where LuauUI's layout
vocabulary is scored against the native controls it replaces, which is the
comparison a Fusion user actually cares about.

| Fusion capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Layout — anything at all | **No Fusion equivalent.** Fusion's documented API has three categories, State, Instances and Animation ([FU-13]); layout is `New "UIListLayout"` ([FU-14]) | A headless measure-then-arrange solver: weighted flex stacks, `distribute`, `layoutPriority` × `shrinkWeight`, per-child `lineAlign`, flow-wrap, three grid modes with row/column flow and spanning, `ViewThatFits`, `containerRelativeFrame`, safe areas, and `Composition`/`Region` ranked adaptive degradation | `src/layout/`; `swiftui-parity.md` §4 |
| — | **No Fusion equivalent** | **Layout complains.** Overflow, unbounded percent, unbounded containers, mixed grid children, inert placement props, HUD zone collisions and cross-surface overlap all arrive through `controller.diagnostics()` | `src/render/renderer.luau`; `src/layout/placement_audit.luau` |
| — | **No Fusion equivalent** | **Incremental relayout.** One changed value re-solves only the subtree it can affect — measured 141 arranged nodes down to 8 | `tests/incremental_layout.spec.luau` |
| — | **No Fusion equivalent** | **Layout is testable with no engine.** The solver is pure | `src/layout/solver.luau` |

### 4.4 Collections

| Fusion capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `ForValues` — map over a table's values, leaving unchanged ones alone ([FU-11]) | **Covered** | `UI.ForEach { items, key, row }` — keyed structural diffing with adds, removes and moves only; duplicate keys are a hard error; a row removed and re-added mid-exit-transition resumes the same mounted subtree | `src/mount.luau`; `src/blueprint.luau` |
| `ForKeys` / `ForPairs` — map over a **dictionary** ([FU-11]) | **Composable**, and the recipe has a trap | `ForEachSpec.items` is `Readable<{any}>` — an **array**. A dictionary must be flattened in a memo first, and the flattening must sort, because Luau's `pairs` order is not stable and an unsorted flatten silently makes your row order nondeterministic. There is no shipped helper. §5, G-3 | `src/blueprint.luau` (`ForEachSpec`) |
| Per-item cleanup on removal (0.2's destructor argument; 0.3's inner scope) | **Covered** | `row(item, itemScope)` hands each item a real scope disposed when that item leaves | `src/blueprint.luau` |
| — | **No Fusion equivalent** | **Virtualization.** `newVirtualList` (either axis), `newTable { virtualized = true }` and `newVirtualGrid` (either axis) window a collection to what the viewport touches, over one shared prefix-sum extent index. Measured: a lazy grid's mount is 54× cheaper than the eager one at 10,000 items, and a scroll frame is flat in N | `src/virtual_extents.luau`; `src/controls/`; `swiftui-parity.md` §4.2 |
| — | **No Fusion equivalent** | **A rich collection control.** Columns, header, single/multi/range selection, reorder, per-row capability opt-outs, swipe actions | `src/controls/table.luau` |

### 4.5 Motion

The one area where Fusion has something LuauUI genuinely lacks.

| Fusion capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `Spring(goal, speed, damping)` — a value that follows another as if on a damped spring ([FU-09]) | **Covered**, with a different vocabulary | `MotionValue` springs declared as `{ dampingRatio, response }`. Fusion's damping is the same idea in the same words — "`0` represents no friction, and `1` is just enough friction to reach the goal without overshooting" ([FU-09]). LuauUI's `response` is a time constant where Fusion's `speed` "does not directly correlate to a duration" ([FU-09]) | `src/motion/motion.luau`, `src/motion/spring.luau` |
| An inline spring at a call site ([FU-09]) | **Missing, by decision** | Refused with a hard error naming `motion.registerClass`. Four named classes ship, and re-registering one is the sanctioned way to tune it. The reason is drift: a library with forty slightly different feels got there one call site at a time | `src/motion/classes.luau` |
| `Spring:setVelocity` / `addVelocity` / `setPosition` ([FU-09]) | **Covered**, and deeper | `setTarget` never touches value or velocity, so an interrupted spring continues instead of jumping — pinned by a differential test against a velocity-cut twin. A 100 ms rolling-window velocity tracker feeds gesture→animation hand-off | `src/motion/motion.luau`; `src/input/drag_velocity.luau` |
| **`Tween(goal, tweenInfo)` — time-based easing ([FU-10])** | **Covered** (built 2026-08-15, ADR-0033) | `clock:tween(initial, curveName)` and the `motion.registerCurve` registry. Before that mission: nothing in `src/motion/` took a duration and a curve, and `Enum.EasingStyle`, `TweenInfo` and the word `easing` appeared nowhere in `src/` (all three are there now). The engine's own `TweenService:GetValue` evaluates the curve in production (a PURE evaluator, so it can drive a value LuauUI owns where `TweenService:Create` cannot); a twin pinned to it by a 33,033-sample differential oracle serves Lune. Fusion takes a plain `TweenInfo` at the call site; LuauUI refuses that and takes a registered curve NAME, which is the same drift rule the spring classes already carry | `src/motion/curves.luau`; ADR-0033; `artifacts/time-based-easing/` |
| — | **No Fusion equivalent** | **Reduce Motion that preserves information.** Decorative motion snaps but still fires its completion callback; *informational* motion (a count-up whose number is the message) keeps running to the same terminus but quantizes its writes to a 250 ms step | `src/motion/motion.luau` |
| — | **No Fusion equivalent** | **`withAnimation`** — wrap a state write and every node whose box changed is painted travelling, on one shared progress spring, plus the three authored paint values | `src/present/presenter.luau` |
| — | **No Fusion equivalent** | **Arrival at a live target** (`chase`), **choreography** (`timeline` with `interrupt`/`skip`), and structural **enter/exit transitions** shared by `ForEach` and `When` | `src/motion/`; `src/render/transitions.luau` |

### 4.6 Everything above the primitive

Fusion ships none of this and does not claim to. The table is here so a Fusion
user can see the size of what they will be writing themselves, not as a score.

| Capability | Fusion | LuauUI |
|---|---|---|
| Controls catalog | none ([FU-13]); the cookbook has a button *recipe* ([FU-01]) | 51 registered rows; 25 composites; 16 interactive, all with automated four-input proofs |
| Focus / keyboard / gamepad navigation | none | `newFocusGraph`: flat and grouped scopes, per-group axis/wrap/entry/exit, directional navigation, document-order Tab traversal, focus traps and restore |
| Theming | none; the cookbook has a light/dark *recipe* ([FU-01]) | Theme packages owning typography, metrics, radii, strokes, solver-visible insets and 17 art decoration slots; dark/light on native StyleSheets with no remount |
| The player's text-size preference | none | First-class layout input, with measured per-preference pixel offsets; changing it re-solves in place preserving identity, focus, scroll and state |
| Safe areas / platform chrome | none | Four-edge insets as environment facts, plus a `platformChrome` band that models Roblox's own controls as an L rather than an edge |
| Modals, toasts, popovers | none | A presenter with focus traps, priority bands, typed dismissal reasons, display-order layering, and cross-surface overlap detection |
| Drag and drop | a cookbook recipe ([FU-01]) | `UI.draggable` / `UI.dropTarget` with a typed payload and three acquisition paths funnelling into one session lifecycle, including a non-pointer arm→navigate→commit flow |
| Adaptive layout | none | `Composition`/`Region` ranked degradation; five clean-room reference apps carry all their adaptation with **zero device-name branches** |
| Assistive technology | none | **none** — this row is a tie and it is the largest hole in either framework |
| Right-to-left / bidirectional | none | **none** — likewise |
| Diagnostics you can query | `lastError` does not exist; errors are printed | `controller.diagnostics()` and `core:lastError()` |
| Performance instrumentation | none | 20 named production-shaped workloads, p50/p95/p99, regression budgets as executable ratio tests, live heap and graph counters |

### 4.7 Context and environment

| Fusion capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `Contextual` — a user-defined value passed down the call stack without threading it through props (0.3; [FU-17] names theme colour as the motivating case) | **Partial** | LuauUI's environment does the same job for the framework's own facts — per-key signals with derived memos on top, so a keyboard-occlusion change cannot invalidate a subscriber that only reads colours. But **the key set is closed**: there is no `defineKey`, no consumer namespace, and no way for a game to add "this panel is in preview mode" as an environment fact. §5, G-4 | `src/env/environment.luau`; verified by search |

### Verdict counts

Across §§4.1–4.7: **48 comparison rows** carrying a verdict — **26 Covered, 4
Partial, 1 Composable, 5 Missing**, plus **16** marked *no Fusion equivalent*.
(Those overlap by five: a row can name a LuauUI capability whose nearest Fusion
analogue exists in a narrower form, and it carries both marks.) §4.6's
scope-of-the-two-products table is deliberately excluded from the count — it
scores nothing.

**A count is not a score, and here it is less of one than usual.** Fusion is a
library with three jobs and LuauUI is a framework with about fifteen; counting
rows measures scope, not quality, and a reader who takes "26 Covered" as a
verdict on which to use has read the wrong section — §3 is that section. The five
**Missing** rows are the part of this document worth acting on, and §5 is where
they go.

---

## 5. Ranked gap analysis — what, if anything, to build before first release

The director's question, restated: *are there features in Fusion we should
implement before LuauUI's first release?*

**The short answer is two, and they are both small.** Ranked by what a real game
author would actually miss, with a cost, whether LuauUI already answers it
differently, and a recommendation. This was the list to dispatch from; **G-1 was
built on 2026-08-15 (ADR-0033) and G-3 alongside it** — the rest stand as written.

| # | Gap | Recommendation |
|---|---|---|
| **G-1** | Time-based easing (`Tween` / `TweenInfo`) | ~~BUILD NOW~~ — **BUILT 2026-08-15**, ADR-0033 |
| **G-2** | An instance escape hatch (`Ref` / `Out`) | **DEFER** — trigger named |
| **G-3** | Reactive iteration over a dictionary (`ForKeys` / `ForPairs`) | ~~BUILD NOW~~ — **BUILT 2026-08-15**, `UI.sortedEntries` (a helper, not a class) |
| **G-4** | Consumer-defined environment values (`Contextual`) | **DEFER** — trigger named |
| **G-5** | A derivation that owns per-value resources | **DEFER** — trigger named |
| **G-6** | Cross-scope lifetime checking | **DEFER** — trigger named |
| **G-7** | Driving arbitrary Roblox instances (`New "Part"`) | **DEFER** — already owns a decision record |
| **G-8** | `Hydrate` — adopting instances LuauUI did not create | **DECLINE** — reason and route below |
| **G-9** | Scope poisoning | **DECLINE** — already answered |
| **G-10** | Per-frame instance-write coalescing | **DECLINE** — already answered, better |

---

#### G-1 — Time-based easing. **BUILD NOW.**

**What it is.** Fusion ships `Tween(goal, tweenInfo)`: "Follows the value of
another state object, by tweening towards it", where `tweenInfo` is "The style of
tween to use when moving to the goal" ([FU-10]) — a plain Roblox `TweenInfo`, so
easing style, direction, duration, delay, repeat count and reverse all come free.

**What LuauUI has instead**, as of the survey and BEFORE ADR-0033 shipped.
Springs, a beat-sequenced `timeline`, a 2-D `chase`, a `counter` and a `timer`.
Verified AT THAT TIME: `Enum.EasingStyle`, `TweenInfo` and the string `easing`
appeared nowhere in `src/`. All three are there now — `src/motion/curves.luau`
carries the registry and the engine's evaluator — so read this paragraph as the
before picture, not as a live claim. A spring's duration is not authorable —
`response` is a feel dial, and the four registered classes are 0.18 s to 0.5 s.

**Why a game author misses it.** Three concrete cases the framework cannot
currently express. A designer hands you a spec in milliseconds and a named curve,
and you have to argue with them instead of implementing it. A UI beat must land
on an audio cue or a fixed-length cutscene frame, and a spring's settle time is
emergent rather than commanded. And a *linear* ramp — a loading bar, a cooldown
sweep — is not a spring shape at all; a spring approaches its target
asymptotically and a cooldown must arrive exactly on time.

**Cost: small.** `MotionValue` already has the whole handle — a target, a current
value, `onSettle`, reduced-motion branching, and a clock that steps it. A tween
driver is a second driver behind that same handle. The only design work is
keeping the framework's own rule: an inline `TweenInfo` at a call site must be
refused exactly the way an inline spring literal is, so the curve family belongs
in a registry beside `motion.registerClass` — `motion.registerCurve("banner",
{ duration = 0.4, style = "quad", direction = "out" })`. That preserves "zero
per-call magic numbers", which is the invariant the spring-only decision was
protecting in the first place.

**Recommendation: build now.** — **DONE, 2026-08-15 (ADR-0033).** Shipped as
`clock:tween(initial, curveName)` plus `motion.registerCurve`, with the curve
evaluated by the engine's own `TweenService:GetValue` and a pure twin, pinned to
it by a differential oracle, serving the headless suite. Two findings worth
carrying back into this document's own claims: the gap was never "no duration"
(`timer` and `glide` both had one) but "no SHAPE" — both were strictly linear;
and the "consumer proof" this note first claimed — that RascalRally's `p^1.6`
ease-in had been flattened to a linear timer in its LuauUI port — **was withdrawn
on the same day** by the consumer rider: that exponent shapes a blink FREQUENCY no
easing curve can express, only legacy calls it, and the port's linear timer
faithfully matches the linear ramp legacy actually paints (ADR-0033, "Context").
No shipped consumer had a curve taken away from it; the primitive stands on the
duration that arrives on time. The original reasoning below stands as written.

It is the only row in §4 where a Fusion user
moving to LuauUI loses a capability outright, it is the shape every design
handoff arrives in, and shipping 1.0 of a motion system with no duration is a
hole a reviewer will find in the first hour.

#### G-2 — An instance escape hatch. **DEFER**, trigger below.

**What it is.** Fusion's `Ref` writes the created instance into a `Value`, and
`Out` binds a property back out ([FU-13]). You always have the `GuiObject`.

**What LuauUI has instead.** Nothing. The public controller surface is `rectOf`,
`screenRectOf`, `diagnostics()` and the presentation writes; verified by search,
no public API returns an `Instance`.

**Why it matters.** The Roblox API is full of functions that take a `GuiObject`:
`GuiService.SelectedObject`, `TweenService:Create`, `UIDragDetector`,
`BillboardGui.Adornee`, `CanvasGroup` capture, and every third-party library.
LuauUI already wraps several of these internally — there is an opt-in engine
selection bridge, native drag detectors, and `canvasGroup` as a declared prop —
so the gap is narrower than it sounds. But it is not zero, and "I cannot get at
it" is the single most common reason a developer abandons a framework.

**Does LuauUI answer it differently?** Partly, and the reason it withholds the
handle is not squeamishness: handing out a `GuiObject` hands out the ability to
write its properties, which is precisely the second-writer situation §2.3 exists
to make impossible. A read-only handle is not a thing Roblox offers.

**Recommendation: defer, with a named trigger** — *the first consumer naming a
specific Roblox API that requires a `GuiObject` and that LuauUI does not already
wrap.* The right shape when that arrives is almost certainly not `Ref`; it is a
narrow, named seam for that one API, the way the selection bridge already is.
Booking it as "add `Ref`" would ship the authority hole with it.

#### G-3 — Reactive iteration over a dictionary. ~~BUILD NOW~~ — **BUILT 2026-08-15** (a helper).

**What it is.** Fusion's `ForKeys` and `ForPairs` map over a table with arbitrary
keys, "leaving unchanged values alone" ([FU-11]).

**What LuauUI has instead.** `ForEachSpec.items` is `Readable<{ any }>` — an
array, keyed by `key(item)`. A dictionary must be flattened into an array first.

**Why it matters, and this is the actual argument.** The flatten is three lines
and every consumer will write it, and **the obvious version of it is wrong**:
Luau's `pairs` order is not stable, so a memo that flattens a dictionary with
`pairs` produces a different row order between runs. LuauUI guarantees
deterministic dumps at the framework level and then hands its consumers a
one-liner that silently breaks determinism in their own screen. That is exactly
the class of defect this codebase spends its diagnostics budget on.

**Cost: tiny, and it is not a new blueprint class.** One exported helper —
`UI.sortedEntries(dict, compare)` returning a `Readable<{ {key, value} }>` — plus
a paragraph in the guide, plus one test that the same dictionary yields the same
order twice. The construction ladder's own test (does it need its own layout,
paint or input semantics an existing class cannot compose?) says helper, not
class.

**Recommendation: build now**, at helper scope only. — **DONE, 2026-08-15
(`UI.sortedEntries`).** It orders KEYS rather than entries, which is what makes
the determinism unconditional. Refuse the temptation to add
a `UI.ForPairs` blueprint class; that would be a second structural region with
the same semantics as the first.

#### G-4 — Consumer-defined environment values. **DEFER**, trigger below.

**What it is.** Fusion 0.3's `Contextual` lets a value be assigned for the
duration of one callback and read anywhere down the call stack, without threading
it through every function in between. Fusion's own release material names theme
colour as the motivating case ([FU-17]).

**What LuauUI has instead.** An environment of per-key signals with derived memos
on top, precise enough that a keyboard-occlusion change cannot invalidate a
subscriber that only reads colours. But the key set is **closed** — verified: no
`defineKey`, no `registerKey`, no consumer namespace anywhere in `src/env/`. A
game that wants "this panel is in preview mode" as an ambient fact threads a
signal through props.

**Does LuauUI answer it differently?** Adequately, for now. A blueprint is built
by a plain Lua function, so passing a signal down is cheap and explicit — and
explicit prop-passing is a defensible position, not a missing feature.

**Cost: low-moderate, with one real design constraint.** The environment's keys
are **solver inputs**: `themeMetrics`, `preferredTextOffset`, `viewportRect` and
friends all dirty layout. A consumer key must be structurally incapable of doing
that, so it cannot simply join the same table — it needs a separate,
paint-and-binding-only channel with its own invalidation class. That is the whole
of the work, and it is why this is not a fifteen-minute change.

**Recommendation: defer, with a named trigger** — *the second time a game-side
value is threaded through more than three levels of blueprint function.* One
occurrence is a value that should be a prop. Two is an ambient fact.

#### G-5 — A derivation that owns per-value resources. **DEFER**, trigger below.

**What it is.** Fusion 0.3's `Computed(scope, function(use, scope) … end)` hands
the callback an **inner scope** that lives exactly as long as the value it
produced; when the value is replaced, the old inner scope is cleaned up
automatically [FS-03]. Fusion 0.2's cruder version of the same idea was the
destructor parameter ([FU-06]).

**What LuauUI has instead.** `Core.memo`'s compute receives `use` and nothing
else. A derivation that allocates something releasable has nowhere to put it: you
hoist it to an outer scope and it outlives its value, or you release it by hand.

**Does LuauUI answer it differently?** At a different layer, yes, and well. The
UI-shaped version of this problem is per-item resources in a collection, and
`UI.ForEach`'s `row(item, itemScope)` gives each item a genuine scope disposed
when the item leaves. Asynchronous resources have `newResourceProvider`, with
scope-owned handles and generation-counter rejection of stale completions. So the
cases a UI author hits are covered. It is the *core* contract that is narrower
than Fusion's.

**Cost: moderate, and it is a contract amendment.** Changing `memo`'s compute
signature touches `src/core/contract.luau` and all three implementations, plus the
conformance suite.

**Recommendation: defer, with a named trigger** — *the first memo, in `src/` or in
a consuming game, that owns something releasable.* Worth flagging that
[`ADR-0024`](../adr/ADR-0024-declarative-3d.md) records scope-owned per-item
resources as a declarative-3D truth, so if that build is ever approved, this
trigger fires with it.

#### G-6 — Cross-scope lifetime checking. **DEFER**, trigger below.

**What it is.** Fusion 0.3 checks, at every `use()` and at every property,
attribute and ref binding, that the used object's scope outlives the using
object's, and raises a formatted message naming both [FS-07]. It catches
use-after-dispose at the line where you wrote it.

**What LuauUI has instead.** Ownership, reverse-order idempotent disposal,
double-dispose detection, a releasability check at `own()`, and quarantined
cleanup errors — but no check that a long-lived memo is not reading a
short-lived signal. That failure surfaces later, as a read of a disposed node.

**Cost: moderate.** Every core node would have to know its owning scope, and
today it does not: `scope:own(core:signal(...))` is ownership by insertion into
the scope's array, and the signal itself has no back-reference. Adding one is a
change to the node representation in all three cores.

**Honest note on priority.** Fusion needs this more than LuauUI does. In Fusion
the consumer hand-builds the whole graph, so the mistake is available everywhere.
In LuauUI the framework owns most of the graph, and the places a consumer creates
long-lived derivations over short-lived signals are few.

**Recommendation: defer, with a named trigger** — *the first bug traced to a
use-after-dispose across scopes.* If one arrives, build the check; do not build it
speculatively, because the node-representation change is the kind of broad
refactor `ENGINEERING.md` says should not be folded into feature work.

#### G-7 — Driving arbitrary Roblox instances. **DEFER** — a decision already exists.

Fusion's `New` takes any class name ([FU-07]), so the same graph that runs your
menu can run a `Part`, a `Beam` or a `Sound`. LuauUI renders 21 UI classes and
nothing else.

This is **already decided and does not need re-deciding**:
[`ADR-0024`](../adr/ADR-0024-declarative-3d.md), accepted 2026-08-13, chose a
sibling scene system on the shared reactive kernel — bless the kernel, do not
extract it — with the build waiting for a consumer. Its trigger is the trigger.
Listed here only so a reader comparing the two frameworks does not mistake it for
an unexamined hole.

#### G-8 — `Hydrate`. **DECLINE**, with the route named.

Fusion's `Hydrate` takes an instance you did not create and returns a component
that modifies it ([FU-08]). It is genuinely the best thing on Fusion's side of
this comparison for one specific situation: **you have an existing
Studio-authored screen and you want to make it reactive without rewriting it.**

**Decline, and the reason is the one thing this framework will not trade.** A
hydrated instance has an unknown existing writer — a StyleSheet rule, a legacy
script, the engine's own default. LuauUI's whole property model rests on knowing
that exactly one function writes each property (§2.3), and the measured reason it
rests there is that on this platform a second writer is *silent*: an explicit
write defeats a StyleSheet rule, fires no signal, and the rule never comes back.
A hydration API is a supported way to create that situation, and the framework
would have no way to detect it or report it.

**The route, so this is a decline and not a dead end.** LuauUI's incremental-
adoption story is **per surface, not per property**: mount a LuauUI surface beside
your existing UI, and move screens over one at a time. That works today — it is
what Rascal Rally did, where the LuauUI Sponsor surface is the production default
and the legacy modules stay shipped and untouched behind a flag. Document that as
the migration path; do not build the per-property one.

#### G-9 — Scope poisoning. **DECLINE** — already answered.

Fusion 0.3 replaces a destroyed scope's metatable so any later use raises
[FS-06]. LuauUI asserts on `own()` and `child()` into a disposed scope, which
covers both operations that mutate one, and detects double disposal. Fusion needs
the wider version because a Fusion scope *is* a plain array the consumer indexes
directly; a LuauUI scope is an opaque object with four methods, and there is
nothing else to poison.

#### G-10 — Per-frame instance-write coalescing. **DECLINE** — already answered, better.

Fusion 0.2 coalesces a bound property write to one per resumption step via a
`willUpdate` latch [FS-08]; Fusion 0.3 removed it [FS-10]. LuauUI's answer is
`transaction`, which batches at the *source* rather than at the sink, so the
intermediate derivations do not run either — and the renderer commits once per
flush regardless. Listed so a reader migrating from 0.2 can see that the thing
they were implicitly relying on is not being lost.

---

## 6. What the Fusion adapter revealed that neither framework's documentation says

The rarest output of this exercise. Six findings, each verified in source, each
absent from both projects' written material.

**1. Fusion 0.3 already sorts its observers into node-creation order, for a
reason LuauUI arrived at independently.** `change()` collects the eager nodes it
must evaluate and does
`table.sort(eagerList, function(a, b) return a.createdAt < b.createdAt end)`,
with the comment *"If objects are not executed in order of creations, then
dynamic graphs may experience 'glitches' where nested graph objects see
intermediate values before being destroyed"* [FS-01]. LuauUI's contract added the
same rule — "within one flush, OBSERVERS are notified in node CREATION order" —
on 2026-08-14, for a *different* stated reason: several consumers each watch their
own memo, and table-hash notification order varies run to run, so a surface's
re-solve order would not be reproducible. **Two independent designs converged on
the identical mechanism from two different motivations, and neither one's
documentation mentions the ordering at all.** If you are building a reactive graph
on this platform, treat creation-order notification as a settled requirement
rather than a nicety.

**2. Fusion 0.2 batches instance writes and Fusion 0.3 does not, and no page in
either version says so.** 0.2's `bindProperty` uses a `willUpdate` latch plus
`task.defer`, so a hundred sets in one frame are one property write [FS-08]. 0.3's
is `Observer(scope, value):onBind(function() setProperty(…) end)` — synchronous,
every change [FS-10]. The 0.2 docs say the property updates "on the next
resumption step" ([FU-07]) without saying it coalesces; the 0.3 docs say only that
it "is re-assigned every time the value of the state object changes" ([FU-18])
without saying when. **A 0.2 project migrating to 0.3 with a per-frame-updating
value silently changes from one engine write per frame to one per set.** That is
the most actionable thing in this document for an existing Fusion user, and it is
not in any migration note this research found.

**3. "Fusion is eager" and "Fusion is lazy" are both true, of different
versions, and the adapter's caveat is about neither.** 0.2 recomputes the whole
dependent graph inside `set` [FS-08]. 0.3's Computeds are declared
`timeliness = "lazy"` and recompute on read [FS-03]. The adapter's comment —
"Fusion propagates EAGERLY and has no flush boundary at all" — is precise but
easy to misread: it is about **notification**, not evaluation. Fusion 0.3 is
pull-based *and* has no boundary, which are independent properties. The useful
generalization: **the thing that makes transactions possible is not laziness, it
is having a moment that is not a write.** Fusion has laziness and no such moment;
LuauUI has both.

**4. Fusion's diagnostics are printed, not returned, and that single fact
accounts for four of the adapter's nine red checks.** `logErrorNonFatal` routes to
the external provider's logger [FS-03]. A Computed that throws keeps its old
value, returns "not changed", and the graph never learns. So the adapter's
factory declares `cycleDetection = false` even though **Fusion 0.3 genuinely
detects cycles** — it detects them and then puts the finding somewhere the adapter
cannot read. The distinction that matters for anybody choosing a reactive library
is not *does it detect this* but *can my code ask*. Fusion's answer is no, in both
versions, for every class of error.

**5. Fusion 0.3's infinite-loop guard is a wall clock, not an iteration count.**
`TERMINATION_TIME = 1` second [FS-01]. So a genuine cycle costs a full second of
frozen frame before you are told, the message cannot name the path, and — the
part that matters for a test suite — the guard's behaviour depends on how fast
your machine is. Fusion knows this and exposes `External.safetyTimerMultiplier`
specifically so its own tests can tighten it. LuauUI's equivalent is a hundred
write generations, which is deterministic and therefore assertable. **If you are
writing a reactive core, count rounds, not seconds.**

**6. Fusion 0.2 has no cycle detection at all, and its error catalog proves the
absence.** The documented 0.2 error list runs to thirty-five entries covering
property assignment, handlers, spring parameters, key collisions and destructors,
and contains **nothing** about cycles, infinite loops, yielding, or
non-convergence ([FU-12]) — and the 0.2 source contains no such check. This is not
an oversight to be embarrassed about; a topological update walk terminates on an
acyclic graph and a cyclic one was out of scope. But a 0.2 user should know that a
mutually-recursive `Computed` pair is a hang with no message, and no page tells
them.

---

## 7. Verification appendix

| | |
|---|---|
| LuauUI version | `0.9.0` (`src/init.luau`) |
| Audit date | 2026-08-15 |
| Fusion baseline — documentation | **0.2** as published at `elttob.uk/Fusion/0.2`, read 2026-08-15; **0.3** pages read the same day where cited. Every quote is in §8 with its version tag |
| Fusion baseline — source | **0.2**: `github.com/dphfox/Fusion` at tag `v0.2-beta`, files read verbatim via the GitHub API on 2026-08-15. **0.3**: `vendor/Fusion/` in this repository, whose `init.luau` declares `version = {major = 0, minor = 3, isRelease = true}` |
| LuauUI baseline | Source only: `src/core/`, `src/render/`, `src/layout/`, `src/motion/`, `src/env/`, `src/blueprint.luau`, `src/init.luau`, plus `tests/conformance/` |
| Conformance evidence | `lune run tests/conformance/cli fusion` and `… custom`, both re-run 2026-08-15. Results in `artifacts/conformance-fusion.json` (37/46) and `artifacts/conformance-custom.json` (46/46) |
| Performance evidence | `artifacts/bench.json`, 2026-08-15. **Headless Lune = regression signal only.** No Studio arm and no device arm exists for any number in this document |
| Size figures | `find vendor -name '*.luau'`: 67 files, 5,153 lines. `find src -name '*.luau'`: 122 files, 83,801 lines. Both measured 2026-08-15 |

**Things this document could NOT verify, recorded rather than assumed.**

- **No Fusion project was built for this comparison.** Every Fusion-side claim is
  from its documentation or its source, never from using it in anger. Where a
  framework is pleasant or unpleasant to work in, this document has no standing to
  say so and does not.
- **The 0.2 source claims are read from the `v0.2-beta` tag**, which is the
  release the 0.2 documentation describes. If a 0.2.x patch changed one of them,
  this document would not know.
- **A citation proves a sentence, not a behaviour.** Each §8 quote was taken from
  the page named on the date named. That catches an unsourced claim and a page
  that has since changed; it does not catch a sentence read correctly and
  understood wrongly.
- **The nine red conformance checks measure the adapter, which measures Fusion's
  native semantics by design.** §2.4 states what a thicker adapter could recover
  and what it could not. Do not read them as a claim that Fusion's model cannot be
  wrapped better.
- **No physical-device evidence exists for anything on LuauUI's side**, here or in
  `swiftui-parity.md` §14.

---

## 8. Citations

### 8.1 Fusion's documentation — `[FU-nn]`

Every quote below was read at the URL given, on the date given, at the version
given. Where Fusion's documentation is silent on something this document asserts,
the assertion is sourced to §8.2 instead and says so.

| id | version | page | quoted verbatim | read |
|---|---|---|---|---|
| **FU-01** | 0.2 | `https://elttob.uk/Fusion/0.2/` | "Fusion is a UI, state management and animation library for Roblox." — also the site navigation, whose Cookbook section lists exactly seven recipes: Player List, Animated Computed, Fetch Data From Server, Light & Dark Theme, Button Component, Loading Spinner, Drag & Drop. Rows above that say "the cookbook has a *recipe*" for a capability rest on this listing, not on having read that recipe | 2026-08-15 |
| **FU-02** | 0.2 | `.../api-reference/state/value/` | "Replaces the currently stored value, updating any other state objects that depend on this value object." · "If the new value is the same as the old value, other state objects won't be updated." · "Updates are always sent out when setting a table value" | 2026-08-15 |
| **FU-03** | 0.2 | `.../api-reference/state/computed/` | "Calculates a single value based on the returned values from other state objects." · "Computed objects automatically detect dependencies used inside their callback each time their callback runs." · "When a dependency changes value, the computed object will re-run its callback to generate and cache the current value internally." · "the dependencies will be updated to reduce unnecessary updates" | 2026-08-15 |
| **FU-04** | 0.2 | `.../tutorials/fundamentals/computeds/` | "Fusion can detect any time you call `:get()` on a state object inside the callback. If any of them change value, the callback will be re-run." · "you must return the value immediately" · "For this reason, yielding in computed callbacks is disallowed." | 2026-08-15 |
| **FU-05** | 0.2 | `.../api-reference/state/observer/` | "Observes various updates and events on a given dependency." · "Connects the given callback as a change handler, and returns a function which will disconnect the callback. The callback will run whenever the observed dependency is updated." | 2026-08-15 |
| **FU-06** | 0.2 | `.../tutorials/fundamentals/destructors/` | "Destructors are functions that clean up values passed to them. Computed objects use them to clean up old values when they're no longer needed." | 2026-08-15 |
| **FU-07** | 0.2 | `.../api-reference/instances/new/` | "Given a class name, returns a component which creates instances of that class. The property table may specify properties to set on the instance, or include special keys for more advanced operations." · "Passing a state object to a string key will bind the property value; when the value of the object changes, the property will update to match on the next resumption step." | 2026-08-15 |
| **FU-08** | 0.2 | `.../api-reference/instances/hydrate/` | "Given an instance, returns a component which modifies that instance." | 2026-08-15 |
| **FU-09** | 0.2 | `.../api-reference/animation/spring/` | "Follows the value of another state object, as if linked by a damped spring." · speed: "Scales the time it takes for the spring to move (but does not directly correlate to a duration). Defaults to `10`." · damping: "`0` represents no friction, and `1` is just enough friction to reach the goal without overshooting or oscillating. Defaults to `1`." · "Overwrites the velocity of this spring. This does not have an immediate effect on the position of the spring." | 2026-08-15 |
| **FU-10** | 0.2 | `.../api-reference/animation/tween/` | "Follows the value of another state object, by tweening towards it." · tweenInfo: "The style of tween to use when moving to the goal. Defaults to `TweenInfo.new()`." | 2026-08-15 |
| **FU-11** | 0.2 | `.../tutorials/lists-and-tables/the-for-objects/` | "The `For` objects provide a cleaner way to do the same thing, except with less boilerplate and leaving unchanged values alone" | 2026-08-15 |
| **FU-12** | 0.2 | `.../api-reference/errors/` | **Fusion documents no cycle, infinite-loop, yielding or non-convergence error in 0.2.** The full documented list is 35 ids covering property assignment (`cannotAssignProperty`, `invalidPropertyType`), handlers (`invalidEventHandler`, `invalidChangeHandler`), spring/tween parameters (`invalidSpringDamping`, `mistypedTweenInfo`), key collisions (`forKeysKeyCollision`, `forPairsKeyCollision`), destructors (`destructorNeededComputed` and three siblings) and callback errors. This row is an **absence claim**: the page was read in full and contains no such entry | 2026-08-15 |
| **FU-13** | 0.2 | `.../api-reference/` | The complete documented API surface, in three categories: **State** (`CanBeState`, `Computed`, `cleanup`, `Dependency`, `Dependent`, `doNothing`, `ForKeys`, `ForPairs`, `ForValues`, `Observer`, `StateObject`, `Value`), **Instances** (`Child`, `Children`, `Cleanup`, `Component`, `Hydrate`, `New`, `OnChange`, `OnEvent`, `Out`, `Ref`, `SpecialKey`) and **Animation** (`Animatable`, `Spring`, `Tween`). This row is the **absence claim** behind §4.6: there is no layout, control, focus, theming, accessibility or virtualization entry | 2026-08-15 |
| **FU-14** | 0.2 | `.../examples/cookbook/player-list/` | Fusion's own list example does layout with `New "UIListLayout" { SortOrder = "Name", FillDirection = "Vertical" }` inside `[Children]`, alongside `ForPairs(props.PlayerSet, …)` | 2026-08-15 |
| **FU-15** | 0.2 | `.../tutorials/components/reusing-ui/` | "components are functions which return a child" | 2026-08-15 |
| **FU-16** | 0.3 | `.../tutorials/fundamentals/scopes/` | "When you create many objects at once, you often want to destroy them together later." · "The contents are destroyed in reverse order" | 2026-08-15 |
| **FU-17** | 0.3 | `github.com/dphfox/Fusion/releases` tag `v0.3-beta` (announced August 2024); `wally.run/package/elttob/fusion?version=0.3.0` | Fusion 0.3 is the current release; its announced additions include contextual values, whose motivating example is passing a theme without threading it through every component | 2026-08-15 |
| **FU-18** | 0.3 | `.../api-reference/roblox/members/new/` | "Given a class name, returns a component for constructing instances of that class." · "If the value is a state object, it is re-assigned every time the value of the state object changes." — **and the page states no timing**, which is the silence §6 finding 2 is about | 2026-08-15 |

### 8.2 Fusion's source — `[FS-nn]`

Cited where Fusion's documentation does not make the claim. Pinned to a tag or to
the vendored copy, never to a moving branch.

| id | version | file | what it establishes | read |
|---|---|---|---|---|
| **FS-01** | 0.3 | `vendor/Fusion/Graph/change.luau` | `Value:set` evaluates the target, BFS-invalidates every transitive dependent, then evaluates only `timeliness == "eager"` nodes — sorted by `createdAt`, with the comment about glitches in dynamic graphs. `TERMINATION_TIME = 1` second is the infinite-loop guard, reported as `logError("infiniteLoop")` | 2026-08-15 |
| **FS-02** | 0.3 | `vendor/Fusion/Graph/evaluate.luau`, `State/peek.luau` | Evaluation is on demand: `peek` calls `evaluate(target, false)`, which recomputes only if the node is invalid or a dependency's `lastChange` is newer | 2026-08-15 |
| **FS-03** | 0.3 | `vendor/Fusion/State/Computed.luau` | `class.timeliness = "lazy"`. Each `_evaluate` derives an `_innerScope` passed to the processor, and the previous inner scope is `doCleanup`-ed after the new value is computed. A throwing processor is `xpcall`-ed, reported through `External.logErrorNonFatal("callbackError", …)`, and **returns `false` (not changed)** while keeping the old value | 2026-08-15 |
| **FS-04** | 0.3 | `vendor/Fusion/Graph/Observer.luau` | `class.timeliness = "eager"`; `_evaluate` calls each change listener through `External.doTaskImmediate` | 2026-08-15 |
| **FS-05** | 0.3 | `vendor/Fusion/Utility/isSimilar.luau` | The similarity test returns `false` for any table that is neither frozen nor metatable-bearing — the mechanism behind [FU-02]'s "Updates are always sent out when setting a table value" | 2026-08-15 |
| **FS-06** | 0.3 | `vendor/Fusion/Memory/poisonScope.luau`, `Memory/doCleanup.luau` | A cleaned-up scope's metatable is replaced so any index or assignment raises `"Attempted to use a scope after it's been destroyed"`. `doCleanup` refuses re-entry with `"destroyedTwice"` and iterates the array **backwards** | 2026-08-15 |
| **FS-07** | 0.3 | `vendor/Fusion/Memory/checkLifetime.luau` and its callers in `State/Computed.luau`, `Instances/applyInstanceProps.luau` | `checkLifetime.bOutlivesA` is called on every `use()` inside a Computed and on every bound property, attribute, ref and animation goal | 2026-08-15 |
| **FS-08** | 0.2 | `github.com/dphfox/Fusion` @ `v0.2-beta`: `src/Dependencies/updateAll.lua`, `src/State/Value.lua`, `src/State/Computed.lua`, `src/State/Observer.lua`, `src/Instances/applyInstanceProps.lua` | `Value:set` calls `updateAll`, a two-pass topological walk whose own header states objects "are only ever updated after all of their dependencies are updated, are only ever updated once, and won't be updated if their dependencies are unchanged" — so 0.2 recomputes **eagerly**. `Observer:update` runs listeners via `task.spawn`. `bindProperty` sets a `willUpdate` latch and `task.defer`s the assignment, coalescing many sets into one property write per resumption | 2026-08-15 |
| **FS-09** | 0.3 | `vendor/Fusion/State/Value.luau`, `State/Computed.luau`, `Logging/messages.luau` | `class.get` raises `stateGetWasRemoved`: "`StateObject:get()` has been replaced by `use()` and `peek()`". The 0.3 message catalog contains `infiniteLoop`, `cannotDepend`, `destroyedTwice`, `poisonedScope` and `scopeMissing`, none of which exists in 0.2 | 2026-08-15 |
| **FS-10** | 0.3 | `vendor/Fusion/Instances/applyInstanceProps.luau` | `bindProperty` is `Observer(scope, value):onBind(function() setProperty(instance, property, peek(value)) end)` — **no latch and no defer**, unlike 0.2's [FS-08] | 2026-08-15 |

### 8.3 A note on re-checking

Fusion's documentation is statically rendered, so unlike Apple's it can be
fetched and grepped directly — a quote below can be re-checked with an ordinary
HTTP request. The source citations are the more durable half: pin the tag, read
the file. If a quote in §8.1 no longer appears at its URL, the row above it that
leans on it is due a re-read, and the safest assumption is that the page changed
rather than that this document was wrong.

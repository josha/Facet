# Sipworks and Glade — from browsable apps to played loops

Binding scope: `docs/plans/example-games-and-standalones.md`, "Retire Wardrobe; complete
Sipworks and Glade". Both are **required** showcase scenarios and curated standalone
places. Each standalone imports the same source as its showcase scenario and its
reference validation — no simplified fork.

---

## 1. What is wrong with them today

Neither is broken. Both are large, careful applications with real services behind them:
Sipworks has a catalogue, orders, Steam Stamps, rewards, recipe unlocks, favourites,
localisation and an adaptive nav shell; Glade has five glades with draining supplies, a
commerce path, visitor history and Keeper settings.

The problem is that **neither has a task**.

- **Sipworks** opens on its blend menu inside a four-section nav shell. It is a
  catalogue. A player can browse for a while without discovering that there is a loop
  at all, and the Steam Stamp reward — the thing the app is *about* — is ten orders
  away.
- **Glade** opens on a grid of five glade cards with live-draining supply rings and a
  search field. It is a browser. Nothing says what a wisp is, what it wants, or what
  the player is supposed to do about it.

They also carry proof jargon. `p3_sipworks/init.luau:45` sets
`title = "Sipworks (reference proof RA-P3)"`, and the sibling proofs carry equivalents.
Those `.title` fields are not painted for the player today, but they are exactly the
literals the plan says to purge before these become curated standalone places with
real chrome. (`p4_foyer` and `p5_wardrobe` go further and *do* paint it: "This wing is
a labeled stub in this proof." Wardrobe retires; Foyer's line gets rewritten.)

## 2. Sipworks — serve a customer and earn a reward

### The opening screen

One sentence explaining the tea house, then a compact **Today's order** task with
progress. The catalogue stays underneath it — this is a task placed *on* the app, not
a replacement for it.

> **Sipworks** — a tea house. Pick a blend, serve it, and collect a stamp.
> **Today's order** · one stamp from a free pour · *Choose a blend to begin*

### The loop

Four steps, deterministic, seeded so the lesson does not require ten repetitive orders:

1. **Choose a blend and place a successful order.** The existing catalogue and order
   services; nothing new.
2. **The prepared drink appears and awards the final stamp.** `rewards.new` already
   takes `startEarned` / `startSpent`, and `rewards.THRESHOLD` is 10 — so the
   standalone seeds `startEarned = 9`. One order completes the card. **The seeding is
   the whole design decision here**: the stamp ceremony, the reward, and the free pour
   are the app's best material, and at ten orders a visitor never sees them.
3. **Choose another blend and redeem the free pour.** `rewards.REDEEM_COST` is a flat
   ten; the existing redeem path runs unchanged.
4. **An unmistakable completion state** says what the player accomplished, and offers
   **Serve another customer** — a reset back to the seeded start.

### Failure and recovery

A rejected order explains what happened and how to retry **without losing progress**.
The async accept/reject states already exist; what changes is that a rejection now has
somewhere to return the player to — the task line — rather than leaving them in a
catalogue wondering what happened.

### What stays secondary

The broader catalogue, search, favourites, the Blend Book, localisation, the
compact-link entry and the adaptive navigation all remain, because each teaches
something the task does not. The rule is that the task must stay **visible or quickly
recoverable**, and must always say the next action. Browsing away from it is allowed;
losing it is not.

The stamp animation, the order presentation and the Full/Reduced outcomes must
*support* the task rather than interrupt it — a ceremony the player has to wait out
before they can act is a worse ceremony.

## 3. Glade — prepare a home for a visiting wisp

### The opening screen

> **Glade** — wisps visit glades that have fresh dew and the nectar they like.
> **Prepare this glade:** Fernhollow, for Ember (who likes emberbloom nectar)
> ☐ Refill Fernhollow's dew   ☐ Set out emberbloom nectar
> *Open Fernhollow to begin*

A named glade, a named wisp, two plain progress rows, and a clear first action.

### The loop

1. **Open the named glade and refill its dew** — the existing supply service.
2. **Choose the wisp's preferred nectar** — the existing flora/commerce fixtures.
3. **When both are true, the wisp visibly arrives or brightens**, both rows complete,
   and an unmistakable success state offers **Prepare again**.

The arrival is the payoff, and it is also where the motion lesson attaches to something
the player *wanted* to happen rather than to a demo button.

### Time passing is a recovery path, not a dead end

Glade's supplies drain on a clock. If time advances or supplies run out mid-task, the
task line explains the changed condition — "Fernhollow's dew has dried out again" — and
lets the player recover. That path is played and tested, because a task that can
silently become unsatisfiable is worse than no task.

### What stays secondary

Browsing, search, favourites, the other four glades, visitor history, flora, the
commerce-shaped fixtures and Keeper settings. None of them may hide the task, and none
of them may be required to understand the core loop.

## 4. What both must satisfy

| | |
|---|---|
| **Goal** | stated in one sentence on the opening screen |
| **First action** | named, and reachable without hunting |
| **Progress** | visible at all times, not inferred |
| **Failure** | explained, with a recovery that keeps progress |
| **Success** | unmistakable, and says what was accomplished |
| **Reset** | one control, back to the seeded start |
| **The Facet lesson** | a short optional **What this shows**, *after* the play task, never in place of it |
| **Jargon** | no "reference proof", no stage IDs, no gate language, no capability-ledger codes, anywhere a player can see |

The last row of the plan's bar is the hard one: *the player must understand the goal,
current progress, next action, result, and what Facet adapted **without reading
source***. That is a human judgment (E5) and it cannot be self-certified by the agent
that built it — it goes to a fresh reviewer who plays it.

## 5. Evidence

Both loops are played end to end in Studio on pointer, touch proxy, keyboard and
gamepad, across the device/text/theme matrix — and for Glade, the motion axis too,
because the arrival animates.

Sipworks: paid order → final stamp → free pour → success → reset, plus a rejection and
its retry.
Glade: first action → dew → nectar → arrival → success → reset, plus a depleted
condition and its recovery.

Headless specs carry the deterministic half — the seeded start, each step's state
transition, the end states, the reset returning every observable to its seeded value,
and the drift test that the standalone and the showcase scenario import the same
module. Studio carries what only the real adapter can show.

## 6. Boundaries

Everything above is **example** work: content, seeds, copy, task composition, and which
existing service to call. The services already exist and are not rewritten — the change
is a task surface placed over them and a seed that makes the loop reachable.

Facet owns what it always owns here: the adaptive navigation that turns a sidebar into
a bottom bar, the async accept/reject presentation, the motion the arrival rides, the
theme and text adaptation the matrix sweeps. If either loop needs something those
cannot express, it is a framework gap with a ledger row — not a local helper.

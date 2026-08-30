# A weak-keyed table whose value references its key keeps both forever

Luau's weak tables are **not** ephemerons. If a value in a `__mode = "k"` table
holds a reference to its own key, the entry is never collected — the key is reachable
*through the table's own value*, so the weak reference never becomes the last one.

Measured directly, 2026-08-29 (`tests/_weak.luau`, a throwaway probe):

| 5 000 weak-keyed rows | survive a collection |
|---|---:|
| value holds no back-reference to its key | **0** |
| value references its own key | **5 000** |

That is the whole mechanism. Everything below is what it cost.

## What it cost here

`src/render/surface_overlap.luau` keeps a registry of live paint targets:

```lua
local live: { [any]: { [any]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
```

The outer table is weak-keyed on the target, and its docstring promised the obvious
thing: *"a target that goes away takes its bucket with it… the weak keys are the
backstop."*

The **bucket** was an ordinary table. Each `Entry.snapshot` calls
`controller.coverRect()`, and that controller closes over the very target the bucket is
keyed by. So every registered surface was a strong reference to its own weak key, and
the backstop could never fire.

The consequence is not "a small table leaks". One surface whose `controller.dispose()`
was skipped — an abandoned test fixture, an owner that drops a screen — pinned its
adapter, its renderer, its **entire mounted tree**, and its core, for the life of the
process.

On this repository's own test suite that was:

| | before | after |
|---|---:|---:|
| full suite wall | 1587 s | 256 s |
| peak resident | 14.25 GB | 711 MB |
| an 80-spec subset's live set | 1 284 MB | 12.5 MB |
| cases passing | 7678 | 7678 |

**One line.** `bucket = {}` became
`bucket = setmetatable({}, { __mode = "k" })`.

## Why nothing caught it

- **The suite was green throughout.** Every case passed; the collector simply spent
  nearly the whole run marking a live set that only grew.
- **`mount_unmount_soak` is blind to it by construction.** It censuses adapter
  *handles* — the instance count — and proves those return to baseline. They do. The
  Lua heap is a different quantity and nothing was counting it.
- **A per-spec timing ranking blames the wrong file.** Luau's collector runs where it
  runs, so a heap grown by spec 40 charges its marking cost to whichever case allocates
  next. The existing ranking pointed at whatever happened to run last and found
  nothing, twice.
- **Every spec was fast alone.** 0.01–0.3 s and 25–54 MB each; 300 of them summed to
  195 s. Only the one-process run showed it, and only in wall clock, which reads as
  "the suite has grown" rather than as a defect.

## How it was actually found

1. **Compare the sum of the parts against the whole.** Every spec run alone summed to
   195 s; in one process the same work took 1587 s. That ratio is the signal — it says
   the cost is in what running them *together* does, and nothing else could have said
   it.
2. **Bisect construction against use.** Building a core, an environment, an action
   system, an adapter, a presenter, or a blueprint retains nothing measurable.
   `present` + `dismiss` retains ~5.5 KB per presented node. That narrowed it to one
   verb.
3. **Get a real number out of a noisy one.** `collectgarbage("count")` alone cannot be
   bisected with. Churning the allocator and taking the **low-water mark** turns a
   trend into a figure: 0.56 MB empty → 16.77 MB with 200 k live tables → *exactly*
   0.56 MB after dropping them.
4. **Ballast the candidates.** Attach a 20 000-element table to each suspect at
   construction and watch which one makes per-lap growth jump by ~320 KB. The mounted
   node and the mount root did; the renderer controller and the presenter handle did
   not.

Note that Luau implements only `collectgarbage("count")` — there is no
`collectgarbage("collect")`. The collector is automatic, so a series that keeps
climbing across laps *is* retention, and the low-water instrument is how you read it.

## The rule

**In a weak table, ask what the value can reach.** A `__mode = "k"` table only helps
when the value cannot reach the key. If the value is a record, a closure, or anything
holding a controller, a handle, or a parent, either:

- make the inner container weak too, so the whole cycle collects as a unit; or
- store something that genuinely cannot reach back — an id, a plain number, a frozen
  copy.

And treat "the weak keys are the backstop" in a comment as a claim to be measured, not
a design. This one was written in good faith, was wrong for the entire life of the
module, and cost a fourteen-gigabyte heap.

## Still owed

`src/themes/snapshot.luau` has six module-level `__mode = "k"` tables
(`appRefreshed`, `densityCache`, `resolveMemo`, …) and `src/client/theme_controller.luau`
has one. Any whose value transitively reaches its own key has the identical defect.
Not material at the post-fix live set of 12 MB, and not yet measured.

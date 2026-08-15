# "Stage by name" is not isolation

**2026-08-14.** Ten concurrent agents, one repo. Every brief carried the rule
that had been learned the hard way in round 2:

> NEVER `git reset`, `git checkout .`, `git stash`, or `git add -A` — stage files
> BY NAME.

That rule is necessary and it is **not sufficient**, and this is the failure it
does not prevent.

## What happened

I committed `7990c42` (four architecture-gate findings) and staged exactly the
files I had edited, by name:

```
git add src/render/renderer.luau src/core/contract.luau src/core/custom.luau tests/geometry_solve_coalescing.spec.luau
```

Another agent was concurrently editing **the same `renderer.luau`** for the
`withAnimation` size work. `git add <path>` stages the file's *current working
state* — not "my changes to it". Their uncommitted hunks went into my commit
under my message.

Nothing was lost, and nothing broke: the suite stayed green because both sets of
changes were correct. But the commit claims to be one thing and contains two, the
other agent found their work already committed under someone else's rationale,
and the history now attributes their design decision to my findings.

## Why the obvious defence fails

`git add -A` sweeps *other files*. Staging by name still sweeps *other people's
edits to your file*. The rule everyone was given protects the first case and says
nothing about the second — and with ten agents in one tree, the second is the
common one.

## What actually isolates

In rough order of cost:

1. **Disjoint files.** The only real isolation. When assigning concurrent work,
   partition by file and say so explicitly — "you are in `virtual_list.luau`, the
   other agent is in `table.luau`". Two agents in one file is a scheduling
   decision, not an accident to discover later.
2. **When two agents must share a file, commit small and often.** The exposure
   window is the time between someone else's edit and your `git add`. Minutes
   instead of an hour turns a merged commit into a near-miss.
3. **Check before you stage, not after.** `git diff --stat <file>` immediately
   before `git add` shows the whole diff you are about to take. If it is bigger
   than what you wrote, someone else is in there.
4. **A worktree** (`isolation: "worktree"`) for genuinely independent work. Costs
   setup and a merge; buys real separation.

## The rule, corrected

> Stage by name, **and check what that name currently contains.** If another
> agent is live in the same file, either partition first or accept that whoever
> commits is committing both.

Recording it because the wrong version of this rule was written into roughly ten
agent briefs in one session, each one confidently — a rule repeated often enough
to feel proven, while the case it misses was happening.

## Addendum, same day: `git commit -- <pathspec>` does not escape it either

The presenter split hit this a second time, while deliberately trying to avoid
it. The index had four other agents' files staged in it, so instead of
`git add` + `git commit` I used the pathspec form:

```
git commit -F - -- src/present/presenter.luau src/present/text_reveal.luau tools/check_source_size.py
```

That form correctly ignored everything else in the index — the renderer agent's
staged `layout_node.luau` and specs were left exactly where they were, which is
what it is for. But `git commit -- <path>` commits **that path's current
working-tree content**, which is the same substitution `git add <path>` makes.
`tools/check_source_size.py` is the shared scoreboard every split agent edits,
the solver agent had just written its `FOURTH ROW CLEARED` paragraph into it,
and that paragraph went out under the presenter commit's message.

So the corrected rule above applies to **every** command that names a path, not
just `git add`. The check is the same one and it is cheap:

```
git diff --stat <path>   # or: git diff <path> | grep '^[+-]' | grep -v '^[+-][+-]'
```

immediately before committing — if the hunks are not the ones you wrote,
someone else is in that file. The presenter agent ran exactly that check before
its FIRST commit (clean, and it committed cleanly) and skipped it before the
second, in the ~4 minutes it took to write the message. That gap is the whole
exposure window.

And the deeper point: the SHARED FILE is the one to watch, not your own. Both
`src/present/*` paths in that commit were private to one agent and perfectly
isolated. The file that leaked was the one the mission brief told four agents
to edit — a scoreboard is a shared mutable, and a scoreboard everyone must
update at every step is a collision scheduled in advance.

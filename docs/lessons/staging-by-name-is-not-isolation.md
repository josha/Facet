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

## Third occurrence, 2026-08-15: the check is necessary and STILL not sufficient

The focus-graph agent did everything this file asks. Before committing it ran

```
git diff --cached --stat
```

and read back **only its own 11 files**. Then it committed — and `4ba1a6d`
came out carrying `src/mount.luau`, `tests/mount.spec.luau` and
`tests/transitions.spec.luau`, which belonged to the `UI.When` agent. Nothing
was lost and HEAD was green, but a second agent again found its work already
in history under someone else's message and rationale.

The check did not fail. **The window moved.** Every version of the rule in this
file — including the corrected one — implicitly assumes the dangerous interval
is *edit → stage*. It is not. With N agents sharing one index the interval that
matters is:

> **check → commit**

and that gap is filled by exactly the things a careful agent does between them:
composing a commit message, re-reading a diff, writing a report. The more
conscientious the agent, the wider its own exposure window. That is the part
that makes this failure keep recurring despite everyone knowing the rule.

**The rule, corrected again:**

> Stage and commit as **one uninterrupted step**. Write the commit message
> *first*, then check, then commit immediately — `git commit -F <file> -- <paths>`
> in a single call. Never review, go away and compose prose, and come back to
> commit.

And the structural note, since three occurrences in one week is a design signal
rather than three lapses: **a shared index is shared mutable state, and the
staging rules are a lock protocol implemented in etiquette.** Etiquette does not
hold under concurrency. When work is genuinely independent, the fix is not a
better rule — it is `isolation: "worktree"`, which costs setup and a merge and
buys an index nobody else can write. The three incidents this week were all in
concurrent agents that could have been given one.

---

## Round 4 (2026-08-15): two more ways to hit this, neither of them staging

The time-based-easing agent hit the same class twice more, and neither instance
was a `git add`. Recorded here rather than in a new file because it is the same
root cause — a shared working tree treated as private — wearing different hats.

### 4a. Editing by PATTERN is the same failure, before git is involved at all

Renaming my own ADR number, I ran:

```
grep -rln "ADR-0031" src/ tests/ | xargs sed -i '' 's/ADR-0031/ADR-0033/g'
```

That is a whole-*repo* edit wearing the costume of a whole-*file* edit. **Thirteen
files belonging to three other agents** carried `ADR-0031` for their own reasons
(the `UI.Foreign` work legitimately owns that number), and every one of them was
silently rewritten. No git command had run yet. The staging rules cannot help
here, because the damage is in the working tree before anything is staged.

It was caught only because the harness echoed the file list. Had I piped
`grep -l` straight into `xargs` without looking, the corruption would have gone
into someone else's commit an hour later, in a file I never opened.

**The rule:** a `sed`/`xargs` across a path glob is an edit to every file it
matches, and in a shared tree you own none of them. Enumerate the files you own
**explicitly** and loop over that list — never over a search result. If the search
is what tells you which files to touch, you have just discovered that you do not
know what you own.

### 4b. A stale index entry makes `git diff --cached` lie about *their* work

Another agent committed with `git commit -- <paths>`. That is a partial commit:
it commits from the working tree and **leaves the index entry for those paths
untouched**, still pointing at the pre-commit blob. HEAD moved; the index did not.

The next agent to run `git diff --cached` — me — saw this:

```
examples/gallery/scenarios/branch_scope.luau   | 288 ----------
examples/gallery/scenarios/sorted_entries.luau | 310 ----------
tests/sorted_entries.spec.luau                 | 326 ----------
```

**Phantom deletions of work that had just landed.** Committing at that moment
would have reverted three files of another agent's completed feature, in a commit
whose message was about easing. The staged diff is the last line of defence and
it was showing a change I had not made and did not want — so "read the staged
diff before committing" caught it only because the deletions were too large to
miss. A one-line phantom revert would have sailed through.

Worse, the obvious repair is a trap. `git add <those paths>` makes the index match
the working tree — but the working tree is *live*, and in the seconds between my
`git diff HEAD` (which showed them clean) and my `git add`, two concurrent agents
wrote to four of those files. The `add` swept their in-flight, half-finished work
into my index.

**The repair that is actually safe**, because it never reads the working tree:

```
info=$(git ls-tree HEAD -- "$p" | awk '{print $1","$3}')
git update-index --cacheinfo "$info,$p"
```

That resets *the index entry* for one path to its HEAD blob and leaves the file on
disk alone — the surgical form of the `git reset <path>` the rules forbid, and the
one the rules should have named all along.

**And the ordering that closes the race:** `git commit` with no pathspec commits
**the index**, so once the index is verified correct a later working-tree write
cannot contaminate it. `git commit -- <paths>` commits the **working tree** for
those paths and re-opens the whole exposure window. Prefer the former; the latter
is what created this incident in the first place.

### The pattern under all four rounds

Every round has been a different mechanism and the same mistaken belief: **that
naming a thing (a file, a pattern, a path) scopes the operation to my work.** It
scopes it to a *location*. In a shared tree, location and ownership are unrelated,
and every tool git gives you — `add`, `commit -- <path>`, `diff --cached` — reports
on the location. The only operations that are genuinely scoped to your changes are
hunk-level ones (`git apply --cached` with a filtered patch) and the only thing
that makes location and ownership coincide again is a worktree of your own.

---

## Round 5 (2026-08-15): the fix is a private index, and it is cheaper than a worktree

The paragraph immediately above is the conclusion this round **corrects**. It said
the only structural fix was `isolation: "worktree"`. There is a better one, it
costs no setup and no merge, and it is now a script:

```
tools/commit_isolated.py -m <message-file> <path>[:marker,marker] ...
```

### What it does

`GIT_INDEX_FILE` makes the index a **parameter**, not a singleton. Seed a private
one from HEAD, apply only your own hunks to it with `git apply --cached`, write
the tree, `commit-tree` it, and advance the branch with `git update-ref <ref>
<new> <old>` — a compare-and-swap. `.git/index`, the shared mutable every other
agent is also writing, is never touched for staging. The working tree is never
modified: no reset, no checkout, no stash, no `add -A`.

That closes the round-3 failure **structurally**. Round 3's window was
`check → commit`, and it was filled by composing a commit message. Here the
message is written *before* the tool runs and staging-plus-committing is one
process invocation with no interval inside it for anyone to land in.

### Why this beats a worktree for this workload

A worktree buys a private index *and* a private working tree, and charges setup, a
second checkout, and a merge back. Almost every collision in rounds 1–4 was a
**staging** collision, not an editing one: the agents were editing different parts
of shared files quite happily and only destroyed each other at commit time. A
private index is the half that was actually needed. Reach for a worktree when
agents genuinely need different *file contents* on disk at the same time — which
is a rarer situation than this file's earlier rounds assumed.

### The hole this introduced, which was measured, not reasoned

A commit made this way moves HEAD **without updating the shared index**, and that
is not cosmetic. In a scratch repo, with the index left stale:

```
me:      commit A.txt = "mine v2"   (private index, update-ref)
them:    git commit                  (ordinary, from the stale shared index)
result:  git show HEAD:A.txt  ->  "mine v1"      <- SILENTLY REVERTED
```

Their commit writes the index as a tree, and their index still held the
pre-commit blob for my path. Green tests, clean status, my work gone.

**This already happened here.** Round 4b above — the phantom staged deletions of
`branch_scope.luau`, `sorted_entries.luau` and `tests/sorted_entries.spec.luau`
that nearly went out in an easing commit — was *this* hole, caused by the first
three private-index commits of this very round. Round 4b diagnosed it as a
property of `git commit -- <pathspec>`; it is the general property of **any commit
that does not refresh the index**, and a private-index commit is one of those.

So the republish is mandatory and the script does it, using round 4b's own repair:

```
info=$(git ls-tree <my-commit> -- "$p" | awk '{print $1","$3}')
git update-index --cacheinfo "$info,$p"
```

It reads no working-tree bytes, so it cannot sweep anyone's in-flight edits. Where
another agent had *staged* content at one of those paths, republishing returns
their staging to unstaged — their file on disk is untouched and they simply
re-stage — and the script prints a `NOTE` naming the path rather than doing it
quietly. Left alone, that same entry would have reverted the commit instead.

`tools/commit_isolated.py --repair <path>...` is the standalone form, for when you
find phantom deletions in `git diff --cached` and want round 4b's fix without
looking it up.

### One correction to round 4b's advice

Round 4b ends "prefer `git commit` with no pathspec, because once the index is
verified correct a later working-tree write cannot contaminate it." That is right
about *contamination* and wrong as a default in a tree where anyone is committing
without refreshing the index — a bare `git commit` is precisely the command that
turns a stale index into a silent revert. Verify the index against HEAD first
(`git diff --cached --stat` empty, or `--repair` the paths), *then* the advice
holds.

### The hole that is still open, named

**Hunk granularity.** `git diff` merges nearby edits into one hunk, so if another
agent's change lands within the context window of yours, a marker match takes
both and the script cannot tell. It diffs at `-U1` to make that window one line
instead of three, and it writes the exact committed bytes to a `patch:` file so
the claim is auditable afterwards — but it does not close it. Two agents inside
the same few lines are not separated by anything short of a worktree.

Everything else is closed: the private index cannot be swept or destroyed; the
compare-and-swap makes a genuine race a loud exit-3 rather than a clobber (a
commit landing between the read and the update-ref fails with `is at X but
expected Y`, and the working tree is untouched so a re-run is free); the
republish removes the stale-index revert. `commit-tree` bypasses pre-commit and
commit-msg hooks — this repo has none, and a repo that has them must run them
itself.

### The rule, corrected a fourth time

> Do not stage into the shared index at all. Write the message first, then
> `tools/commit_isolated.py -m <msg> <paths...>` — private index, hunk-filtered,
> compare-and-swapped, index republished — and read its `drop` lines, which are
> the claim you are making about what is not yours.

### 4c. The root cause of 4a was not the `sed` — it was an identifier assigned from stale knowledge

Worth separating, because fixing the wrong one of these fixes nothing.

The `sed` in 4a existed only because I had to *renumber an ADR mid-mission*. The
orchestrator assigned ADR numbers in three separate messages — 0031, then 0032,
then 0033 — while ADR files were landing concurrently from other agents. Every
instruction was **already stale when it arrived**: by the time "take 0031" reached
me, 0031 had been claimed on disk by the `UI.Foreign` work. The final numbering
settled at 0030 focus / 0032 nested-instance-tree / 0033 easing / 0034 foreign,
and no agent's original assignment survived.

So the sequence was: a number is assigned out of band → it is stale on arrival →
the agent must rename its own citations → the rename is a cross-cutting text edit
→ the cross-cutting text edit hits files the agent does not own. **The dangerous
operation was manufactured by the coordination protocol, not chosen.**

**The rule:** an identifier drawn from a shared namespace — an ADR number, a
migration number, a port, a table name — must be **claimed by creating the artifact
on disk**, not by being told a value. Create `docs/adr/ADR-00NN-<slug>.md` as an
empty stub in your first minutes, `ls docs/adr/` immediately before you commit, and
if the stub collided, renumber then — while the only citations are your own and
still in one file. An agent told a number is holding a value that was true when it
was sent; an agent holding a file is holding the namespace.

And the corollary for whoever is orchestrating: **do not hand out identifiers from
a namespace concurrent agents are writing into.** Telling three agents three
numbers across three messages does not serialise them; it just moves the collision
to whichever one reads last, and hands each of them a rename to perform in a shared
tree.

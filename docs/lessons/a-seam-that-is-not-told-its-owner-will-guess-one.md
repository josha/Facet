# A seam that is not told its owner will guess one

**Found 2026-08-17, root-causing NM-H4a: the HUD paint latch.**

`adapter.adopt(handle, newPath, newClass, hint)` handed a pooled GuiObject a new
identity. It was told the new path, the new class and the decoration hint — and
**not the surface it was adopting for**. But adopting means re-parenting, and a
parent is a surface fact. So the adapter answered it from a module-scope local
holding the root of the last `create` on that adapter, whichever surface that
create belonged to.

One adapter serves every surface a presenter puts on it. The gallery runs a
backdrop, a chrome bar, a scenario and whatever that scenario presents — four
ScreenGuis on one `screen_target`. So "the last root that created something" was
the right answer only by luck of ordering, and when the luck ran out a node was
re-parented into another surface's ScreenGui.

## Why it is the worst possible failure mode

The node keeps its rect, its ZIndex, its properties and `Visible = true`. Only
its `Parent` is wrong. So:

- every model-side check agrees with itself;
- the property probe reads the right numbers off the right instance;
- `adapter.getInstance(path)` still answers, because that map is keyed by path;
- and when the foreign surface is later disabled or destroyed, the instance is
  nowhere while **writes to it are still silently accepted** — the renderer goes
  on setting rects and visibility on an orphan and nothing errors.

Partial, permanent, and invisible to everything except a question nobody asked.
288 headless replays, 144 ordered viewport pairs and 36 live Studio combinations
all diverged by zero against a screen that was visibly broken.

## The rule

**If a seam performs an action whose correctness depends on WHO is asking, the
caller passes the owner. It is never recovered from ambient state.** A
module-scope "last one wins" is a guess wearing a variable name, and it is right
often enough to ship.

The corollary for test doubles: a fake target that does not model a fact cannot
disagree about it. `fake_target` had no parent model at all, so no headless spec
could have caught this however many were written. **When a defect turns out to
live in a fact the double does not represent, the fix is two changes — the
product's, and the double's.** The double's is the one that keeps it fixed.

## The audit that catches the whole class, from any VM

`buildHandle` writes `instance.Name = path` and `adopt` writes
`instance.Name = newPath`, so every GuiObject carries the node path it believes
it is. A node whose path names one surface while its ancestor ScreenGui is
another **is** the defect — no framework handle needed:

```lua
for _, gui in playerGui:GetChildren() do
    if gui:IsA("ScreenGui") and string.sub(gui.Name, 1, 7) == "LuauUI_" then
        local screenId = string.sub(gui.Name, 8)
        for _, d in gui:GetDescendants() do
            if d:IsA("GuiObject") and string.sub(d.Name, 1, 1) == "/" then
                assert(string.match(d.Name, "^/([^/]+)") == screenId)
            end
        end
    end
end
```

Prove it fires before trusting a zero: build two roots on one real adapter, adopt
with the wrong one, and watch it report exactly one. An audit that has never
fired is a comment.

See `artifacts/navigation-and-menus/h4a-root-cause.md` for the full ledger, and
[`a-per-path-cache-outlives-the-node-it-remembers.md`](a-per-path-cache-outlives-the-node-it-remembers.md)
for the neighbouring class: state keyed to a path that survives the path.

# A synthesized activate must carry the pointer kind

**Found:** 2026-08-13, by reading `Table`'s new touch branch against every caller
that can reach it. **Status: RECORDED, NOT FIXED** — the fix is adapter-side and is
owed by whoever next touches `screen_target`'s minimum-target work. See
`docs/plans/swiftui-parity-round2.md` §3.4.1 "Owed, not fixed here".

## The defect

`src/client/screen_target.luau:3312` — the 44px minimum-target hit expander:

```lua
expander.Activated:Connect(function()
    if handle.activate ~= nil and handle.instance.Interactable ~= false and handle.instance.Visible then
        handle.activate({ source = "hitExpander" })
    end
end)
```

The meta names its **source** and nothing else. It carries **no `pointer` field**,
even though `Activated` fires for a finger and a mouse alike and the adapter knows
which one opened the capture.

## Why that is not harmless

Every control that adapts its semantics per input reads `meta.pointer`, and the
idiomatic shape of that read treats *absent meta* as touch — because a bare mount
with no adapter genuinely is the touch case. `src/controls/table.luau`:

```lua
if meta == nil or meta.pointer == "touch" then
    -- Apple's rule: a plain tap OPENS; edit mode is the selection mode
```

A meta that **exists but is silent** satisfies neither half, so it falls through to
the mouse branch — `api.select(rowKey, { mode = "replace" })`, and the primary
action only on a second press inside the 500 ms double-click window. So a finger
landing in the *overhang* of a row shorter than 44px **replace-selects instead of
opening**: the exact inverse of the rule, chosen by an omission three files away.

`{ source = "hitExpander" }` is worse than `nil` here. `nil` would have been right.

## Reproduction

A `Table` with `selection = "single"|"multi"`, an `onPrimaryAction`, and a
`rowHeight` under 44. Tap inside the expanded band rather than on the row itself.

**Practical exposure is small today** — sibling row buttons occlude most of the
overhang, and RascalRally's only `newTable` is single-select with no primary
action, so both branches do the same thing there. Small exposure is why it is
recorded rather than rushed; it is not why it is acceptable.

## The fix direction, and the one to avoid

**Do:** carry the originating pointer kind into the expander's meta, adapter-side.
The expander is a real `TextButton` under the same input stack as the host, so the
kind is knowable at the moment `Activated` fires.

**Do not:** teach each control to treat a missing `pointer` as touch. The control's
"no meta means touch" default is deliberate and correct for a bare mount; widening
it to absorb an adapter's omission makes every future omission invisible instead of
one of them wrong.

## The general rule

**An adapter that synthesizes an activate owes the same meta a real one carries.**
A partial meta is not a smaller truth than no meta — it is a *different* one, and
it silently defeats exactly the `meta == nil` fallbacks written to catch its
absence. When adding a new synthetic input path, list the fields the genuine path
fills and justify every one you leave out.

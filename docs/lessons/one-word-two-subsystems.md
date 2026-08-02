# One word, two subsystems — and only one of them was listening

**Found:** 2026-07-26, iPhone 15 Pro, showcase place. **Cost:** two director
rounds and a defect that looked like a *theme* bug in two unrelated themes.

## The symptom

The playlist demo's five star buttons declared `surface = "plain"`, which is the
library's own way of saying "paint nothing behind this".

* Under **Glossy Touch** the rating rendered as five glossy **pills**.
* Under **Glossy Mobile** — whose `control` recipe is `{ kind = "native",
  shadow = "raised" }` — each star grew a drop **shadow**, and five overlapping
  shadows read as a smeared dark band behind the row. The director's words were
  "the blur behind all the stars looks bad".

Two very different themes, two very different artefacts, one cause. That pattern
— *the same declaration failing differently everywhere* — is the tell.

## The cause

`surface = "plain"` was honoured by the **native paint** path and ignored by the
**decoration** path.

```lua
-- src/client/screen_target.luau — the native path DID listen
handle.nativeSurface = if surface == "plain" then nil else surface

-- src/tokens/chrome_slots.luau — the decoration path did NOT
if CONTROL_SURFACES[surface or ""] or CONTROL_CLASSES[class or ""] then
    return "control"     -- CONTROL_CLASSES = { Button = true, Toggle = true }
end
```

The classifier fell through to the **class**, and every Button is a control. So
the tag came off (no sheet fill) while the package's `control` recipe was still
materialized on the node — art, shadow and all.

## Why nothing caught it

Both subsystems had tests and both passed, because each was tested against its
own idea of what the word meant. Nothing tested that the two ideas were the
*same* idea. A property with two readers needs a test that pins them **to each
other**, not two tests that pin them separately:

```lua
expect(chrome_slots.classify({ class = "Button" })).toBe("control")
expect(chrome_slots.classify({ class = "Button", surface = "plain" })).toBeNil()
```

## The rule

**A public word that more than one subsystem reads has exactly one meaning, and
something must assert that.** When you add a reader for an existing property, the
first test to write is not "does my reader work" — it is "does my reader agree
with the reader that was already there".

Corollary, specific to this codebase: a `classify`-style function that falls back
to a broad default (class, kind, category) must check the **explicit opt-out**
before the fallback. A fallback that outranks an explicit declaration is not a
default, it is an override.

## See also

- [`a-fixed-box-cannot-hold-a-themes-frame.md`](a-fixed-box-cannot-hold-a-themes-frame.md)
  — the other half of the same device round.
- `docs/lessons/decoration-paints-to-the-edges.md` — the earlier instance of the
  same family: a policy string nothing read.

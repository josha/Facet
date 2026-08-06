# Image lifecycle for windowed lists — what already exists, and what does not

Answering a direct question: *don't load images that aren't visible, make sure they're
loaded just before they become visible so there's no pop, hold them briefly after they
leave, then drop them.* Is that viable?

**Two of the three already work. The third does not exist and is the real proposal.**

## 1. "Don't load anything off-screen" — already true

A `VirtualList` only materialises rows inside its window. A row that does not exist has
no cell, no `newAsyncImage` handle and no request. Nothing off-screen is ever asked for,
because nothing off-screen is ever built.

## 2. "Make sure it's loaded just before it becomes visible" — already true

That is what `overscan` is. The lab runs `overscan = 2`, so two rows beyond each edge are
materialised — and therefore requested — before they are on screen. The pop this is meant
to prevent is already prevented, and the knob to tune it (more overscan = earlier load =
more mounted rows) already exists.

## 3. "Hold it briefly after it leaves, then drop it" — **does not exist**

`resources.releaseState` disposes the entry the moment the last handle releases it:

```lua
entry.refs -= 1
if entry.refs <= 0 then
    entry.state:dispose()
    entry.value:dispose()
    entry.error:dispose()
    keyState[key] = nil
end
```

A row that scrolls one row off the bottom and straight back re-requests its image from
scratch. Measured on `async-image-churn` (2 000 rows): scrolling away and back moved
`dropped` from 86 → 106 → 128 — roughly 22 discarded requests per fling step — while the
provider's `cached` count stayed flat at 7.

### The proposal, concretely

A **grace period** in `resources`: on the last release, do not dispose. Move the entry to
a bounded LRU of completed values and dispose it only when it is evicted or a timer
expires. A re-acquire within that window is a cache hit with no request at all.

Bounded by entry count rather than time is probably better here: a fling can retire
hundreds of rows in a second, and a time-based hold would keep whatever that second
happened to contain.

### Before building it — what makes this uncertain

**The engine already caches decoded content.** Re-setting the same `Image` string on an
`ImageLabel` is not a fresh download; Roblox keeps the decoded texture. So the saving is
the LuauUI-side request/handle/generation round trip and the `PreloadAsync` call, **not**
the image fetch itself. That may be a small number.

**Instance recycling now covers part of the same ground.** A recycled row keeps its
`ImageLabel`, and with the property diff its `Image` property is only rewritten when it
actually differs — so a row scrolling back to the same content may already skip the write
entirely.

**So the honest position is: viable, cheap to build, and not yet shown to be worth it.**
The measurement that would settle it is one number — the wall-clock cost of a re-acquire
that hits the engine's cache versus one served from a LuauUI-side hold — and it is worth
taking before writing the LRU rather than after.

## Recommendation

Measure first. If a re-acquire on a warm engine cache costs materially more than a hold
would, build the bounded LRU; if it is noise, the two mechanisms already in place
(windowing plus overscan plus recycling) are the whole answer and the third piece is not
worth the moving part.

# Release-candidate reactive-runtime review (fresh-context verifier, 2026-08-17)

Reviewed at commit b230b87. Stored verbatim by the controller from the
verifier's returned compact report (stub has no file-write tool).

[REACTIVE-REVIEW]: CONCERNS

RR-1 | High | High | src/core/custom.luau:136-140 | Memo failing on its FIRST evaluation keeps an empty dep set (swap is success-only), so it is permanently nil and never recomputes.
RR-2 | High | High | src/core/custom.luau:160-166 | runEffect re-subscribes an effect that disposed itself (or its scope) during its own run; record stays in dep.subs forever while counters read clean.
RR-3 | Medium | High | src/core/custom.luau:104-105 | Node.name is never set anywhere, so every cycle diagnostic prints "memo -> memo -> memo"; the promised cycle path is unusable.
RR-4 | Medium | High | src/core/custom.luau:187-188,136-140 | Illegal write-during-memo on first evaluation permanently kills that memo (same root cause as RR-1), not just the current pass.
RR-5 | Medium | Medium | src/controls/*.luau (25 sites, e.g. virtual_list.luau:3295, table.luau:1723) | Memos returning fresh `{...}` with default identity eq notify on every recompute, re-dirtying measure/arrange for unchanged values.
RR-6 | Medium | High | src/client/roblox_env.luau:228-229 | Keyboard-occlusion connection is gated on `UserInputService.OnScreenKeyboardVisible` at attach, so on device it is never made and keyboardOcclusionRect never updates.
RR-7 | Low | High | src/core/custom.luau:451-475 | Disposing a memo/signal clears node.subs, silently freezing every downstream memo forever with no diagnostic.
RR-8 | Low | High | src/core/custom.luau:95-142 | Memo chains deeper than ~190 blow the Lua call budget inside pull's pcall; the chain degrades to nil silently and permanently (measured at depth 200).
RR-9 | Low | High | src/core/custom.luau:409-431 | A settle callback that never converges is re-run to the 100-round cap on EVERY later flush in the session; it is never quarantined after tripping the cap.
RR-10 | Low | High | src/core/custom.luau:547-552 | observe()'s baseline pull swallows a cycle error without calling fail(), so that quarantine never reaches lastError.
RR-11 | Low | High | src/core/custom.luau:378 | Feedback cap is off by one (`rounds <= 100` permits 101 rounds); measured runaway effect reached 101.
RR-12 | Low | Medium | src/core/custom.luau:227-247,319-332 | Per-flush allocation is unavoidable (snapshot+sort per notified node, 3 tables per round, closure+deps per pull): ~61 B/flush minimal, ~491 B/flush at 50 memos.
RR-13 | Low | Medium | src/core/custom.luau:115-119 | A `use` captured out of a compute and called later mutates node.deps without a matching dep.subs entry, producing a dep the node is not subscribed to.
RR-14 | Low | Medium | src/core/custom.luau:175-184,204-221 | markMemosStale/collect are recursive over graph depth; a deep or wide graph risks stack exhaustion inside the flush rather than a bounded error.
RR-15 | Low | Medium | src/core/custom.luau:337-352 | An observer that writes mid-round is visible to later pulls in the SAME round, so nodes notified after it see a newer state than nodes notified before it.

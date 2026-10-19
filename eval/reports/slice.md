# FacetBench slice

This record holds one run per arm on the racing-hub slice, seed 1, with
`eval/slice.json`. Both arms use Claude Opus 5.5 (`claude-opus-5-5`) at medium
effort through the Claude Code CLI, the same wall budget of 3,600 seconds, the
same scoped Studio MCP tools and the same disallowed tools (web search, web
fetch and subagents). The Facet arm also receives the Facet author kit.

One seed per arm does not establish a general quality, cost or speed claim.
The Plain run is reused from an earlier fresh run with the same starter, brief
and checks; the Facet run is fresh on the kit of Facet at the merge of
josha/Facet#147.

## Results

| Measure | Plain | Facet |
| --- | --- | --- |
| Run status | completed | completed, passed |
| Agent wall time | 1,147 s | 2,007 s |
| Total tokens | 16.8M | 14.4M |
| Output tokens | 114,803 | 68,017 |
| Cost | $7.44 | $5.98 |
| Universal checks, desktop | 0% | 100% |
| Universal checks, phone portrait | 0% | 100% |
| Spec checks | 61% | 67% |
| Mount, desktop | 6.2 s | 2.2 s |
| Mount, phone portrait | 2.2 s | 2.2 s |
| Reads of Facet or tool source | n/a | 3 (the Verify audit) |

The Facet agent spent 851 seconds in the model and 1,155 seconds in tools,
mostly `verify` sweeps and Studio checks.

## Screenshot judge

The judge compares the captures of both arms on each device. It chose Plain on
desktop (confidence 0.88) and on phone portrait (confidence 0.62).

- Desktop: Plain has a stronger neon identity, a nine-item shop grid with
  currency icons and shortfall lines, and dock tiles with status. Facet has a
  flat look, a shop that shows about two cards in a short scroll area, a faint
  HUD, small text and empty panel space.
- Phone portrait: the judge credits Facet with larger touch targets, panel
  tabs and shortfall text, and faults its HUD for stale values (0 Coins and
  `LV --` while the panels show the wallet) and its slightly clipped cards.

## Places

- [Plain](places/racing-hub-slice-plain.rbxl)
- [Facet](places/racing-hub-slice-facet.rbxl)

Each place is built from the arm's final workspace with Rojo.

## Hill-climbing opportunities

Each item names a Facet, tool or eval change that the run evidence supports.

1. **Buy stays enabled when the player cannot pay.** `Tasks.shop` disables
   Buy for an unaffordable item. The brief asks the server to refuse and name
   the missing currency, and six spec cases tap Buy on such items. Keep Buy
   enabled, show the shortfall in the caption and show the server's reason.
2. **Focus ring on console.** `focus-hidden` reports the HUD dock buttons
   after every console sweep, in one Composition and one ScreenGui. Reproduce
   the selection image state in Studio and fix the ring.
3. **Modal backdrop and covered actions.** With a Sheet open, the audit
   reports the HUD buttons under the modal backdrop as `action-covered`, and
   one spec case fails because Quests is covered. Decide whether controls
   under an active modal backdrop count as covered, and teach the recipe to
   close the Sheet before the next dock action.
4. **Collections in a hug panel.** A VirtualGrid or VirtualList inside a
   Sheet with a `hug` detent takes all the height, so the agent set fixed
   heights and the desktop shop showed about two cards. Size virtual
   collections to their items in a hug container.
5. **Exit motion in captures.** A capture right after Close can catch the exit
   transition and report a backdrop finding. Wait for exit motion to settle.
6. **Live HUD state.** The phone HUD showed placeholder values. Show in
   `Tasks.hud` how the first server state and each change set the HUD cells.
7. **Exact wording.** Spec cases look for brief text such as
   "Buy for 10 Gems", "+5/s" and "Ends in M:SS". Put the brief's exact
   product words in the recipes and panel examples.
8. **Visual identity.** The judge still prefers Plain's look. Give the theme
   recipe currency icons, glow strokes on primary actions, dock status tiles
   and larger HUD numbers, and size short panels to their content while Close
   keeps one place.
9. **Speed.** Cold `lint --types` takes about 15 seconds because Facet has
   about 380 new-solver errors of its own. A five-device sweep takes about a
   minute. Fix the new-solver errors, make repeat sweeps incremental, and move
   geometry checks into a layout solver in the engine double.

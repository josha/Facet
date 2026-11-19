# Review.hud

Review rules for a HUD `Composition`.

| Rule | Finds |
|---|---|
| `composition-unfit` | A Composition whose regions do not fit its size now, or a 358 by 812 or 812 by 358 phone with touch controls. The detail names the regions. |
| `worded-command` | A Button in a Composition region whose text is a standard command or a destination that players know, such as Settings, Menu, Shop, Inventory or Lifetime Stats. Medium. The detail names the icon to use. A Button in a Sheet, Dialog or page does not count. |
| `top-row-stacked` | A Composition whose top-center regions sit below a corner region, because the top row has no room beside it. Medium. Every region below them moves down too; compact status and commands belong in `zone = "topbar"`. |

Back to [Review](Review.md).

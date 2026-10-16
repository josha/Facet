### Instances you hand to a presenter

<!-- aliases: Instances you hand to a presenter | instances-you-hand-to-a-presenter -->

Instances-you-hand-to-a-presenter contract and option values.

A Sheet (`content`, `header`, `hero.content`), DisclosureGroup, CollapsibleView,
Callout and NavigationStack destination accept an Instance as well as a
factory. The presenter parents that Instance while it is shown and detaches it
(`Parent = nil`) before the surface is destroyed, also on the final unmount, so
the same Instance can be shown again. The game owns it: destroy it, and
disconnect what you connected to it, when you no longer need it. A factory
builds a fresh Instance each time and needs nothing.

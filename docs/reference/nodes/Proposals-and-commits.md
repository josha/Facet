#### Proposals and commits

The colour belongs to you. Each change sends a proposal to `onChange`. The
control shows only the colour that you then hold. If you refuse a change,
nothing paints.

A gesture is a drag of the plane, a slider drag or step, a stick session, a
swatch press or a field commit. Without `draft`, each gesture commits once. B,
Escape, a tap outside and Done close the panel and keep the colour.

With `draft = true`, only Apply commits. Each other way out proposes the
colour that the panel opened with. Cancel does this too. If you write the
value while the panel is open, your value becomes the value that Cancel
restores. Apply has the `facet-accent` tag.

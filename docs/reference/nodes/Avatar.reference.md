# Avatar

Avatar.reference option values and behavior.

| Control | Main contract |
|---|---|
| `Avatar` | `name`; one face: image, userId, resource or `icon` (an icon name, such as `"person"` for a guest, drawn in place of the initials); loader and onStatus; presence online, away, busy, offline or `inExperience`; presence label and mark; diameter or controlSize; standard or icon form; `background`, a palette role (`surface`, `surfaceStrong`, `control`, `contentStrong`, `accent`, `success`, `warning` or `danger`) for the plate, with its partner color on the initials and the icon; optional activation. `inExperience` draws an `accent` ring with a `surface` gap inside the edge of the face in place of a corner mark. Each band is twice `strokes.hairline` wide. An Avatar without an activation takes no input. With one, a `HoverRing` stroke in `accent` lights only the avatar under the pointer. |

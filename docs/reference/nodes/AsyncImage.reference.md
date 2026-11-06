# AsyncImage

AsyncImage.reference option values and behavior.

| Control | Main contract |
|---|---|
| `AsyncImage` | An image or source, an optional resource or loader, a placeholder, a failure label and a status callback. `imageProperties` forwards native properties and children to the inner ImageLabel. |

The loader receives `(source, resolve, reject)` and can return cancellation.
A superseded result cannot replace the current image. Loading and failure
stay observable; the control does not invent successful assets.

Without a loader or resource, AsyncImage uses the ContentProvider. A source
that the ContentProvider reports as fetched, or that Facet remembers from an
earlier successful fetch, becomes `ready` immediately when it mounts. This
prevents a placeholder flash when a collection row or an Avatar shows the
image again. A remembered source still preloads. A failed fetch then sets the
state to `failed` and removes the source from the memo.

`resource` is a function returning an `ImageResource` with `value` and either
`state` or `status`. It can register cleanup with `Compose.cleanup`.
A Compose shared resource acquire function also fits this contract.
Resource lifetime uses Compose ownership.

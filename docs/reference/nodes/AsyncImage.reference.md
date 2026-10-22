# AsyncImage

AsyncImage.reference option values and behavior.

| Control | Main contract |
|---|---|
| `AsyncImage` | An image or source, an optional resource or loader, a placeholder, a failure label and a status callback. `imageProperties` forwards native properties and children to the inner ImageLabel. |

The loader receives `(source, resolve, reject)` and can return cancellation.
A superseded result cannot replace the current image. Loading and failure
stay observable; the control does not invent successful assets.

`resource` is a function returning an `ImageResource` with `value` and either
`state` or `status`. It can register cleanup with `Compose.cleanup`.
A Compose shared resource acquire function also fits this contract.
Resource lifetime uses Compose ownership.

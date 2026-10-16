# CellEditor.draft

`draft` is an optional writable cell containing nil or `{ text: string, original: unknown, error: string? }`.

`draft` is an optional writable cell containing nil or
`{ text: string, original: unknown, error: string? }`. It is valid only for text
and number editors. Keep one draft per record and field outside the render
owner. Clear it when the record is deleted. Accepted changes clear the draft.
Validation errors and synchronous rejections keep it for correction. An external
model update does not replace dirty text; the editor reports a conflict. Escape
cancels to the latest value; an explicit commit proposes the draft against that
latest value. The model can reject that proposal. A pending request's rejection
can set `draft.error` before clearing `busy`.

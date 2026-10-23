# Facet Design verification

Build the plugin and companion place from the repository root:

```sh
lute run tools/facet build designer
lute run tools/facet gate full
```

The committed specs check adapter construction, exported source, supported
source parsing, literal escaping, document bounds, history, storage revisions,
and resource cleanup. Read the selected case results. Constructor acceptance
does not prove every property interaction.

## Studio checks

Open the built companion place and install the built plugin. Compare the
editor canvas with the exported component. Check presented Alert, Sheet,
Dialog, Popover, Callout, and Toast content.

Select a layer and a canvas control. Edit text and structured values. Check
Reset, Undo, and Redo. Rename a layer with a double-click. Return commits;
Escape cancels. Reorder rows and restore the order with Undo. The root Screen
must stay in place. Duplicate and Delete must be disabled for the root.

Filter Insert and the template gallery. Check empty results and Clear. Open a
template at desktop, phone portrait, and tablet landscape sizes. Check pane
tabs, Fit and Width zoom, safe insets, text fit, and scrolling.

Edit a supported linked ModuleScript outside the editor. Check one source
update and no self-write loop. Add a custom expression. Check that visual
writes stop and preserve the custom source. See [agent editing](agent-editing.md).

Save, reload, rename, duplicate, remove, and restore a design. Test quotes,
backslashes, and newlines. Check plugin settings readback and companion cloud
save status. Cloud persistence requires a published server test.

## Evidence limits

Native geometry and input need Studio. Device simulation does not prove
physical touch input or the on-screen keyboard. Test long editing sessions,
real devices, and published cloud saves separately. See
[verification scope](../../docs/guide/verification-scope.md).

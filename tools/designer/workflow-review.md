# Facet Design workflow review

Date: 2026-10-01.

This review records the editor workflows, their evidence, and the remaining checks.

| Workflow | Facet Design evidence | Remaining work |
| --- | --- | --- |
| Insert native controls | All 63 public constructors have adapters. Insert supports live search, Clear, and empty results. | Live previews now cover the insert gallery; test more control interactions. |
| Select and edit | Native input selects canvas controls and opens Inspector. Text edits update the canvas and exported Luau. | 1,000 field definitions now cover all constructors; custom game behavior remains outside the inspector. |
| Edit layout | Containers expose dimensions, spacing, padding, and alignment. Layers can move between containers. | Side padding, native colors, constraints, and more layout fields are editable. |
| Undo and redo | History stores documents and selection. Reset, Undo, and Redo pass native input checks. Template and saved-design loads retain history. | Check a long editing session on a physical phone. |
| Preview appearance | Device, orientation, palette, text size, and comparison settings use native Facet rendering. | 96 edited template, device, palette, and text-size combinations mount in Studio; physical devices remain. |
| Edit on a phone | Fixed commands, pane tabs, a visible Insert button, and width zoom pass phone simulator checks. | Check the on-screen keyboard and touch gestures on a physical phone. |
| Export code | All adapter exports have tests and native geometry evidence. The plugin creates component and preview ModuleScripts. | General game code with callbacks and external expressions does not round trip. |
| Start from a template | Six templates use the same editable document format and a live visual gallery. | Check longer design sessions with these templates. |
| Manage designs | My designs opens saved documents. The plugin uses native settings. The experience has a validated DataStore library. | Visual browsing, rename, duplicate, remove, and restore are implemented. Verify cloud saves after publication. |
| Share designs | The Studio plugin exports components. The experience shows selectable Luau. | Validated JSON design-file import and export are implemented. A community library and image export remain. |

Visual browsing, broader property editing, and design-file transfer are implemented.
Real device input and published cloud saves remain unverified. Constructor coverage
alone does not prove complete interaction coverage or product readiness on every platform.

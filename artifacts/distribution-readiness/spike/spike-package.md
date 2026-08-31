# Package spike — all questions answered (2026-08-31)

Throwaway asset `83627005624999` ("Facet-Spike-DeleteMe"), creator user
1364639953, built `build/Facet.rbxm` (0.10.0, commit 630ce8da). Raw responses
beside this file. Owner-approved spike; the asset is archived at the end.

| Question | Answer | Evidence |
|---|---|---|
| Does a rojo-built `.rbxm` upload via Open Cloud POST? | **Yes**, processed and `Approved` in ~10 s | `create-response.json`, revision 1 |
| Does the platform's "outside-Studio `.rbxm` might not work" warning bite here? | **No** — the inserted copy requires and runs (core smoke returned 42) | Studio probe, 2026-08-31 |
| Does the uploaded Model become a **real Package**? | **Yes** — the insert carries a genuine `PackageLink` (VersionNumber 1) on the root `ModuleScript`; 171 modules; `Distribution` attributes byte-match the local build | Studio probe |
| Does `PATCH` accept new `.rbxm` content (docs say `.fbx` only)? | **Yes** — a distinct payload produced `revisionId 2`; the docs' restriction is stale in practice | `update2-response.json` |
| What happens on identical bytes? | Silently **no new version** (revision stayed 1) — exactly why the publish guard demands a positive version-number edge | `update-response.json` |
| Wire format | Plain spellings: `"Model"`, `"Approved"`, `state: "Active"` — not proto constants | every response |
| Versions API | `GET …/versions` lists both, newest first, `published: true` | `update2-response.json` |
| `PackageLink` scriptability | `VersionNumber` readable from the command bar; `AutoUpdate`/`Status` are RobloxScript-locked — the AutoUpdate half of the final proof needs the Properties panel or Get Latest click | Studio probe |

**Ruling: `route = "open-cloud"`.** Create and same-ID update are both proven
end-to-end by API; the Studio publish flow remains the documented fallback. The
final insert/AutoUpdate/modified-copy proof still happens in Studio against the
REAL asset after creation.

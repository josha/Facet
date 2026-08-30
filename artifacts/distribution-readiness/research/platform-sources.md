# Platform sources: Roblox Open Cloud, Packages, Creator Store, GitHub

Research note for Facet's public-distribution + Roblox Package tooling. All fetches performed **2026-08-30**. Every bullet is tagged `FACT` (quoted/paraphrased from a cited doc) or `INFERENCE` (mine). Where a doc is silent, that is stated explicitly as "doc does not say" — no endpoint or field below is invented.

Two kinds of source URL appear:
- **Rendered page** — the `create.roblox.com/docs/...` or `docs.github.com/...` page a human reads.
- **Raw source** — the underlying file in the docs' own open-source repo (`github.com/Roblox/creator-docs` or `github.com/github/docs`), fetched directly because the rendered pages are JS-driven OpenAPI/YAML explorers that don't serialize fully to text. Content is identical; the raw file is what the rendered page is generated from, as stated by Roblox itself (see §1.0).

---

## 1. Roblox Open Cloud — Assets API (v1, Beta)

### 1.0 Source note
FACT — "Roblox publishes an OpenAPI 3.0.4 document... that contains **all** of the Roblox Cloud APIs. You can find this file, `openapi.json`, in the open source [creator-docs](https://github.com/Roblox/creator-docs/tree/main/content/en-us/reference/cloud) repository." — [OpenAPI document](https://create.roblox.com/docs/cloud/reference/openapi.md), fetched 2026-08-30. The Assets API's own spec file is `content/en-us/reference/cloud/assets/v1.json` in that repo — [raw file](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/cloud/assets/v1.json), fetched 2026-08-30. Rendered at [create.roblox.com/docs/cloud/reference/features/assets](https://create.roblox.com/docs/cloud/reference/features/assets).

FACT — All endpoints below carry `"x-roblox-stability": "BETA"`. Usage guide: "This API contains beta endpoints that might be subject to changes for future releases." — [Usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets), fetched 2026-08-30.

FACT — Base server: `https://apis.roblox.com/assets` (from `servers[0].url` in the spec).

### 1.1 Endpoints (exact, from `v1.json`)

| Method | Path | Purpose | Scopes required | Rate limit (per IP / per key owner / per OAuth authz) |
|---|---|---|---|---|
| POST | `/v1/assets` | Create Asset | `asset:read`, `asset:write` | 120/min |
| GET | `/v1/assets/{assetId}` | Get Asset (metadata) | `asset:read` | 120/min |
| PATCH | `/v1/assets/{assetId}` | Update Asset (content and/or metadata) | `asset:read`, `asset:write` | 120/min |
| POST | `/v1/assets/{assetId}:archive` | Archive Asset | `asset:read`, `asset:write` | 100/min |
| POST | `/v1/assets/{assetId}:restore` | Restore Asset | `asset:read`, `asset:write` | 100/min |
| GET | `/v1/assets/{assetId}/versions/{versionNumber}` | Get Asset Version | `asset:read` | 100/min |
| GET | `/v1/assets/{assetId}/versions` | List Asset Versions | `asset:read` | 100/min |
| POST | `/v1/assets/{assetId}/versions:rollback` | Rollback Asset to a previous version | `asset:read`, `asset:write` | 100/min |
| GET | `/v1/operations/{operationId}` | Get Operation (poll create/update result) | `asset:read` | 300/min |

All FACT, from [`v1.json`](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/cloud/assets/v1.json) (`x-roblox-rate-limits`, `x-roblox-scopes` per operation), fetched 2026-08-30. There is also a separate `x-roblox-throttling-limit.perApiKey` of 120/60s (create/update) or 100/60s (others) — same numbers, a second declared limiter.

FACT — There is **no** `/docs/cloud/legacy` directory for Assets in the current docs repo; `content/en-us/cloud/` contains only `auth/`, `guides/`, `reference/`, `webhooks/`, `index.md` (checked via GitHub API listing, 2026-08-30). The only Assets API version documented is this v1 Beta. "Legacy Assets API v1" as a distinct page does not exist — doc does not say there is one.

### 1.2 Create Asset — request shape (`POST /v1/assets`)

FACT — Multipart form-data, two parts, both required: `request` (JSON, schema = `Asset`) and `fileContent` (binary).

`request` JSON (from the `Asset`/`CreationContext`/`Creator` schemas):

| Field | Type | Notes |
|---|---|---|
| `assetType` | string (enum, format not enumerated in spec — see below) | "The asset type. Required for Create Asset." |
| `displayName` | string | Required for Create Asset |
| `description` | string | Limit 1000 characters. Required for Create Asset |
| `creationContext.creator.userId` | int64 | "Required if the asset is individual-user-owned." |
| `creationContext.creator.groupId` | int64 | "Required if the asset is group-owned." |
| `creationContext.expectedPrice` | int64, write-only | "Expected asset upload fee in Robux. When the actual price is more than expected, the operation fails with a 400 error." |
| `creationContext.assetPrivacy` | enum: `default`, `restricted`, `openUse`; write-only | "Only applies to asset types that support privacy override." |

FACT — the spec's `assetType` field is typed `"format": "enum"` but the OpenAPI file does **not** enumerate the allowed string values inline (no explicit list in `v1.json`). The usage guide's example uses the literal string `"Model"`; the supported-types table (§1.3) is the effective enum. Doc does not say there is a canonical machine-readable enum list beyond that table.

FACT — SocialLink objects (`facebookSocialLink`, `twitterSocialLink`, `youtubeSocialLink`, `twitchSocialLink`, `discordSocialLink`, `githubSocialLink`, `robloxSocialLink`, `guildedSocialLink`, `devForumSocialLink` — max 3 per asset) **cannot** be set on Create; the spec says: "You can't add SocialLink objects when you create an asset. Instead, use Update Asset."

Verbatim curl sample from the spec:
```
curl --location --request POST 'https://apis.roblox.com/assets/v1/assets' \
--header 'x-api-key: {apiKey}' \
--form 'request="{ \"assetType\": \"Model\", \"displayName\": \"Name\", \"description\": \"This is a description\", \"creationContext\": { \"creator\": { \"userId\": \"${userId}\" } } }"' \
--form 'fileContent=@"/filepath/model.fbx";type=model/fbx'
```

### 1.3 Supported asset types, file formats, and content-types (Model row is the load-bearing one)

FACT, verbatim table from the [usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets) ("Supported asset types and limits"), fetched 2026-08-30:

| Asset type | Formats | Content-type(s) | Restrictions (key excerpts) |
|---|---|---|---|
| Animation | `.rbxm`, `.rbxmx` | `model/x-rbxm` (both) | "`.rbxm` or `.rbxmx` files edited outside of Roblox Studio might not upload or function." |
| Audio | `.mp3`, `.ogg`, `.wav`, `.flac` | `audio/mpeg`, `audio/ogg`, `audio/wav`, `audio/flac` | ≤7 min; 100 uploads/month if ID-verified, 10/month if not; not updatable |
| Decal, Image | `.png`, `.jpeg`, `.bmp`, `.tga` | `image/png`, `image/jpeg`, `image/bmp`, `image/tga` | <8000×8000 px; not updatable |
| Mesh | Roblox-delivered only | `model/x-file-mesh-data` | "Only content downloaded from Asset delivery API is accepted."; not updatable |
| **Model** | `.fbx`, `.gltf`, `.glb`, `.rbxm`, `.rbxmx` | `model/fbx`, `model/gltf+json`, `model/gltf-binary`, `model/x-rbxm` (both `.rbxm`/`.rbxmx`) | "Imports custom 3D models as a `Class.Model` container containing one or more `Class.MeshPart` objects." / "`.rbxm` or `.rbxmx` files edited outside of Roblox Studio might not upload or function." / **"Will be uploaded as [packages](../../projects/assets/packages.md)"** |
| Video | `.mp4`, `.mov` | `video/mp4`, `video/mov` | ≤5 min, ≤4096×2160, ≤3.75 GB, 20/day if 13+ and ID-verified; not updatable |

FACT — Max file size: "you can only create or update one asset with the file size up to 20 MB" (all types, from the same guide, above the table).

FACT — the exact `.rbxm` warning quoted above is verbatim, appears twice (Animation and Model rows).

FACT — **The Model row is the single documented statement connecting Open Cloud uploads to Packages: "Will be uploaded as packages."** This is the entire textual basis for §6's "Recommended publish route." The doc does not elaborate on what "uploaded as packages" means mechanically (no mention of a `PackageLink` instance being created, no mention of Studio's AutoUpdate/modified-flag system applying to it) — see §2.6 for the gap.

### 1.4 Update Asset (`PATCH /v1/assets/{assetId}`)

FACT — Same multipart shape (`request` + `fileContent`, both required in the schema, though the usage guide shows metadata-only updates omitting `fileContent`). Query param `updateMask` (string, optional): "Asset metadata fields to update, including the description, display name, icon, and previews." (FieldMask format — comma-separated field names; see [Types](https://create.roblox.com/docs/cloud/reference/types.md).)

FACT — "Currently can only update the content body for **Models**. Icons and Previews must be **Image** assets. Icons must have square dimensions." — spec description for `Assets_UpdateAsset`.

FACT — Usage guide, more specific: "Currently, you can only update the asset content for `.fbx` files. The update creates a new version." (i.e., of the Model-eligible upload formats, only `.fbx` supports content replacement via PATCH today — `.rbxm`/`.rbxmx`/`.gltf`/`.glb` content is not listed as updatable.)

FACT — Response: 200 returns an `Operation` (same shape as Create); for metadata-only updates a comment in the spec says it can return "the updated metadata fields" directly, with an example showing a `previews` array.

FACT — Required fields for update: `assetId` (int64, "Required for Update Asset") on the `request` object; `assetType` is shown in every example but the schema marks it required only for Create.

### 1.5 Get Asset (`GET /v1/assets/{assetId}`)

FACT — Query param `readMask` (string, optional): "Asset metadata fields to retrieve, including the description, display name, icon, social links, and previews. Examples: `description%2CdisplayName`, `previews%2CtwitchSocialLink`." Responses: 200 → `Asset`; 400 "likely due to an invalid read mask"; 401 "not valid for this operation / don't have authorization"; 403 "Doesn't have the required permission"; 404 "Asset doesn't exist."

### 1.6 Operation polling (`GET /v1/operations/{operationId}`)

FACT — `Operation` schema: `path` (string, "The server-assigned resource path. The default format is `operations/{operation_id}`"), `done` (boolean), `error` (`$ref Status`), `response` (`$ref Asset`).

FACT — `Status` schema: `code` (int32, "The HTTP status code"), `message` (string).

FACT — `Asset` (i.e. the `response` payload once `done: true`) fields: `assetType` (string), `assetId` (int64, read-only), `creationContext`, `description`, `displayName`, `path` (string, format `assets/{assetId}`, e.g. `assets/2205400862`), `revisionId` (string, read-only — "**Equivalent to `versionNumber`**. Every change of the asset automatically commits a new version. The format is an integer string. Example: `1`."), `revisionCreateTime` (date-time, read-only), `moderationResult` (`$ref ModerationResult`), `icon` (string), `previews` (array of `{asset, altText}`), `state` (enum `Unspecified`/`Active`/`Archived`), `socialLink`.

FACT — `ModerationResult.moderationState` (string): schema description says "Can be `Reviewing`, `Rejected`, or `Approved`." However the usage guide's worked example response shows the value **`"MODERATION_STATE_APPROVED"`** (full enum-style name), not bare `Approved`:
```json
{
  "path": "operations/{operationId}",
  "done": true,
  "response": {
    "@type": "type.googleapis.com/roblox.open_cloud.assets.v1.Asset",
    "path": "assets/2205400862",
    "revisionId": "1",
    "revisionCreateTime": "2023-03-02T22:27:04.062164400Z",
    "assetId": "2205400862",
    "displayName": "Name",
    "description": "This is a description",
    "assetType": "ASSET_TYPE_DECAL",
    "creationContext": { "creator": { "userId": "11112938575" } },
    "moderationResult": { "moderationState": "MODERATION_STATE_APPROVED" }
  }
}
```
FACT — this same example also shows `assetType` rendered back as `"ASSET_TYPE_DECAL"` (proto-style), not `"Decal"` as sent on create. **The two docs (schema table vs. worked example) disagree on wire-format casing/prefixing for both `assetType` and `moderationState`; the note itself does not reconcile this** — a publish tool must not assume one form without testing against a live response. Both quoted verbatim above from [Usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets) and [`v1.json`](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/cloud/assets/v1.json), fetched 2026-08-30.

FACT — Retrieve asset operation status guide text: "If your request for creating a new asset or updating an existing asset succeeds, it returns an **Operation ID** in the format of `{ "path": "operations/${operationId}" }`."

Doc does not say: a recommended poll interval/backoff for this specific endpoint (no exponential-backoff guidance is given on this page; general rate-limit guidance — §1.9 — says to honor `retry-after` / use exponential backoff only on 429).

### 1.7 Asset Versions / Rollback / Archive / Restore

FACT — `GET /v1/assets/{assetId}/versions`: query params `maxPageSize` (int, "Valid values range from 1 to 50 (inclusive). Defaults to 8 when not provided.") and `pageToken` (string). Returns `AssetVersion[]`.

FACT — `AssetVersion` schema: `creationContext`, `path` (format `assets/{assetId}/versions/{version}`, e.g. `assets/2205400862/versions/1`), `moderationResult`, `published` (boolean, "Only applies to place asset types.").

FACT — `GET /v1/assets/{assetId}/versions/{versionNumber}`: path params `assetId`, `versionNumber` (both string). Returns single `AssetVersion`. 403/404 documented.

FACT — `POST /v1/assets/{assetId}/versions:rollback`: multipart form field `assetVersion` (string, required) — "The asset version path in the format of `assets/{assetId}/versions/{versionNumber}`." Response 200 → `AssetVersion`. This **is** the Open Cloud rollback/revert mechanism the brief asked about, and it is documented (contrary to the possibility it might not exist).

FACT — `POST /v1/assets/{assetId}:archive` — "Archives the asset. Archived assets disappear from the website and are no longer usable or visible in Roblox experiences, but you can restore them." Returns `Asset` with `state: Archived`. 403 "Forbidden - API key without Write scope or user doesn't have access."; 404.

FACT — `POST /v1/assets/{assetId}:restore` — "Restores an archived asset." Returns `Asset`.

### 1.8 Errors, rate limits, IP allowlist

FACT — Generic gateway/auth error shape (any Open Cloud v1 or v2 API): `{"errors":[{"code":0,"message":"Invalid API Key"}]}` — [Errors](https://create.roblox.com/docs/cloud/reference/errors.md), fetched 2026-08-30.

FACT — Assets-API-specific error responses actually documented in `v1.json`: 400 → `Status{code,message}` ("Invalid argument. Failed to parse the request or the file."); 401 → no body schema, description only: "The API key is not valid for this operation / You don't have the authorization."; 403 (on some endpoints only) → "Forbidden - API key without {Read|Write} scope or user doesn't have access." / "Doesn't have the required permission."; 404 → "Asset doesn't exist." / "Asset or Asset Version not found."; 500 → "Server internal error / Unknown error."

FACT — Doc does not explicitly state that an IP-allowlist mismatch produces a **401** specifically — the [API keys](https://create.roblox.com/docs/cloud/auth/api-keys.md) page (fetched 2026-08-30) describes the CIDR-restriction feature ("explicitly restrict IP access to the key using CIDR notation... add it to the Accepted IP Addresses section") and warns "Do not use IP address restrictions when using your API key in Roblox places to ensure your key can be used with Roblox servers," but never states the resulting status code for a blocked IP. INFERENCE: given the generic 401 wording above ("you don't have the authorization"), an IP-allowlist violation almost certainly also surfaces as 401, but this is not confirmed in text.

FACT — Rate limits, general mechanism ([Rate limits](https://create.roblox.com/docs/cloud/reference/rate-limits.md), fetched 2026-08-30): response headers `x-ratelimit-limit`, `x-ratelimit-remaining`, `x-ratelimit-reset`; "When this reaches 0, you receive HTTP 429 responses." "API key" limits are "applied across all API keys per owner" (user or group); in-game `HttpService` calls additionally count against "a fixed limit of 500 HTTP requests per minute per Roblox game server"; OAuth 2.0 limits are per access token. On 429: "check the `retry-after` response header... If there is no `retry-after` response header present, implement an exponential backoff retry strategy." Per-endpoint numeric limits for the Assets API specifically are the ones tabulated in §1.1 (from `x-roblox-rate-limits`), not from this general page.

FACT — Open Cloud v2 error-code table (code / HTTP status): `INVALID_ARGUMENT`/400, `PERMISSION_DENIED`/403, `NOT_FOUND`/404, `ABORTED`/409, `RESOURCE_EXHAUSTED`/429, `CANCELLED`/499, `INTERNAL`/500, `NOT_IMPLEMENTED`/501, `UNAVAILABLE`/503 — [Errors](https://create.roblox.com/docs/cloud/reference/errors.md). Note: the Assets API's own per-endpoint error docs (§ above) use plain-English descriptions, not these v2 codes verbatim, and the page itself says "Open Cloud v1 APIs have inconsistent error response formats" — treat Assets API errors as belonging to that inconsistent-v1 family, not the clean v2 table.

### 1.9 Required permissions / scopes

FACT — API key config (Creator Dashboard → API Keys): "In the **Access Permissions** section, select an API from the **Select API System** menu." Usage guide, Assets-specific: "1. Add **assets** to **Access Permissions**. 1. Add **Read** and **Write** operation permissions to your selected game, depending on the required scopes of the endpoints you plan to call." All endpoints require the `x-api-key` header. — [API keys](https://create.roblox.com/docs/cloud/auth/api-keys.md) + [Usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets), fetched 2026-08-30.

FACT — OAuth 2.0 scopes: `asset:read` ("This allows viewing information about your assets.") and `asset:write` ("This allows uploading and updating assets to Roblox.") — from `v1.json` `securitySchemes.roblox-oauth2.flows.authorizationCode.scopes`.

FACT — Per-endpoint scope requirements are exactly as tabulated in §1.1 (`asset:read` alone for all GETs; both `asset:read`+`asset:write` for POST/PATCH, including the two writes that only mutate state — archive/restore/rollback still require **both** scopes together, not `asset:write` alone).

FACT — Group-owned assets: "To create an API key for managing group assets, you must have the corresponding permissions. For more information on granting group permissions, see Group roles and permissions." — Usage guide.

### 1.10 Rate limits and IP allowlist — behavior not covered above
Already folded into §1.8/1.9; not repeated.

---

## 2. Roblox Packages

Primary source: [Packages](https://create.roblox.com/docs/projects/assets/packages) rendered page / [raw `packages.md`](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/projects/assets/packages.md), fetched 2026-08-30.

### 2.1 Creating a package
FACT — "In the Explorer window or 3D viewport, right-click the object(s) you want to turn into a package and, in contextual menu, select **Convert to Package**." If working in a group, "set **Ownership** to the appropriate group in which you have permission to create/edit group games."

FACT — Ownership warning, verbatim: "**Ownership transfers are not supported by the asset system, so carefully consider the owner when creating a package.**" (No path exists in-doc to move a package between a user and a group after creation.)

FACT — "After the conversion completes, the object receives a 'chain link' symbol... Additionally, you can see a new `Class.PackageLink` object parented to the object." Do-not-delete warning: "Do not delete or move the `Class.PackageLink` object! Doing so for any package copy converts the copy back into a normal object and loses package capabilities."

### 2.2 `PackageLink` object — full property list
FACT, from [`PackageLink.yaml`](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/PackageLink.yaml), fetched 2026-08-30 (rendered at [create.roblox.com/docs/reference/engine/classes/PackageLink](https://create.roblox.com/docs/reference/engine/classes/PackageLink)):

| Property | Type | Read/Write security | Notes |
|---|---|---|---|
| `AutoUpdate` | boolean | Roblox script security both ways | "When this property is set to true, the package... will be automatically updated to the latest version. By default, this property is false upon creation of a package... The game periodically checks for new updates while a place is open." |
| `Creator` | string | read-only, NotReplicated, NotScriptable | "The creator of the package asset." |
| `DefaultName` | string | engine-managed | "the as-published baseline the engine compares against the current instance name to detect local name customizations." |
| `PackageAssetName` | string | read-only | "The asset name of the package." |
| `PackageContent` | Content | read-only | Content URL for the backing model asset; same target as `PackageId`. |
| `PackageId` | ContentId | read-only | "The ID of the asset this package corresponds to." |
| `PermissionLevel` | `Enum.PackagePermission` | read-only, NotScriptable | "The package permission for the current Studio user." |
| `SerializedDefaultAttributes` | BinaryString | engine-managed | as-published baseline for attribute three-way merge |
| `Status` | string | Roblox script security | "It can be one of the following statuses: **Up To Date, Changed, New Version Available, Changed + New Version Available.**" |
| `VersionNumber` | int64 | engine-managed | "Refers to a revision of a specific package." |

FACT — Class summary/description: "Links a `Class.DataModel` instance to a corresponding asset in the cloud... improves flows for collaboration, version control, and sharing for models." PackageLinks are `NotCreatable` (cannot be scripted into existence) and always sort first under their package root regardless of tree sort order.

### 2.3 Publishing a new version, mass updates, auto-update, modified-copy behavior
FACT — Publish: right-click modified copy → **Publish to Package**. "It's **not** required to publish a modified package before publishing a place because the modified version is saved along with the place." Optional changelog: Package Options → Package Details → Versions tab → Add.

FACT — **AutoUpdate is opt-in, per `PackageLink` instance** (i.e. per copy, since every copy has its own `PackageLink`), and **is disabled and ignored the moment a copy is locally modified** — the exact behavior the brief asked about: "Automatic updating does not apply to modified package copies. Once you modify a package instance, its **AutoUpdate** property becomes disabled and is ignored." A modified copy is neither reported-and-blocked nor silently overwritten by auto-update — it's simply excluded from the auto-update mechanism entirely, and gets a visible "modified" icon in the Explorer instead ("Once modified, packages with unpublished changes get a modified icon in the Explorer window").

FACT — What counts as "modified" (i.e. what disables AutoUpdate) explicitly **excludes**: renaming the root node; changing position/rotation of a `BasePart`/`Model`/`GuiObject` root; toggling `LayerCollector.Enabled` on a root `GuiObject`; changing a `Weld` reference that points outside the package. Everything else flags modified.

FACT — Manual per-copy update: right-click an outdated copy (marked with a "download" symbol) → **Get Latest Package**, or select multiple → **Get Latest For Selected Packages**.

FACT — Mass update ("Update All"): updates all copies of a package across chosen places in one action; "automatically **saves** the selected places but does not **publish** them"; explicitly **skips** modified copies and reports a count of skipped packages afterward.

### 2.4 Version history and revert
FACT — "View the full version history for a package, compare versions, and restore old versions" is listed as a headline capability. Mechanism: Package Options → Package Details → **Versions** tab, which "displays details for each published version, including the date and time of publication, along with any descriptions of the changes." Restore: "Click the checkmark next to the version you want to restore and click **Submit**." Caveat: "Reverting changes to a package does not reset the configuration to the default" (attributes must be reverted separately).

FACT — Separate, unpublished-changes-only revert exists too: right-click a modified copy → **Undo Changes to Package** (or **Undo Changes to Selected Packages**) — this is local/unpublished revert, distinct from restoring a prior *published* version.

FACT — A diff/compare tool exists ("Compare Package Versions") with Visual/Properties/Script tabs; "Some older versions might be incompatible with the package diff tool."

### 2.5 Ownership, sharing, insertion
FACT — Access levels for collaborators: **Use & View** (use/view current+previous versions, cannot edit; "Once you provide a collaborator with this ability, you cannot revoke access to a copy they already inserted into their game") vs. **Edit** (can also publish changes). Game-level access is granted via Creator Dashboard → package's Permissions page → add universe IDs.

FACT — Insertion is via the **Toolbox**: "Inventory ⟩ My Packages" (your own or Creator-Store-obtained packages, or friend-shared ones) or "Creations ⟩ Group Packages" (group member packages). Doc does not mention `InsertService:LoadAsset` or an asset-ID-driven insertion path anywhere on this page — insertion is described purely as a Toolbox/Explorer UI action. Once inserted into a published place, the package "appears in the Asset Manager and remains there even if you later delete all copies of it."

### 2.6 The open question: does an Open-Cloud-updated Model produce a new Package version?
FACT — `packages.md` never mentions Open Cloud, HTTP APIs, or any non-Studio upload path at all. Its entire model of "package" is Studio-UI-driven (Convert to Package, Publish to Package, PackageLink property panel).

FACT — The only textual bridge is the Assets-API usage guide's Model-type table row: **"Will be uploaded as packages"** (§1.3). It does not say whether this means (a) a `PackageLink` instance is attached to the uploaded Model's root the same way Studio's Convert-to-Package does, (b) whether a `PATCH` content-update to that asset increments `PackageLink.VersionNumber`/flips `Status` to "New Version Available" for existing in-place copies the same way a Studio Publish does, or (c) whether `PackageLink.AutoUpdate` copies actually pick up an Open-Cloud-authored revision on next place-open the same way they pick up a Studio-published one. **Doc does not say.** This is carried into §7 as an open question and an explicitly-labeled inference.

---

## 3. Creator Store distribution

Source: [Creator Store](https://create.roblox.com/docs/production/creator-store) rendered / [raw `creator-store.md`](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/production/creator-store.md), fetched 2026-08-30.

### 3.1 Eligibility to distribute (free)
FACT, verbatim, "Distributor Requirements" tab: "Your Roblox account must be at least 2 days old." / "Your Roblox account must not have been recently banned for any reason." / "Your Roblox account must be verified by passing an age check or using a government ID. You **cannot** verify with a phone number." (Age-check and government-ID are the only two accepted verification paths; a phone-verified-only account cannot distribute.)

FACT — Additional requirements apply **only** if setting a USD price / becoming a seller (not required for free distribution): 18+ or 13–17 with parental consent, 2-Step Verification, residency in a Stripe-supported country, one Stripe account per Roblox account.

FACT — Per-30-day distribution caps by verification status:

| Account | Mesh | Image | Model | Audio | Plugins |
|---|---|---|---|---|---|
| Verified | 200 | 200 | 200 | 100 | 10 |
| Unverified | 10 | 10 | 10 | 10 | 2 |

### 3.2 Metadata requirements
FACT — Required: Name, Description fields. Optional (requires ID or phone verification): up to 1 video + 5 thumbnail images. Optional: a "Try in Roblox" demo experience (default or custom). Doc does not specify tags/category as a required metadata field beyond the asset's existing category (mesh/image/model/audio/plugin) chosen at upload time.

FACT — Two distribution paths documented: via the Creator Hub (asset's Configure page) or inside Studio (Toolbox → Creations → Edit Asset, or Explorer → Save/Export → Save to Roblox..., both funnel to the same Creator Hub Configure page).

### 3.3 The toggle
FACT, verbatim: "In the **Distribution** section, toggle on **Distribute on Creator Store**." Then, if selling: set a USD price ("If you keep the default value of **Free**, the asset displays on the Creator Store as free to all creators"). "Click the **Save Changes** button. After a few moments, the asset becomes public and visible on the Creator Store."

### 3.4 Un-listing / delisting behavior for existing users — doc does not say
Doc does not say what happens to a copy of the asset a user already inserted into their game/inventory if the creator later toggles distribution off or removes the asset. The only related, narrower statement found is about **refunds** on paid assets: "When a refund occurs, Roblox removes the asset from the customer's inventory" — that is a refund-specific removal, not a general delist behavior, and does not generalize to "toggle off Distribute on Creator Store." Doc does not say.

### 3.5 Open-source / MIT / attribution policy — doc does not say
No mention anywhere in `creator-store.md` of MIT, GPL, open-source, or any software-license concept. Asset content requirements reference only Roblox's own **Community Rules**, **Terms of Use**, and **DMCA** guidelines, plus content-safety rules (no obfuscated code, no code that dynamically `require()`s/`loadstring()`s remote assets, no oversized scripts). Doc does not say anything about a creator's own choice of software license (e.g. an MIT LICENSE file shipped inside the model) being recognized, required, or restricted by the Creator Store.

### 3.6 Pricing / revenue
FACT — Free is the default and requires no seller account. Selling for USD requires a Stripe-backed seller account; "you can only price assets on the Creator Store in USD" (no direct Robux pricing for Creator Store items). Revenue: "earn 100% of net proceeds on transactions... as only taxes and payment processing fees are deducted." Group-owned assets **cannot** be sold ("You can only sell assets that you own from an **individual** user account. Group-owned assets are ineligible.") — this restriction is sell-specific; free distribution of group-owned assets is not restricted by this clause.

---

## 4. GitHub — renaming a repository

Sources: rendered [Renaming a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository), raw [renaming-a-repository.md](https://raw.githubusercontent.com/github/docs/main/content/repositories/creating-and-managing-repositories/renaming-a-repository.md); [REST: Update a repository](https://docs.github.com/en/rest/repos/repos#update-a-repository) with schema cross-checked against [github/rest-api-description](https://github.com/github/rest-api-description) `api.github.com.json`. All fetched 2026-08-30.

### 4.1 Permission required
FACT, verbatim (page intro): "You can rename a repository if you're either an organization owner or have admin permissions for the repository."

### 4.2 What redirects
FACT, verbatim: "When you rename a repository, all existing information, with the exception of project site URLs, is automatically redirected to the new name, including: Issues / Wikis / Stars / Followers." And: "In addition to redirecting web traffic, all `git clone`, `git fetch`, or `git push` operations targeting the previous location will continue to function as if made on the new location."

### 4.3 What does NOT redirect
FACT, verbatim: "GitHub Pages" project-site URLs are the explicit exception called out in the sentence above (link target: what-is-github-pages#types-of-github-pages-sites). Recommendation given: "If you plan to rename a repository that has a GitHub Pages site, we recommend using a custom domain for your site... This ensures that the site's URL isn't impacted by renaming the repository."

FACT, verbatim (Note callout): "GitHub will not redirect calls to an action hosted by a renamed repository. Any workflow that uses that action will fail with the error `repository not found`. Instead, create a new repository and action with the new name and archive the old repository." — This is specifically about **reusable/composite Actions hosted in the renamed repo being referenced by other workflows**, not about the renamed repo's own internal workflow files (which continue to work via the redirect, per the general git/web redirect statement).

### 4.4 Warning about reusing the old name
FACT, verbatim (Warning callout): "If you create a new repository under your account in the future, do not reuse the original name of the renamed repository. If you do, redirects to the renamed repository will no longer work."

### 4.5 Updating a local clone
FACT, verbatim command given: `git remote set-url origin NEW_URL`

### 4.6 How to actually do it (doc's steps)
FACT — Settings → (Repository Name field) → type new name → click **Rename**.

### 4.7 REST: `PATCH /repos/{owner}/{repo}`
FACT, from the live OpenAPI description (`operationId: repos/update`, `summary: "Update a repository"`), cross-checked against `github/rest-api-description`:

| Field | Type | Description (verbatim) |
|---|---|---|
| `name` | string | "The name of the repository." |
| `visibility` | string, enum `public`/`private` | "The visibility of the repository." |
| `private` | boolean, default `false` | "Either `true` to make the repository private or `false` to make it public. Default: `false`. **Note**: You will get a `422` error if the organization restricts changing repository visibility to organization owners and a non-owner tries to change the value of private." |
| `description` | string | "A short description of the repository." |
| `homepage` | string | "A URL with more information about the repository." |
| `has_issues` | boolean, default `true` | enable/disable issues |
| `has_wiki` | boolean, default `true` | enable/disable wiki |
| `default_branch` | string | "Updates the default branch for this repository." |
| `delete_branch_on_merge` | boolean, default `false` | auto-delete head branches on PR merge |
| `allow_squash_merge` | boolean, default `true` | allow squash-merge |
| `archived` | boolean, default `false` | "Whether to archive this repository. `false` will unarchive a previously archived repository." |

FACT — this endpoint's OpenAPI operation object carries **no `security` field** in the machine-readable spec (`"security": null`), i.e. the exact fine-grained-PAT permission name and OAuth scope for this specific call are **not exposed in the OpenAPI description** and could not be confirmed via automated fetch of the rendered page either (its "Fine-grained access tokens" callout is client-rendered and did not serialize to fetchable text in this session). Doc does not say (via this fetch) the precise fine-grained permission name (commonly believed to be "Administration" repo permission — **not independently confirmed here, do not hard-code it without a live check**).

FACT — the classic OAuth scope for full repo control **is** documented, generically (not endpoint-specific): `repo` — "Grants full access to public and private repositories including read and write access to code, commit statuses, repository invitations, collaborators, deployment statuses, and repository webhooks." `public_repo` is the public-only subset. — [Scopes for OAuth apps](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps), fetched 2026-08-30.

FACT — `license_template` is **not** a field on the Update-a-repository schema (checked in the dereferenced OpenAPI schema); it exists only on the **create**-repository endpoints. Renaming/re-licensing an existing repo via this PATCH cannot set a license — that has to be done by committing a LICENSE file (§6).

### 4.8 What changes when a private repo becomes public
Source: rendered [Setting repository visibility](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility), raw [setting-repository-visibility.md](https://raw.githubusercontent.com/github/docs/main/content/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility.md), fetched 2026-08-30.

FACT, "Changing from private to public" (verbatim bullets): "The code will be visible to everyone who can visit GitHub." / "Anyone can fork your repository." / "**All push rulesets will be disabled.**" / "Your changes will be published as activity." / "Actions history and logs will be visible to everyone." / "Stars and watchers for this repository will be erased."

FACT — Elsewhere on the page, "Making a repository public" section adds: "GitHub will detach private forks and turn them into a standalone private repository" (i.e. any pre-existing private forks become independent standalone private repos, not linked back); "The repository will automatically gain access to GitHub Advanced Security features"; "Actions history and logs will be visible to everyone. If your repository had reusable or required workflows that were shared from a different repository in your organization, the workflow file path including the repository name will be visible in the logs."

FACT — "Making a repository private" section (the reverse direction, relevant if ever needed): "GitHub will detach public forks of the public repository and put them into a new network. Public forks are not made private." And, Free-plan-specific: "If you're using GitHub Free for personal accounts or organizations, some features won't be available in the repository after you change the visibility to private. **Any published GitHub Pages site will be automatically unpublished.** If you added a custom domain to the Pages site, you should remove or update your DNS records before making the repository private, to avoid the risk of a domain takeover."

FACT — "Stars and watchers for this repository will be erased" is stated identically for **every** visibility-change direction (public↔private, internal↔private, internal↔public) on this page — this is not a one-way loss, it always happens on any visibility change.

Doc does not say (on this specific page): a general Free-vs-paid-plan table of branch-protection/ruleset feature availability beyond the one push-ruleset-disable bullet above and the one Pages-unpublish bullet; no explicit "check your git history for secrets before going public" warning appears on this page (the licensing page does separately note that going public makes the repo forkable/viewable by others — see §4.9 note below — but that's not phrased as a secrets warning).

FACT (found on the licensing page, not the visibility page, but directly relevant): "If you publish your source code in a public repository on GitHub, according to the Terms of Service, other users of GitHub have the right to view and fork your repository. If you have already created a repository and no longer want users to have access to the repository, you can make the repository private. When you change the visibility of a repository to private, existing forks or local copies created by other users will still exist." — [Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository), fetched 2026-08-30. This is the closest the docs come to a "you can't put the genie back in the bottle" warning — it's about forks/clones surviving a later re-privatization, not about secret-scanning history.

---

## 5. GitHub community profile & license detection

Sources: rendered [About community profiles](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories) / raw [about-community-profiles-for-public-repositories.md](https://raw.githubusercontent.com/github/docs/main/content/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories.md); [Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository) / raw [licensing-a-repository.md](https://raw.githubusercontent.com/github/docs/main/content/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository.md); plus [Setting guidelines for repository contributors](https://raw.githubusercontent.com/github/docs/main/content/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors.md), [Adding a code of conduct](https://raw.githubusercontent.com/github/docs/main/content/communities/setting-up-your-project-for-healthy-contributions/adding-a-code-of-conduct-to-your-project.md), [About issue and PR templates](https://raw.githubusercontent.com/github/docs/main/content/communities/using-templates-to-encourage-useful-issues-and-pull-requests/about-issue-and-pull-request-templates.md). All fetched 2026-08-30.

### 5.1 What the checklist checks
FACT, verbatim: "The community profile checklist checks to see if a project includes recommended community health files, such as README, CODE_OF_CONDUCT, LICENSE, or CONTRIBUTING, in a supported location." The word "such as" means this is explicitly a non-exhaustive example list, not the full inventory — doc does not give one single complete enumerated list on this page. The checklist UI shows each recommended file as "Added" (green check) or "Not added yet" (orange circle), with **Add** (maintainer) / **Propose** (contributor) actions.

### 5.2 File locations, per file (from the other pages, since the profile page itself doesn't give locations)

| File | Accepted location(s) | Notes | Source |
|---|---|---|---|
| `LICENSE` | Root only (`LICENSE.txt`, `.md`, or `.rst`) | "Most people place their license text in a file named `LICENSE.txt` (or `LICENSE.md` or `LICENSE.rst`) in the root of the repository." No `.github`/`docs` alternative documented for LICENSE. | licensing-a-repository.md |
| `CODE_OF_CONDUCT` | root, `docs/`, or `.github/` | "To make your code of conduct visible in the repository's root directory, type `CODE_OF_CONDUCT`... `docs` directory, type `docs/CODE_OF_CONDUCT`... `.github` directory, type `.github/CODE_OF_CONDUCT`." | adding-a-code-of-conduct-to-your-project.md |
| `CONTRIBUTING` | root, `docs/`, or `.github/`; precedence order if more than one exists | "If a repository contains more than one CONTRIBUTING file, then the file shown in links is chosen from locations in the following order: **the `.github` directory, then the repository's root directory, and finally the `docs` directory.**" | setting-guidelines-for-repository-contributors.md |
| Issue templates | `.github/ISSUE_TEMPLATE/` only (hidden dir, default branch only) | "Issue templates are stored on the repository's default branch, in a hidden `.github/ISSUE_TEMPLATE` directory... need a `.md` extension" (or `.yml` for issue forms). | about-issue-and-pull-request-templates.md |
| PR template | root, `docs/`, or `.github/` (default branch only) | "You can store your pull request template in the repository's visible root directory, the `docs` folder, or the hidden `.github` directory." | about-issue-and-pull-request-templates.md |
| `SECURITY` | Doc does not say (on the one security-policy page fetched) | Could not confirm root/docs/.github pattern for SECURITY.md specifically in this session — do not assume parity with CODE_OF_CONDUCT/CONTRIBUTING without checking. | — |

### 5.3 License detection mechanism
FACT, verbatim: "[The open source Ruby gem Licensee](https://github.com/licensee/licensee) compares the repository's *LICENSE* file to a short list of known licenses." "The license picker is only available when you create a new project on GitHub" — for an existing repo you add a LICENSE file manually (no in-place picker after creation, beyond GitHub's "Add file" UI which does offer the same template chooser when creating a new file named LICENSE).

FACT — MIT is a recognized license keyword in the searchable-by-license table: `| MIT | `MIT` |`.

FACT — Detection accuracy caveats, verbatim: "If your repository is using a license that isn't listed on the Choose a License website, you can request including the license." And: "If your repository is using a license that is listed on the Choose a License website and it's not displaying clearly at the top of the repository page, it may contain multiple licenses or other complexity. To have your license detected, simplify your *LICENSE* file and note the complexity somewhere else, such as your repository's *README* file." No blanket "GitHub is not able to provide legal advice" sentence was found verbatim on this specific page (that disclaimer language may live on a different legal/ToS page — not confirmed here).

FACT — README-only license mentions are explicitly a *weaker*, secondary signal, not primary detection: "Some projects include information about their license in their README. For example, a project's README may include a note saying 'This project is licensed under the terms of the MIT license.'" Primary detection is the LICENSE file via Licensee.

---

## 6. InsertService (Roblox engine) — insertion by asset ID

Source: [InsertService.yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/InsertService.yaml), rendered at [create.roblox.com/docs/reference/engine/classes/InsertService](https://create.roblox.com/docs/reference/engine/classes/InsertService), fetched 2026-08-30.

FACT — `InsertService:LoadAsset(assetId: int64): Instance` — "fetches an asset given its ID and returns a `Class.Model` containing the asset." Yields; wrap in `pcall`. Security: `security: None` (i.e. no elevated engine security context), but gated at runtime by capability `LoadOwnedAsset` and a documented **Security Check**: the asset must be created/owned by the game creator, OR shared by the owner, OR owned by Roblox, OR be an inherently `OpenUse` type (t-shirts/shirts/pants/avatar accessories). "To load assets which do not meet the above criteria, such as free Models published on the Store, you must use `Class.AssetService:LoadAssetAsync()` and enable `Class.AssetService.AllowInsertFreeAssets`." A lowercase deprecated variant `InsertService:loadAsset` also exists ("deprecated variant of LoadAsset").

FACT — `InsertService:LoadAssetVersion(assetVersionId): Instance` and `InsertService:GetLatestAssetVersionAsync(assetId): int64` both exist, both gated by `LoadOwnedAsset`/`AssetRead` capability respectively.

FACT — **`InsertService:LoadLocalAsset` does not appear anywhere in the `InsertService.yaml` reference file.** Grepping the full property/method list confirms no method by that name (or containing "Local") exists on this class in the current docs. Doc does not say this method exists — the brief's premise that it might ("Studio, local .rbxm") is not confirmed; if such a mechanism exists it is not part of the public `InsertService` API surface as documented today.

---

## 7. Open questions the docs do not answer

- Does an Open-Cloud `PATCH`ed Model asset actually attach/update a `PackageLink` on existing in-place copies, flip their `Status` to "New Version Available," and respect their `AutoUpdate` flag the same way a Studio "Publish to Package" does? The only textual link is "Will be uploaded as packages" (§1.3) — mechanism unconfirmed.
- What exact wire-format do `assetType` and `moderationState` use in live responses — the schema's plain words (`Model`, `Approved`) or the worked example's proto-style constants (`ASSET_TYPE_DECAL`, `MODERATION_STATE_APPROVED`)? Docs contradict each other (§1.6).
- What HTTP status does an IP-allowlist-blocked API key request actually return? Not stated (§1.8).
- What happens to a user's already-acquired copy of a free asset when the creator turns off "Distribute on Creator Store" or deletes the asset? Not stated (§3.4).
- Does the Creator Store or Open Cloud recognize/require/restrict a bundled open-source license (e.g. MIT LICENSE file inside the Model) at all? Not mentioned anywhere (§3.5).
- Exact fine-grained PAT permission name and level for `PATCH /repos/{owner}/{repo}` (rename + visibility change) — not exposed in the OpenAPI description, not confirmed via rendered-page fetch (§4.7).
- SECURITY.md accepted locations — not confirmed to follow the same root/docs/.github pattern as CODE_OF_CONDUCT/CONTRIBUTING (§5.2).
- Whether an asset created as a Package in Studio, then later updated via Open Cloud `PATCH .../assets/{assetId}` (content or metadata), produces a new *Package* version (visible in the Package Details → Versions tab, triggering `AutoUpdate` copies) or only a new *Asset* revision (visible via `GET .../versions`) — see §6 recommendation below; not documented in either direction.

## 8. Recommended publish route (INFERENCE — mine, not from any single doc)

INFERENCE: Treat Open Cloud's Assets API and Studio's Package system as **two different, incompletely-reconciled subsystems that happen to share the same underlying "Model asset."** The only doc-confirmed bridge is the one sentence in §1.3. Given that:

1. **For the first publish** (minting the stable asset ID), use Open Cloud `POST /v1/assets` with `assetType: "Model"`, a `creationContext.creator.userId` (or `groupId` if the Package should be group-owned — note §2.1's irreversible-ownership warning applies at this step, since Open Cloud gives no documented way to transfer ownership later either), and an `.fbx`-exported or Studio-produced `.rbxm`/`.rbxmx` as `fileContent`. Poll `GET /v1/operations/{operationId}` until `done: true` and capture the resulting `assetId` as the stable Package ID — this is documented and reliable (§1.1–1.6).
2. **For subsequent version pushes**, prefer `PATCH /v1/assets/{assetId}` content updates **only if the payload is `.fbx`** (the only content type the docs confirm as update-capable, §1.4) — otherwise fall back to Studio's "Publish to Package" flow for `.rbxm`-based content updates, since Open Cloud's update path for other Model sub-formats is not documented as supported.
3. **Do not assume** that an Open-Cloud-driven update will surface as a version bump inside Studio's Package Details → Versions UI, or that `PackageLink.AutoUpdate` copies elsewhere in the game will pick it up automatically. Before relying on this in the publish pipeline, run a live one-time test: publish via Open Cloud, then open a place with an `AutoUpdate`-enabled `PackageLink` copy of that asset and confirm (a) `PackageLink.Status` changes, and (b) the copy actually updates on place-open. Until that's verified empirically, gate any "auto-propagates to consumer games" claim in the owner packet as unconfirmed.
4. Use the Open Cloud **rollback** endpoint (`POST /v1/assets/{assetId}/versions:rollback`, §1.7) as the scripted rollback path for the Asset-revision history; do not conflate this with Studio's separate Package-version "Restore to published version" UI (§2.4) until step 3's test confirms they operate on the same version sequence.
5. GitHub rename + visibility flip are independent of the Roblox side and low-risk per §4: rename first (redirects preserved for git/web, broken only for Actions-hosted-by-this-repo references elsewhere — check for any external consumer that references `josha/LuauUI` as an Action), then flip visibility to public, budgeting for **stars/watchers being erased** and **all push rulesets being disabled** (§4.8) as the two concrete, documented side effects to redo post-flip.

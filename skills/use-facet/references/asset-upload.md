# Upload original game art

Use this route when a design needs authored image assets, including icons,
illustrations, textures and control surfaces. Complete the upload and binding
as part of building the UI. Native text, paths and standard controls do not
need an image asset when they already provide the intended result.

Create ordinary image files, upload them to Roblox through Open Cloud, and use
the returned asset IDs. Do not use EditableImage, embedded pixel buffers or
runtime image reconstruction to avoid uploading authored game art. A local
preview is not the delivered asset. Missing icons and plain substitutes do not
complete a design that depends on those images.

This rule concerns authored UI assets. EditableImage is appropriate for dynamic
pixels created by the player, such as a drawing canvas and its live brush
preview. Those pixels do not need to be uploaded as UI artwork. Keep the game's
authored icons, illustrations and control surfaces on the asset-ID route.

## Prepare the files

Create original art for the current design. Use image generation or an art
tool when the chosen finish needs it. Inspect the actual files at their intended
size. Keep reusable surfaces, subject art and icons separate from live labels,
values and controls. Preserve transparency where needed, and record the slice
rectangle for stretchable artwork. Do not upload a reference game's images or
flatten the whole interface into a screenshot.

Keep the source files and a small asset manifest with their role, content hash,
dimensions and intended creator. Reuse an existing successful upload of the
same file instead of creating duplicates on each run.

## Upload through the connected Studio

Discover the Studio tools and read their current Open Cloud and permission
guidance. When available, use `open_cloud_invoke`: it authenticates through the
creator's Studio connection. Do not put credentials in the game or call Open
Cloud from a LocalScript. Check the current [Assets API](https://create.roblox.com/docs/cloud/reference/features/assets)
and [upload guide](https://create.roblox.com/docs/cloud/guides/usage-assets)
for supported image types, request fields and processing limits.

1. Determine the intended owner from the experience and connected account.
   For an unpublished local place, use the connected creator unless the user
   specified a group. Resolve an unclear owner before creating assets.
2. Check `asset:read` and `asset:write` with the connection's harmless scope
   probe. If a scope is disabled, request that exact permission in Studio's
   Assistant Settings, under MCP Permissions → Publish & manage assets. Use an
   approved upload directory. Do not move files or switch APIs to bypass a
   denied permission. Do not request approval again for an upload the user has
   already authorized; a missing connection permission is a separate blocker.
3. Create the asset through `POST /assets/v1/assets`. With the MCP tool, put
   the metadata object under the `request` form field in `body`, and provide
   the image through `files` with `name = "fileContent"`, its absolute path and
   MIME type. Use the intended `creationContext.creator` and an appropriate
   image asset type from the current API. An upload is not a place publication
   or a Creator Store listing.
4. Save the returned operation path. Poll that operation until it succeeds or
   reports an error; do not repeat the create request just because processing
   is pending. Record the resulting asset ID and owner with the file hash.
5. Bind the asset ID to the actual UI and verify it in Studio. Check processing,
   moderation and experience access when an image fails to load. A successful
   upload response alone does not prove that the game can display it.

An image upload can return a Decal asset ID. If that ID does not load in an
ImageLabel, load the authorized Decal with `InsertService:LoadAsset`, read its
`Texture`, and use that image content ID. Destroy the temporary loaded model.
Record both IDs; do not guess an image ID from a numeric offset. Verify the
resolved image in the actual experience before supplying it to controls.

If permission, upload, moderation or loading is blocked, preserve the prepared
art and report the exact blocker. Continue independent work, but leave the art
integration incomplete. Do not silently switch to EditableImage or replace the
needed images with generic controls. A tool's unsupported authentication route
and a denied permission are different failures; follow the connected tool's
documented handling for each.

## Bind and inspect the result

Keep the values needed by the UI in a short runtime asset catalog: semantic
name, resolved image content ID, verified slice or sprite coordinates, scale
and content insets where used. Keep upload operations and provenance in a
separate record. Label local source dimensions separately; they do not establish
the delivered image's coordinate system. Bind from the verified values rather
than deriving a second set from the source file. If a tool truncates the
catalog, read its relevant entries in full before using them.

Use `rbxassetid://` strings in the supported contracts:

- Register icon images in the theme's `icons` or `assets`, then reference those
  semantic names from controls. A RadialMenu uses its documented icon, caption
  and focus behavior; do not attach artwork by reaching into its private tree.
- Put reusable image surfaces in theme `assets` and `chrome`. Use the correct
  image dimensions, slice rectangle, state variants and live-text insets.
  Roblox can resize the uploaded file. Check slice and sprite coordinates
  against the delivered image in Studio, not only the local source dimensions.
- Use Image or AsyncImage for standalone subject art.

Inspect the uploaded art on real controls at the required sizes. Check that the
images loaded, remain recognizable and preserve the target's finish. Exercise
hover, pressed, selected, focused and disabled states where used, including
selection after focus moves. Confirm that no icon or surface is still a local
placeholder before the first Studio translation review or final delivery.

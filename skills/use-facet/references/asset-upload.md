# Upload original game art

Use this route when a design needs authored image files: icons, illustrations,
textures and control surfaces. Native text, paths and standard controls need no
image asset when they already give the intended result.

Create ordinary image files, upload them to Roblox through Open Cloud and use
the returned asset IDs. Do not use EditableImage, embedded pixel buffers or
runtime image reconstruction for authored art; a dynamic player drawing canvas
can use EditableImage. Do not upload another game's images or a screenshot of a
whole interface.

## Upload through the connected Studio

Use the Studio connection's `open_cloud_invoke` tool when it is available. It
authenticates as the creator. Do not put credentials in the game or call Open
Cloud from a LocalScript.

1. Determine the owner. For an unpublished local place, use the connected
   creator unless the user named a group.
2. Create each asset with `POST /assets/v1/assets` and the scopes `asset:read`
   and `asset:write`. Put the metadata object under the `request` form field:
   `assetType = "Image"`, a `displayName`, and
   `creationContext.creator.userId` or `groupId`. Provide the image through
   `files` with `name = "fileContent"` and its absolute path. The file must be
   in a directory that the creator approved for uploads.
3. Each create returns an operation. Poll `GET /assets/v1/operations/{id}`
   until `done` is true, then read `response.assetId`. Do not repeat a create
   because processing is pending.
4. Bind `rbxassetid://<assetId>` in the UI and look at it in Studio. A
   successful upload does not prove that the game can display the image.

If a scope is disabled or a directory is rejected, ask the user to enable it
in Studio's Assistant Settings under MCP Permissions. Do not move files or
switch APIs to pass a denied permission. If an upload, moderation or load is
blocked, keep the prepared art, report the exact blocker and leave that art
integration incomplete; do not replace it with EditableImage or call generic
controls the finished design.

An upload can return a Decal asset ID. If that ID does not load in an
ImageLabel, load the Decal with `InsertService:LoadAsset`, read its `Texture`
and use that content ID. Do not guess an image ID from a numeric offset.

Reuse an earlier successful upload of the same file instead of creating a
duplicate on each run.

## Bind and inspect the result

Keep one small art module: a semantic name, the `rbxassetid://` string, the
delivered pixel size, and slice or sprite coordinates where used. Roblox can
resize an upload, so take those coordinates from the delivered image in
Studio, not from the source file.

- Register icon images in the theme's `icons` or `assets` and reference the
  semantic names from controls. A RadialMenu uses its documented icon, caption
  and focus options; do not reach into its private tree.
- Put reusable image surfaces in theme `assets` and `chrome`, with the slice
  rectangle, state variants and content insets.
- Use `Image` or `AsyncImage` for standalone subject art.

Look at the uploaded art on real controls at the supported sizes. Check that
each image loaded and that hover, pressed, selected, focused and disabled
states read correctly.

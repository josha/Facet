#!/usr/bin/env python3
"""Upload LuauUI's standard icon set to Roblox, headlessly, and write the manifest.

WHY THIS EXISTS. Every one of the 11 theme assets shipped before this went up
through Studio: a local `http.server` on 127.0.0.1:8643 plus the Studio MCP
`upload_image` tool, with the returned ids hand-transcribed into
`upload-manifest.json`. That needs Studio open and a human in the loop.

THE HEADLESS ROUTE WORKS, with one correction to the documentation. Open Cloud's
asset API accepts `assetType = "Image"` and returns a real Image asset
(`AssetTypeId = 1`), confirmed by experiment on 2026-07-27 and cross-checked in
Studio against `81048500362779` (`ornate_panel_fill`), which went up the Studio
way and renders in the shipped fantasy-ornate package. Do not "fix" this to
`"Decal"` on the strength of the docs: the usage guide, the widely-cited
community reference and the October 2025 announcement are all stale on this
point, and uploading as a Decal hands back a DECAL id, which `ImageLabel.Image`
cannot use and which has no stable Open Cloud conversion.

Keys: `ROBLOX_API_KEY` (scope `assets`, read + write) from
GameStudio/tools/API_KEYS.txt, loaded the way every other studio tool loads it --
a real environment variable of the same name wins. The creator id comes from
`ROBLOX_CREATOR_USER_ID` or the default below; it is configuration, not a secret,
but it is not hardcoded into the call either.

Usage:
    python3 tools/upload_icons.py            # upload anything with no content id
    python3 tools/upload_icons.py --force    # re-upload everything
    python3 tools/upload_icons.py --dry-run  # show what would go up
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request
import uuid

REPO = pathlib.Path(__file__).resolve().parent.parent
ICON_DIR = REPO / "assets" / "icons"
MANIFEST = ICON_DIR / "upload-manifest.json"
REGISTRY = REPO / "src" / "themes" / "standard_icons.luau"
KEYS_FILE = REPO.parent.parent / "tools" / "API_KEYS.txt"

CREATE_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATION_URL = "https://apis.roblox.com/assets/v1/operations/{}"
DEFAULT_CREATOR = "1364639953"

# poll budget: moderation is usually instant but is not promised to be
POLL_ATTEMPTS = 40
POLL_INTERVAL = 3.0


def load_keys() -> None:
    """KEY=value lines into the environment; real env vars win, missing file is fine."""
    if not KEYS_FILE.is_file():
        return
    for line in KEYS_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        v = v.strip()
        if v:
            os.environ.setdefault(k.strip(), v)


def multipart(fields: dict[str, str], filename: str, blob: bytes) -> tuple[bytes, str]:
    """Hand-rolled multipart so this script needs nothing outside the stdlib."""
    boundary = f"----luauui{uuid.uuid4().hex}"
    out = bytearray()
    for name, value in fields.items():
        out += f"--{boundary}\r\n".encode()
        out += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        out += value.encode("utf-8") + b"\r\n"
    out += f"--{boundary}\r\n".encode()
    out += f'Content-Disposition: form-data; name="fileContent"; filename="{filename}"\r\n'.encode()
    out += b"Content-Type: image/png\r\n\r\n"
    out += blob + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={boundary}"


def call(url: str, key: str, body: bytes | None = None, content_type: str | None = None) -> dict:
    req = urllib.request.Request(url, data=body, method="POST" if body else "GET")
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise SystemExit(f"HTTP {e.code} from {url}\n{detail}") from e


def upload_one(path: pathlib.Path, key: str, creator: str) -> tuple[str, str]:
    request = {
        "assetType": "Image",  # NOT "Decal" -- see the module docstring
        "displayName": path.stem,
        "description": "LuauUI standard icon set. Near-white silhouette on transparency; colour comes from the theme's tintRole.",
        "creationContext": {"creator": {"userId": creator}},
    }
    body, ctype = multipart({"request": json.dumps(request)}, path.name, path.read_bytes())
    started = call(CREATE_URL, key, body, ctype)
    op = started.get("operationId") or (started.get("path") or "").split("/")[-1]
    if not op:
        raise SystemExit(f"{path.name}: no operationId in {started}")
    for _ in range(POLL_ATTEMPTS):
        time.sleep(POLL_INTERVAL)
        result = call(OPERATION_URL.format(op), key)
        if not result.get("done"):
            continue
        response = result.get("response") or {}
        asset_id = response.get("assetId")
        moderation = (response.get("moderationResult") or {}).get("moderationState")
        if not asset_id:
            raise SystemExit(f"{path.name}: operation finished with no assetId: {result}")
        # MODERATION IS ASYNCHRONOUS, and "Reviewing" is not a failure. The
        # operation completing means the asset EXISTS and has an id; approval
        # lands separately, usually within minutes for flat UI art. Treating
        # `Reviewing` as fatal (the first version of this script did) throws away
        # a perfectly good upload and would re-upload it on the next run, so the
        # state is RECORDED instead -- `--recheck` re-reads it later. Only an
        # outright rejection stops the run.
        if moderation == "Rejected":
            raise SystemExit(f"{path.name}: moderation REJECTED the asset")
        # the returned assetType is the check that matters: an Image, not a Decal
        if response.get("assetType") not in (None, "Image"):
            raise SystemExit(f"{path.name}: came back as {response.get('assetType')!r}, not Image")
        return f"rbxassetid://{asset_id}", str(moderation or "Unknown")
    raise SystemExit(f"{path.name}: operation {op} never completed")


def recheck(key: str, assets: dict) -> None:
    """Re-read each asset's moderation state.

    Moderation is asynchronous, so the state recorded at upload time is a
    snapshot, not a verdict. This asks Open Cloud what it says NOW. It is also
    the check that answers the question that actually matters -- is this an
    IMAGE? -- by asset IDENTITY rather than by decode state: a client-side
    `IsLoaded` read is not evidence (a known-good shipped asset reads `false`
    too), which cost a round on 2026-07-27.
    """
    for name, record in sorted(assets.items()):
        asset_id = str(record.get("contentId", "")).rsplit("/", 1)[-1]
        if not asset_id:
            continue
        info = call(f"https://apis.roblox.com/assets/v1/assets/{asset_id}", key)
        state = (info.get("moderationResult") or {}).get("moderationState") or "Unknown"
        kind = info.get("assetType") or "Unknown"
        record["moderation"] = state
        record["assetType"] = kind
        flag = "" if (state == "Approved" and kind == "Image") else "   <-- check"
        print(f"  {name:32s} {state:12s} {kind}{flag}")


def write_registry(assets: dict, names: dict[str, str]) -> None:
    """Push the manifest's content ids into the Luau registry.

    The registry is the source of truth the framework READS and the manifest is
    the record of what was uploaded; writing one from the other is what keeps
    them from drifting the way a hand-transcribed id can. `check_docs` asserts
    the agreement independently.
    """
    src = REGISTRY.read_text(encoding="utf-8")
    for icon_name, asset_name in names.items():
        content_id = (assets.get(asset_name) or {}).get("contentId")
        if not content_id:
            continue
        # located in two hops rather than one literal, because the entries are
        # wrapped by the formatter and `assetName`/`contentId` do not always end
        # up on the same line
        anchor = src.index(f'assetName = "{asset_name}"')
        start = src.index("contentId = ", anchor) + len("contentId = ")
        end = src.index(",", start)
        src = src[:start] + f'"{content_id}"' + src[end:]
    REGISTRY.write_text(src, encoding="utf-8")
    print(f"registry -> {REGISTRY}")


def registry_names() -> dict[str, str]:
    """icon name -> assetName, scraped from the Luau registry that is the source of truth."""
    src = REGISTRY.read_text(encoding="utf-8")
    body = src[src.index("standard_icons.ART") :]
    out: dict[str, str] = {}
    for chunk in body.split('["')[1:]:
        name = chunk.split('"]', 1)[0]
        if 'assetName = "' not in chunk:
            continue
        out[name] = chunk.split('assetName = "', 1)[1].split('"', 1)[0]
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="re-upload assets that already have an id")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--recheck", action="store_true", help="re-read moderation state and asset type; upload nothing")
    args = ap.parse_args()

    load_keys()
    key = os.environ.get("ROBLOX_API_KEY", "").strip()
    if not key and not args.dry_run:
        print(f"ROBLOX_API_KEY is not set (looked in the environment and {KEYS_FILE})", file=sys.stderr)
        return 1
    creator = os.environ.get("ROBLOX_CREATOR_USER_ID", DEFAULT_CREATOR).strip()

    names = registry_names()
    existing = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.is_file() else {}
    assets = existing.get("assets", {})

    if args.recheck:
        recheck(key, assets)
        existing["assets"] = dict(sorted(assets.items()))
        MANIFEST.write_text(json.dumps(existing, indent=2) + "\n", encoding="utf-8")
        write_registry(assets, names)
        return 0

    for icon_name, asset_name in sorted(names.items()):
        path = ICON_DIR / f"{asset_name}.png"
        if not path.is_file():
            print(f"MISSING {path} — run assets/icons/source/generate_icons.py", file=sys.stderr)
            return 1
        record = assets.get(asset_name, {})
        if record.get("contentId") and not args.force:
            print(f"  skip   {asset_name}  {record['contentId']}")
            continue
        if args.dry_run:
            print(f"  would upload  {asset_name}")
            continue
        content_id, moderation = upload_one(path, key, creator)
        assets[asset_name] = {
            "file": path.name,
            "contentId": content_id,
            "size": "128x128",
            "sliceBorder": 0,
            "slot": f"icons.{icon_name}",
            "state": "default",
            "moderation": moderation,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        print(f"  upload {asset_name}  {content_id}  ({moderation})")

    if args.dry_run:
        return 0

    MANIFEST.write_text(
        json.dumps(
            {
                "schema": "luauui-theme-assets/1",
                "package": "luauui-standard-icons",
                "stage": "compact-label",
                "uploaded": datetime.date.today().isoformat(),
                "method": (
                    "Roblox Open Cloud POST /assets/v1/assets with assetType=Image, polled to done via "
                    "/assets/v1/operations/<id>, by tools/upload_icons.py. FULLY HEADLESS -- no Studio and no "
                    "human step, unlike the eleven per-package assets that went up through the Studio MCP "
                    "upload_image route. assetType=Image (not Decal) returns a real Image asset, AssetTypeId 1."
                ),
                "note": (
                    "Framework-owned art, not a theme package: it resolves BELOW a package's own icons and "
                    "ABOVE the ASCII fallback glyph (src/themes/package.luau resolveIcon). One near-white "
                    "#F0F0F2 silhouette per name, no per-state variants -- tintRole owns the colour, and "
                    "ImageColor3 multiplies, so white reaches every palette while black could only darken. "
                    "Regenerate the PNGs with assets/icons/source/generate_icons.py."
                ),
                "assets": dict(sorted(assets.items())),
                "uploadedBy": "compact-label stage (the standard icon set that makes compactLabel's image form usable)",
                "uploadedFiles": sorted(assets.keys()),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"\nmanifest -> {MANIFEST}")
    write_registry(assets, names)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

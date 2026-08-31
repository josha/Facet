#!/usr/bin/env python3
"""Distribution spike, step 2: try a same-ID content update, then list versions.

Answers the two remaining route questions against the THROWAWAY asset
83627005624999 ("Facet-Spike-DeleteMe"):
  1. Does PATCH /v1/assets/{id} accept new .rbxm content (docs say .fbx only)?
  2. What does GET /v1/assets/{id}/versions report afterwards?

Writes raw responses to artifacts/distribution-readiness/spike/update-response.json.
Reads ROBLOX_API_KEY from the environment or GameStudio/tools/API_KEYS.txt; the
key is never printed.

Run from the Facet repository root:
    python3 artifacts/distribution-readiness/spike/spike_update.py
"""
import json
import os
import pathlib
import time
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[3]
os.chdir(ROOT)
ASSET_ID = "83627005624999"

key = os.environ.get("ROBLOX_API_KEY", "")
if not key:
    keys = ROOT.parents[1] / "tools" / "API_KEYS.txt"
    if keys.exists():
        for line in keys.read_text().splitlines():
            if line.strip().startswith("ROBLOX_API_KEY="):
                key = line.split("=", 1)[1].strip()
                break
if not key:
    raise SystemExit("ROBLOX_API_KEY not found")

record = {}

def call(name, req):
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode())
            record[name] = {"ok": True, "body": data}
            return data
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:600]
        record[name] = {"ok": False, "http": e.code, "body": body}
        print(f"{name}: HTTP {e.code}: {body}")
        return None

rbxm = pathlib.Path("build/Facet.rbxm").read_bytes()
request_json = json.dumps(
    {
        "assetType": "Model",
        "assetId": ASSET_ID,
        "creationContext": {"creator": {"userId": "1364639953"}},
    }
)
boundary = uuid.uuid4().hex
body = (
    f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n'
    f"Content-Type: application/json\r\n\r\n{request_json}\r\n"
).encode()
body += (
    f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; '
    f'filename="Facet.rbxm"\r\nContent-Type: model/x-rbxm\r\n\r\n'
).encode() + rbxm + b"\r\n"
body += f"--{boundary}--\r\n".encode()

patch = urllib.request.Request(
    f"https://apis.roblox.com/assets/v1/assets/{ASSET_ID}",
    data=body,
    method="PATCH",
    headers={"x-api-key": key, "Content-Type": f"multipart/form-data; boundary={boundary}"},
)
op = call("patch", patch)
if op:
    print("patch operation:", json.dumps(op))
    path = op.get("path") or (f"operations/{op['operationId']}" if op.get("operationId") else None)
    final = None
    if path:
        for _ in range(40):
            time.sleep(5)
            state = call(
                "patch-poll",
                urllib.request.Request(
                    f"https://apis.roblox.com/assets/v1/{path}", headers={"x-api-key": key}
                ),
            )
            if state and state.get("done"):
                final = state
                break
    record["patch-final"] = final
    print("patch final:", json.dumps(final, indent=1)[:800] if final else "timed out")

versions = call(
    "versions",
    urllib.request.Request(
        f"https://apis.roblox.com/assets/v1/assets/{ASSET_ID}/versions",
        headers={"x-api-key": key},
    ),
)
print("versions:", json.dumps(versions, indent=1)[:800] if versions else "unreadable")

out = pathlib.Path("artifacts/distribution-readiness/spike/update-response.json")
out.write_text(json.dumps(record, indent=1))
print("raw responses saved to", out)

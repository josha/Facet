#!/usr/bin/env python3
"""Distribution spike, step 3: PATCH with DIFFERENT content to break the tie.

Step 2 PATCHed byte-identical content and nothing changed — which could mean
".rbxm content updates are unsupported" (what the docs say) or "identical bytes
were deduplicated". This builds a tiny, clearly-different Model (one
ModuleScript with a SpikeMarker child), PATCHes it to the throwaway asset
83627005624999, polls, and lists versions again. A version 2 appearing means
same-ID `.rbxm` updates DO work over Open Cloud; still-version-1 means they do
not and the Studio route is confirmed.

Writes raw responses to artifacts/distribution-readiness/spike/update2-response.json.
Reads ROBLOX_API_KEY from env or GameStudio/tools/API_KEYS.txt; never prints it.

Run from the Facet repository root:
    python3 artifacts/distribution-readiness/spike/spike_update2.py
"""
import json
import os
import pathlib
import subprocess
import tempfile
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

# Build a tiny, clearly-different Model with the pinned toolchain.
env = dict(os.environ)
env["PATH"] = f"{os.path.expanduser('~')}/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:" + env.get("PATH", "")
with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    (tmp / "src").mkdir()
    (tmp / "src" / "init.luau").write_text('return { SPIKE = "update2", VERSION = "0.0.0-spike2" }\n')
    (tmp / "src" / "SpikeMarker.txt").write_text("spike update 2 marker\n")
    (tmp / "p.project.json").write_text(json.dumps({"name": "FacetSpike2", "tree": {"$path": "src"}}))
    out = tmp / "spike2.rbxm"
    subprocess.run(["rojo", "build", str(tmp / "p.project.json"), "-o", str(out)], check=True, env=env)
    rbxm = out.read_bytes()
print(f"distinct payload built: {len(rbxm)} bytes")

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
    f'filename="spike2.rbxm"\r\nContent-Type: model/x-rbxm\r\n\r\n'
).encode() + rbxm + b"\r\n"
body += f"--{boundary}--\r\n".encode()

op = call(
    "patch2",
    urllib.request.Request(
        f"https://apis.roblox.com/assets/v1/assets/{ASSET_ID}",
        data=body,
        method="PATCH",
        headers={"x-api-key": key, "Content-Type": f"multipart/form-data; boundary={boundary}"},
    ),
)
final = None
if op:
    print("patch operation:", json.dumps(op))
    path = op.get("path") or (f"operations/{op['operationId']}" if op.get("operationId") else None)
    if path:
        for _ in range(40):
            time.sleep(5)
            state = call(
                "patch2-poll",
                urllib.request.Request(
                    f"https://apis.roblox.com/assets/v1/{path}", headers={"x-api-key": key}
                ),
            )
            if state and state.get("done"):
                final = state
                break
    record["patch2-final"] = final
    print("patch final:", json.dumps(final, indent=1)[:900] if final else "timed out")

versions = call(
    "versions-after",
    urllib.request.Request(
        f"https://apis.roblox.com/assets/v1/assets/{ASSET_ID}/versions",
        headers={"x-api-key": key},
    ),
)
print("versions now:", json.dumps(versions, indent=1)[:900] if versions else "unreadable")

out = pathlib.Path("artifacts/distribution-readiness/spike/update2-response.json")
out.write_text(json.dumps(record, indent=1))
print("raw responses saved to", out)

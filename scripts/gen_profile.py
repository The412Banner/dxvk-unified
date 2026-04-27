#!/usr/bin/env python3
import json, os, sys

stage, version = sys.argv[1], sys.argv[2]

files = []
for name in sorted(os.listdir(os.path.join(stage, "system32"))):
    if name.endswith(".dll"):
        files.append({"source": "system32/" + name, "target": "${system32}/" + name})
for name in sorted(os.listdir(os.path.join(stage, "syswow64"))):
    if name.endswith(".dll"):
        files.append({"source": "syswow64/" + name, "target": "${syswow64}/" + name})

profile = {
    "type": "DXVK",
    "versionName": version,
    "versionCode": 0,
    "description": "Unified D3D1-12 to Vulkan (Upstream: Philip Rebohle / Hans-Kristian Arntzen)",
    "files": files
}

with open(os.path.join(stage, "profile.json"), "w") as f:
    json.dump(profile, f, indent=2)

print(json.dumps(profile, indent=2))

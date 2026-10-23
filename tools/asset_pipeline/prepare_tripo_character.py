"""Preserve the supplied skin and clips while naming them for the game."""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / "assets/characters/newcomer_tripo"
source = DIRECTORY / "source/newcomer_tripo_original.glb"
payload = source.read_bytes()
magic, version, total = struct.unpack_from("<III", payload)
if magic != 0x46546C67 or version != 2 or total != len(payload):
    raise ValueError("Invalid source GLB")
json_length, json_kind = struct.unpack_from("<II", payload, 12)
document = json.loads(payload[20:20 + json_length])
clips = []
for animation in document.get("animations", []):
    original_name = animation.get("name", "")
    name = original_name.split(".")[0].lower()
    if name not in ("idle", "walk"):
        raise ValueError("Unexpected clip; map it explicitly: " + original_name)
    animation["name"] = name
    clips.append({"source_name": original_name, "name": name,
                  "duration_seconds": max(document["accessors"][sampler["input"]]["max"][0]
                                          for sampler in animation["samplers"])})
if {clip["name"] for clip in clips} != {"idle", "walk"}:
    raise ValueError("Both actual idle and walk clips are required")
encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
encoded += b" " * (-len(encoded) % 4)
remainder = payload[20 + json_length:]
result = struct.pack("<III", magic, version, 20 + len(encoded) + len(remainder))
result += struct.pack("<II", len(encoded), json_kind) + encoded + remainder
(DIRECTORY / "newcomer.glb").write_bytes(result)
positions = [document["accessors"][primitive["attributes"]["POSITION"]]
             for mesh in document["meshes"] for primitive in mesh["primitives"]]
height = max(accessor["max"][1] for accessor in positions) - min(accessor["min"][1] for accessor in positions)
report = {
    "source": "User-provided Tripo GLB with selected idle/walk animations",
    "source_sha256": hashlib.sha256(payload).hexdigest(),
    "output_sha256": hashlib.sha256(result).hexdigest(),
    "vertices": sum(accessor["count"] for accessor in positions),
    "triangles": sum(document["accessors"][primitive["indices"]]["count"] // 3
                     for mesh in document["meshes"] for primitive in mesh["primitives"]),
    "bones": len(document["skins"][0]["joints"]),
    "clips": clips,
    "bind_height_m": height,
    "target_height_m": 1.75,
    "scene_uniform_scale": 1.75 / height,
    "processing": "Only clip names normalized. Original geometry, weights, keyframes and textures preserved.",
    "missing_clips": ["run", "dodge", "attack", "hit", "death", "fishing"],
}
(DIRECTORY / "import_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))

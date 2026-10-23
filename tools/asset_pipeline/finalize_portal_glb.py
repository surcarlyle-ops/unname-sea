"""Convert extracted source art and restore basic PBR materials in a GLB."""
import json
import sys
import struct
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / ".deps"))
import OpenEXR
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/environments/portal_ruins"
REPORTS = ROOT / "docs/art/ue_portal_import"
TEXTURES = ASSETS / "textures"
(TEXTURES / ".gdignore").touch()
inventory = json.loads((REPORTS / "level_inventory.json").read_text(encoding="utf-8"))
sources = json.loads((REPORTS / "material_sources.json").read_text(encoding="utf-8"))
actors = {actor["label"]: actor for actor in inventory["actors"]}
converted = {}
for path in sorted(TEXTURES.iterdir()):
    if path.suffix.lower() == ".exr":
        channels = OpenEXR.File(str(path)).channels()
        if "RGB" in channels:
            pixels = channels["RGB"].pixels
        elif "RGBA" in channels:
            pixels = channels["RGBA"].pixels[:, :, :3]
        else:
            pixels = np.stack([channels[name].pixels for name in ("R", "G", "B")], axis=-1)
        rgb = np.clip(pixels.astype(np.float32), 0.0, 1.0)
        srgb = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.power(rgb, 1.0 / 2.4) - 0.055)
        image = Image.fromarray(np.uint8(np.clip(srgb, 0.0, 1.0) * 255.0 + 0.5))
    elif path.suffix.lower() == ".tga":
        image = Image.open(path).convert("RGB")
    else:
        continue
    image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
    destination = path.with_suffix(".png")
    image.save(destination)
    converted[path.stem] = destination

data = (ASSETS / "portal_ruins_geometry.glb").read_bytes()
json_length = struct.unpack_from("<I", data, 12)[0]
document = json.loads(data[20:20 + json_length])
binary_start = 20 + json_length
binary_length = struct.unpack_from("<I", data, binary_start)[0]
binary = bytearray(data[binary_start + 8:binary_start + 8 + binary_length])
document["materials"] = []
document["images"] = []
document["textures"] = []
document["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
material_indices = {}
image_indices = {}


def embed_texture(path):
    if path.name in image_indices:
        return image_indices[path.name]
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    payload = path.read_bytes()
    binary.extend(payload)
    view = len(document["bufferViews"])
    document["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(payload)})
    image_index = len(document["images"])
    document["images"].append({"bufferView": view, "mimeType": "image/png", "name": path.stem})
    texture_index = len(document["textures"])
    document["textures"].append({"source": image_index, "sampler": 0})
    image_indices[path.name] = texture_index
    return texture_index


def get_material(asset):
    if asset in material_indices:
        return material_indices[asset]
    name = asset.rsplit(".", 1)[-1] if asset else "TerrainPreview"
    material = {"name": name, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.9}}
    pbr = material["pbrMetallicRoughness"]
    record = sources.get(name, {})
    candidates = record.get("candidate_textures", [])
    texture = next((converted[path.rsplit(".", 1)[-1]] for path in candidates
                    if path.rsplit(".", 1)[-1] in converted), None)
    if name == "mat_portal":
        texture = converted.get("PORTAL_材质_001_BaseColor")
    elif name == "pt2":
        texture = converted.get("portal3_low_材质_002_BaseColor")
    if texture:
        pbr["baseColorTexture"] = {"index": embed_texture(texture)}
    else:
        pbr["baseColorFactor"] = [0.40, 0.48, 0.25, 1.0] if not asset else [0.59, 0.60, 0.49, 1.0]
    index = len(document["materials"])
    document["materials"].append(material)
    material_indices[asset] = index
    return index


def apply_actor_materials(index, actor):
    node = document["nodes"][index]
    if "mesh" in node:
        mesh = document["meshes"][node["mesh"]]
        if mesh.get("name", "").startswith("LandscapeComponent"):
            materials = [None]
        else:
            components = actor.get("meshes", [])
            component = next((part for part in components if part["component"] == node.get("name")), None)
            component = component or (components[0] if components else {})
            materials = component.get("materials", [None])
        for primitive_index, primitive in enumerate(mesh["primitives"]):
            primitive["material"] = get_material(materials[min(primitive_index, len(materials) - 1)])
    for child in node.get("children", []):
        apply_actor_materials(child, actor)


for root_index in document["scenes"][document.get("scene", 0)]["nodes"]:
    root_node = document["nodes"][root_index]
    actor = actors.get(root_node.get("name"), {})
    apply_actor_materials(root_index, actor)
while len(binary) % 4:
    binary.append(0)
document["buffers"][0]["byteLength"] = len(binary)
json_data = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
json_data += b" " * ((-len(json_data)) % 4)
total = 12 + 8 + len(json_data) + 8 + len(binary)
result = struct.pack("<III", 0x46546C67, 2, total)
result += struct.pack("<II", len(json_data), 0x4E4F534A) + json_data
result += struct.pack("<II", len(binary), 0x004E4942) + binary
destination = ASSETS / "portal_ruins_sample.glb"
destination.write_bytes(result)
summary = {"file": str(destination), "bytes": len(result), "meshes": len(document["meshes"]),
           "triangles_unique_meshes": sum(document["accessors"][primitive["indices"]]["count"] // 3
                                          for mesh in document["meshes"] for primitive in mesh["primitives"]),
           "materials": len(document["materials"]), "embedded_base_color_textures": len(document["images"]),
           "terrain_material": "Flat preview color; original layered shader not baked.",
           "texture_conversion": "EXR linear RGB converted to sRGB; maximum 1024 px for preview."}
(REPORTS / "godot_asset_report.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
print(json.dumps(summary, indent=2))

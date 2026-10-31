"""Import the few Ultimate Stylized Nature models the shore area uses.

Source: Quaternius, "Ultimate Stylized Nature" (May 2022), License.txt = CC0 1.0.
The pack ships 4K normal maps (18-22 MB each) that a stylized test area does not
need, so each copied glTF has its normalTexture reference stripped and only the
diffuse / leaf atlases are copied next to it. Geometry, UVs and materials are
otherwise untouched (byte-for-byte glTF + .bin).

Run:  python tools/asset_pipeline/import_stylized_nature.py
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

SOURCE = Path(
    r"C:\Users\QAQ\Downloads\Ultimate Stylized Nature - May 2022-20261028T081630Z-1-001"
    r"\Ultimate Stylized Nature - May 2022\glTF"
)
TARGET = Path(__file__).resolve().parents[2] / "assets" / "environments" / "stylized_nature"

# Shore test area only needs a handful: two canopy trees, one dead tree for the
# bank, two bushes, one grass clump and two flower/reeds clumps.
MODELS = [
    "BirchTree_1",
    "MapleTree_2",
    "DeadTree_3",
    "Bush_Large",
    "Bush_Small",
    "Grass_Large_Extruded",
    "Flower_2_Clump",
    "Flower_3_Clump",
]


def strip_normals(document: dict) -> None:
    """Drop normalTexture and prune images/textures that become unreferenced."""
    for material in document.get("materials", []):
        material.pop("normalTexture", None)

    used: list[int] = []
    for material in document.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        for slot in ("baseColorTexture", "metallicRoughnessTexture"):
            if slot in pbr:
                used.append(int(pbr[slot]["index"]))
        for slot in ("occlusionTexture", "emissiveTexture"):
            if slot in material:
                used.append(int(material[slot]["index"]))

    textures = document.get("textures", [])
    remap: dict[int, int] = {}
    kept_textures: list[dict] = []
    for index, texture in enumerate(textures):
        if index in used:
            remap[index] = len(kept_textures)
            kept_textures.append(texture)
    for material in document.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        for slot in ("baseColorTexture", "metallicRoughnessTexture"):
            if slot in pbr:
                pbr[slot]["index"] = remap[int(pbr[slot]["index"])]
        for slot in ("occlusionTexture", "emissiveTexture"):
            if slot in material:
                material[slot]["index"] = remap[int(material[slot]["index"])]
    document["textures"] = kept_textures

    images = document.get("images", [])
    used_images: list[int] = []
    for texture in kept_textures:
        if "source" in texture:
            used_images.append(int(texture["source"]))
    image_remap: dict[int, int] = {}
    kept_images: list[dict] = []
    for index, image in enumerate(images):
        if index in used_images:
            image_remap[index] = len(kept_images)
            kept_images.append(image)
    for texture in kept_textures:
        if "source" in texture:
            texture["source"] = image_remap[int(texture["source"])]
    document["images"] = kept_images


def bounds(document: dict) -> tuple[list[float], list[float]]:
    """POSITION accessor min/max of the first primitive, for scale decisions."""
    primitive = document["meshes"][0]["primitives"][0]
    accessor = document["accessors"][primitive["attributes"]["POSITION"]]
    return accessor.get("min", []), accessor.get("max", [])


def main() -> None:
    TARGET.mkdir(parents=True, exist_ok=True)
    copied: set[str] = set()
    for name in MODELS:
        source_gltf = SOURCE / f"{name}.gltf"
        document = json.loads(source_gltf.read_text(encoding="utf-8"))
        strip_normals(document)
        low, high = bounds(document)
        (TARGET / f"{name}.gltf").write_text(
            json.dumps(document, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        shutil.copy2(SOURCE / f"{name}.bin", TARGET / f"{name}.bin")
        for image in document.get("images", []):
            uri = str(image.get("uri", ""))
            if uri and uri not in copied:
                shutil.copy2(SOURCE / uri, TARGET / uri)
                copied.add(uri)
        size = [round(h - l, 3) for l, h in zip(low, high)] if low and high else []
        print(f"{name:24s} bounds={size} images={[i.get('uri') for i in document.get('images', [])]}")
    print(f"copied {len(copied)} textures -> {TARGET}")


if __name__ == "__main__":
    main()

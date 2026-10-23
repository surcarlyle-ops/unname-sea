"""Normalize and skin the supplied glove, preserving its original UVs and texture."""
from __future__ import annotations

import copy
import hashlib
import json
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / "assets/characters/fps_gloves"
SOURCE = ASSET / "source/hand_glove_04_raw.glb"
COMPONENTS = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path: Path) -> tuple[dict, bytes]:
    payload = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", payload)
    if magic != 0x46546C67 or version != 2 or length != len(payload):
        raise ValueError("Invalid GLB")
    size, kind = struct.unpack_from("<II", payload, 12)
    if kind != 0x4E4F534A:
        raise ValueError("Missing JSON chunk")
    document = json.loads(payload[20:20 + size])
    offset = 20 + size
    binary_size, binary_kind = struct.unpack_from("<II", payload, offset)
    if binary_kind != 0x004E4942:
        raise ValueError("Missing binary chunk")
    return document, payload[offset + 8:offset + 8 + binary_size]


def array(document: dict, binary: bytes, index: int) -> np.ndarray:
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    dtype = np.dtype(COMPONENTS[accessor["componentType"]])
    width = WIDTHS[accessor["type"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", dtype.itemsize * width)
    return np.ndarray((accessor["count"], width), dtype=dtype, buffer=binary,
                      offset=offset, strides=(stride, dtype.itemsize)).copy()


def normalize(positions: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, float]:
    center = positions.mean(axis=0)
    _, vectors = np.linalg.eigh(np.cov((positions - center).T))
    longitudinal = vectors[:, 2]
    if longitudinal[0] < 0:
        longitudinal *= -1
    normal = vectors[:, 0]
    if normal[2] < 0:
        normal *= -1
    lateral = np.cross(longitudinal, normal)
    rotation = np.stack([lateral, normal, -longitudinal])
    projected = positions @ rotation.T
    total = np.ptp(projected[:, 2])
    scale = 0.48 / total
    # The dorsal wrist seam is the reference origin; exact landmarks follow in the layout file.
    wrist_long = np.max(projected[:, 2]) - total * 0.53
    wrist_section = projected[np.abs(projected[:, 2] - wrist_long) < total * 0.025]
    origin = np.array([np.median(wrist_section[:, 0]), np.median(wrist_section[:, 1]), wrist_long])
    return (projected - origin) * scale, rotation, origin, scale


def inspect() -> None:
    document, binary = read_glb(SOURCE)
    primitive = document["meshes"][0]["primitives"][0]
    raw = array(document, binary, primitive["attributes"]["POSITION"])
    points, rotation, origin, scale = normalize(raw)
    for lo in np.arange(-0.22, 0.08, 0.02):
        section = points[(points[:, 2] >= lo) & (points[:, 2] < lo + 0.02)]
        if len(section):
            print("z=%.2f..%.2f count=%d x-range=%s y-range=%s" % (
                lo, lo + 0.02, len(section), np.round([section[:, 0].min(), section[:, 0].max()], 4),
                np.round([section[:, 1].min(), section[:, 1].max()], 4)))
    info = {"source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
            "vertices": len(raw), "triangles": int(document["accessors"][primitive["indices"]]["count"] // 3),
            "bounds_m": [points.min(axis=0).tolist(), points.max(axis=0).tolist()],
            "rotation": rotation.tolist(), "origin": origin.tolist(), "scale": scale,
            "skins_in_source": len(document.get("skins", [])), "animations_in_source": len(document.get("animations", []))}
    (ASSET / "source_audit.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    np.save(ASSET / "source" / "normalized_points.npy", points)
    print(json.dumps(info, indent=2))


def smooth(value: np.ndarray) -> np.ndarray:
    t = np.clip(value, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def skin_weights(points: np.ndarray, layout: dict, faces: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray, list[str], np.ndarray, list[int]]:
    names = ["Forearm", "Hand"]
    joints = [layout["forearm"], layout["wrist"]]
    parents = [-1, 0]
    candidates = []
    for name, locations in layout["fingers"].items():
        first = len(joints)
        for index, location in enumerate(locations):
            names.append(name + (str(index + 1) if index < 3 else "Tip"))
            joints.append(location)
            parents.append(1 if index == 0 else len(joints) - 2)
        chain = np.asarray(locations)
        lengths = np.linalg.norm(np.diff(chain, axis=0), axis=1)
        offsets = np.concatenate(([0.0], np.cumsum(lengths)))
        distances, progress = [], []
        for index in range(3):
            vector = chain[index + 1] - chain[index]
            fraction = np.clip((points - chain[index]) @ vector / np.dot(vector, vector), 0.0, 1.0)
            closest = chain[index] + fraction[:, None] * vector
            distances.append(np.linalg.norm(points - closest, axis=1))
            progress.append(offsets[index] + fraction * lengths[index])
        distances = np.stack(distances, axis=1)
        selected = np.argmin(distances, axis=1)
        nearest = distances[np.arange(len(points)), selected]
        along = np.stack(progress, axis=1)[np.arange(len(points)), selected]
        forward = (chain[-1] - chain[0]) / np.linalg.norm(chain[-1] - chain[0])
        root_progress = (points - chain[0]) @ forward
        # A hard radius cut left thick glove vertices behind on the palm bone.
        # Assign the whole digit cross-section and fade its base into the palm instead.
        valid = root_progress > -0.025
        score = np.where(valid, nearest, 100.0)
        candidates.append((first, lengths, offsets, score, along, root_progress))
    indices = np.zeros((len(points), 4), dtype=np.uint16)
    weights = np.zeros((len(points), 4), dtype=np.float32)
    hand = smooth((0.03 - points[:, 2]) / 0.055)
    indices[:, 0], indices[:, 1] = 0, 1
    weights[:, 0], weights[:, 1] = 1.0 - hand, hand
    chosen = np.argmin(np.stack([c[3] for c in candidates], axis=1), axis=1)
    for candidate_index, (first, lengths, offsets, score, along, root_progress) in enumerate(candidates):
        mask = (chosen == candidate_index) & (score < 1.0)
        rows = np.flatnonzero(mask)
        if not len(rows):
            continue
        p = along[rows]
        digit_weight = smooth((root_progress[rows] + 0.025) / 0.045)
        # Neighboring phalanges blend locally around each hinge, not across adjacent fingers.
        proximal_to_middle = smooth((p - offsets[1] + 0.007) / 0.014)
        middle_to_distal = smooth((p - offsets[2] + 0.006) / 0.012)
        indices[rows] = [1, first, first + 1, first + 2]
        weights[rows, 0] = 1.0 - digit_weight
        weights[rows, 1] = digit_weight * (1.0 - proximal_to_middle)
        weights[rows, 2] = digit_weight * proximal_to_middle * (1.0 - middle_to_distal)
        weights[rows, 3] = digit_weight * middle_to_distal
    weights /= weights.sum(axis=1, keepdims=True)
    if faces is not None:
        # Smooth along connected triangles, welding UV duplicates without joining adjacent fingers.
        _, weld = np.unique(np.round(points, 6), axis=0, return_inverse=True)
        count = int(weld.max()) + 1
        dense = np.zeros((count, len(names)))
        hits = np.bincount(weld, minlength=count)
        for influence in range(4):
            np.add.at(dense, (weld, indices[:, influence]), weights[:, influence])
        dense /= hits[:, None]
        edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
        edges = np.unique(np.sort(weld[edges], axis=1), axis=0)
        edges = edges[edges[:, 0] != edges[:, 1]]
        edges = np.concatenate([edges, edges[:, ::-1]])
        degree = np.bincount(edges[:, 0], minlength=count)
        for _ in range(20):
            neighbors = np.zeros_like(dense)
            np.add.at(neighbors, edges[:, 0], dense[edges[:, 1]])
            average = neighbors / np.maximum(degree[:, None], 1)
            dense = np.where(degree[:, None] > 0, dense * .5 + average * .5, dense)
        dense = dense[weld]
        indices = np.argsort(dense, axis=1)[:, -4:].astype(np.uint16)
        weights = np.take_along_axis(dense, indices, axis=1).astype(np.float32)
        weights /= weights.sum(axis=1, keepdims=True)
    return indices, weights, names, np.asarray(joints), parents


def append_array(document: dict, binary: bytearray, values: np.ndarray, kind: str, component: int, bounds: bool = False) -> int:
    binary.extend(b"\x00" * (-len(binary) % 4))
    offset = len(binary)
    data = values.tobytes()
    binary.extend(data)
    view = len(document["bufferViews"])
    document["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(data)})
    accessor = {"bufferView": view, "componentType": component, "count": len(values), "type": kind}
    if bounds:
        accessor.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
    index = len(document["accessors"])
    document["accessors"].append(accessor)
    return index


def write_glb(path: Path, document: dict, binary: bytearray) -> None:
    document["buffers"] = [{"byteLength": len(binary)}]
    encoded = json.dumps(document, separators=(",", ":")).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    binary.extend(b"\x00" * (-len(binary) % 4))
    header = struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
    path.write_bytes(header + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
                     + struct.pack("<II", len(binary), 0x004E4942) + binary)


def build() -> None:
    original, payload = read_glb(SOURCE)
    primitive = original["meshes"][0]["primitives"][0]
    points, rotation, _, _ = normalize(array(original, payload, primitive["attributes"]["POSITION"]))
    normals = array(original, payload, primitive["attributes"]["NORMAL"]) @ rotation.T
    indices = array(original, payload, primitive["indices"]).reshape(-1, 3)
    layout = json.loads((ASSET / "rig_layout.json").read_text(encoding="utf-8"))
    skin_indices, weights, names, joint_points, parents = skin_weights(points, layout, indices)
    report = json.loads((ASSET / "source_audit.json").read_text(encoding="utf-8"))
    report.update(bones=len(names), skinning="Custom 22-joint forearm/hand rig; geometric weights authored for this mesh",
                  animations="Procedural finger poses in fps_glove.gd; no motion clips supplied by Tripo",
                  weights_finite=bool(np.isfinite(weights).all()), weights_max_sum_error=float(np.max(np.abs(weights.sum(axis=1) - 1.0))),
                  source_unchanged=hashlib.sha256(SOURCE.read_bytes()).hexdigest() == report["source_sha256"])
    for left in (False, True):
        document, binary = copy.deepcopy(original), bytearray(payload)
        side = "left" if left else "right"
        reflected = np.array([-1.0 if left else 1.0, 1.0, 1.0])
        vertices = (points * reflected).astype("<f4")
        vertex_normals = (normals * reflected).astype("<f4")
        joint_locations = joint_points * reflected
        output_primitive = document["meshes"][0]["primitives"][0]
        output_primitive["attributes"]["POSITION"] = append_array(document, binary, vertices, "VEC3", 5126, True)
        output_primitive["attributes"]["NORMAL"] = append_array(document, binary, vertex_normals, "VEC3", 5126)
        output_primitive["attributes"]["JOINTS_0"] = append_array(document, binary, skin_indices, "VEC4", 5123)
        output_primitive["attributes"]["WEIGHTS_0"] = append_array(document, binary, weights, "VEC4", 5126)
        output_indices = indices[:, [0, 2, 1]] if left else indices
        output_primitive["indices"] = append_array(document, binary, output_indices.astype("<u4").reshape(-1, 1), "SCALAR", 5125)
        nodes = [{"name": "Glove_" + side, "children": [1, 2]}, {"name": "GloveMesh", "mesh": 0, "skin": 0}]
        for i, name in enumerate(names):
            parent = parents[i]
            translation = joint_locations[i] - (joint_locations[parent] if parent >= 0 else 0)
            children = [2 + j for j, p in enumerate(parents) if p == i]
            node = {"name": name, "translation": translation.tolist()}
            if children:
                node["children"] = children
            nodes.append(node)
        bind = np.repeat(np.eye(4)[None, :, :], len(names), axis=0)
        bind[:, :3, 3] = -joint_locations
        bind_accessor = append_array(document, binary, bind.transpose(0, 2, 1).reshape(-1, 16).astype("<f4"), "MAT4", 5126)
        document["nodes"] = nodes
        document["scenes"] = [{"name": "Glove_" + side, "nodes": [0]}]
        document["scene"] = 0
        document["skins"] = [{"name": "GloveRig", "inverseBindMatrices": bind_accessor, "joints": list(range(2, len(nodes))), "skeleton": 2}]
        document.pop("animations", None)
        for material in document.get("materials", []):
            material["pbrMetallicRoughness"]["roughnessFactor"] = 0.78
        document["asset"]["generator"] = "Tripo original mesh; Codex glove normalization, skinning and baked left-hand mirror"
        output = ASSET / ("glove_" + side + ".glb")
        write_glb(output, document, binary)
        report[side + "_sha256"] = hashlib.sha256(output.read_bytes()).hexdigest()
    report["triangles_pair"] = report["triangles"] * 2
    (ASSET / "import_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    inspect()
    build()

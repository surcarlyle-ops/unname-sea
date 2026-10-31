"""Extend only the sword's middle section; preserve the hilt, tip silhouette and UVs."""
from pathlib import Path
import hashlib
import json
import math
import struct

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/weapons/fantasy sword 3d model.glb'
OUTPUT = ROOT / 'assets/weapons/tide_blade_long.glb'
BASE, LOWER, UPPER, MULTIPLIER = 0.48, 0.56, 0.88, 1.5

def main():
    original = SOURCE.read_bytes()
    json_size = struct.unpack_from('<I', original, 12)[0]
    doc = json.loads(original[20:20 + json_size])
    binary_header = 20 + json_size
    binary_size, kind = struct.unpack_from('<II', original, binary_header)
    assert kind == 0x004E4942
    binary = bytearray(original[binary_header + 8:binary_header + 8 + binary_size])
    primitive = doc['meshes'][0]['primitives'][0]
    position = doc['accessors'][primitive['attributes']['POSITION']]
    normal = doc['accessors'][primitive['attributes']['NORMAL']]
    old_tip = position['max'][1]
    extension = (old_tip - BASE) * (MULTIPLIER - 1)
    stretch = 1 + extension / (UPPER - LOWER)
    def offset(accessor, index):
        view = doc['bufferViews'][accessor['bufferView']]
        assert accessor['componentType'] == 5126 and accessor['type'] == 'VEC3'
        return view.get('byteOffset', 0) + accessor.get('byteOffset', 0) + index * view.get('byteStride', 12)
    positions, normals = [], []
    fixed_count = 0
    for i in range(position['count']):
        po, no = offset(position, i), offset(normal, i)
        x, y, z = struct.unpack_from('<3f', binary, po)
        nx, ny, nz = struct.unpack_from('<3f', binary, no)
        if y <= LOWER:
            new_y, derivative = y, 1
            fixed_count += 1
        elif y >= UPPER:
            new_y, derivative = y + extension, 1
        else:
            new_y, derivative = LOWER + (y - LOWER) * stretch, stretch
        ny /= derivative
        length = math.sqrt(nx * nx + ny * ny + nz * nz)
        updated_normal = (nx / length, ny / length, nz / length) if length else (0, 1, 0)
        struct.pack_into('<3f', binary, po, x, new_y, z)
        struct.pack_into('<3f', binary, no, *updated_normal)
        positions.append((x, new_y, z))
        normals.append(updated_normal)
    for accessor, values in ((position, positions), (normal, normals)):
        accessor['min'] = [min(v[a] for v in values) for a in range(3)]
        accessor['max'] = [max(v[a] for v in values) for a in range(3)]
    payload = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    payload += b' ' * (-len(payload) % 4)
    result = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(payload) + 8 + len(binary))
    result += struct.pack('<II', len(payload), 0x4E4F534A) + payload
    result += struct.pack('<II', len(binary), 0x004E4942) + binary
    OUTPUT.write_bytes(result)
    metadata = {'source': SOURCE.name, 'source_sha256': hashlib.sha256(original).hexdigest(), 'output': OUTPUT.name,
                'blade_base': BASE, 'original_tip': old_tip, 'new_tip': position['max'][1],
                'blade_length_multiplier': MULTIPLIER, 'extension': extension,
                'stretch_start': LOWER, 'stretch_end': UPPER, 'unchanged_lower_vertices': fixed_count,
                'note': 'Only middle-blade Y positions and their normals changed. Hilt, guard, blade tip shape, X/Z width, UVs, indices and embedded textures preserved. Codex.'}
    OUTPUT.with_suffix('.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(metadata, ensure_ascii=False))

if __name__ == '__main__':
    main()

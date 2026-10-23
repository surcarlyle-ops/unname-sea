"""Convert a local PMX prototype to skinned GLB; MMD physics/IK are not exported."""
from __future__ import annotations

import argparse
import io
import json
import math
import struct
from pathlib import Path

from PIL import Image


class Reader:
    def __init__(self, path: Path) -> None:
        self.data = io.BytesIO(path.read_bytes())

    def unpack(self, fmt: str) -> tuple:
        return struct.unpack('<' + fmt, self.data.read(struct.calcsize('<' + fmt)))

    def value(self, fmt: str) -> int | float:
        return self.unpack(fmt)[0]

    def text(self) -> str:
        size = self.value('i')
        return self.data.read(size).decode(self.encoding, errors='replace')

    def index(self, kind: str) -> int:
        size = self.sizes[kind]
        return self.value(({1: 'B', 2: 'H', 4: 'I'} if kind == 'vertex' else {1: 'b', 2: 'h', 4: 'i'})[size])


def read_pmx(path: Path) -> dict:
    r = Reader(path)
    if r.data.read(4) != b'PMX ':
        raise ValueError('Not a PMX model')
    version = r.value('f')
    header = list(r.data.read(r.value('B')))
    r.encoding = 'utf-16-le' if header[0] == 0 else 'utf-8'
    r.sizes = dict(zip(['vertex', 'texture', 'material', 'bone', 'morph', 'rigid'], header[2:8]))
    name, english, comment, english_comment = [r.text() for _ in range(4)]
    vertices = []
    modes = {}
    for _ in range(r.value('i')):
        position = r.unpack('3f')
        normal = r.unpack('3f')
        uv = r.unpack('2f')
        r.data.read(header[1] * 16)
        mode = r.value('B')
        modes[mode] = modes.get(mode, 0) + 1
        if mode == 0:
            joints, weights = [r.index('bone')], [1.0]
        elif mode in (1, 3):
            joints = [r.index('bone'), r.index('bone')]
            weight = r.value('f')
            weights = [weight, 1.0 - weight]
            if mode == 3:
                r.data.read(36)
        elif mode in (2, 4):
            joints = [r.index('bone') for _ in range(4)]
            weights = list(r.unpack('4f'))
        else:
            raise ValueError(f'Unsupported skinning mode {mode}')
        r.value('f')
        vertices.append((position, normal, uv, joints, weights))
    indices = [r.index('vertex') for _ in range(r.value('i'))]
    textures = [r.text() for _ in range(r.value('i'))]
    materials = []
    for _ in range(r.value('i')):
        material_name, material_english = r.text(), r.text()
        diffuse = r.unpack('4f')
        r.unpack('3f'); r.value('f'); r.unpack('3f')
        flags = r.value('B')
        r.unpack('4f'); r.value('f')
        texture, sphere = r.index('texture'), r.index('texture')
        r.value('B')
        shared_toon = r.value('B')
        r.value('B') if shared_toon else r.index('texture')
        r.text()
        count = r.value('i')
        materials.append(dict(name=material_name, diffuse=diffuse, texture=texture, count=count, flags=flags))
    bones = []
    for _ in range(r.value('i')):
        bone_name, bone_english = r.text(), r.text()
        position, parent = r.unpack('3f'), r.index('bone')
        r.value('i')
        flags = r.value('H')
        r.index('bone') if flags & 1 else r.unpack('3f')
        if flags & 0x0300:
            r.index('bone'); r.value('f')
        if flags & 0x0400:
            r.unpack('3f')
        if flags & 0x0800:
            r.unpack('6f')
        if flags & 0x2000:
            r.value('i')
        if flags & 0x0020:
            r.index('bone'); r.value('i'); r.value('f')
            for _ in range(r.value('i')):
                r.index('bone')
                if r.value('B'):
                    r.unpack('6f')
        bones.append(dict(name=bone_name, english=bone_english, position=position, parent=parent))
    return dict(name=name, version=version, vertices=vertices, indices=indices,
                textures=textures, materials=materials, bones=bones, skinning_modes=modes)


def quaternion(x: float, y: float, z: float) -> list[float]:
    cx, sx = math.cos(x / 2), math.sin(x / 2)
    cy, sy = math.cos(y / 2), math.sin(y / 2)
    cz, sz = math.cos(z / 2), math.sin(z / 2)
    return [sx * cy * cz - cx * sy * sz, cx * sy * cz + sx * cy * sz,
            cx * cy * sz - sx * sy * cz, cx * cy * cz + sx * sy * sz]


def convert(source: Path, output: Path) -> dict:
    model = read_pmx(source)
    low = min(v[0][1] for v in model['vertices'])
    high = max(v[0][1] for v in model['vertices'])
    scale = 1.78 / (high - low)

    def point(p: tuple) -> list[float]:
        return [p[0] * scale, (p[1] - low) * scale, -p[2] * scale]

    blob = bytearray()
    doc = dict(asset=dict(version='2.0', generator='Local PMX prototype converter'),
               scene=0, scenes=[dict(nodes=[0])], nodes=[dict(name='TrailblazerLocal', children=[])],
               buffers=[dict(byteLength=0)], bufferViews=[], accessors=[], meshes=[],
               materials=[], images=[], textures=[], samplers=[dict(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497)], skins=[], animations=[])

    def view(data: bytes, target: int | None = None) -> int:
        while len(blob) % 4:
            blob.append(0)
        entry = dict(buffer=0, byteOffset=len(blob), byteLength=len(data))
        if target:
            entry['target'] = target
        doc['bufferViews'].append(entry)
        blob.extend(data)
        return len(doc['bufferViews']) - 1

    def accessor(values: list, fmt: str, component: int, kind: str, width: int,
                 target: int | None = None, bounds: bool = False) -> int:
        flat = [v for row in values for v in row] if width > 1 else values
        data = struct.pack('<' + fmt * len(flat), *flat)
        entry = dict(bufferView=view(data, target), componentType=component, count=len(values), type=kind)
        if bounds:
            rows = values if width > 1 else [[v] for v in values]
            entry['min'] = [min(row[i] for row in rows) for i in range(width)]
            entry['max'] = [max(row[i] for row in rows) for i in range(width)]
        doc['accessors'].append(entry)
        return len(doc['accessors']) - 1

    positions = [point(v[0]) for v in model['vertices']]
    normals = [[v[1][0], v[1][1], -v[1][2]] for v in model['vertices']]
    joints, weights = [], []
    for v in model['vertices']:
        js = [max(j, 0) for j in v[3]]
        ws = [w if j >= 0 else 0.0 for j, w in zip(v[3], v[4])]
        total = sum(ws)
        ws = [w / total for w in ws] if total > 0 else [1.0] + [0.0] * (len(ws) - 1)
        joints.append((js + [0] * 4)[:4]); weights.append((ws + [0.0] * 4)[:4])
    attributes = dict(POSITION=accessor(positions, 'f', 5126, 'VEC3', 3, 34962, True),
                      NORMAL=accessor(normals, 'f', 5126, 'VEC3', 3, 34962),
                      TEXCOORD_0=accessor([v[2] for v in model['vertices']], 'f', 5126, 'VEC2', 2, 34962),
                      JOINTS_0=accessor(joints, 'H', 5123, 'VEC4', 4, 34962),
                      WEIGHTS_0=accessor(weights, 'f', 5126, 'VEC4', 4, 34962))
    alpha_textures = set()
    for i, texture in enumerate(model['textures']):
        texture_path = source.parent / texture.replace('\\', '/')
        if not texture_path.is_file():
            raise FileNotFoundError(texture_path)
        with Image.open(texture_path) as image:
            rgba = image.convert('RGBA')
            if rgba.getchannel('A').getextrema()[0] < 250:
                alpha_textures.add(i)
            stream = io.BytesIO(); rgba.save(stream, format='PNG')
        doc['images'].append(dict(name=f'texture_{i}', bufferView=view(stream.getvalue()), mimeType='image/png'))
        doc['textures'].append(dict(source=i, sampler=0))
    primitives, offset = [], 0
    for material in model['materials']:
        indices = model['indices'][offset:offset + material['count']]
        offset += material['count']
        if material['diffuse'][3] < 0.02 or not indices:
            continue
        pbr = dict(baseColorFactor=list(material['diffuse']), metallicFactor=0.0, roughnessFactor=0.85)
        texture = material['texture']
        if texture >= 0:
            pbr['baseColorTexture'] = dict(index=texture)
        mat = dict(name=material['name'], pbrMetallicRoughness=pbr, doubleSided=bool(material['flags'] & 1))
        if texture in alpha_textures or material['diffuse'][3] < 0.99:
            mat.update(alphaMode='MASK', alphaCutoff=0.1)
        doc['materials'].append(mat)
        reversed_indices = [index for i in range(0, len(indices), 3) for index in (indices[i], indices[i+2], indices[i+1])]
        primitives.append(dict(attributes=attributes, indices=accessor(reversed_indices, 'I', 5125, 'SCALAR', 1, 34963), material=len(doc['materials'])-1))
    bone_positions = [point(b['position']) for b in model['bones']]
    for i, bone in enumerate(model['bones']):
        parent = bone['parent']
        base = bone_positions[parent] if parent >= 0 else [0.0, 0.0, 0.0]
        doc['nodes'].append(dict(name=f'bone_{i:03d}', translation=[a-b for a,b in zip(bone_positions[i], base)], extras=dict(pmx_name=bone['name'])))
    roots = []
    for i, bone in enumerate(model['bones']):
        if bone['parent'] >= 0:
            doc['nodes'][bone['parent']+1].setdefault('children', []).append(i+1)
        else:
            roots.append(i+1)
    matrices = []
    for x, y, z in bone_positions:
        matrices.append([1,0,0,0, 0,1,0,0, 0,0,1,0, -x,-y,-z,1])
    doc['skins'].append(dict(name='PMXSkeleton', joints=list(range(1,len(model['bones'])+1)), inverseBindMatrices=accessor(matrices,'f',5126,'MAT4',16)))
    doc['meshes'].append(dict(name='TrailblazerMesh', primitives=primitives))
    doc['nodes'].append(dict(name='CharacterMesh', mesh=0, skin=0))
    doc['nodes'][0]['children'] = roots + [len(doc['nodes'])-1]

    names = {b['name']: i+1 for i,b in enumerate(model['bones'])}
    used_bones = [n for n in ['左腕','右腕','左ひじ','右ひじ','左足D','右足D','左ひざD','右ひざD','上半身'] if n in names]
    for animation_name, duration, stride in [('idle',2.0,0.012),('walk',0.85,0.38),('run',0.60,0.58),('dodge',0.30,0.25)]:
        animation = dict(name=animation_name, samplers=[], channels=[])
        times = [duration * i/32 for i in range(33)]
        time_accessor = accessor(times,'f',5126,'SCALAR',1,bounds=True)
        for name in used_bones:
            rotations = []
            for t in times:
                phase = t/duration * math.tau
                left = name.startswith('左')
                swing = math.sin(phase + (0 if left else math.pi))
                x,y,z = 0.0,0.0,0.0
                if name in ('左腕','右腕'):
                    z = -0.70 if left else 0.70
                    x = -swing * stride * 0.65
                elif name in ('左ひじ','右ひじ'):
                    y = -0.12 if left else 0.12
                elif name in ('左足D','右足D'):
                    x = swing * stride
                elif name in ('左ひざD','右ひざD'):
                    x = max(0.0, -swing) * stride * 0.8
                elif name == '上半身':
                    x = 0.28 if animation_name == 'dodge' else (0.05 if animation_name == 'run' else 0)
                rotations.append(quaternion(x,y,z))
            index = accessor(rotations,'f',5126,'VEC4',4)
            animation['samplers'].append(dict(input=time_accessor, output=index, interpolation='LINEAR'))
            animation['channels'].append(dict(sampler=len(animation['samplers'])-1,target=dict(node=names[name],path='rotation')))
        doc['animations'].append(animation)
    doc['buffers'][0]['byteLength'] = len(blob)
    json_bytes = json.dumps(doc, ensure_ascii=False, separators=(',',':')).encode('utf-8')
    json_bytes += b' ' * (-len(json_bytes)%4)
    blob.extend(b'\x00' * (-len(blob)%4))
    data = struct.pack('<4sII',b'glTF',2,12+8+len(json_bytes)+8+len(blob))
    data += struct.pack('<I4s',len(json_bytes),b'JSON') + json_bytes
    data += struct.pack('<I4s',len(blob),b'BIN\x00') + blob
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(data)
    report = dict(name=model['name'], vertices=len(positions), triangles=len(model['indices'])//3,
                  bones=len(model['bones']), materials=len(primitives), textures=len(model['textures']),
                  height=1.78, skinning_modes=model['skinning_modes'], animated_bones=used_bones,
                  limitations=['Temporary procedural animations, not game originals','SDEF/QDEF approximated by linear skinning','No MMD IK, morphs or cloth physics','Local non-commercial prototype only; preserve source usage rules'])
    output.with_suffix('.report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source',type=Path)
    parser.add_argument('output',type=Path,nargs='?')
    args = parser.parse_args()
    if args.output:
        print(json.dumps(convert(args.source,args.output),ensure_ascii=False))
    else:
        data = read_pmx(args.source)
        print(json.dumps({k:data[k] for k in ('name','version','textures','materials','bones','skinning_modes')},ensure_ascii=False,indent=2))

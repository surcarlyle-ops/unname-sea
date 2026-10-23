"""Retarget the CC0 authored sword grip onto the user's existing glove rig.

Run with Blender. Transfer phalanx directions in an anatomical palm frame,
not by copying Euler angles between unrelated bone axes. Preserve the mesh,
texture, bind matrices and skin weights while authoring an editable pose clip.
"""
import bpy
import json
import sys
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from prepare_fps_glove import read_glb, append_array, write_glb

ASSET = ROOT / 'assets/characters/fps_gloves'
QA = ROOT / '.mvp_qa' / 'grip_retarget'
QA.mkdir(parents=True, exist_ok=True)
AUTHORING = ASSET / 'authoring'
AUTHORING.mkdir(parents=True, exist_ok=True)
layout = json.loads((ASSET / 'rig_layout.json').read_text())
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(ROOT / 'assets/characters/fps_arms/Arms.fbx'))
source = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')

def source_point(name, posed=False):
    wrist = source.pose.bones['Wrist.R'].matrix if posed else source.data.bones['Wrist.R'].matrix_local
    point = source.pose.bones[name].matrix.translation if posed else source.data.bones[name].head_local
    return wrist.inverted() @ point

forward = (source_point('Middle3.R') - source_point('Middle2.R')).normalized()
lateral = source_point('Pinky2.R') - source_point('Index2.R')
lateral = (lateral - forward * lateral.dot(forward)).normalized()
back = -forward
dorsal = back.cross(lateral).normalized()
canonical = Matrix((lateral, dorsal, back))
source.animation_data.action = next(a for a in bpy.data.actions if a.name.endswith('|Sword_Idle'))
bpy.context.scene.frame_set(1)
bpy.context.view_layer.update()

pose = {}
directions = {}
endpoints = {}
for digit, points in layout['fingers'].items():
    rest = [Vector(p) for p in points]
    parent_rotation = Quaternion()
    posed_points = [rest[0]]
    for segment in range(3):
        source_segment = segment + (1 if digit == 'Thumb' else 2)
        start_name = f'{digit}{source_segment}.R'
        end_name = (f'{digit}{source_segment + 1}.R' if source_segment < (3 if digit == 'Thumb' else 4) else f'{digit}{source_segment}.R_end')
        authored_direction = canonical @ (source_point(end_name, True) - source_point(start_name, True))
        authored_direction.normalize()
        rest_direction = rest[segment + 1] - rest[segment]
        global_rotation = rest_direction.normalized().rotation_difference(authored_direction)
        local_rotation = parent_rotation.inverted() @ global_rotation
        name = f'{digit}{segment + 1}'
        pose[name] = [local_rotation.x, local_rotation.y, local_rotation.z, local_rotation.w]
        directions[name] = list(authored_direction)
        posed_points.append(posed_points[-1] + authored_direction * rest_direction.length)
        parent_rotation = global_rotation
    endpoints[digit] = [list(p) for p in posed_points]

# Contact correction: the source thumb's CMC is closer to the palm than the
# Tripo glove's CMC. Preserve its bend plane, but land its pad on the index.
thumb = [Vector(p) for p in endpoints['Thumb']]
base = thumb[0].copy()
lengths = [(thumb[i + 1] - thumb[i]).length for i in range(3)]
index = [Vector(p) for p in endpoints['Index']]
goal = (index[1] + index[2]) * 0.5 + Vector((0.005, -0.008, 0.005))
for _ in range(16):
    thumb[-1] = goal.copy()
    for i in range(2, -1, -1):
        thumb[i] = thumb[i + 1] + (thumb[i] - thumb[i + 1]).normalized() * lengths[i]
    thumb[0] = base.copy()
    for i in range(3):
        thumb[i + 1] = thumb[i] + (thumb[i + 1] - thumb[i]).normalized() * lengths[i]
parent_rotation = Quaternion()
for i in range(3):
    rest_direction = Vector(layout['fingers']['Thumb'][i + 1]) - Vector(layout['fingers']['Thumb'][i])
    target_direction = (thumb[i + 1] - thumb[i]).normalized()
    global_rotation = rest_direction.normalized().rotation_difference(target_direction)
    local_rotation = parent_rotation.inverted() @ global_rotation
    pose['Thumb' + str(i + 1)] = [local_rotation.x, local_rotation.y, local_rotation.z, local_rotation.w]
    parent_rotation = global_rotation
endpoints['Thumb'] = [list(p) for p in thumb]

library = {'source': 'BigAndCrispy/Unity-First-Person-Melee / Arms.fbx / Sword_Idle frame 1',
           'method': 'Anatomical palm-frame phalanx direction retarget; preserve glove mesh and skin',
           'right': pose, 'source_directions': directions, 'posed_joint_points': endpoints}
(ASSET / 'sword_grip_pose.json').write_text(json.dumps(library, indent=2), encoding='utf-8')

# A separate animated GLB is editable in Blender; production source stays intact.
document, binary_data = read_glb(ASSET / 'glove_right.glb')
binary = bytearray(binary_data)
time = append_array(document, binary, np.array([[0.0], [1.0]], dtype='<f4'), 'SCALAR', 5126, True)
samplers, channels = [], []
for name, rotation in pose.items():
    index = next(i for i, node in enumerate(document['nodes']) if node.get('name') == name)
    output = append_array(document, binary, np.array([rotation, rotation], dtype='<f4'), 'VEC4', 5126)
    channels.append({'sampler': len(samplers), 'target': {'node': index, 'path': 'rotation'}})
    samplers.append({'input': time, 'output': output, 'interpolation': 'LINEAR'})
document['animations'] = [{'name': 'SwordGrip', 'channels': channels, 'samplers': samplers}]
write_glb(AUTHORING / 'glove_authored_grip.glb', document, binary)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(AUTHORING / 'glove_authored_grip.glb'))
bpy.context.scene.frame_set(1)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/weapons/fantasy sword 3d model.glb'))
sword_roots = [o for o in bpy.context.selected_objects if o.parent is None]
holder = bpy.data.objects.new('AuthoredSwordGrip', None)
bpy.context.collection.objects.link(holder)
# Convert the exact Godot attachment matrix into Blender Z-up coordinates.
conversion = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
from math import pi
attachment = (Matrix.Translation((0, -0.037, -0.110)) @ Matrix.Rotation(pi / 2, 4, 'Z')
              @ Matrix.Scale(0.65, 4) @ Matrix.Translation((0, -0.18 * 0.96, 0))
              @ Matrix.Rotation(pi / 2, 4, 'Y') @ Matrix.Scale(0.96, 4))
holder.matrix_world = conversion @ attachment @ conversion.inverted()
for obj in sword_roots:
    local = obj.matrix_world.copy()
    obj.parent = holder
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = local
bpy.ops.wm.save_as_mainfile(filepath=str(AUTHORING / 'glove_sword_grip.blend'))
print('AUTHORED_GRIP_RETARGETED', ASSET / 'sword_grip_pose.json')

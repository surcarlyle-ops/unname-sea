"""Inspect the existing CC0 melee FBX source without changing game assets."""
import bpy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.mvp_qa' / 'melee_candidate'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(ROOT / 'assets/characters/fps_arms/Arms.fbx'))
report = {'objects': [], 'actions': []}
for obj in bpy.context.scene.objects:
    entry = {'name': obj.name, 'type': obj.type, 'location': list(obj.location),
             'rotation': list(obj.rotation_euler), 'scale': list(obj.scale),
             'dimensions': list(obj.dimensions)}
    if obj.type == 'ARMATURE':
        entry['bones'] = [{'name': b.name, 'head': list(b.head_local), 'tail': list(b.tail_local)} for b in obj.data.bones]
    if obj.type == 'MESH':
        entry['vertices'] = len(obj.data.vertices)
        entry['materials'] = [m.name if m else None for m in obj.data.materials]
    report['objects'].append(entry)
for action in bpy.data.actions:
    report['actions'].append({'name': action.name, 'range': list(action.frame_range), 'slots': [s.identifier for s in action.slots]})
bpy.ops.import_scene.fbx(filepath=str(ROOT / 'assets/characters/fps_arms/Steel Shortsword.fbx'))
report['sword_objects'] = [{'name': o.name, 'type': o.type, 'dimensions': list(o.dimensions), 'location': list(o.location), 'rotation': list(o.rotation_euler), 'scale': list(o.scale)} for o in bpy.context.selected_objects]
(OUT / 'source_inspection.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'source_inspection.blend'))
print('MELEE_SOURCE_INSPECTED', OUT)

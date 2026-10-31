"""Keep the supplied geometry; align skin weights across overlapping glove/finger pieces."""
from pathlib import Path
import json
import numpy as np
from prepare_fps_glove import ASSET, ROOT, read_glb, array, skin_weights, append_array, write_glb

qa = ROOT / '.mvp_qa/mvp_upgrade'
qa.mkdir(parents=True, exist_ok=True)
layout = json.loads((ASSET / 'rig_layout.json').read_text())
report = []
for side in ('right', 'left'):
    target = ASSET / f'glove_{side}.glb'
    backup = qa / f'original_glove_{side}.glb'
    if not backup.exists():
        backup.write_bytes(target.read_bytes())
    doc, payload = read_glb(backup)
    p = doc['meshes'][0]['primitives'][0]
    points = array(doc, payload, p['attributes']['POSITION'])
    normalized = points.copy()
    if side == 'left':
        normalized[:, 0] *= -1
    # A continuous spatial field must not smooth each disconnected leather/skin/nail
    # island independently: they overlap at the cuff and must bend together.
    ids, weights, names, _, _ = skin_weights(normalized, layout, faces=None)
    old_ids = array(doc, payload, p['attributes']['JOINTS_0'])
    old_weights = array(doc, payload, p['attributes']['WEIGHTS_0'])
    finger_region = normalized[:, 2] < -.09
    ids[~finger_region] = old_ids[~finger_region]
    weights[~finger_region] = old_weights[~finger_region]
    binary = bytearray(payload)
    p['attributes']['JOINTS_0'] = append_array(doc, binary, ids, 'VEC4', 5123)
    p['attributes']['WEIGHTS_0'] = append_array(doc, binary, weights, 'VEC4', 5126)
    write_glb(target, doc, binary)
    report.append({'side': side, 'geometry_changed': False, 'uv_changed': False,
                   'weights_changed_vertices': int(finger_region.sum()),
                   'weight_sum_error': float(abs(weights.sum(1)-1).max())})
(qa / 'weight_repair.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report))

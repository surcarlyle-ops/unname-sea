"""Read-only audit of coincident seam weights and connected glove geometry."""
from pathlib import Path
import json
import numpy as np
from prepare_fps_glove import read_glb, array, ASSET

for side in ('right', 'left'):
    doc, data = read_glb(ASSET / f'glove_{side}.glb')
    p = doc['meshes'][0]['primitives'][0]
    v = array(doc, data, p['attributes']['POSITION'])
    ids = array(doc, data, p['attributes']['JOINTS_0'])
    weights = array(doc, data, p['attributes']['WEIGHTS_0'])
    faces = array(doc, data, p['indices']).reshape(-1, 3)
    dense = np.zeros((len(v), len(doc['skins'][0]['joints'])))
    for k in range(4):
        dense[np.arange(len(v)), ids[:, k]] += weights[:, k]
    _, inv = np.unique(np.round(v, 5), axis=0, return_inverse=True)
    lower = np.full((int(inv.max())+1, dense.shape[1]), np.inf)
    upper = np.full_like(lower, -np.inf)
    np.minimum.at(lower, inv, dense)
    np.maximum.at(upper, inv, dense)
    bad = np.max(upper-lower, axis=1)
    print(side, json.dumps({'vertices':len(v), 'welded':len(lower),
        'seam_weight_max_difference': float(bad.max()),
        'seams_differing_over_001': int((bad > .01).sum())}))
    parent = np.arange(len(lower))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for face in inv[faces]:
        for i in (1, 2):
            a, b = find(face[0]), find(face[i])
            parent[a] = b
    components = np.array([find(i) for i in inv])
    for key in np.unique(components):
        pts = v[components == key]
        if len(pts) > 30:
            print('component', len(pts), np.round(pts.min(0), 4), np.round(pts.max(0), 4))

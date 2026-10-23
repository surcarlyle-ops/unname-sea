"""Check skinned mesh continuity at a closed grip, including duplicate UV seams."""
import json
import numpy as np
from prepare_fps_glove import ASSET, read_glb, array, normalize, SOURCE, skin_weights


def evaluate(grip=0.86):
    doc, binary = read_glb(SOURCE)
    primitive = doc['meshes'][0]['primitives'][0]
    points, _, _, _ = normalize(array(doc, binary, primitive['attributes']['POSITION']))
    faces = array(doc, binary, primitive['indices']).reshape(-1, 3)
    layout = json.loads((ASSET / 'rig_layout.json').read_text())
    indices, weights, names, joints, parents = skin_weights(points, layout, faces)
    transforms = []
    for i, name in enumerate(names):
        rotation = np.eye(3)
        if name not in ('Forearm', 'Hand') and not name.endswith('Tip'):
            finger, segment = name[:-1], int(name[-1]) - 1
            chain = np.array(layout['fingers'][finger])
            axis = np.cross(chain[-1] - chain[0], [0, -1, 0])
            axis /= np.linalg.norm(axis)
            angle = np.deg2rad(([20, 30, 15] if finger == 'Thumb' else [70, 95, 55])[segment]) * grip
            x, y, z = axis
            cross = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
            rotation = np.eye(3) + np.sin(angle) * cross + (1 - np.cos(angle)) * cross @ cross
            if finger == 'Thumb' and segment == 0:
                c, s = np.cos(-grip), np.sin(-grip)
                rotation = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]) @ rotation
        local = np.eye(4)
        local[:3, :3] = rotation
        local[:3, 3] = joints[i] - (joints[parents[i]] if parents[i] >= 0 else 0)
        transforms.append(transforms[parents[i]] @ local if parents[i] >= 0 else local)
    bind = np.repeat(np.eye(4)[None], len(joints), axis=0)
    bind[:, :3, 3] = -joints
    matrices = np.array(transforms) @ bind
    homogeneous = np.column_stack([points, np.ones(len(points))])
    posed = np.einsum('nk,nkij,nj->ni', weights, matrices[indices], homogeneous)[:, :3]
    edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    before = np.linalg.norm(points[edges[:, 0]] - points[edges[:, 1]], axis=1)
    after = np.linalg.norm(posed[edges[:, 0]] - posed[edges[:, 1]], axis=1)
    stretch = after - before
    sleeve = points[:, 2] > .08
    result = {'grip': grip, 'max_edge_extension_m': float(stretch.max()),
              'sleeve_displacement_m': float(np.linalg.norm(posed[sleeve] - points[sleeve], axis=1).max()),
              'finite_vertices': bool(np.isfinite(posed).all())}
    assert result['finite_vertices'], 'Skinning produced a non-finite vertex'
    assert result['max_edge_extension_m'] < .012, 'A finger boundary stretches by over 12mm'
    assert result['sleeve_displacement_m'] < .0001, 'Finger grip deforms the sleeve'
    return result


if __name__ == '__main__':
    results = [evaluate(grip) for grip in (0.0, .18, .86, 1.0)]
    (ASSET / 'deformation_report.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(json.dumps(results, indent=2))

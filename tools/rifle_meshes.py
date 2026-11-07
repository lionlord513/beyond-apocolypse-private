"""Build/verify cached meshes from the existing rifle geometry (requires lupa).

The shipped native loader uses SceneScale=100 and the YForward (X,Z,Y) basis.
Keep the original triangle order, UVs, normals and tangent handedness. Sights
remain separate so equipping the existing 2x optic can hide them independently.
"""
from pathlib import Path
import argparse
import base64
import json
import struct
from lupa.lua54 import LuaRuntime


ASSETS = Path(__file__).resolve().parents[1] / 'mod/BasicM4/assets'


def axis(value, scale=1):
    return value['X'] * scale, value['Z'] * scale, value['Y'] * scale


def convert(geometry, indices):
    used = sorted(set(indices))
    mapping = {value: index for index, value in enumerate(used)}
    doc = {'asset': {'version': '2.0'}, 'bufferViews': [], 'accessors': []}
    blob = bytearray()

    def accessor(rows, fmt, kind):
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        for row in rows:
            blob.extend(struct.pack('<' + fmt, *row))
        view = len(doc['bufferViews'])
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(blob) - offset})
        value = {'bufferView': view, 'componentType': 5126 if fmt[-1] == 'f' else 5125,
                 'count': len(rows), 'type': kind}
        if kind == 'VEC3':
            value.update(min=[min(row[i] for row in rows) for i in range(3)],
                         max=[max(row[i] for row in rows) for i in range(3)])
        doc['accessors'].append(value)
        return len(doc['accessors']) - 1

    positions = [axis(geometry['vertices'][i + 1], .01) for i in used]
    normals = [axis(geometry['normals'][i + 1]) for i in used]
    uv = [(geometry['uv'][i + 1]['X'], geometry['uv'][i + 1]['Y']) for i in used]
    tangents = []
    for i in used:
        tangent = geometry['tangents'][i + 1]
        tangents.append((*axis(tangent['TangentX']), -1.0 if tangent['bFlipTangentY'] else 1.0))
    attributes = {'POSITION': accessor(positions, 'fff', 'VEC3'), 'NORMAL': accessor(normals, 'fff', 'VEC3'),
                  'TEXCOORD_0': accessor(uv, 'ff', 'VEC2'), 'TANGENT': accessor(tangents, 'ffff', 'VEC4')}
    primitive = {'attributes': attributes, 'indices': accessor([(mapping[i],) for i in indices], 'I', 'SCALAR')}
    doc.update(buffers=[{'byteLength': len(blob), 'uri': 'data:application/octet-stream;base64,' + base64.b64encode(blob).decode()}],
               meshes=[{'primitives': [primitive]}], nodes=[{'mesh': 0}], scenes=[{'nodes': [0]}], scene=0)
    return doc, used


def verify(doc, geometry, indices, used):
    """Decode output independently and compare what the native loader receives."""
    data = base64.b64decode(doc['buffers'][0]['uri'].split(',', 1)[1], validate=True)
    primitive = doc['meshes'][0]['primitives'][0]

    def read(index):
        acc = doc['accessors'][index]
        view = doc['bufferViews'][acc['bufferView']]
        components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[acc['type']]
        fmt = '<' + ('f' if acc['componentType'] == 5126 else 'I') * components
        start = view['byteOffset']
        rows = list(struct.iter_unpack(fmt, data[start:start + view['byteLength']]))
        assert len(rows) == acc['count']
        return rows

    attrs = {key: read(index) for key, index in primitive['attributes'].items()}
    assert [used[row[0]] for row in read(primitive['indices'])] == indices, 'Triangle winding/topology changed'
    for index, original in enumerate(used):
        for name, field, scale in [('POSITION', 'vertices', 100), ('NORMAL', 'normals', 1)]:
            x, y, z = attrs[name][index]
            actual = x * scale, z * scale, y * scale
            expected = geometry[field][original + 1]
            assert all(abs(a - expected[k]) < (1e-4 if scale == 100 else 1e-6)
                       for a, k in zip(actual, ('X', 'Y', 'Z'))), (name, original)
        expected_uv = geometry['uv'][original + 1]
        assert all(abs(a - expected_uv[k]) < 1e-6 for a, k in zip(attrs['TEXCOORD_0'][index], ('X', 'Y')))
        tangent = geometry['tangents'][original + 1]
        x, y, z, w = attrs['TANGENT'][index]
        assert all(abs(a - tangent['TangentX'][k]) < 1e-6 for a, k in zip((x, z, y), ('X', 'Y', 'Z')))
        assert w == (-1 if tangent['bFlipTangentY'] else 1), 'Normal-map handedness changed'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify shipped files without modifying them')
    args = parser.parse_args()
    lua = LuaRuntime()
    destination = ASSETS / 'rifles'
    if not args.check:
        destination.mkdir(exist_ok=True)
    for weapon, filename in [('m4', 'model.lua'), ('hunting', 'hunting.lua'), ('enfield', 'enfield.lua'), ('optic', 'optic/model.lua')]:
        data = lua.execute((ASSETS / filename).read_text())
        if weapon == 'optic':
            data = {'scope': data}
        for part, geometry in data.items():
            for key, suffix in [('triangles', part), ('ironTriangles', 'iron')]:
                if not geometry[key]:
                    continue
                indices = list(geometry[key].values())
                doc, used = convert(geometry, indices)
                target = destination / (weapon + '-' + suffix + '.gltf')
                if args.check:
                    shipped = json.loads(target.read_text())
                    assert shipped == doc, f'{target.name} differs from its original source'
                    verify(shipped, geometry, indices, used)
                else:
                    verify(doc, geometry, indices, used)
                    target.write_text(json.dumps(doc, separators=(',', ':')))
                print('PASS', target.name, len(used), 'vertices;', len(indices) // 3, 'unchanged triangles')


if __name__ == '__main__':
    main()

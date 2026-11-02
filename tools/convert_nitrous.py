"""Convert the supplied FBX's single bottle, preserving UVs and normals."""
from pathlib import Path
import sys, math, json
sys.path.insert(0,str(Path(__file__).parent))
from read_fbx import Reader,child
import argparse
parser=argparse.ArgumentParser()
parser.add_argument('fbx',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
nodes=Reader(args.fbx).read()
objects=next(n for n in nodes if n['name']=='Objects')['c']
g=next(n for n in objects if n['name']=='Geometry' and n['p'][1].startswith('nto_b_s.'))
v=child(g,'Vertices')['p'][0]; indices=child(g,'PolygonVertexIndex')['p'][0]
n=child(child(g,'LayerElementNormal'),'Normals')['p'][0]
uv=child(g,'LayerElementUV');coords=child(uv,'UV')['p'][0];ui=child(uv,'UVIndex')['p'][0]
lo=[min(v[k::3])for k in range(3)];hi=[max(v[k::3])for k in range(3)]
# The narrow valve is on negative X. Rotate into upright Z.
scale=38/(hi[0]-lo[0]);cy=(lo[1]+hi[1])/2;cz=(lo[2]+hi[2])/2
vertices=[];normals=[];uvs=[];triangles=[];face=[]
for j,index in enumerate(indices):
 k=index if index>=0 else -index-1
 x,y,z=v[k*3:k*3+3];nx,ny,nz=n[j*3:j*3+3]
 vertices.append({'X':round((z-cz)*scale,5),'Y':round(-y*scale,5),'Z':round((hi[0]-x)*scale,5)})
 normals.append({'X':round(nz,6),'Y':round(-ny,6),'Z':round(-nx,6)})
 u,w=coords[ui[j]*2:ui[j]*2+2];uvs.append({'X':round(u,7),'Y':round(1-w,7)})
 face.append(j)
 if index<0:
  # Reflect Y for Unreal's handedness; this also changes the face winding.
  for k in range(1,len(face)-1):triangles.extend([face[0],face[k],face[k+1]])
  face=[]
assert not face and len(triangles)==1512
def lua(v):
 if isinstance(v,dict):return '{'+','.join(k+'='+lua(w)for k,w in v.items())+'}'
 if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
 return str(v).lower()
import struct,base64
g=dict(vertices=vertices,triangles=triangles,normals=normals,uv=uvs)
# Both flat bracket feet have X=-6.20731 in the upright model. Their centre
# along the bottle is Z=15.887675. Make that centre the placement origin.
for p in g['vertices']:p['X'],p['Y'],p['Z']=round(p['Z']-15.887675,6),-p['Y'],round(p['X']+6.20731,6)
for n in g['normals']:n['X'],n['Y'],n['Z']=n['Z'],-n['Y'],n['X']
def text(v):
 if isinstance(v,dict):return '{'+','.join(k+'='+text(w)for k,w in v.items())+'}'
 if isinstance(v,list):return '{'+','.join(map(text,v))+'}'
 return str(v).lower()
args.output.write_text('-- Bracket feet lie on Z=0; horizontal long axis X; centimetres.\nreturn '+text(g)+'\n',newline='\n')
# Hidden static mesh supplies one tightly fitted native simple collider.
# Native import is verified against these dimensions before packaging.
lo=[min(v[k]for v in g['vertices'])for k in 'XYZ'];hi=[max(v[k]for v in g['vertices'])for k in 'XYZ']
positions=[(x/100,z/100,y/100)for x in [lo[0],hi[0]]for y in [lo[1],hi[1]]for z in [lo[2],hi[2]]]
indices=[0,1,3,0,3,2,4,6,7,4,7,5,0,4,5,0,5,1,2,3,7,2,7,6,0,2,6,0,6,4,1,5,7,1,7,3]
data=b''.join(struct.pack('<3f',*p)for p in positions)+struct.pack('<36H',*indices)
obj={'asset':{'version':'2.0'},'buffers':[{'byteLength':len(data),'uri':'data:application/octet-stream;base64,'+base64.b64encode(data).decode()}],
 'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':96},{'buffer':0,'byteOffset':96,'byteLength':72}],
 'accessors':[{'bufferView':0,'componentType':5126,'count':8,'type':'VEC3','min':[lo[0]/100,lo[2]/100,lo[1]/100],'max':[hi[0]/100,hi[2]/100,hi[1]/100]},{'bufferView':1,'componentType':5123,'count':36,'type':'SCALAR'}],
 'meshes':[{'primitives':[{'attributes':{'POSITION':0},'indices':1}]}],'nodes':[{'mesh':0}],'scenes':[{'nodes':[0]}],'scene':0}
(args.output.parent/'collider.gltf').write_text(json.dumps(obj),newline='\n')
print('Bracket-origin mesh and collider bounds cm:',lo,hi)

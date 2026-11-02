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
target=args.output
target.write_text('-- Supplied nitrous FBX; 504 triangles, original UVs, centimetres.\nreturn '+lua(dict(vertices=vertices,triangles=triangles,normals=normals,uv=uvs))+'\n')
print(target,len(vertices),'vertices',len(triangles)//3,'triangles',lo,hi)

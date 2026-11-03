"""Render the actual fitted soldier in an exported native idle pose, offline."""
from pathlib import Path
import sys,json,struct,argparse
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'python-deps'))
import numpy as np
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('build',type=Path);p.add_argument('references',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
def read_glb(path):
 data=path.read_bytes();length=struct.unpack_from('<I',data,12)[0];d=json.loads(data[20:20+length]);blob=data[28+length:]
 def arr(i):
  ac=d['accessors'][i];v=d['bufferViews'][ac['bufferView']];dtype={5126:'<f4',5125:'<u4',5123:'<u2'}[ac['componentType']];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[ac['type']]
  return np.frombuffer(blob,dtype=dtype,count=ac['count']*n,offset=v.get('byteOffset',0)+ac.get('byteOffset',0)).reshape(-1,n)
 return d,arr
def mat(r):
 x,y,z,w=r['q'];m=np.eye(4);m[:3,:3]=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])@np.diag(r['s']);m[:3,3]=r['t'];return m
ref={r['name']:mat(r)for r in json.loads((a.references/'skeleton-body.json').read_text())}
pose={r['name']:mat(r)for r in json.loads((a.references/'soldier-idle-pose.json').read_text())}
for kind in ['body','arms','first_body']:
 d,get=read_glb(a.build/f'soldier-{kind}.glb');attrs=d['meshes'][0]['primitives'][0]['attributes'];weights=get(attrs['WEIGHTS_0']);joints=get(attrs['JOINTS_0']);positions=get(attrs['POSITION']);normals=get(attrs['NORMAL'])
 assert len(d['skins'][0]['joints'])==70 and len(d['meshes'])==3
 assert np.isfinite(positions).all() and np.isfinite(normals).all() and np.allclose(weights.sum(axis=1),1,atol=1e-5)
 assert joints.max()<70 and np.all((weights>=0)&(weights<=1))
 for mesh in d['meshes']:assert get(mesh['primitives'][0]['indices']).max()<len(positions)
 print('PASS',kind,len(positions),'vertices;',len(get(d['meshes'][0]['primitives'][0]['indices']))//3,'triangles')
d,get=read_glb(a.build/'soldier-body.glb');attr=d['meshes'][0]['primitives'][0]['attributes'];data=np.load(a.build/'preview-body.npz');points=data['vertices'];normals=data['normals'];colors=data['colors'][data['materials']];tris=data['triangles'];weights=get(attr['WEIGHTS_0']);joints=get(attr['JOINTS_0'])
transforms=np.array([pose[d['nodes'][i]['name']]@np.linalg.inv(ref[d['nodes'][i]['name']])for i in d['skins'][0]['joints']])
v=np.zeros_like(points);n=np.zeros_like(normals)
for j in range(4):
 t=transforms[joints[:,j]];v+=(np.einsum('nij,nj->ni',t[:,:3,:3],points)+t[:,:3,3])*weights[:,j,None];n+=np.einsum('nij,nj->ni',t[:,:3,:3],normals)*weights[:,j,None]
n/=np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-8)
def render(filename,size,target,height):
 w,h=size;target=np.array(target,dtype=float);eye=target+np.array([55,400,40]);forward=target-eye;forward/=np.linalg.norm(forward);right=np.cross(forward,[0,0,1]);right/=np.linalg.norm(right);up=np.cross(right,forward)
 cam=np.c_[(v-target)@right,(v-target)@up,(v-eye)@forward];screen=np.c_[w/2+cam[:,0]*h/height,h/2-cam[:,1]*h/height];depth=np.full((h,w),np.inf);canvas=np.zeros((h,w,3))
 for y in range(h):canvas[y,:,:]=np.array([.025,.031,.038])*(1-.3*y/h)
 lights=[(np.array([-.4,.55,.75]),.7),(np.array([.8,.5,.2]),.28)];shade=np.full(len(v),.38)
 for light,amount in lights:light/=np.linalg.norm(light);shade+=amount*np.maximum(0,n@light)
 rgb=np.clip(colors*shade[:,None]*1.25,0,1)
 for tri in tris:
  xy=screen[tri];x0,y0=np.maximum(np.floor(xy.min(axis=0)).astype(int),[0,0]);x1,y1=np.minimum(np.ceil(xy.max(axis=0)).astype(int),[w-1,h-1])
  if x1<x0 or y1<y0:continue
  aa,bb,cc=xy;den=(bb[1]-cc[1])*(aa[0]-cc[0])+(cc[0]-bb[0])*(aa[1]-cc[1])
  if abs(den)<1e-8:continue
  xx,yy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5);u=((bb[1]-cc[1])*(xx-cc[0])+(cc[0]-bb[0])*(yy-cc[1]))/den;vv=((cc[1]-aa[1])*(xx-cc[0])+(aa[0]-cc[0])*(yy-cc[1]))/den;ww=1-u-vv
  zz=u*cam[tri[0],2]+vv*cam[tri[1],2]+ww*cam[tri[2],2];sl=np.s_[y0:y1+1,x0:x1+1];mask=(u>=0)&(vv>=0)&(ww>=0)&(zz<depth[sl]);depth[sl][mask]=zz[mask]
  color=u[:,:,None]*rgb[tri[0]]+vv[:,:,None]*rgb[tri[1]]+ww[:,:,None]*rgb[tri[2]];canvas[sl][mask]=color[mask]
 srgb=np.where(canvas<=.0031308,canvas*12.92,1.055*canvas**(1/2.4)-.055);Image.fromarray(np.uint8(np.clip(srgb*255+.5,0,255))).save(a.output/filename)
render('soldier-preview.png',(640,960),(0,0,98),225)
render('soldier-face.png',(256,256),(0,0,179),65)

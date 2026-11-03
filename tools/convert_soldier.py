"""Fit the supplied Mixamo FBX to exported DBH reference bones; no runtime retarget loop."""
from pathlib import Path
import sys,json,struct,math
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'python-deps'))
import numpy as np
from PIL import Image
from read_fbx import Reader,child
import argparse
ap=argparse.ArgumentParser();ap.add_argument('fbx',type=Path);ap.add_argument('references',type=Path);ap.add_argument('output',type=Path);a=ap.parse_args();a.output.mkdir(parents=True,exist_ok=True)
ns=Reader(a.fbx).read();objects=next(n['c']for n in ns if n['name']=='Objects');byid={n['p'][0]:n for n in objects};links=next(n['c']for n in ns if n['name']=='Connections')
g=next(n for n in objects if n['name']=='Geometry');model=next(byid[n['p'][2]]for n in links if n['p'][1]==g['p'][0])
pose=next(n for n in objects if n['name']=='Pose');bind={child(n,'Node')['p'][0]:np.array(child(n,'Matrix')['p'][0]).reshape(4,4).T for n in pose['c']if n['name']=='PoseNode'}
swap=np.eye(4)[[0,2,1,3]];meshbind=swap@bind[model['p'][0]]
points=np.array(child(g,'Vertices')['p'][0]).reshape(-1,3);points=(np.c_[points,np.ones(len(points))]@meshbind.T)[:,:3]
bonepos={n['p'][1].split('\0')[0].removeprefix('mixamorig:'):(swap@bind[n['p'][0]])[:3,3]for n in objects if n['name']=='Model'and n['p'][2]=='LimbNode'and n['p'][0]in bind}
weights=[{}for _ in points]
for n in objects:
 if n['name']=='Deformer'and n['p'][2]=='Cluster':
  name=n['p'][1].split('\0')[0].removeprefix('mixamorig:')
  if not child(n,'Indexes'):continue
  for i,w in zip(child(n,'Indexes')['p'][0],child(n,'Weights')['p'][0]):
   if w>1e-7:weights[i][name]=w
assert all(w for w in weights),'Unweighted source vertices'
mats=[byid[n['p'][1]]for n in links if n['p'][2]==model['p'][0]and byid.get(n['p'][1],{}).get('name')=='Material']
colors=[];rough=[];metal=[]
for m in mats:
 props={p['p'][0]:p['p'][4:]for p in child(m,'Properties70')['c']};name=m['p'][1].lower()
 colors.append(props.get('DiffuseColor',[.2,.2,.2]));rough.append(.42 if any(s in name for s in ['iron','metal','armor','glass'])else .78);metal.append(.55 if any(s in name for s in ['iron','metal','armor'])else 0)
liner_material=len(colors);colors.append([.003,.003,.003]);rough.append(.9);metal.append(0)
size=128;cell=32
for filename,values in [('palette.png',colors),('roughness.png',[[v]*3 for v in rough]),('metallic.png',[[v]*3 for v in metal])]:
 arr=np.zeros((size,size,3),np.uint8)
 for i,c in enumerate(values):
  c=np.array(c);c=np.where(c<=.0031308,c*12.92,1.055*c**(1/2.4)-.055)if filename=='palette.png'else c
  arr[i//4*cell:(i//4+1)*cell,i%4*cell:(i%4+1)*cell]=np.clip(c*255+.5,0,255).astype(np.uint8)
 Image.fromarray(arr).save(a.output/filename)
Image.new('RGB',(8,8),(128,128,255)).save(a.output/'normal.png');Image.new('RGB',(8,8),(255,255,255)).save(a.output/'ao.png')
(a.output/'textures.gltf').write_text(json.dumps({'asset':{'version':'2.0'},'images':[{'uri':n}for n in ['palette.png','normal.png','roughness.png','metallic.png','ao.png']]}))
indices=child(g,'PolygonVertexIndex')['p'][0];normal_layer=child(g,'LayerElementNormal');normals=np.array(child(normal_layer,'Normals')['p'][0]).reshape(-1,3)@meshbind[:3,:3].T;normals/=np.linalg.norm(normals,axis=1)[:,None]
normal_indices=child(normal_layer,'NormalsIndex')
if normal_indices:normals=normals[normal_indices['p'][0]]
face_mats=child(child(g,'LayerElementMaterial'),'Materials')['p'][0]
faces=[];corners=[];face=[];fi=0
for j,i in enumerate(indices):
 face.append((j,i if i>=0 else -i-1))
 if i<0:
  for k in range(1,len(face)-1):faces.append([face[0],face[k],face[k+1]]);corners.append(face_mats[fi])
  face=[];fi+=1
assert not face
mapping={'Hips':'Pelvis','Spine':'spine_01','Spine1':'spine_02','Spine2':'spine_03','Neck':'neck_01','Head':'Head','HeadTop_End':'Head'}
for side,s in [('Left','l'),('Right','r')]:
 for src,dst in [('Shoulder','clavicle'),('Arm','upperarm'),('ForeArm','lowerarm'),('Hand','Hand'),('UpLeg','thigh'),('Leg','calf'),('Foot','foot'),('ToeBase','ball'),('Toe_End','ball')]:mapping[side+src]=dst+'_'+(s.upper()if dst=='Hand'else s)
 for f in ['Thumb','Index','Middle','Ring','Pinky']:
  for i in range(1,5):mapping[side+'Hand'+f+str(i)]=f.lower()+'_'+str(min(i,3)).zfill(2)+'_'+s
def rotation(q):
 x,y,z,w=q
 return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
def align(u,v):
 u=u/np.linalg.norm(u);v=v/np.linalg.norm(v);cross=np.cross(u,v);dot=np.dot(u,v);k=np.array([[0,-cross[2],cross[1]],[cross[2],0,-cross[0]],[-cross[1],cross[0],0]])
 if dot<-.9999:return -np.eye(3)+2*np.outer(np.array([0,1,0]),np.array([0,1,0]))
 return np.eye(3)+k+k@k/(1+dot)
childbone={'Hips':'Spine','Spine':'Spine1','Spine1':'Spine2','Spine2':'Neck','Neck':'Head','Head':'HeadTop_End'}
for side in ['Left','Right']:
 for parent,nextname in [('Shoulder','Arm'),('Arm','ForeArm'),('ForeArm','Hand'),('Hand','HandMiddle1'),('UpLeg','Leg'),('Leg','Foot'),('Foot','ToeBase'),('ToeBase','Toe_End')]:childbone[side+parent]=side+nextname
 for f in ['Thumb','Index','Middle','Ring','Pinky']:
  for i in range(1,4):childbone[side+'Hand'+f+str(i)]=side+'Hand'+f+str(i+1)
def build(label):
 refs=json.loads((a.references/('skeleton-'+('arms'if label=='arms'else'body')+'.json')).read_text());refs=[r for r in refs if not r['name'].startswith('VB ')]
 names={r['name']:i for i,r in enumerate(refs)};lower={n.lower():n for n in names};mp={s:lower.get(t.lower())for s,t in mapping.items()}
 def mapped(s):return mp.get(s)or mp.get(s.removesuffix('_end'))or 'Head'
 target={r['name']:np.array(r['t'])for r in refs};total_scale=(target['Head'][2]-target['Pelvis'][2])/(bonepos['Head'][2]-bonepos['Hips'][2])
 transforms={}
 for source in bonepos:
  dest=mapped(source)
  if dest not in target:continue
  R=np.eye(3);stretch=np.eye(3)*total_scale;ch=childbone.get(source)
  if ch in bonepos and mapped(ch)!=dest and mapped(ch)in target:
   u=bonepos[ch]-bonepos[source];v=target[mapped(ch)]-target[dest]
   if np.linalg.norm(u)>.01 and np.linalg.norm(v)>.01:
    R=align(u,v);direction=u/np.linalg.norm(u);stretch+=np.outer(direction,direction)*(np.linalg.norm(v)/np.linalg.norm(u)-total_scale)
  elif source.startswith(('LeftHand','RightHand')):
   prev=source[:-1]+str(max(1,int(source[-1])-1)) if source[-1].isdigit()else source
   if prev in transforms:R,stretch,_=transforms[prev]
  transforms[source]=(R,stretch,target[dest])
 verts=[];norm=[];uv=[];joints=[];ws=[];source_material=[];source_ids=[];remap={};tris=[]
 for face,material in zip(faces,corners):
  if label=='first_body':
   # Keep the look-down torso/legs and seated hands. The helmet and neck are
   # omitted from the owner-only mesh, never from the full remote body/shadow.
   if any(sum(w for b,w in weights[i].items()if b in ('Head','Neck','HeadTop_End'))>.10 for _,i in face):continue
  if label=='arms':
   # Keep complete arm polygons; no torso/head floating in first-person view.
   if not all(sum(w for b,w in weights[i].items()if any(b.startswith(s)for s in ['LeftArm','LeftForeArm','LeftHand','RightArm','RightForeArm','RightHand']))>=.70 for _,i in face):continue
  triangle=[]
  for corner,i in face:
   key=(i,material,tuple(np.round(normals[corner],5)))
   if key not in remap:
    pairs=sorted(weights[i].items(),key=lambda v:-v[1])[:4];total=sum(w for _,w in pairs);p=np.zeros(3);n=np.zeros(3);boneweights={}
    for b,w in pairs:
     w/=total;R,stretch,t=transforms[b];p+=(R@stretch@(points[i]-bonepos[b])+t)*w;n+=(R@normals[corner])*w;bi=names[mapped(b)];boneweights[bi]=boneweights.get(bi,0)+w
    bw=list(boneweights.items());bi=[k for k,w in bw];ww=[w for k,w in bw]
    while len(bi)<4:bi.append(0);ww.append(0)
    remap[key]=len(verts);verts.append(p);norm.append(n/max(np.linalg.norm(n),1e-8));joints.append(bi);ws.append(ww);uv.append(((material%4+.5)/4,(material//4+.5)/4));source_material.append(material);source_ids.append(i)
   triangle.append(remap[key])
  # Conversion to RH glTF reverses the source FBX handedness twice overall.
  tris.extend(triangle)
 # Refine exposed hands for close-up use; retain the armour's authored edges.
 skin={i for i,m in enumerate(mats)if '(skin)'in m['p'][1].lower()}
 welded={};alias={}
 for i,material in enumerate(source_material):
  if material in skin:
   key=(source_ids[i],material);alias[i]=welded.setdefault(key,i)
 smooth_faces=[];other_faces=[]
 for face in np.array(tris).reshape(-1,3).tolist():
  if source_material[face[0]]in skin:smooth_faces.append([alias[i]for i in face])
  else:other_faces.append(face)
 edges={};neighbors={}
 orientation=1 if sum(np.dot(np.cross(np.array(verts[b])-verts[a],np.array(verts[c])-verts[a]),norm[a])for a,b,c in smooth_faces)>=0 else -1
 for a0,b0,c0 in smooth_faces:
  for x,y,z in [(a0,b0,c0),(b0,c0,a0),(c0,a0,b0)]:
   edges.setdefault(tuple(sorted((x,y))),[]).append(z);neighbors.setdefault(x,set()).add(y);neighbors.setdefault(y,set()).add(x)
 def blend_skin(parts):
  p=sum((np.array(verts[i])*w for i,w in parts),np.zeros(3));bw={}
  for i,w in parts:
   for j,v in zip(joints[i],ws[i]):bw[j]=bw.get(j,0)+w*v
  bw=sorted(bw.items(),key=lambda v:-v[1])[:4];total=sum(v for _,v in bw);ji=[j for j,_ in bw];ww=[v/total for _,v in bw]
  while len(ji)<4:ji.append(0);ww.append(0)
  return p,ji,ww
 newpos={};boundary={i for edge,opposite in edges.items()if len(opposite)!=2 for i in edge}
 for i,near in neighbors.items():
  if i not in boundary:
   beta=3/16 if len(near)==3 else 3/(8*len(near));newpos[i]=blend_skin([(i,1-len(near)*beta)]+[(j,beta)for j in near])
 midpoint={}
 for edge,opposite in edges.items():
  parts=[(edge[0],.375),(edge[1],.375)]+[(i,.125)for i in opposite]if len(opposite)==2 else [(i,.5)for i in edge]
  p,ji,ww=blend_skin(parts);idx=len(verts);midpoint[edge]=idx;verts.append(p);joints.append(ji);ws.append(ww);norm.append(np.array([0.,0.,1.]));uv.append(uv[edge[0]]);source_material.append(source_material[edge[0]]);source_ids.append(-1)
 for i,(p,ji,ww)in newpos.items():verts[i]=p;joints[i]=ji;ws[i]=ww
 refined=[]
 for a0,b0,c0 in smooth_faces:
  ab,bc,ca=[midpoint[tuple(sorted(e))]for e in [(a0,b0),(b0,c0),(c0,a0)]];refined.extend([[a0,ab,ca],[b0,bc,ab],[c0,ca,bc],[ab,bc,ca]])
 smooth_norm={}
 for face in refined:
  n=np.cross(np.array(verts[face[1]])-verts[face[0]],np.array(verts[face[2]])-verts[face[0]])*orientation
  for i in face:smooth_norm[i]=smooth_norm.get(i,np.zeros(3))+n
 for i,n in smooth_norm.items():norm[i]=n/max(np.linalg.norm(n),1e-8)
 tris=np.array(other_faces+refined).reshape(-1).tolist()
 if label=='first_body':
  # A matte inner chest panel closes the owner-only cutout below the camera.
  # It follows the torso, with no camera offset or collision change.
  center=target['spine_03']+np.array([0,1.3,10]);start=len(verts);segments=24
  for i in range(segments+1):
   angle=2*math.pi*(i-1)/segments
   pos=center if i==0 else center+np.array([20*math.cos(angle),13*math.sin(angle),-1])
   verts.append(pos);norm.append(np.array([0,0,1]));uv.append(((liner_material%4+.5)/4,(liner_material//4+.5)/4));joints.append([names['spine_03'],0,0,0]);ws.append([1,0,0,0]);source_material.append(liner_material);source_ids.append(-1)
  for i in range(segments):
   j=start+1+i;k=start+1+(i+1)%segments;tris.extend([start,j,k,start,k,j])
 verts=np.array(verts);norm=np.array(norm);uv=np.array(uv);joints=np.array(joints,dtype=np.uint16);ws=np.array(ws)
 # UE centimetres -> Y-up glTF metres, matching the bundled YForward importer.
 P=swap[:3,:3];gverts=verts@P.T/100;gnorm=norm@P.T
 blob=bytearray();views=[];access=[]
 def acc(values,kind,dtype,component):
  values=np.asarray(values,dtype=dtype);blob.extend(b'\0'*((-len(blob))%4));offset=len(blob);raw=values.tobytes();blob.extend(raw);views.append({'buffer':0,'byteOffset':offset,'byteLength':len(raw)});obj={'bufferView':len(views)-1,'componentType':component,'count':len(values),'type':kind}
  if kind=='VEC3':obj.update(min=values.min(axis=0).tolist(),max=values.max(axis=0).tolist())
  access.append(obj);return len(access)-1
 attrs={'POSITION':acc(gverts,'VEC3','<f4',5126),'NORMAL':acc(gnorm,'VEC3','<f4',5126),'TEXCOORD_0':acc(uv,'VEC2','<f4',5126),'JOINTS_0':acc(joints,'VEC4','<u2',5123),'WEIGHTS_0':acc(ws,'VEC4','<f4',5126)}
 triangles=np.array(tris).reshape(-1,3)
 meshes=[{'name':'SciFi Soldier '+label,'primitives':[{'attributes':attrs,'indices':acc(triangles.reshape(-1),'SCALAR','<u4',5125),'material':0}]}]
 # Two lower detail index buffers by bounded vertex clustering, retaining skin data.
 for step in [2.5,5.0]:
  bins={};ids=[]
  for i,p in enumerate(verts):
   key=(*np.floor(p/step+.5).astype(int),source_material[i],int(joints[i,np.argmax(ws[i])]))
   if key not in bins:bins[key]=i
   ids.append(bins[key])
  t=np.array(ids)[triangles];t=t[(t[:,0]!=t[:,1])&(t[:,1]!=t[:,2])&(t[:,0]!=t[:,2])]
  meshes.append({'name':'LOD'+str(len(meshes)),'primitives':[{'attributes':attrs,'indices':acc(t.reshape(-1),'SCALAR','<u4',5125),'material':0}]})
 globals=[]
 for r in refs:
  m=np.eye(4);m[:3,:3]=rotation(r['q'])@np.diag(r['s']);m[:3,3]=r['t'];m=swap@m@swap;m[:3,3]/=100;globals.append(m)
 nodes=[]
 for i,r in enumerate(refs):
  parent=names.get(r['parent']);m=globals[i] if parent is None else np.linalg.inv(globals[parent])@globals[i];node={'name':r['name'],'matrix':m.T.reshape(-1).tolist()};children=[j for j,c in enumerate(refs)if c['parent']==r['name']]
  if children:node['children']=children
  nodes.append(node)
 nodes.append({'name':'SciFiSoldier','mesh':0,'skin':0})
 ibm=acc(np.array([np.linalg.inv(m).T.reshape(-1)for m in globals]),'MAT4','<f4',5126)
 doc={'asset':{'version':'2.0','generator':'Beyond Apocalypse soldier adapter'},'buffers':[{'byteLength':len(blob)}],'bufferViews':views,'accessors':access,'meshes':meshes,'nodes':nodes,'skins':[{'joints':list(range(len(refs))),'skeleton':0,'inverseBindMatrices':ibm}],'materials':[{'name':'SoldierPalette','pbrMetallicRoughness':{'baseColorFactor':[.3,.32,.28,1],'metallicFactor':0,'roughnessFactor':.7}}],'scenes':[{'nodes':[0,len(refs)]}],'scene':0}
 js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*((-len(js))%4);blob.extend(b'\0'*((-len(blob))%4));data=struct.pack('<III',0x46546C67,2,12+8+len(js)+8+len(blob))+struct.pack('<II',len(js),0x4E4F534A)+js+struct.pack('<II',len(blob),0x004E4942)+blob
 (a.output/('soldier-'+label+'.glb')).write_bytes(data)
 np.savez(a.output/('preview-'+label+'.npz'),vertices=verts,normals=norm,triangles=triangles,materials=source_material,colors=colors)
 print(label,'bones',len(refs),'vertices',len(verts),'triangles',len(tris)//3,'bounds',verts.min(axis=0).round(2),verts.max(axis=0).round(2))
build('body');build('arms');build('first_body')

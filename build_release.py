"""Package public gameplay only; no installed-game directory is an input."""
from pathlib import Path
import argparse, hashlib, json, shutil, zipfile

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--runtime',type=Path,required=True,help='Recovered Win64 directory with pinned dwmapi/UE4SS')
parser.add_argument('--model-source',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
version='1.1.5';binroot='DriveBeyondHorizons/Binaries/Win64';mods=binroot+'/ue4ss/Mods'
sha=lambda data:hashlib.sha256(data).hexdigest()
def payload(path):return {p.relative_to(path).as_posix():p.read_bytes() for p in sorted(path.rglob('*'))if p.is_file()}
mod=payload(root/'mod/BasicM4')
for name,data in mod.items():
 assert not any(x.lower()in ('devmenu','backups','logs','userdata')for x in name.split('/')),name
 assert name.lower()not in ('scripts/attach.lua','scripts/config.lua'),name
 assert not name.startswith('state/')or name=='state/KEEP THIS FOLDER.txt',name
 if name.endswith(('.lua','.txt')):
  assert not any(s in data.lower()for s in (b'baaudit',b'c:/users/',b'c:\\users\\',b'live-audit',b'work/private-companion')),name
assert b"Version='1.1.5',Channel='stable'"in mod['Scripts/release.lua']
runtime={}
for name in ['dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/UE4SS-settings.ini','ue4ss/LICENSE','ue4ss/Mods/shared/UEHelpers/UEHelpers.lua']:
 runtime[name]=(args.runtime/name).read_bytes()
assert sha(runtime['ue4ss/UE4SS.dll'])=='e14657eec1c3fb08d1d0e4d5b24f69a9343cd06359e1af27ae6c9c84c5f010cf'
docs=payload(root/'release');shim=docs.pop('legacy-main.lua')
assert shim.startswith(b'-- BeyondApocalypse legacy migration shim v1')
nexus={**{mods+'/BeyondApocalypse/'+k:v for k,v in mod.items()},**{binroot+'/'+k:v for k,v in runtime.items()},
 mods+'/BasicM4/Scripts/main.lua':shim,mods+'/BasicM4/Scripts/release.lua':mod['Scripts/release.lua'],
 'READ ME FIRST.txt':docs['README.txt'],'bmm.json':docs['bmm.json']}
for k,v in docs.items():
 if k not in ('bmm.json','Install.cmd','Install.ps1','Uninstall.ps1'):nexus[binroot+'/BeyondApocalypse-Docs/'+k]=v
def archive(name,files):
 checks=''.join(sha(data)+'  '+name+'\n'for name,data in sorted(files.items()))
 files={**files,'SHA256SUMS.txt':checks.encode()}
 p=out/name
 with zipfile.ZipFile(p,'w',zipfile.ZIP_DEFLATED,compresslevel=6)as z:
  for key,data in sorted(files.items()):
   entry=zipfile.ZipInfo(key,(2026,11,2,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED;entry.external_attr=0o100644<<16;z.writestr(entry,data)
 with zipfile.ZipFile(p)as z:
  assert z.testzip()is None
  assert len(z.namelist())==len(set(z.namelist()))
  assert all('DevMenu/'not in n and '/Scripts/devmenu/'not in n for n in z.namelist())
 print('BUILT',p.name,p.stat().st_size,flush=True)
 return p
# Both delivery channels use one canonical package, including the loader.
# Hash-based same-version checks therefore recognize a Nexus install as current.
nex=archive('BeyondApocolypse-1.1.5-Nexus.zip',nexus)
pub=out/'BeyondApocalypse-1.1.5-public.zip';shutil.copyfile(nex,pub)
assert pub.read_bytes()==nex.read_bytes()
legacy=out/'BeyondApocolypse-1.1.5-beta.zip';shutil.copyfile(pub,legacy)
with zipfile.ZipFile(args.model_source)as z:
 source={n:z.read(n)for n in z.namelist()if not n.endswith('/')}
assert any(n.endswith(('.ac','.blend','.gltf'))for n in source),'Original editable model is missing'
for k,v in mod.items():
 if k.startswith('assets/gyrocopter/'):source['Beyond-Apocalypse-1.1.5-current/'+k]=v
source['Beyond-Apocalypse-1.1.5-current/README.txt']=b'Original source/converter retained. Current imported Hornet assets are included under assets/gyrocopter. See its ATTRIBUTION.txt and COPYING.txt.\n'
model=archive('BeyondApocolypse-1.1.5-Hornet-Model-Source.zip',source)
meta=json.loads(docs['bmm.json']);notes=meta['history'][0]['notes']
def manifest(p):return {'schema':1,'version':version,'released':'2026-11-06','channel':'stable','origin':'GitHub','asset':p.name,'size':p.stat().st_size,'sha256':sha(p.read_bytes()),'url':'https://github.com/lionlord513/beyond-apocolypse-private/releases/download/v1.1.5/'+p.name,'notes':notes,'history':meta['history'][1:]}
for name,p in [('bmm-mod.json',pub),('release.json',legacy)]:
 (out/name).write_text(json.dumps(manifest(p),indent=2)+'\n',encoding='utf-8')
files=[pub,nex,legacy,model,out/'bmm-mod.json',out/'release.json']
(out/'SHA256SUMS.txt').write_text(''.join(sha(p.read_bytes())+'  '+p.name+'\n'for p in files),encoding='utf-8')
report={'version':version,'publicFiles':len(nexus),'nexusFiles':len(nexus),'personalMenuIncluded':False,'files':[{'name':p.name,'size':p.stat().st_size,'sha256':sha(p.read_bytes())}for p in files]}
(out/'package-verification.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')

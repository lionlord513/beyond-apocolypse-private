local root,scratch=assert(arg[1]),assert(arg[2])
local sight=dofile(root..'/weapons/ak_sight.lua')({X=-.7,Y=1.1275,Z=11.0717},1.06)
assert(math.abs(sight.height-11.736002)<1e-6)
-- Applying the native AK's -90-degree presentation rotation cancels Y/Z
-- at the sight socket; the prior 6 cm constant left it high above the camera.
assert(math.abs(.7*1.06-sight.lateral)<1e-9)
local values={['r.ViewDistanceScale']=.8,['r.StaticMeshLODDistanceScale']=1,['foliage.LODDistanceScale']=1,['grass.DensityScale']=.4,['sg.PostProcessQuality']=2,
 ['r.Shadow.MaxResolution']=1024,['r.Shadow.MaxCSMResolution']=2048,['r.Shadow.CSM.MaxCascades']=2,['r.SkeletalMeshLODBias']=0,['r.ParticleLODBias']=0,
 ['r.ShadowQuality']=4,['r.VolumetricFog']=1,['r.SSR.Quality']=4,['r.RefractionQuality']=2,['r.AmbientOcclusionLevels']=-1,
 ['r.MotionBlurQuality']=4,['r.DepthOfFieldQuality']=2,['r.BloomQuality']=4,['r.LensFlareQuality']=2,
 ['r.VolumetricCloud']=1,['r.SkyAtmosphere.MultiScatteringLUT.HighQuality']=1,['r.SkyAtmosphere.SampleCountMin']=8,
 ['r.SkyAtmosphere.SampleCountMax']=96,['r.SkyAtmosphere.FastSkyLUT.SampleCountMin']=6,['r.SkyAtmosphere.FastSkyLUT.SampleCountMax']=96}
local initial={};for k,v in pairs(values)do initial[k]=v end
local commands=0;local pc={PlayerControlled={IsLoaded=true}};local sys={};local rejected
function sys:GetConsoleVariableFloatValue(name)return assert(values[name],name)end
function sys:ExecuteConsoleCommand(_,command)
 local key,value=command:match('^(%S+) (%S+)$');assert(key~='r.ViewDistanceScale','Native visibility radius was changed');if key~=rejected then values[key]=tonumber(value)end;commands=commands+1
 if key=='sg.PostProcessQuality'and key~=rejected then values['r.BloomQuality']=tonumber(value)*2 end
end
StaticFindObject=function()return sys end
local scans=0;FindAllOf=function(kind)assert(kind=='StaticMeshComponent'or kind=='Ultra_Dynamic_Sky_Nory_C');if kind=='StaticMeshComponent'then scans=scans+1 end;return{}end
NotifyOnNewObject=function()end;RegisterHook=function()end
local M={root=root..'/..',statePath=function(name)return scratch..'/'..name end}
local H={GetPlayerController=function()return pc end}
local F=dofile(root..'/performance.lua')(M,H,function(x)return x~=nil end,function()end)
assert(F.setGameplayMode(true,true));assert(values['r.StaticMeshLODDistanceScale']==8 and values['grass.DensityScale']==0 and values['sg.PostProcessQuality']==0)
assert(values['foliage.LODDistanceScale']==.25 and values['r.ShadowQuality']==0 and values['r.VolumetricFog']==0 and values['r.SSR.Quality']==0)
assert(values['r.VolumetricCloud']==0 and values['r.SkyAtmosphere.SampleCountMax']==16 and values['r.SkyAtmosphere.SampleCountMin']==4)
assert(values['r.Shadow.MaxResolution']==512 and values['r.Shadow.MaxCSMResolution']==512 and values['r.Shadow.CSM.MaxCascades']==1)
assert(values['r.SkeletalMeshLODBias']==1 and values['r.ParticleLODBias']==1)
assert(values['r.ViewDistanceScale']==.8 and F.scene)
local count=commands;for _=1,10000 do F.tick()end;assert(commands==count,'Idle mode rewrote render settings')
assert(scans==1,'Recurring world scan in Performance Mode')
assert(F.setGameplayMode(false,true));for k,v in pairs(initial)do assert(values[k]==v,'Setting not restored: '..k)end
assert(F.setGameplayMode(false,true));assert(F.setGameplayMode(true,true));F.reset();for k,v in pairs(initial)do assert(values[k]==v)end
values['sg.PostProcessQuality']=3;F.tick();assert(values['sg.PostProcessQuality']==3)
assert(F.setGameplayMode(true,true));values['sg.PostProcessQuality']=1;F.nextAt=0;F.tick()
assert(values['sg.PostProcessQuality']==0);F.setGameplayMode(false,true);assert(values['sg.PostProcessQuality']==1)
assert(F.setGameplayMode(true,true));values['sg.PostProcessQuality']=2;rejected='sg.PostProcessQuality';F.nextAt=0;F.tick()
assert(F.status:find('partly rejected',1,true),'Rejected settings were reported as fully applied')
rejected=nil;F.nextAt=0;F.tick();assert(not F.status:find('rejected',1,true));F.setGameplayMode(false,true)
assert(values['sg.PostProcessQuality']==2,'An external graphics choice was lost')
values['r.Shadow.MaxResolution']=256;values['r.Shadow.CSM.MaxCascades']=0;values['r.SkeletalMeshLODBias']=2
assert(F.setGameplayMode(true,true))
assert(values['r.Shadow.MaxResolution']==256 and values['r.Shadow.CSM.MaxCascades']==0 and values['r.SkeletalMeshLODBias']==2,'Mode increased an already lower rendering budget')
F.setGameplayMode(false,true)
pc.PlayerControlled.IsLoaded=false;local before=commands;assert(not F.setGameplayMode(true,true));assert(commands==before,'Unloaded world applied render changes')
print('PASS: native AK sight alignment; extreme visual preset, event-driven decoration, idle settings and exact restoration')

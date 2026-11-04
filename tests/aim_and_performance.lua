local root,scratch=assert(arg[1]),assert(arg[2])
local sight=dofile(root..'/weapons/ak_sight.lua')({X=-.7,Y=1.1275,Z=11.0717},1.06)
assert(math.abs(sight.height-11.736002)<1e-6)
-- Applying the native AK's -90-degree presentation rotation cancels Y/Z
-- at the sight socket; the prior 6 cm constant left it high above the camera.
assert(math.abs(.7*1.06-sight.lateral)<1e-9)
local values={['r.ViewDistanceScale']=.8,['r.StaticMeshLODDistanceScale']=1,['grass.DensityScale']=.4,['sg.PostProcessQuality']=2}
local initial={};for k,v in pairs(values)do initial[k]=v end
local commands=0;local pc={};local sys={}
function sys:GetConsoleVariableFloatValue(name)return assert(values[name],name)end
function sys:ExecuteConsoleCommand(_,command)
 local key,value=command:match('^(%S+) (%S+)$');assert(key~='r.ViewDistanceScale','Native visibility radius was changed');values[key]=tonumber(value);commands=commands+1
end
StaticFindObject=function()return sys end
FindAllOf=function()error('Performance Mode scanned native objects')end
NotifyOnNewObject=function()error('Performance Mode registered a component observer')end
local M={root=root..'/..',statePath=function(name)return scratch..'/'..name end}
local H={GetPlayerController=function()return pc end}
local F=dofile(root..'/performance.lua')(M,H,function(x)return x~=nil end,function()end)
assert(F.setGameplayMode(true,true));assert(values['r.StaticMeshLODDistanceScale']==4 and values['grass.DensityScale']==0 and values['sg.PostProcessQuality']==0)
assert(values['r.ViewDistanceScale']==.8 and not F.scene)
local count=commands;for _=1,10000 do F.tick()end;assert(commands==count,'Idle mode rewrote render settings')
assert(F.setGameplayMode(false,true));for k,v in pairs(initial)do assert(values[k]==v,'Setting not restored: '..k)end
assert(F.setGameplayMode(false,true));assert(F.setGameplayMode(true,true));F.reset();for k,v in pairs(initial)do assert(values[k]==v)end
values['sg.PostProcessQuality']=3;F.tick();assert(values['sg.PostProcessQuality']==3)
assert(F.setGameplayMode(true,true));values['sg.PostProcessQuality']=1;F.nextAt=0;F.tick()
assert(values['sg.PostProcessQuality']==0);F.setGameplayMode(false,true);assert(values['sg.PostProcessQuality']==1)
print('PASS: native AK sight alignment; scan-free performance mode, idle settings and exact restoration')

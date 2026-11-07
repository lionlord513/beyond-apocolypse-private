local root=arg[1];local hooks={};local notify;local scans=0;local calls=0;local nextId=0
local function valid(o)return o~=nil and (type(o)~='table'or not o.dead)end
StaticFindObject=function(path)return path end
RegisterHook=function(path,fn,post)assert(not hooks[path]);hooks[path]=post or fn end
NotifyOnNewObject=function(_,fn)assert(not notify);notify=fn end
local function change(c,path,key,value)
 local h=hooks[path];if h then h({get=function()return c end},{get=function()return value end,set=function(_,x)value=x end})end
 c[key]=value;calls=calls+1
end
local function component(name,particle)
 nextId=nextId+1;local id=nextId
 local c={bVisible=true,paused=false,tick=true}
 function c:GetAddress()return id end;function c:GetFullName()return name end
 function c:IsA()return particle end
 function c:SetVisibility(v)change(self,'/Script/Engine.SceneComponent:SetVisibility','bVisible',v)end
 function c:SetPaused(v)change(self,'/Script/Niagara.NiagaraComponent:SetPaused','paused',v)end
 function c:SetComponentTickEnabled(v)change(self,'/Script/Engine.ActorComponent:SetComponentTickEnabled','tick',v)end
 function c:IsPaused()return self.paused end;function c:IsComponentTickEnabled()return self.tick end
 return c
end
local function actor()
 local a={Sun=component('Sun'),Moon=component('Moon'),time=17,coverage=.8}
 for _,name in ipairs({'VolumetricCloud','StaticCloudsSphere','Overcast_Turbulence','Inside_Cloud_Fog','VolumetricCloud_LightRays'})do
  a[name]=component(name,name=='Inside_Cloud_Fog'or name=='VolumetricCloud_LightRays')
 end
 return a
end
local a=actor();a.StaticCloudsSphere.bVisible=false
FindAllOf=function(kind)assert(kind=='Ultra_Dynamic_Sky_Nory_C');scans=scans+1;return{a}end
local S=dofile(root..'/performance_sky.lua')(valid);S.begin()
assert(not a.VolumetricCloud.bVisible and not a.Inside_Cloud_Fog.bVisible and a.Inside_Cloud_Fog.paused and not a.Inside_Cloud_Fog.tick)
assert(a.Sun.bVisible and a.Moon.bVisible and a.time==17 and a.coverage==.8,'Weather/time/lighting changed')
local before=calls;for _=1,10000 do S.tick()end;assert(scans==1 and calls==before,'Idle cloud work repeated')
a.VolumetricCloud:SetVisibility(true);assert(not a.VolumetricCloud.bVisible,'Native visibility bypassed suppression')
a.Inside_Cloud_Fog:SetPaused(false);a.Inside_Cloud_Fog:SetComponentTickEnabled(true)
assert(a.Inside_Cloud_Fog.paused and not a.Inside_Cloud_Fog.tick,'Cloud simulation restarted')
a.Inside_Cloud_Fog.paused=false
hooks['/Script/Engine.ActorComponent:Activate']({get=function()return a.Inside_Cloud_Fog end});S.tick()
assert(a.Inside_Cloud_Fog.paused and not a.Inside_Cloud_Fog.tick,'Newly activated cloud simulation escaped suppression')
assert(S.saved[a.Inside_Cloud_Fog:GetAddress()].tick,'Activation replaced native tick intent with the forced value')
a.VolumetricCloud_LightRays:SetVisibility(false)
local streamed=actor();notify(streamed);S.tick();assert(not streamed.VolumetricCloud.bVisible,'Streamed sky missed')
streamed.StaticCloudsSphere.dead=true
assert(S.restore());assert(a.VolumetricCloud.bVisible and not a.StaticCloudsSphere.bVisible)
assert(not a.Inside_Cloud_Fog.paused and a.Inside_Cloud_Fog.tick and not a.VolumetricCloud_LightRays.bVisible)
assert(a.Sun.bVisible and a.Moon.bVisible and not next(S.saved))
local off=actor();notify(off);S.tick();assert(off.VolumetricCloud.bVisible)
S.begin();assert(S.restore());assert(scans==2)
return 'Cloud rendering/simulation, latest native intent, streaming, idle work, exact restore, unchanged weather and lights'

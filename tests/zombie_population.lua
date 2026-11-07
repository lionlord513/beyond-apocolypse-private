local scripts,scratch=assert(arg[1]),assert(arg[2]);local now=0;os.clock=function()return now end
local host=true;local observer;local zombies={};local searches=0
local world={GetAddress=function()return 100 end}
local pawn={IsLoaded=true,GetWorld=function()return world end,K2_GetActorLocation=function()return{X=0,Y=0,Z=0}end}
local pc={IsLocalPlayerController=function()return true end,HasAuthority=function()return host end}
local native={MinZombieBySpawn=2,MaxZombieBySpawn=11,['Min Zombie by SpawnBase']=1,['Max Zombie by SpawnBase']=10,TimerHandle={}}
local original={};for k,v in pairs(native)do original[k]=v end
local gs={BP_ZombieSpawner=native,GetAddress=function()return 101 end,Players={ForEach=function(_,fn)fn(1,{get=function()return pawn end})end}}
local game={GetGameState=function()return gs end};local paused=false
local sys={K2_IsTimerActiveHandle=function()return not paused end,K2_IsTimerPausedHandle=function()return paused end,
 K2_PauseTimerHandle=function()paused=true end,K2_UnPauseTimerHandle=function()paused=false end}
StaticFindObject=function(s)if s:find('GameplayStatics',1,true)then return game elseif s:find('KismetSystemLibrary',1,true)then return sys end;return{}end
RegisterHook=function()return 1,2 end
NotifyOnNewObject=function(_,fn)assert(not observer);observer=fn end
FindAllOf=function()searches=searches+1;return zombies end
local function zombie(id,distance,authority,w)
 local z={IsDead=false,destroyed=false}
 function z:GetAddress()return id end;function z:GetWorld()return w or world end
 function z:HasAuthority()return authority~=false end;function z:IsActorBeingDestroyed()return self.destroyed end
 function z:K2_GetActorLocation()return{X=distance,Y=0,Z=0}end
 function z:K2_DestroyActor()self.destroyed=true end
 return z
end
for i=1,5 do zombies[i]=zombie(i,i*100)end
local config={MechanicEnabled=false}
local M={config={Apocalypse=config},apocalypse={},mechanic={reset=function()end},roaming={reset=function()end}}
local P=dofile(scripts..'/zombie_population.lua')(M,scratch,{GetPlayerController=function()return pc end,GetPlayer=function()return pawn end},function(o)return type(o)=='table'end,function()end)
P.tick(pawn);assert(P.live==5 and searches==1)
assert(P.limit==10 and P.target()==5 and P.remaining()==0,'default daytime population is not five')
gs.UDS={['Time of Day']=2100};assert(P.target()==10 and P.remaining()==5,'night target is not ten')
gs.UDS['Time of Day']=1200;M.apocalypse.infestationActive=true;assert(P.target()==10,'daytime infestation not allowed to reach ten')
M.apocalypse.infestationActive=false;assert(P.target()==5,'infestation target leaked into normal daytime')
assert(P.setLimit(2));assert(P.live==2 and paused and zombies[5].destroyed and not zombies[1].destroyed,'cap did not retain nearest two')
M.apocalypse.infestationActive=true;assert(P.target()==2 and P.remaining()==0,'infestation bypassed host ceiling');M.apocalypse.infestationActive=false
gs.UDS['Time of Day']=2100;assert(P.target()==2,'night bypassed host ceiling');gs.UDS['Time of Day']=1200
assert(native.MaxZombieBySpawn==0 and P.remaining()==0,'native additions allowed beyond cap')
host=false;assert(not pcall(P.setLimit,40)and not pcall(P.setDisabled,true),'client changed host population');host=true
for _,n in ipairs({0,1,41,2.5,0/0})do assert(not pcall(P.setLimit,n),'invalid cap accepted')end
zombies[1].IsDead=true;now=1;P.tick(pawn);assert(P.live==1 and P.remaining()==1 and not paused,'death did not reopen native spawn capacity')
local extra=zombie(6,900);observer(extra);observer(extra);now=2;P.tick(pawn);assert(P.live==2,'duplicate construction event counted twice')
local burst=zombie(7,1000);observer(burst);now=3;P.tick(pawn);assert(burst.destroyed and P.live==2,'native batch exceeded shared cap')
assert(P.setDisabled(true));assert(P.live==0 and extra.destroyed and paused)
local late=zombie(8,500);observer(late);now=4;P.tick(pawn);assert(late.destroyed and P.live==0,'disabled mode allowed native spawn')
P.setDisabled(false);assert(not paused and P.remaining()==2)
for _=1,50 do now=now+.3;P.tick(pawn)end;assert(searches==1,'population added recurring world scans')
P.reset();assert(not paused);for k,v in pairs(original)do assert(native[k]==v,'native spawner value not restored')end
-- An enabled Mechanic owns one place inside the ceiling, even after a native
-- batch fills it. His greater spawn distance must not make him first to cull.
config.MechanicEnabled=true;P.limit=10;gs.UDS['Time of Day']=2100;zombies={}
for i=1,10 do zombies[i]=zombie(100+i,i*100)end
P.tick(pawn);assert(P.live==9 and zombies[10].destroyed,'Ordinary zombies consumed the reserved Mechanic slot')
assert(P.remaining()==0 and P.remaining('mechanic')==1 and native.MaxZombieBySpawn==0,'Spawn budgets did not distinguish Mechanic from ordinary zombies')
local mechanic=zombie(200,23000);P.track(mechanic)
-- Native callbacks can return distinct Lua wrappers for the same UObject.
P.track(setmetatable({},{__index=mechanic}),'mechanic');P.enforce()
assert(P.live==10 and not mechanic.destroyed and P.remaining()==0,'Mechanic exceeded the ceiling or was immediately culled')
local overflow=zombie(201,10);observer(overflow);now=now+1;P.tick(pawn)
assert(P.live==10 and not mechanic.destroyed,'Near ordinary spawn displaced the distant Mechanic')
P.setLimit(4);assert(P.live==4 and not mechanic.destroyed,'Lowering the ceiling removed the reserved enemy')
mechanic.IsDead=true;P.enforce()
assert(P.live==3 and P.remaining()==0 and P.remaining('mechanic')==1,'Death did not retain the next reserved slot')
config.MechanicEnabled=false;assert(P.remaining()==1,'Disabling the feature did not release its reservation')
P.reset();config.MechanicEnabled=true;P.limit=10;zombies={};gs.UDS['Time of Day']=1200
P.tick(pawn);assert(P.remaining()==5,'Reservation unnecessarily reduced the normal daytime target')
P.reset();assert(not P.mechanic,'World change retained a protected old actor')
print('PASS: shared ceiling, reserved Mechanic admission/retention, native bursts, feature toggle, daytime target, client denial and restore')

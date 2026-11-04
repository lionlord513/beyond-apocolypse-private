local root,scratch=assert(arg[1]),assert(arg[2])
local P=dofile(root..'/player_models/policy.lua')
assert(#P.catalog==3 and P.catalog[1].id==0 and P.catalog[2].id==1)
for _,s in ipairs({'BASKIN1|set|0|1','BASKIN1|set|1|3','BASKIN1|set|1|1|other','BASKIN1|set|-1|0','BASKIN1|set|2147483648|0','BASKIN1|ack|1|1',string.rep('x',65)})do assert(not P.parse(s,'set'),s)end
assert(P.parse(P.message('set',21,1),'set')==21)
local replay={};assert(P.accept(replay,1,1,0));assert(P.accept(replay,1,1,.1));assert(not P.accept(replay,1,0,2));assert(not P.accept(replay,2,0,.1));assert(P.accept(replay,2,0,1));assert(not P.accept(replay,1,1,2))
assert(P.markerId('BA_PlayerSkin_v1_1')==1 and not P.markerId('BA_PlayerSkin_v1_10'))

local realDofile=dofile;local clock=0;os.clock=function()return clock end
local nextId=0;local function object(name)
 nextId=nextId+1;local o={name=name,address=nextId}
 function o:GetFullName()return self.name end;function o:GetAddress()return self.address end
 function o:IsA()return true end;return o
end
local function valid(o)return type(o)=='table'and not o.dead end
FName=function(s)return {ToString=function()return s end}end
local nativeArray={rows={}}
function nativeArray:ForEach(fn)for i,p in ipairs(self.rows)do fn(i,{get=function()return p end})end end
setmetatable(nativeArray,{__index=function(_,k)if type(k)=='number'then error('Do not iterate native PlayerArray with ipairs')end end})
local gs={PlayerArray=nativeArray};local game={GetGameState=function()return gs end}
StaticFindObject=function(path)if path:find('Default__GameplayStatics',1,true)then return game end;return {path=path}end
local hooks={};RegisterHook=function(path,pre,post)hooks[path]={pre,post};return 1,2 end
local observed,searches={},0
FindAllOf=function(kind)assert(kind=='PlayerBase_C');searches=searches+1;return observed end
local notify;NotifyOnNewObject=function(_,callback)notify=callback end
local queue={};local enqueue=function(f)queue[#queue+1]=f end
local function flush()local q=queue;queue={};for _,f in ipairs(q)do f()end end
local function pawn(name)
 local p=object(name);p.IsLoaded=true;p.Mesh=object(name..' mesh');p.FpsArm=object(name..' arms');p.components={}
 function p:HasAuthority()return true end
 function p:K2_GetComponentsByClass()local t={};for _,c in ipairs(self.components)do t[#t+1]={get=function()return c end}end;return t end
 function p:AddComponentByClass()
  local c=object(self.name..' marker');c.AttachSocketName=FName('None')
  function c:SetVisibility()end;function c:SetComponentTickEnabled()end
  function c:K2_AttachToComponent(_,name)self.AttachSocketName=name end
  function c:SetIsReplicated(v)self.bReplicates=v end
  self.components[#self.components+1]=c;return c
 end
 function p:FlushNetDormancy()end;function p:ForceNetUpdate()end
 return p
end
local function controller(name,p,localOwner)
 local pc=object(name);pc.PlayerControlled=p;pc.localOwner=localOwner;pc.authority=true
 local ps=object(name..' state');ps.PawnPrivate=p;ps.GetOwner=function()if not ps.hideOwner then return pc end end;pc.PlayerState=ps;p.PlayerState=ps
 function pc:HasAuthority()return self.authority end;function pc:IsLocalPlayerController()return self.localOwner end
 function pc:ClientMessage(msg,kind)self.ack={P.parse(msg,'ack')};assert(kind:ToString()==P.kind)end
 return pc,ps
end
local hostPawn,remotePawn=pawn('host pawn'),pawn('remote pawn')
local host,hostState=controller('host',hostPawn,true);local guest,guestState=controller('guest',remotePawn,false)
nativeArray.rows={hostState,guestState}
observed={hostPawn,remotePawn}
local player,pc=hostPawn,host
local H={GetPlayer=function()return player end,GetPlayerController=function()return pc end}
local visuals
dofile=function(path)
 if path:match('/player_models/visuals.lua$')then return function()
  local R={records={},loads=0,removed=0};visuals=R
  function R.load()R.loads=R.loads+1 end
  function R.apply(p)local key=p:GetFullName();R.records[key]=R.records[key]or{actor=p,key=key};return R.records[key]end
  function R.hide(r)r.hidden=true end;function R.update()end;function R.clothingChanged(r)r.clothesChanged=true end
  function R.syncWearables()end;function R.syncRagdoll()end
  function R.remove(r)if type(r)=='string'then r=R.records[r]end;if r then R.records[r.key]=nil;R.removed=R.removed+1 end end
  function R.reset()R.records={}end
  return R
 end end
 return realDofile(path)
end
local M={features=true,statePath=function(n)return scratch..'/models-'..n end}
local C=dofile(root..'/player_models/controller.lua')(M,root..'/..',H,valid,enqueue,function()end)
C.select(1);C.tick();assert(C.selected==1 and not C.pending)
assert(hostPawn.components[1].bReplicates and #hostPawn.components==1)
assert(visuals.records[hostPawn:GetFullName()])
local palette='FF20800A0D0B00';assert(C.server(guest,10,2,palette));assert(guest.ack[1]==10 and guest.ack[2]==2 and guest.ack[3]==palette)
clock=1;C.tick();assert(C.players[remotePawn:GetFullName()].id==2 and C.players[remotePawn:GetFullName()].colors==palette)
assert(not C.server(guest,9,0));assert(not C.server(guest,11,3))
guest.PlayerState=hostState;assert(not C.server(guest,11,0));guest.PlayerState=guestState
M.features=false;assert(not C.server(guest,11,0));M.features=true
remotePawn.IsLoaded=false;assert(not C.server(guest,11,0));remotePawn.IsLoaded=true
-- Closing/reopening the UI must not allocate new markers or change choices.
for i=1,30 do clock=clock+.51;C.tick()end
assert(#hostPawn.components==1 and #remotePawn.components==1)
assert(searches==1,'Steady-state ticks repeated the world discovery')
local vehicle=object('car');vehicle.IsA=function(_,cls)return cls.path=='/Script/VehicleSystemPlugin.VehicleSystemBase'end;vehicle.Driver=remotePawn
hostState.PawnPrivate=vehicle;guestState.PawnPrivate=vehicle
hostPawn.PlayerState=nil;remotePawn.PlayerState=nil
clock=clock+1;C.tick();assert(C.players[hostPawn:GetFullName()].id==1 and C.players[remotePawn:GetFullName()].id==2 and C.players[remotePawn:GetFullName()].colors==palette,'Vehicle possession removed a custom model')
assert(C.server(guest,11,2,palette),'Model choice denied during native UnPossess')
-- The same controller retains its selection after the native pawn respawns.
local replacement=pawn('respawned guest');replacement.PlayerState=guestState;guest.PlayerControlled=replacement;guestState.PawnPrivate=replacement
remotePawn.dead=true;observed={hostPawn,replacement};notify(replacement);flush()
clock=clock+1;C.tick();assert(C.players[replacement:GetFullName()].id==2 and C.players[replacement:GetFullName()].colors==palette)
assert(not visuals.records[remotePawn:GetFullName()])
-- A client joining later reads the already replicated marker, without an RPC.
pc.authority=false;guestState.hideOwner=true;guestState.PawnPrivate=vehicle;vehicle.Driver=replacement;replacement.PlayerState=nil;C.players={};C.humans={};C.states={};C.seeded=false
clock=clock+1;C.tick();assert(C.players[replacement:GetFullName()].id==2 and C.players[replacement:GetFullName()].colors==palette,'Late join lost a seated remote model');pc.authority=true;guestState.hideOwner=false
clock=clock+1;assert(C.server(guest,12,0));C.tick();assert(not visuals.records[replacement:GetFullName()])
-- Blueprint notifications only queue native work, avoiding re-entry from UI.
local h=hooks['/Game/BP/Player/CustomizablePlayer/MaleCharacter.MaleCharacter_C:SetClothes'][1]
h({get=function()return hostPawn end});assert(not visuals.records[hostPawn:GetFullName()].clothesChanged);flush();assert(visuals.records[hostPawn:GetFullName()].clothesChanged)
clock=clock+1;C.select(0);C.tick();assert(C.selected==0 and not visuals.records[hostPawn:GetFullName()])
local f=assert(io.open(M.statePath('player-model.txt')));assert(f:read('*a')=='model=0\n');f:close()
nativeArray.rows={hostState};clock=clock+1;C.tick();assert(not C.players[replacement:GetFullName()])
C.reset();assert(next(visuals.records)==nil)
dofile=realDofile
-- Native inspection can report first person in IsInFPS while its active camera
-- is third person. Only the owning camera may hide the helmet/full body.
local V=realDofile(root..'/player_models/visuals.lua')({},root..'/..',{},valid,function()end)
local function component(name)
 local c=object(name);c.bVisible=true;c.bHiddenInGame=false;c.bOwnerNoSee=false
 c.bRenderInMainPass=true;c.bRenderInDepthPass=true;c.CastShadow=true
 function c:SetVisibility(v)self.bVisible=v end
 function c:SetHiddenInGame(v)self.bHiddenInGame=v end
 function c:SetOwnerNoSee(v)self.bOwnerNoSee=v end
 function c:SetRenderInMainPass(v)self.bRenderInMainPass=v end
 function c:SetRenderInDepthPass(v)self.bRenderInDepthPass=v end
 function c:SetCastShadow(v)self.CastShadow=v end
 return c
end
local human=object('local cosmetic');human.FpsArm=component('native hands');human.BP_PlayerStats={IsDead=false}
local cameraFPS=true;local camera={IsInFPS=true,IsInCameraFPS=function(_,out)out.IsFPS=cameraFPS end}
local cosmetic={actor=human,follower=component('full soldier'),firstBody=component('headless body'),driverBody=component('driver limbs'),arms=component('soldier hands'),parts={}}
V.update(cosmetic,human,camera)
assert(not cosmetic.follower.bVisible and cosmetic.firstBody.bVisible)
assert(human.FpsArm.bVisible and not human.FpsArm.bHiddenInGame,'Changing native animation inputs causes flicker')
assert(not human.FpsArm.bRenderInMainPass and not human.FpsArm.bRenderInDepthPass,'Two sets of hands must not render together')
cameraFPS=false;V.update(cosmetic,human,camera)
assert(cosmetic.follower.bVisible and not cosmetic.follower.bOwnerNoSee and not cosmetic.firstBody.bVisible,'Inspection must show the full helmet')
cameraFPS=true;camera.Vehicle=object('occupied car');camera.Vehicle.Driver=human;V.update(cosmetic,human,camera)
assert(not cosmetic.follower.bVisible and not cosmetic.firstBody.bVisible and cosmetic.driverBody.bVisible and not cosmetic.arms.bVisible,'The cockpit must use native seated limbs')
cameraFPS=false;V.update(cosmetic,human,camera)
assert(cosmetic.follower.bVisible and not cosmetic.firstBody.bVisible and not cosmetic.driverBody.bVisible,'Exterior camera lost the full model')
cameraFPS=true
camera.Vehicle=nil;V.update(cosmetic,human,camera)
V.update(cosmetic,object('different local player'),camera)
assert(cosmetic.follower.bVisible and not cosmetic.follower.bOwnerNoSee and not cosmetic.firstBody.bVisible and not cosmetic.arms.bVisible,'Remote players must see a full helmet')
print('PASS: model choices, strict RPC ownership, stale/rate-limited messages, late discovery, respawn, clothing notification, bounded native arrays and restore')

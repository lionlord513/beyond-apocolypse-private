local root,dir=arg[1],arg[2]
local function valid(o)return type(o)=='table'and o.alive~=false end
local ids,registered={},{}
FName=function(s)return s end
RegisterHook=function(name,fn)registered[name]=fn;return 1 end
local steam={GetSteamIdFromPlayerState=function(_,s)return s.id end,BreakSteamID=function(_,s)return s end}
StaticFindObject=function(path)if path:find('SteamUtilities',1,true)then return steam end;return {}end
local qty='NbBullet_7_9635697947FC4A8ADC5190856DA85E1C'
local function player(address,count,localController)
 local pawn={IsLoaded=true,IsInitialized=true,n=count};pawn.MapNbbullet={ForEach=function(_,fn)fn({get=function()return 2 end},{get=function()return {[qty]=pawn.n}end})end}
 function pawn:AddBulletToPlayer(v)self.n=self.n+v[qty]end
 function pawn:ForceNetUpdate()end
 return {GetAddress=function()return address end,GetFullName=function()return 'PC'..address end,PlayerControlled=pawn,
  HasAuthority=function()return true end,IsLocalPlayerController=function()return localController end,
  ClientMessage=function(self,s)self.received=s end,PlayerState={id=string.rep('0',17)}}
end
local key='world-revision-1';local save={SaveGameMetadata={},IsA=function()return true end}
local M={statePath=function(file)return dir..'/state/'..file end,gyrocopter={transport={journal={key=function()return key,'world'end}}}}
local host=player(1,10,true);local a,b=player(2,20,false),player(3,30,false)
local function each(...)ids={...}end
FindAllOf=function()return ids end
local S=dofile(root..'/session.lua')(M,{GetPlayerController=function()return host end},valid,function(fn)fn()end);M.session=S;S.tick()
local exec=registered['/Script/Engine.PlayerController:ServerExecRPC']
local function send(pc,s)exec({get=function()return pc end},{get=function()return {ToString=function()return s end}end})end
local function identify(pc,token)
 send(pc,'BAMOD1|hello');assert(not S.offlineOwner(pc)and pc.received=='BAMOD1|identity?')
 send(pc,'BAMOD1|identity|'..token);assert(S.offlineOwner(pc)=='offline-'..token)
end
local first,second=string.rep('a',32),string.rep('b',32)
identify(a,first);identify(b,second)
local online=player(4,40,false);online.PlayerState.id='76561198000000001'
local R=dofile(root..'/ammo_reserves.lua')(M,valid,print);R.load(save);each(host,a,b,online);R.update();R.capture(save)
assert(R.players.host[2]==10 and R.players['offline-'..first][2]==20 and R.players['offline-'..second][2]==30 and R.players['steam-'..online.PlayerState.id][2]==40)
R.reset();S.reset();S.tick();local again=player(9,0,false);identify(again,second);each(host,again);R.load(save);R.update()
assert(again.PlayerControlled.n==30 and R.players['offline-'..first][2]==20)
local unmodded=player(10,1,false);assert(not S.offlineOwner(unmodded)and not unmodded.received)
return 'Two separate offline guests, Steam owner, host and reconnect from disk'

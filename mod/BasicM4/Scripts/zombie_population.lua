-- Host-owned shared limit for native zombies, encounters, hazmats and Mechanic.
-- Construction notifications avoid adding a recurring world search.
return function(M,root,H,valid,log)
 local P={limit=10,disabled=false,records={},incoming={},live=0,nextAt=0}
 local config=M.config and M.config.Apocalypse or {}
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local path=M.statePath and M.statePath('zombie-limit.txt')or root..'/state/zombie-limit.txt'
 local fields={'MinZombieBySpawn','MaxZombieBySpawn','Min Zombie by SpawnBase','Max Zombie by SpawnBase'}
 do local f=io.open(path,'r');if f then local n=tonumber(f:read('*a'));f:close();if n and n%1==0 and n>=2 and n<=40 then P.limit=n end end end
 local function alive(z)return valid(z)and not z:IsActorBeingDestroyed()and not z.IsDead end
 function P.isHost()
  local pc,p=H.GetPlayerController(),H.GetPlayer()
  return valid(pc)and pc:IsLocalPlayerController()and pc:HasAuthority()and valid(p)and p.IsLoaded
 end
 local function restoreNative()
  local r=P.native;if not r or not valid(r.actor)then P.native=nil;return end
  for name,value in pairs(r.values)do r.actor[name]=value end
  if r.paused then sys:K2_UnPauseTimerHandle(r.actor,r.actor.TimerHandle)end
  P.native=nil
 end
 function P.track(z,kind)
  if not P.worldAddress or not alive(z)or not z:HasAuthority()then return end
  local w=z:GetWorld();if not valid(w)or w:GetAddress()~=P.worldAddress then return end
  local key=z:GetAddress();if not P.records[key]then P.records[key]=z;P.live=P.live+1;P.dirty=true end
  if kind=='mechanic'then P.mechanic=z;P.dirty=true end
 end
 local function mechanicAlive()return alive(P.mechanic)and alive(P.records[P.mechanic:GetAddress()])end
 local function reserved()return mechanicAlive()or config.Enabled~=false and config.MechanicEnabled~=false end
 function P.remaining(kind)
  if P.disabled then return 0 end
  -- Reserve one place inside the hard ceiling, without reducing a lower
  -- daytime target. A manual replacement may reuse the existing Mechanic's slot.
  if kind=='mechanic'then return math.max(0,P.limit-P.live+(mechanicAlive()and 1 or 0))end
  local held=reserved()and not mechanicAlive()and 1 or 0
  return math.max(0,math.min(P.target()-P.live,P.limit-P.live-held))
 end
 function P.dayTarget(n)return math.min(n,math.max(2,math.floor(n*.5+.5)))end
 function P.target()
  local sky=valid(P.gs)and P.gs.UDS;local t=valid(sky)and sky['Time of Day']or 1200
  if t>=1900 or t<600 or M.apocalypse.infestationActive then return P.limit end
  return P.dayTarget(P.limit)
 end
 function P.nativeBudget()
  local r=P.native;if not r or not valid(r.actor)then return end
  local s=r.actor;local room=P.remaining()
  for _,name in ipairs(fields)do s[name]=math.min(r.values[name],room)end
  if room==0 then
   if sys:K2_IsTimerActiveHandle(s,s.TimerHandle)and not sys:K2_IsTimerPausedHandle(s,s.TimerHandle)then
    sys:K2_PauseTimerHandle(s,s.TimerHandle);r.paused=true
   end
  elseif r.paused then sys:K2_UnPauseTimerHandle(s,s.TimerHandle);r.paused=false end
 end
 function P.enforce()
  local list={};for key,z in pairs(P.records)do if alive(z)then list[#list+1]=z else P.records[key]=nil end end
  -- Night survivors can remain in a fight after dawn. Stop new additions at
  -- the daytime target; the host's hard ceiling still applies at all times.
  local cap=P.disabled and 0 or P.rebalance and P.target()or P.limit;P.rebalance=nil
  if reserved()and not mechanicAlive()then cap=math.max(0,math.min(cap,P.limit-1))end
  if #list>cap then
   local players={};if valid(P.gs)then P.gs.Players:ForEach(function(_,v)local p=v:get();if valid(p)and p.IsLoaded then players[#players+1]=p:K2_GetActorLocation()end end)end
   local ranked={};for _,z in ipairs(list)do
    local at=z:K2_GetActorLocation();local nearest=math.huge
    for _,p in ipairs(players)do nearest=math.min(nearest,(at.X-p.X)^2+(at.Y-p.Y)^2+(at.Z-p.Z)^2)end
    ranked[#ranked+1]={actor=z,distance=nearest,mechanic=mechanicAlive()and z:GetAddress()==P.mechanic:GetAddress()}
   end
   table.sort(ranked,function(a,b)
    if a.mechanic~=b.mechanic then return a.mechanic==true end
    if a.distance==b.distance then return a.actor:GetAddress()<b.actor:GetAddress()end;return a.distance<b.distance
   end)
   for i=cap+1,#ranked do local z=ranked[i].actor;P.records[z:GetAddress()]=nil;z:K2_DestroyActor()end
  end
  P.live=math.min(#list,cap);P.dirty=false;P.nativeBudget()
 end
 function P.setLimit(n)
  assert(P.isHost(),'Only the host can change the zombie limit')
  assert(type(n)=='number'and n%1==0 and n>=2 and n<=40,'Choose 2 to 40 zombies')
  local f=assert(io.open(path..'.tmp','w'),'Cannot save the zombie limit');assert(f:write(tostring(n)..'\n'));assert(f:close())
  os.remove(path..'.bak');local old=io.open(path,'r');if old then old:close();assert(os.rename(path,path..'.bak'))end
  local ok,e=os.rename(path..'.tmp',path);if not ok then os.rename(path..'.bak',path);error(e)end
  P.limit=n;P.rebalance=true;P.enforce();return ('Zombie targets saved: %d day / %d night and infestations'):format(P.dayTarget(n),n)
 end
 function P.setDisabled(disabled)
  assert(P.isHost(),'Only the host can disable zombies')
  P.disabled=disabled==true
  if P.disabled then
   M.apocalypse.devPending=nil
   if M.mechanic then M.mechanic.reset()end
   if M.roaming then M.roaming.reset()end
  end
  P.enforce();return P.disabled and 'Zombies disabled for this session; existing zombies cleared.'or 'Zombies enabled; host limit '..P.limit
 end
 function P.tick(p)
  if not P.isHost()then return end
  local gs=game:GetGameState(p);if not valid(gs)or not valid(gs.BP_ZombieSpawner)then return end
  if not valid(P.gs)or P.gs:GetAddress()~=gs:GetAddress()then
   restoreNative();P.records={};P.live=0;P.mechanic=nil;P.gs=gs;P.worldAddress=p:GetWorld():GetAddress();P.rebalance=true
   local s=gs.BP_ZombieSpawner;P.native={actor=s,values={}}
   for _,name in ipairs(fields)do P.native.values[name]=s[name]end
   for _,z in ipairs(FindAllOf('BP_Zombie_C')or{})do P.track(z)end
  end
  local pending=P.incoming;P.incoming={};for _,z in ipairs(pending)do P.track(z)end
  local now=os.clock();if P.dirty or now>=P.nextAt then P.nextAt=now+.25;P.enforce()end
 end
 function P.reset()
  restoreNative();P.records={};P.incoming={};P.live=0;P.mechanic=nil;P.gs=nil;P.worldAddress=nil;P.disabled=false;P.nextAt=0
 end
 NotifyOnNewObject('/Game/BP/Player/Zombies/BP_Zombie.BP_Zombie_C',function(z)P.incoming[#P.incoming+1]=z end)
 local update='/Game/BP/Components/BP_ZombieSpawnerUsed.BP_ZombieSpawnerUsed_C:UpdateValue'
 if valid(StaticFindObject(update))then P.updateHook={RegisterHook(update,function()if P.native then P.nativeBudget()end end)}end
 return P
end

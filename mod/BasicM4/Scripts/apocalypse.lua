-- All native calls run inside the weapon pack's single game-thread queue.
return function(root,c,valid,log,hazmat)
 local P=dofile(root..'/Scripts/apocalypse_policy.lua')
 local Z=dofile(root..'/Scripts/zombie_variants.lua')
 local stops=dofile(root..'/Scripts/stop_encounters.lua')(P,c)
 local A={policy=P,owned={},locations={},stats={spawned=0,despawned=0,killed=0,deferred=0}}
 local gs,sys,road,classes,splines,stateFile,last,nextPass,nextRefresh,play,nextRoamer,nextSwarm,swarmLeft,swarmUntil,saveAt
 local placementLeft,locationCursor=nil,1
 local cleared={};local color={R=0,G=0,B=0,A=1}
 local function vec(v)return {X=v.X,Y=v.Y,Z=v.Z}end
 local function between(lo,hi)return math.random(math.floor(lo),math.floor(hi))end
 local function save()
  if not stateFile then return end
  local tmp=stateFile..'.tmp';local f=io.open(tmp,'w');if not f then return end
  f:write(string.format('clock %.3f %.3f %.3f\n',play,nextRoamer,nextSwarm))
  for k,t in pairs(cleared)do if t.untilTime>play then f:write(k..' '..t.kills..' '..math.floor(t.untilTime)..'\n')end end
  f:close()
  os.remove(stateFile..'.bak');os.rename(stateFile,stateFile..'.bak')
  local ok=os.rename(tmp,stateFile);if not ok then os.rename(stateFile..'.bak',stateFile);log('Apocalypse state write failed')end
 end
 function A.reset()
  save();gs=nil;sys=nil;road=nil;classes=nil;splines={};A.owned={};A.locations={};cleared={}
  placementLeft=nil;locationCursor=1
  stops.reset();A.previous=nil;A.spawningPaused=false;A.devPending=nil;stateFile=nil;last=nil;nextPass=0;nextRefresh=0;play=0;nextRoamer=0;nextSwarm=0;swarmLeft=0;swarmUntil=0;saveAt=0
 end
 A.reset()
 local function setup(p,game)
  gs=game:GetGameState(p);if not valid(gs)or not valid(gs.BP_ZombieSpawner)or not valid(gs.LSLevelSpawner)then return false end
  sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');classes=Z.classes(gs.BP_ZombieSpawner,valid)
  if #classes==0 then return false end
  stateFile=root..'/state/apocalypse-'..tostring(gs.Seed)..'.txt'
  local f=io.open(stateFile,'r');if f then
   for line in f:lines()do
    local a,b,d=line:match('^clock ([%d.]+) ([%d.]+) ([%d.]+)$')
    if a then play=tonumber(a);nextRoamer=tonumber(b);nextSwarm=tonumber(d)else
     local k,n,t=line:match('^(%S+) (%d+) (%d+)$');if k then cleared[k]={kills=tonumber(n),untilTime=tonumber(t)}end
    end
   end;f:close()
  end
  if nextRoamer<=0 then nextRoamer=play+between(c.RoamerMinSeconds,c.RoamerMaxSeconds)end
  if nextSwarm<=0 then nextSwarm=play+between(c.SwarmMinSeconds,c.SwarmMaxSeconds)end
  log('Apocalypse host manager ready; native spawner unchanged');return true
 end
 local function players(p,dt)
  local list={};gs.Players:ForEach(function(_,v)
   local a=v:get();if valid(a)and a.IsLoaded and not a.BP_PlayerStats.IsDead then
    local q=vec(a:K2_GetActorLocation());local v=vec(a:GetVelocity());local speed=math.sqrt(v.X*v.X+v.Y*v.Y)/100
    -- Attached passengers may report zero velocity; sample their world movement.
    local prev=A.previous and A.previous[a:GetFullName()]
    if prev and dt>0 and P.distance(q,prev)<200 then
     local vx,vy=(q.X-prev.X)/dt,(q.Y-prev.Y)/dt
     if vx*vx+vy*vy>v.X*v.X+v.Y*v.Y then v={X=vx,Y=vy,Z=0};speed=math.sqrt(vx*vx+vy*vy)/100 end
    end
    list[#list+1]={actor=a,pos=q,velocity=v,speed=speed,forward=vec(a:GetActorForwardVector())}
   end
  end)
  A.previous={};for _,t in ipairs(list)do A.previous[t.actor:GetFullName()]=t.pos end
  return list
 end
 local function refresh(ps)
  A.locations={}
  gs.LSLevelSpawner.LevelsRep:ForEach(function(_,v)
   local level=v:get();local q=vec(level.Transform.Translation)
   -- LevelsRep contains descriptors; this game's Level pointers remain null.
   -- Range stays within native streaming distance; collision readiness is checked below.
   if level.HasBeenInitialized and P.nearLocation(q,ps,c)and P.nearest(q,ps)<gs.LSLevelSpawner.DistanceLoadLevel/100 then
    local world=level.WorldSoftObjectPtrPath:ToString()
    if world==''then world=level.LevelLoad:ToString():gsub('_%d+_%d+_%d+$','')end
    local key=world:gsub('%s','_')..string.format('@%.0f,%.0f,%.0f',q.X,q.Y,q.Z)
    A.locations[#A.locations+1]={key=key,pos=q}
   end
  end)
  table.sort(A.locations,function(a,b)return P.nearest(a.pos,ps)<P.nearest(b.pos,ps)end)
  splines={}
  for _,s in ipairs(FindAllOf('SLSplineInfluencer')or{})do
   if valid(s)and s:GetFullName():find('PRRoadState',1,true)and s:GetSplineLength()>0 then splines[#splines+1]=s end
  end
  local total=0
  for _,z in ipairs(FindAllOf('BP_Zombie_C')or{})do
   if valid(z)and not z.IsDead and P.nearest(z:K2_GetActorLocation(),ps)<c.DespawnMeters then total=total+1 end
  end
  A.nearbyTotal=total
 end
 local function roadDistance(q)
  local distance=math.huge
  for _,s in ipairs(splines)do if valid(s)then
   local r=s:FindLocationClosestToWorldLocation(q,1)
   distance=math.min(distance,math.sqrt((q.X-r.X)^2+(q.Y-r.Y)^2)/100)
  end end
  return distance
 end
 local function roadSafe(q)
  local d=roadDistance(q)
  return d<math.huge and d>=c.RoadClearanceMeters
 end
 local function trace(context,a,b,radius)
  local hit={};local ok
  if radius then ok=sys:SphereTraceSingle(context,a,b,radius,0,false,{},0,hit,true,color,color,0)
  else ok=sys:LineTraceSingle(context,a,b,0,false,{},0,hit,true,color,color,0)end
  return ok,hit
 end
 local function point(p,origin,ps,rmin,rmax,game,sector)
  for attempt=1,4 do
   if placementLeft then
    if placementLeft<=0 then return end;placementLeft=placementLeft-1
   end
   local angle=sector and (sector.angle+(math.random()-0.5)*math.pi/8)or math.random()*math.pi*2
   local r=between(rmin,rmax)*100
   local q={X=origin.X+math.cos(angle)*r,Y=origin.Y+math.sin(angle)*r,Z=origin.Z}
   if P.safePoint(q,ps,c)and roadSafe(q)then
    local ok,h=trace(p,{X=q.X,Y=q.Y,Z=q.Z+15000},{X=q.X,Y=q.Y,Z=q.Z-20000})
    if ok and h.ImpactNormal.Z>0.8 then
     local hitComponent=h.Component:Get()
     A.lastGround=valid(hitComponent)and hitComponent:GetFullName()or 'no hit component'
     -- The procedural terrain is ground; rooftops and objects are excluded.
     local terrain=valid(hitComponent)and hitComponent:GetFullName():lower():find('landscape',1,true)
     q=vec(h.ImpactPoint)
     local spaced=true
     if sector then
      if P.distance(q,origin)<rmin or P.distance(q,origin)>rmax then spaced=false end
      for _,prior in ipairs(sector.prior)do if P.distance(q,prior)<c.StopSpawnSeparationMeters then spaced=false;break end end
     end
     if terrain and spaced and P.safePoint(q,ps,c)then
      local blocked=trace(p,{X=q.X,Y=q.Y,Z=q.Z+55},{X=q.X,Y=q.Y,Z=q.Z+160},42)
      local visible=false
      if not blocked then
       for _,t in ipairs(ps)do
        -- Within draw range, require terrain/buildings to hide materialization.
        local forward=(q.X-t.pos.X)*t.forward.X+(q.Y-t.pos.Y)*t.forward.Y
        if P.distance(q,t.pos)<c.DrawMeters and forward>0 then
         local occluded=trace(p,{X=t.pos.X,Y=t.pos.Y,Z=t.pos.Z+70},{X=q.X,Y=q.Y,Z=q.Z+140})
         if not occluded then visible=true;break end
        end
       end
       if not visible then q.Z=q.Z+100;return q end
      end
     end
    end
   end
  end
  A.stats.deferred=A.stats.deferred+1
 end
 local function spawn(p,game,q,key,runner,night,stopGroup,variant)
  local tr={Translation=q,Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
  local useHazmat=hazmat and(variant=='hazmat' or math.random(100)<=math.max(0,math.min(100,c.HazmatPercent or 20)))and hazmat.ready(p)
  local class=useHazmat and LoadAsset('/Game/BP/Player/Zombies/BP_Zombie_M01.BP_Zombie_M01_C')or classes[between(1,#classes)]
  local a=game:BeginDeferredActorSpawnFromClass(p,class,tr,2,nil,0)
  if not valid(a)then return false end
  local ok,e=pcall(function()
   a.Spawner=gs.BP_ZombieSpawner
   game:FinishSpawningActor(a,tr,0);Z.configure(a,c,valid)
   -- Blueprint components may not exist until construction completes.
   if valid(a.ItemSaver)then a.ItemSaver.SaveOnDistance=false end
   if useHazmat then
    useHazmat=hazmat.mark(a)
    if useHazmat and variant~='hazmat' then runner=runner or math.random(100)<=(night and 30 or 15)end
   end
  end)
  if not ok then a:K2_DestroyActor();error(e)end
  A.owned[#A.owned+1]={actor=a,key=key,runner=runner,stopGroup=stopGroup,baseSpeed=a.MaxSpeed,born=play,chaseUntil=play+c.SwarmChaseSeconds}
  A.stats.spawned=A.stats.spawned+1;A.nearbyTotal=(A.nearbyTotal or 0)+1
  return true
 end
 local function maintain(ps,night)
  local kept={};local counts={}
  for _,t in ipairs(A.owned)do
   local a=t.actor
   if valid(a)then
    local d=P.nearest(a:K2_GetActorLocation(),ps)
    if a.IsDead and not t.dead then
     t.dead=play;A.stats.killed=A.stats.killed+1
     if t.key then local r=cleared[t.key]or{kills=0};r.kills=r.kills+1;r.untilTime=play+c.LocationRespawnSeconds;cleared[t.key]=r end
     save()
    end
    if d>c.DespawnMeters then t.outside=t.outside or play else t.outside=nil end
    local remove=t.outside and play-t.outside>=c.DespawnGraceSeconds
    if t.dead and play-t.dead>180 and d>150 then remove=true end
    if remove then a:K2_DestroyActor();A.stats.despawned=A.stats.despawned+1
    else
     kept[#kept+1]=t
     if not t.dead then
      if t.key then counts[t.key]=(counts[t.key]or 0)+1 end
      local running=t.runner and play<t.chaseUntil
      a.MaxSpeed=running and c.RunnerSpeed or t.baseSpeed*(night and c.NightSpeedMultiplier or 1)
      -- Reduce distant work, retain full-rate nearby combat.
      local interval=d>400 and 0.3 or (d>180 and 0.1 or 0)
      a:SetActorTickInterval(interval)
      if valid(a.CharacterMovement)then a.CharacterMovement:SetComponentTickInterval(interval);a.CharacterMovement.MaxWalkSpeed=a.MaxSpeed end
      -- Stop hunters keep pursuing without the timed swarm's five-minute limit.
      if not a.IsSpawning and (running or t.stopGroup) and #ps>0 then
       local target=ps[1];for _,t2 in ipairs(ps)do if P.distance(a:K2_GetActorLocation(),t2.pos)<P.distance(a:K2_GetActorLocation(),target.pos)then target=t2 end end
       a['Target Player']=target.actor;a.angry=true;a:MoveToTarget(150,target.pos)
      elseif not a.IsSpawning and not t.roaming then a:RoamingAround();t.roaming=true end
     end
    end
   end
  end
  A.owned=kept;return counts
 end
 function A.tick(p,game,now)
  if not c.Enabled or not p:HasAuthority()then return end
  if not valid(gs)then if not setup(p,game)then return end end
  if now<nextPass then return end
  local dt=last and math.max(0,math.min(5,now-last))or 0;last=now;nextPass=now+1;play=play+dt
  local ps=players(p,dt);if #ps==0 then stops.reset();return end
  local night=valid(gs.UDS)and P.night(gs.UDS['Time of Day'])or false
  local counts=maintain(ps,night)
  if now>=nextRefresh then refresh(ps);nextRefresh=now+5 end
  local budget=P.budget(#A.owned,A.nearbyTotal or 0,night,c)
  placementLeft=nil
  A.status={play=play,night=night,live=#A.owned,locations=#A.locations,total=A.nearbyTotal,nextSwarm=nextSwarm-play,swarmLeft=swarmLeft}
  -- Pausing additions must not suspend distance cleanup or existing AI maintenance.
  if A.spawningPaused then A.devPending=nil;return end
  if A.devPending then
   if play>A.devPending.untilTime then A.devPending=nil
   elseif budget>0 then
    local target=A.devPending.target
    local position=valid(target)and target:K2_GetActorLocation()or ps[1].pos
    local q=point(p,position,ps,160,300,game)
    if q and spawn(p,game,q,nil,A.devPending.runner,night,nil,A.devPending.variant)then
     budget=budget-1;A.devPending.count=A.devPending.count-1
     if A.devPending.count<=0 then A.devPending=nil end
    end
   end
  end
  local stopAlive,stopCount={},0
  for _,t in ipairs(A.owned)do if t.stopGroup and not t.dead then
   stopAlive[t.stopGroup]=(stopAlive[t.stopGroup]or 0)+1;stopCount=stopCount+1
  end end
  for _,t in ipairs(ps)do
   t.roadMeters=roadDistance(t.pos);t.nearBuilding=false
   for _,loc in ipairs(A.locations)do
    if P.distance(t.pos,loc.pos)<=c.BuildingRadiusMeters then t.nearBuilding=true;break end
   end
  end
  for _,request in ipairs(stops.update(ps,play,stopAlive))do
   if budget<=0 or stopCount>=c.StopMaxHunters then break end
   local q=point(p,request.origin,ps,c.StopSpawnMinMeters,c.StopSpawnMaxMeters,game,request)
   local created=q and spawn(p,game,q,nil,false,night,request.group.id)
   stops.result(request,created and q or nil,play)
   if created then budget=budget-1;stopCount=stopCount+1 end
  end
  if play>=nextSwarm then
   swarmLeft=between(c.SwarmMin,c.SwarmMax);swarmUntil=play+120
   nextSwarm=play+between(c.SwarmMinSeconds,c.SwarmMaxSeconds);save();log('Runner encounter queued')
  end
  if play>swarmUntil then swarmLeft=0 end
  if swarmLeft>0 and budget>0 then
   local q=point(p,ps[1].pos,ps,180,320,game)
   if q and spawn(p,game,q,nil,true,night)then swarmLeft=swarmLeft-1;budget=budget-1 end
  end
  -- Bound failed POI placement work; other encounter timers retain their turn.
  placementLeft=math.max(4,(c.MaxSpawnsPerPass or 2)*4)
  local locationCount=#A.locations
  local start=locationCount>0 and((locationCursor-1)%locationCount+1)or 1
  for offset=0,locationCount-1 do
   if budget<=0 or placementLeft<=0 then break end
   local index=(start+offset-1)%locationCount+1
   local loc=A.locations[index];locationCursor=index%locationCount+1
   local rec=cleared[loc.key];if rec and rec.untilTime<=play then cleared[loc.key]=nil;rec=nil end
   local hash=5381;for i=1,#loc.key do hash=(hash*33+loc.key:byte(i))&0xffffffff end
   local lo,hi=night and c.NightMin or c.DayMin,night and c.NightMax or c.DayMax
   local desired=math.max(0,lo+hash%(hi-lo+1)-(rec and rec.kills or 0))
   if (counts[loc.key]or 0)<desired then
    local q=point(p,loc.pos,ps,30,140,game)
    if q and spawn(p,game,q,loc.key,false,night)then budget=budget-1;counts[loc.key]=(counts[loc.key]or 0)+1 end
   end
  end
  placementLeft=nil
  if play>=nextRoamer and budget>0 then
   local q=point(p,ps[1].pos,ps,160,300,game)
   if q and spawn(p,game,q,nil,false,night)then
    nextRoamer=play+between(c.RoamerMinSeconds,c.RoamerMaxSeconds)/(night and 1.75 or 1);save()
   end
  end
  if play>=saveAt then saveAt=play+30;save()end
  A.status={play=play,night=night,live=#A.owned,locations=#A.locations,total=A.nearbyTotal,nextSwarm=nextSwarm-play,swarmLeft=swarmLeft,stopHunters=stopCount}
 end
 A.save=save
 A.stopEncounters=stops
 function A.devEncounter(count,runner,variant,target)
  assert(valid(gs)and gs:HasAuthority(),'Apocalypse host manager not ready')
  assert(c.Enabled and not A.spawningPaused,'Enable Apocalypse additions first')
  assert(not A.devPending,'An encounter is already queued')
  if variant=='hazmat'then assert(hazmat and hazmat.ready(gs),'Hazmat import unavailable; check the mod log')end
  A.devPending={count=math.max(1,math.min(10,math.floor(count))),runner=runner==true,variant=variant,target=target,untilTime=play+120}
 end
 function A.devClear()
  assert(valid(gs)and gs:HasAuthority(),'Host only')
  local n=0;for _,t in ipairs(A.owned)do if valid(t.actor)then t.actor:K2_DestroyActor();n=n+1 end end
  A.owned={};A.devPending=nil;swarmLeft=0;A.stats.despawned=A.stats.despawned+n
  nextRefresh=0;return n
 end
 return A
end

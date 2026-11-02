-- One host-owned native enemy. No client spawning, custom RPC, or saved actor.
return function(root,c,valid,log)
 local N={};local visual=dofile(root..'/Scripts/mechanic_visual.lua')(root,valid,log)
 local markerName='BA_Mechanic_v1'
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local actor,target,world,nextScan,nextThink,lastNow,respawnAt,bearing,manual,sawNight,killed,deadAt,farAt
 local marked={};local reported={};local lastState,lastAttack,nextPath,recoverUntil
 local function distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)/100 end
 local function vec(v)return {X=v.X,Y=v.Y,Z=v.Z}end
 local function remove()
  if valid(actor)and actor:HasAuthority()then actor:K2_DestroyActor()end
  actor=nil;deadAt=nil;farAt=nil;lastState=nil;lastAttack=nil;nextPath=0;recoverUntil=0
 end
 function N.reset()
  remove();visual.reset();target=nil;world=nil;marked={};nextScan=0;nextThink=0;lastNow=nil
  respawnAt=0;bearing=nil;manual=false;sawNight=false;killed=false;reported={}
 end
 N.reset()
 local function marker(z)
  for _,v in ipairs(z:K2_GetComponentsByClass(StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')))do
   local component=v:get()
   if valid(component)and component.AttachSocketName:ToString():lower()==markerName:lower()then return component end
  end
 end
 local function scan(host)
  marked={}
  for _,z in ipairs(FindAllOf('BP_Zombie_C')or{})do if valid(z)then
   local m=marker(z)
   if m then
    if host and z:HasAuthority()and valid(actor)and actor:GetAddress()~=z:GetAddress()then z:K2_DestroyActor()
    else
     if host and z:HasAuthority()then actor=z end
     marked[#marked+1]={actor=z,marker=m}
    end
   end
  end end
 end
 local function players(gs)
  local ps={}
  gs.Players:ForEach(function(_,v)
   local p=v:get()
   if valid(p)and p.IsLoaded and valid(p.BP_PlayerStats)and not p.BP_PlayerStats.IsDead then ps[#ps+1]={actor=p,pos=vec(p:K2_GetActorLocation())}end
  end)
  return ps
 end
 local function nearest(q,ps)
  local n=math.huge;for _,p in ipairs(ps)do n=math.min(n,distance(q,p.pos))end;return n
 end
 local function ground(p,q,dev)
  local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
  local h={};local color={R=0,G=0,B=0,A=1}
  if not sys:LineTraceSingle(p,{X=q.X,Y=q.Y,Z=q.Z+3000},{X=q.X,Y=q.Y,Z=q.Z-12000},0,false,{p},0,h,true,color,color,0)or h.ImpactNormal.Z<.8 then return end
  local comp=h.Component:Get()
  if not dev and(not valid(comp)or not comp:GetFullName():lower():find('landscape',1,true))then return end
  q=vec(h.ImpactPoint)
  if sys:SphereTraceSingle(p,{X=q.X,Y=q.Y,Z=q.Z+55},{X=q.X,Y=q.Y,Z=q.Z+170},42,0,false,{p},0,{},true,color,color,0)then return end
  q.Z=q.Z+100;return q
 end
 local function spawn(p,game,gs,q,now)
  if N.population and N.population.remaining()==0 then return end
  local ready,err=visual.ready(p);assert(ready,err)
  local tr={Translation=q,Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
  local z=game:BeginDeferredActorSpawnFromClass(p,LoadAsset('/Game/BP/Player/Zombies/BP_Zombie_M01.BP_Zombie_M01_C'),tr,2,nil,0)
  assert(valid(z),'No free space for Mechanic')
  local ok,e=pcall(function()
   z.Spawner=gs.BP_ZombieSpawner;game:FinishSpawningActor(z,tr,0)
   z.HP=z.HP*3 -- Host-only, once at creation; ordinary zombies stay unchanged.
   z.MaxSpeed=300;z.CharacterMovement.MaxWalkSpeed=300
   z:SetReplicates(true);z:SetReplicateMovement(true);z.bAlwaysRelevant=false;z.NetCullDistanceSquared=90000^2
   if valid(z.ItemSaver)then z.ItemSaver.SaveOnDistance=false end
   local m=z:AddComponentByClass(StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent'),true,identity,false)
   assert(valid(m),'Mechanic identity unavailable')
   m:SetCollisionEnabled(0);m:SetVisibility(false,false)
   m:K2_AttachToComponent(z.RootComponent,FName(markerName),0,0,0,false)
   m:SetRelativeScale3D({X=1,Y=1,Z=gs:GetServerWorldTimeSeconds()+1});m:SetIsReplicated(true)
   z:FlushNetDormancy();z:ForceNetUpdate()
   -- Replace only after the new actor was constructed successfully, in one tick.
   local closest=p;local best=distance(q,p:K2_GetActorLocation())
   for _,v in ipairs(players(gs))do local d=distance(q,v.pos);if d<best then best=d;closest=v.actor end end
   remove();actor=z;marked={{actor=z,marker=m}};target=closest;respawnAt=now+35
   z.IsSpawning=false;z['Target Player']=closest;z.angry=true
   z:MoveToTarget(150,vec(closest:K2_GetActorLocation()));nextPath=now+.9
  end)
  if not ok then z:K2_DestroyActor();error(e)end
  if N.population then N.population.track(z)end
  return z
 end
 function N.spawnHere(p,game)
  assert(valid(p)and p:HasAuthority(),'Mechanic spawning requires the host')
  local gs=game:GetGameState(p);assert(valid(gs)and valid(gs.BP_ZombieSpawner),'World is not ready')
  local q,v=p:K2_GetActorLocation(),p:GetActorForwardVector();local len=math.sqrt(v.X*v.X+v.Y*v.Y)
  assert(len>.01,'Look forward before spawning')
  local spot=ground(p,{X=q.X+v.X/len*500,Y=q.Y+v.Y/len*500,Z=q.Z},true)
  assert(spot,'Clear the ground directly in front of you')
  local z=spawn(p,game,gs,spot,game:GetTimeSeconds(p))
  world=gs;manual=true;killed=false;bearing=nil
  local hour=valid(gs.UDS)and gs.UDS['Time of Day']or 1200;sawNight=hour>=1900 or hour<600
  return z
 end
 local function animation(z,m,gs)
  local velocity=z:GetVelocity();local speed=math.sqrt(velocity.X^2+velocity.Y^2)
  local index=z.IsDead and 4 or(z.IsHit and 3 or(z.IsAttacking and(lastAttack or 5)or(speed>35 and 2 or 1)))
  if z.IsAttacking and lastState~=5 and lastState~=6 then lastAttack=lastAttack==5 and 6 or 5;index=lastAttack end
  if z.IsDead then index=4 end
  if index~=lastState then
   local rate=1
   if index==5 or index==6 then
    local inst=z.Mesh:GetAnimInstance()
    if valid(inst)then
     local montage=inst:GetCurrentActiveMontage()
     if valid(montage)and montage.SequenceLength>0 then rate=visual.clips()[index].SequenceLength/montage.SequenceLength*math.abs(inst:Montage_GetPlayRate(montage))end
    end
   elseif index==2 then rate=math.max(.75,math.min(1.6,speed/450))end
   m:SetRelativeScale3D({X=index,Y=math.max(.25,math.min(4,rate)),Z=gs:GetServerWorldTimeSeconds()+1})
   z:ForceNetUpdate();lastState=index
  end
 end
 local function tick(p,game,now)
  local gs=game:GetGameState(p);if not valid(gs)then return end
  if world and(not valid(world)or world:GetAddress()~=gs:GetAddress())or lastNow and now<lastNow then N.reset()end
  world=gs;lastNow=now
  local host=p:HasAuthority()
  if now>=nextScan then scan(host);visual.prune();nextScan=now+1 end
  if host and valid(gs.UDS)and valid(gs.BP_ZombieSpawner)and now>=nextThink then
   nextThink=now+.25
   local t=gs.UDS['Time of Day'];local night=t>=1900 or t<600
   if not night and sawNight then remove();manual=false;killed=false;bearing=nil;respawnAt=now+5 end
   sawNight=night
   if not manual and(not night or c.Enabled==false or c.MechanicEnabled==false)then remove()
   else
    local ps=players(gs);local chosen
    do
     local best=math.huge;local q=valid(actor)and actor:K2_GetActorLocation()or p:K2_GetActorLocation()
     for _,v in ipairs(ps)do local d=distance(q,v.pos);if d<best then best=d;chosen=v end end
    end
    if valid(actor)then
     if actor.IsDead then
      deadAt=deadAt or now;killed=true
      if now-deadAt>=20 then remove()end
     elseif chosen then
      if not valid(target)or target:GetAddress()~=chosen.actor:GetAddress()then nextPath=0 end
      target=chosen.actor;local q=actor:K2_GetActorLocation()
      bearing=math.atan(q.Y-chosen.pos.Y,q.X-chosen.pos.X)
      if nearest(q,ps)>950 then farAt=farAt or now else farAt=nil end
      if farAt and now-farAt>=8 then remove();respawnAt=now+35
      elseif not actor.IsSpawning then
       actor['Target Player']=target;actor.angry=true
       -- Let native attacks/hit reactions finish without restarting their chase.
       -- A short recovery gives the player room to dodge and break contact.
       if actor.IsAttacking or actor.IsHit then recoverUntil=now+.65 end
       if now<recoverUntil then
        actor.MaxSpeed=0;actor.CharacterMovement.MaxWalkSpeed=0
        actor:StopInputMoving();nextPath=now+.25
       else
        local speed=distance(q,chosen.pos)<6 and 220 or 300
        actor.MaxSpeed=speed;actor.CharacterMovement.MaxWalkSpeed=speed
        -- Pursue a sampled position rather than continuously steering into the player.
        if now>=nextPath then actor:MoveToTarget(150,vec(chosen.pos));nextPath=now+.9 end
       end
      end
     else remove();respawnAt=now+35 end
    elseif actor~=nil then remove();respawnAt=now+35
    elseif not killed and chosen and now>=respawnAt then
     respawnAt=now+5
     for attempt=1,4 do
      local angle=bearing and(bearing+(math.random()-.5)*.35)or math.random()*math.pi*2
      local r=math.random(180,230)*100
      local q={X=chosen.pos.X+math.cos(angle)*r,Y=chosen.pos.Y+math.sin(angle)*r,Z=chosen.pos.Z}
      if nearest(q,ps)>120 then q=ground(p,q,false)else q=nil end
      if q then spawn(chosen.actor,game,gs,q,now);break end
     end
    end
   end
  end
  for _,r in ipairs(marked)do if valid(r.actor)and valid(r.marker)then
   if host then animation(r.actor,r.marker,gs)end
   visual.present(r.actor,r.marker,gs:GetServerWorldTimeSeconds())
  end end
 end
 function N.tick(p,game,now)
  local ok,e=pcall(tick,p,game,now)
  if not ok and not reported[tostring(e)]then reported[tostring(e)]=true;log('Mechanic: '..tostring(e))end
 end
 N.visual=visual;N.markerName=markerName
 return N
end

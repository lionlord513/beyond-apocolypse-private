-- Only marked Hornets/carriers participate. Native vehicles save independently:
-- never put an entire aircraft in the native item-cargo serialization list.
return function(M,G,root,H,valid,log)
 local T={carriers={},aircraft={},pending={},seen={},nextScan=0};local ownerChanges={};local none=FName('None')
 local J=dofile(root..'/Scripts/gyrocopter/journal.lua')(root,valid,log,M.statePath);T.journal=J
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
 local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local scene=StaticFindObject('/Script/Engine.SceneComponent')
 local meshClass=StaticFindObject('/Script/Engine.StaticMeshComponent')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local color={R=0,G=0,B=0,A=1};local markerName='BA_HornetCarrier_v1'
 local function vec(x,y,z)return {X=x,Y=y,Z=z}end
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function length(v)return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)end
 local function delta(a,b)return length(vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z))end
 local function parts(a,fn)a.CarEquipableComponents:ForEach(function(_,v)local p=v:get().AttachedCarEquipableActor;if valid(p)then fn(p)end end)end
 local function marker(a)
  for _,v in ipairs(a:K2_GetComponentsByClass(scene))do local c=v:get();if valid(c)and c.AttachSocketName:ToString()==markerName then return c end end
 end
 function T.id(t)local p=t.CarEquipableV2.AttachedCarEquipableActor;return valid(p)and M.guid(p)or nil end
 function T.hasCarrier(t)return valid(t)and T.carriers[t:GetFullName()]~=nil end
 function T.roll(id)
  local hash=5381;for i=1,#id do hash=(hash*33+id:byte(i))&0xffffffff end
  return hash%100<50
 end
 function T.create(p,heli,at)
  assert(valid(p)and p:HasAuthority(),'Trailer spawning requires server authority')
  if not at then
   local q,f=p:K2_GetActorLocation(),p:GetActorForwardVector()
   for _,n in ipairs({1200,1800,2400,3000})do at=G.clearance(p,vec(q.X+f.X*n,q.Y+f.Y*n,q.Z));if at then break end end
  end
  assert(at,'Move to open, level ground before spawning a trailer')
  local tr={Translation=at,Rotation={X=0,Y=0,Z=0,W=1},Scale3D=vec(1,1,1)}
  local t=game:BeginDeferredActorSpawnFromClass(p,LoadAsset('/Game/BP/CarsV2/Vehicle_Trailer.Vehicle_Trailer_C'),tr,1,nil,0)
  assert(valid(t),'Native trailer unavailable');t.SpawnWithOriginalPart=true;game:FinishSpawningActor(t,tr,0)
  T.pending[t:GetFullName()]={heli=heli==true,after=game:GetTimeSeconds(p)+3}
  return heli and 'Heli trailer assembling with its landing pad fitted'or 'Normal trailer assembling nearby',t
 end
 function T.spawn(heli,at)return T.create(H.GetPlayer(),heli,at)end
 function T.classify(t,id,now)
  if not J.ready or J.error or not id or J.state.carrier[id]or J.state.ordinary[id]then return end
  local key=t:GetFullName();local choice=T.pending[key]
  T.seen[key]=T.seen[key]or now
  if now<(choice and choice.after or T.seen[key]+3)then return end
  -- Select once per saved native trailer, not once per streaming visit.
  local heli=choice and choice.heli or not choice and T.roll(id)
  if heli and #t.AttachActorOn.ActorsAttached==0 then
   if not T.stopped(t)then return end
   local ok,e=pcall(T.upgrade,t);if not ok then
    if T.setupError~=tostring(e)then T.setupError=tostring(e);log('Carrier setup: '..T.setupError)end
    T.seen[key]=now+2;if choice then choice.after=now+5 end;return
   end
  else J.writable();J.state.ordinary[id]=true end
  T.pending[key]=nil;T.seen[key]=nil
 end
 function T.deckCollision(r)
  local t=r.actor;local found={};r.collisionReady=r.collisionReady or{}
  for _,v in ipairs(t:K2_GetComponentsByClass(meshClass))do
   local c=v:get();local side=valid(c)and c.AttachSocketName:ToString():match('^BA_HornetDeck_v2_([123])$')
   if side then found[tonumber(side)]=c end
  end
  for i,v in ipairs({{-50,0,105,4.8,2.4,.12},{43,-88,116,.10,.32,.10},{43,88,116,.10,.32,.10}})do
   local c=found[i];local created=false
   if not c and t:HasAuthority()then
    c=t:AddComponentByClass(meshClass,true,identity,false);assert(valid(c),'Carrier deck unavailable');r.components[#r.components+1]=c
    c:K2_AttachToComponent(t.VehicleMesh,FName('BA_HornetDeck_v2_'..i),0,0,0,false);created=true
   end
   if valid(c)and not r.collisionReady[c:GetAddress()]then
    -- LoadAsset returns mesh, found, loaded. Pass only the mesh to Unreal.
    local cube=LoadAsset('/Engine/BasicShapes/Cube.Cube');c:SetStaticMesh(cube)
    c:SetRelativeScale3D(vec(v[4],v[5],v[6]));c:K2_SetRelativeLocation(vec(v[1],v[2],v[3]),false,{},true)
    -- One replicated movement base on both peers, with no welded tow mass.
    -- Clients wait for it instead of standing on an unrelated local collider.
    c:SetVisibility(false,false);c:SetCollisionProfileName(FName('BlockAll'),true);c:SetCollisionEnabled(1);c:SetCullDistance(65000)
    t.Wheels:ForEach(function(_,w)local wheel=w:get();if valid(wheel)then c:SetCollisionResponseToChannel(wheel.WheelConfig.TraceChannel,0)end end)
    if created then c:SetIsReplicated(true);t:FlushNetDormancy();t:ForceNetUpdate()end
    r.collisionReady[c:GetAddress()]=true
   end
   if valid(c)and c:GetCollisionEnabled()>=2 then c:SetCollisionEnabled(1)end
  end
 end
 function T.deck(t)
  local key=t:GetFullName();if T.carriers[key]then return T.carriers[key]end
  local id=t:HasAuthority()and T.id(t);local mark=marker(t)
  local savedMass=id and J.state.bodymass[id]or valid(mark)and mark.RelativeLocation.X>25 and mark.RelativeLocation.X
  local r={actor=t,id=id,components={},baseMass=savedMass or t.VehicleMesh:GetMass()}
  local ok,e=pcall(function()
   T.deckCollision(r)
   local visual=t:AddComponentByClass(pmc,true,identity,false);assert(valid(visual));r.components[#r.components+1]=visual
   visual:K2_AttachToComponent(t.VehicleMesh,none,0,0,0,false);visual:SetIsReplicated(false);G.visuals.fill(visual,'carrier',false,t);r.visual=visual
   if t:HasAuthority()and not marker(t)then
    local c=t:AddComponentByClass(scene,true,identity,false);assert(valid(c));c:SetVisibility(false,false)
    c:K2_AttachToComponent(t.VehicleMesh,FName(markerName),0,0,0,false);c:K2_SetRelativeLocation(vec(r.baseMass,0,0),false,{},true);c:SetIsReplicated(true);t:ForceNetUpdate()
   end
  end)
  if not ok then for _,c in ipairs(r.components)do if valid(c)then c:K2_DestroyComponent(t)end end;error(e)end
  if id then J.state.bodymass[id]=r.baseMass end
  G.visuals.prune(t,{r.visual},true);T.carriers[key]=r;return r
 end
 local function ignored(a,t)
  local list={a,t};parts(a,function(p)list[#list+1]=p end);parts(t,function(p)list[#list+1]=p end)
  if valid(a.Driver)then list[#list+1]=a.Driver end
  -- These original blades are refitted during departure. Exclude their native
  -- pickup meshes from the body sweep, while retaining all unrelated cargo.
  if T.blades then for _,b in pairs(T.blades.items)do if valid(b.actor)then
   local rack=J.state.rack[M.guid(b.actor)]
   if rack and rack[1]==T.id(t)and b.owner==G.id(a)and same(b.actor:GetAttachParentActor(),t)then list[#list+1]=b.actor end
  end end end
  if valid(a.CarCollisionProxy)then list[#list+1]=a.CarCollisionProxy end;return list
 end
 function T.clear(a,t,rotor)
  local center=mathlib:TransformLocation(t:GetTransform(),vec(0,0,rotor and 337 or 220));local hit={}
  return not sys:BoxTraceSingle(t,center,vec(center.X,center.Y,center.Z+.1),rotor and vec(340,340,15)or vec(170,98,105),t:K2_GetActorRotation(),0,false,ignored(a,t),0,hit,true,color,color,0)
 end
 local function stopped(a)return length(a.VehicleMesh:GetPhysicsLinearVelocity(none))<20 and length(a.VehicleMesh:GetPhysicsAngularVelocityInDegrees(none))<4 end
 function T.dockRange(a,t)
  local p=mathlib:InverseTransformLocation(t:GetTransform(),a:K2_GetActorLocation())
  return math.abs(p.X+30)<210 and math.abs(p.Y)<135 and p.Z>45 and p.Z<245
 end
 function T.checkDock(a,t)
  assert(T.hasCarrier(t),'Find a Hornet carrier trailer')
  assert(T.dockRange(a,t),'Hover low over the landing pad, then press J')
  local av,tv=a.VehicleMesh:GetPhysicsLinearVelocity(none),t.VehicleMesh:GetPhysicsLinearVelocity(none)
  assert(length(tv)<100 and length(t.VehicleMesh:GetPhysicsAngularVelocityInDegrees(none))<25,'Park the trailer before docking')
  assert(delta(av,tv)<500,'Slow to a hover above the pad')
  local ar,tr=a:K2_GetActorRotation(),t:K2_GetActorRotation()
  assert(math.abs(ar.Pitch)<45 and math.abs(ar.Roll)<45 and math.abs(tr.Roll)<18 and math.abs(tr.Pitch)<18,'Keep the aircraft upright above a level pad')
  for _,r in pairs(G.tracked)do if not same(r.actor,a)and same(r.docked,t)then error('Carrier is occupied')end end
  assert(T.clear(a,t,false),'Clear cargo and people from the aircraft footprint')
  -- The blades are folded into their racks as part of this transaction;
  -- their expanded rotor disc does not need departure clearance to dock.
  return true
 end
 local function restoreCollision(r)
  if r.savedNetwork then
   for k,v in pairs(r.savedNetwork)do r.actor[k]=v end;r.savedNetwork=nil
  end
  if r.syncSuspended then r.actor:SetShouldSyncWithServer(true);r.syncSuspended=nil end
  for _,w in ipairs(r.savedWheels or{})do if valid(w[1])then w[1]:SetIsSimulatingSuspension(w[2])end end;r.savedWheels=nil
  for _,p in ipairs(r.savedCollision or{})do if valid(p[1])then p[1]:SetCollisionEnabled(p[2])end end
  if r.savedPhysics~=nil then
   local physics=r.savedPhysics;if r.dockOwnerChanged then physics=G.simulates(r.actor)end
   r.actor.VehicleMesh:SetSimulatePhysics(physics);r.savedPhysics=nil
  end
  r.dockOwnerChanged=nil
  r.savedCollision=nil;r.collisionSeen=nil;r.collisionAt=nil
 end
 local function suspendCollision(r)
  if r.savedPhysics==nil then
   r.savedPhysics=r.freePhysics
   if r.savedPhysics==nil then r.savedPhysics=r.actor.VehicleMesh:IsSimulatingPhysics(none)end
  end
  r.savedCollision=r.savedCollision or{};r.collisionSeen=r.collisionSeen or{}
  local current={};local function suspend(o)
   -- Keep native seat/part traces alive. Only rigid-body collision is removed.
   -- Also repairs actors saved while the old build disabled actor collision.
   if not o:GetActorEnableCollision()then o:SetActorEnableCollision(true)end
   for _,v in ipairs(o:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.PrimitiveComponent')))do
    local c=v:get();if valid(c)then
     local key=c:GetAddress();current[key]=true;local mode=c:GetCollisionEnabled()
     if mode>=2 then
      if not r.collisionSeen[key]then r.collisionSeen[key]=true;r.savedCollision[#r.savedCollision+1]={c,mode}end
      c:SetCollisionEnabled(1)
     end
    end
   end
  end
  suspend(r.actor);parts(r.actor,suspend)
  if valid(r.actor.CarCollisionProxy)then suspend(r.actor.CarCollisionProxy)end
  if not r.savedNetwork then r.savedNetwork={ReplicateMovement=r.actor.ReplicateMovement,SyncLocation=r.actor.SyncLocation,SyncRotation=r.actor.SyncRotation}end
  -- AVS free-flight smoothing otherwise fights the trailer attachment on the
  -- owning client. Restore the original flags as soon as it is released.
  r.actor.ReplicateMovement=false;r.actor.SyncLocation=false;r.actor.SyncRotation=false
  -- AVS keeps a native NetStateSend timer plus a receive gate. Changing its
  -- public flags alone leaves that timer running on the guest pilot. Use the
  -- game's setter to stop both while the trailer owns the transform.
  if not r.syncSuspended then r.actor:SetShouldSyncWithServer(false);r.syncSuspended=true end
  if not r.savedWheels then
   r.savedWheels={};r.actor.Wheels:ForEach(function(_,v)local w=v:get();if valid(w)then r.savedWheels[#r.savedWheels+1]={w,w:GetIsSimulatingSuspension()}end end)
  end
  for _,w in ipairs(r.savedWheels)do if valid(w[1])and w[1]:GetIsSimulatingSuspension()then w[1]:SetIsSimulatingSuspension(false)end end
  for i=#r.savedCollision,1,-1 do local p=r.savedCollision[i]
   if not valid(p[1])or not current[p[1]:GetAddress()]then
    if valid(p[1])then p[1]:SetCollisionEnabled(p[2]);r.collisionSeen[p[1]:GetAddress()]=nil end
    table.remove(r.savedCollision,i)
   end
  end
 end
 function T.guardPart(p)
  if not valid(p)or T.guarding or not T.blades or not T.blades.items[p:GetFullName()]then return end
  local slot=p.ParentCarEquipableV2
  if not valid(slot)then return end
  local mount=T.blades.mounts.slots[slot:GetAddress()];local r=mount and G.tracked[mount.actor:GetFullName()]
  if not r or not(valid(r.docked)or r.pendingDock)then return end
  T.guarding=true
  local ok,e=pcall(function()
   p.CollisionWhenAttached=1;p.RootMeshComponent:SetCollisionEnabled(1);p.RootMeshComponent:SetSimulatePhysics(false)
   suspendCollision(r);r.actor.VehicleMesh:SetSimulatePhysics(false)
  end)
  T.guarding=false;if not ok then error(e)end
 end
 function T.bind(r,t)
  local a=r.actor;assert(valid(t)and valid(a),'Aircraft or trailer unavailable')
  if same(r.docked,t)and same(a:GetAttachParentActor(),t)then return end
  local motor=a.CarMotorV2.AttachedCarEquipableActor;if valid(motor)then motor:StopMotor()end
  r.mass=a.VehicleMesh:GetMass();r.settleAt=nil;suspendCollision(r)
  a:SetThrottleInput(0);a.VehicleMesh:SetPhysicsLinearVelocity(vec(0,0,0),false,none);a.VehicleMesh:SetPhysicsAngularVelocityInDegrees(vec(0,0,0),false,none)
  a.VehicleMesh:SetSimulatePhysics(false)
  assert(a:K2_AttachToActor(t,none,2,2,2,false),'Native attachment refused')
  a:K2_SetActorRelativeLocation(vec(0,0,94),false,{},true)
  a:K2_SetActorRelativeRotation({Pitch=0,Yaw=0,Roll=0},false,{},true)
  r.docked=t;r.flight=G.flight.new();r.pendingDock=nil;a:FlushNetDormancy();a:ForceNetUpdate()
 end
 function T.hold(r,now)
  local a=r.actor;local parent=a:GetAttachParentActor()
  if not a:HasAuthority()then
   if r.netState then
    if r.netState.dock>0 then
     r.confirmedDock=true;r.releasedParent=nil;r.mass=r.netState.mass;r.pendingDock=not valid(r.netCarrier)
     if valid(r.netCarrier)then
      r.docked=r.netCarrier
     end
    elseif r.confirmedDock then
     -- A confirmed dock followed by a newer zero state is an explicit release.
     -- Ignore a late native parent update from the just-released attachment.
     r.releasedParent=r.docked or parent;r.releaseUntil=now+1;r.confirmedDock=nil
     a:K2_DetachFromActor(1,1,1);restoreCollision(r)
     r.docked=nil;r.pendingDock=nil;r.flight=G.flight.new();r.result=nil;return false
    elseif T.hasCarrier(parent)and same(parent,r.releasedParent)and now<(r.releaseUntil or 0)then
     a:K2_DetachFromActor(1,1,1);return false
    elseif T.hasCarrier(parent)then
     -- Native attachment can arrive before the custom dock snapshot. An older
     -- zero snapshot must not leave this attached aircraft simulating flight.
     r.docked=parent;r.pendingDock=nil
    elseif r.docked or r.pendingDock then
     restoreCollision(r);r.docked=nil;r.pendingDock=nil;r.flight=G.flight.new();r.result=nil
    end
   elseif T.hasCarrier(parent)then r.docked=parent;r.mass=r.mark.RelativeLocation.Z
   elseif r.docked then
    restoreCollision(r);r.docked=nil;r.flight=G.flight.new();r.result=nil
   end
  end
  if not r.netState and not valid(r.docked)and T.hasCarrier(parent)then r.docked=parent end
  if not valid(r.docked)and not r.pendingDock then r.freePhysics=a.VehicleMesh:IsSimulatingPhysics(none);return false end
  -- Disable bodies, suspension and independent movement BEFORE attaching or
  -- snapping. Recheck late native part updates while docked, not after 0.5 s.
  suspendCollision(r);r.settleAt=nil
  r.last=now;r.result={lift=0,thrust=0,drag=0,pitch=0,roll=0,yaw=0,authority=0,governor=0}
  G.inputs.apply(r);if G.simulates(a)then a:SetThrottleInput(0)end;r.telemetry=nil;r.flight.rpm=0;r.flight.propRPM=0;r.flight.collective=0
  r.visual.rotorSpin.RotationRate={Pitch=0,Yaw=0,Roll=0};r.visual.propellerSpin.RotationRate={Pitch=0,Yaw=0,Roll=0}
  if T.blades then r.flight.bladeMask=T.blades.mask(r);G.visuals.tick(r.visual,r.flight,0)end
  local motor=a.CarMotorV2.AttachedCarEquipableActor;if a:HasAuthority()and valid(motor)and motor.IsStart then motor:StopMotor()end
  if a.VehicleMesh:IsSimulatingPhysics(none)then a.VehicleMesh:SetSimulatePhysics(false)end
  if valid(r.docked)then
   if not same(a:GetAttachParentActor(),r.docked)then a:K2_AttachToActor(r.docked,none,2,2,2,false)end
   a:K2_SetActorRelativeLocation(vec(0,0,94),false,{},true)
   a:K2_SetActorRelativeRotation({Pitch=0,Yaw=0,Roll=0},false,{},true)
  end
  return true
 end
 function T.release(r)
  local a=r.actor;local t=r.docked
  if valid(t)then assert(stopped(t),'Stop the trailer first');assert(T.clear(a,t,false)and T.clear(a,t,true),'Clear the departure area first')end
  a:K2_DetachFromActor(1,1,1)
  if r.savedCollision then restoreCollision(r)else a:SetActorEnableCollision(true);parts(a,function(p)p:SetActorEnableCollision(true)end)end
  a.VehicleMesh:SetPhysicsLinearVelocity(vec(0,0,0),false,none);a.VehicleMesh:SetPhysicsAngularVelocityInDegrees(vec(0,0,0),false,none)
  r.docked=nil;r.pendingDock=nil;r.savedCollision=nil;r.flight=G.flight.new();r.result=nil
  local motor=a.CarMotorV2.AttachedCarEquipableActor;if valid(motor)then motor:StopMotor()end
  a:SetHandbrakeInput(true);a:ForceNetUpdate()
 end
 function T.dock(a,t)
  J.writable();T.checkDock(a,t);local id=assert(G.id(a));local tid=assert(T.id(t));local r=assert(G.tracked[a:GetFullName()])
  assert(not r.failed,'Aircraft controller needs attention')
  local list=T.blades and T.blades.planStow(a,t)or{}
  -- Copy native transforms before mutating attachment/physics ownership.
  local q,rot=a:K2_GetActorLocation(),a:K2_GetActorRotation()
  local pos=vec(q.X,q.Y,q.Z);local rotation={Pitch=rot.Pitch,Yaw=rot.Yaw,Roll=rot.Roll}
  local ok,e=pcall(function()
   T.bind(r,t)
   r.visual.rotorSpin.RotationRate={Pitch=0,Yaw=0,Roll=0};r.visual.propellerSpin.RotationRate={Pitch=0,Yaw=0,Roll=0}
   if T.blades then T.blades.stow(a,t,list)end
  end)
  if not ok then
   -- stow rolls its own original parts back; never clone/destroy inventory.
   a:K2_DetachFromActor(1,1,1);restoreCollision(r)
   a:K2_SetActorLocationAndRotation(pos,rotation,false,{},true)
   r.docked=nil;r.pendingDock=nil;r.flight=G.flight.new();r.result=nil;error(e)
  end
  J.state.dock[id]={tid};return 'Hornet snapped into place; blades stowed and engine off'
 end
 function T.undock(r)
  J.writable();local t=r.docked;local moved=T.blades.planUnstow(r.actor,t)
  -- Check departure clearance before touching either original blade.
  if valid(t)then assert(stopped(t),'Stop the trailer first');assert(T.clear(r.actor,t,false)and T.clear(r.actor,t,true),'Clear the departure area first')end
  T.blades.unstow(r.actor,moved,t)
  local ok,e=pcall(T.release,r)
  if not ok then if valid(t)then pcall(T.blades.stow,r.actor,t,moved)end;error(e)end
  J.state.dock[assert(G.id(r.actor))]=nil;return 'Hornet released; its blades refitted, rack free and engine off' 
 end
 function T.upgrade(t)
  assert(stopped(t),'Park the trailer first');assert(#t.AttachActorOn.ActorsAttached==0,'Unload the trailer before fitting the carrier deck')
  local at=mathlib:TransformLocation(t:GetTransform(),vec(-50,0,119));local hit={}
  assert(not sys:BoxTraceSingle(t,at,vec(at.X,at.Y,at.Z+.1),vec(240,125,24),t:K2_GetActorRotation(),0,false,ignored(t,t),0,hit,true,color,color,0),'Clear space around the trailer deck')
  J.writable();local id=assert(T.id(t),'Trailer parts still loading');T.deck(t);J.state.carrier[id]=true;J.state.ordinary[id]=nil;return 'Heli trailer landing pad fitted'
 end
 function T.scan(p,now)
  local host=p:HasAuthority();local gi=game:GetGameInstance(p)
  if host and not J.ready then J.load(gi.MainSaveGame)end
  local byId={}
  for _,t in ipairs(FindAllOf('Vehicle_Trailer_C')or{})do if valid(t)then
   local id=host and T.id(t)
   if host then T.classify(t,id,now)end
   if id and J.state.carrier[id]or marker(t)then local r=T.deck(t);if id then byId[id]=r end end
  end end
  for k,r in pairs(T.carriers)do if not valid(r.actor)then T.carriers[k]=nil end end
  if T.blades then T.blades.scan(host)end
  if host then
  for _,r in pairs(G.tracked)do if valid(r.actor)then
   local id=G.id(r.actor);local relation=id and J.state.dock[id]
   if relation then
    local carrier=byId[relation[1]]
    if carrier and same(r.docked,carrier.actor)and same(r.actor:GetAttachParentActor(),carrier.actor)then
     r.pendingSince=nil;r.restoreAfter=nil
    else
     -- Native streaming exposes the actor/part identities before its saved
     -- world transform has finished applying. Freeze briefly and let BOTH
     -- originals settle before deciding whether the link is truly distant.
     if not r.pendingSince then r.pendingSince=now;r.restoreAfter=now+5;r.pendingDock=true end
     if carrier and now>=r.restoreAfter and delta(r.actor:K2_GetActorLocation(),carrier.actor:K2_GetActorLocation())<650 then
      local ok,e=pcall(T.bind,r,carrier.actor)
      if ok then r.pendingSince=nil;r.restoreAfter=nil else log('Carrier rebind: '..tostring(e))end
     elseif now-r.pendingSince>20 then
      if r.pendingDock then T.release(r)end
      J.state.dock[id]=nil;r.pendingSince=nil;r.restoreAfter=nil
      log('Saved carrier unavailable or distant; original aircraft released in place')
     end
    end
   end
  end end
  end
  for _,c in pairs(T.carriers)do
   T.deckCollision(c)
   if valid(c.visual)then G.visuals.keepMaterial(c.visual,c.actor,true)end
   c.parked=T.stopped(c.actor)
   if host then c.actor.CarEquipableV2.CanBeRemoved=false end
   -- Aircraft and pad are weightless transport visuals. Keep the native
   -- trailer body/suspension/hitch balance; ordinary cargo remains native.
   if not c.massRestored then c.actor.VehicleMesh:SetMassOverrideInKg(none,c.baseMass,true);c.massRestored=true end
  end
 end
 function T.tick(p,now)
  if T.blades then T.blades.repairHeld(H.GetPlayerController())end
  if not T.ownerHook then
   local path='/VehicleSystemPlugin/AVS_Vehicle.AVS_Vehicle_C:OwnerChanged'
   if valid(StaticFindObject(path))then T.ownerHook={RegisterHook(path,function(ctx)
    if #ownerChanges<32 then ownerChanges[#ownerChanges+1]=ctx:get()end
   end)}end
  end
  local changes=ownerChanges;ownerChanges={}
  for _,a in ipairs(changes)do if valid(a)then local r=G.tracked[a:GetFullName()]
   if r and(valid(r.docked)or r.pendingDock)then
    r.dockOwnerChanged=true;r.syncSuspended=nil;suspendCollision(r);a.VehicleMesh:SetSimulatePhysics(false)
   end
  end end
  if T.sync then T.sync.tick(p,now)end
  if now>=T.nextScan then T.nextScan=now+.5;T.scan(p,now)end
  if T.controls then T.controls.tick(p,now)end
 end
 function T.reset()ownerChanges={};T.carriers={};T.aircraft={};T.pending={};T.seen={};T.nextScan=0;J.reset();if T.blades then T.blades.reset()end;if T.controls then T.controls.reset()end;if T.sync then T.sync.reset()end end
 T.same=same;T.stopped=stopped;T.distance=delta;T.parts=parts;T.marker=marker;T.game=game;T.math=mathlib;T.sys=sys
 T.blades=dofile(root..'/Scripts/gyrocopter/blades.lua')(M,G,T,root,valid,log)
 T.sync=dofile(root..'/Scripts/gyrocopter/sync.lua')(M,G,T,H,valid,log)
 T.controls=dofile(root..'/Scripts/gyrocopter/transport_controls.lua')(M,G,T,H,valid,log)
 return T
end

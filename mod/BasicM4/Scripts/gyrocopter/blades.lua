-- Existing native removable part actors retain their original GUID, wear,
-- inventory data and save handlers. No destroy/recreate operation is used here.
return function(M,G,T,root,valid,log)
 local B={items={}};local J=T.journal;local none=FName('None')
 local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local scene=StaticFindObject('/Script/Engine.SceneComponent')
 local boxClass=StaticFindObject('/Script/Engine.BoxComponent')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local color={R=0,G=0,B=0,A=1};local slots={'CarLightsV3_HL','CarLightsV3_HL1'}
 local function vec(x,y,z)return {X=x,Y=y,Z=z}end
 function B.slot(a,i)return a[slots[i]]end
 local function marker(p)
  for _,v in ipairs(p:K2_GetComponentsByClass(scene))do local c=v:get();local i=valid(c)and c.AttachSocketName:ToString():match('^BA_HornetBlade_([12])$');if i then return c,tonumber(i)end end
 end
 function B.info(p)
  if not valid(p)then return end
  if not valid(B.lightClass)then B.lightClass=FindObject('BlueprintGeneratedClass','CarItemLightV2_C')end
  if not valid(B.lightClass)or not p:IsA(B.lightClass)then return end
  local r=B.items[p:GetFullName()];if r then return r.side,r.owner end
  if p:HasAuthority()then local id=M.guid(p);local d=id and J.state.blade[id];if d then return d[2],d[1]end end
  local _,side=marker(p);return side
 end
 function B.skin(p,side,owner)
  local key=p:GetFullName();local r=B.items[key]
  if not r then
   local m=marker(p)
   if not m and p:HasAuthority()then
    m=p:AddComponentByClass(scene,true,identity,false);assert(valid(m));m:SetVisibility(false,false)
    m:K2_AttachToComponent(p.RootComponent,FName('BA_HornetBlade_'..side),0,0,0,false);m:SetIsReplicated(true);p:ForceNetUpdate()
   end
   local c=p:AddComponentByClass(pmc,true,identity,false);assert(valid(c));c:K2_AttachToComponent(p.RootMeshComponent,none,0,0,0,false)
   -- Loose native parts simulate their mesh separately from DefaultSceneRoot.
   -- Follow that same mesh so the visible blade and native pickup shape agree.
   c:SetAbsolute(false,false,true);c:SetIsReplicated(false);G.visuals.item(c,side,p)
   G.visuals.prune(p,{c},false)
   r={actor=p,visual=c,side=side,owner=owner};B.items[key]=r
  end
  if r.side~=side then G.visuals.item(r.visual,side,p);r.side=side end
  if owner then r.owner=owner end
  if not r.setup then
   p.BeamIntensity=0;p.HighBeamIntensity=0;p.LightConsumption=0;p:SetAllLightsOff()
   p.CanBeDettachedOnImpact=false;p.CollisionWhenAttached=1
   -- Native root remains the simulated pickup; an elongated cube supplies a
   -- lightweight convex collision shape. Imported visual uses absolute scale.
   local cube=LoadAsset('/Engine/BasicShapes/Cube.Cube');p.RootMeshComponent:SetStaticMesh(cube)
   p.RootMeshComponent:SetMassOverrideInKg(none,8,true);r.setup=true;r.regrab=true
  end
  local fitted=valid(p.ParentCarEquipableV2)
  if not fitted then r.mount=nil end
  p:SetActorHiddenInGame(false);p.RootMeshComponent:SetVisibility(false,false)
  for _,v in ipairs(p:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.StaticMeshComponent')))do v:get():SetVisibility(false,false)end
  p:SetAllLightsOff()
  r.visual:SetVisibility(not fitted,false)
  if not p:HasAuthority()and r.netFitted~=nil then r.visual:SetVisibility(not r.netFitted,false)end
  p.RootMeshComponent:SetRelativeScale3D(fitted and vec(1,1,1)or vec(3.184,.21,.14))
  if fitted then p.RootMeshComponent:SetCollisionEnabled(0)end
  -- Query-only pickup assistance follows the full blade, independent of the
  -- narrow native physics cube. Reuse its native collision profile so no
  -- global trace/input rules or unrelated item interactions are replaced.
  if not valid(r.aim)then
   r.aim=p:AddComponentByClass(boxClass,true,identity,false);assert(valid(r.aim),'Blade pickup query unavailable')
   r.aim:K2_AttachToComponent(p.RootMeshComponent,FName('BA_HornetBlade_Aim'),0,0,0,false)
   r.aim:SetAbsolute(false,false,true);r.aim:SetIsReplicated(false);r.aim:SetGenerateOverlapEvents(false)
   r.aim:SetCollisionProfileName(p.RootMeshComponent:GetCollisionProfileName(),false)
   -- Character/vehicle movement sweeps must keep the original physical body.
   for _,channel in ipairs({0,1,2,5,6,7})do r.aim:SetCollisionResponseToChannel(channel,0)end
   r.aim:SetBoxExtent(vec(159.2,20,16),false)
  end
  local ground={};p:CanBePickedUpFromGround(ground)
  local held=valid(p.PhysicsHandle)and valid(p.PhysicsHandle:GetGrabbedComponent())
  r.aim:SetCollisionEnabled(not fitted and not held and not valid(p:GetAttachParentActor())and ground.Can and 1 or 0)
  return r
 end
 -- Collision-body recreation completes after the native pickup callback.
 function B.repairHeld(pc)
  if not valid(pc)or not pc:IsLocalPlayerController()then return end
  local p=M.backpack.native.held(pc);local r=valid(p)and B.items[p:GetFullName()]
  if not r or not r.regrab or valid(p.ParentCarEquipableV2)then return end
  local now=os.clock();if not r.grabAt then r.grabAt=now+.05;return end
  if now<r.grabAt then return end;r.grabAt=now+.1
  local mesh=p.RootMeshComponent;local handle=p.PhysicsHandle
  if not valid(handle)or not valid(mesh)then return end
  local grabbed=handle:GetGrabbedComponent()
  if not T.same(grabbed,mesh)then p:OnRepIsHandleInHand(true,true);grabbed=handle:GetGrabbedComponent()end
  if T.same(grabbed,mesh)then r.regrab=nil;r.grabAt=nil end
 end
 -- Apply the host's rack state to the native pickup mesh as well as its
 -- rendering. A client must never simulate a blade secured by the host.
 function B.syncRack(r)
  local p=r.actor;if p:HasAuthority()or r.netRack==nil then return end
  local mesh=p.RootMeshComponent;if not valid(mesh)then return end
  local t=r.netCarrier
  if r.netRack>0 then
   r.rackControlled=true
   mesh:SetSimulatePhysics(false);mesh:SetCollisionEnabled(valid(t)and 1 or 0)
   if not valid(t)or not valid(t.VehicleMesh)then r.visual:SetVisibility(false,false);return end
   if not T.same(mesh:GetAttachParent(),t.VehicleMesh)then mesh:K2_AttachToComponent(t.VehicleMesh,none,0,0,0,false)end
   local q=mesh.RelativeLocation;local y=r.side==1 and 130 or 156
   if math.abs(q.X+50)>.01 or math.abs(q.Y-y)>.01 or math.abs(q.Z-142)>.01 then mesh:K2_SetRelativeLocation(vec(-50,y,142),false,{},true)end
   local rot=mesh.RelativeRotation
   if math.abs(rot.Pitch)+math.abs(rot.Yaw)+math.abs(rot.Roll)>.01 then mesh:K2_SetRelativeRotation({Pitch=0,Yaw=0,Roll=0},false,{},true)end
   mesh:SetRelativeScale3D(vec(3.184,.21,.14));r.visual:SetVisibility(true,false);r.clientRack=t
  elseif r.rackControlled then
   -- A fitted snapshot can beat the native mount reference. Hold the mesh
   -- without physics until that reference arrives; do not drop it for a frame.
   if r.netFitted then
    mesh:SetSimulatePhysics(false);mesh:SetCollisionEnabled(0);r.visual:SetVisibility(false,false)
    if not valid(p.ParentCarEquipableV2)then return end
    if valid(r.clientRack)and T.same(mesh:GetAttachParent(),r.clientRack.VehicleMesh)then p:OnRepParentCarEquipableV2(false)end
   else
    if valid(r.clientRack)and T.same(mesh:GetAttachParent(),r.clientRack.VehicleMesh)then mesh:K2_DetachFromComponent(1,1,1,false)end
    -- Restore through the native replicated physics policy, never force a
    -- held/fitted part into simulation based on an old local cached flag.
    p:OnRepIsPhysicsSimulate()
   end
   r.rackControlled=nil;r.clientRack=nil
  end
 end
 function B.mask(r)
  local a=r.actor
  if not a:HasAuthority()then
   if r.netState then return r.netState.mask end
   local p=r.mark.RelativeLocation;return p.Y==1 and math.max(0,math.min(3,math.floor(p.X+.5)))or 0
  end
  local id=G.id(a);if not id or not J.state.issued[id]then return r.newAirframe and 0 or 3 end
  local mask=0
  for i=1,2 do local p=B.slot(a,i).AttachedCarEquipableActor
   if valid(p)then local d=J.state.blade[M.guid(p)];if d and d[2]==i and d[1]==id then mask=mask|(1<<(i-1))end end
  end
  local mass=valid(r.docked)and(r.mass or a.VehicleMesh:GetMass())or a.VehicleMesh:GetMass()
  local p=r.mark.RelativeLocation;if p.X~=mask or p.Y~=1 or math.abs(p.Z-mass)>.1 then r.mark:K2_SetRelativeLocation(vec(mask,1,mass),false,{},true);a:FlushNetDormancy();a:ForceNetUpdate()end
  return mask
 end
 function B.parked(a)
  local r=assert(G.tracked[a:GetFullName()],'Not a Hornet')
  if not a:HasAuthority()then assert(r.netState and r.netState.parked,'Waiting for host parked state');return end
  assert(T.stopped(a)and r.flight.rpm<5,'Land and stop the rotor before handling blades')
  if valid(r.docked)then assert(T.stopped(r.docked),'Stop the trailer first');return end
  local contact=false
  a.Wheels:ForEach(function(_,v)local w=v:get();if valid(w)and w:GetIsSimulatingSuspension()and w:GetHasContact()then contact=true end end)
  if contact then return end
  local q=a:K2_GetActorLocation();local ignore={a};T.parts(a,function(p)ignore[#ignore+1]=p end)
  local hit={};assert(T.sys:LineTraceSingle(a,vec(q.X,q.Y,q.Z+25),vec(q.X,q.Y,q.Z-15),0,false,ignore,0,hit,true,color,color,0),'Land before handling blades')
 end
 function B.positions(a)
  local positions={};local q=a:K2_GetActorLocation();local ignore={a};T.parts(a,function(p)ignore[#ignore+1]=p end)
  for i=1,2 do for _,offset in ipairs({500,650,800})do
   local at=T.math:TransformLocation(a:GetTransform(),vec(0,(i==1 and -1 or 1)*offset,0));local hit={}
   if T.sys:LineTraceSingle(a,vec(at.X,at.Y,q.Z+150),vec(at.X,at.Y,q.Z-250),0,false,ignore,0,hit,true,color,color,0)and hit.ImpactNormal.Z>.94 then
    local p=hit.ImpactPoint;local pos=vec(p.X,p.Y,p.Z+40);local blocked={}
    if not T.sys:BoxTraceSingle(a,pos,vec(pos.X,pos.Y,pos.Z+.1),vec(164,13,12),{Pitch=0,Yaw=a:K2_GetActorRotation().Yaw,Roll=0},0,false,ignore,0,blocked,true,color,color,0)then positions[i]=pos;break end
   end
  end;assert(positions[i],'Clear level ground beside the aircraft for its blades')end
  return positions
 end
 local function refit(p,a,side)
  local c=B.slot(a,side);assert(not valid(c.AttachedCarEquipableActor),'Blade mount occupied')
  p.CollisionWhenAttached=1;p.RootMeshComponent:SetCollisionEnabled(1);p.RootMeshComponent:SetSimulatePhysics(false)
  c.ShouldUpdateChildCollision=false
  c.AttachedCarEquipableActor=p;p.ParentCarEquipableV2=c;c:OnRepAttachedCarEquipableActor();p:OnRepParentCarEquipableV2(true)
  assert(T.same(c.AttachedCarEquipableActor,p),'Native blade fitting failed');T.guardPart(p);p:ForceNetUpdate();a:ForceNetUpdate()
 end
 function B.seed(r)
  local a=r.actor;local id=G.id(a);if not id or J.state.issued[id]then return end
  local p={B.slot(a,1).AttachedCarEquipableActor,B.slot(a,2).AttachedCarEquipableActor}
  if not valid(p[1])or not valid(p[2])then return end
  local ids={M.guid(p[1]),M.guid(p[2])};if not ids[1]or not ids[2]then return end
  J.writable();local positions=r.newAirframe and B.positions(a)
  for i=1,2 do J.state.blade[ids[i]]={id,i};B.skin(p[i],i,id)end
  J.state.issued[id]=true
  if positions then
   local ok,e=pcall(function()for i=1,2 do B.slot(a,i):DettachAttachedCarEquipableActor(true);p[i]:K2_SetActorLocationAndRotation(positions[i],{Pitch=0,Yaw=a:K2_GetActorRotation().Yaw,Roll=0},false,{},true);B.skin(p[i],i,id)end end)
   if not ok then for i=1,2 do if not valid(B.slot(a,i).AttachedCarEquipableActor)then pcall(refit,p[i],a,i)end end;log('Blade placement left original parts recoverable: '..tostring(e))end
  end
  if positions and r.worldSpawn then
   local roll=0;for i=1,#id do roll=(roll*33+id:byte(i))%100 end
   local keep=roll<25 and 0 or roll<80 and 1 or 2
   for i=keep+1,2 do
    -- Only dispose of the newly issued, loose parts from this spawn transaction.
    if valid(p[i])and not valid(p[i].ParentCarEquipableV2)then J.state.blade[ids[i]]=nil;B.items[p[i]:GetFullName()]=nil;p[i]:K2_DestroyActor()end
   end
  end
  r.newAirframe=nil;r.worldSpawn=nil;B.mask(r)
 end
 function B.assign(p,a,side)
  assert(side==1 or side==2,'Invalid blade mount');local id=assert(M.guid(p));local owner=assert(G.id(a))
  J.state.blade[id]={owner,side}
  local r=B.items[p:GetFullName()]
  if r then
   if r.side~=side then G.visuals.item(r.visual,side,p)end
   r.side=side;r.owner=owner
  end
  local m=marker(p)
  if valid(m)and m.AttachSocketName:ToString()~='BA_HornetBlade_'..side then m:K2_AttachToComponent(p.RootComponent,FName('BA_HornetBlade_'..side),0,0,0,false);p:ForceNetUpdate()end
 end
 function B.fit(pc,p,a,requestedSide)
  J.writable();B.parked(a);local side,owner=B.info(p);assert(side,'Not a rotor blade');side=requestedSide or(not valid(B.slot(a,side).AttachedCarEquipableActor)and side or 3-side)
  assert(not valid(p.ParentCarEquipableV2),'Blade is already installed');assert(not valid(B.slot(a,side).AttachedCarEquipableActor),'Blade mount occupied')
  local held=M.backpack.native.held(pc);assert(T.same(held,p)or T.distance(p:K2_GetActorLocation(),pc.PlayerControlled:K2_GetActorLocation())<240,'Blade out of reach')
  local rack=J.state.rack[M.guid(p)];if rack then B.unrack(p)end
  if T.same(held,p)then pc:RemoveItemInHand()end
  refit(p,a,side);if G.service then G.service.consume(pc,p)end;B.assign(p,a,side);B.skin(p,side,G.id(a));B.mask(G.tracked[a:GetFullName()]);return 'Main blade '..side..' installed'
 end
 function B.remove(a,side)
  J.writable();B.parked(a);local p=B.slot(a,side).AttachedCarEquipableActor;assert(valid(p)and B.info(p),'No main blade in this mount')
  local positions=B.positions(a);B.slot(a,side):DettachAttachedCarEquipableActor(true);p:K2_SetActorLocationAndRotation(positions[side],{Pitch=0,Yaw=a:K2_GetActorRotation().Yaw,Roll=0},false,{},true)
  local _,owner=B.info(p);B.skin(p,side,owner);B.mask(G.tracked[a:GetFullName()]);return 'Main blade '..side..' placed beside the aircraft'
 end
 local function cargo(p,t,side)
  local rel={Translation=vec(-50,side==1 and 130 or 156,142),Rotation={X=0,Y=0,Z=0,W=1},Scale3D=vec(1,1,1)}
  return {Actor_2_62DE748F44B7CBBBDC5471B53B1803CE=p,ComponentAttached_5_7C2F01C7441B2324C8960C81A55FBB68=t.VehicleMesh,Transform_8_1B293402457C5FD5DE77DDB72871997D=rel,WithDynamicCollision_12_2A2A3C1A45A9ED58C33B828184D63966=false,IsBourred_14_BBC6E510483E36BF7F274CBFA8767DAF=false,KeepTick_16_B3DDBA4B4F681AD92A644C9C82429BA8=true,IsAttachable_19_BD0D858D48CDF86C40F5529D1B2C8B1C=true}
 end
 function B.rackFree(t,side,except,aircraft,reserved)
  for id,r in pairs(J.state.rack)do if r[1]==T.id(t)and r[2]==side and id~=except then return false end end
  if reserved then return true end -- geometry was checked before snapping the airframe
  local at=T.math:TransformLocation(t:GetTransform(),vec(-50,side==1 and 130 or 156,142));local hit={};local ignored={t}
  T.parts(t,function(p)ignored[#ignored+1]=p end)
  if valid(aircraft)then ignored[#ignored+1]=aircraft;T.parts(aircraft,function(p)ignored[#ignored+1]=p end);if valid(aircraft.Driver)then ignored[#ignored+1]=aircraft.Driver end;if valid(aircraft.CarCollisionProxy)then ignored[#ignored+1]=aircraft.CarCollisionProxy end end
  if except then for _,r in pairs(B.items)do if valid(r.actor)and M.guid(r.actor)==except then ignored[#ignored+1]=r.actor end end end
  return not T.sys:BoxTraceSingle(t,at,vec(at.X,at.Y,at.Z+.1),vec(164,12,10),t:K2_GetActorRotation(),0,false,ignored,0,hit,true,color,color,0)
 end
 function B.rack(pc,p,t,docking,reserved)
  J.writable();assert(docking or T.stopped(t),'Stop the trailer');local side,owner=B.info(p);assert(side,'Not a Hornet blade');local id=assert(M.guid(p))
  assert(B.rackFree(t,side,id,docking,reserved),'Blade rack position is occupied');assert(not valid(p.ParentCarEquipableV2),'Remove the blade from the aircraft first')
  if pc and T.same(M.backpack.native.held(pc),p)then pc:RemoveItemInHand()end
  t.AttachActorOn:AttachActorOn(cargo(p,t,side),false)
  assert(T.same(p:GetAttachParentActor(),t),'Native rack attachment refused')
  J.state.rack[id]={T.id(t),side};B.skin(p,side,owner);p:ForceNetUpdate();t:ForceNetUpdate();return 'Main blade secured in rack'
 end
 function B.unrack(p,docking)
  J.writable();local id=assert(M.guid(p));assert(J.state.rack[id],'Blade is not racked')
  local t=p:GetAttachParentActor();assert(T.hasCarrier(t)and(docking or T.stopped(t)),'Stop the carrier first')
  t.AttachActorOn:RemoveAttachActorOn(p);p.AttachActorOn:RemoveParentActorOn();assert(not valid(p:GetAttachParentActor()),'Native rack release refused')
  J.state.rack[id]=nil;p:ForceNetUpdate();t:ForceNetUpdate();return 'Blade released; pick it up normally'
 end
 function B.planStow(a,t)
  local list={};for i=1,2 do local p=B.slot(a,i).AttachedCarEquipableActor
   if valid(p)then assert(B.info(p),'Unknown part in blade mount');assert(B.rackFree(t,i,M.guid(p),a),'Clear both blade rack positions');list[#list+1]={p,i}end
  end
  return list
 end
 function B.stow(a,t,list)
  list=list or B.planStow(a,t)
  local moved={};local ok,e=pcall(function()for _,v in ipairs(list)do B.slot(a,v[2]):DettachAttachedCarEquipableActor(true);moved[#moved+1]=v;B.rack(nil,v[1],t,a,true)end end)
  if not ok then for _,v in ipairs(moved)do pcall(function()if J.state.rack[M.guid(v[1])]then B.unrack(v[1],a)end;refit(v[1],a,v[2])end)end;error(e)end
  return moved
 end
 function B.planUnstow(a,t)
  local list={};if not valid(t)then return list end
  local owner,tid=G.id(a),T.id(t)
  for id,rack in pairs(J.state.rack)do
   local info=J.state.blade[id]
   if rack[1]==tid and info and info[1]==owner then
    local found;for _,r in pairs(B.items)do if valid(r.actor)and M.guid(r.actor)==id then found=r.actor;break end end
    assert(valid(found),"Wait for this helicopter's racked blades to synchronize")
    assert(not valid(B.slot(a,info[2]).AttachedCarEquipableActor),"Remove the extra blade from this helicopter's mount first")
    assert(T.same(found:GetAttachParentActor(),t),'Wait for the blade rack attachment to synchronize')
    list[#list+1]={found,info[2]}
   end
  end
  return list
 end
 function B.unstow(a,moved,t)
  local done={};local ok,e=pcall(function()
   for _,v in ipairs(moved)do
    B.unrack(v[1],a);done[#done+1]=v;refit(v[1],a,v[2]);B.skin(v[1],v[2],G.id(a))
   end
  end)
  if not ok then
   for _,v in ipairs(done)do pcall(function()
    if valid(v[1].ParentCarEquipableV2)then B.slot(a,v[2]):DettachAttachedCarEquipableActor(true)end
    B.rack(nil,v[1],t,a,true)
   end)end
   error(e)
  end
  B.mask(G.tracked[a:GetFullName()]);return done
 end
 local function migrateRack(r,t)
  if r.rackChecked==t:GetAddress()or not T.stopped(t)then return end
  local now=T.game:GetTimeSeconds(t);r.rackCheckAt=r.rackCheckAt or now+5;if now<r.rackCheckAt then return end
  local p=r.actor;local at=T.math:InverseTransformLocation(t:GetTransform(),p.RootMeshComponent:K2_GetComponentLocation())
  if math.abs(math.abs(at.Y)-112)<5 and math.abs(at.X+50)<5 then
   -- Move the same saved actor through the native cargo API, updating its
   -- persisted/replicated relative transform as well as the visible position.
   J.writable();t.AttachActorOn:RemoveAttachActorOn(p);p.AttachActorOn:RemoveParentActorOn()
   t.AttachActorOn:AttachActorOn(cargo(p,t,r.side),false);p:ForceNetUpdate();t:ForceNetUpdate()
  end
  r.rackChecked=t:GetAddress()
 end
 function B.scan(host)
  if host then for _,r in pairs(G.tracked)do if valid(r.actor)then
   local ok,e=pcall(B.seed,r);if not ok and r.bladeError~=tostring(e)then r.bladeError=tostring(e);log('Blade initialization: '..r.bladeError)end
   B.mask(r)
  end end end
  for _,p in ipairs(FindAllOf('CarItemLightV2_C')or{})do if valid(p)then local side,owner=B.info(p);if side then B.skin(p,side,owner)end end end
  for key,r in pairs(B.items)do if not valid(r.actor)then B.items[key]=nil
   elseif host then local id=M.guid(r.actor);local rack=id and J.state.rack[id]
    if rack then
     if T.hasCarrier(r.actor:GetAttachParentActor())then r.looseSince=nil;migrateRack(r,r.actor:GetAttachParentActor())
     else local now=T.game:GetTimeSeconds(r.actor);r.looseSince=r.looseSince or now;if now-r.looseSince>10 then J.state.rack[id]=nil;r.looseSince=nil end end
    end
   else B.syncRack(r)end end
  B.mounts.update()
 end
 function B.reset()for _,r in pairs(B.items)do if valid(r.aim)then r.aim:K2_DestroyComponent(r.actor)end end;B.items={};B.mounts.reset()end
 B.mounts=dofile(root..'/Scripts/gyrocopter/blade_mounts.lua')(M,G,T,B,valid,log)
 B.refit=refit;return B
end

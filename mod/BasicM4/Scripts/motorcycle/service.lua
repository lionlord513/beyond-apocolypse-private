return function(M,B,valid,log)
 local S={parts={},slots={},mounts={},meshes={},pending={},nextAt=0};local lib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
 -- Retain the classic bay's length/height, fitting width independently. The
 -- thin service panels sit on opposite sides, clear of the engine and frame.
 local defs={CarMotorV2={class='CarItemMotor',at={X=-3,Y=0,Z=-1},size={X=54,Y=24,Z=38},axisFit=true,rotation={Pitch=90,Yaw=0,Roll=0}},CarBatteryV2={class='CarItemBattery',at={X=-16,Y=-17,Z=-12},size={X=22,Y=4,Z=16},axisFit=true,rotation={Pitch=0,Yaw=0,Roll=0}},CarRadiatorV2={class='CarItemTankRadiator',at={X=-3,Y=17,Z=-1},size={X=30,Y=4,Z=28},axisFit=true,rotation={Pitch=0,Yaw=90,Roll=0}}}
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function restore(saved)
  if valid(saved.mesh)then saved.mesh:SetRelativeScale3D(saved.scale);S.meshes[saved.mesh:GetAddress()]=nil end
  if valid(saved.root)then S.meshes[saved.root:GetAddress()]=nil end
  if valid(saved.actor)and saved.collision~=nil then saved.actor.CollisionWhenAttached=saved.collision;saved.actor.CanBeDettachedOnImpact=saved.impact end
  S.parts[saved.key]=nil
 end
 function S.align(r,name,d)
  local c=r.actor[name];local p=c.AttachedCarEquipableActor
  if not valid(p)or not same(p.ParentCarEquipableV2,c)or not valid(p.RootMeshComponent)then return end
  local mesh=p.RootMeshComponent;local key=p:GetAddress();local saved=S.parts[key]
  if saved and not same(saved.slot,c)then restore(saved);saved=nil end
  -- The replicated slot reference can arrive before native component parenting.
  -- Never measure a held/world-space pose or move the mount to follow it.
  local root=p.RootComponent
  if not valid(root)or not same(root:GetAttachParent(),c)then return end
  local linked=mesh
  for _=1,8 do if same(linked,root)then break end;linked=valid(linked)and linked:GetAttachParent()end
  if not same(linked,root)then return end
  if not saved then local s=mesh.RelativeScale3D;saved={key=key,actor=p,mesh=mesh,root=root,scale={X=s.X,Y=s.Y,Z=s.Z},slot=c,collision=p.CollisionWhenAttached,impact=p.CanBeDettachedOnImpact};S.parts[key]=saved;S.meshes[mesh:GetAddress()]=p;S.meshes[root:GetAddress()]=p
   -- The compact service bay is queryable for tools/ports, but attached parts
   -- must not become extra rigid bodies colliding with the frame or rider.
   p.CollisionWhenAttached=1;p.CanBeDettachedOnImpact=false
   mesh:SetSimulatePhysics(false);mesh:SetCollisionEnabled(1)
  end
  -- Native actors, service sockets, GUID and wear remain intact. Scale only while fitted.
  local rot=c.RelativeRotation
  d.quaternion=d.quaternion or lib:Conv_RotatorToQuaternion(d.rotation)
  local q=lib:Conv_RotatorToQuaternion(rot);local t=d.quaternion
  if math.abs(q.X*t.X+q.Y*t.Y+q.Z*t.Z+q.W*t.W)<.999999 then c:K2_SetRelativeRotation(d.rotation,false,{},true)end
  local mr,rr,rs=mesh.RelativeRotation,root.RelativeRotation,root.RelativeScale3D
  local orientation=('%.5f:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f'):format(mr.Pitch,mr.Yaw,mr.Roll,rr.Pitch,rr.Yaw,rr.Roll,rs.X,rs.Y,rs.Z)
  if saved.orientation~=orientation then saved.fit=nil;saved.orientation=orientation end
  local lo,hi={},{};mesh:GetLocalBounds(lo,hi)
  -- Measure once per fitted part; repeatedly restoring unit scale wakes native
  -- attached collision and can flash a full-size engine into the rider.
  if not saved.fit then
  local frame,world=r.frame:K2_GetComponentToWorld(),mesh:K2_GetComponentToWorld()
  local current=mesh.RelativeScale3D
  if math.abs(current.X)<.0001 or math.abs(current.Y)<.0001 or math.abs(current.Z)<.0001 then return end
  -- GetLocalBounds is unscaled. Remove only the mesh's current relative scale
  -- from its transform; never expose a full-size fitted engine for measurement.
  local unitWorld={Translation=world.Translation,Rotation=world.Rotation,Scale3D={X=world.Scale3D.X/current.X,Y=world.Scale3D.Y/current.Y,Z=world.Scale3D.Z/current.Z}}
  local min,max={X=math.huge,Y=math.huge,Z=math.huge},{X=-math.huge,Y=-math.huge,Z=-math.huge}
  for _,x in ipairs({lo.X,hi.X})do for _,y in ipairs({lo.Y,hi.Y})do for _,z in ipairs({lo.Z,hi.Z})do
   local q=lib:InverseTransformLocation(frame,lib:TransformLocation(unitWorld,{X=x,Y=y,Z=z}))
   for _,axis in ipairs({'X','Y','Z'})do min[axis]=math.min(min[axis],q[axis]);max[axis]=math.max(max[axis],q[axis])end
  end end end
  local scale=math.min(.8,d.size.X/math.max(max.X-min.X,1),d.size.Y/math.max(max.Y-min.Y,1),d.size.Z/math.max(max.Z-min.Z,1))
  if d.axisFit then
   -- Resolve each mesh axis into the bike frame before choosing its scale.
   -- Engine length/height can fill the bay without enlarging its width.
   local origin=lib:InverseTransformLocation(frame,lib:TransformLocation(unitWorld,{X=0,Y=0,Z=0}))
   local fit,contribution={},{}
   for _,axis in ipairs({'X','Y','Z'})do
    local basis={X=0,Y=0,Z=0};basis[axis]=1
    local q=lib:InverseTransformLocation(frame,lib:TransformLocation(unitWorld,basis))
    local dominant='X';for _,k in ipairs({'Y','Z'})do if math.abs(q[k]-origin[k])>math.abs(q[dominant]-origin[dominant])then dominant=k end end
    fit[axis]=math.min(.8,d.size[dominant]/math.max(max[dominant]-min[dominant],1));contribution[axis]={}
    for _,k in ipairs({'X','Y','Z'})do contribution[axis][k]=math.abs(q[k]-origin[k])*(hi[axis]-lo[axis])end
   end
   -- Non-cardinal native mesh rotations must still respect leg/bay clearance.
   for _,k in ipairs({'X','Y','Z'})do
    local span=0;for _,axis in ipairs({'X','Y','Z'})do span=span+contribution[axis][k]*fit[axis]end
    if span>d.size[k]then for _,axis in ipairs({'X','Y','Z'})do if contribution[axis][k]>.0001 then fit[axis]=fit[axis]*d.size[k]/span end end end
   end
   saved.fit=fit
  else saved.fit=scale end
  end
  local scale=saved.fit;local fit=type(scale)=='table'and scale or {X=scale,Y=scale,Z=scale};local current=mesh.RelativeScale3D
  if math.abs(current.X-fit.X)+math.abs(current.Y-fit.Y)+math.abs(current.Z-fit.Z)>.0001 then mesh:SetRelativeScale3D(fit)end
  local center={X=(lo.X+hi.X)/2,Y=(lo.Y+hi.Y)/2,Z=(lo.Z+hi.Z)/2}
  local q=lib:InverseTransformLocation(r.frame:K2_GetComponentToWorld(),lib:TransformLocation(mesh:K2_GetComponentToWorld(),center))
  local at=c.RelativeLocation
  if math.abs(q.X-d.at.X)+math.abs(q.Y-d.at.Y)+math.abs(q.Z-d.at.Z)>.05 then c:K2_SetRelativeLocation({X=at.X+d.at.X-q.X,Y=at.Y+d.at.Y-q.Y,Z=at.Z+d.at.Z-q.Z},false,{},true)end
  p:SetActorHiddenInGame(false)
 end
 function S.changed(p)
  if S.busy or not valid(p)then return end
  S.busy=true
  local ok,e=pcall(function()
   local saved=S.parts[p:GetAddress()]
   if saved and not same(p.ParentCarEquipableV2,saved.slot)then restore(saved)end
   local c=p.ParentCarEquipableV2;local m=valid(c)and S.mounts[c:GetAddress()]
   if m and same(c.AttachedCarEquipableActor,p)then S.align(m.r,m.name,m.d)end
  end)
  S.busy=false;if not ok then log('Motorcycle fitting: '..tostring(e))end
 end
 local function changedComponent(ctx)
  local c=ctx:get();if not valid(c)then return end
  local p=S.meshes[c:GetAddress()];local m=S.mounts[c:GetAddress()]
  if p then S.changed(p)elseif m then S.changed(c.AttachedCarEquipableActor)end
 end
 local function installFitHooks()
  if S.fitHooks then return end
  local base='/Game/BP/CarsV2/System/Actors/Master/CarItemEquipableActor.CarItemEquipableActor_C:'
  if not valid(StaticFindObject(base..'OnRepParentCarEquipableV2'))then return end
  S.fitHooks={}
  -- Blueprint callbacks run after native fitting. Native /Script hooks require
  -- their explicit post callback so replicated transforms finish first.
  for _,event in ipairs({'OnRepParentCarEquipableV2','UpdateOffsetTransform'})do
   S.fitHooks[#S.fitHooks+1]={RegisterHook(base..event,function(ctx)S.changed(ctx:get())end)}
  end
  local postActor=function(ctx)local p=ctx:get();if valid(p)and S.parts[p:GetAddress()]then S.changed(p)end end
  S.fitHooks[#S.fitHooks+1]={RegisterHook('/Script/Engine.Actor:OnRep_AttachmentReplication',function()end,postActor)}
  S.fitHooks[#S.fitHooks+1]={RegisterHook('/Script/Engine.SceneComponent:OnRep_Transform',function()end,changedComponent)}
 end
 local function eligible(slot,item)
  local d=S.slots[slot:GetAddress()];if not d or not valid(item)then return end
  local cls=StaticFindObject('/Game/BP/CarsV2/System/Actors/Master/'..d.class..'.'..d.class..'_C')
  return valid(cls)and item:IsA(cls)
 end
 -- Native ExecutePrimaryAction owns attachment/removal. Processing a held item
 -- after that action can mistake a freshly removed engine for a new installation.
 local function consume(q)
  local c,p=q.slot,q.part
  if not valid(c)or not S.slots[c:GetAddress()]or not valid(p)then return end
  if same(c.AttachedCarEquipableActor,p)and same(p.ParentCarEquipableV2,c)then
   for _,r in pairs(B.tracked)do if valid(r.actor)then for name,d in pairs(r.config and r.config.service or defs)do
    if same(r.actor[name],c)then S.align(r,name,d)end
   end end end
   M.gyrocopter.service.consume(q.owner,p)
  end
 end
 function S.tick(now)
  installFitHooks()
  if not S.hooks then
   local base='/Game/BP/CarsV2/System/Components/CarEquipableV2.CarEquipableV2_C:'
   if valid(StaticFindObject(base..'CanBePutInside'))then
    S.hooks={}
    S.hooks[1]={RegisterHook(base..'CanBePutInside',function(ctx,item,out)
     local c=ctx:get();if eligible(c,item:get())then local a=c:GetOwner();local v=a:GetVelocity();out:set(not valid(c.AttachedCarEquipableActor)and not valid(a.Driver)and v.X*v.X+v.Y*v.Y+v.Z*v.Z<50^2)end
    end)}
    S.hooks[2]={RegisterHook(base..'ExecutePrimaryAction',function(ctx,pressed,pc,component,item)
     if pressed:get()and #S.pending<32 then S.pending[#S.pending+1]={slot=ctx:get(),owner=pc:get(),part=item:get()}end
    end)}
   end
  end
  local pending=S.pending;S.pending={}
  for _,q in ipairs(pending)do local ok,e=pcall(consume,q);if not ok then log("Motorcycle service: "..tostring(e))end end
  if now<S.nextAt then return end;S.nextAt=now+.25
  for key,s in pairs(S.parts)do
   if not valid(s.actor)then S.parts[key]=nil;if valid(s.mesh)then S.meshes[s.mesh:GetAddress()]=nil end;if valid(s.root)then S.meshes[s.root:GetAddress()]=nil end
   elseif not same(s.actor.ParentCarEquipableV2,s.slot)then restore(s)end
  end
  S.slots={};S.mounts={}
  for _,r in pairs(B.tracked)do if valid(r.actor)then
   for name,d in pairs(r.config and r.config.service or defs)do local c=r.actor[name];S.slots[c:GetAddress()]=d;S.mounts[c:GetAddress()]={r=r,name=name,d=d};c.CanBeRemoved=true;c.CanBeAttached=true;S.align(r,name,d)end
  end end
 end
 function S.reset()for _,s in pairs(S.parts)do restore(s)end;S.parts={};S.slots={};S.mounts={};S.meshes={};S.pending={};S.nextAt=0 end
 return S
end

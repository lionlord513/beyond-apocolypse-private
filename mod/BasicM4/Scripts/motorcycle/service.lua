return function(M,B,valid,log)
 local S={parts={},slots={},pending={},nextAt=0};local lib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
 local defs={CarMotorV2={class='CarItemMotor',at={X=4,Y=0,Z=-2},size={X=58,Y=38,Z=38},rotation={Pitch=90,Yaw=0,Roll=0}},CarBatteryV2={class='CarItemBattery',at={X=-34,Y=-9,Z=-6},size={X=22,Y=16,Z=16},rotation={Pitch=0,Yaw=0,Roll=0}},CarRadiatorV2={class='CarItemTankRadiator',at={X=-38,Y=10,Z=-15},size={X=18,Y=9,Z=27},rotation={Pitch=0,Yaw=90,Roll=0}}}
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 function S.align(r,name,d)
  local c=r.actor[name];local p=c.AttachedCarEquipableActor
  if not valid(p)or not same(p.ParentCarEquipableV2,c)or not valid(p.RootMeshComponent)then return end
  local mesh=p.RootMeshComponent;local key=p:GetAddress();local saved=S.parts[key]
  if not saved then local s=mesh.RelativeScale3D;saved={actor=p,mesh=mesh,scale={X=s.X,Y=s.Y,Z=s.Z},slot=c,collision=p.CollisionWhenAttached,impact=p.CanBeDettachedOnImpact};S.parts[key]=saved
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
   if not valid(s.actor)then S.parts[key]=nil
   elseif not same(s.actor.ParentCarEquipableV2,s.slot)then if valid(s.mesh)then s.mesh:SetRelativeScale3D(s.scale)end;if s.collision~=nil then s.actor.CollisionWhenAttached=s.collision;s.actor.CanBeDettachedOnImpact=s.impact end;S.parts[key]=nil end
  end
  S.slots={}
  for _,r in pairs(B.tracked)do if valid(r.actor)then
   for name,d in pairs(r.config and r.config.service or defs)do local c=r.actor[name];S.slots[c:GetAddress()]=d;c.CanBeRemoved=true;c.CanBeAttached=true;S.align(r,name,d)end
  end end
 end
 function S.reset()S.parts={};S.slots={};S.pending={};S.nextAt=0 end
 return S
end

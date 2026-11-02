-- Native world loot and explicit Hangar/dev-menu spawns. Native AVS owns drivetrain and service items.
return function(M,root,H,valid,log)
 local B={tracked={},pending={},known={},nextScan=0};local none=FName('None')
 local V=dofile(root..'/Scripts/motorcycle/visuals.lua')(root,valid)
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local scene=StaticFindObject('/Script/Engine.SceneComponent')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local mark='BA_Motorcycle_v1';local marks={classic=mark,suzuki='BA_Motorcycle_suzuki_v1'};local file=M.statePath and M.statePath('motorcycles.txt')or root..'/state/motorcycles.txt'
 local function vec(x,y,z)return {X=x,Y=y,Z=z}end
 local function id(a)local g=a.GuidGarage;if g.A==0 and g.B==0 and g.C==0 and g.D==0 then return end;return ('%08x:%08x:%08x:%08x'):format(g.A&0xffffffff,g.B&0xffffffff,g.C&0xffffffff,g.D&0xffffffff)end
 do local f=io.open(file,'r');if f then for k in f:lines()do local guid,variant=k:match('^(%x+:%x+:%x+:%x+) (suzuki)$');if guid then B.known[guid]=variant elseif k:match('^%x+:%x+:%x+:%x+$')then B.known[k]='classic'end end;f:close()end end
 local function marker(a)for _,v in ipairs(a:K2_GetComponentsByClass(scene))do local c=v:get();if valid(c)and (c.AttachSocketName:ToString()==mark or c.AttachSocketName:ToString()==marks.suzuki)then return c,c.AttachSocketName:ToString()==marks.suzuki and 'suzuki'or 'classic' end end end
 local function attach(c,frame,at)
  c:K2_AttachToComponent(frame,none,0,0,0,false);c:SetRelativeScale3D(vec(1,1,1));c:K2_SetRelativeLocation(at,false,{},true)
 end
 function B.owns(a)local out={};a:isOwningClient(out);return out.OwningClient==true end
 function B.adopt(a,fresh,variant)
  local existing=B.tracked[a:GetFullName()]
  if existing and valid(existing.actor)and existing.actor:GetAddress()==a:GetAddress()then return existing end
  local state={};a:GetInitializationState(state);if not state.Initialized then return end
  local key=id(a);if a:HasAuthority()and not key then return end
  local frame,markedVariant=marker(a)
  variant=variant or markedVariant or(type(B.known[key])=='string'and B.known[key])or 'classic'
  if fresh and not B.known[key]then local f=assert(io.open(file,'a'));assert(f:write(key..(variant=='suzuki'and ' suzuki'or '')..'\n'));assert(f:close());B.known[key]=variant end
  if not frame then frame=a:AddComponentByClass(scene,true,identity,false);frame:K2_AttachToComponent(a.VehicleMesh,FName(marks[variant]or mark),0,0,0,false);frame:SetIsReplicated(a:HasAuthority())end
  -- Keep the complete native Caddie physics setup. Presentation must not
  -- replace its collision body, inertia, wheel contacts or suspension tuning.
  local cfg=variant=='suzuki'and dofile(root..'/Scripts/motorcycle/suzuki.lua')or nil
  local r={actor=a,frame=frame,variant=variant,config=cfg,last=game:GetTimeSeconds(a)}
  r.visual=V.create(a,frame,variant);V.singleSkid(r)
  a.VehicleMesh:SetVisibility(false,false)
  frame:SetRelativeScale3D(vec(1,1,1));frame:K2_SetRelativeRotation({Pitch=0,Yaw=0,Roll=0},false,{},true)
  frame:K2_SetRelativeLocation(vec(17.2,0,26.76+(cfg and cfg.frameOffsetZ or 0)),false,{},true)
  local slots={CarSeatDriver=vec(-17,0,12),CarMotorV2=vec(8,0,2),CarBatteryV2=vec(-35,-12,-12),CarRadiatorV2=vec(-40,12,0),CarTankGasV2=vec(15,0,32),CarStarterV2=vec(25,0,40),CarSteeringWheelV2=vec(18,0,56)}
  slots=cfg and cfg.slots or slots
  for name,at in pairs(slots)do attach(a[name],frame,at)end
  -- Native four-wheel support is intentionally retained under the two
  -- visible wheels. Wheelie uses temporary pitch torque without relocating physical wheels.
  for _,w in ipairs({a.Vehicle_Wheel_DriverFront,a.Vehicle_Wheel_DriverBack,a.Vehicle_Wheel_PassengerFront,a.Vehicle_Wheel_PassengerBack})do
   if valid(w.WheelMeshComponent)then w.WheelMeshComponent:SetVisibility(false,true)end
  end
  local primitive=StaticFindObject('/Script/Engine.PrimitiveComponent');local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
  for _,v in ipairs(a:K2_GetComponentsByClass(primitive))do local c=v:get();if valid(c)and not c:IsA(pmc)then c:SetVisibility(false,false)end end
  a.CarEquipableComponents:ForEach(function(_,v)local c=v:get();if not valid(c)then return end
   local kind=c:GetFullName():match('^(%S+)');local service=kind=='CarMotorV2_C'or kind=='CarBatteryV2_C'or kind=='CarRadiatorV2_C'
   c.CanBeRemoved=service;c.CanBeAttached=service
   local p=c.AttachedCarEquipableActor;if valid(p)then
    local seat=c:GetAddress()==a.CarSeatDriver:GetAddress()
    p:SetActorHiddenInGame(not service and not seat)
    if seat then p.RootMeshComponent:SetVisibility(false,false)end
   end
  end)
  if valid(a.CarSeatDriver1)and valid(a.CarSeatDriver1.AttachedCarEquipableActor)then a.CarSeatDriver1.AttachedCarEquipableActor.CanPlayerAttach=false end
  a.AutomaticShifterPositon=true
  a.CanHitch=false
  a:SetActorHiddenInGame(false);B.tracked[a:GetFullName()]=r
  if a:HasAuthority()then a:FlushNetDormancy();a:ForceNetUpdate()end
  return r
 end
 function B.spawn(player,onFailure,variant)
  local p=player or H.GetPlayer();assert(valid(p)and p:HasAuthority(),'Motorcycle spawn is host-only')
  local q,f=p:K2_GetActorLocation(),p:GetActorForwardVector();local at
  local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');local color={R=0,G=0,B=0,A=1}
  for _,n in ipairs({450,650,900,1200})do
   local x,y=q.X+f.X*n,q.Y+f.Y*n;local hit={}
   if sys:LineTraceSingle(p,vec(x,y,q.Z+300),vec(x,y,q.Z-1500),0,false,{},0,hit,true,color,color,0)and hit.ImpactNormal.Z>.85 then
    local pos=hit.ImpactPoint;local box={};local center=vec(pos.X,pos.Y,pos.Z+90)
    if not sys:BoxTraceSingle(p,center,vec(center.X,center.Y,center.Z+1),vec(135,60,55),{Pitch=0,Yaw=0,Roll=0},0,false,{},0,box,true,color,color,0)then at=vec(pos.X,pos.Y,pos.Z+70);break end
   end
  end
  assert(at,'Move to open level ground before spawning the motorcycle')
  local tr={Translation=at,Rotation={X=0,Y=0,Z=0,W=1},Scale3D=vec(1,1,1)}
  local a=game:BeginDeferredActorSpawnFromClass(p,LoadAsset('/Game/BP/CarsV2/CaddieCar.CaddieCar_C'),tr,1,nil,0);assert(valid(a));a:SetActorHiddenInGame(true);a.SpawnWithOriginalPart=true;game:FinishSpawningActor(a,tr,0)
  local pending={actor=a,variant=variant,ready=game:GetTimeSeconds(p)+3,expires=game:GetTimeSeconds(p)+18,onFailure=onFailure}
  B.pending[#B.pending+1]=pending;return a,pending
 end
 function B.update(r,now)
  local a=r.actor;local dt=math.max(0,math.min(.1,now-r.last));r.last=now;B.wheelie.tick(r,dt);V.tick(r,dt)
  -- Native late initialization/seat adjustment can restore the donor's mount.
  local seat=a.CarSeatDriver;local at=seat.RelativeLocation;local target=r.config and r.config.seat or vec(-17,0,12)
  if math.abs(at.X-target.X)+math.abs(at.Y-target.Y)+math.abs(at.Z-target.Z)>.01 then seat:K2_SetRelativeLocation(target,false,{},true)end
  local saddle=seat.AttachedCarEquipableActor
  if valid(saddle)and saddle.AdjustSeat~=0 then saddle.AdjustSeat=0;saddle:OnRep_AdjustSeat()end
  if valid(a.Driver)then B.rider.apply(a.Driver)end

 end
 function B.tick(p,now)
  for _,q in ipairs(B.pending)do if valid(q.actor)then q.actor:SetActorHiddenInGame(true);q.actor.CarEquipableComponents:ForEach(function(_,v)local c=v:get();if valid(c)and valid(c.AttachedCarEquipableActor)then c.AttachedCarEquipableActor:SetActorHiddenInGame(true)end end)end end
  B.rider.install();V.install(B);B.wheelie.keys()
  for k,r in pairs(B.tracked)do if not valid(r.actor)then B.tracked[k]=nil elseif not r.failed then local ok,e=pcall(B.update,r,now);if not ok then B.wheelie.clear(r);r.failed=true;log('Motorcycle: '..tostring(e))end end end
  B.service.tick(now)
  B.headlights.tick(now)
  if now<B.nextScan then return end;B.nextScan=now+1
  for i=#B.pending,1,-1 do local q=B.pending[i]
   if not valid(q.actor)then table.remove(B.pending,i);if q.onFailure then pcall(q.onFailure)end
   elseif now>q.expires then q.actor:K2_DestroyActor();table.remove(B.pending,i);if q.onFailure then pcall(q.onFailure)end;log('Motorcycle native initialization failed')
   elseif now>=q.ready then local ok,r=pcall(B.adopt,q.actor,true,q.variant);if ok and r then table.remove(B.pending,i)elseif not ok then log('Motorcycle setup: '..tostring(r));q.ready=now+3 end end
  end
  for _,a in ipairs(FindAllOf('CaddieCar_C')or{})do if valid(a)and not B.tracked[a:GetFullName()]then
   if B.known[id(a)]or marker(a)then local ok,e=pcall(B.adopt,a,false);if not ok then log('Motorcycle restore: '..tostring(e))end
   else B.loot.consider(a,p,id(a))end
  end end
 end
 function B.reset()B.wheelie.reset();B.headlights.reset();for _,r in pairs(B.tracked)do V.restoreSkid(r)end;B.tracked={};B.pending={};B.nextScan=0;V.reset();B.service.reset();B.loot.reset()end
 B.loot=dofile(root..'/Scripts/motorcycle/loot.lua')(B,M,valid,log)
 B.service=dofile(root..'/Scripts/motorcycle/service.lua')(M,B,valid,log)
 B.wheelie=dofile(root..'/Scripts/motorcycle/wheelie.lua')(M,B,H,valid,log)
 B.rider=dofile(root..'/Scripts/motorcycle/rider.lua')(B,valid)
 B.visuals=V;B.headlights=dofile(root..'/Scripts/motorcycle/headlights.lua')(M,B,valid,log)
 return B
end

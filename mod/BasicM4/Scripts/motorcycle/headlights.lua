-- Native lamps retain GUID, inventory, saving and car headlight inputs.
return function(M,B,valid,log)
 local L={parts={},slots={},secondary={},pending={},incoming={},nextAt=0,hooks={},mounts={}}
 local none=FName('None');local scene=StaticFindObject('/Script/Engine.SceneComponent')
 local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local static=StaticFindObject('/Script/Engine.StaticMeshComponent');local spot=StaticFindObject('/Script/Engine.SpotLightComponent')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local zero={X=0,Y=0,Z=0};local rotation={Pitch=0,Yaw=0,Roll=0}
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function changed(a,b)return math.abs(a.X-b.X)+math.abs(a.Y-b.Y)+math.abs(a.Z-b.Z)>.001 end
 local function light(p)
  if not valid(L.lightClass)then L.lightClass=FindObject('BlueprintGeneratedClass','BP_GTR_Light_HL_C')end
  return valid(p)and valid(L.lightClass)and p:IsA(L.lightClass)and not M.gyrocopter.transport.blades.info(p)
 end
 local function marker(p)
  for _,v in ipairs(p:K2_GetComponentsByClass(scene))do local c=v:get();local kind=valid(c)and c.AttachSocketName:ToString():match('^BA_BikeLamp_(%a+)$')
   if kind=='classic'or kind=='suzuki'then return c,kind end
  end
 end
 local function variant(p)
  if not light(p)then return end
  local id=M.guid(p);local s=M.gyrocopter.transport.journal.state
  if id and s.lampClassic and s.lampClassic[id]then return 'classic'end
  if id and s.lampSuzuki and s.lampSuzuki[id]then return 'suzuki'end
  local _,v=marker(p);return v
 end
 function L.mark(p,v)
  if not light(p)then return end
  local J=M.gyrocopter.transport.journal;local m,old=marker(p)
  if p:HasAuthority()then
   local id=assert(M.guid(p),'Headlamp identity unavailable');J.writable()
   J.state.lampClassic=J.state.lampClassic or{};J.state.lampSuzuki=J.state.lampSuzuki or{}
   J.state.lampClassic[id]=v=='classic'or nil;J.state.lampSuzuki[id]=v=='suzuki'or nil
   if not m then m=p:AddComponentByClass(scene,true,identity,false);assert(valid(m));m:SetVisibility(false,false);m:SetIsReplicated(true)end
   if old~=v then m:K2_AttachToComponent(p.RootComponent,FName('BA_BikeLamp_'..v),0,0,0,false);p:ForceNetUpdate()end
  end
  return L.skin(p,v)
 end
 function L.skin(p,v)
  if not light(p)or not valid(p.RootMeshComponent)then return end
  local key=p:GetFullName();local s=L.parts[key]
  if not s then
   local c=p:AddComponentByClass(pmc,true,identity,false);assert(valid(c))
   c:K2_AttachToComponent(p.RootMeshComponent,FName('BA_BikeLampVisual'),0,0,0,false);c:SetAbsolute(false,false,true);c:SetIsReplicated(false)
   s={actor=p,visual=c,lights={}};L.parts[key]=s
   for _,item in ipairs(p:K2_GetComponentsByClass(spot))do s.lights[#s.lights+1]=item:get()end
  end
  if s.variant~=v then
   s.size=B.visuals.headlampItem(p,v,s.visual)
   -- Same convex native-part pickup body used by the modular rotor blades.
   local cube=LoadAsset('/Engine/BasicShapes/Cube.Cube');p.RootMeshComponent:SetStaticMesh(cube);s.variant=v
   s.regrab=valid(p.PhysicsHandle)and valid(p.PhysicsHandle:GetGrabbedComponent())or nil
  end
  p.HUDName=FText(v=='suzuki'and 'Suzuki PV 50 headlight'or 'Motorcycle headlight')
  p.CanBeDettachedOnImpact=false;p.CollisionWhenAttached=1;p:SetActorHiddenInGame(false)
  for _,item in ipairs(p:K2_GetComponentsByClass(static))do item:get():SetVisibility(false,false)end
  p.RootMeshComponent:SetWorldScale3D({X=s.size.X/100,Y=s.size.Y/100,Z=s.size.Z/100})
  local fitted=valid(p.ParentCarEquipableV2);s.visual:SetVisibility(not fitted,false)
  if not fitted then p:SetAllLightsOff()end
  if s.regrab and not fitted then
   local handle=p.PhysicsHandle;if valid(handle)then handle:ReleaseComponent();p:OnRepIsHandleInHand(true,true)end;s.regrab=nil
  end
  return s
 end
 function L.fit(r)
  local a,steer=r.actor,r.visual and r.visual.steer;if not valid(steer)then return end
  local c=a.CarLightsV3_HL;if not valid(c)then return end
  local velocity=a:GetVelocity();local parked=not valid(a.Driver)and velocity.X^2+velocity.Y^2+velocity.Z^2<50^2
  c.CanBeRemoved=parked;c.CanBeAttached=parked;c.ShouldUpdateChildCollision=false
  L.slots[c:GetAddress()]={slot=c,record=r,parked=parked}
  local d=L.mounts[r.variant]
  if not d then local _,center,size,scale=B.visuals.headlampGeometry(r.variant);d={center=center,size=size,scale=scale};L.mounts[r.variant]=d end
  if not same(c:GetAttachParent(),steer)then c:K2_AttachToComponent(steer,none,0,0,0,false)end
  if changed(c.RelativeLocation,d.center)then c:K2_SetRelativeLocation(d.center,false,{},true)end
  c:K2_SetRelativeRotation(rotation,false,{},true);c:SetRelativeScale3D({X=1/d.scale,Y=1/d.scale,Z=1/d.scale})
  if not valid(c.ShapeComponent)then c:CheckShapeComponent()end
  local shape=c.ShapeComponent
  if valid(shape)then
   if not same(shape:GetAttachParent(),c)then shape:K2_AttachToComponent(c,none,0,0,0,false)end
   shape:K2_SetRelativeLocation(zero,false,{},true);shape:K2_SetRelativeRotation(rotation,false,{},true)
   shape:SetBoxExtent({X=math.max(8,d.size.X*.5),Y=math.max(8,d.size.Y*.5),Z=math.max(8,d.size.Z*.5)},false)
  end
  local unused=a.CarLightsV3_HL1
  if valid(unused)then L.secondary[unused:GetAddress()]=unused;unused.CanBeAttached=false;unused.CanBeRemoved=false
   local p=unused.AttachedCarEquipableActor;if valid(p)then p:SetAllLightsOff();p:SetActorHiddenInGame(true)end
  end
  local p=c.AttachedCarEquipableActor;local has=light(p)
  if valid(r.visual.headlamp)then r.visual.headlamp:SetVisibility(has,false)end
  if not has or not same(p.ParentCarEquipableV2,c)or not same(p.RootComponent:GetAttachParent(),c)then return end
  local s=L.parts[p:GetFullName()]
  if not s or s.variant~=r.variant then s=L.mark(p,r.variant)else L.skin(p,r.variant)end
  if not s then return end
  p.RootComponent:K2_SetRelativeLocation(zero,false,{},true);p.RootComponent:K2_SetRelativeRotation(rotation,false,{},true)
  if not same(p.RootMeshComponent,p.RootComponent)then p.RootMeshComponent:K2_SetRelativeLocation(zero,false,{},true);p.RootMeshComponent:K2_SetRelativeRotation(rotation,false,{},true)end
  p.RootMeshComponent:SetSimulatePhysics(false);p.RootMeshComponent:SetCollisionEnabled(parked and 1 or 0)
  for _,beam in ipairs(s.lights)do if valid(beam)then beam:SetAbsolute(false,false,true);beam:K2_SetWorldLocationAndRotation(c:K2_GetComponentLocation(),steer:K2_GetComponentRotation(),false,{},true)end end
 end
 local function install()
  if L.installed then return end
  local base='/Game/BP/CarsV2/System/Components/CarEquipableV2.CarEquipableV2_C:'
  if not valid(StaticFindObject(base..'CanBePutInside'))then return end
  L.hooks[#L.hooks+1]={RegisterHook(base..'CanBePutInside',function(ctx,item,out)
   local c=ctx:get();local r=valid(c)and L.slots[c:GetAddress()]
   if r and same(r.slot,c)then out:set(r.parked and not valid(c.AttachedCarEquipableActor)and light(item:get())or false)end
  end)}
  L.hooks[#L.hooks+1]={RegisterHook(base..'ExecutePrimaryAction',function(ctx,pressed,pc,component,item)
   local c=ctx:get();if valid(c)and L.slots[c:GetAddress()]and pressed:get()and #L.pending<16 then L.pending[#L.pending+1]={slot=c,owner=pc:get(),part=item:get()}end
  end)}
  L.hooks[#L.hooks+1]={RegisterHook('/Game/BP/CarsV2/System/Components/CarLights/CarLightsV3_HL.CarLightsV3_HL_C:UpdateLights',function(ctx)
   if L.busy then return end;L.busy=true
   local ok,e=pcall(function()local c=ctx:get();local saved=valid(c)and L.slots[c:GetAddress()]
    if saved and same(saved.slot,c)then L.fit(saved.record)end
    if valid(c)and same(L.secondary[c:GetAddress()],c)then local p=c.AttachedCarEquipableActor;if valid(p)then p:SetAllLightsOff()end end
   end);L.busy=false;if not ok then log('Motorcycle headlamp: '..tostring(e))end
  end)}
  NotifyOnNewObject('/Game/BP/CarsV2/System/Actors/GTR/BP_GTR_Light_HL.BP_GTR_Light_HL_C',function(p)L.incoming[#L.incoming+1]={actor=p,attempts=0}end)
  L.installed=true
 end
 function L.tick(now)
  install()
  for _,q in ipairs(L.pending)do if valid(q.slot)and light(q.part)and same(q.slot.AttachedCarEquipableActor,q.part)and same(q.part.ParentCarEquipableV2,q.slot)then
   local ok,e=pcall(M.gyrocopter.service.consume,q.owner,q.part);if not ok then log('Motorcycle headlamp inventory: '..tostring(e))end
  end end;L.pending={}
  if now<L.nextAt then return end;L.nextAt=now+.25
  if not L.seeded then for _,p in ipairs(FindAllOf('BP_GTR_Light_HL_C')or{})do L.incoming[#L.incoming+1]={actor=p,attempts=0}end;L.seeded=true end
  for _=1,math.min(16,#L.incoming)do local q=table.remove(L.incoming,1)
   if light(q.actor)then local v=variant(q.actor)
    if v then L.skin(q.actor,v)elseif q.attempts<20 then q.attempts=q.attempts+1;L.incoming[#L.incoming+1]=q end
   end
  end
  for key,s in pairs(L.parts)do if not light(s.actor)or s.actor:GetFullName()~=key then L.parts[key]=nil else L.skin(s.actor,s.variant)end end
  L.slots={};L.secondary={}
  for _,r in pairs(B.tracked)do if valid(r.actor)and not r.failed then local ok,e=pcall(L.fit,r);if not ok and r.headlightError~=tostring(e)then r.headlightError=tostring(e);log('Motorcycle headlamp: '..r.headlightError)end end end
 end
 function L.reset()L.parts={};L.slots={};L.secondary={};L.pending={};L.incoming={};L.seeded=nil;L.nextAt=0 end
 return L
end

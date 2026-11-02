-- Native seat actors keep their inventory, save, passenger and replication logic.
return function(M,G,H,valid,log)
 local S={slots={},aligned={},nextAt=0,pending={}};local base='/Game/BP/CarsV2/System/Components/CarEquipableV2.CarEquipableV2_C:'
 local function seat(p)return valid(p)and p:IsA(StaticFindObject('/Game/BP/CarsV2/System/Actors/Master/CarItemSeat.CarItemSeat_C'))end
 local function parked(a)
  return not valid(a.Driver)and pcall(G.transport.blades.parked,a)
 end
 function S.install()
  if S.hooks or not valid(StaticFindObject(base..'CanBePutInside'))then return end
  S.hooks={}
  S.hooks[1]={RegisterHook(base..'CanBePutInside',function(ctx,item,out)
   local c=ctx:get();local a=S.slots[c:GetAddress()]
   if a and seat(item:get())then out:set(not valid(c.AttachedCarEquipableActor)and parked(a))end
  end)}
  S.hooks[2]={RegisterHook(base..'ExecutePrimaryAction',function(ctx,pressed,pc,component,item)
   local c=ctx:get();local a=S.slots[c:GetAddress()];if not a or not pressed:get()or not a:HasAuthority()or valid(c.AttachedCarEquipableActor)then return end
   local owner=pc:get();if not valid(owner)or not valid(owner.PlayerControlled)then return end
   local p=M.backpack.native.held(owner);if not seat(p)or not parked(a)then return end
   if G.transport.distance(owner.PlayerControlled:K2_GetActorLocation(),c:K2_GetComponentLocation())>300 then return end
   local ok,why=pcall(function()
    G.transport.journal.writable();assert(not StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetGameInstance(a).IsSaving)
    owner:RemoveItemInHand();p.CollisionWhenAttached=1;p.RootMeshComponent:SetSimulatePhysics(false)
    c.AttachedCarEquipableActor=p;p.ParentCarEquipableV2=c;c:OnRepAttachedCarEquipableActor();p:OnRepParentCarEquipableV2(true)
    G.service.consume(owner,p)
    S.align(a,c)
    p:SetActorHiddenInGame(false);p:ForceNetUpdate();a:ForceNetUpdate()
   end)
   if not ok then log('Seat fitting: '..tostring(why));if valid(p)and not valid(p.ParentCarEquipableV2)then owner:SetItemInHand(p)end end
  end)}
  local seatBase='/Game/BP/CarsV2/System/Actors/Master/CarItemSeat.CarItemSeat_C:'
  for _,event in ipairs({'OnRep_AdjustSeat','OnRepAdjustSeat','ExecuteThirdAction'})do
   local path=seatBase..event
   if valid(StaticFindObject(path))then S.hooks[#S.hooks+1]={RegisterHook(path,function(ctx)S.pending[ctx:get()]=true end)}end
  end
  local path='/Game/BP/CarsV2/System/Actors/Master/CarItemEquipableActor.CarItemEquipableActor_C:OnRepParentCarEquipableV2'
  if valid(StaticFindObject(path))then S.hooks[#S.hooks+1]={RegisterHook(path,function(ctx)S.pending[ctx:get()]=true end)}end
  if valid(StaticFindObject(seatBase..'GetTertiaryActionName'))then S.hooks[#S.hooks+1]={RegisterHook(seatBase..'GetTertiaryActionName',function(ctx,out)
   local p=ctx:get();if valid(p.ParentCarEquipableV2)and S.slots[p.ParentCarEquipableV2:GetAddress()]then out:set(FText(''))end
  end)}end
 end
 function S.align(a,c)
  local part=c.AttachedCarEquipableActor;if not seat(part)or not valid(part.RootMeshComponent)then return end
  if part.AdjustSeat~=0 then part.AdjustSeat=0;part:OnRep_AdjustSeat();if part:HasAuthority()then part:ForceNetUpdate()end end
  local key=c:GetAddress();local old=S.aligned[key];local at=c.RelativeLocation
  local rel=part.RootMeshComponent:GetRelativeTransform()
  local signature=table.concat({rel.Translation.X,rel.Translation.Y,rel.Translation.Z,rel.Rotation.X,rel.Rotation.Y,rel.Rotation.Z,rel.Rotation.W,rel.Scale3D.X,rel.Scale3D.Y,rel.Scale3D.Z},':')
  if old and old.part==part:GetAddress()and old.signature==signature and math.abs(at.X-old.X)+math.abs(at.Y-old.Y)+math.abs(at.Z-old.Z)<.01 then return end
  local mesh=part.RootMeshComponent;local lo,hi={},{};mesh:GetLocalBounds(lo,hi)
  local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
  local tr=mesh:K2_GetComponentToWorld();local car=a.VehicleMesh:K2_GetComponentToWorld()
  local mn={X=math.huge,Y=math.huge,Z=math.huge};local mx={X=-math.huge,Y=-math.huge,Z=-math.huge}
  for _,x in ipairs({lo.X,hi.X})do for _,y in ipairs({lo.Y,hi.Y})do for _,z in ipairs({lo.Z,hi.Z})do
   local q=mathlib:InverseTransformLocation(car,mathlib:TransformLocation(tr,{X=x,Y=y,Z=z}))
   for _,k in ipairs({'X','Y','Z'})do mn[k]=math.min(mn[k],q[k]);mx[k]=math.max(mx[k],q[k])end
  end end end
  -- Original Hornet seat bounds: X29.75..89.24, Y-22.87..25.08, base Z64.55.
  local dx,dy,dz=59.4946-(mn.X+mx.X)/2,1.10635-(mn.Y+mx.Y)/2,64.552-mn.Z
  if math.abs(dx)+math.abs(dy)+math.abs(dz)>.1 then
   local at=c.RelativeLocation;c:K2_SetRelativeLocation({X=at.X+dx,Y=at.Y+dy,Z=at.Z+dz},false,{},true)
  end
  local at=c.RelativeLocation;S.aligned[key]={part=part:GetAddress(),X=at.X,Y=at.Y,Z=at.Z,signature=signature}
 end
 function S.tick(now)
  local pending=S.pending;S.pending={}
  for p in pairs(pending)do if valid(p)and valid(p.ParentCarEquipableV2)then local c=p.ParentCarEquipableV2;local a=S.slots[c:GetAddress()];if valid(a)then S.aligned[c:GetAddress()]=nil;S.align(a,c)end end end
  if now<S.nextAt then return end;S.nextAt=now+.5;S.install();S.slots={}
  for _,r in pairs(G.tracked)do local a=r.actor;if valid(a)then
   local c=a.CarSeatDriver;S.slots[c:GetAddress()]=a;c.CanBeRemoved=parked(a);c.CanBeAttached=c.CanBeRemoved
   if not valid(c.ShapeComponent)then c:CheckShapeComponent()end
   S.align(a,c)
  end end
 end
 return S
end

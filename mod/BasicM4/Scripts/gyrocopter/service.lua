-- Keep presentation in connector space; inventory remains owned by the host.
return function(M,G,valid,log)
 local S={pending={},nextAt=0}
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 function S.consume(pc,p)
  if not valid(p)or not p:HasAuthority()or not valid(p.ParentCarEquipableV2)then return end
  local inv=p.LastInventoryComponent
  if valid(inv)then inv:RemoveItem(p);inv:InventoryChange_Event()end
  if valid(pc)and valid(pc.PlayerControlled)then
   local bag=M.backpack.native.worn(pc.PlayerControlled)
   if valid(bag)and not same(bag.BP_InventoryComponent,inv)then bag.BP_InventoryComponent:RemoveItem(p);bag.BP_InventoryComponent:InventoryChange_Event();bag:ForceNetUpdate()end
  end
  p.FromInventory=false;p.LastInventoryComponent=nil;p.LastSlot=-1
 end
 function S.engine(r)
  local a=r.actor;local c=a.CarMotorV2;local p=c.AttachedCarEquipableActor
  if not valid(p)then r.engineMount=nil;return end
  if not same(p.ParentCarEquipableV2,c)or not valid(p.RootMeshComponent)then return end
  local old=r.engineMount
  if not old or old.part~=p:GetAddress()then
   -- Mesh-local bounds cannot grow to include another actor or a physics handle.
   local mesh=p.RootMeshComponent;local lo,hi={},{};mesh:GetLocalBounds(lo,hi)
   local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
   local center={X=(lo.X+hi.X)/2,Y=(lo.Y+hi.Y)/2,Z=(lo.Z+hi.Z)/2}
   local offset=mathlib:InverseTransformLocation(c:K2_GetComponentToWorld(),mathlib:TransformLocation(mesh:K2_GetComponentToWorld(),center))
   -- Ignore a transient held/replicating pose; retry after native fitting settles.
   if math.abs(offset.X)>150 or math.abs(offset.Y)>150 or math.abs(offset.Z)>150 then return end
   old={part=p:GetAddress(),X=-offset.X,Y=-offset.Y,Z=125-offset.Z};r.engineMount=old
  end
  local at=c.RelativeLocation
  if math.abs(at.X-old.X)+math.abs(at.Y-old.Y)+math.abs(at.Z-old.Z)>.01 then c:K2_SetRelativeLocation({X=old.X,Y=old.Y,Z=old.Z},false,{},true)end
 end
 function S.tick(now)
  if not S.hook then
   local path='/Game/BP/CarsV2/System/Components/CarEquipableV2.CarEquipableV2_C:ExecutePrimaryAction'
   if valid(StaticFindObject(path))then S.hook={RegisterHook(path,function(ctx,pressed,pc,component,item)
    if pressed:get()and #S.pending<32 then S.pending[#S.pending+1]={slot=ctx:get(),pc=pc:get(),part=item:get()}end
   end)}end
  end
  local pending=S.pending;S.pending={}
  for _,v in ipairs(pending)do if valid(v.slot)and valid(v.part)and same(v.slot.AttachedCarEquipableActor,v.part)then
   for _,r in pairs(G.tracked)do if valid(r.actor)and same(v.slot:GetOwner(),r.actor)then S.consume(v.pc,v.part);break end end
  end end
  if now<S.nextAt then return end;S.nextAt=now+.25
  for _,r in pairs(G.tracked)do if valid(r.actor)then S.engine(r)end end
 end
 function S.reset()S.pending={};S.nextAt=0 end
 return S
end

-- Keep presentation in connector space; inventory remains owned by the host.
return function(M,G,valid,log)
 local S={pending={},mounts={},parts={},meshes={},nextAt=0}
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
  S.mounts[c:GetAddress()]=r
  if not valid(p)then r.engineMount=nil;return end
  if not same(p.ParentCarEquipableV2,c)or not valid(p.RootMeshComponent)then return end
  local mesh=p.RootMeshComponent
  -- Parent metadata can precede the real attachment on clients. Do not cache
  -- an offset from the held engine or a prior vehicle's connector.
  local root=p.RootComponent
  if not valid(root)or not same(root:GetAttachParent(),c)then return end
  local linked=mesh
  for _=1,8 do if same(linked,root)then break end;linked=valid(linked)and linked:GetAttachParent()end
  if not same(linked,root)then return end
  S.parts[p:GetAddress()]=r;S.meshes[mesh:GetAddress()]=p;S.meshes[root:GetAddress()]=p
  local pos,rot,scale=mesh.RelativeLocation,mesh.RelativeRotation,mesh.RelativeScale3D
  local signature=('%.5f:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f'):format(pos.X,pos.Y,pos.Z,rot.Pitch,rot.Yaw,rot.Roll,scale.X,scale.Y,scale.Z)
  pos,rot,scale=root.RelativeLocation,root.RelativeRotation,root.RelativeScale3D
  signature=signature..(':%0.5f:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f:%.5f'):format(pos.X,pos.Y,pos.Z,rot.Pitch,rot.Yaw,rot.Roll,scale.X,scale.Y,scale.Z)
  local old=r.engineMount
  if not old or old.part~=p:GetAddress()or old.signature~=signature then
   -- Mesh-local bounds cannot grow to include another actor or a physics handle.
   local lo,hi={},{};mesh:GetLocalBounds(lo,hi)
   local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
   local center={X=(lo.X+hi.X)/2,Y=(lo.Y+hi.Y)/2,Z=(lo.Z+hi.Z)/2}
   local offset=mathlib:InverseTransformLocation(c:K2_GetComponentToWorld(),mathlib:TransformLocation(mesh:K2_GetComponentToWorld(),center))
   -- Ignore a transient held/replicating pose; retry after native fitting settles.
   if math.abs(offset.X)>150 or math.abs(offset.Y)>150 or math.abs(offset.Z)>150 then return end
   old={part=p:GetAddress(),signature=signature,X=-offset.X,Y=-offset.Y,Z=125-offset.Z};r.engineMount=old
  end
  local at=c.RelativeLocation
  if math.abs(at.X-old.X)+math.abs(at.Y-old.Y)+math.abs(at.Z-old.Z)>.01 then c:K2_SetRelativeLocation({X=old.X,Y=old.Y,Z=old.Z},false,{},true)end
 end
 function S.changed(p)
  if S.busy or not valid(p)then return end
  local c=p.ParentCarEquipableV2;local r=valid(c)and S.mounts[c:GetAddress()]
  local prior=S.parts[p:GetAddress()]
  if prior and prior~=r then prior.engineMount=nil;S.parts[p:GetAddress()]=nil;if valid(p.RootMeshComponent)then S.meshes[p.RootMeshComponent:GetAddress()]=nil end;if valid(p.RootComponent)then S.meshes[p.RootComponent:GetAddress()]=nil end end
  if not r or not valid(r.actor)then return end
  S.busy=true;local ok,e=pcall(S.engine,r);S.busy=false
  if not ok then log('Aircraft engine fitting: '..tostring(e))end
 end
 local function changedComponent(ctx)
  local c=ctx:get();if not valid(c)then return end
  local p=S.meshes[c:GetAddress()];local r=S.mounts[c:GetAddress()]
  if p then S.changed(p)elseif r then S.changed(c.AttachedCarEquipableActor)end
 end
 local function installFitHooks()
  if S.fitHooks then return end
  local base='/Game/BP/CarsV2/System/Actors/Master/CarItemEquipableActor.CarItemEquipableActor_C:'
  if not valid(StaticFindObject(base..'OnRepParentCarEquipableV2'))then return end
  S.fitHooks={}
  for _,event in ipairs({'OnRepParentCarEquipableV2','UpdateOffsetTransform'})do
   S.fitHooks[#S.fitHooks+1]={RegisterHook(base..event,function(ctx)S.changed(ctx:get())end)}
  end
  S.fitHooks[#S.fitHooks+1]={RegisterHook('/Script/Engine.Actor:OnRep_AttachmentReplication',function()end,function(ctx)local p=ctx:get();if valid(p)and S.parts[p:GetAddress()]then S.changed(p)end end)}
  S.fitHooks[#S.fitHooks+1]={RegisterHook('/Script/Engine.SceneComponent:OnRep_Transform',function()end,changedComponent)}
 end
 function S.tick(now)
  installFitHooks()
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
  S.mounts={};S.parts={};S.meshes={}
  for _,r in pairs(G.tracked)do if valid(r.actor)then S.engine(r)end end
 end
 function S.reset()S.pending={};S.mounts={};S.parts={};S.meshes={};S.nextAt=0 end
 return S
end

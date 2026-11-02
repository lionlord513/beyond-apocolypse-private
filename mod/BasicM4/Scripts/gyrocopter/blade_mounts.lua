-- Native prompts/RPCs with cheap cached hover eligibility. Disk and ground
-- validation run on actual mutations, never in the per-frame selection hook.
return function(M,G,T,B,valid,log)
 local N={slots={},hooks={}}
 local base='/Game/BP/CarsV2/System/Components/CarEquipableV2.CarEquipableV2_C:'
 local selectPath='/Game/BP/PlayerController/PlayerControllerBase.PlayerControllerBase_C:CheckNeedShape'
 local function playerReady(pc)
  assert(valid(pc)and valid(pc.PlayerControlled),'Player unavailable')
  local p=pc.PlayerControlled
  assert(p.IsLoaded and p.IsInitialized and not p.BP_PlayerStats.IsDead and not p.BP_PlayerStats.IsDying,'Player unavailable')
  assert(not T.game:GetGameInstance(pc).IsSaving,'Wait for the game save to finish')
  assert(not valid(pc.Vehicle),'Leave the pilot seat to handle blades')
  return p
 end
 local function validate(pc,p,slot,attached)
  local r=N.slots[slot:GetAddress()];assert(r,'Blades only fit their matching Hornet')
  local side,owner=B.info(p);assert(side,'Use a rotor blade')
  if r.actor:HasAuthority()then T.journal.writable()end
  B.parked(r.actor);local player=playerReady(pc)
  assert(T.distance(player:K2_GetActorLocation(),slot:K2_GetComponentLocation())<300,'Move closer to the rotor mount')
  local current=slot.AttachedCarEquipableActor
  assert(not valid(current)or attached and T.same(current,p),'Blade mount occupied')
  return r
 end
 function N.selected(pc,p)
  if M.features==false then return end
  local slot=pc.ItemSelected;if not valid(slot)then return end
  local r=N.slots[slot:GetAddress()]
  local blade=valid(p)and B.items[p:GetFullName()]
  if not r and not blade then return end
  -- Native selection already checks reach and player state. Only constant-time
  -- lookups are needed here; host mutation validation below remains fresh.
  if not(r and r.parked and blade )then pc.ItemSelected=nil end
 end
 local function feedback(pc,result)pc:ClientMessage(tostring(result):gsub('^.-:%d+: ',''),FName('BAHornetTransport'),4)end
 function N.attached(slot,pressed,pc,p)
  if not pressed or not valid(pc)or not pc:HasAuthority()or not valid(p)then return end
  if not N.slots[slot:GetAddress()]and not B.info(p)then return end
  if not T.same(slot.AttachedCarEquipableActor,p)then return end
  local ok,result=pcall(validate,pc,p,slot,true)
  if not ok then
   slot:DettachAttachedCarEquipableActor(true)
   if not M.backpack.native.held(pc)then pc:SetItemInHand(p)end
   feedback(pc,result)
  end
  local target=N.slots[slot:GetAddress()];if ok and target then B.assign(p,target.actor,target.side)end
  local side,owner=B.info(p);if side then B.skin(p,side,owner)end
  local r=N.slots[slot:GetAddress()];if r then T.guardPart(p);B.mask(G.tracked[r.actor:GetFullName()])end
 end
 function N.removable(slot,out)
  local r=N.slots[slot:GetAddress()];if r then out:set(r.parked and valid(slot.AttachedCarEquipableActor))end
 end
 function N.secondaryName(p,out)
  if not valid(p)or not B.items[p:GetFullName()]or valid(p.ParentCarEquipableV2)then return end
  local parent=p:GetAttachParentActor();local rack=valid(parent)and T.carriers[parent:GetFullName()]
  if rack and rack.parked then out:set(FText('Remove'))end
 end
 function N.detached(p,pc,pressed)
  if not valid(pc)or not pc:HasAuthority()then return end
  local blade=B.items[p:GetFullName()]
  if not blade then return end
  local parent=p:GetAttachParentActor()
  if pressed and T.hasCarrier(parent)and not valid(p.ParentCarEquipableV2)then
   local ok,why=pcall(function()
    local player=playerReady(pc);assert(not M.backpack.native.held(pc),'Empty your hands first')
    assert(T.distance(player:K2_GetActorLocation(),p.RootMeshComponent:K2_GetComponentLocation())<300 and pc:LineOfSightTo(p,{X=0,Y=0,Z=0},false),'Move closer to the blade')
    B.unrack(p);pc:SetItemInHand(p);B.skin(p,blade.side,blade.owner)
   end)
   if not ok then feedback(pc,why)end;return
  end
  local id=M.guid(p)
  if id and T.journal.state.rack[id]and not T.hasCarrier(p:GetAttachParentActor())then T.journal.state.rack[id]=nil;blade.rackChecked=nil;blade.rackCheckAt=nil end
  if not valid(blade.mount)or valid(p.ParentCarEquipableV2)then return end
  local slot=blade.mount;local r=N.slots[slot:GetAddress()];if not r then return end
  local ok,why=pcall(function()T.journal.writable();B.parked(r.actor);playerReady(pc)end)
  if not ok then
   if T.same(M.backpack.native.held(pc),p)then pc:RemoveItemInHand()end
   B.refit(p,r.actor,r.side);feedback(pc,why)
  else blade.mount=nil end
  B.skin(p,blade.side,blade.owner);B.mask(G.tracked[r.actor:GetFullName()])
 end
 function N.install()
  if N.ready then return end
  local itemClass=FindObject('BlueprintGeneratedClass','CarItemEquipableActor_C');if not valid(itemClass)then return end
  local itemBase=itemClass:GetFullName():gsub('^BlueprintGeneratedClass ','')..':'
  local callbacks={
   [selectPath]=function(ctx,item)N.selected(ctx:get(),item:get())end,
   [base..'ExecutePrimaryAction']=function(ctx,pressed,pc,component,item)N.attached(ctx:get(),pressed:get(),pc:get(),item:get())end,
   [base..'CheckCanBeRemoved']=function(ctx,out)N.removable(ctx:get(),out)end,
   [itemBase..'ExecuteSecondaryAction']=function(ctx,pressed,pc)N.detached(ctx:get(),pc:get(),pressed:get())end,
   [itemBase..'OnRepParentCarEquipableV2']=function(ctx)T.guardPart(ctx:get())end,
   [itemBase..'UpdateCollisionParent']=function(ctx)T.guardPart(ctx:get())end,
   [itemBase..'GetSecondaryActionName']=function(ctx,out)N.secondaryName(ctx:get(),out)end,
  }
  for path in pairs(callbacks)do if not valid(StaticFindObject(path))then return end end
  for path,fn in pairs(callbacks)do if not N.hooks[path]then N.hooks[path]={RegisterHook(path,fn)}end end
  N.ready=true
 end
 function N.update()
  N.install();N.slots={}
  for _,r in pairs(G.tracked)do if valid(r.actor)then
   local parked=pcall(B.parked,r.actor);local owner=r.actor:HasAuthority()and G.id(r.actor)or nil
   for side=1,2 do
    local slot=B.slot(r.actor,side);local y=side==1 and -18 or 18
    N.slots[slot:GetAddress()]={actor=r.actor,side=side,owner=owner,parked=parked}
    slot.CanBeRemoved=N.ready and parked;slot.CanBeAttached=N.ready and parked;slot.ShouldUpdateChildCollision=false
    local at=slot.RelativeLocation
    if math.abs(at.X-12.9)>.01 or math.abs(at.Y-y)>.01 or math.abs(at.Z-217)>.01 then slot:K2_SetRelativeLocation({X=12.9,Y=y,Z=217},false,{},true)end
    if not valid(slot.ShapeComponent)then slot:CheckShapeComponent()end
    local shape=slot.ShapeComponent
    if valid(shape)then
     local at,extent=shape.RelativeLocation,shape.BoxExtent
     if math.abs(at.X)+math.abs(at.Y)+math.abs(at.Z)>.01 then shape:K2_SetRelativeLocation({X=0,Y=0,Z=0},false,{},true)end
     if extent.X~=18 or extent.Y~=16 or extent.Z~=32 then shape:SetBoxExtent({X=18,Y=16,Z=32},false)end
    end
    local p=slot.AttachedCarEquipableActor;local blade=valid(p)and B.items[p:GetFullName()]
    if blade then
     blade.mount=slot
     -- The original native part supplies a query-only surface over the actual
     -- stopped blade, not an invisible pickup volume at the old headlight.
     local mesh=p.RootMeshComponent;mesh:SetCollisionEnabled(parked and 1 or 0)
     if parked then
      local rotor=r.visual.rotor;local center={X=side==1 and 169.3856 or -169.3778,Y=side==1 and -3.4352 or 3.43,Z=4.9661}
      mesh:K2_SetWorldLocationAndRotation(T.math:TransformLocation(rotor:K2_GetComponentToWorld(),center),rotor:K2_GetComponentRotation(),false,{},true)
      mesh:SetWorldScale3D({X=3.1843,Y=.2035,Z=.1347})
     end
    end
   end
  end end
 end
 function N.reset()N.slots={}end
 N.validate=validate;return N
end

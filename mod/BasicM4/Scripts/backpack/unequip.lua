-- Native Unequip replaces the worn actor. Follow that replacement immediately;
-- the old actor cannot be used for the delayed pickup or inventory replication.
return function(N,M,valid,log)
 return function(pc,b)
  local before={};for _,a in ipairs(FindAllOf('ItemBackpack_C')or{})do if valid(a)then before[a:GetAddress()]=true end end
  local class=b:GetClass();local originalId=N.actor(b);local p=pc.PlayerControlled
  local q=p:K2_GetActorLocation();local origin={X=q.X,Y=q.Y,Z=q.Z}
  local old=b.BP_InventoryComponent
  local scratch=StaticConstructObject(old:GetClass(),pc);local copy=scratch.Slots
  old.Slots:ForEach(function(k,v)copy:Add(k:get(),v:get())end)
  b:Unequip(pc)
  local replacement
  -- UE4SS IsValid can remain true until GC after K2_DestroyActor. Prefer the
  -- newly created actor; never mistake the dying original for a dropped bag.
  for _,a in ipairs(FindAllOf('ItemBackpack_C')or{})do if valid(a)and not before[a:GetAddress()]and a:GetClass():GetAddress()==class:GetAddress()then
    assert(not replacement,'More than one native replacement; inventory left untouched');replacement=a
  end end
  assert(valid(replacement),'Native backpack replacement is still loading')
  local i=replacement.BP_InventoryComponent
  -- Use the actual native structs; never rebuild save bytes or clone a live item.
  copy:ForEach(function(k,v)local slot=k:get();local d=v:get()
   if i.Slots:Contains(slot)then assert(N.token(i.Slots:Find(slot):get())==N.token(d),'Native replacement contents differ; preserved for inspection')
   else i.Slots:Add(slot,d)end
  end)
  if not valid(replacement.PlayerEquiped)then
   local center,extent={},{};replacement:GetActorBounds(false,center,extent,false)
   local forward=p:GetActorForwardVector();local target={X=origin.X+forward.X*70,Y=origin.Y+forward.Y*70,Z=origin.Z+30}
   local mesh=replacement.RootMeshComponent
   -- Physics meshes can be detached from DefaultSceneRoot. Move by the bounds
   -- delta and account for either attachment state without applying it twice.
   local at=replacement:K2_GetActorLocation();local dx,dy,dz=target.X-center.X,target.Y-center.Y,target.Z-center.Z
   replacement:K2_SetActorLocation({X=at.X+dx,Y=at.Y+dy,Z=at.Z+dz},false,{},true)
   replacement:GetActorBounds(false,center,extent,false)
   local atMesh=mesh:K2_GetComponentLocation()
   mesh:K2_SetWorldLocation({X=atMesh.X+target.X-center.X,Y=atMesh.Y+target.Y-center.Y,Z=atMesh.Z+target.Z-center.Z},false,{},true)
   mesh:SetPhysicsLinearVelocity({X=0,Y=0,Z=0},false,FName('None'))
   mesh:SetPhysicsAngularVelocityInDegrees({X=0,Y=0,Z=0},false,FName('None'))
  end
  replacement:FlushNetDormancy();i:InventoryChange_Event();replacement:ForceNetUpdate()
  log('Backpack native replacement '..tostring(originalId)..' -> '..tostring(N.actor(replacement))..'; retained '..#i.Slots..' native slots')
  N.pickups=N.pickups or{};N.pickups[pc:GetAddress()]={pc=pc,bag=replacement,at=os.clock()+.3}
  return 'Removing backpack...'
 end
end

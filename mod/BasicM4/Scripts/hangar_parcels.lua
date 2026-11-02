-- Custom contents use the native parcel animation and native inventory loader.
-- Only journalled Hangar parcels are intercepted; ordinary shop boxes are untouched.
return function(M,valid,log)
 local P={nextAt=0,requests={},restored={},delivered={}}
 function P.open(box)
  if M.features==false or not valid(box)or not box:HasAuthority()or not box.IsActive then return end
  local J=M.gyrocopter.transport.journal;local key=M.guid(box);local record=key and J.state.parcel[key];if not record or P.busy then return end
  P.busy=true;local part;local originalClass=box.ActorData.Class
  local ok,why=pcall(function()
   J.writable();assert(not StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetGameInstance(box).IsSaving,'Wait for the save to finish')
   assert(valid(box.ActorData.Class)and #box.ActorData.ByteData>0,'Parcel contents unavailable')
   local i=StaticConstructObject(FindObject('BlueprintGeneratedClass','BP_InventoryComponent_C'),box);i.NbSlot=1;i.Slots:Add(0,box.ActorData)
   -- The native open event can restore ActorData before our Blueprint post-hook.
   -- Adopt that exact saved item instead of restoring the payload a second time.
   part=P.restored[key]or box.ActorToSpawn
   if not valid(part)or M.guid(part)~=record[1]then
    local at=box.StaticMesh:K2_GetComponentLocation();local out={};i:GetItemFromSlot(0,true,{X=at.X,Y=at.Y,Z=at.Z+35},true,false,out);part=out.Item
   end
   assert(valid(part)and M.guid(part)==record[1],'Parcel identity could not be restored')
   local ammoClass=FindObject('BlueprintGeneratedClass','AkBullet_C')
   local rifleAmmo=valid(ammoClass)and part:IsA(ammoClass)
   if rifleAmmo then
    if part.NbBullet~=30 then log('Hangar rifle parcel restored '..tostring(part.NbBullet)..' rounds; correcting to 30')end
    part.Min=30;part.Max=30;part.NbBullet=30
   end
   if record[2]==1 then local B=M.gyrocopter.transport.blades;local r=assert(J.state.blade[record[1]]);B.skin(part,r[2],r[1])elseif record[2]==2 then M.rail.optic.markItem(part)elseif record[2]>=4 then M.force(part,({[4]='m4',[5]='hunting',[6]='enfield'})[record[2]])end
   -- Consume the native payload before dropping/destroying can cause another event.
   box.ActorData.Class=nil;box.ActorToSpawn=part;P.delivered[key]={box=box,part=part,guid=record[1]};P.restored[key]=nil
   part.FromInventory=false;part.LastInventoryComponent=nil;part.LastSlot=-1;part:DropItem()
   if rifleAmmo then
    if part.NbBullet~=30 then log('Hangar rifle parcel drop changed count to '..tostring(part.NbBullet)..'; correcting to 30')end
    part.Min=30;part.Max=30;part.NbBullet=30
    local visible,visualError=pcall(M.ammo.appearance,part);if not visible then log('Hangar ammo carton: '..tostring(visualError))end
   end
   part:FlushNetDormancy();part:ForceNetUpdate()
   J.state.parcel[key]=nil;box:K2_DestroyActor()
  end)
  P.busy=false
  if not ok then
   P.restored[key]=nil;P.delivered[key]=nil
   if valid(part)then part.FromInventory=false;part.LastInventoryComponent=nil;part:K2_DestroyActor()end
   if valid(box)then box.ActorData.Class=originalClass;box.ActorToSpawn=nil;box.IsActive=false;box.IsFinish=false;box:ForceNetUpdate()end
   log('Hangar parcel retained: '..tostring(why))
  end
 end
 local function suppress(box)
  box.DestroyAfterTrigger=false;box.ItemToSpawn:Empty();box.CarClassToSpawn=nil;box.ClassOfItemToSpawn=nil;box.ClassToSpawn=nil;box.ClassToSpawnWhenOpen=nil
 end
 function P.install()
  -- Native inventory restoration is a Blueprint post-hook. It runs for both
  -- native parcel opening and our fallback, and only journalled boxes qualify.
  local restore='/Game/BP/Components/BP_InventoryComponent.BP_InventoryComponent_C:GetItemFromSlot'
  if not P.restoreHook and valid(StaticFindObject(restore))then P.boxClass=FindObject('BlueprintGeneratedClass','BP_eBayColis_C');P.restoreHook={RegisterHook(restore,function(ctx,_,__,___,____,_____,item)
   local inventory=ctx:get();local box=inventory:GetOuter();if not valid(box)or not valid(P.boxClass)or not box:IsA(P.boxClass)or not box:HasAuthority()then return end
   local key=M.guid(box);if not key then return end
   local record=M.gyrocopter.transport.journal.state.parcel[key];local done=P.delivered[key]
   local expected=record and record[1]or done and done.guid;if not expected then return end
   local part=item:get();if not valid(part)or M.guid(part)~=expected then return end
   local first=done and done.part or P.restored[key]
   if valid(first)and first:GetAddress()~=part:GetAddress()then
    part.FromInventory=false;part.LastInventoryComponent=nil;part:K2_DestroyActor();item:set(first)
   else P.restored[key]=part end
  end)}end
  for key,r in pairs(P.delivered)do if not valid(r.box)then P.delivered[key]=nil end end
  local path='/Game/BP/EbaySystem/BP_eBayColis.BP_eBayColis_C:ExecutePrimaryAction'
  if not P.hook and valid(StaticFindObject(path))then P.hook={RegisterHook(path,function(ctx,pressed,owner)
   local box=ctx:get();if not pressed:get()or not box:HasAuthority()then return end
   local key=M.guid(box);local J=M.gyrocopter.transport.journal
   if key and J.state.parcel[key]then P.requests[key]={box=box,pc=owner:get()}end
  end)}end
  -- Open after the native interaction finishes, never destroy an actor in its event.
  for key,r in pairs(P.requests)do
   P.requests[key]=nil;local box,pc=r.box,r.pc
   if valid(box)and valid(pc)and pc:HasAuthority()and valid(pc.PlayerControlled)then
    local p=pc.PlayerControlled;local a,b=p:K2_GetActorLocation(),box.StaticMesh:K2_GetComponentLocation()
    if p.IsLoaded and not p.BP_PlayerStats.IsDead and not p.BP_PlayerStats.IsDying and (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2<350^2 and pc:LineOfSightTo(box,{X=0,Y=0,Z=0},false)then box.IsActive=true;P.open(box)end
   end
  end
  if os.clock()<P.nextAt then return end;P.nextAt=os.clock()+.5
  local J=M.gyrocopter.transport.journal
  if not J.ready or not next(J.state.parcel)then return end
  for _,box in ipairs(FindAllOf('BP_eBayColis_C')or{})do
   if valid(box)and box:HasAuthority()and J.state.parcel[M.guid(box)]then suppress(box);P.open(box)end
  end
 end
 function P.prepare(box,part,kind)
  P.install();assert(P.hook,'Native parcel interaction unavailable')
  local J=M.gyrocopter.transport.journal;J.writable();local id=assert(M.guid(box));J.state.parcel[id]={assert(M.guid(part)),({blade=1,sight=2,tank=3,radiator=3,ammo=3,m4=4,hunting=5,enfield=6})[kind]or error('Unknown parcel kind')}
  suppress(box)
 end
 return P
end

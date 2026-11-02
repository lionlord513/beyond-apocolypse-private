-- Read-only view uses native replicated SlotsList. Only the host mutates Slots.
return function(B,M,root,H,valid,enqueue,log)
 local P=B.policy;local S=dofile(root..'/Scripts/backpack/snapshot.lua')
 local N={};B.native=N
 local reachable=dofile(root..'/Scripts/backpack/reach.lua')
 -- ID is replicated by the game; GuidUnique is save-only and differs on clients.
 function N.actor(item)
  if not valid(item)then return end
  local id=item.ID
  if type(id)=='number'and id>0 and id%1==0 and id<=2147483647 then return 'n:'..tostring(id)end
 end
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 function N.tier(b)return valid(b)and P.tiers[b:GetFullName():match('^(%S+)')]end
 function N.worn(p)local o={};p:GetBackpack(o);return o.Backpack end
 function N.held(pc)local o={};pc:GetItemInHand(o);return valid(o.Item)and o.Item or nil end
 function N.nativeData(b)
  local result={}
  if b:HasAuthority()then
   b.BP_InventoryComponent.Slots:ForEach(function(k,v)local d=v:get();if valid(d.Class)then result[k:get()]=d end end)
   return result
  end
  b.BP_InventoryComponent.SlotsList:ForEach(function(_,v)
   local s=v:get();local d=s.Item_6_8F0F2EDA49763B1E44E91892B40CECD0
   if valid(d.Class)then result[s.Slot_4_66BD88B64B3029E7A3AF77BC02AE2489]=d end
  end);return result
 end
 N.token=S.token
 local weaponIds={};local weaponIdFile=M.statePath and M.statePath('inventory-weapons.txt')or root..'/state/inventory-weapons.txt'
 do local f=io.open(weaponIdFile,'r');if f then for line in f:lines()do local token,id=line:match('^(%x+:%x+:%x+:%x+) (%x+:%x+:%x+:%x+)$');if token then weaponIds[token]=id end end;f:close()end end
 local function rememberWeapon(token,id)
  if not id or weaponIds[token]==id then return end;weaponIds[token]=id
  local f=io.open(weaponIdFile,'a');if f then f:write(token..' '..id..'\n');f:close()end
 end
 function N.attachments(d,b,k)
  if type(d)=='table'and d.attachments then return d.attachments end
  if not M.rail or not d or not valid(d.Class)or not d.Class:GetFullName():find('AkWeapon',1,true)then return ''end
  local token=S.token(d);local id=weaponIds[token]
  if not id and valid(b)and b:HasAuthority()then
   -- Native snapshots compress the actor GUID. Resolve an older snapshot once
   -- through native loading; never decode or rewrite its serialized bytes.
   local item;local ok=pcall(function()
    local out={};b.BP_InventoryComponent:GetItemFromSlot(k,true,b:K2_GetActorLocation(),false,true,out);item=out.Item
    assert(valid(item));item.FromInventory=false;item.LastInventoryComponent=nil;item.LastSlot=-1;id=M.guid(item);rememberWeapon(token,id)
   end)
   if valid(item)then item:K2_DestroyActor()end
   if not ok then return 'Attachments unavailable'end
  end
  return id and M.rail.attachments(id)or ''
 end
 local labels={};local labelFile=M.statePath and M.statePath('inventory-labels.txt')or root..'/state/inventory-labels.txt'
 do local f=io.open(labelFile,'r');if f then for line in f:lines()do local token,label=line:match('^(%x+:%x+:%x+:%x+) (.+)$');if token then labels[token]=label end end;f:close()end end
 function N.remember(d,item)
  if not M.itemName then return end
  local token=S.token(d);local label=M.itemName(item)
  if valid(item)and item:GetFullName():match('^AkWeapon_C ')then rememberWeapon(token,M.guid(item))end
  if labels[token]==label then return end;labels[token]=label
  local f=io.open(labelFile,'a');if f then f:write(token..' '..label:gsub('[\r\n]',' ')..'\n');f:close()end
 end
 local resolvedBladeLabels={}
 function N.title(d,b,k)
  if valid(b)and b:HasAuthority()and valid(d.Class)and d.Class:GetFullName():find('BP_GTR_Light_H',1,true)and labels[S.token(d)]~='Universal rotor blade'and not resolvedBladeLabels[S.token(d)]then
   resolvedBladeLabels[S.token(d)]=true
   local item;local ok=pcall(function()local out={};b.BP_InventoryComponent:GetItemFromSlot(k,true,b:K2_GetActorLocation(),false,true,out);item=out.Item;if valid(item)then N.remember(d,item)end end)
   if valid(item)then item:K2_DestroyActor()end
  end
  if type(d)=='table'and d.label then return d.label end
  local label=labels[S.token(d)];if label then return label end
  local c=d.Class:GetFullName():match('%.([^%.]+)_C$')or'Item'
  if c=='AkWeapon'then return 'Rifle'end
  return c:gsub('(%l)(%u)','%1 %2'):gsub('_',' ')
 end
 function N.icon(d,pc)
  if N.title(d)~='Universal rotor blade'then return end
  if not valid(N.bladeIcon)then N.bladeIcon=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(pc,root..'/assets/shop/blade.png')end
  return N.bladeIcon
 end
 function N.heldTitle(item)return M.itemName and M.itemName(item)or'Item'end
 function N.data(b)
  local data=N.nativeData(b)
  return not b:HasAuthority()and N.view and N.view.data(b,data)or data
 end
 function N.loose(pc,item)
  if not valid(item)or not item:IsA(StaticFindObject('/Game/BP/Items/Master/ItemBaseMaster.ItemBaseMaster_C'))then return false end
  if N.tier(item)or item:IsA(StaticFindObject('/Game/BP/Items/Master/ItemBackpack.ItemBackpack_C'))then return false end
  if N.held(pc)or item.isAttached or valid(item.VehicleAttached)or valid(item:GetAttachParentActor())then return false end
  local a,c=pc.PlayerControlled:K2_GetActorLocation(),item:K2_GetActorLocation()
  local dx,dy,dz=a.X-c.X,a.Y-c.Y,a.Z-c.Z;if dx*dx+dy*dy+dz*dz>200*200 then return false end
  local out={};item:CanBePickedUpFromGround(out);if not out.Can then return false end
  out={};item:CanBePickedUp(pc,out);if not out.Can then return false end
  for _,other in ipairs(FindAllOf('PlayerController')or{})do
   if valid(other)and valid(other.PlayerControlled)and same(N.held(other),item)then return false end
  end
  return pc:LineOfSightTo(item,{X=0,Y=0,Z=0},false)
 end
 function N.looked(pc,id)
  local item=pc.ItemTargeted
  if N.loose(pc,item)and(not id or N.actor(item)==id)then return item end
  local out={};pc:GetItemSelected(out);item=out.ItemSelected
  if N.loose(pc,item)and(not id or N.actor(item)==id)then return item end
 end
 function N.storeTarget(pc,id)
  if pc:IsLocalPlayerController()then return N.looked(pc,id)end
  -- Selection traces/HUD belong to the owning client. Resolve its GUID on the
  -- authority by its replicated ID, then check reach, LOS and pickup rules.
  for _,item in ipairs(FindAllOf('ItemBaseMaster_C')or{})do
   if valid(item)and N.actor(item)==id and N.loose(pc,item)then return item end
  end
 end
 function N.free(b)
  local tier=N.tier(b);local data=N.data(b)
  -- Fill storage first, preserving the user's chosen quick slots.
  for k=tier.hotbar,tier.cells-1 do if not data[k]then return k end end
  for k=0,tier.hotbar-1 do if not data[k]then return k end end
 end
 function N.access(pc,b)
  local p=pc.PlayerControlled
  if not valid(p)or not p.IsLoaded or not p.IsInitialized or p.BP_PlayerStats.IsDead or p.BP_PlayerStats.IsDying or valid(pc.Vehicle)then return false end
  if not N.tier(b)then return false end
  if same(b.PlayerEquiped,p)and same(N.worn(p),b)then return true end
  if valid(b.PlayerEquiped)and same(N.worn(b.PlayerEquiped),b)then return false end
  -- OwnedByPlayer can loop on a freshly detached wearable. Compare actual hands.
  for _,other in ipairs(FindAllOf('PlayerController')or{})do
   if valid(other)and valid(other.PlayerControlled)and same(N.held(other),b)then return false end
  end
  return reachable(pc,b)
 end
 function N.target(pc)
  if N.tier(pc.ItemTargeted)and N.access(pc,pc.ItemTargeted)then return pc.ItemTargeted end
  local out={};pc:GetItemSelected(out)
  if N.tier(out.ItemSelected)and N.access(pc,out.ItemSelected)then return out.ItemSelected end
  local b=N.worn(pc.PlayerControlled);if N.access(pc,b)then return b end
 end
 local function find(pc,id)
  local b=N.worn(pc.PlayerControlled)
  -- Freshly equipped bags can arrive before their numeric ID. The server can
  -- resolve only this caller's worn slot; never fall back to another player's bag.
  if id:sub(1,2)=='w:'then
   if N.tier(b)and b:GetFullName():match('^(%S+)')==id:sub(3)then return b end;return
  end
  if N.tier(b)and N.actor(b)==id then return b end
  for _,a in ipairs(FindAllOf('ItemBackpack_C')or{})do if N.tier(a)and N.actor(a)==id then return a end end
 end
 N.find=find
 local function changed(b)
  b:FlushNetDormancy();b.BP_InventoryComponent:InventoryChange_Event();b:ForceNetUpdate()
  for _,w in ipairs(FindAllOf('WBP_Inventory_C')or{})do if valid(w)and same(w.CurrentWear,b)then w:UpdateInventory()end end
 end
 local function expanded(i,capacity,fn)
  local n=i.NbSlot;i.NbSlot=capacity;local ok,result=pcall(fn);i.NbSlot=n
  if not ok then error(result)end;return result
 end
 local function eligible(item,fn)
  local old=item.CanBeInBackpack;item.CanBeInBackpack=true
  local ok,result=pcall(fn);item.CanBeInBackpack=old
  if not ok then error(result)end;return result
 end
 local function stage(b,slots)
  if not valid(N.scratch)then N.scratch=StaticConstructObject(b.BP_InventoryComponent:GetClass(),b)end
  local m=N.scratch.Slots;m:Empty()
  for _,k in ipairs(slots)do if b.BP_InventoryComponent.Slots:Contains(k)then m:Add(k,b.BP_InventoryComponent.Slots:Find(k):get())end end
  return m
 end
 local unequip=dofile(root..'/Scripts/backpack/unequip.lua')(N,M,valid,log)
 function N.execute(pc,r)
  assert(valid(pc)and pc:HasAuthority(),'Host owns inventory transfers')
  local p=pc.PlayerControlled;assert(valid(p),'Player unavailable')
  local gi=StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetGameInstance(pc)
  assert(not gi.IsSaving,'Wait for the game save to finish')
  local b=assert(find(pc,r.bag),'Backpack unavailable');assert(N.access(pc,b),'Backpack out of reach or in use')
  local tier=N.tier(b);local i=b.BP_InventoryComponent;local slots=i.Slots;local h=N.held(pc)
  local function at(k)return slots:Contains(k)and S.token(slots:Find(k):get())or'-'end
  local ok,why=P.validate(r,tier.cells,at,h and(N.actor(h)or'held-unsynced')or'-');assert(ok,why)
  if r.op=='unequip'then
   assert(same(N.worn(p),b),'That backpack is not equipped')
   return unequip(pc,b)
  end
  if r.op=='store'then
   assert(same(N.worn(p),b),'Wear your backpack first')
   local item=assert(N.storeTarget(pc,r.source),'Look at a loose item within reach with empty hands')
   assert(N.actor(item)==r.source,'Target changed; try again')
   log('Backpack store: serialize '..item:GetFullName())
   local out={}
   local worked,err=pcall(function()
    -- Native Force does not bypass eligibility. This non-save flag is borrowed
    -- only for this validated native serialization, then restored even on error.
    eligible(item,function()expanded(i,tier.cells,function()i:AddItemToSlot(r.to,item,false,false,out)end)end)
    assert(out.Added and slots:Contains(r.to),'Native storage refused this item')
   end)
   if not worked then slots:Remove(r.to);changed(b);error(err)end
   log('Backpack store: native snapshot accepted; remove world actor')
   N.remember(slots:Find(r.to):get(),item)
   item:K2_DestroyActor();changed(b);log('Backpack store: complete');return 'Stored in backpack'
  elseif r.op=='move'then
   -- Native quick slots retain a save snapshot while their live item is equipped.
   -- Never move that stale snapshot; putting the held item removes it natively.
   if h and same(N.worn(p),b)and valid(p.ItemEquiped)then assert(r.from~=i.CurrentSlot and r.to~=i.CurrentSlot,'Store the held item before moving its hotbar cell')end
   local backup=stage(b,{r.from,r.to})
   local worked,err=pcall(function()
    slots:Add(r.to,backup:Find(r.from):get())
    if backup:Contains(r.to)then slots:Add(r.from,backup:Find(r.to):get())else slots:Remove(r.from)end
    assert(at(r.to)==r.source and at(r.from)==r.target,'Native item copy did not preserve data')
   end)
   if not worked then
    slots:Add(r.from,backup:Find(r.from):get());if backup:Contains(r.to)then slots:Add(r.to,backup:Find(r.to):get())else slots:Remove(r.to)end
    changed(b);error(err)
   end
   backup:Empty();changed(b);return 'Item moved'
  elseif r.op=='put'then
   assert(not N.tier(h)and not h:IsA(StaticFindObject('/Game/BP/Items/Master/ItemBackpack.ItemBackpack_C')),'Backpacks cannot be stored inside backpacks')
   -- Do not destroy until the native serializer has accepted and stored the item.
   local out={};eligible(h,function()expanded(i,tier.cells,function()i:CanAddItemToSlot(r.to,h,out)end)end);assert(out.Return,'This cell cannot accept the item')
   local worn=N.worn(p)
   if valid(worn)then worn.BP_InventoryComponent:RemoveItem(h)end
   if valid(p.ItemEquiped)then p:RemoveEquipedItem()end;pc:RemoveItemInHand()
   out={};eligible(h,function()expanded(i,tier.cells,function()i:AddItemToSlot(r.to,h,false,false,out)end)end)
   if not out.Added then h:ExecutePrimaryAction(true,pc,h.RootComponent,h);error('Storage refused; item returned to the world/hands')end
   -- ShouldDestroy=false leaves a recoverable original until success is verified.
   assert(slots:Contains(r.to),'Native storage did not confirm the item')
   N.remember(slots:Find(r.to):get(),h)
   h:K2_DestroyActor();changed(b);if valid(worn)and not same(worn,b)then changed(worn)end;return 'Item stored'
  elseif r.op=='attach'then
   assert(M.rail,'Weapon attachments unavailable')
   if h and same(N.worn(p),b)and valid(p.ItemEquiped)then assert(r.from~=i.CurrentSlot and r.to~=i.CurrentSlot,'Store the equipped item before attaching')end
   local backup=stage(b,{r.from,r.to});local lamp,gun,id,previous,kind
   local worked,err=pcall(function()
    local out={};i:GetItemFromSlot(r.from,true,p:K2_GetActorLocation(),false,true,out);lamp=out.Item;assert(valid(lamp),'Flashlight retrieval failed')
    out={};i:GetItemFromSlot(r.to,true,p:K2_GetActorLocation(),false,true,out);gun=out.Item;assert(valid(gun),'Rifle retrieval failed')
    -- Temporary slot actors must not erase the saved cell when destroyed.
    for _,item in ipairs({lamp,gun})do item.FromInventory=false;item.LastInventoryComponent=nil;item.LastSlot=-1 end
    assert(M.rail.flash(lamp)or M.rail.optic.item(lamp),'Drag a flashlight or 2x sight onto a rifle');M.scan();kind=M.rail.optic.item(lamp)and 'scope'or 'light'
    assert(M.rail.definition(gun),'Choose M4A1, Hunting Rifle or Lee-Enfield')
    id=M.guid(gun);previous=M.rail.journal.state[kind][id];assert(not previous,'This rifle already has a flashlight')
    M.rail.mount(gun,lamp)
    slots:Remove(r.from);slots:Remove(r.to)
    out={};eligible(gun,function()expanded(i,tier.cells,function()i:AddItemToSlot(r.to,gun,false,false,out)end)end)
    assert(out.Added and slots:Contains(r.to),'Rifle storage failed');N.remember(slots:Find(r.to):get(),gun)
   end)
   if not worked then
    if id then M.rail.journal.state[kind][id]=previous end
    slots:Add(r.from,backup:Find(r.from):get());slots:Add(r.to,backup:Find(r.to):get())
   end
   if valid(gun)then gun:K2_DestroyActor()end;if valid(lamp)then lamp:K2_DestroyActor()end
   backup:Empty();changed(b);if not worked then error(err)end;return 'Attachment fitted'
  elseif r.op=='detach'then
   assert(M.rail,'Attachments unavailable')
   if h and same(N.worn(p),b)and valid(p.ItemEquiped)then assert(r.from~=i.CurrentSlot,'Store the equipped rifle first')end
   local backup=stage(b,{r.from});local gun,id,made,old
   local ok,e=pcall(function()
    local out={};i:GetItemFromSlot(r.from,true,p:K2_GetActorLocation(),false,true,out);gun=out.Item;assert(valid(gun),'Rifle retrieval failed')
    gun.FromInventory=false;gun.LastInventoryComponent=nil;gun.LastSlot=-1;M.refreshWeapon(gun);id=M.guid(gun)
    made,old=M.rail.detach(gun,pc);slots:Remove(r.from)
    out={};eligible(gun,function()expanded(i,tier.cells,function()i:AddItemToSlot(r.from,gun,false,false,out)end)end)
    assert(out.Added and slots:Contains(r.from),'Rifle storage failed');N.remember(slots:Find(r.from):get(),gun)
   end)
   if not ok then
    if old then M.rail.journal.state.light[id]=old.light;M.rail.journal.state.scope[id]=old.scope end
    for _,a in ipairs(made or{})do if valid(a)then a:K2_DestroyActor()end end
    slots:Add(r.from,backup:Find(r.from):get())
   end
   if valid(gun)then gun:K2_DestroyActor()end;backup:Empty();changed(b);if not ok then error(e)end
   return 'Attachments placed at your feet'
  elseif r.op=='drophand'then
   -- Native secondary handles equipped hotbar cleanup and the physical release.
   N.dropHeld(pc,h)
   changed(b);return 'Item dropped'
  elseif r.op=='take'or r.op=='drop'then
   if r.op=='drop'and h and same(N.worn(p),b)and valid(p.ItemEquiped)then assert(r.from~=i.CurrentSlot,'Drop the equipped item from hands')end
   local backup=stage(b,{r.from});local out={}
   local at=p:K2_GetActorLocation()
   if r.op=='drop'then local f=p:GetActorForwardVector();at={X=at.X+f.X*100,Y=at.Y+f.Y*100,Z=at.Z+30}end
   local ok,e=pcall(function()i:GetItemFromSlot(r.from,true,at,true,false,out)end)
   local item=out.Item
   if not ok or not valid(item)then
    slots:Add(r.from,backup:Find(r.from):get());changed(b);error(ok and 'Native retrieval failed; stored item restored'or e)
   end
   backup:Empty()
   -- A storage-cell retrieval is a world item, not a native hotbar toggle.
   -- Clear the saved inventory return route before native pickup/drop runs.
   if r.op=='drop'or r.from>=tier.hotbar then
    item.FromInventory=false;item.LastInventoryComponent=nil;item.LastSlot=-1
   end
   if r.op=='drop'then item:DropItem();item:FlushNetDormancy();item:ForceNetUpdate();changed(b);return 'Item dropped'end
   item:ExecutePrimaryAction(true,pc,item.RootComponent,item)
   changed(b);return 'Item retrieved'
  end
 end
 function N.dropHeld(pc,item)
  assert(pc:HasAuthority()and same(N.held(pc),item),'Held item changed')
  local p=pc.PlayerControlled;local worn=N.worn(p)
  local rifle=M.rail and M.rail.definition and M.rail.definition(item)
  if valid(worn)then worn.BP_InventoryComponent:RemoveItem(item)end
  item.FromInventory=false;item.LastInventoryComponent=nil;item.LastSlot=-1
  if M.weaponHandling and pc:IsLocalPlayerController()then M.weaponHandling.reset()end
  -- Equipped native items need their OnUnequip/owner/animation transition first.
  -- The first secondary puts a rifle into physical hands; the second releases it.
  item:ExecuteSecondaryAction(true,pc,item.RootComponent,item,item:GetTransform())
  if same(N.held(pc),item)then item:ExecuteSecondaryAction(true,pc,item.RootComponent,item,item:GetTransform())end
  assert(not same(N.held(pc),item),'Native item release is still pending')
  if rifle and valid(item)and valid(item.RootMeshComponent)then
   -- The FPS arm moves the rendered mesh, not the loose actor's old root.
   -- After native ownership cleanup, release physics at this player's feet.
   local q,f=p:K2_GetActorLocation(),p:GetActorForwardVector()
   local target={X=q.X+f.X*85,Y=q.Y+f.Y*85,Z=q.Z-20}
   item:K2_SetActorLocation(target,false,{},true)
   item.RootMeshComponent:K2_SetWorldLocation(target,false,{},true)
   item.RootMeshComponent:SetPhysicsLinearVelocity({X=0,Y=0,Z=0},false,FName('None'))
   item.RootMeshComponent:SetPhysicsAngularVelocityInDegrees({X=0,Y=0,Z=0},false,FName('None'))
  end
  if valid(item)then item:FlushNetDormancy();item:ForceNetUpdate()end
  if valid(worn)then changed(worn)end
 end
 function N.request(b,op,from,to,item)
  if B.pending then return end
  local pc=H.GetPlayerController();assert(N.access(pc,b),'Backpack unavailable')
  if not pc:HasAuthority()and N.view and op~='unequip'then
   assert(N.view.fresh(b),'Waiting for the host inventory; try again in a moment')
  end
  local d=N.data(b);local h=N.held(pc)
  N.sequence=(N.sequence or 0)+1
  local bag=N.actor(b)
  if not bag and same(N.worn(pc.PlayerControlled),b)then bag='w:'..b:GetFullName():match('^(%S+)')end
  local source=(op=='put'or op=='drophand')and assert(N.actor(h),'Held item is still syncing; try again')or S.token(d[from])
  local r={seq=N.sequence,bag=assert(bag,'Backpack is still syncing; try again'),op=op,from=from or -1,to=to or -1,source=source,target=S.token(d[to])}
  if op=='store'then r.source=assert(N.actor(item),'Item is still syncing; try again')end
  if pc:HasAuthority()then B.message=N.execute(pc,r)else
   B.pending=os.clock()+5;B.pendingRequest=r;B.pendingBag=b;B.pendingAccepted=false
   local ok,e=pcall(function()pc:ServerExecRPC(P.encode(r))end)
   if not ok then N.clearPending();error(e)end
   B.message='Waiting for host inventory update...';log('Backpack sent #'..r.seq..': '..r.op..' bag='..r.bag)
  end
 end
 function N.clearPending()
  B.pending=nil;B.pendingRequest=nil;B.pendingBag=nil;B.pendingAccepted=false
 end
 function N.confirmed()
  local r=B.pendingRequest;local b=B.pendingBag
  if not r then return false end
  local pc=H.GetPlayerController();if not valid(pc)then return false end
  if r.op=='unequip'then return not same(N.worn(pc.PlayerControlled),b)end
  if not valid(b)then return false end
  local d=N.data(b);local at=function(k)return N.token(d[k])end
  if r.op=='move'then return at(r.to)==r.source and at(r.from)==r.target end
  if r.op=='store'or r.op=='put'then return B.pendingAccepted and d[r.to]~=nil end
  if r.op=='attach'then return B.pendingAccepted and not d[r.from]and d[r.to]~=nil end
  if r.op=='detach'then return B.pendingAccepted and d[r.from]~=nil and N.attachments(d[r.from])=='' end
  if r.op=='drop'then return B.pendingAccepted and not d[r.from]end
  if r.op=='drophand'then return B.pendingAccepted and N.held(pc)==nil end
  if r.op=='take'then return B.pendingAccepted and not d[r.from]and N.held(pc)~=nil end
  return false
 end
 function N.finish(message)
  N.clearPending();B.message=message;B.feedbackUntil=os.clock()+4
  if B.ui.opened and valid(B.ui.widget)then B.ui.render()elseif B.notify then B.notify(message)end
 end
 function N.tick()
  if N.view then N.view.tick()end
  if B.pending then
   if N.confirmed()then N.finish('Inventory updated')
   elseif os.clock()>=B.pending then N.finish(B.pendingAccepted and 'Host saved the change; inventory is still syncing. Reopen Tab.'or 'No host response. Both players need the same mod version.')end
  end
  for key,v in pairs(N.pickups or{})do if os.clock()>=v.at then
   N.pickups[key]=nil
   if valid(v.pc)and valid(v.bag)then
    if not N.held(v.pc)and N.access(v.pc,v.bag)then v.bag:ExecutePrimaryAction(true,v.pc,v.bag.RootComponent,v.bag)end
    if v.pc:IsLocalPlayerController()and B.notify then
     B.notify(same(N.held(v.pc),v.bag)and 'Backpack moved to hands.'or 'Backpack is on the ground nearby; pick it up normally.')
    end
   end
  end end
 end
 local replyType='BAInventory'
 function N.reply(pc,r,ok,message)
  message=tostring(message):gsub('^.-:%d+: ',''):gsub('[\r\n|]',' '):sub(1,180)
  pc:ClientMessage('BAINV2R|'..r.seq..'|'..(ok and 'ok'or 'error')..'|'..message,FName(replyType),0)
 end
 function N.install()
  if not N.labelHook then
   local path='/Game/BP/Components/BP_InventoryComponent.BP_InventoryComponent_C:AddItemToSlot'
   if valid(StaticFindObject(path))then N.labelHook={RegisterHook(path,function(ctx,slot,item,destruct,force,added)
    local inv,p,k=ctx:get(),item:get(),slot:get()
    if valid(inv)and valid(p)and p:HasAuthority()and M.gyrocopter and M.gyrocopter.transport.blades.info(p)and inv.Slots:Contains(k)then N.remember(inv.Slots:Find(k):get(),p)end
   end)}end
  end
  if N.hook then return end
  if N.view then N.view.install()end
  -- Both directions are read-only observations. Never mutate engine-owned strings.
  N.replyHook={RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(ctx,msg,kind)
   local ok,text=pcall(function()if kind:get():ToString()==replyType then return msg:get():ToString()end end)
   if not ok or not text then return end
   local pc=ctx:get()
   local seq,status,message=text:match('^BAINV2R|(%d+)|(%a+)|([^|]+)$')
   seq=tonumber(seq);if not seq then return end
   enqueue(function()
    if not valid(pc)or not pc:IsLocalPlayerController()then return end
    if not B.pendingRequest or B.pendingRequest.seq~=seq then return end
    log('Backpack host reply #'..seq..': '..status..' '..message)
    if status=='error'then N.finish(message)
    elseif status=='ok'then
     B.pendingAccepted=true;B.pending=os.clock()+5;B.message=message..' - syncing inventory'
     if B.ui.opened and valid(B.ui.status)then B.ui.status:SetText(FText(B.message))end
    end
   end)
  end)}
  N.hook={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,msg)
   local ok,s=pcall(function()return msg:get():ToString()end)
   if not ok or #s>200 or s:sub(1,5)~='BAINV'then return end
   if (N.queuedRequests or 0)>=32 then return end;N.queuedRequests=(N.queuedRequests or 0)+1
   local pc=ctx:get()
   enqueue(function()
   N.queuedRequests=math.max(0,(N.queuedRequests or 1)-1)
   if not valid(pc)or not pc:HasAuthority()then return end
   if s:sub(1,7)=='BAINV1|'then
    enqueue(function()pc:ClientMessage('Backpacks need Beyond Apocolypse 0.7.2 on BOTH players.',FName('BeyondBackpack'),5)end);return
   end
   if s:sub(1,#P.prefix)~=P.prefix then return end
   local r=P.decode(s);if not r then return end
   local key=pc:GetAddress();local now=os.clock();N.rate=N.rate or{};N.last=N.last or{}
   -- One queued request per player. Replays return a reply without repeating mutation.
   local previous=N.last[key]
   if previous and previous.seq==r.seq then
    if previous.done then enqueue(function()N.reply(pc,r,previous.ok,previous.message)end)end;return
   end
   if previous and r.seq<previous.seq then
    enqueue(function()N.reply(pc,r,false,'Old inventory request ignored; try again')end);return
   end
   if previous and not previous.done or now<(N.rate[key]or 0)then
    enqueue(function()N.reply(pc,r,false,'Previous inventory request is still processing; try again')end);return
   end
   N.rate[key]=now+.12
   local result={seq=r.seq,done=false};N.last[key]=result
   log('Backpack request queued #'..r.seq..': '..r.op..' bag='..r.bag)
   enqueue(function()
    local ok,e=pcall(N.execute,pc,r);result.done=true;result.ok=ok;result.message=e
    log(ok and 'Backpack request complete: '..r.op or 'Backpack request rejected: '..tostring(e))
    if valid(pc)then local sent,why=pcall(N.reply,pc,r,ok,e);if not sent then log('Backpack reply failed: '..tostring(why))end end
   end)
   end)
  end)}
 end
 N.view=dofile(root..'/Scripts/backpack/view.lua')(B,M,N,root,H,valid,log)
 return N
end

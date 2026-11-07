-- Native flashlight model, replicated component markers and revision-bound state.
return function(M,root,H,valid,enqueue,log)
 local R={records={},last={},queued=0,seq=0};local J=dofile(root..'/Scripts/weapons/light_state.lua')(root,valid,log,M.statePath);R.journal=J
 local N=M.backpack.native;local game,mathlib,meshClass
 R.optic=dofile(root..'/Scripts/weapons/optic.lua')(M,R,root,valid,H)
 local prefix='BAWL1|';local marker='BA_RailLight_'
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function vec(x,y,z)return {X=x,Y=y,Z=z}end
 local function transform(x,y,z,s)return {Translation=vec(x,y,z),Rotation={X=0,Y=0,Z=0,W=1},Scale3D=vec(s or 1,s or 1,s or 1)}end
 R.mounts={ak=transform(35,0,-2.5,.52),m4=transform(25,0,-2.24,.52),hunting=transform(31,0,-2.12,.52),enfield=transform(37,0,-4.4,.52)}
 function R.flash(a)return valid(a)and a:GetFullName():match('^LampeTorche_C ')~=nil and not R.optic.item(a)end
 function R.definition(a)return M.weaponDefinition(a)end
 local function init()
  game=game or StaticFindObject('/Script/Engine.Default__GameplayStatics')
  mathlib=mathlib or StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
  meshClass=meshClass or StaticFindObject('/Script/Engine.StaticMeshComponent')
 end
 local function findMarker(a)
  init();for _,v in ipairs(a:K2_GetComponentsByClass(meshClass))do local c=v:get()
   if valid(c)and c.AttachSocketName:ToString():sub(1,#marker)==marker then return c end
  end
 end
 function R.has(a)
  if a:HasAuthority()then local id=M.guid(a);return id and J.state.light[id]end
  return findMarker(a)
 end
 function R.update(a,d)
  R.optic.update(a,d)
  init();local c=findMarker(a);local record=a:HasAuthority()and J.ready and J.state.light[M.guid(a)]or nil
  if a:HasAuthority()and not J.ready then return end
  if a:HasAuthority()and not record then
   local r=R.records[a:GetFullName()];if r and valid(r.beam)then r.beam:K2_DestroyComponent(a)end;R.records[a:GetFullName()]=nil
   if c then c:K2_DestroyComponent(a)end;return
  end
  if not c and record then
   local tr=mathlib:ComposeTransforms(R.mounts[d.Id],d.Transform())
   c=a:AddComponentByClass(meshClass,true,tr,false);assert(valid(c),'Cannot create flashlight mount')
   local model=LoadAsset('/Game/Safe_House/meshes/SM_desk_props_flashlight.SM_desk_props_flashlight');assert(valid(model),'Flashlight model unavailable');c:SetStaticMesh(model)
   c:SetCollisionEnabled(0);c:K2_AttachToComponent(a.SkeletalMesh,FName(marker..(record[2]==1 and'on'or'off')),0,0,0,false)
   c:K2_SetRelativeTransform(tr,false,{},true);c:SetIsReplicated(true);a:FlushNetDormancy();a:ForceNetUpdate()
  end
  if not valid(c)then local old=R.records[a:GetFullName()];if old and valid(old.beam)then old.beam:K2_DestroyComponent(a)end;R.records[a:GetFullName()]=nil;return end
  c:SetCastShadow(false)
  if record then
   local tag=marker..(record[2]==1 and'on'or'off')
   if c.AttachSocketName:ToString()~=tag then c:K2_AttachToComponent(a.SkeletalMesh,FName(tag),0,0,0,false);a:ForceNetUpdate()end
  end
  local key=a:GetFullName();local r=R.records[key]
  if not r or not same(r.marker,c)then if r and valid(r.beam)then r.beam:K2_DestroyComponent(a)end;r={actor=a,marker=c};R.records[key]=r end
  if not valid(r.beam)then
   -- Recover any native-saved beam rather than making another copy.
   for _,v in ipairs(a:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.SpotLightComponent')))do local light=v:get()
    if valid(light)and light.AttachSocketName:ToString()=='BA_RailBeam'then r.beam=light;break end
   end
   if not valid(r.beam)then r.beam=a:AddComponentByClass(StaticFindObject('/Script/Engine.SpotLightComponent'),true,transform(0,0,0),false)end
   r.beam:K2_AttachToComponent(c,FName('BA_RailBeam'),0,0,0,false);r.beam:K2_SetRelativeTransform(transform(d.Id=='enfield'and 88 or d.Id=='hunting'and 84 or 68,0,0),false,{},true)
   -- The .52-scale rail socket sits behind the muzzle. Put the emitter beyond
   -- each barrel in model space; retain shadows from the world and other actors.
   r.beam:SetUseInverseSquaredFalloff(false);r.beam:SetIntensityUnits(0);r.beam:SetLightFalloffExponent(2);r.beam:SetIESTexture(nil)
   r.beam:SetIntensity(450);r.beam:SetAttenuationRadius(3000);r.beam:SetInnerConeAngle(20);r.beam:SetOuterConeAngle(42)
   r.beam:SetLightColor({R=1,G=.94,B=.83,A=1},false);r.beam:SetCastShadows(true)
  end
  local visible=c.AttachSocketName:ToString()==marker..'on'
  if r.visible~=visible then r.beam:SetVisibility(visible,false);r.visible=visible end
 end
 function R.mount(gun,lamp)
  if R.optic.item(lamp)then return R.optic.mount(gun,lamp)end
  init();J.writable();assert(gun:HasAuthority()and lamp:HasAuthority(),'Host owns attachments')
  local d=assert(R.definition(gun),'Choose an equipped mod rifle');assert(R.flash(lamp),'Choose a flashlight')
  local id=assert(M.guid(gun));assert(not J.state.light[id],'This rifle already has a flashlight')
  assert(not valid(lamp:GetAttachParentActor())and not lamp.isAttached,'Flashlight is attached to something')
  local lightId=assert(M.guid(lamp),'Flashlight is still loading')
  J.state.light[id]={lightId,1}
  local ok,e=pcall(R.update,gun,d)
  if not ok then J.state.light[id]=nil;local c=findMarker(gun);if c then c:K2_DestroyComponent(gun)end;error(e)end
  assert(valid(findMarker(gun)),'Flashlight mount did not initialize')
  -- Consume the loose flashlight only after the persistent mount exists.
  lamp:K2_DestroyActor();return 'Flashlight attached'
 end
 function R.loose(pc,lamp)
  if not(R.flash(lamp)or R.optic.item(lamp))or valid(lamp:GetAttachParentActor())or lamp.isAttached then return false end
  local q,f=pc.PlayerControlled:K2_GetActorLocation(),lamp:K2_GetActorLocation();local dx,dy,dz=q.X-f.X,q.Y-f.Y,q.Z-f.Z
  if dx*dx+dy*dy+dz*dz>200*200 or not pc:LineOfSightTo(lamp,vec(0,0,0),false)then return false end
  for _,other in ipairs(FindAllOf('PlayerController')or{})do if valid(other)and same(N.held(other),lamp)then return false end end
  return true
 end
 function R.target(pc)
  if R.loose(pc,pc.ItemTargeted)then return pc.ItemTargeted end
  local out={};pc:GetItemSelected(out);if R.loose(pc,out.ItemSelected)then return out.ItemSelected end
 end
 function R.execute(pc,op,gunId,source)
  init();assert(pc:HasAuthority(),'Host owns weapon changes');local p=pc.PlayerControlled
  assert(valid(p)and p.IsLoaded and not p.BP_PlayerStats.IsDead and not p.BP_PlayerStats.IsDying and not valid(pc.Vehicle),'Player unavailable')
  assert(not game:GetGameInstance(pc).IsSaving,'Wait for the save to finish')
  local gun=p.ItemEquiped;assert(R.definition(gun)and N.actor(gun)==gunId,'Equipped rifle changed')
  if op=='drop'then N.dropHeld(pc,gun);return 'Rifle dropped'end
  if op=='slot'then
   local target=tonumber(source);local bag=N.worn(p)
   assert(target and target%1==0 and target>=0 and N.tier(bag)and target<N.tier(bag).hotbar,'Invalid hotbar slot')
   local inventory=bag.BP_InventoryComponent;local original=gun.LastSlot
   if original>=0 and original<inventory.NbSlot and same(gun.LastInventoryComponent,inventory)and inventory.Slots:Contains(original)then
    if M.weaponHandling and pc:IsLocalPlayerController()then M.weaponHandling.reset()end
    local out={};p:ServerAddItemToSlot(original,out);assert(out.Added,'Could not return rifle to its slot')
    -- Native storage leaves a physical-hand reference after unequipping.
    pc:RemoveItemInHand()
    if target~=original and inventory.Slots:Contains(target)then p:ServerGetItemFromSlot(target,true,true)end
   else p:UseSlot(target)end
   return 'Hotbar selected'
  end
  if op=='toggle'then
   J.writable();local row=assert(J.state.light[M.guid(gun)],'No flashlight attached');assert(source=='1'or source=='2')
   row[2]=tonumber(source);R.update(gun,R.definition(gun));return row[2]==1 and'Flashlight on'or'Flashlight off'
  end
  assert(op=='mount','Unknown weapon action');local lamp
  for _,kind in ipairs({'LampeTorche_C','Binocular_C'})do for _,a in ipairs(FindAllOf(kind)or{})do if N.actor(a)==source then lamp=a;break end end end
  assert(R.loose(pc,lamp),'Flashlight out of reach or in use');return R.mount(gun,lamp)
 end
 function R.request(op,slot)
  local gun,p,pc=M.weaponHandling.equipped();if not gun or pc.bShowMouseCursor or pc.HUD.ChatUI.TypeInChat or H.IsPauseMenu(pc)then return end
  local source='-'
  if op=='slot'then if M.backpack.ui.opened or M.overlayCapturesInput() then return end;source=tostring(slot)end
  if op=='light'then local lamp=R.target(pc)
   if lamp and(R.optic.item(lamp)and not R.optic.has(gun)or R.flash(lamp)and not R.has(gun))then op='mount';source=assert(N.actor(lamp),'Flashlight still syncing')
   else op='toggle';local c=findMarker(gun);assert(c,'Look at a loose flashlight and press L');source=c.AttachSocketName:ToString()==marker..'on'and'2'or'1'end
  end
  local id=assert(N.actor(gun),'Rifle still syncing')
  if pc:HasAuthority()then local result=R.execute(pc,op,id,source);if op~='slot'then M.backpack.notify(result)end
  else R.seq=R.seq+1;pc:ServerExecRPC(prefix..R.seq..'|'..op..'|'..id..'|'..source)end
 end
 function R.tick(p)
  R.optic.tick()
  init();local pc=H.GetPlayerController();if not valid(pc)or not valid(p)then return end
  if pc:HasAuthority()and not J.ready then J.load(game:GetGameInstance(pc).MainSaveGame)end
  if not R.hook then R.hook={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,msg)
   local ok,s=pcall(function()return msg:get():ToString()end);if not ok or #s>120 or s:sub(1,#prefix)~=prefix or R.queued>=16 then return end
   local caller=ctx:get();R.queued=R.queued+1
   enqueue(function()
    R.queued=math.max(0,R.queued-1);if not valid(caller)or not caller:HasAuthority()then return end
    local seq,op,gid,source=s:match('^BAWL1|(%d+)|(%a+)|(n:%d+)|([^|]+)$');seq=tonumber(seq)
    if not seq or seq>2147483647 or not valid(caller.PlayerControlled)then return end
    if not M.backpack.policy.actor(gid)or not(op=='drop'and source=='-'or op=='mount'and M.backpack.policy.actor(source)or op=='toggle'and(source=='1'or source=='2')or op=='slot'and source:match('^[0-5]$'))then return end
    local key=caller:GetAddress();local prev=R.last[key];if prev and(seq<=prev.seq or os.clock()-prev.at<.15)then return end
    R.last[key]={seq=seq,at=os.clock()};local worked,e=pcall(R.execute,caller,op,gid,source)
    if op~='slot'or not worked then caller:ClientMessage(tostring(e):gsub('^.-:%d+: ',''),FName('BeyondWeapon'),4)end
    if not worked then log('Weapon action rejected: '..tostring(e))end
   end)
  end)}end
  for key,r in pairs(R.records)do if not valid(r.actor)then R.records[key]=nil end end
 end
 function R.reset()R.records={};R.last={};R.optic.reset();J.reset()end
 dofile(root..'/Scripts/weapons/detach.lua')(M,R,valid)
 return R
end

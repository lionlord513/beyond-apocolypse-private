-- Cosmetic followers share native animation. Gameplay skeletons are never replaced.
return function(M,root,H,valid,log)
 local R={records={},cache={}}
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local I={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local skinned=StaticFindObject('/Script/Engine.SkeletalMeshComponent')
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function offset(o,name)local value;o:ForEachProperty(function(p)if p:GetFName():ToString()==name then value=p:GetOffset_Internal()end end);assert(value,'Missing player-model field '..name);return value end
 local function find(kind,address)for _,o in ipairs(FindAllOf(kind)or{})do if valid(o)and o:GetAddress()==address then return o end end end
 function R.load(context,kind,source)
  local entry=R.cache[kind];if entry and valid(entry.holder)and valid(entry.mesh)then return entry end
  local read=assert(package.loadlib(root..'/assets/native/BeyondImports.dll','ba_load_asset'))
  local build=assert(package.loadlib(root..'/assets/native/BeyondImports.dll','ba_load_lods'))
  local lib=StaticFindObject('/Script/glTFRuntime.Default__glTFRuntimeFunctionLibrary')
  local fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeFunctionLibrary:glTFLoadAssetFromFilename')
  local cfg=StaticFindObject('/Script/glTFRuntime.glTFRuntimeConfig')
  local address,why=read(lib:GetAddress(),fn:GetAddress(),offset(fn,'LoaderConfig'),offset(fn,'ReturnValue'),root..'/assets/player_models/soldier-'..kind..'.glb',offset(cfg,'SceneScale'),offset(cfg,'TransformBaseType'))
  assert(address and address~=0,why or 'Soldier import failed')
  local asset=assert(find('glTFRuntimeAsset',address),'Soldier asset unavailable')
  local native=source:GetSkinnedAsset();assert(valid(native),'Native animation rig unavailable')
  fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeAsset:LoadSkeletalMeshLODs');cfg=StaticFindObject('/Script/glTFRuntime.glTFRuntimeSkeletalMeshConfig')
  address,why=build(asset:GetAddress(),fn:GetAddress(),offset(fn,'SkeletalMeshConfig'),offset(fn,'ReturnValue'),native.Skeleton:GetAddress(),offset(cfg,'Skeleton'),-1)
  assert(address and address~=0,why or 'Soldier skeleton import failed')
  local mesh=assert(find('SkeletalMesh',address),'Soldier mesh unavailable')
  local holder=game:BeginDeferredActorSpawnFromClass(context,StaticFindObject('/Script/Engine.SkeletalMeshActor'),I,1,nil,0)
  assert(valid(holder),'Player-model cache unavailable');game:FinishSpawningActor(holder,I,0)
  holder:SetReplicates(false);holder:SetActorHiddenInGame(true);holder:SetActorEnableCollision(false);holder:SetActorTickEnabled(false)
  holder.SkeletalMeshComponent:SetSkinnedAssetAndUpdate(mesh,true);holder.SkeletalMeshComponent:SetComponentTickEnabled(false)
  entry={holder=holder,mesh=mesh};R.cache[kind]=entry
  local material=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(holder,LoadAsset('/MasterWeapon/Materials/Weapons/MAT_ArK47.MAT_ArK47'),FName('BA_Soldier_'..kind),0)
  assert(valid(material),'Soldier material unavailable')
  local images=dofile(root..'/Scripts/weapons/pbr_images.lua')(root,valid)('assets/player_models/textures.gltf',128)
  for param,texture in pairs(images)do material:SetTextureParameterValue(FName(param),texture)end
  material:SetScalarParameterValue(FName('AODarkness'),1);material:SetScalarParameterValue(FName('DiffuseBrightness'),1.35);material:SetScalarParameterValue(FName('RoughnessBrightness'),1)
  holder.SkeletalMeshComponent:SetMaterial(0,material);entry.material=material
  log('SciFi Soldier '..kind..' loaded once; shared native pose and three detail levels')
  return entry
 end
 local faceParts={LeftEye=true,RightEye=true,TearDuct=true,eyelashes=true,Brows=true,EyeOcclusion=true}
 function R.capture(r)
  r.parts={};local skeleton=r.source:GetSkinnedAsset().Skeleton
  local fps=r.isPawn and r.actor.FpsArm or nil
  for _,v in ipairs(r.actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.MeshComponent')))do
   local c=v:get();local name=c:GetFName():ToString();local take=faceParts[name]==true
   if c:IsA(skinned)and not same(c,r.arms)and not same(c,r.firstBody)and not same(c,r.follower)and not same(c,fps)then
    local asset=c:GetSkinnedAsset();take=valid(asset)and same(asset.Skeleton,skeleton)or take
    if name:find('man_Edit_Man_',1,true)then take=true end
   end
   if take then r.parts[#r.parts+1]={component=c,visible=c.bVisible,hidden=c.bHiddenInGame,shadow=c.CastShadow}end
  end
 end
 local function hideParts(parts)
  for _,part in ipairs(parts or{})do local c=part.component;if valid(c)then
   if c.bVisible then c:SetVisibility(false,false)end
   if not c.bHiddenInGame then c:SetHiddenInGame(true,false)end
   if c.CastShadow then c:SetCastShadow(false)end
  end end
 end
 local function restoreParts(parts)
  for _,part in ipairs(parts or{})do if valid(part.component)then part.component:SetVisibility(part.visible,false);part.component:SetHiddenInGame(part.hidden,false);part.component:SetCastShadow(part.shadow)end end
 end
 function R.hide(r)
  hideParts(r.parts);for _,item in pairs(r.wearables or{})do hideParts(item.parts)end
 end
 function R.syncWearables(r)
  if not r.isPawn then return end
  r.wearables=r.wearables or{};local seen={}
  local attached={};r.actor:GetAttachedActors(attached,true,false)
  local wearable=StaticFindObject('/Game/BP/Items/Master/ItemWearable.ItemWearable_C')
  for _,value in ipairs(attached)do
   local actor=value:get();if valid(actor)and actor:IsA(wearable)and same(actor.PlayerEquiped,r.actor)then
   local key=actor:GetFullName();seen[key]=true;local item=r.wearables[key]
   if not item or not same(item.actor,actor)then
    item={actor=actor,parts={}};r.wearables[key]=item
    for _,v in ipairs(actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.MeshComponent')))do local c=v:get()
     item.parts[#item.parts+1]={component=c,visible=c.bVisible,hidden=c.bHiddenInGame,shadow=c.CastShadow}
    end
   end
   hideParts(item.parts)
   end
  end
  for key,item in pairs(r.wearables)do if not seen[key]then restoreParts(item.parts);r.wearables[key]=nil end end
 end
 local clothing={sleeveless_shirt=true,shirt=true,pants=true,shoes1=true,tie=true,shoes_formal=true,Legs=true,arms_feet=true,Chest=true}
 function R.clothingChanged(r)
  local old={};for _,part in ipairs(r.parts or{})do old[part.component:GetAddress()]=part end
  R.capture(r)
  for _,part in ipairs(r.parts)do local saved=old[part.component:GetAddress()]
   if saved then part.shadow=saved.shadow;part.hidden=saved.hidden;if not clothing[part.component:GetFName():ToString()]then part.visible=saved.visible end end
  end
 end
 function R.restore(r)
  restoreParts(r.parts)
 end
 local function follower(actor,source,kind)
  local entry=R.load(actor,kind,source)
  local c=actor:AddComponentByClass(skinned,true,I,false);assert(valid(c),'Cannot attach soldier cosmetic')
  local ok,why=pcall(function()
   c:SetIsReplicated(false);c:SetCollisionEnabled(0);c:K2_AttachToComponent(source,FName('None'),0,0,0,false);c:K2_SetRelativeTransform(I,false,{},true)
   c:SetSkinnedAssetAndUpdate(entry.mesh,true);c:SetMaterial(0,entry.material);c:SetLeaderPoseComponent(source,true,false)
   if kind=='arms'or kind=='first_body'then c:SetForcedLOD(1)end
   c:SetCastShadow(kind=='body');if kind=='body'then c:SetCastHiddenShadow(true)end
  end)
  if not ok then c:K2_DestroyComponent(actor);error(why)end
  return c
 end
 function R.apply(actor,source)
  local key=actor:GetFullName();local old=R.records[key]
  if old and same(old.actor,actor)and valid(old.follower)then return old end
  source=source or actor.Mesh;assert(valid(source),'Player body unavailable')
  local r={actor=actor,key=key,source=source,tick=source.VisibilityBasedAnimTickOption,isPawn=actor:IsA(StaticFindObject('/Game/BP/Player/PlayerBase.PlayerBase_C'))}
  r.follower=follower(actor,source,'body');R.records[key]=r
  local ok,why=pcall(function()R.capture(r);source.VisibilityBasedAnimTickOption=0;R.syncWearables(r);R.hide(r)end)
  if not ok then R.remove(r);error(why)end
  return r
 end
 function R.remove(key)
  local r=type(key)=='table'and key or R.records[key];if not r or r.removed then return end;r.removed=true
  if r.ragdoll then R.remove(r.ragdoll)end
  for _,item in pairs(r.wearables or{})do restoreParts(item.parts)end
  R.restore(r)
  if valid(r.source)then r.source.VisibilityBasedAnimTickOption=r.tick end
  if r.armSource and valid(r.armSource)then
   r.armSource:SetRenderInMainPass(r.armMain);r.armSource:SetRenderInDepthPass(r.armDepth);r.armSource:SetCastShadow(r.armShadow);r.armSource.VisibilityBasedAnimTickOption=r.armTick
  end
  if valid(r.follower)then r.follower:K2_DestroyComponent(r.actor)end
  if valid(r.arms)then r.arms:K2_DestroyComponent(r.actor)end
  if valid(r.firstBody)then r.firstBody:K2_DestroyComponent(r.actor)end
  R.records[r.key]=nil
 end
 function R.syncRagdoll(r)
  if not r.isPawn then return end
  local actor=r.actor.RagdollCharacter
  if r.ragdoll and(not valid(actor)or not same(r.ragdoll.actor,actor))then R.remove(r.ragdoll);r.ragdoll=nil end
  if valid(actor)and not r.ragdoll then
   local skeleton=r.source:GetSkinnedAsset().Skeleton
   for _,v in ipairs(actor:K2_GetComponentsByClass(skinned))do local source=v:get();local mesh=source:GetSkinnedAsset()
    if valid(mesh)and same(mesh.Skeleton,skeleton)then r.ragdoll=R.apply(actor,source);break end
   end
  end
  if r.ragdoll then R.hide(r.ragdoll)end
 end
 function R.update(r,localPlayer,pc)
  if not same(r.actor,localPlayer)then
   if r.follower.bOwnerNoSee then r.follower:SetOwnerNoSee(false)end
   if not r.follower.bVisible then r.follower:SetVisibility(true,false)end
   if r.localOwner then if valid(r.arms)then r.arms:SetVisibility(false,false)end;if valid(r.firstBody)then r.firstBody:SetVisibility(false,false)end;r.localOwner=false end
   return
  end
  r.localOwner=true;r.view=r.view or{};pc:IsInCameraFPS(r.view)
  local fps=r.view.IsFPS==true;R.hide(r)
  if r.follower.bOwnerNoSee~=fps then r.follower:SetOwnerNoSee(fps)end
  if r.follower.bVisible==fps then r.follower:SetVisibility(not fps,false)end;r.fps=fps
  if not valid(r.firstBody)then r.firstBody=follower(localPlayer,r.source,'first_body')end
  if r.firstBody.bOwnerNoSee then r.firstBody:SetOwnerNoSee(false)end
  if r.firstBody.bVisible~=fps then r.firstBody:SetVisibility(fps,false)end
  local src=localPlayer.FpsArm
  if valid(src)and not valid(r.arms)then
   r.arms=follower(localPlayer,src,'arms');r.armSource=src;r.armMain=src.bRenderInMainPass;r.armDepth=src.bRenderInDepthPass;r.armShadow=src.CastShadow;r.armTick=src.VisibilityBasedAnimTickOption;src.VisibilityBasedAnimTickOption=0
  end
  if valid(r.arms)then
   -- Native hands are also used for some third-person interactions. Follow the
   -- source visibility instead of making a separate camera-mode assumption.
   local show=not src.bHiddenInGame and not localPlayer.BP_PlayerStats.IsDead
   if r.showArms~=show then r.arms:SetVisibility(show,false);r.arms:SetHiddenInGame(not show,false);r.showArms=show end
   -- The game toggles native visibility while handling guns. Keep those flags
   -- as its animation/interaction inputs, and suppress only the original draw.
   if src.bRenderInMainPass then src:SetRenderInMainPass(false)end
   if src.bRenderInDepthPass then src:SetRenderInDepthPass(false)end
   if src.CastShadow then src:SetCastShadow(false)end
  end
 end
 function R.reset()
  local rows={};for _,r in pairs(R.records)do rows[#rows+1]=r end;for _,r in ipairs(rows)do R.remove(r)end
  for _,c in pairs(R.cache)do if valid(c.holder)then c.holder:K2_DestroyActor()end end;R.cache={}
 end
 return R
end

-- Transient local cosmetics; native zombies retain navigation, damage and replication.
return function(root,valid,log)
 local V={};local cache,mesh,failed;local clips={};local tracked={}
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local function prop(o,name)
  local found;o:ForEachProperty(function(p)if p:GetFName():ToString()==name then found=p:GetOffset_Internal()end end)
  assert(found,'Missing import field '..name);return found
 end
 local function object(kind,address)
  for _,o in ipairs(FindAllOf(kind)or{})do if valid(o)and o:GetAddress()==address then return o end end
 end
 local function load(context)
  local complete=valid(cache)and valid(mesh)and #clips==6
  for _,clip in ipairs(clips)do if not valid(clip)then complete=false end end
  if complete then return mesh end
  if valid(cache)then cache:K2_DestroyActor()end
  cache=nil;mesh=nil;clips={}
  assert(not failed,failed)
  local path=root..'/assets/native/BeyondImports.dll'
  local read=assert(package.loadlib(path,'ba_load_asset'))
  local build=assert(package.loadlib(path,'ba_load_mesh'))
  local lib=StaticFindObject('/Script/glTFRuntime.Default__glTFRuntimeFunctionLibrary')
  local fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeFunctionLibrary:glTFLoadAssetFromFilename')
  local config=StaticFindObject('/Script/glTFRuntime.glTFRuntimeConfig')
  local address,err=read(lib:GetAddress(),fn:GetAddress(),prop(fn,'LoaderConfig'),prop(fn,'ReturnValue'),root..'/assets/mechanic/mechanic.glb',prop(config,'SceneScale'),prop(config,'TransformBaseType'))
  assert(address and address~=0,err or 'Import helper requires the bundled UE4SS version')
  local asset=assert(object('glTFRuntimeAsset',address),'No loaded Mechanic asset')
  fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeAsset:LoadSkeletalMesh')
  config=StaticFindObject('/Script/glTFRuntime.glTFRuntimeSkeletalMeshConfig')
  address,err=build(asset:GetAddress(),fn:GetAddress(),prop(fn,'SkeletalMeshConfig'),prop(fn,'ReturnValue'),0,prop(config,'Skeleton'),-1)
  assert(address and address~=0,err or 'Mechanic mesh import failed')
  mesh=assert(object('SkeletalMesh',address),'No Mechanic mesh')
  local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
  cache=game:BeginDeferredActorSpawnFromClass(context,StaticFindObject('/Script/Engine.SkeletalMeshActor'),identity,1,nil,0)
  assert(valid(cache),'Mechanic cache actor unavailable');game:FinishSpawningActor(cache,identity,0)
  cache:SetReplicates(false);cache:SetActorHiddenInGame(true);cache:SetActorEnableCollision(false);cache:SetActorTickEnabled(false)
  cache.SkeletalMeshComponent:SetSkinnedAssetAndUpdate(mesh,true)
  cache.SkeletalMeshComponent:SetComponentTickEnabled(false)
  local materialLibrary=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
  local mat=materialLibrary:CreateDynamicMaterialInstance(cache,LoadAsset('/Game/YI_ModularZombies/Materials/ZombieM02/Clothing/LongJeans/03KhakiClean/MI_Clth_LongJeans_M02_03.MI_Clth_LongJeans_M02_03'),FName('BA_Mechanic'),0)
  assert(valid(mat),'Mechanic material unavailable')
  for channel,param in ipairs({'0.BC','2.AO_R_M','1.N'})do
   local tex=asset:LoadImage(channel-1,{Compression=channel==3 and 1 or 0,Group=0,bSRGB=channel==1,MaxWidth=1024,MaxHeight=1024,bVerticalFlip=false,bForceHDR=false,bCompressMips=false,bStreaming=true,LODBias=0,bForceAutoDetect=true,ForcePixelFormat=0})
   assert(valid(tex),'Missing Mechanic texture');mat:SetTextureParameterValue(FName(param),tex)
  end
  for i=0,cache.SkeletalMeshComponent:GetNumMaterials()-1 do cache.SkeletalMeshComponent:SetMaterial(i,mat)end
  local animate=assert(package.loadlib(root..'/assets/native/BeyondCreature.dll','ba_load_animation'))
  fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeAsset:LoadSkeletalAnimation')
  config=StaticFindObject('/Script/glTFRuntime.glTFRuntimeSkeletalAnimationConfig')
  -- Export order is checked by the asset test; state IDs are independent of it.
  for i,index in ipairs({4,5,3,2,0,1})do
   address,err=animate(asset:GetAddress(),fn:GetAddress(),mesh:GetAddress(),index,prop(fn,'SkeletalMesh'),prop(fn,'AnimationIndex'),prop(fn,'SkeletalAnimationConfig'),prop(fn,'ReturnValue'),prop(config,'RootNodeIndex'),prop(config,'FramesPerSecond'))
   assert(address and address~=0,err or 'Mechanic animation import failed')
   local clip=assert(object('AnimSequence',address),'No imported animation')
   assert(clip.SequenceLength>0,'Empty Mechanic animation')
   -- UPROPERTY references keep transient animation assets alive across UE GC.
   local holder=cache:AddComponentByClass(StaticFindObject('/Script/Engine.SkeletalMeshComponent'),true,identity,false)
   assert(valid(holder),'Animation cache unavailable');holder:SetCollisionEnabled(0);holder:SetIsReplicated(false)
   holder:SetSkinnedAssetAndUpdate(mesh,true);holder:PlayAnimation(clip,true);holder:SetComponentTickEnabled(false)
   clips[i]=clip
  end
  log('Mechanic ready: original rig and all six animations')
  return mesh
 end
 function V.ready(context)
  if failed then return false,failed end
  local ok,result=pcall(load,context)
  if not ok then failed=tostring(result);log('Mechanic import unavailable: '..failed)end
  return ok,result
 end
 function V.create(actor,parent)
  assert(V.ready(actor));local skin=actor:AddComponentByClass(StaticFindObject('/Script/Engine.SkeletalMeshComponent'),true,identity,false)
  assert(valid(skin),'Mechanic skin unavailable')
  skin:SetIsReplicated(false);skin:SetCollisionEnabled(0)
  if valid(parent)then skin:K2_AttachToComponent(parent,FName('None'),0,0,0,false)end
  skin:SetSkinnedAssetAndUpdate(mesh,true)
  for i=0,cache.SkeletalMeshComponent:GetNumMaterials()-1 do skin:SetMaterial(i,cache.SkeletalMeshComponent:GetMaterial(i))end
  skin.VisibilityBasedAnimTickOption=0;skin:SetCullDistance(90000);skin:SetBoundsScale(4)
  return skin,clips
 end
 function V.present(z,marker,now)
  local id=z:GetFullName();local rec=tracked[id]
  if not rec or not valid(rec.actor)or not valid(rec.skin)or rec.actor:GetAddress()~=z:GetAddress()then
   local skin=V.create(z,z.RootComponent)
   local half=z.CapsuleComponent:GetScaledCapsuleHalfHeight()
   skin:K2_SetRelativeTransform({Translation={X=0,Y=0,Z=-half},Rotation={X=0,Y=0,Z=-.70710678118655,W=.70710678118655},Scale3D={X=1,Y=1,Z=1}},false,{},true)
   rec={actor=z,skin=skin};tracked[id]=rec
  end
  local meta=marker.RelativeScale3D;local index=math.floor(meta.X+.5)
  if index<1 or index>6 then return end
  local rate=math.max(.25,math.min(4,meta.Y));local start=meta.Z-1
  if rec.index~=index or rec.start~=start then
   local clip=clips[index];assert(valid(rec.skin)and valid(clip),'Mechanic animation expired during world transition')
   local loop=index==1 or index==2
   rec.skin:PlayAnimation(clip,loop);rec.skin:SetPlayRate(rate)
   local position=math.max(0,now-start)*rate
   position=loop and position%clip.SequenceLength or math.min(position,clip.SequenceLength)
   rec.skin:SetPosition(position,false);rec.index=index;rec.start=start
  end
  z.Mesh.VisibilityBasedAnimTickOption=0
  for _,v in ipairs(z:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.SkinnedMeshComponent')))do
   local part=v:get();if valid(part)and part:GetAddress()~=rec.skin:GetAddress()then part:SetVisibility(false,false)end
  end
 end
 function V.reset()
  if valid(cache)then cache:K2_DestroyActor()end
  cache=nil;mesh=nil;clips={};tracked={};failed=nil
 end
 function V.prune()for k,r in pairs(tracked)do if not valid(r.actor)then tracked[k]=nil end end end
 V.load=load;V.clips=function()return clips end
 return V
end

-- Local cosmetics on native zombies. Only a tiny marker component is replicated;
-- transient imported meshes never enter the network or the native save system.
return function(root,c,valid,log)
 local H={};local cache,mesh,tracked,failed=nil,nil,{},nil
 local markerName='BA_Hazmat_Variant_v1'
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local function prop(o,name)
  local found;o:ForEachProperty(function(p)if p:GetFName():ToString()==name then found=p:GetOffset_Internal()end end)
  assert(found,'Missing import field '..name);return found
 end
 local function object(kind,address)
  for _,o in ipairs(FindAllOf(kind)or{})do if valid(o)and o:GetAddress()==address then return o end end
 end
 local function load(context)
  if valid(cache)and valid(mesh)then return mesh end
  assert(not failed,failed)
  local path=root..'/assets/native/BeyondImports.dll'
  local read=assert(package.loadlib(path,'ba_load_asset'))
  local build=assert(package.loadlib(path,'ba_load_lods'))
  local lib=StaticFindObject('/Script/glTFRuntime.Default__glTFRuntimeFunctionLibrary')
  local fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeFunctionLibrary:glTFLoadAssetFromFilename')
  local config=StaticFindObject('/Script/glTFRuntime.glTFRuntimeConfig')
  local address,err=read(lib:GetAddress(),fn:GetAddress(),prop(fn,'LoaderConfig'),prop(fn,'ReturnValue'),root..'/assets/hazmat/hazmat.glb',prop(config,'SceneScale'),prop(config,'TransformBaseType'))
  assert(address and address~=0,err or 'Import helper requires the bundled UE4SS version')
  local asset=assert(object('glTFRuntimeAsset',address),'No loaded Hazmat asset')
  fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeAsset:LoadSkeletalMeshLODs')
  config=StaticFindObject('/Script/glTFRuntime.glTFRuntimeSkeletalMeshConfig')
  local native=LoadAsset('/Game/BP/Player/Zombies/BP_Zombie_M01.BP_Zombie_M01_C'):GetCDO().Mesh:GetSkinnedAsset()
  address,err=build(asset:GetAddress(),fn:GetAddress(),prop(fn,'SkeletalMeshConfig'),prop(fn,'ReturnValue'),native.Skeleton:GetAddress(),prop(config,'Skeleton'),-1)
  assert(address and address~=0,err or 'Hazmat mesh import failed')
  mesh=assert(object('SkeletalMesh',address),'No Hazmat mesh')
  local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
  cache=game:BeginDeferredActorSpawnFromClass(context,StaticFindObject('/Script/Engine.SkeletalMeshActor'),identity,1,nil,0)
  assert(valid(cache),'Hazmat cache actor unavailable');game:FinishSpawningActor(cache,identity,0)
  cache:SetReplicates(false);cache:SetActorHiddenInGame(true);cache:SetActorEnableCollision(false);cache:SetActorTickEnabled(false)
  cache.SkeletalMeshComponent:SetSkinnedAssetAndUpdate(mesh,true)
  cache.SkeletalMeshComponent:SetComponentTickEnabled(false)
  local materials={}
  local materialLibrary=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
  for index=0,1 do
   local path=index==0 and '/Game/YI_ModularZombies/Materials/ZombieM02/Clothing/LongJeans/03KhakiClean/MI_Clth_LongJeans_M02_03.MI_Clth_LongJeans_M02_03'
    or '/Game/YI_ModularZombies/Materials/ZombieM01/Head01/01Skin01Default/MI_Head01_M01_01.MI_Head01_M01_01'
   local mat=materialLibrary:CreateDynamicMaterialInstance(cache,LoadAsset(path),FName('BA_Hazmat_'..index),0)
   assert(valid(mat),'Hazmat material unavailable')
   local params=index==0 and {'0.BC','2.AO_R_M','1.N'}or{'0. Albedo','0. AO_R_M','0. Normal'}
   for channel,param in ipairs(params)do
    -- POD config: no maps, strings or opaque delegates. Native texture import
    -- supplies correct color space, normal sampling and a bounded texture size.
    local tex=asset:LoadImage(index*3+channel-1,{Compression=channel==3 and 1 or 0,Group=0,bSRGB=channel==1,MaxWidth=1024,MaxHeight=1024,bVerticalFlip=false,bForceHDR=false,bCompressMips=false,bStreaming=true,LODBias=0,bForceAutoDetect=true,ForcePixelFormat=0})
    assert(valid(tex),'Missing Hazmat texture '..param);mat:SetTextureParameterValue(FName(param),tex)
   end
   if index==1 then mat:SetVectorParameterValue(FName('0.Albedo_Tint'),{R=1,G=1,B=1,A=1})end
   materials[index+1]=mat
  end
  for i=0,cache.SkeletalMeshComponent:GetNumMaterials()-1 do cache.SkeletalMeshComponent:SetMaterial(i,materials[i%2+1])end
  log('Hazmat mesh ready: native zombie animations, three detail levels')
  return mesh
 end
 function H.ready(context)
  if failed then return false,failed end
  local ok,result=pcall(load,context)
  if not ok then failed=tostring(result);log('Hazmat unavailable; native zombies retained: '..failed)end
  return ok,result
 end
 local function marker(z)
  local cls=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
  for _,v in ipairs(z:K2_GetComponentsByClass(cls))do
   local component=v:get()
   if valid(component)and component.AttachSocketName:ToString():lower()==markerName:lower()then return component end
  end
 end
 function H.mark(z)
  assert(z:HasAuthority(),'Hazmat selection belongs to the host')
  local ok,err=H.ready(z);if not ok then return false,err end
  if not marker(z)then
   local component=z:AddComponentByClass(StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent'),true,identity,false)
   assert(valid(component),'Cannot create Hazmat marker')
   component:SetCollisionEnabled(0);component:SetVisibility(false,false)
   component:K2_AttachToComponent(z.Mesh,FName(markerName),0,0,0,false)
   component:SetIsReplicated(true);z:FlushNetDormancy();z:ForceNetUpdate()
  end
  return true
 end
 local function apply(z)
  local name=z:GetFullName();local rec=tracked[name]
  if rec and valid(rec.actor)and rec.actor:GetAddress()==z:GetAddress()and valid(rec.follower)then return rec end
  assert(valid(z.Mesh),'Zombie mesh unavailable')
  local follower=z:AddComponentByClass(StaticFindObject('/Script/Engine.SkeletalMeshComponent'),true,identity,false)
  assert(valid(follower),'Cannot create Hazmat skin')
  local ok,err=pcall(function()
   follower:SetIsReplicated(false);follower:SetCollisionEnabled(0)
   follower:K2_AttachToComponent(z.Mesh,FName('None'),0,0,0,false)
   follower:K2_SetRelativeTransform(identity,false,{},true)
   follower:SetSkinnedAssetAndUpdate(load(z),true)
   for i=0,cache.SkeletalMeshComponent:GetNumMaterials()-1 do follower:SetMaterial(i,cache.SkeletalMeshComponent:GetMaterial(i))end
   follower:SetLeaderPoseComponent(z.Mesh,true,false)
   follower:SetCullDistance(c.DrawMeters*100)
  end)
  if not ok then follower:K2_DestroyComponent(z);error(err)end
  -- Keep the native skeleton and physics for movement, attacks and ragdoll.
  z.Mesh.VisibilityBasedAnimTickOption=0
  rec={actor=z,follower=follower};tracked[name]=rec;return rec
 end
 function H.tick(player)
  if failed then return end
  local position=player:K2_GetActorLocation()
  for _,z in ipairs(FindAllOf('BP_Zombie_C')or{})do if valid(z)and marker(z)then
   local ok,err=pcall(function()
    local r=apply(z)
    local now=os.clock()
    if not r.partsAt or now>=r.partsAt then
     r.partsAt=now+3
     for _,v in ipairs(z:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.SkinnedMeshComponent')))do
      local part=v:get();if part:GetAddress()~=r.follower:GetAddress()then part:SetVisibility(false,false)end
     end
    end
    local q=z:K2_GetActorLocation();local distance=math.sqrt((q.X-position.X)^2+(q.Y-position.Y)^2+(q.Z-position.Z)^2)/100
    local lod=distance<40 and 1 or(distance<110 and 2 or 3)
    if r.lod~=lod then r.follower:SetForcedLOD(lod);r.lod=lod end
    local interval=distance>110 and 0.1 or 0
    if r.interval~=interval then z.Mesh:SetComponentTickInterval(interval);r.interval=interval end
   end)
   if not ok then failed=tostring(err);log('Hazmat cosmetic update stopped: '..failed);break end
  end end
  for name,r in pairs(tracked)do if not valid(r.actor)then tracked[name]=nil end end
 end
 function H.reset()
  if valid(cache)then cache:K2_DestroyActor()end
  cache=nil;mesh=nil;tracked={};failed=nil
 end
 H.markerName=markerName;H.load=load
 return H
end

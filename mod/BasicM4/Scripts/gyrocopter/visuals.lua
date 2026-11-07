return function(root,valid)
 local V={};local geom={};local mat;local carrierMat;local plasticNormal,plasticORM,plasticDirt
 V.prune=dofile(root..'/Scripts/gyrocopter/prune_visuals.lua')(valid)
 local cls=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local pivots={plastic={X=0,Y=0,Z=122.4},body={X=0,Y=0,Z=122.4},rotor={X=12.9,Y=0,Z=237.2},propeller={X=-50.2,Y=0,Z=113.3},nose={X=144.4,Y=0,Z=12.9},left={X=13.6,Y=-87.9,Z=12.8},right={X=13.6,Y=87.9,Z=12.8},tail={X=-138.2,Y=0,Z=25.2}}
 local function textures(carrier)
  local function prop(o,name)local n;o:ForEachProperty(function(p)if p:GetFName():ToString()==name then n=p:GetOffset_Internal()end end);assert(n,'Missing image loader field');return n end
  local load=assert(package.loadlib(root..'/assets/native/BeyondImports.dll','ba_load_asset'))
  local lib=StaticFindObject('/Script/glTFRuntime.Default__glTFRuntimeFunctionLibrary')
  local fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeFunctionLibrary:glTFLoadAssetFromFilename')
  local cfg=StaticFindObject('/Script/glTFRuntime.glTFRuntimeConfig')
  local address=load(lib:GetAddress(),fn:GetAddress(),prop(fn,'LoaderConfig'),prop(fn,'ReturnValue'),root..'/assets/gyrocopter/'..(carrier=='plastic'and 'plastic-textures.gltf'or carrier and 'carrier-textures.gltf'or 'textures.gltf'),prop(cfg,'SceneScale'),prop(cfg,'TransformBaseType'))
  for _,asset in ipairs(FindAllOf('glTFRuntimeAsset')or{})do if asset:GetAddress()==address then return asset end end
  error('Aircraft texture import failed')
 end
 local function material(a,carrier)
  local cached;if carrier then cached=carrierMat else cached=mat end;if valid(cached)then return cached end
  local lib=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
  local created=lib:CreateDynamicMaterialInstance(a,LoadAsset('/MasterWeapon/Materials/Weapons/MAT_ArK47.MAT_ArK47'),FName(carrier and 'BA_HeliTrailer'or 'BA_Hornet'),0)
  local asset=textures(carrier)
  for i,key in ipairs({'Diffuse','NormalMap','RoughnessMap','MetalMap'})do
   local tex=asset:LoadImage(i-1,{Compression=i==2 and 1 or 0,Group=0,bSRGB=i==1,MaxWidth=1024,MaxHeight=1024,bVerticalFlip=false,bForceHDR=false,bCompressMips=false,bStreaming=true,LODBias=0,bForceAutoDetect=true,ForcePixelFormat=0})
   assert(valid(tex),'Missing Hornet texture');created:SetTextureParameterValue(FName(key),tex)
  end
  -- The native parent contains an AK-shaped occlusion map. Its inherited UV
  -- shadows do not belong on aircraft, blades or the flat landing deck.
  local render=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
  local ao=render:ImportFileAsTexture2D(a,root..'/assets/gyrocopter/clean-ao.png');assert(valid(ao),'Missing clean occlusion map')
  created:SetTextureParameterValue(FName('AOMap'),ao)
  created:SetScalarParameterValue(FName('AODarkness'),0);if carrier then carrierMat=created else mat=created end;return created
 end
 function V.fill(c,part,low,a)
  local name=part..(part=='body'and low and '_low'or '')
  geom[name]=geom[name]or dofile(root..'/assets/gyrocopter/'..name..'.lua');local g=geom[name]
  c:CreateMeshSection(0,g.vertices,g.triangles,g.normals,g.uv,{},{},part=='plastic')
  c:SetMaterial(0,material(a,part=='carrier'));c:SetCollisionEnabled(0);c:SetCullDistance(65000)
  if part=='plastic'then c:SetCollisionResponseToAllChannels(0);c:SetCollisionResponseToChannel(3,2);c:SetCollisionEnabled(1);c:SetGenerateOverlapEvents(false)end
 end
 function V.keepMaterial(c,a,carrier)
  local wanted=material(a,carrier);local current=c:GetMaterial(0)
  if not valid(current)or current:GetAddress()~=wanted:GetAddress()then c:SetMaterial(0,wanted)end
 end
 function V.create(a)
  local v={actor=a,low=false};local made={}
  local ok,err=pcall(function()
  for _,part in ipairs({'body','plastic','rotor','propeller','nose','left','right','tail'})do
   local c=a:AddComponentByClass(cls,true,identity,false);assert(valid(c),'Hornet visual creation failed')
   made[#made+1]=c
   c:K2_AttachToComponent(a.VehicleMesh,FName('None'),0,0,0,false)
   c:K2_SetRelativeLocation(pivots[part],false,{},true);c:SetIsReplicated(false)
   V.fill(c,part,false,a);v[part]=c
   if part=='plastic'then
    local material=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(a,a.VehicleMesh:GetMaterial(0).Parent,FName('BA_Plastic'),0)
    local white=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(a,root..'/assets/gyrocopter/clean-ao.png')
    if not valid(plasticNormal)or not valid(plasticORM)then
     local asset=textures('plastic')
     plasticNormal=asset:LoadImage(0,{Compression=1,Group=0,bSRGB=false,MaxWidth=8,MaxHeight=8,bVerticalFlip=false,bForceHDR=false,bCompressMips=false,bStreaming=true,LODBias=0,bForceAutoDetect=true,ForcePixelFormat=0})
     plasticORM=asset:LoadImage(1,{Compression=0,Group=0,bSRGB=false,MaxWidth=8,MaxHeight=8,bVerticalFlip=false,bForceHDR=false,bCompressMips=false,bStreaming=true,LODBias=0,bForceAutoDetect=true,ForcePixelFormat=0})
     assert(valid(plasticNormal)and valid(plasticORM),'Airframe paint textures unavailable')
    end
    material:SetTextureParameterValue(FName('TextureCleanNormal'),plasticNormal)
    material:SetTextureParameterValue(FName('TextureCleanORM'),plasticORM);material:SetTextureParameterValue(FName('ClearCoatTexture'),white)
    material:SetTextureParameterValue(FName('TextureColor'),white);material:SetTextureParameterValue(FName('TextureColorMask'),white)
    v.paintWhite=white
    c:SetMaterial(0,material);a.MaterialDynComponent:AddDynMaterial(c,'BA_Plastic',material);a.MaterialDynComponent:ProcessDynParam();v.paint=material
   end
   if part~='body'and part~='plastic'then
    local spin=a:AddComponentByClass(StaticFindObject('/Script/Engine.RotatingMovementComponent'),true,identity,false)
    made[#made+1]=spin
    spin:SetUpdatedComponent(c);spin.bRotationInLocalSpace=true;spin.RotationRate={Pitch=0,Yaw=0,Roll=0};v[part..'Spin']=spin
   end
  end
  for i=1,2 do
   local c=a:AddComponentByClass(cls,true,identity,false);made[#made+1]=c
   c:K2_AttachToComponent(v.rotor,FName('None'),0,0,0,false);c:SetIsReplicated(false);V.fill(c,'blade'..i,false,a);c:SetVisibility(false,false);v['blade'..i]=c
  end
  local low=a:AddComponentByClass(cls,true,identity,false);made[#made+1]=low
  low:K2_AttachToComponent(a.VehicleMesh,FName('None'),0,0,0,false);low:K2_SetRelativeLocation(pivots.body,false,{},true);low:SetIsReplicated(false)
  V.fill(low,'body',true,a);low:SetVisibility(false,false);v.bodyLow=low
  end)
  if not ok then for _,comp in ipairs(made)do if valid(comp)then comp:K2_DestroyComponent(a)end end;error(err)end
  v.components=made
  local pruned,why=pcall(V.prune,a,made,false)
  if not pruned then for _,comp in ipairs(made)do if valid(comp)then comp:K2_DestroyComponent(a)end end;error(why)end
  return v
 end
 function V.maintain(r,now,blades)
  if now<(r.presentationAt or 0)then return end;r.presentationAt=now+.5
  local a=r.actor;local v=r.visual
  local intact=v~=nil
  for _,name in ipairs({'body','plastic','rotor','propeller','nose','left','right','tail','blade1','blade2','rotorSpin','propellerSpin'})do
   if not v or not valid(v[name])then intact=false;break end
  end
  if not intact then
   -- Rebuild local rendering only. Never convert/reconfigure the native actor
   -- or touch its physics, saved identity, parts or flight controls here.
   local replacement=V.create(a)
   for _,c in ipairs(v and v.components or{})do if valid(c)then c:K2_DestroyComponent(a)end end
   r.visual=replacement;v=replacement
  end
  -- Native wear stays saved/replicated, but its car UV atlas must never render here.
  local wearMaterial=a.VehicleMesh:GetMaterial(0)
  if valid(wearMaterial)and valid(v.paint)then
   local dirty=wearMaterial:K2_GetScalarParameterValue(FName('Rust and wear'))>.05
   if v.dirty~=dirty then
    -- An unused texture held only by Lua can be collected while every airframe
    -- is clean. Reacquire it before handing a pointer to the render thread.
    if dirty and not valid(plasticDirt)then
     plasticDirt=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(a,root..'/assets/gyrocopter/plastic-dirt.png')
     assert(valid(plasticDirt),'Airframe dirt texture unavailable')
    end
    v.paint:SetTextureParameterValue(FName('TextureColor'),dirty and plasticDirt or v.paintWhite);v.dirty=dirty
   end
   v.paint:SetScalarParameterValue(FName('Rust and wear'),0)
  end
  for _,value in ipairs(a:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.PrimitiveComponent')))do
   local c=value:get();if valid(c)and not c:IsA(cls)and c:IsVisible()then c:SetVisibility(false,false)end
  end
  a.CarEquipableComponents:ForEach(function(_,value)
   local slot=value:get();if not valid(slot)then return end
   local p=slot.AttachedCarEquipableActor;if not valid(p)or blades[p:GetFullName()]then return end
   local mount=p.ParentCarEquipableV2
   if not valid(mount)or mount:GetAddress()~=slot:GetAddress()then return end
   local kind=slot:GetFullName():match('^(%S+)')
   local service=slot:GetAddress()==a.CarSeatDriver:GetAddress()or kind=='CarMotorV2_C'or kind=='CarRadiatorV2_C'or kind=='CarTankGasV2_C'or kind=='CarBatteryV2_C'
   p:SetActorHiddenInGame(not service)
  end)
  for _,name in ipairs({'body','plastic','rotor','propeller','nose','left','right','tail'})do
   if (name~='body'or not v.low)and not v[name]:IsVisible()then v[name]:SetVisibility(true,false)end
  end
 end
 function V.tick(v,s,distance)
  if not valid(v.body)then return end
  local low=distance>(v.low and 11000 or 15000)
  if low~=v.low then
   if valid(v.bodyLow)then v.body:SetVisibility(not low,false);v.bodyLow:SetVisibility(low,false)
   else V.fill(v.body,'body',low,v.actor)end
   v.low=low
  end
  -- Native rotating components animate every frame; no extra Lua polling loop.
  local near=distance<35000
  local mask=s.bladeMask or 3
  if v.mask~=mask then v.blade1:SetVisibility(mask&1~=0,false);v.blade2:SetVisibility(mask&2~=0,false);v.mask=mask end
  if v.near~=near then
   for _,part in ipairs({'rotor','propeller','nose','left','right','tail'})do v[part..'Spin']:SetComponentTickEnabled(near)end
   v.near=near
  end
  v.rotorSpin.RotationRate={Pitch=0,Roll=0,Yaw=s.rpm*6}
  v.propellerSpin.RotationRate={Pitch=0,Roll=(s.propRPM or 0)*6,Yaw=0}
  local speed=v.actor:GetVelocity();local forward=v.actor:GetActorForwardVector()
  local wheelRate=(speed.X*forward.X+speed.Y*forward.Y+speed.Z*forward.Z)/13*180/math.pi
  for _,part in ipairs({'nose','left','right','tail'})do
   v[part..'Spin'].RotationRate={Pitch=-wheelRate,Roll=0,Yaw=0}
  end
 end
 function V.reset()mat=nil;carrierMat=nil end
 function V.item(c,side,a)V.fill(c,'blade'..side..'_item',false,a)end
 return V
end

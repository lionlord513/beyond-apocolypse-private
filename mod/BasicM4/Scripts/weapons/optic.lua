-- One shared 2x optic. Identity rides native items; only the host consumes parts.
return function(M,R,root,valid,H)
 local O={records={},seen={},candidates={},lenses={},actorLenses={}};local J=R.journal
 local cache=assert(M.weaponMeshes);local meshClass=cache.class
 local scene=StaticFindObject('/Script/Engine.SceneComponent')
 local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 O.axisHeight=2.63878
 O.mounts={m4={x=1,z=5.10},hunting={x=15,z=5.4},enfield={x=3,z=3.65},ak={x=12,y=.7,z=8.6}}
 local material;local built={}
 local function getMaterial(a)
  if valid(material)then return material end
  local function offset(o,name)local n;o:ForEachProperty(function(p)if p:GetFName():ToString()==name then n=p:GetOffset_Internal()end end);return assert(n)end
  local load=assert(package.loadlib(root..'/assets/native/BeyondImports.dll','ba_load_asset'))
  local lib=StaticFindObject('/Script/glTFRuntime.Default__glTFRuntimeFunctionLibrary')
  local fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeFunctionLibrary:glTFLoadAssetFromFilename')
  local cfg=StaticFindObject('/Script/glTFRuntime.glTFRuntimeConfig')
  local address=load(lib:GetAddress(),fn:GetAddress(),offset(fn,'LoaderConfig'),offset(fn,'ReturnValue'),root..'/assets/optic/textures.gltf',offset(cfg,'SceneScale'),offset(cfg,'TransformBaseType'))
  local asset;for _,v in ipairs(FindAllOf('glTFRuntimeAsset')or{})do if v:GetAddress()==address then asset=v;break end end;assert(valid(asset),'Sight textures unavailable')
  local context=H.GetPlayerController();assert(valid(context),'Local world is loading')
  local mat=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(context,LoadAsset('/MasterWeapon/Materials/Weapons/MAT_ArK47.MAT_ArK47'),FName('BA_Optic'),0)
  for i,key in ipairs({'Diffuse','NormalMap','RoughnessMap','MetalMap'})do
   local tex=asset:LoadImage(i-1,{Compression=i==2 and 1 or 0,Group=0,bSRGB=i==1,MaxWidth=1024,MaxHeight=1024,bVerticalFlip=false,bForceHDR=false,bCompressMips=false,bStreaming=true,LODBias=0,bForceAutoDetect=true,ForcePixelFormat=0});assert(valid(tex));mat:SetTextureParameterValue(FName(key),tex)
  end
  mat:SetTextureParameterValue(FName('AOMap'),StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(context,root..'/assets/gyrocopter/clean-ao.png'));mat:SetScalarParameterValue(FName('AODarkness'),1);material=mat;return mat
 end
 local function marker(a,name)
  for _,v in ipairs(a:K2_GetComponentsByClass(scene))do local c=v:get();if valid(c)and c.AttachSocketName:ToString()==name then return c end end
 end
 local function lenses(a,parent)
  local key=parent:GetFullName();local r=O.lenses[key]
  if r and valid(r.parent)and r.parent:GetAddress()==parent:GetAddress()and valid(r.front)and valid(r.rear)then return end
  local mat=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(a,LoadAsset('/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial'),FName('None'),0)
  mat:SetVectorParameterValue(FName('Color'),{R=.025,G=.075,B=.095,A=1})
  local function lens(x,radius)
   local c=a:AddComponentByClass(meshClass,true,identity,false);assert(valid(c),'Sight lens unavailable')
   c:SetStaticMesh((LoadAsset('/Engine/BasicShapes/Sphere.Sphere')));c:SetMaterial(0,mat)
   c:K2_AttachToComponent(parent,FName('BA_2xLens'),0,0,0,false)
   c:K2_SetRelativeLocation({X=x,Y=0,Z=O.axisHeight},false,{},true)
   c:SetRelativeScale3D({X=.0015,Y=radius/50,Z=radius/50})
   c:SetCollisionEnabled(0);c:SetGenerateOverlapEvents(false);c:SetComponentTickEnabled(false);c:SetIsReplicated(false);c:SetCastShadow(false)
   return c
  end
  O.lenses[key]={actor=a,actorKey=a:GetFullName(),parent=parent,rear=lens(-9.1,1.03),front=lens(10.1,1.34),visible=true}
  O.actorLenses[a:GetFullName()]=O.lenses[key]
 end
 function O.aim(a,aiming)
  local r=aiming and valid(a)and O.actorLenses[a:GetFullName()]or nil
  if O.aimed==r then return end
  for _,old in pairs({previous=O.aimed,current=r})do
   local visible=old~=r
   if valid(old.front)then old.front:SetVisibility(visible,false)end
   if valid(old.rear)then old.rear:SetVisibility(visible,false)end
   old.visible=visible
  end
  O.aimed=r
 end
 function O.item(a)
  if not valid(a)then return false end;local name=a:GetFullName();if not(name:match('^Binocular_C ')or name:match('^LampeTorche_C '))then return false end
  return a:HasAuthority()and J.state.scopeItem[M.guid(a)]or marker(a,'BA_2xItem')~=nil
 end
 function O.has(a)return valid(a)and(a:HasAuthority()and J.state.scope[M.guid(a)]or marker(a,'BA_2xScope'))end
 local function mesh(a,parent,tr,name)
  local c=marker(a,name)
  if c and not c:IsA(meshClass)then c:K2_DestroyComponent(a);c=nil end
  if not c then
   c=a:AddComponentByClass(meshClass,true,tr,false);assert(valid(c),'Sight mesh unavailable')
   c:K2_AttachToComponent(parent,FName(name),0,0,0,false);c:SetCollisionEnabled(0);c:SetGenerateOverlapEvents(false);c:SetComponentTickEnabled(false);c:SetIsReplicated(false)
  end
  local key=c:GetFullName()
  if not valid(built[key])or built[key]:GetAddress()~=c:GetAddress()or not valid(c.StaticMesh)then
   cache.fill(a,c,'optic','scope',getMaterial(a));c:SetCastShadow(false);built[key]=c
  end
  c:K2_SetRelativeTransform(tr,false,{},true)
  lenses(a,c)
  return c
 end
 function O.markItem(a)
  assert(a:HasAuthority());J.state.scopeItem[assert(M.guid(a))]=true
  local c=marker(a,'BA_2xItem');if not c then c=a:AddComponentByClass(scene,true,identity,false);c:K2_AttachToComponent(a.RootComponent,FName('BA_2xItem'),0,0,0,false);c:SetIsReplicated(true);a:ForceNetUpdate()end
  O.skinItem(a)
 end
 function O.skinItem(a)
  if not O.item(a)then return end
  O.records[a:GetFullName()]=a
  a.StaticMesh:SetVisibility(false,false)
  if a:GetFullName():match('^LampeTorche_C ')and valid(a.SpotLight)then a.SpotLight:SetVisibility(false,false);a.SpotLight:SetIntensity(0)end
  mesh(a,a.RootMeshComponent,identity,'BA_2xLoose')
 end
 function O.update(a,d)
  local m=marker(a,'BA_2xScope');local row=a:HasAuthority()and J.state.scope[M.guid(a)]
  if a:HasAuthority()then
   if not J.ready then return end
   if not row then if m then m:K2_DestroyComponent(a)end;local visual=marker(a,'BA_2xVisual');if visual then visual:K2_DestroyComponent(a)end;return end
   if not m then
    m=a:AddComponentByClass(scene,true,identity,false);m:K2_AttachToComponent(a.SkeletalMesh,FName('BA_2xScope'),0,0,0,false);m:SetIsReplicated(true);a:ForceNetUpdate()
   end
  end
  if not m then local visual=marker(a,'BA_2xVisual');if visual then visual:K2_DestroyComponent(a)end;return end
  local mount=O.mounts[d.Id];local tr={Translation={X=mount.x,Y=mount.y or 0,Z=mount.z},Rotation=identity.Rotation,Scale3D=identity.Scale3D}
  tr=mathlib:ComposeTransforms(tr,d.Transform());mesh(a,a.SkeletalMesh,tr,'BA_2xVisual')
 end
 function O.mount(gun,item)
  J.writable();assert(gun:HasAuthority()and item:HasAuthority()and O.item(item),'Choose a 2x sight')
  local id=assert(M.guid(gun));assert(not J.state.scope[id],'A sight is already fitted');local source=assert(M.guid(item))
  J.state.scope[id]={source};local ok,e=pcall(O.update,gun,assert(R.definition(gun)))
  if not ok then J.state.scope[id]=nil;error(e)end
  item:K2_DestroyActor();return '2x sight attached'
 end
 function O.tick()
  if os.clock()<(O.nextAt or 0)then return end;O.nextAt=os.clock()+1
  for key,c in pairs(built)do if not valid(c)then built[key]=nil end end
  for key,r in pairs(O.lenses)do if not valid(r.actor)or not valid(r.parent)then
   for _,c in ipairs({r.front,r.rear})do if valid(c)and valid(r.actor)then c:K2_DestroyComponent(r.actor)end end
   O.lenses[key]=nil;if O.actorLenses[r.actorKey]==r then O.actorLenses[r.actorKey]=nil end
  end end
  if not O.seeded then
   for _,kind in ipairs({'Binocular_C','LampeTorche_C'})do for _,a in ipairs(FindAllOf(kind)or{})do O.observe(a)end end;O.seeded=true
  end
  for key,a in pairs(O.records)do if valid(a)then O.skinItem(a)else O.records[key]=nil end end
  local held;local count=0
  for key,q in pairs(O.candidates)do local a=q.actor
   if count>=16 then break end;count=count+1
   if not valid(a)then O.candidates[key]=nil else
   local id=M.guid(a)
   if a:HasAuthority()and J.ready and id and not O.seen[id]then
    O.seen[id]=true
    if a:GetFullName():match('^LampeTorche_C ')and a['From Level Spawn']==true and not a.FromInventory and not a.isAttached and not valid(a:GetAttachParentActor())then
     if not held then held={};for _,pc in ipairs(FindAllOf('PlayerController')or{})do if valid(pc)then local out={};pc:GetItemInHand(out);if valid(out.Item)then held[out.Item:GetAddress()]=true end end end end
     local h=5381;for i=1,#id do h=(h*33+id:byte(i))&0xffffffff end
     if h%100<40 and not held[a:GetAddress()]then O.markItem(a)end
    end
   end
   if O.item(a)then O.skinItem(a);O.records[key]=a;O.candidates[key]=nil
   elseif not a:HasAuthority()or J.ready then q.tries=q.tries+1;if q.tries>=30 then O.candidates[key]=nil end end
  end end
 end
 function O.observe(a)if valid(a)then O.candidates[a:GetFullName()]={actor=a,tries=0}end end
 NotifyOnNewObject('/Game/BP/Items/Movable/Binocular/Binocular.Binocular_C',O.observe)
 NotifyOnNewObject('/Game/BP/Items/Movable/ActivableInHand/LampeTorche.LampeTorche_C',O.observe)
 function O.reset()material=nil;built={};O.seen={};O.records={};O.candidates={};O.lenses={};O.actorLenses={};O.aimed=nil;O.seeded=nil;O.nextAt=0 end
 return O
end

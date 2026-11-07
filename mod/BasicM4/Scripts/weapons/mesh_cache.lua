-- Native meshes are shared across inventory recreations. Hidden, unticked local
-- controller components retain the meshes/materials while every rifle is stored.
return function(M,H,valid)
 local C={entries={},irons={}}
 local cls=StaticFindObject('/Script/Engine.StaticMeshComponent')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local function offset(o,name)local n;o:ForEachProperty(function(p)if p:GetFName():ToString()==name then n=p:GetOffset_Internal()end end);assert(n,'Mesh loader field unavailable: '..name);return n end
 local function import(file)
  local load=assert(package.loadlib(M.root..'/assets/native/BeyondMotorcycle.dll','ba_load_asset'))
  local lib=StaticFindObject('/Script/glTFRuntime.Default__glTFRuntimeFunctionLibrary')
  local fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeFunctionLibrary:glTFLoadAssetFromFilename')
  local cfg=StaticFindObject('/Script/glTFRuntime.glTFRuntimeConfig')
  local addr,why=load(lib:GetAddress(),fn:GetAddress(),offset(fn,'LoaderConfig'),offset(fn,'ReturnValue'),M.root..'/assets/rifles/'..file..'.gltf',offset(cfg,'SceneScale'),offset(cfg,'TransformBaseType'))
  local asset;for _,a in ipairs(FindAllOf('glTFRuntimeAsset')or{})do if a:GetAddress()==addr then asset=a;break end end
  assert(valid(asset),'Rifle mesh import failed: '..tostring(why or file))
  -- The pinned bridge initializes this complex native struct safely. Passing a
  -- Lua table directly to LoadStaticMesh is unsafe in the pinned UE4SS build.
  local build=assert(package.loadlib(M.root..'/assets/native/BeyondMotorcycle.dll','ba_load_chassis'))
  fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeAsset:LoadStaticMesh');cfg=StaticFindObject('/Script/glTFRuntime.glTFRuntimeStaticMeshConfig')
  addr=build(asset:GetAddress(),fn:GetAddress(),offset(fn,'StaticMeshConfig'),offset(fn,'ReturnValue'),offset(cfg,'bBuildSimpleCollision'),offset(cfg,'bBuildComplexCollision'))
  for _,mesh in ipairs(FindAllOf('StaticMesh')or{})do if mesh:GetAddress()==addr then return mesh end end
  error('Rifle mesh build failed: '..file)
 end
 local function component(owner)
  local c=owner:AddComponentByClass(cls,true,identity,false);assert(valid(c),'Rifle component unavailable')
  c:SetCollisionEnabled(0);c:SetGenerateOverlapEvents(false);c:SetComponentTickEnabled(false);c:SetIsReplicated(false)
  return c
 end
 function C.reset()
  for _,r in pairs(C.irons)do if valid(r.owner)and valid(r.component)then r.component:K2_DestroyComponent(r.owner)end end
  for _,r in pairs(C.entries)do if valid(r.owner)and valid(r.holder)then r.holder:K2_DestroyComponent(r.owner)end end
  C.entries={};C.irons={}
 end
 function C.mesh(id,part,material)
  local key=id..'-'..part;local r=C.entries[key];local owner=H.GetPlayerController()
  assert(valid(owner),'Local world is loading')
  if r and valid(r.owner)and r.owner:GetAddress()==owner:GetAddress()and valid(r.holder)and valid(r.mesh)then
   if valid(material)then r.holder:SetMaterial(0,material)end
   return r.mesh
  end
  if r and valid(r.owner)and valid(r.holder)then r.holder:K2_DestroyComponent(r.owner)end
  local mesh=import(key);local holder=component(owner)
  local ok,why=pcall(function()
   holder:SetVisibility(false,false);holder:SetCastShadow(false);assert(holder:SetStaticMesh(mesh),'Rifle cache assignment failed')
   if valid(material)then holder:SetMaterial(0,material)end
  end)
  if not ok then holder:K2_DestroyComponent(owner);error(why)end
  C.entries[key]={owner=owner,holder=holder,mesh=mesh};return mesh
 end
 function C.fill(a,c,id,part,material)
  local mesh=C.mesh(id,part,material)
  if not valid(c.StaticMesh)or c.StaticMesh:GetAddress()~=mesh:GetAddress()then assert(c:SetStaticMesh(mesh),'Rifle mesh assignment failed')end
  c:SetMaterial(0,material)
  if part~='body'then return end
  local key=c:GetFullName();local r=C.irons[key]
  if not r or not valid(r.body)or r.body:GetAddress()~=c:GetAddress()or not valid(r.component)then
   local iron=component(a)
   local ok,why=pcall(function()
    assert(iron:SetStaticMesh(C.mesh(id,'iron',material)),'Rifle sight assignment failed');iron:SetMaterial(0,material)
    iron:K2_AttachToComponent(c,FName('BA_RifleIron'),0,0,0,false);iron:K2_SetRelativeTransform(identity,false,{},true)
   end)
   if not ok then iron:K2_DestroyComponent(a);error(why)end
   C.irons[key]={body=c,component=iron,owner=a}
  end
 end
 function C.showIrons(c,show)
  local r=C.irons[c:GetFullName()]
  if r and valid(r.component)and r.visible~=show then r.component:SetVisibility(show,false);r.visible=show end
 end
 function C.remove(c)
  local key=c:GetFullName();local r=C.irons[key]
  if r and valid(r.owner)and valid(r.component)then r.component:K2_DestroyComponent(r.owner)end
  C.irons[key]=nil
 end
 function C.prune()for key,r in pairs(C.irons)do if not valid(r.body)or not valid(r.component)then
  if valid(r.owner)and valid(r.component)then r.component:K2_DestroyComponent(r.owner)end
  C.irons[key]=nil
 end end end
 C.class=cls
 return C
end

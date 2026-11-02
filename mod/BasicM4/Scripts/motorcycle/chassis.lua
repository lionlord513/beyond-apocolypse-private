return function(root,valid)
 local cached,holder
 return function()
  if valid(cached)then return cached end
  local function offset(o,name)local n;o:ForEachProperty(function(p)if p:GetFName():ToString()==name then n=p:GetOffset_Internal()end end);assert(n,'Missing chassis field '..name);return n end
  local load=assert(package.loadlib(root..'/assets/native/BeyondMotorcycle.dll','ba_load_asset'))
  local lib=StaticFindObject('/Script/glTFRuntime.Default__glTFRuntimeFunctionLibrary')
  local fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeFunctionLibrary:glTFLoadAssetFromFilename');local cfg=StaticFindObject('/Script/glTFRuntime.glTFRuntimeConfig')
  local addr,why=load(lib:GetAddress(),fn:GetAddress(),offset(fn,'LoaderConfig'),offset(fn,'ReturnValue'),root..'/assets/motorcycle/chassis.gltf',offset(cfg,'SceneScale'),offset(cfg,'TransformBaseType'))
  for _,a in ipairs(FindAllOf('glTFRuntimeAsset')or{})do if a:GetAddress()==addr then holder=a;break end end
  assert(valid(holder),'Chassis asset import failed: '..tostring(addr)..' '..tostring(why))
  local build=assert(package.loadlib(root..'/assets/native/BeyondMotorcycle.dll','ba_load_chassis'))
  fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeAsset:LoadStaticMesh');cfg=StaticFindObject('/Script/glTFRuntime.glTFRuntimeStaticMeshConfig')
  addr=build(holder:GetAddress(),fn:GetAddress(),offset(fn,'StaticMeshConfig'),offset(fn,'ReturnValue'),offset(cfg,'bBuildSimpleCollision'),offset(cfg,'bBuildComplexCollision'))
  for _,mesh in ipairs(FindAllOf('StaticMesh')or{})do if mesh:GetAddress()==addr then cached=mesh;return cached end end
  error('Chassis collision import failed')
 end
end

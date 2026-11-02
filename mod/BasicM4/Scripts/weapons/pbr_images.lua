-- Reuse the verified sight image-loading path for explicit PBR colour spaces.
return function(root,valid)
 return function(file,maxSize)
  local function offset(o,name)local n;o:ForEachProperty(function(p)if p:GetFName():ToString()==name then n=p:GetOffset_Internal()end end);assert(n,'Image loader field unavailable: '..name);return n end
  local load=assert(package.loadlib(root..'/assets/native/BeyondImports.dll','ba_load_asset'))
  local lib=StaticFindObject('/Script/glTFRuntime.Default__glTFRuntimeFunctionLibrary')
  local fn=StaticFindObject('/Script/glTFRuntime.glTFRuntimeFunctionLibrary:glTFLoadAssetFromFilename')
  local cfg=StaticFindObject('/Script/glTFRuntime.glTFRuntimeConfig')
  local address=load(lib:GetAddress(),fn:GetAddress(),offset(fn,'LoaderConfig'),offset(fn,'ReturnValue'),root..'/'..file,offset(cfg,'SceneScale'),offset(cfg,'TransformBaseType'))
  local asset;for _,v in ipairs(FindAllOf('glTFRuntimeAsset')or{})do if v:GetAddress()==address then asset=v;break end end
  assert(valid(asset),'PBR images unavailable: '..file)
  local textures={}
  for i,key in ipairs({'Diffuse','NormalMap','RoughnessMap','MetalMap','AOMap'})do
   local tex=asset:LoadImage(i-1,{Compression=i==2 and 1 or 0,Group=0,bSRGB=i==1,MaxWidth=maxSize or 1024,MaxHeight=maxSize or 1024,bVerticalFlip=false,bForceHDR=false,bCompressMips=false,bStreaming=true,LODBias=0,bForceAutoDetect=true,ForcePixelFormat=0})
   assert(valid(tex),'PBR texture unavailable: '..key);textures[key]=tex
  end
  return textures
 end
end

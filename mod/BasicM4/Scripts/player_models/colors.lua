return function(root,valid)
 local C={}
 local K=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
 local renderer=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
 local tiles=dofile(root..'/Scripts/player_models/tiles.lua')
 local I={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local function channel(s,index)return tonumber(s:sub(index,index+1),16)end
 local function linear(x)x=x/255;return x<=.04045 and x/12.92 or ((x+.055)/1.055)^2.4 end
 function C.rgb(hex)return {R=linear(channel(hex,1)),G=linear(channel(hex,3)),B=linear(channel(hex,5)),A=1}end
 function C.part(pal,i)
  local v=pal:sub(i*7-6,i*7)
  return v:sub(1,6),tonumber(v:sub(7))
 end
 -- The imported Soldier uses one UV tile per original FBX material. Preserve
 -- untouched tiles and apply each finish to precisely the same material IDs.
 local function crc32(s)
  local c=0xffffffff
  for i=1,#s do c=c~s:byte(i);for _=1,8 do c=(c>>1)~((c&1)~=0 and 0xedb88320 or 0)end end
  return (~c)&0xffffffff
 end
 local function chunk(name,s)return string.pack('>I4',#s)..name..s..string.pack('>I4',crc32(name..s))end
 local function png(pixels)
  local rows={}
  for y=0,3 do
   local row={'\0'};for x=1,4 do row[#row+1]=pixels[y*4+x]:rep(32)end
   rows[#rows+1]=table.concat(row):rep(32)
  end
  local raw=table.concat(rows);local a,b=1,0;for i=1,#raw do a=(a+raw:byte(i))%65521;b=(b+a)%65521 end
  local z='\120\1\1'..string.pack('<I2I2',#raw,0xffff-#raw)..raw..string.pack('>I4',b*65536+a)
  return '\137PNG\r\n\26\n'..chunk('IHDR',string.pack('>I4I4BBBBB',128,128,8,2,0,0,0))..chunk('IDAT',z)..chunk('IEND','')
 end
 local function srgbByte(linearByte)
  local v=linearByte/255
  return math.floor(255*(v<=.0031308 and v*12.92 or 1.055*v^(1/2.4)-.055)+.5)
 end
 local function texture(actor,pixels)
  local path=root..'/state/appearance-swatch.png';local f=assert(io.open(path,'wb'));assert(f:write(png(pixels)));assert(f:close())
  local tex=renderer:ImportFileAsTexture2D(actor,path);assert(valid(tex),'Appearance texture unavailable');return tex
 end
 function C.soldier(actor,base,pal)
  local master=LoadAsset('/MasterWeapon/Materials/Weapons/MAT_ArK47.MAT_ArK47')
  local m=K:CreateDynamicMaterialInstance(actor,master,FName('None'),0)
  m:K2_CopyMaterialInstanceParameters(base,true)
  local rgb,rough,metal={},{},{}
  local finishes=false
  for i,row in ipairs(tiles)do
   local group,hex,r,mt=table.unpack(row)
   if group>0 then
    local value,finish=C.part(pal,group)
    if value~='------'then hex=value end
    if finish>0 then finishes=true;r=finish==1 and 246 or 68;mt=finish==1 and 0 or 255 end
   end
   rgb[i]=string.char(channel(hex,1),channel(hex,3),channel(hex,5))
   r=srgbByte(r);mt=srgbByte(mt);rough[i]=string.char(r,r,r);metal[i]=string.char(mt,mt,mt)
  end
  m:SetTextureParameterValue(FName('Diffuse'),texture(actor,rgb))
  if finishes then m:SetTextureParameterValue(FName('RoughnessMap'),texture(actor,rough));m:SetTextureParameterValue(FName('MetalMap'),texture(actor,metal))end
  return m
 end
 function C.alien(actor,base,pal)
  local skin=C.part(pal,2)
  if skin=='------' then return base end
  local m=K:CreateDynamicMaterialInstance(actor,base,FName('None'),0)
  local diffuse=m:K2_GetTextureParameterValue(FName('Diff'))
  assert(valid(diffuse),'Alien diffuse texture unavailable')
  local shader=LoadAsset('/Engine/EngineMaterials/Widget3DPassThrough_Opaque.Widget3DPassThrough_Opaque')
  local brush=K:CreateDynamicMaterialInstance(actor,shader,FName('None'),0)
  brush:SetTextureParameterValue(FName('SlateUI'),diffuse)
  local tint=C.rgb(skin)
  for _,key in ipairs({'R','G','B'})do tint[key]=.018+3.5*tint[key]end
  brush:SetVectorParameterValue(FName('TintColorAndOpacity'),tint)
  local target=renderer:CreateRenderTarget2D(actor,diffuse:Blueprint_GetSizeX(),diffuse:Blueprint_GetSizeY(),3,{R=0,G=0,B=0,A=1},false,false)
  renderer:DrawMaterialToRenderTarget(actor,target,brush)
  m:SetTextureParameterValue(FName('Diff'),target)
  return m
 end
 local function part(actor,mesh,socket,shape,m)
  local c=actor:AddComponentByClass(StaticFindObject('/Script/Engine.StaticMeshComponent'),true,I,false)
  c:SetStaticMesh((LoadAsset('/Engine/BasicShapes/'..shape..'.'..shape)));c:SetMaterial(0,m)
  c:SetCollisionEnabled(0);c:SetGenerateOverlapEvents(false);c:SetComponentTickEnabled(false);c:SetCastShadow(false)
  c:K2_AttachToComponent(mesh,FName(socket),0,0,0,false);return c
 end
 function C.band(actor,mesh,pal)
  local v=C.part(pal,1);if v=='------'then return end
  local m=K:CreateDynamicMaterialInstance(actor,LoadAsset('/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial'),FName('None'),0)
  m:SetVectorParameterValue(FName('Color'),C.rgb(v));local c=part(actor,mesh,'hand_l','Cylinder',m)
  c:SetRelativeScale3D({X=.074,Y=.061,Z=.023});c:K2_SetRelativeRotation({Pitch=90,Yaw=0,Roll=0},false,{},true)
  c:K2_SetRelativeLocation({X=-2,Y=0,Z=0},false,{},true);return c
 end
 function C.eyes(actor,mesh,pal)
  local value=C.part(pal,1);local rgb=C.rgb(value=='------'and '41FFE6' or value)
  local shader=LoadAsset('/Engine/EngineMaterials/Widget3DPassThrough_Opaque.Widget3DPassThrough_Opaque')
  local mat=K:CreateDynamicMaterialInstance(actor,shader,FName('None'),0)
  local white=LoadAsset('/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture')
  assert(valid(white),'Eye texture unavailable')
  mat:SetTextureParameterValue(FName('SlateUI'),white)
  mat:SetVectorParameterValue(FName('TintColorAndOpacity'),{R=rgb.R*24,G=rgb.G*24,B=rgb.B*24,A=1})
  local eyes={}
  for _,side in ipairs({-1,1})do
   local c=part(actor,mesh,'head','Sphere',mat)
   local key=side<0 and 'left' or 'right'
   c:K2_SetRelativeTransform(C.eyeFit[key],false,{},true)
   eyes[#eyes+1]=c
  end
  return eyes
 end
 C.eyeFit=dofile(root..'/Scripts/player_models/eye_fit.lua')
 return C
end

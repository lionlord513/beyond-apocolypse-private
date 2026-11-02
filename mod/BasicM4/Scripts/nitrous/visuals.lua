return function(root,valid)
 local V={materials={}};local geometry
 local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local collision=dofile(root..'/Scripts/nitrous/collider.lua')(root,valid)
 local tangent=dofile(root..'/Scripts/nitrous/tangents.lua')
 local images=dofile(root..'/Scripts/weapons/pbr_images.lua')(root,valid)
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local function material(a,d)
  local m=V.materials[d.tier];if valid(m)then return m end
  m=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(a,LoadAsset('/MasterWeapon/Materials/Weapons/MAT_ArK47.MAT_ArK47'),FName('BA_Nitrous_'..d.tier),0)
  for key,tex in pairs(images('assets/nitrous/'..d.color..'-textures.gltf',2048))do m:SetTextureParameterValue(FName(key),tex)end
  -- The old zero AO multiplier removed indirect lighting, especially in shade.
  m:SetScalarParameterValue(FName('DiffuseBrightness'),1.3);m:SetScalarParameterValue(FName('AODarkness'),1);m:SetScalarParameterValue(FName('RoughnessBrightness'),1)
  V.materials[d.tier]=m;return m
 end
 local function scale(r)
  local a=r.actor;local s=r.def.height/38;local desired={X=s,Y=s,Z=s}
  a.BaseRelativeScale=desired
  local current=a.TankMesh:K2_GetComponentScale()
  if math.abs(current.X-s)>.001 or math.abs(current.Y-s)>.001 or math.abs(current.Z-s)>.001 then a.TankMesh:SetWorldScale3D(desired)end
 end
 function V.apply(r,d)
  local a=r.actor;local mesh=a.TankMesh;if not valid(mesh)then return end
  -- Replace the 100-litre donor barrel collider, not just its visible skin.
  mesh:SetStaticMesh(collision());scale(r)
  if not valid(r.visual)then
   geometry=geometry or dofile(root..'/assets/nitrous/bottle.lua')
   local c=a:AddComponentByClass(pmc,true,identity,false);assert(valid(c),'Nitrous mesh unavailable');r.visual=c
   c:K2_AttachToComponent(mesh,FName('BA_NitrousVisual'),0,0,0,false);c:SetAbsolute(false,false,false);c:SetIsReplicated(false);c:SetCollisionEnabled(0)
   c:CreateMeshSection(0,geometry.vertices,geometry.triangles,geometry.normals,geometry.uv,{},tangent(geometry),false);c:SetMaterial(0,material(a,d));c:SetCullDistance(18000)
  end
  r.visual:SetRelativeScale3D({X=1,Y=1,Z=1});mesh:SetVisibility(false,false);a.Caps:SetVisibility(false,false)
  -- The origin is now between the two bracket feet, with the bottle horizontal.
  a.AttachableComponent.AttachableRotationOffset={Pitch=0,Yaw=0,Roll=0}
  a.ItemTankComponent:SetAbsolute(false,false,false)
  a.ItemTankComponent:K2_SetRelativeLocation({X=22.112325,Y=0,Z=9.5},false,{},true)
  a.ItemTankComponent:K2_SetRelativeRotation({Pitch=0,Yaw=0,Roll=0},false,{},true)
  a.Caps:K2_SetRelativeLocation({X=0,Y=0,Z=0},false,{},true)
  a.CapsTriggerBox:SetAbsolute(false,false,false);a.CapsTriggerBox:SetRelativeScale3D({X=1,Y=1,Z=1})
  a.CapsTriggerBox:K2_SetRelativeLocation({X=0,Y=0,Z=0},false,{},true);a.CapsTriggerBox:SetBoxExtent({X=3,Y=3,Z=3},false)
  a.UpVector:K2_SetRelativeRotation({Pitch=0,Yaw=0,Roll=0},false,{},true)
  a.FluidConnectorTriggerBox:SetSphereRadius(3.5,false)
  a.CanBeAttachedToTheCar=true
  return r
 end
 function V.maintain(r)
  local a=r.actor;scale(r)
  if a.TankMesh:IsVisible()then a.TankMesh:SetVisibility(false,false)end
  if a.Caps:IsVisible()then a.Caps:SetVisibility(false,false)end
 end
 function V.reset()V.materials={}end
 return V
end

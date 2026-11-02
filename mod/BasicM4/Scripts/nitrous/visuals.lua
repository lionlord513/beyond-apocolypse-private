return function(root,valid)
 local V={materials={}};local geometry
 local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local render=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local function material(a,d)
  local m=V.materials[d.tier];if valid(m)then return m end
  m=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(a,LoadAsset('/MasterWeapon/Materials/Weapons/MAT_ArK47.MAT_ArK47'),FName('BA_Nitrous_'..d.tier),0)
  for key,file in pairs({Diffuse='nitrous/'..d.color..'.png',NormalMap='gyrocopter/plastic-normal.png',AOMap='gyrocopter/clean-ao.png',RoughnessMap='gyrocopter/roughness.png',MetalMap='gyrocopter/metal.png'})do
   local tex=render:ImportFileAsTexture2D(a,root..'/assets/'..file);assert(valid(tex),'Missing nitrous texture: '..file);m:SetTextureParameterValue(FName(key),tex)
  end
  m:SetScalarParameterValue(FName('DiffuseBrightness'),1);m:SetScalarParameterValue(FName('AODarkness'),0);m:SetScalarParameterValue(FName('RoughnessBrightness'),.8)
  V.materials[d.tier]=m;return m
 end
 function V.apply(r,d)
  local a=r.actor;local mesh=a.TankMesh;if not valid(mesh)then return end
  if not valid(r.visual)then
   geometry=geometry or dofile(root..'/assets/nitrous/bottle.lua')
   local c=a:AddComponentByClass(pmc,true,identity,false);assert(valid(c),'Nitrous mesh unavailable')
   c:K2_AttachToComponent(mesh,FName('BA_NitrousVisual'),0,0,0,false);c:SetAbsolute(false,false,true);c:SetIsReplicated(false);c:SetCollisionEnabled(0)
   c:CreateMeshSection(0,geometry.vertices,geometry.triangles,geometry.normals,geometry.uv,{},{},false);c:SetMaterial(0,material(a,d));c:SetCullDistance(18000);r.visual=c
  end
  local s=d.height/38
  r.visual:SetRelativeScale3D({X=s,Y=s,Z=s});mesh:SetVisibility(false,false);a.Caps:SetVisibility(false,false)
  -- Keep the native cylinder's convex pickup/attachment collision, fitted to this mesh.
  mesh:SetWorldScale3D({X=d.height*.270/74.82,Y=d.height*.270/74.82,Z=d.height/102.92})
  a.ItemTankComponent:K2_SetRelativeLocation({X=0,Y=0,Z=100.5},false,{},true)
  a.Caps:K2_SetRelativeLocation({X=0,Y=0,Z=0},false,{},true)
  a.CapsTriggerBox:SetAbsolute(false,false,true);a.CapsTriggerBox:SetWorldScale3D({X=1,Y=1,Z=1});a.CapsTriggerBox:SetBoxExtent({X=4,Y=4,Z=4},false)
  a.CanBeAttachedToTheCar=true
  return r
 end
 function V.maintain(r)
  local a=r.actor
  if a.TankMesh:IsVisible()then a.TankMesh:SetVisibility(false,false)end
  if a.Caps:IsVisible()then a.Caps:SetVisibility(false,false)end
 end
 function V.reset()V.materials={}end
 return V
end

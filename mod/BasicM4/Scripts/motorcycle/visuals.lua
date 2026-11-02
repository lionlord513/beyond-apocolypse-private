return function(root,valid)
 local V={};local geom,materials={},{}
 local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
 local system=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local tireRadius=32.22805 -- measured from both imported tire meshes, centimetres
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local pivots={front={X=83.82057,Y=0,Z=-17.14414},rear={X=-72.104,Y=0,Z=-17.14414},steer={X=37.5,Y=0,Z=43.75},frontpaint={X=37.5,Y=0,Z=43.75},body={X=0,Y=0,Z=0},paint={X=0,Y=0,Z=0},rearpaint={X=0,Y=0,Z=0}}
 local function texture(a,file,data)
  local render=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
  local t=render:ImportFileAsTexture2D(a,root..'/assets/'..file)
  assert(valid(t),'Missing bike texture '..file)
  if data and t.SRGB==true then t=render:ImportFileAsTexture2D(a,root..'/assets/'..file:gsub('%.png$','-srgb.png'));assert(valid(t),'Missing encoded bike data '..file)end
  return t
 end
 local finishes={SuzukiDetail='suzuki/albedo.png',['Llanta.001']='motorcycle/texture0.png',['Cromo.001']='motorcycle/texture1.png',['Cromo.002']='motorcycle/texture2.png',Cromo='motorcycle/steel.png'}
 local function tangents(g)
  if g.tangents then return g.tangents end
  local out={};for i=1,#g.vertices do out[i]={TangentX={X=1,Y=0,Z=0},bFlipTangentY=false}end
  for k=1,#g.triangles,3 do
   local ia,ib,ic=g.triangles[k]+1,g.triangles[k+1]+1,g.triangles[k+2]+1
   local a,b,c=g.vertices[ia],g.vertices[ib],g.vertices[ic];local u,v,w=g.uv[ia],g.uv[ib],g.uv[ic]
   local e={X=b.X-a.X,Y=b.Y-a.Y,Z=b.Z-a.Z};local f={X=c.X-a.X,Y=c.Y-a.Y,Z=c.Z-a.Z}
   local du,dv=v.X-u.X,v.Y-u.Y;local eu,ev=w.X-u.X,w.Y-u.Y;local determinant=du*ev-eu*dv
   if math.abs(determinant)>1e-8 then
    local t={X=(e.X*ev-f.X*dv)/determinant,Y=(e.Y*ev-f.Y*dv)/determinant,Z=(e.Z*ev-f.Z*dv)/determinant}
    local bit={X=(f.X*du-e.X*eu)/determinant,Y=(f.Y*du-e.Y*eu)/determinant,Z=(f.Z*du-e.Z*eu)/determinant}
    for _,i in ipairs({ia,ib,ic})do local n=g.normals[i];local dot=t.X*n.X+t.Y*n.Y+t.Z*n.Z
     local x,y,z=t.X-dot*n.X,t.Y-dot*n.Y,t.Z-dot*n.Z;local length=math.sqrt(x*x+y*y+z*z)
     if length>1e-8 then x,y,z=x/length,y/length,z/length
      local cross={X=n.Y*z-n.Z*y,Y=n.Z*x-n.X*z,Z=n.X*y-n.Y*x}
      out[i]={TangentX={X=x,Y=y,Z=z},bFlipTangentY=(cross.X*bit.X+cross.Y*bit.Y+cross.Z*bit.Z)<0}
     end
    end
   end
  end
  g.tangents=out;return out
 end
 local function material(a,key)
  if valid(materials[key])then return materials[key]end
  if key=='SuzukiDetail'or key=='SuzukiMetal'or key=='Cromo'then
   local suzuki=key=='SuzukiDetail';local suzukiMetal=key=='SuzukiMetal';local folder=suzuki and 'suzuki/'or 'motorcycle/'
   local m=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(a,a.VehicleMesh:GetMaterial(0).Parent,FName('BA_Bike_'..key),0)
   m:SetTextureParameterValue(FName('TextureColor'),texture(a,folder..(suzuki and 'readable-albedo.png'or 'silver-detail.png')))
   m:SetTextureParameterValue(FName('TextureColorMask'),texture(a,'motorcycle/no-tint-mask.png'))
   m:SetTextureParameterValue(FName('TextureCleanNormal'),texture(a,(suzukiMetal and 'suzuki/render-normal.png'or folder..(suzuki and 'render-normal.png'or 'paint-metal-normal.png')),true))
   m:SetTextureParameterValue(FName('TextureCleanORM'),texture(a,folder..(suzuki and 'render-orm.png'or 'silver-orm.png'),true))
   m:SetTextureParameterValue(FName('ClearCoatTexture'),texture(a,'gyrocopter/clean-ao.png'))
   m:SetScalarParameterValue(FName('Rust and wear'),0);m:SetScalarParameterValue(FName('Polish'),.65)
   materials[key]=m;return m
  end
  local m=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(a,LoadAsset('/MasterWeapon/Materials/Weapons/MAT_ArK47.MAT_ArK47'),FName('BA_Bike_'..key),0)
  m:SetTextureParameterValue(FName('Diffuse'),texture(a,assert(finishes[key])))
  m:SetTextureParameterValue(FName('NormalMap'),texture(a,key=='SuzukiDetail'and 'suzuki/normal.png'or 'gyrocopter/plastic-normal.png'))
  m:SetTextureParameterValue(FName('RoughnessMap'),texture(a,key=='SuzukiDetail'and 'suzuki/roughness.png'or key=='Llanta.001'and 'gyrocopter/carrier-roughness.png'or 'gyrocopter/roughness.png'))
  m:SetTextureParameterValue(FName('MetalMap'),texture(a,key=='SuzukiDetail'and 'suzuki/metal.png'or key=='Llanta.001'and 'rifle-metal.png'or key=='Cromo'and 'gyrocopter/clean-ao.png'or 'gyrocopter/metal.png'))
  m:SetTextureParameterValue(FName('AOMap'),texture(a,key=='SuzukiDetail'and 'suzuki/ao.png'or 'gyrocopter/clean-ao.png'))
  m:SetScalarParameterValue(FName('AODarkness'),0)
  m:SetScalarParameterValue(FName('RoughnessBrightness'),key=='Llanta.001'and 1 or .9)
  m:SetScalarParameterValue(FName('DiffuseBrightness'),1);materials[key]=m;return m
 end
 function V.create(a,frame,variant)
  local cfg=variant=='suzuki'and dofile(root..'/Scripts/motorcycle/suzuki.lua')or nil
  local pivots=cfg and cfg.pivots or pivots;local folder=cfg and cfg.dir or 'motorcycle'
  local v={components={},config=cfg};local cls=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
  local ok,err=pcall(function()
  local paint=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(a,a.VehicleMesh:GetMaterial(0).Parent,FName('BA_MotorcyclePaint'),0)
  for key,file in pairs({TextureCleanNormal=cfg and 'suzuki/render-normal.png'or 'motorcycle/paint-metal-normal.png',TextureCleanORM=cfg and 'suzuki/render-orm.png'or 'motorcycle/paint-metal-orm.png',ClearCoatTexture='gyrocopter/clean-ao.png',TextureColor=cfg and 'suzuki/readable-albedo.png'or 'motorcycle/paint-metal-detail.png',TextureColorMask='gyrocopter/clean-ao.png'})do paint:SetTextureParameterValue(FName(key),texture(a,file,key=='TextureCleanNormal'or key=='TextureCleanORM'))end
  v.paintMaterial=paint
  for _,part in ipairs({'body','paint','rearpaint','steer','frontpaint','front','rear'})do
   local c=a:AddComponentByClass(cls,true,identity,false);assert(valid(c),'Motorcycle mesh unavailable');v.components[#v.components+1]=c
   c:K2_AttachToComponent(frame,FName('BA_MotorcycleVisual_'..part),0,0,0,false);c:K2_SetRelativeLocation(pivots[part],false,{},true);c:SetIsReplicated(false)
   if cfg and cfg.visualScale then local s=cfg.visualScale;c:SetRelativeScale3D({X=s,Y=s,Z=s})end
   local key=folder..'/'..part;geom[key]=geom[key]or dofile(root..'/assets/'..key..'.lua')
   local painted=part=='paint'or part=='frontpaint'or part=='rearpaint'
   for i,g in ipairs(geom[key])do c:CreateMeshSection(i-1,g.vertices,g.triangles,g.normals,g.uv,{},tangents(g),painted);c:SetMaterial(i-1,painted and paint or material(a,g.material))end
   c:SetCollisionEnabled(0);c:SetCullDistance(45000)
   if painted then c:SetCollisionResponseToAllChannels(0);c:SetCollisionResponseToChannel(3,2);c:SetCollisionEnabled(1);c:SetGenerateOverlapEvents(false);a.MaterialDynComponent:AddDynMaterial(c,'BA_Motorcycle_'..part,paint)end
   v[part]=c
  end
  a.MaterialDynComponent:ProcessDynParam()
  end)
  if not ok then for _,c in ipairs(v.components)do if valid(c)then c:K2_DestroyComponent(a)end end;error(err)end
  -- Retry/reconstruction must replace only this carrier's tagged presentation.
  local keep={};for _,c in ipairs(v.components)do keep[c:GetAddress()]=true end
  for _,item in ipairs(a:K2_GetComponentsByClass(cls))do local c=item:get();if valid(c)and not keep[c:GetAddress()]and c.AttachSocketName:ToString():match('^BA_MotorcycleVisual_')then c:K2_DestroyComponent(a)end end
  return v
 end
 local traceColor={R=0,G=0,B=0,A=1}
 local function centerHeight(r,part,w,other,fallback,refresh,parked)
  local tireRadius=r.visual.config and r.visual.config.tireRadius or tireRadius
  -- Use the actual native physics-wheel centre, not its spring-length estimate.
  -- Imported tires are larger than the donor wheels; align their lowest point
  -- with the donor contact without changing suspension, collision or handling.
  if valid(w.WheelController)and valid(other.WheelController)then
   local p,q=w.WheelController:K2_GetComponentLocation(),other.WheelController:K2_GetComponentLocation()
   local center=mathlib:InverseTransformLocation((r.neutralFrame or r.frame:K2_GetComponentToWorld()),{X=(p.X+q.X)*.5,Y=(p.Y+q.Y)*.5,Z=(p.Z+q.Z)*.5})
   local a,b={},{};w:GetWheelRadius(a);other:GetWheelRadius(b)
   if type(a.BrakePressure)=='number'and type(b.BrakePressure)=='number'then
    local radius=(a.BrakePressure+b.BrakePressure)*.5;local nominal=center.Z+tireRadius-radius+(r.frameFitZ or 0)
    if refresh and parked and radius>10 and radius<60 then
      local top={X=(p.X+q.X)*.5,Y=(p.Y+q.Y)*.5,Z=(p.Z+q.Z)*.5+45}
      if r.config and r.config.visualScale then local pivot=r.config.pivots[part];local at=mathlib:TransformLocation((r.neutralFrame or r.frame:K2_GetComponentToWorld()),{X=pivot.X,Y=0,Z=nominal});top.X,top.Y=at.X,at.Y end
      local bottom={X=top.X,Y=top.Y,Z=top.Z-150};local hit={}
      if system:LineTraceSingle(r.actor,top,bottom,0,false,{r.actor},0,hit,true,traceColor,traceColor,0)and hit.ImpactPoint and hit.ImpactNormal and hit.ImpactNormal.Z>.6 then
       local gap=(p.Z+q.Z)*.5-radius-hit.ImpactPoint.Z
       if gap>-10 and gap<45 then
        local previous=r.ground and r.ground[part]
        local ground=hit.ImpactPoint.Z
        if previous then ground=previous+math.max(-2,math.min(2,ground-previous))end
        r.ground[part]=ground
       end
      end
    end
    if parked and r.ground and r.ground[part]then
     local point={X=(p.X+q.X)*.5,Y=(p.Y+q.Y)*.5,Z=r.ground[part]+tireRadius+.5}
     if r.config and r.config.visualScale then local pivot=r.config.pivots[part];local at=mathlib:TransformLocation((r.neutralFrame or r.frame:K2_GetComponentToWorld()),{X=pivot.X,Y=0,Z=nominal});point.X,point.Y=at.X,at.Y end
     local ground=mathlib:InverseTransformLocation((r.neutralFrame or r.frame:K2_GetComponentToWorld()),point).Z
     if math.abs(ground-nominal)<45 then return ground end
    end
    return nominal
   end
  end
  return fallback
 end
 function V.singleSkid(r)
  if r.skidOriginal then return end;r.skidOriginal={}
  for _,w in ipairs({r.actor.Vehicle_Wheel_DriverFront,r.actor.Vehicle_Wheel_PassengerFront,r.actor.Vehicle_Wheel_PassengerBack})do
   r.skidOriginal[#r.skidOriginal+1]={wheel=w,enabled=w.SkidParticles};w.SkidParticles=false;w:CleanupSkidParticle()
  end
 end
 function V.restoreSkid(r)
  for _,s in ipairs(r.skidOriginal or{})do if valid(s.wheel)then s.wheel.SkidParticles=s.enabled end end;r.skidOriginal=nil
 end
 function V.centerSkid(r,w)
  if not valid(w)or w:GetAddress()~=r.actor.Vehicle_Wheel_DriverBack:GetAddress()then return end
  local tr=(r.neutralFrame or r.frame:K2_GetComponentToWorld())
  for _,name in ipairs({'ActiveSkidParticle','SkidParticleNiagara'})do local c=w[name];if valid(c)then
   local p=mathlib:InverseTransformLocation(tr,c:K2_GetComponentLocation());p.Y=0
   c:K2_SetWorldLocation(mathlib:TransformLocation(tr,p),false,{},true)
  end end
 end
 function V.install(B)
  if V.skidHook then return end
  local cls=FindObject('BlueprintGeneratedClass','Vehicle_Wheel_C');if not valid(cls)then return end
  local path=cls:GetFullName():gsub('^%S+ ','')..':UpdateSkidEffects';if not valid(StaticFindObject(path))then return end
  V.skidHook={RegisterHook(path,function(ctx)local w=ctx:get();local a=valid(w)and w.Vehicle
   local r=valid(a)and B.tracked[a:GetFullName()];if r and not r.failed then V.centerSkid(r,w)end
  end)}
 end
 function V.tick(r,dt)
  local a,v=r.actor,r.visual;local pivots=v.config and v.config.pivots or pivots;local fw,rw=a.Vehicle_Wheel_DriverFront,a.Vehicle_Wheel_DriverBack
  -- The motorcycle grips have a shorter usable arc than the donor steering rack.
  -- Keep the entire visible fork/wheel/handlebar assembly within rider reach.
  local angle=(fw:GetSteeringAngle()+a.Vehicle_Wheel_PassengerFront:GetSteeringAngle())*.25;r.steerAngle=angle
  local frontSpring=(fw.WheelData.CurrentSpringLength+a.Vehicle_Wheel_PassengerFront.WheelData.CurrentSpringLength)*.5
  local rearSpring=(rw.WheelData.CurrentSpringLength+a.Vehicle_Wheel_PassengerBack.WheelData.CurrentSpringLength)*.5
  v.steer:K2_SetRelativeRotation({Pitch=0,Yaw=angle,Roll=0},false,{},true);v.frontpaint:K2_SetRelativeRotation({Pitch=0,Yaw=angle,Roll=0},false,{},true)
  local velocity=a:GetVelocity();local speed2=velocity.X^2+velocity.Y^2+velocity.Z^2
  local still=speed2<(r.parked and 30^2 or 12^2)and math.abs(r.presentationAngle or 0)<.01;r.parked=still
  local refresh=still and(not r.groundAt or r.last>=r.groundAt)
  if not still then r.ground=nil;r.groundAt=nil elseif not r.ground then r.ground={}end
  local heights={front=centerHeight(r,'front',fw,a.Vehicle_Wheel_PassengerFront,fw.RelativeLocation.Z-frontSpring-r.frame.RelativeLocation.Z+9.23,refresh,still),
   rear=centerHeight(r,'rear',rw,a.Vehicle_Wheel_PassengerBack,rw.RelativeLocation.Z-rearSpring-r.frame.RelativeLocation.Z+9.23,refresh,still)}
  if refresh then r.groundAt=(r.last or 0)+.25 end
  v.frontpaint:K2_SetRelativeLocation({X=pivots.frontpaint.X,Y=pivots.frontpaint.Y,Z=pivots.frontpaint.Z+heights.front-pivots.front.Z},false,{},true)
  if valid(v.rearpaint)then v.rearpaint:K2_SetRelativeLocation({X=0,Y=0,Z=heights.rear-pivots.rear.Z+2.5*(v.config and v.config.visualScale or 1)},false,{},true)end
  for _,t in ipairs({{'front',fw},{'rear',rw}})do
   local part,w=t[1],t[2];local spin=w:GetWheelAngVelInRadians()
   if still and math.abs(spin)<.08 then spin=0 end -- filter visible idle wheel creep only
   r[part..'Spin']=((r[part..'Spin']or 0)-spin*dt*180/math.pi)%360
   v[part]:K2_SetRelativeRotation({Pitch=r[part..'Spin'],Yaw=part=='front'and angle or 0,Roll=0},false,{},true)
   if part=='front'then local rad=angle*math.pi/180;local dx=pivots.front.X-pivots.steer.X
    v.front:K2_SetRelativeLocation({X=pivots.steer.X+dx*math.cos(rad),Y=dx*math.sin(rad),Z=heights.front},false,{},true)
   else
    v.rear:K2_SetRelativeLocation({X=pivots.rear.X,Y=0,Z=heights.rear},false,{},true)
   end
  end
  v.paintMaterial:SetScalarParameterValue(FName('Rust and wear'),0)
 end
 function V.reset()materials={}end
 V.pivots=pivots;V.tangents=tangents;return V
end



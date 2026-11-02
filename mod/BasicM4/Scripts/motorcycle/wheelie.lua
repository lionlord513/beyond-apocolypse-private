-- Held-X rear-contact pivot of the bike, saddle/rider and native service parts.
-- Native AVS driving/steering/collision/suspension/weight are unchanged.
return function(M,B,H,valid,log)
 local W={maxAngle=35,borrowed={},pending={},sequence=0};local none=FName('None')
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
 local function clamp(x,a,b)return math.max(a,math.min(b,x))end
 local function approach(x,y,rate,dt)return x+clamp(y-x,-rate*dt,rate*dt)end
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 function W.step(s,x,dt)
  local held=x.held and x.ready
  s.angle=approach(s.angle or 0,held and W.maxAngle or 0,held and 14 or 20,clamp(dt,0,.1))
  s.active=s.angle>0;return s.angle
 end
 function W.input(pc)return pc:IsInputKeyDown({KeyName=FName('X')})end
 function W.install()
  if W.hook then return end
  W.hook={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,arg)
   local ok,text=pcall(function()return arg:get():ToString()end);if not ok or #text>40 or #W.pending>=32 then return end
   local seq,held=text:match('^BAMW1|(%d+)|([01])$');seq=tonumber(seq)
   if seq and seq<2147483647 then W.pending[#W.pending+1]={pc=ctx:get(),seq=seq,held=held=='1'}end
  end)}
 end
 function W.process()
  local queue=W.pending;W.pending={}
  for _,q in ipairs(queue)do
   local pc=q.pc
   if valid(pc)and pc:HasAuthority()and valid(pc.Vehicle)then
    local r=B.tracked[pc.Vehicle:GetFullName()]
    if r and not r.failed and same(r.actor.Driver,pc.PlayerControlled)and (not r.remoteWheelie or q.seq>r.remoteWheelie.seq)then
     r.remoteWheelie={pc=pc,seq=q.seq,held=q.held,at=game:GetTimeSeconds(r.actor)}
    end
   end
  end
 end
 function W.pose(r,angle)
  if not valid(r.actor)or not valid(r.frame)or not valid(r.actor.VehicleMesh)then return end
  local a,cfg=r.actor,r.config;local parent=a.VehicleMesh:K2_GetComponentToWorld()
  local base={X=17.2,Y=0,Z=26.76+(cfg and cfg.frameOffsetZ or 0)}
  local function transform()
   local p=mathlib:TransformLocation(parent,base)
   return {Translation={X=p.X,Y=p.Y,Z=p.Z},Rotation={X=parent.Rotation.X,Y=parent.Rotation.Y,Z=parent.Rotation.Z,W=parent.Rotation.W},Scale3D={X=parent.Scale3D.X,Y=parent.Scale3D.Y,Z=parent.Scale3D.Z}}
  end
  local tr=transform();local rear=cfg and cfg.pivots.rear or {X=-72.104,Y=0,Z=-17.14414}
  local tire=cfg and cfg.tireRadius or 32.22805;local z=rear.Z;local fit=0
  local rw,other=a.Vehicle_Wheel_DriverBack,a.Vehicle_Wheel_PassengerBack
  if valid(rw.WheelController)and valid(other.WheelController)then
   local p,q=rw.WheelController:K2_GetComponentLocation(),other.WheelController:K2_GetComponentLocation()
   local center=mathlib:InverseTransformLocation(tr,{X=(p.X+q.X)*.5,Y=(p.Y+q.Y)*.5,Z=(p.Z+q.Z)*.5});local radius={};rw:GetWheelRadius(radius)
   if type(radius.BrakePressure)=='number'then
    if cfg and cfg.visualScale then
     local origin=mathlib:TransformLocation(tr,{X=0,Y=0,Z=0});local forward=mathlib:TransformLocation(tr,{X=1,Y=0,Z=0});local up=mathlib:TransformLocation(tr,{X=0,Y=0,Z=1});local uz=up.Z-origin.Z
     if math.abs(uz)>.5 then fit=-(rear.X-center.X)*(forward.Z-origin.Z)/uz+(tire-radius.BrakePressure)*(1/uz-1)end
     fit=clamp(fit,-35,35);base.Z=base.Z+fit;tr=transform()
     center=mathlib:InverseTransformLocation(tr,{X=(p.X+q.X)*.5,Y=(p.Y+q.Y)*.5,Z=(p.Z+q.Z)*.5})
    end
    z=center.Z+tire-radius.BrakePressure+fit
   end
  end
  r.frameFitZ=fit;r.neutralFrame=tr;r.presentationAngle=angle
  local rearPoint={X=rear.X,Y=0,Z=z};local spin=angle*math.pi/180
  local rotated={X=rearPoint.X*math.cos(spin)-rearPoint.Z*math.sin(spin),Y=0,Z=rearPoint.X*math.sin(spin)+rearPoint.Z*math.cos(spin)}
  local at={X=base.X+rearPoint.X-rotated.X,Y=0,Z=base.Z+rearPoint.Z-rotated.Z}
  r.frame:K2_SetRelativeLocation(at,false,{},true);r.frame:K2_SetRelativeRotation({Pitch=angle,Yaw=0,Roll=0},false,{},true)
 end
 local function rebuild(ctx)
  StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'):RequestRebuildControlMappingsUsingContext(ctx,true)
 end
 function W.restoreKeys()
  for _,e in ipairs(W.borrowed)do if valid(e.context)and valid(e.action)then e.context:MapKey(e.action,{KeyName=FName('X')})end end
  local contexts={};for _,e in ipairs(W.borrowed)do if valid(e.context)then contexts[e.context:GetAddress()]=e.context end end
  for _,ctx in pairs(contexts)do rebuild(ctx)end
  W.borrowed={};W.driver=nil;W.blocked=nil
 end
 function W.keys()
  W.install();W.process()
  local p,pc=H.GetPlayer(),H.GetPlayerController();local r
  for _,v in pairs(B.tracked)do if not v.failed and valid(v.actor)and same(v.actor.Driver,p)then r=v;break end end
  if not r or not valid(pc)or M.features==false then if W.driver then W.restoreKeys()end;return end
  local id=r.actor:GetAddress();if W.driver==id then return end
  W.restoreKeys();W.driver=id
  local pending={}
  for _,name in ipairs({'Vehicule','Universal'})do
   local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_'..name..'.IMC_'..name)
   if valid(ctx)then ctx.Mappings:ForEach(function(_,value)
    local m=value:get()
    if m.Key.KeyName:ToString()=='X'then
     if #m.Modifiers>0 or #m.Triggers>0 then W.blocked=true
     else pending[#pending+1]={context=ctx,action=m.Action}end
    end
   end)end
  end
  -- Preserve unusual modified native bindings rather than destroying their data.
  if W.blocked then log('Motorcycle wheelie: X has a modified native binding; restore the native X binding before using wheelie');return end
  local contexts={}
  for _,e in ipairs(pending)do e.context:UnmapKey(e.action,{KeyName=FName('X')});W.borrowed[#W.borrowed+1]=e;contexts[e.context:GetAddress()]=e.context end
  for _,ctx in pairs(contexts)do rebuild(ctx)end
 end
 function W.tick(r,dt)
  local a=r.actor;local p,pc=H.GetPlayer(),H.GetPlayerController();local pilot=same(a.Driver,p)and valid(pc)
  local motor=a.CarMotorV2.AttachedCarEquipableActor;local v=a:GetVelocity();local speed=math.sqrt(v.X^2+v.Y^2)
  local stats=valid(a.Driver)and a.Driver.BP_PlayerStats
  local ready=valid(a.Driver)and valid(stats)and not stats.IsDead and not stats.IsDying and valid(motor)and motor.IsStart and a.EngineRunning and not motor.IsHeatLimit and speed>=70 and speed<=2200 and M.features~=false
  local held=false;local state=r.wheelie or{};r.wheelie=state
  if pilot then
   held=ready and not W.blocked and pc.bShowMouseCursor~=true and W.input(pc)or false
   if not pc:HasAuthority()then
    local now=game:GetTimeSeconds(a)
    if state.sent~=held or now>=(state.sendAt or 0)then W.sequence=W.sequence+1;pc:ServerExecRPC('BAMW1|'..W.sequence..'|'..(held and '1'or '0'));state.sent=held;state.sendAt=now+.5 end
   end
  elseif a:HasAuthority()then
   local q=r.remoteWheelie
   held=ready and q and valid(q.pc)and same(q.pc.Vehicle,a)and same(q.pc.PlayerControlled,a.Driver)and game:GetTimeSeconds(a)-q.at<1 and q.held or false
  else W.pose(r,clamp(r.frame.RelativeRotation.Pitch,0,W.maxAngle));return end
  W.pose(r,W.step(state,{held=held,ready=ready},dt))
  if a:HasAuthority()and math.abs((state.netAngle or 0)-state.angle)>.1 then a:FlushNetDormancy();a:ForceNetUpdate();state.netAngle=state.angle end
 end
 function W.clear(r)r.wheelie=nil;r.remoteWheelie=nil;W.pose(r,0);if valid(r.actor)and W.driver==r.actor:GetAddress()then W.restoreKeys()end end
 function W.reset()for _,r in pairs(B.tracked)do W.clear(r)end;W.pending={};W.restoreKeys()end
 return W
end

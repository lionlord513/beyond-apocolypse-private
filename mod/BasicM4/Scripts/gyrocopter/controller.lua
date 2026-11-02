-- Native vehicle carrier: AVS owns wheel contact, engine servicing, seats,
-- saving and network physics. Only marked CaddieCar actors become aircraft.
return function(M,root,H,valid,log)
 local F=dofile(root..'/Scripts/gyrocopter/flight.lua')
 local Simple=dofile(root..'/Scripts/gyrocopter/simple_flight.lua')
 local V=dofile(root..'/Scripts/gyrocopter/visuals.lua')(root,valid)
 local G={tracked={},pending={},nextScan=0,nextWorld=0,known={},sites={},damaged={},propDamaged={},airframes={}}
 local inputs=dofile(root..'/Scripts/gyrocopter/inputs.lua')(G,valid,log)
 local audio=dofile(root..'/Scripts/gyrocopter/audio.lua')(valid)
 local path='/Game/BP/CarsV2/CaddieCar.CaddieCar_C';local markName='BA_Hornet_v1'
 local c=M.config.Gyrocopter or {};local none=FName('None')
 G.config=c
 if c.WorldSpawns==nil then c.WorldSpawns=true end
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local scene=StaticFindObject('/Script/Engine.SceneComponent')
 local primitive=StaticFindObject('/Script/Engine.PrimitiveComponent')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local color={R=0,G=0,B=0,A=1}
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function vec(x,y,z)return {X=x,Y=y,Z=z}end
 local function distance(a,b)local x,y,z=a.X-b.X,a.Y-b.Y,a.Z-b.Z;return math.sqrt(x*x+y*y+z*z)end
 local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
 local function garageId(a)
  local g=a.GuidGarage;if g.A==0 and g.B==0 and g.C==0 and g.D==0 then return end
  return ("%08x:%08x:%08x:%08x"):format(g.A&0xffffffff,g.B&0xffffffff,g.C&0xffffffff,g.D&0xffffffff)
 end
 local function id(a)
  local garage=garageId(a);if garage and G.airframes[garage]then return G.airframes[garage]end
  if not valid(a.CarSeatDriver)then return end
  local s=a.CarSeatDriver.AttachedCarEquipableActor;if not valid(s)then return end
  local g=s.GuidUnique;if g.A==0 and g.B==0 and g.C==0 and g.D==0 then return end
  return ('%08x:%08x:%08x:%08x'):format(g.A&0xffffffff,g.B&0xffffffff,g.C&0xffffffff,g.D&0xffffffff)
 end
 local file=M.statePath and M.statePath('gyrocopters.txt')or root..'/state/gyrocopters.txt'
 do local f=io.open(file,'r');if f then for line in f:lines()do
  local garage,legacy=line:match('^airframe (%x+:%x+:%x+:%x+) (%x+:%x+:%x+:%x+)$');if garage then G.airframes[garage]=legacy end
  local kind,key=line:match('^(%w+) (%x+:%x+:%x+:%x+)$')
  local t=kind=='gyro'and G.known or kind=='site'and G.sites or kind=='damage'and G.damaged or kind=='prop'and G.propDamaged
  if t then t[key]=true elseif kind=='repair'then G.damaged[key]=nil;G.propDamaged[key]=nil end
 end;f:close()end end
 local function remember(kind,key,t)
  if t[key]then return end
  local f=assert(io.open(file,'a'),'Cannot save aircraft identity');f:write(kind..' '..key..'\n');f:close();t[key]=true
 end
 local world=dofile(root..'/Scripts/gyrocopter/world.lua')(G,valid,remember,c)
 local safety=dofile(root..'/Scripts/gyrocopter/safety.lua')(G,valid,remember,sys)
 local function bindIdentity(a,key)
  local garage=assert(garageId(a),'Waiting for native airframe identity')
  if not G.airframes[garage]then
   a.MaterialDynComponent:UpdateDynParam({Key_2_9A8C438B4224A6B1657E3997CF43EB5B=FName('Color'),VectorParameter_12_33A11DA14457E338EF9919B9B47CA282={R=.025,G=.22,B=.7,A=1},ScalarParameter_8_52C9880A475C4002B11BC8A2E153EE81=0,IsScalarParameter_11_EA81612E4CFE7ABB1E2351A611997EA1=false},false)
   local f=assert(io.open(file,'a'));assert(f:write('airframe '..garage..' '..key..'\n'));assert(f:close());G.airframes[garage]=key end
 end
 local function marker(a)
  for _,v in ipairs(a:K2_GetComponentsByClass(scene))do local o=v:get();if valid(o)and o.AttachSocketName:ToString():lower()==markName:lower()then return o end end
 end
 local function move(comp,x,y,z)
  if valid(comp)then comp:K2_SetRelativeLocation(vec(x,y,z),false,{},true)end
 end
 local function keepServiceMount(comp,x,y,z)
  if not valid(comp)then return end
  local at=comp.RelativeLocation
  -- Native refitting can restore the carrier's original connector position.
  -- Correct only changed Hornet mounts; never move loose parts or ordinary cars.
  if math.abs(at.X-x)>.01 or math.abs(at.Y-y)>.01 or math.abs(at.Z-z)>.01 then move(comp,x,y,z)end
 end
 local function hideActor(a)
  if valid(a)then a:SetActorHiddenInGame(true)end
 end
 local function configure(a)
  local owns=G.simulates(a)
  -- Keep native collision and suspension, with a single nose contact and two
  -- main wheels. Attached native consumables still have their own mass.
  a.StabilityControl=false;a.StabilityControlBase=0;a.DriftAssist=false;a.DynamicAirDrag=false
  a.BaseWeight=250;a.BaseLinearDrag=.04;if owns then a:WeightTimerEvent()end
  inputs.configure(a);a.EnableAutoLevel=false;a.EnableAutopilot=false;a.TwoWheelBalance=false;a.EnableTwoWheelAssist=false
  a.WingLiftCoefficient=0;a.WingDrag=0;a.WingLinearDrag=0;a.WingAoADrag=0;a.AeroLateralGrip=0
  a.WingImbalance=0;a.WingImbalanceStrength=0;a.AirBrakeDrag=0;a.AirBrakeLiftLoss=0;a.MaxAeroSpeed=0
  -- MaxAeroSpeed=0 removes the speed-squared term, not physical speed.
  -- Rotor authority keeps cyclic/yaw consistent from hover through a dive.
  a.WingControlAuthority=.004;a.WingControlDamping=.001;a.BankTurnRate=0;a.MaxPitchAngle=180
  a.EnableRotor=true;a.RotorThrust=0;a.RotorInput=0;a.RotorControlAuthority=500
  a.EnableBoost=true;a.BoostForce=0;a.BoostInput=0;a.BoostRampRate=0
  a.CanHitch=false;a.CanBeRetourned=true
  if owns then
   a.VehicleMesh:SetMassOverrideInKg(none,250,true);a.VehicleMesh:SetAngularDamping(.8);a.VehicleMesh:SetLinearDamping(.04)
   a:SetExactCenterOfMass(vec(40,0,60))
  end
  a.VehicleMesh:SetVisibility(false,false)
  for _,v in ipairs(a:K2_GetComponentsByClass(primitive))do
   local comp=v:get();if valid(comp)and not comp:IsA(pmc)then comp:SetVisibility(false,false)end
  end
  move(a.CarSeatDriver,70,0,52);move(a.CarMotorV2,-12,0,124)
  move(a.CarTankGasV2,-15,34,77);move(a.CarRadiatorV2,-38,-28,105);move(a.CarBatteryV2,30,-24,68)
  move(a.CarStarterV2,86,0,92);move(a.CarSteeringWheelV2,84,0,78)
  a.CarSeatDriver.CanBeRemoved=true;a.CarSeatDriver.CarEquipableActorClass=LoadAsset('/Game/BP/CarsV2/System/Actors/Master/CarItemSeat.CarItemSeat_C')
  if valid(a.CarSeatDriver1)then
   a.CarSeatDriver1.CanBeRemoved=false;local s=a.CarSeatDriver1.AttachedCarEquipableActor
   if valid(s)then s.CanPlayerAttach=false;s.CanBeUsed=false end
  end
  local placements={{a.Vehicle_Wheel_DriverFront,144.4,0,31},{a.Vehicle_Wheel_DriverBack,13.6,-87.9,31},{a.Vehicle_Wheel_PassengerBack,13.6,87.9,31},{a.Vehicle_Wheel_PassengerFront,-138.2,0,44}}
  for _,w in ipairs(placements)do
   local wheel=w[1];move(wheel,w[2],w[3],w[4])
   wheel.WheelConfig.IsDrivingWheel=false
   if owns then wheel:SetWheelTorque(true,0,0,false)end
   wheel.WheelConfig.AutoWheelRadius=false;wheel.WheelConfig.WheelRadius=w[2]<0 and 5.75 or w[2]>140 and 9.4 or 12.8
   wheel.WheelConfig.IsSteerableWheel=same(wheel,a.Vehicle_Wheel_DriverFront)
   if owns then wheel:UpdateWheelRadius();wheel:UpdateLocalTransformCache()end;wheel.PhysicsDownforce=0
   if valid(wheel.WheelMeshComponent)then wheel.WheelMeshComponent:SetVisibility(false,true)end
  end
  if owns then a.Vehicle_Wheel_PassengerFront:SetIsSimulatingSuspension(true)end
  a.Vehicle_Wheel_PassengerFront.WheelConfig.IsDrivingWheel=false
  if owns then a:UpdateInternalWheelArray()end
  a.CarEquipableComponents:ForEach(function(_,v)
   local s=v:get();if valid(s)then
    local kind=s:GetFullName():match('^(%S+)')
    s.CanBeRemoved=same(s,a.CarSeatDriver)or kind=='CarMotorV2_C'or kind=='CarBatteryV2_C'or kind=='CarRadiatorV2_C'or kind=='CarTankGasV2_C'
    local part=s.AttachedCarEquipableActor
    if kind=='CarRimV2_C'then
     -- Native rim updates reapply the connector's drive flag to WheelConfig.
     s.IsDrivingWheel=false
     if valid(part)then part.IsDrivingWheel=false;part['Is Driving Wheel']=false end
    end
    if valid(part)then
     -- Servicing uses the game's actual fuel/oil/coolant/battery actors.
     local service=same(s,a.CarSeatDriver)or kind=='CarMotorV2_C'or kind=='CarRadiatorV2_C'or kind=='CarTankGasV2_C'or kind=='CarBatteryV2_C'
     part:SetActorHiddenInGame(not service)
    end
   end
  end)
 end
 function G.mark(a,missingEngine)
  assert(valid(a)and a:HasAuthority(),'Aircraft spawn requires the host')
  local key=assert(id(a),'Waiting for native pilot seat')
  bindIdentity(a,key)
  remember('gyro',key,G.known)
  if G.damaged[key]or G.propDamaged[key]then
   local f=assert(io.open(file,'a'));f:write('repair '..key..'\n');f:close();G.damaged[key]=nil;G.propDamaged[key]=nil
  end
  local m=marker(a)
  if not m then
   m=a:AddComponentByClass(scene,true,identity,false);assert(valid(m),'Aircraft marker unavailable')
   m:SetVisibility(false,false);m:K2_AttachToComponent(a.VehicleMesh,FName(markName),0,0,0,false);m:SetIsReplicated(true)
  end
  if missingEngine and valid(a.CarMotorV2.AttachedCarEquipableActor)then
   local engine=a.CarMotorV2.AttachedCarEquipableActor;a.CarMotorV2:DettachAttachedCarEquipableActor(true)
   if valid(engine)then engine:K2_DestroyActor()end
  end
  m:SetRelativeScale3D(vec(1,1,1))
  a:FlushNetDormancy();a:ForceNetUpdate();return a
 end
 local function adopt(a,fromHost)
  local key=a:GetFullName();if G.tracked[key]and same(G.tracked[key].actor,a)then return G.tracked[key]end
  local initialized={};a:GetInitializationState(initialized)
  if not initialized.Initialized or not valid(a.VehicleMesh)or not valid(a.CarSeatDriver)or not valid(a.CarMotorV2)then return end
  local m=marker(a)
  if not valid(m)and fromHost and not a:HasAuthority()then
   m=a:AddComponentByClass(scene,true,identity,false);assert(valid(m));m:SetVisibility(false,false)
   m:K2_AttachToComponent(a.VehicleMesh,FName(markName),0,0,0,false);m:SetIsReplicated(false)
  end
  if not valid(m)then return end
  if a:HasAuthority()then bindIdentity(a,assert(id(a),'Waiting for aircraft identity'))end
  local visual=V.create(a)
  local ok,why=pcall(configure,a)
  if not ok then for _,comp in ipairs(visual.components or{})do if valid(comp)then comp:K2_DestroyComponent(a)end end;error(why)end
  local r={actor=a,mark=m,flight=F.new(),visual=visual,throttle=0,last=game:GetTimeSeconds(a),collisionAt=0,settleAt=game:GetTimeSeconds(a)+4}
  a:SetActorHiddenInGame(false)
  G.tracked[key]=r;return r
 end
 function G.clearance(context,q)
  local hit={};local top=vec(q.X,q.Y,q.Z+1000);local bottom=vec(q.X,q.Y,q.Z-2000)
  if not sys:LineTraceSingle(context,top,bottom,0,false,{},0,hit,true,color,color,0)or hit.ImpactNormal.Z<.97 then return end
  local p=hit.ImpactPoint;local at=vec(p.X,p.Y,p.Z+175);local roof={}
  if sys:BoxTraceSingle(context,at,vec(at.X,at.Y,at.Z+1),vec(380,380,145),{Pitch=0,Yaw=0,Roll=0},0,false,{},0,roof,true,color,color,0)then return end
  -- Four ground samples reject ledges and terrain hidden under the rotor disc.
  for _,d in ipairs({{270,0},{-270,0},{0,270},{0,-270}})do
   local h={};if not sys:LineTraceSingle(context,vec(p.X+d[1],p.Y+d[2],p.Z+150),vec(p.X+d[1],p.Y+d[2],p.Z-150),0,false,{},0,h,true,color,color,0)or math.abs(h.ImpactPoint.Z-p.Z)>35 then return end
  end
  return vec(p.X,p.Y,p.Z+70)
 end
 function G.create(p,missingEngine,at,worldSpawn)
  assert(valid(p)and p:HasAuthority(),'Aircraft spawning requires server authority')
  if not at then
   local q,f=p:K2_GetActorLocation(),p:GetActorForwardVector()
   for _,n in ipairs({1200,1800,2400,3000})do at=G.clearance(p,vec(q.X+f.X*n,q.Y+f.Y*n,q.Z));if at then break end end
  end
  assert(at,'Move to open, level ground: the rotor needs eight metres of clearance')
  local tr={Translation=at,Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
  local a=game:BeginDeferredActorSpawnFromClass(p,LoadAsset(path),tr,1,nil,0);assert(valid(a),'Native aircraft carrier unavailable')
  a:SetActorHiddenInGame(true);a.SpawnWithOriginalPart=true;game:FinishSpawningActor(a,tr,0)
  local pending={actor=a,missing=missingEngine~=false,worldSpawn=worldSpawn,readyAt=game:GetTimeSeconds(p)+3,expires=game:GetTimeSeconds(p)+15};G.pending[#G.pending+1]=pending
  return a,pending
 end
 function G.spawn(missingEngine,at,worldSpawn)return G.create(H.GetPlayer(),missingEngine,at,worldSpawn)end
 local function newFinish(a,wild)
  for name,value in pairs({['Rust and wear']=wild and .65 or 0,Polish=wild and 0 or .8})do
   a.MaterialDynComponent:UpdateDynParam({Key_2_9A8C438B4224A6B1657E3997CF43EB5B=FName(name),VectorParameter_12_33A11DA14457E338EF9919B9B47CA282={R=0,G=0,B=0,A=1},ScalarParameter_8_52C9880A475C4002B11BC8A2E153EE81=value,IsScalarParameter_11_EA81612E4CFE7ABB1E2351A611997EA1=true},false)
  end
 end
 function G.stripPurchase(r)
  local a=r.actor;assert(a:HasAuthority()and r.newAirframe,'Only new host purchases can be stripped')
  local J=G.transport.journal;J.writable();local key=assert(id(a));J.state.issued[key]=true
  for _,slot in ipairs({a.CarSeatDriver,a.CarSeatDriver1,a.CarMotorV2,a.CarBatteryV2,a.CarRadiatorV2,G.transport.blades.slot(a,1),G.transport.blades.slot(a,2)})do
   if valid(slot)then local part=slot.AttachedCarEquipableActor;if valid(part)then slot:DettachAttachedCarEquipableActor(true);part:K2_DestroyActor()end end
  end
  r.newAirframe=nil;r.worldSpawn=nil;a:FlushNetDormancy();a:ForceNetUpdate()
 end
 local function down(pc,k)return pc:IsInputKeyDown({KeyName=FName(k)})end
 local function localInput(a,r,dt)
  local pc=H.GetPlayerController();local p=H.GetPlayer()
  if not valid(pc)or not same(a.Driver,p)then return 0,0,0,0 end
  if p.BP_PlayerStats.IsDead or p.BP_PlayerStats.IsDying then return 0,0,0,-1 end
  if pc.HUD.ChatUI.TypeInChat or H.IsPauseMenu(pc)or M.devmenu.ui.opened or M.backpack.ui.opened or(M.utility and M.utility.opened) then return 0,0,0,0 end
  if M.controls then local d=function(id)return M.controls.down(pc,id)and 1 or 0 end;return d('pitchBack')-d('pitchForward'),d('rollRight')-d('rollLeft'),d('yawRight')-d('yawLeft'),d('collectiveUp')-d('collectiveDown')end
  local pitch=((down(pc,'S')or down(pc,'Down'))and 1 or 0)-((down(pc,'W')or down(pc,'Up'))and 1 or 0)
  local roll=((down(pc,'D')or down(pc,'Right'))and 1 or 0)-((down(pc,'A')or down(pc,'Left'))and 1 or 0)
  local collective=((down(pc,'LeftShift')or down(pc,'RightShift'))and 1 or 0)-((down(pc,'LeftControl')or down(pc,'RightControl'))and 1 or 0)
  return pitch,roll,(down(pc,'E')and 1 or 0)-(down(pc,'Q')and 1 or 0),collective
 end
 G.readControls=localInput
 local function ground(a)
  local contact=false;a.Wheels:ForEach(function(_,v)local w=v:get();if valid(w)and w:GetIsSimulatingSuspension()and w:GetHasContact()then contact=true end end);return contact
 end
 function G.simulates(a)
  local out={};a:isOwningClient(out);return out.OwningClient==true
 end
 function G.update(r,now)
  local a=r.actor;if not valid(a)or not valid(a.VehicleMesh)then return end
  keepServiceMount(a.CarRadiatorV2,-38,-28,105)
  keepServiceMount(a.CarBatteryV2,30,-24,68)
  local dt=F.clamp(now-r.last,0,.1);r.last=now;if dt<=0 then return end
  -- Dock transitions take priority over delayed setup and engine/flight writes.
  if G.transport and G.transport.hold(r,now)then G.nativeTow.restore(r);audio.tick(r,now);return end
  if G.nativeTow.hold(r,now)then V.tick(r.visual,r.flight,0);audio.tick(r,now);return end
  local simulates=G.simulates(a)
  if r.wasSimulating~=simulates then
   -- A late join may first encounter this aircraft while docked. Hold skips
   -- normal setup, so nil is also an ownership acquisition on first release.
   if simulates and(r.wasSimulating==false or not r.settleAt)then configure(a);r.simpleFlight=nil;r.settleAt=nil;r.engineAlignAt=now+.5 end
   r.wasSimulating=simulates;r.result=nil
   if not simulates then a.RotorInput=0;a.BoostInput=0;a.AirPitchInput=0;a.AirRollInput=0;a.AirYawInput=0 end
   log('Hornet flight owner '..tostring(simulates)..' '..a:GetFullName())
  end
  if not simulates then
   r.result=nil
   local s=r.netState or r.telemetry
   r.flight.bladeMask=G.transport.blades.mask(r)
   if s then r.flight.rpm=s.rpm or 0;r.flight.propRPM=s.propRPM or 0 end
   local viewer=H.GetPlayer();local dist=valid(viewer)and distance(viewer:K2_GetActorLocation(),a:K2_GetActorLocation())or 100000
   V.tick(r.visual,r.flight,dist);audio.tick(r,now);return
  end
  if r.settleAt and now>=r.settleAt then r.settleAt=nil;configure(a);r.simpleFlight=nil;r.engineAlignAt=now+.5 end
  local v=a.VehicleMesh:GetPhysicsLinearVelocity(none);local f=a:GetActorForwardVector();local right=a:GetActorRightVector();local up=a:GetActorUpVector()
  local motor=a.CarMotorV2.AttachedCarEquipableActor
  local running=valid(motor)and motor.IsStart and a.EngineRunning and not motor.IsHeatLimit
  local bladeMask=G.transport and G.transport.blades and G.transport.blades.mask(r)or 3
  if bladeMask~=3 then running=false end
  r.flight.bladeMask=bladeMask
  local power=0
  if valid(motor)then
   if not same(r.motor,motor)then
    if valid(r.motor)and r.motorPop~=nil then r.motor.CanPopAndBang=r.motorPop end
    r.motor=motor;r.motorPop=motor.CanPopAndBang;r.ratedPower=0;r.engineAlignAt=now+.5
    motor.Gears:ForEach(function(_,v)local gear=v:get();r.ratedPower=math.max(r.ratedPower,gear.MaxTorque*gear.HighRPM*1.5)end)
    r.ratedPower=math.max(r.ratedPower,0)
   end
   motor.CanPopAndBang=false
   if now>=(r.exhaustAt or 0)then
    r.exhaustAt=now+1
    motor.ExhaustPipe:ForEach(function(_,v)local pipe=v:get();if valid(pipe)then
     if valid(pipe.PopAndBang)then pipe.PopAndBang:Stop()end
    end end)
   end
   if r.engineAlignAt and now>=r.engineAlignAt then G.service.engine(r);r.engineAlignAt=nil end
   -- The native motor multiplier already includes its fitted turbo output.
   power=r.ratedPower*math.max(motor.TorqueMultiplier,0)
  end
  if not valid(motor)and valid(r.motor)and r.motorPop~=nil then r.motor.CanPopAndBang=r.motorPop;r.motor=nil end
  audio.tick(r,now)
  local pitch,roll,yaw,collective=G.readControls(a,r,dt);local onGround=ground(a)
  local rot=a:K2_GetActorRotation()
  local simple=M.controls and M.controls.simpleFlight and same(a.Driver,H.GetPlayer())or false
  if r.simpleFlight~=simple then
   r.flight.lastPitch=nil;r.flight.lastRoll=nil
   if r.simpleFlight==true and not simple then
    local available=(power*.72*math.sqrt(2*1.225*34.4))^(2/3)*F.clamp((r.flight.rpm-70)/290,0,1)^2*.8
    r.flight.collective=available>0 and F.clamp(r.flight.lift/available,0,1)or 0
   end
   a.BaseLinearDrag=simple and .15 or .04;a.MaxPitchAngle=simple and 35 or 180
   a.VehicleMesh:SetAngularDamping(simple and 1.4 or .8);a.VehicleMesh:SetLinearDamping(simple and .15 or .04)
   r.simpleFlight=simple
  end
  local result=(simple and Simple or F).step(r.flight,{forward=dot(v,f)*.01,lateral=dot(v,right)*.01,vertical=v.Z*.01,up=up.Z,mass=a.VehicleMesh:GetMass(),
   running=running,bladeMask=bladeMask,power=power,engineRPM=a.RPM,pitch=pitch,roll=roll,yaw=yaw,collectiveInput=collective,ground=onGround,
   attitudePitch=rot.Pitch,attitudeRoll=rot.Roll,noPilot=not valid(a.Driver)},dt)
  r.result=result;r.onGround=onGround;r.running=running
  -- Govern engine load instead of repeatedly racing the native car engine.
  -- The native engine still owns fuel/oil use, heat, starter and failure checks.
  a:SetThrottleInput(result.governor)
  inputs.apply(r)
  a.StabilityControl=false
  local p=H.GetPlayer();local dist=valid(p)and distance(p:K2_GetActorLocation(),a:K2_GetActorLocation())or 100000
  V.tick(r.visual,r.flight,dist)
  G.transport.sync.telemetry(r,now)
  safety.check(r,now)
  if valid(p)and same(a.Driver,p)and c.ShowHUD~=false and now>=(G.hudAt or 0)then
   G.hudAt=now+.10;G.hudOwned=true;G.hudRecord=r
   local warning=bladeMask~=3 and 'FIT BOTH MAIN BLADES / LEFT CLICK AT ROTOR MAST' or not running and 'START ENGINE / I' or result.lowRotor and 'ROTOR SPOOLING UP' or (r.bladeWarningUntil or 0)>now and 'BLADES NEAR OBSTACLE' or 'MANUAL FLIGHT'
   if M.controls then warning=warning:gsub('START ENGINE / I','START ENGINE / '..M.controls.values.ignition[1])end
   if simple then
    if warning=='MANUAL FLIGHT'then warning='SIMPLE FLIGHT'end
    M.devmenu.ui.hud(('HORNET\n%s\nROTOR %.0f rpm  |  AIR %.0f km/h\nCLIMB %+.1f m/s\nHold raise / lower to climb / descend\nRelease to auto-hover\nF9: controls and settings'):format(warning,result.rpm,result.airspeed*3.6,v.Z*.01))
   else
    M.devmenu.ui.hud(('HORNET\n%s\nROTOR %.0f rpm  |  AIR %.0f km/h\nCLIMB %+.1f m/s  |  COLLECTIVE %.1f%%\nF9: controls and keybindings\nCollective holds when released\nFlare to slow; lower collective to land'):format(warning,result.rpm,result.airspeed*3.6,v.Z*.01,result.collective*100),result.collective,result.hoverCollective,v.Z*.01)
   end
  end
 end
 function G.tick(p,now)
  if c.Enabled==false then return end
  for _,q in ipairs(G.pending)do if valid(q.actor)then
   q.actor:SetActorHiddenInGame(true)
   q.actor.CarEquipableComponents:ForEach(function(_,v)local slot=v:get();if valid(slot)and valid(slot.AttachedCarEquipableActor)then slot.AttachedCarEquipableActor:SetActorHiddenInGame(true)end end)
  end end
  if G.transport then G.transport.tick(p,now)end
  G.service.tick(now)
  inputs.install(now)
  if G.seats then G.seats.tick(now)end
  for key,r in pairs(G.tracked)do
   if not valid(r.actor)then
    if valid(r.motor)and r.motorPop~=nil then r.motor.CanPopAndBang=r.motorPop end
    G.tracked[key]=nil
   else
    local shown,e=pcall(V.maintain,r,now,G.transport.blades.items)
    if not shown and r.presentationError~=tostring(e)then r.presentationError=tostring(e);log('Hornet presentation: '..r.presentationError)end
    if not r.failed then local ok,e=pcall(G.update,r,now);if not ok then r.failed=true;pcall(G.nativeTow.restore,r);log('Gyrocopter: '..tostring(e));r.actor.RotorInput=0;r.actor.BoostInput=0 end end
   end
  end
  if G.hudOwned then local pc=H.GetPlayerController();if not valid(pc)or not valid(pc.Vehicle)or not G.tracked[pc.Vehicle:GetFullName()]then M.devmenu.ui.hud(nil);G.hudOwned=false end end
  if now<G.nextScan then return end;G.nextScan=now+1
  for i=#G.pending,1,-1 do
   local r=G.pending[i]
   if not valid(r.actor)then table.remove(G.pending,i);if r.onFailure then r.onFailure()end
   elseif now>r.expires then r.actor:K2_DestroyActor();table.remove(G.pending,i);if r.onFailure then r.onFailure()end;log('Aircraft spawn cancelled: native parts did not initialize')
   elseif now>=r.readyAt and id(r.actor)then G.mark(r.actor,r.missing);local ar=adopt(r.actor);if ar then ar.newAirframe=true;ar.worldSpawn=r.worldSpawn;newFinish(ar.actor,r.worldSpawn and not r.bare);if r.bare then G.stripPurchase(ar)end;table.remove(G.pending,i)end
   end
  end
  for _,a in ipairs(FindAllOf('CaddieCar_C')or{})do
   if valid(a)and not G.tracked[a:GetFullName()]then
    if a:HasAuthority()then local key=id(a);if key and G.known[key]and not marker(a)then G.mark(a,false)end end
    if marker(a)then
     local ok,e=pcall(adopt,a)
     if not ok and G.adoptError~=tostring(e)then G.adoptError=tostring(e);log('Hornet setup: '..G.adoptError)end
    end
   end
  end
  world.tick(p,now)
 end
 function G.current()
  local pc=H.GetPlayerController();local a=valid(pc)and pc.Vehicle
  assert(valid(a)and G.tracked[a:GetFullName()],'Sit in the Hornet pilot seat first');return G.tracked[a:GetFullName()]
 end
 function G.repair()
  local r=G.current();assert(r.onGround and not r.running,'Park and stop the engine before servicing the airframe')
  local key=assert(id(r.actor));local f=assert(io.open(file,'a'));f:write('repair '..key..'\n');f:close()
  G.damaged[key]=nil;G.propDamaged[key]=nil;r.flight.damage=0;r.flight.propDamage=false;r.flight.rpm=0;r.flight.collective=0
  r.mark:SetRelativeScale3D(vec(1,1,1));r.actor:FlushNetDormancy();r.actor:ForceNetUpdate()
 end
 function G.reset()for _,r in pairs(G.tracked)do G.nativeTow.restore(r);if valid(r.motor)and r.motorPop~=nil then r.motor.CanPopAndBang=r.motorPop end end;G.service.reset();G.tracked={};G.pending={};G.nextScan=0;G.nextWorld=0;G.hudOwned=false;G.hudAt=0;V.reset();world.reset();if G.transport then G.transport.reset()end end
 G.service=dofile(root..'/Scripts/gyrocopter/service.lua')(M,G,valid,log)
 G.seats=dofile(root..'/Scripts/gyrocopter/seats.lua')(M,G,H,valid,log)
 G.id=id;G.adopt=adopt;G.flight=F;G.inputs=inputs;G.visuals=V;G.audio=audio
 G.nativeTow=dofile(root..'/Scripts/gyrocopter/native_tow.lua')(G,valid)
 G.transport=dofile(root..'/Scripts/gyrocopter/transport.lua')(M,G,root,H,valid,log)
 return G
end

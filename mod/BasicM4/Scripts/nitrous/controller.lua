-- Native containers, free-placement attachments and AVS force integration.
return function(M,root,H,valid,enqueue,log)
 local N={items={},cars={},incoming={},requests={},nextAt=0,nextLoot=0}
 N.catalog=dofile(root..'/Scripts/nitrous/catalog.lua');N.policy=dofile(root..'/Scripts/nitrous/policy.lua')
 N.fluid=dofile(root..'/Scripts/nitrous/fluid.lua')(valid)
 N.visuals=dofile(root..'/Scripts/nitrous/visuals.lua')(root,valid)
 N.effects=dofile(root..'/Scripts/nitrous/effects.lua')(H,valid)
 N.journal=dofile(root..'/Scripts/nitrous/journal.lua')(root,M.gyrocopter.transport.journal,valid,log,M.statePath)
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics');local scene=StaticFindObject('/Script/Engine.SceneComponent')
 local carClass=StaticFindObject('/Script/VehicleSystemPlugin.VehicleSystemBase')
 local path='/Game/BP/Items/Movable/TankContainer/GasBarrelGaz_2.GasBarrelGaz_2_C'
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function live(r)return r and valid(r.actor)and r.actor:GetFullName()==r.key end
 local function bottle(a)return valid(a)and a:GetFullName():match('^GasBarrelGaz_2_C ')end
 local function marker(a)
  for _,v in ipairs(a:K2_GetComponentsByClass(scene))do local c=v:get();local id=valid(c)and tonumber(c.AttachSocketName:ToString():match('^BA_Nitrous_([1-6])$'));if id then return id,c end end
 end
 function N.info(a)
  if not bottle(a)then return end;local r=N.items[a:GetFullName()];if live(r)then return r.def,r end
  local id=N.journal.state.bottle[M.guid(a)];if not id then id=marker(a)end;return id and N.catalog[id]
 end
 function N.adopt(a,id,fill)
  assert(bottle(a)and N.fluid.install(),'Nitrous donor unavailable');local d=assert(N.catalog[id],'Invalid bottle variant')
  local key=a:GetFullName();local r=N.items[key]
  if r and same(r.actor,a)then return r end
  local old,mark=marker(a)
  if a:HasAuthority()then
   N.journal.writable();local guid=assert(M.guid(a),'Bottle identity not ready')
   local saved=N.journal.state.bottle[guid];assert(not saved or saved==id,'Bottle variant mismatch')
   if not mark then mark=a:AddComponentByClass(scene,true,identity,false);assert(valid(mark));mark:SetVisibility(false,false);mark:K2_AttachToComponent(a.TankMesh,FName('BA_Nitrous_'..id),0,0,0,false);mark:SetIsReplicated(true)end
   a.ItemTankComponent.MaxQuantity=d.litres;a.ItemTankComponent.AllFluidAccepted=true
   a.OvverideMass=d.dryMass;a.BaseMass=d.dryMass
   -- Fill exactly once when creating a new bottle. Restores never refill it.
   if fill and not saved then a.ItemTankComponent:EmptyTank();N.fluid.set(a.ItemTankComponent,d.litres,H.GetPlayer())end
   a.ItemTankComponent:UpdateOwnerWeight();N.journal.state.bottle[guid]=id;a:FlushNetDormancy();a:ForceNetUpdate()
  else a.ItemTankComponent.MaxQuantity=d.litres end
  r={actor=a,key=key,def=d,mark=mark};N.items[key]=r;N.visuals.apply(r,d);return r
 end
 function N.spawn(p,id,at)
  assert(valid(p)and p:HasAuthority()and M.features~=false,'Nitrous spawning requires the host')
  N.journal.load(game:GetGameInstance(p).MainSaveGame);N.journal.writable();assert(N.fluid.install())
  if not at then local q,f=p:K2_GetActorLocation(),p:GetActorForwardVector();at={X=q.X+f.X*180,Y=q.Y+f.Y*180,Z=q.Z+10}end
  local tr={Translation=at,Rotation=identity.Rotation,Scale3D=identity.Scale3D}
  local a=game:BeginDeferredActorSpawnFromClass(p,LoadAsset(path),tr,1,nil,0);assert(valid(a),'Native bottle could not spawn')
  local ok,e=pcall(function()game:FinishSpawningActor(a,tr,0);if not M.guid(a)then a.GuidUnique=StaticFindObject('/Script/Engine.Default__KismetGuidLibrary'):NewGuid()end;N.adopt(a,id,true)end)
  if not ok then a:K2_DestroyActor();error(e)end;return a
 end
 function N.parent(a)
  if not bottle(a)then return end
  -- Follow the actual attachment, including engines/doors, rather than stale
  -- save metadata that can arrive before fitting or survive a detach.
  local car=a:GetAttachParentActor();for _=1,8 do if not valid(car)then return end;if car:IsA(carClass)then return car end;car=car:GetAttachParentActor()end
 end
 function N.ground(a)
  local result=false;a.Wheels:ForEach(function(_,v)local w=v:get();if valid(w)and w:GetIsSimulatingSuspension()and w:GetHasContact()then result=true end end);return result
 end
 function N.held(pc)
  local p=valid(pc)and pc.PlayerControlled
  if not valid(p)or p.BP_PlayerStats.IsDead or p.BP_PlayerStats.IsDying or H.IsPauseMenu(pc)or M.utility.opened or M.devmenu.ui.opened or M.backpack.ui.opened then return false end
  if valid(pc.HUD)and valid(pc.HUD.ChatUI)and pc.HUD.ChatUI.TypeInChat then return false end
  return pc:IsInputKeyDown({KeyName=FName('LeftShift')})or pc:IsInputKeyDown({KeyName=FName('RightShift')})
 end
 local function record(a)
  local key=a:GetFullName();local r=N.cars[key]
  if not r then r={actor=a,key=key,items={},active=false,litres=0,capacity=0,tier=0};N.cars[key]=r end;return r
 end
 function N.apply(r,acceleration)
  if not live(r)then return end;local a=r.actor
  if M.gyrocopter.tracked[r.key]then return end
  local owns={};a:isOwningClient(owns);if not owns.OwningClient then return end
  if acceleration>0 then
   if not r.original then r.original={enabled=a.EnableBoost,force=a.BoostForce,ramp=a.BoostRampRate,input=a.BoostInput,lift=a.BoostLiftBonus}end
   a.EnableBoost=true;a.BoostForce=acceleration*a.VehicleMesh:GetMass();a.BoostRampRate=0;a.BoostLiftBonus=0;a.BoostInput=1
  elseif r.original then
   local old=r.original;a.BoostInput=0;a.EnableBoost=old.enabled;a.BoostForce=old.force;a.BoostRampRate=old.ramp;a.BoostLiftBonus=old.lift;r.original=nil
  end
  r.applied=acceleration
 end
 function N.stop(r)N.apply(r,0);r.active=false;r.acceleration=0;if N.effects then N.effects.update(r,false)end end
 local function sample(r,held,dt,remote)
  local a=r.actor;local chosen,total,capacity=nil,0,0
  for _,v in ipairs(r.items)do local q=N.fluid.quantity(v.actor.ItemTankComponent);total=total+q;capacity=capacity+v.def.litres
   if q>.0001 and(not chosen or v.def.tier>chosen.def.tier)then chosen=v end
  end
  r.litres=total;r.capacity=capacity;r.tier=chosen and chosen.def.tier or 0
  if not chosen then return 0,0 end
  local motor=a.CarMotorV2.AttachedCarEquipableActor;local velocity=a.VehicleMesh:GetPhysicsLinearVelocity(FName('None'));local f=a:GetActorForwardVector()
  local speed=(velocity.X*f.X+velocity.Y*f.Y+velocity.Z*f.Z)*.01
  local throttle,brakes={},{};a:GetThrottleAndBrake(throttle,brakes)
  local state={held=held,driver=valid(a.Driver),running=valid(motor)and motor.IsStart and a.EngineRunning and not motor.IsHeatLimit,
   ground=remote or N.ground(a),brake=brakes.Brake or 0,handbrake=a.HandbrakeApplied,reverse=speed<-.5 or a.CurrentGear<0,
   up=a:GetActorUpVector().Z,litres=N.fluid.quantity(chosen.actor.ItemTankComponent),tier=chosen.def.tier,speed=speed,
   throttle=throttle.Throttle or 0,steering=tonumber(a.SteeringInput)or 0,paused=game:IsGamePaused(a)}
  local acceleration,used=N.policy.output(state,dt)
  if used>0 then N.fluid.set(chosen.actor.ItemTankComponent,state.litres-used,a.Driver);r.litres=math.max(0,total-used)end
  return acceleration,used
 end
 function N.rebuild()
  for _,r in pairs(N.cars)do r.items={}end
  for key,r in pairs(N.items)do
   if not bottle(r.actor)or r.actor:GetFullName()~=key then N.items[key]=nil
   else
    local car=N.parent(r.actor)
    if valid(car)and not M.gyrocopter.tracked[car:GetFullName()]then local c=record(car);c.items[#c.items+1]=r end
   end
  end
  for key,r in pairs(N.cars)do if not live(r)then N.cars[key]=nil elseif #r.items==0 then N.stop(r);N.effects.clear(r);N.cars[key]=nil end end
 end
 function N.discover(now)
  if not N.seeded then for _,a in ipairs(FindAllOf('GasBarrelGaz_2_C')or{})do N.incoming[#N.incoming+1]={actor=a,tries=0}end;N.seeded=true end
  if not N.nameHook then local namePath='/Game/BP/Items/Master/ItemBaseMaster.ItemBaseMaster_C:GetName'
   if valid(StaticFindObject(namePath))then N.nameHook={RegisterHook(namePath,function(ctx,name)
    local a=ctx:get();if not bottle(a)then return end;local r=N.items[a:GetFullName()];if live(r)then name:set(FText(r.def.name))end
   end)}end
  end
  if now>=(N.visualAt or 0)then N.visualAt=now+.5;for _,r in pairs(N.items)do if live(r)then N.visuals.maintain(r)end end end
  local incoming=N.incoming;N.incoming={}
  for i,q in ipairs(incoming)do
   if i>16 or q.at and now<q.at then N.incoming[#N.incoming+1]=q
   elseif bottle(q.actor)then
    local d=N.info(q.actor)
    if d then N.adopt(q.actor,d.id,false)
    elseif q.tries<30 then q.tries=q.tries+1;q.at=now+.5;N.incoming[#N.incoming+1]=q end
   end
  end
 end
 function N.ambient(p,now)
  if now<N.nextLoot or not p:HasAuthority()or game:GetGameInstance(p).IsSaving or N.journal.error then return end;N.nextLoot=now+12
  local gs=game:GetGameState(p);local spawner=valid(gs)and gs.LSLevelSpawner;if not valid(spawner)then return end
  local J=N.journal;local pos=p:K2_GetActorLocation();local selected
  -- Reuse native streamed level descriptors; no actor searches or new streaming requests.
  spawner.LevelsRep:ForEach(function(_,v)
   if selected then return end;local level=v:get();if not level.HasBeenInitialized then return end
   local q=level.Transform.Translation;local d=(q.X-pos.X)^2+(q.Y-pos.Y)^2
   if d<800^2 or d>18000^2 then return end
   local key=level.WorldSoftObjectPtrPath:ToString():gsub('%s','_')..('@%.0f,%.0f,%.0f'):format(q.X,q.Y,q.Z)
   local h=N.policy.hash(tostring(gs.Seed)..'|'..key)
   if not J.state.site[key]and h%100<8 then selected={key=key,pos={X=q.X+((h//100)%9-4)*80,Y=q.Y+((h//1000)%9-4)*80,Z=q.Z},variant=h%10==0 and 4+(h//10)%3 or 1+(h//10)%3}end
  end)
  if not selected then return end
  local q=selected.pos;local hit={};local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');local color={R=0,G=0,B=0,A=0}
  if sys:LineTraceSingle(p,{X=q.X,Y=q.Y,Z=q.Z+1800},{X=q.X,Y=q.Y,Z=q.Z-400},0,false,{},0,hit,true,color,color,0)and hit.ImpactNormal.Z>.85 then
   local at=hit.ImpactPoint;local check={};local height=N.catalog[selected.variant].height
   if not sys:BoxTraceSingle(p,{X=at.X,Y=at.Y,Z=at.Z+height*.5+3},{X=at.X,Y=at.Y,Z=at.Z+height*.5+3.1},{X=height*.15,Y=height*.15,Z=height*.5},{Pitch=0,Yaw=0,Roll=0},0,false,{},0,check,true,color,color,0)then
    N.spawn(p,selected.variant,{X=at.X,Y=at.Y,Z=at.Z+4});J.state.site[selected.key]=true
   end
  end
 end
 N.net=dofile(root..'/Scripts/nitrous/network.lua')(N,M,H,valid,enqueue,log)
 local function tick(p,now)
  if M.features==false or not N.fluid.install()then return end
  N.net.install()
  if p:HasAuthority()then N.journal.load(game:GetGameInstance(p).MainSaveGame)end
  N.net.input(now)
  if now<N.nextAt then return end
  local dt=N.last and math.min(.15,math.max(0,now-N.last))or .1;N.last=now;N.nextAt=now+.1
  N.discover(now);N.rebuild()
  for _,r in pairs(N.cars)do
   local a=r.actor
   if a:HasAuthority()then
    -- Driving possesses the vehicle; the seated human is no longer possessed.
    local driver=a.Driver;local pc=a:GetController();local held=false;local remote=valid(pc)and not pc:IsLocalPlayerController()
    if valid(pc)then
     if remote then local req=N.requests[pc:GetAddress()];held=req and same(req.car,a)and now-req.at<.5 and req.held or false
     else held=N.held(pc)end
    end
    local acceleration=sample(r,held,dt,remote);r.acceleration=acceleration;r.active=acceleration>0
    N.apply(r,acceleration);N.net.publish(r,now)
   else
    local packet=r.net;local acceleration=packet and now-packet.at<.5 and packet.acceleration or 0
    if same(a.Driver,p)and(not N.held(H.GetPlayerController())or not N.ground(a))then acceleration=0 end
    r.active=acceleration>0;r.acceleration=acceleration;N.apply(r,acceleration)
   end
   if N.effects then N.effects.update(r,r.active)end
  end
  N.ambient(p,now)
 end
 function N.tick(p,now)
  if now<(N.errorUntil or 0)then return end
  local ok,e=pcall(tick,p,now)
  if not ok then
   -- An unavailable native field/effect can never leave a force latched on.
   for _,r in pairs(N.cars)do if live(r)then pcall(N.stop,r);pcall(N.effects.clear,r)end end
   N.errorUntil=now+5
   if N.lastError~=tostring(e)then N.lastError=tostring(e);log('Nitrous disabled this tick: '..N.lastError)end
  end
 end
 function N.reset()
  for _,r in pairs(N.cars)do if live(r)then N.stop(r);N.effects.clear(r)end end
  N.items={};N.cars={};N.incoming={};N.requests={};N.seeded=nil;N.nextAt=0;N.visualAt=0;N.nextLoot=0;N.last=nil;N.errorUntil=nil;N.journal.reset();N.visuals.reset();N.net.reset()
 end
 NotifyOnNewObject(path,function(a)if #N.incoming<512 then N.incoming[#N.incoming+1]={actor=a,tries=0}end end)
 return N
end

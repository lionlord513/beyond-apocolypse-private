return function(B,valid)
 local R={};local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
 local left={parent='steer',at={X=-40,Y=-40,Z=17},rotation={Pitch=0,Yaw=0,Roll=-90}}
 local right={parent='steer',at={X=-40,Y=40,Z=17},rotation={Pitch=0,Yaw=180,Roll=90}}
 local lf={parent='frame',at={X=0,Y=-26,Z=-20},rotation={Pitch=0,Yaw=0,Roll=0}}
 local rf={parent='frame',at={X=0,Y=26,Z=-20},rotation={Pitch=0,Yaw=180,Roll=180}}
 local lb={parent='frame',at={X=15,Y=-26,Z=-26},rotation=lf.rotation}
 local rb={parent='frame',at={X=15,Y=26,Z=-26},rotation=rf.rotation}
 local targets={LeftHandWheelMapSocket=left,RightHandWheelMapSocket=right,TransitionSocketLeftHand=left,TransitionSocketRightHand=right,GearLevierRightHand=right,PlayerLeftFoot=lf,PlayerRightFoot=rf,FootBallPedalL=lb,FootBallPedalLeft=lb,FootBallPedalR=rb,FootBallPedalRight=rb}
 function R.apply(p)
  if not valid(p)or not valid(p.Mesh)then return end
  -- A native Driver reference can lag during seat changes. Bind IK to the
  -- actual attached saddle so two motorcycles cannot compete for one rider.
  local saddle=p:GetAttachParentActor();if not valid(saddle)then return end
  local r
  for _,v in pairs(B.tracked)do if valid(v.actor)and valid(v.actor.Driver)and v.actor.Driver:GetAddress()==p:GetAddress()and valid(v.actor.CarSeatDriver.AttachedCarEquipableActor)and v.actor.CarSeatDriver.AttachedCarEquipableActor:GetAddress()==saddle:GetAddress()then r=v;break end end
  if not r or not r.visual then return end
  local anim=p.Mesh:GetAnimInstance();if not valid(anim)then return end
  -- Capture transforms once per application; both native IK and fallback
  -- callers remain active. Separate ankle/foot-ball targets remain unchanged.
  local steer=r.visual.steer:K2_GetComponentToWorld()
  local frame=r.frame:K2_GetComponentToWorld()
  local mesh=p.Mesh:K2_GetComponentToWorld()
  -- Keep the native driving hand pose and suppress the car's gear-lever reach.
  anim.IsChangingGear=false
  anim.MapSocketVehicle:ForEach(function(key,value)
   local name=key:get():ToString();local d=targets[name];if not d then return end
   if r.config and d.parent=='steer'then local hand=name:find('Left',1,true)and 'left'or 'right';d={parent='steer',at=r.config.hands[hand],rotation=d.rotation}end
   if r.config and r.config.feet and d.parent=='frame'then local side=(name:find('Left',1,true)or name:match('L$'))and 'left'or 'right';local foot=side..(name:find('FootBall',1,true)and 'Ball'or '');d={parent='frame',at=r.config.feet[foot],rotation=d.rotation}end
   local world=mathlib:TransformLocation(d.parent=='steer'and steer or frame,d.at)
   local localAt=mathlib:InverseTransformLocation(mesh,world)
   value:get().Translation=localAt
   if d.rotation then
    local rot=mathlib:TransformRotation(d.parent=='steer'and steer or frame,d.rotation)
    value:get().Rotation=mathlib:Conv_RotatorToQuaternion(mathlib:InverseTransformRotation(mesh,rot))
   end
  end)
 end
 function R.install()
  if R.hook and R.seatHooks then return end
  local path='/Game/BP/Player/PlayerBase.PlayerBase_C:UpdateSocketIK'
  -- Resolve the function through the reflected class; asset directory varies by build.
  local cls=FindObject('BlueprintGeneratedClass','PlayerBase_C')
  if valid(cls)then path=cls:GetFullName():gsub('^%S+ ','')..':UpdateSocketIK'end
  if not R.hook and valid(StaticFindObject(path))then R.hook={RegisterHook(path,function(ctx)R.apply(ctx:get())end)}end
  local seatPath='/Game/BP/CarsV2/System/Actors/Master/CarItemSeat.CarItemSeat_C:'
  local function isSaddle(s)
   for _,r in pairs(B.tracked)do if valid(r.actor)and valid(r.actor.CarSeatDriver.AttachedCarEquipableActor)and r.actor.CarSeatDriver.AttachedCarEquipableActor:GetAddress()==s:GetAddress()then return true end end
  end
  if not R.seatHooks and valid(StaticFindObject(seatPath..'GetTertiaryActionName'))then
   R.seatHooks={
    {RegisterHook(seatPath..'GetTertiaryActionName',function(ctx,out)if isSaddle(ctx:get())then out:set(FText(''))end end)},
    {RegisterHook(seatPath..'ExecuteThirdAction',function(ctx)local s=ctx:get();if isSaddle(s)then s.AdjustSeat=0;s:OnRep_AdjustSeat()end end)}
   }
  end
 end
 return R
end

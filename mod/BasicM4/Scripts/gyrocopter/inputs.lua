-- Native vehicle actions also write aircraft axes. Restore our cached output
-- after those events, rather than letting them fight the 20 Hz flight model.
return function(G,valid,log)
 local P={hooks={},errors={},nextAttempt=0}
 local base='/Game/AVS_Template/Template/AVS_Template_Vehicle.AVS_Template_Vehicle_C:'
 local groups={{'MoveCar',32,31},{'MoveCar_Controller',18,17},{'MoveCar_Wheel',16,15},{'LiftUp',14,10},{'LiftDown',9,6},{'Boost',5,1}}
 function P.configure(a)
  -- The current AVS build can permanently switch air control off after the
  -- donor rests on its wheels. The Hornet needs cyclic/yaw after takeoff.
  a.AutoDisableAirControlOnGround=false;a.EnableAirControl=true
 end
 function P.apply(r)
  if not r or r.failed or not r.result or r.towed or not valid(r.actor)then return end
  local a,x=r.actor,r.result
  a.RotorThrust=x.lift;a.RotorInput=x.lift>0 and 1 or 0
  a.BoostForce=x.thrust-x.drag;a.BoostInput=math.abs(a.BoostForce)>.01 and 1 or 0
  a.AirPitchInput=-x.pitch*x.authority
  a.AirRollInput=-x.roll*x.authority;a.AirYawInput=x.yaw*x.authority
 end
 local function afterInput(ctx)
  local a=ctx:get();if not valid(a)then return end
  local r=G.tracked[a:GetFullName()]
  if not r or r.failed then return end
  if r.towed then G.nativeTow.hold(r);return end
  if not r.result then return end
  a:SetThrottleInput(r.result.governor);a:SetBrakeInput(0);a['Set Steering Input'](a,0)
  -- Set Steering Input itself writes AirRollInput. Restore flight axes LAST.
  P.apply(r)
 end
 function P.install(now)
  if P.ready or now<P.nextAttempt then return end;P.nextAttempt=now+2
  local complete=true
  for _,group in ipairs(groups)do for i=group[2],group[3],-1 do
   local path=base..'InpActEvt_'..group[1]..'_K2Node_EnhancedInputActionEvent_'..i
   if not P.hooks[path]then
    if valid(StaticFindObject(path))then
     local ok,a,b=pcall(RegisterHook,path,afterInput)
     if ok then P.hooks[path]={a,b};P.errors[path]=nil
     else complete=false;if not P.errors[path]then log('Hornet input hook: '..tostring(a));P.errors[path]=true end end
    else complete=false end
   end
  end end
  P.ready=complete
 end
 return P
end

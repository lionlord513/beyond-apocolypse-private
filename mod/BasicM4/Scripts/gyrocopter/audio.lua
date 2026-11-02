-- Engine-part audio and the donor vehicle's AVS audio are separate systems.
-- Scope shutdown cleanup to this Hornet; keep ignition/shutdown one-shots,
-- other vehicles, radios and ambient sound under their native handlers.
return function(valid)
 local A={}
 local function stop(c)if valid(c)and c:IsPlaying()then c:Stop()end end
 function A.tick(r,now)
  local a=r.actor;local motor=a.CarMotorV2.AttachedCarEquipableActor
  local docked=valid(r.docked)or r.pendingDock
  if not docked and valid(motor)then
   if motor.IsTryStart then return end
   if motor.IsStart then
    if r.audioQuiet and valid(a.EngineAudio)and not a.EngineAudio.EngineRunning then a.EngineAudio:SetEngineRunning(true)end
    r.audioQuiet=nil;r.audioNext=nil;r.audioMotor=nil;return
   end
  end
  local key=valid(motor)and motor:GetAddress()or 0
  if r.audioQuiet and r.audioMotor==key and now<(r.audioNext or 0)then return end
  r.audioQuiet=true;r.audioMotor=key;r.audioNext=now+.5
  local native=a.EngineAudio
  if valid(native)then
   if native.EngineRunning then native:SetEngineRunning(false)end
   native:ClearStartTimer();native:StopSound()
   stop(native.EngineAudio);stop(native.EngineStartAudio)
  end
  if valid(motor)then
   stop(motor.MotorSound)
   if valid(motor.MotorWwise)then motor.MotorWwise:Stop()end
  end
 end
 return A
end

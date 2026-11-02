return function(G,valid,remember,sys)
 local S={};local color={R=0,G=0,B=0,A=1}
 function S.check(r,now)
  if now<(r.collisionAt or 0)then return end;r.collisionAt=now+.35
  if r.flight.rpm<80 then return end
  local a=r.actor;local ignored={a}
  a.CarEquipableComponents:ForEach(function(_,v)local c=v:get();if valid(c)and valid(c.AttachedCarEquipableActor)then ignored[#ignored+1]=c.AttachedCarEquipableActor end end)
  if valid(a.Driver)then ignored[#ignored+1]=a.Driver end
  local center=r.visual.rotor:K2_GetComponentLocation();local forward=a:GetActorForwardVector();local right=a:GetActorRightVector()
  -- Crossed narrow sweeps avoid the old square's false corner hits. Contact is
  -- advisory: vegetation/fences must never invisibly delete the blades.
  for _,axis in ipairs({forward,right})do
   local hit={};local p={X=center.X-axis.X*315,Y=center.Y-axis.Y*315,Z=center.Z-axis.Z*315}
   local q={X=center.X+axis.X*315,Y=center.Y+axis.Y*315,Z=center.Z+axis.Z*315}
   if sys:SphereTraceSingle(a,p,q,8,0,false,ignored,0,hit,true,color,color,0)then r.bladeWarningUntil=now+1.5;break end
  end
 end
 return S
end

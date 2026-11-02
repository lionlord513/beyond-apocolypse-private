-- Native wearable mesh origins are offset below the visible backpack. Use its
-- bounds for reach, and trace to that same point if native origin LOS fails.
return function(pc,b)
 local p=pc.PlayerControlled;local center,extent={},{}
 b:GetActorBounds(false,center,extent,false)
 local at=p:K2_GetActorLocation();local dx,dy,dz=at.X-center.X,at.Y-center.Y,at.Z-center.Z
 if dx*dx+dy*dy+dz*dz>200*200 then return false end
 if pc:LineOfSightTo(b,{X=0,Y=0,Z=0},false)then return true end
 local eyes,rotation={},{};p:GetActorEyesViewPoint(eyes,rotation)
 local color={R=0,G=0,B=0,A=1};local hit={}
 return not StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):LineTraceSingle(p,eyes,center,0,true,{p,b},0,hit,true,color,color,0)
end

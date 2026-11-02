-- Small host-only idle patrols. Native targeting, attacks and path following win.
return function(M,valid,log)
 local R={records={},nextScan=0,nextThink=0};local world
 local function copy(v)return {X=v.X,Y=v.Y,Z=v.Z}end
 local function dist(a,b)return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2 end
 local function release(r)
  if r.slow and valid(r.actor)and valid(r.actor.CharacterMovement)then
   r.actor.MaxSpeed=r.speed;r.actor.CharacterMovement.MaxWalkSpeed=r.walk;r.slow=false
  end
 end
 function R.reset()for _,r in pairs(R.records)do release(r)end;R.records={};R.nextScan=0;R.nextThink=0;world=nil end
 local function excluded(z,owned)
  if owned[z:GetAddress()]then return true end
  for _,v in ipairs(z:K2_GetComponentsByClass(StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')))do
   local c=v:get();if valid(c)then local s=c.AttachSocketName:ToString():lower();if s=='ba_mechanic_v1'then return true end end
  end
 end
 function R.frame(z,dt)
  if M.active==false or not valid(z)or not z:HasAuthority()then return end
  local r=R.records[z:GetAddress()];if not r or not r.goal or not r.direction then return end
  if z.IsDead or z.IsSpawning or z.angry or z.IsAttacking or z.IsHit then release(r);r.direction=nil;return end
  local q=z:K2_GetActorLocation();if dist(q,r.goal)<100^2 then r.direction=nil;return end
  z.MaxSpeed=65;z.CharacterMovement.MaxWalkSpeed=65
  z:AddMovementInput(r.direction,1,true)
  local rot=z:K2_GetActorRotation();local yaw=math.deg(math.atan(r.direction.Y,r.direction.X));local delta=(yaw-rot.Yaw+180)%360-180
  local step=120*math.min(dt or .016,.1);z:K2_SetActorRotation({Pitch=0,Yaw=rot.Yaw+math.max(-step,math.min(step,delta)),Roll=0},false)
 end
 function R.tick(p,game,now)
  if not p:HasAuthority()then return end
  if not R.hook then R.hook={RegisterHook('/Game/BP/Player/Zombies/BP_Zombie.BP_Zombie_C:ReceiveTick',function(ctx,dt)R.frame(ctx:get(),dt:get())end)}end
  local gs=game:GetGameState(p);if not valid(gs)then return end
  if world and world~=gs:GetAddress()then R.reset()end;world=gs:GetAddress()
  if now>=R.nextScan then
   R.nextScan=now+3;local owned={}
   for _,v in ipairs(M.apocalypse.owned or{})do if valid(v.actor)and(v.runner or v.stopGroup)then owned[v.actor:GetAddress()]=true end end
   for _,z in ipairs(FindAllOf('BP_Zombie_C')or{})do if valid(z)and z:HasAuthority()and not z.IsDead and not excluded(z,owned)then
    local key=z:GetAddress();if not R.records[key]then
     local hash=5381;local name=z:GetFullName();for i=1,#name do hash=(hash*33+name:byte(i))&0xffffffff end
     R.records[key]={actor=z,selected=hash%100<65,anchor=copy(z:K2_GetActorLocation()),next=now+hash%5}
    end
   end end
  end
  if now<R.nextThink then return end;R.nextThink=now+.5
  local ps={};gs.Players:ForEach(function(_,v)local a=v:get();if valid(a)and a.IsLoaded and not a.BP_PlayerStats.IsDead then ps[#ps+1]=copy(a:K2_GetActorLocation())end end)
  local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');local color={R=0,G=0,B=0,A=1}
  for key,r in pairs(R.records)do local z=r.actor
   if not valid(z)or z.IsDead then R.records[key]=nil
   elseif r.selected and valid(z.CharacterMovement)then
    local q=z:K2_GetActorLocation();local near=false;for _,at in ipairs(ps)do if dist(q,at)<15000^2 then near=true;break end end
    if not near or z.IsSpawning or z.angry or z.IsAttacking or z.IsHit then release(r);r.goal=nil;r.direction=nil;r.next=now+3
    else
     if not r.slow then r.speed=z.MaxSpeed;r.walk=z.CharacterMovement.MaxWalkSpeed;r.slow=true end
     z.MaxSpeed=65;z.CharacterMovement.MaxWalkSpeed=65
     if r.goal and(dist(q,r.goal)<100^2 or now>=r.untilTime)then z:StopInputMoving();r.goal=nil;r.next=now+2+math.random()*3 end
     r.direction=nil
     if r.goal then
      local dx,dy=r.goal.X-q.X,r.goal.Y-q.Y;local length=math.sqrt(dx*dx+dy*dy)
      if length>1 then
       local direction={X=dx/length,Y=dy/length,Z=0};local ahead={X=q.X+direction.X*130,Y=q.Y+direction.Y*130,Z=q.Z};local hit={};local ground={}
       local blocked=sys:LineTraceSingle(z,copy(q),ahead,0,false,{z},0,hit,true,color,color,0)
       local supported=sys:LineTraceSingle(z,{X=ahead.X,Y=ahead.Y,Z=q.Z+80},{X=ahead.X,Y=ahead.Y,Z=q.Z-220},0,false,{z},0,ground,true,color,color,0)
       if not blocked and supported and ground.ImpactNormal.Z>.7 then r.direction=direction else z:StopInputMoving();r.goal=nil;r.next=now+1 end
      end
     end
     if not r.goal and now>=r.next then
      r.next=now+4;local angle=math.random()*math.pi*2;local radius=300+math.random()*600
      local at={X=r.anchor.X+math.cos(angle)*radius,Y=r.anchor.Y+math.sin(angle)*radius,Z=r.anchor.Z};local hit={}
      if sys:LineTraceSingle(z,{X=at.X,Y=at.Y,Z=at.Z+500},{X=at.X,Y=at.Y,Z=at.Z-1500},0,false,{z},0,hit,true,color,color,0)and hit.ImpactNormal.Z>.8 then
       local goal=copy(hit.ImpactPoint);goal.Z=goal.Z+90
       z:StopInputMoving();z.RoamingLocation=goal;z.IsRoaming=true;r.goal=goal;r.untilTime=now+22
      end
     end
    end
   end
  end
 end
 return R
end

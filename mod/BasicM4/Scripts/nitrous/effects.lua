-- Reuse the game's exhaust flame, tinted by the active boost stage. No boost audio or dynamic lights.
return function(H,valid)
 local E={};local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local component=StaticFindObject('/Script/Niagara.NiagaraComponent')
 local slotClass;local system
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local function clear(r)
  for _,v in ipairs(r.flames or{})do if valid(v.fx)then pcall(function()v.fx:Deactivate();v.fx:K2_DestroyComponent(r.actor)end)end end;r.flames=nil;r.flameSignature=nil;r.flamesActive=false;r.flameTier=nil
 end
 function E.update(r,active)
  local a=r.actor;if not valid(a)then return end
  local p=H.GetPlayer();if not valid(p)then active=false else local x,y=p:K2_GetActorLocation(),a:K2_GetActorLocation();if (x.X-y.X)^2+(x.Y-y.Y)^2+(x.Z-y.Z)^2>16000^2 then active=false end end
  if not active then if r.flamesActive then for _,v in ipairs(r.flames or{})do if valid(v.fx)then v.fx:Deactivate()end end end;r.flamesActive=false;return end
  local now=game:GetTimeSeconds(a)
  if not r.flames or now>=(r.flameCheck or 0)then
   r.flameCheck=now+1;slotClass=slotClass or LoadAsset('/Game/BP/CarsV2/System/Components/CarExhaustPipeV2.CarExhaustPipeV2_C')
   local anchors={};local signature={}
   for _,v in ipairs(a:K2_GetComponentsByClass(slotClass))do if #anchors<4 then
    local slot=v:get();local part=slot.AttachedCarEquipableActor;local anchor=slot;local native=false
    if valid(part)then for _,v in ipairs(part:K2_GetComponentsByClass(component))do local c=v:get();if valid(c)then anchor=c;native=true;break end end end
    anchors[#anchors+1]={anchor=anchor,native=native};signature[#signature+1]=anchor:GetFullName()
   end end
   local key=table.concat(signature,'|')
   if key~=r.flameSignature then
    clear(r);r.flameSignature=key;r.flames={}
    system=valid(system)and system or LoadAsset('/Game/Realistic_Starter_VFX_Pack_Niagara/Niagara/MuzzleFlash/NS_Backfire.NS_Backfire')
    for _,anchor in ipairs(anchors)do for phase=0,1 do
     local fx=a:AddComponentByClass(component,true,identity,false);assert(valid(fx),'Nitrous exhaust unavailable')
     r.flames[#r.flames+1]={fx=fx,phase=phase}
     fx:SetAutoActivate(false);fx:Deactivate();fx:SetAsset(system,false);fx:K2_AttachToComponent(anchor.anchor,FName('None'),0,0,0,false)
     if not anchor.native then fx:K2_SetRelativeRotation({Pitch=270.23,Yaw=0,Roll=0},false,{},true)end
     fx:SetRelativeScale3D({X=.85,Y=.85,Z=1.15});fx:SetVariableLinearColor(FName('User.User_ColorTint'),{R=.04,G=.38,B=2.5,A=1});fx:SetCastShadow(false);fx:SetCullDistance(16000)
    end end
   end
  end
  local tier=r.tier==2 and 2 or 1
  if r.flameTier~=tier then
   local tint=tier==2 and {R=1.35,G=.05,B=2.5,A=1}or {R=.04,G=.38,B=2.5,A=1}
   for _,v in ipairs(r.flames or{})do if valid(v.fx)then v.fx:SetVariableLinearColor(FName('User.User_ColorTint'),tint)end end
   r.flameTier=tier
  end
  -- Two retained bursts overlap at each tip, producing an uninterrupted flame.
  -- Only alternate components restart; nothing is spawned or searched each pulse.
  if now>=(r.flamePulseAt or 0)or not r.flamesActive then
   r.flamePulseAt=now+.095;r.flamePhase=1-(r.flamePhase or 0)
   for _,v in ipairs(r.flames)do if v.phase==r.flamePhase and valid(v.fx)then v.fx:Activate(true)end end
  end
  r.flamesActive=true
 end
 E.clear=clear;return E
end

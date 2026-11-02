-- First-person presentation only. Native bullets, damage and remote poses stay native.
return function(M,root,H,valid,enqueue,log)
 local V={blend=0};local mathlib
 local akSight=dofile(root..'/Scripts/weapons/ak_sight.lua')
 V.slots=dofile(root..'/Scripts/weapons/slots.lua')(M,H,valid,enqueue)
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function copy(tr)return {Translation={X=tr.Translation.X,Y=tr.Translation.Y,Z=tr.Translation.Z},Rotation={X=tr.Rotation.X,Y=tr.Rotation.Y,Z=tr.Rotation.Z,W=tr.Rotation.W},Scale3D={X=tr.Scale3D.X,Y=tr.Scale3D.Y,Z=tr.Scale3D.Z}}end
 local function opacity(o,hidden,key)
  V.overlays=V.overlays or {};local old=V.overlays[key]
  if old and (not hidden or not same(old.widget,o))then if valid(old.widget)then old.widget:SetRenderOpacity(old.opacity)end;V.overlays[key]=nil;old=nil end
  if hidden and valid(o)then if not old then old={widget=o,opacity=o.RenderOpacity};V.overlays[key]=old end;o:SetRenderOpacity(0)end
 end
 local function unchanged(a,b)
  if not b then return false end
  for _,part in ipairs({'Translation','Rotation','Scale3D'})do for key,value in pairs(b[part])do if math.abs(a[part][key]-value)>.001 then return false end end end
  return true
 end
 local function reticle(active,hud)
  if active and (not valid(V.dot)or not same(V.dotHUD,hud))then
   if valid(V.dot)then V.dot:RemoveFromParent()end;if valid(V.glow)then V.glow:RemoveFromParent()end
   local canvas=hud.WeightInfoText:GetParent():GetParent()
   if not valid(canvas)or not canvas:IsA(StaticFindObject('/Script/UMG.CanvasPanel'))then return end
   local function disc(size,alpha)
    local image=StaticConstructObject(StaticFindObject('/Script/UMG.Image'),hud.WidgetTree)
    image:SetBrush({DrawAs=4,TintColor={SpecifiedColor={R=1,G=.012,B=.006,A=alpha},ColorUseRule=0},OutlineSettings={Width=0,CornerRadii={X=size,Y=size,Z=size,W=size},RoundingType=0}})
    local slot=canvas:AddChildToCanvas(image);slot:SetAnchors({Minimum={X=.5,Y=.5},Maximum={X=.5,Y=.5}});slot:SetAlignment({X=.5,Y=.5});slot:SetPosition({X=0,Y=0});slot:SetSize({X=size,Y=size});slot:SetZOrder(25);return image
   end
   V.glow=disc(7,.18);V.dot=disc(2.5,1);V.dotHUD=hud
  end
  if valid(V.dot)then V.dot:SetVisibility(active and 3 or 1);V.glow:SetVisibility(active and 3 or 1)end
 end
 function V.equipped()
  if M.features==false then return end
  local p=H.GetPlayer();local pc=H.GetPlayerController()
  if not valid(pc)or not valid(p)or not p.IsLoaded or p.BP_PlayerStats.IsDead or p.BP_PlayerStats.IsDying or valid(pc.Vehicle)then return end
  local a=p.ItemEquiped;if not valid(a)then return end
  local now=os.clock();local c=V.equipCache
  if not c or not same(c.actor,a)or now>=c.untilAt or not valid(c.body)then
   M.refreshWeapon(a);local meshes=M.components(a);local d=M.weaponDefinition(a);local body=d and d.Id=='ak'and a.SkeletalMesh or nil
   if d and d.Id~='ak'then for _,part in ipairs(meshes)do if part.AttachSocketName:ToString()~=d.MagazineSocket then body=part;break end end end
   c={actor=a,def=d,body=body,untilAt=now+.75};V.equipCache=c
   if d and d.Id=='ak'and valid(body)then
    c.sight=akSight(body:GetSocketTransform(FName('SightAttachmentPoint'),2).Translation,1.06)
   end
  end
  if c.def then return a,p,pc,c.def end
 end
 function V.reset()
  reticle(false)
  for key in pairs(V.overlays or{})do opacity(nil,false,key)end
  if valid(V.pc)then V.pc:FOV(0)end
  -- Never overwrite a newer native unequip/death pose with an old gun pose.
  if valid(V.pawn)and valid(V.pawn.FpsArm)and V.originalArm and unchanged(V.pawn.FpsArm:GetRelativeTransform(),V.appliedArm)then V.pawn.FpsArm:K2_SetRelativeTransform(V.originalArm,false,{},true)end
  if V.middle then V.mapping(false)end
  V.gun=nil;V.pawn=nil;V.pc=nil;V.blend=0;V.pose=nil;V.time=nil;V.originalArm=nil;V.appliedArm=nil
 end
 function V.hudFrame()
  local a,p,pc=V.equipped()
  local ready=a and pc.IsInFPS and not pc.bShowMouseCursor and not pc.HUD.ChatUI.TypeInChat and not H.IsPauseMenu(pc)and not M.backpack.ui.opened and not M.devmenu.ui.opened
  local aim=ready and pc:IsInputKeyDown({KeyName=FName('RightMouseButton')})
  local hud=pc and pc.HUD
  opacity(hud and hud.CursorOverlay,aim,'cursor');opacity(hud and hud.StaticCursorAk,aim,'ak');opacity(hud and hud.StaticCursorItem,aim,'item')
  opacity(hud and hud.WeightInfoText,a~=nil,'weight')
  reticle(aim and M.rail and M.rail.optic.has(a),hud)
 end
 function V.frame(dt)
  if M.active==false or M.features==false then return end
  if M.hudFrame then M.hudFrame(dt)end
  V.slots.frame()
  if M.backpack.ui.frame then M.backpack.ui.frame()end
  local a,p,pc,d=V.equipped()
  if not a or not pc.IsInFPS or pc.bShowMouseCursor or pc.HUD.ChatUI.TypeInChat or H.IsPauseMenu(pc)or M.backpack.ui.opened or M.devmenu.ui.opened then
   if V.gun then V.reset()end;return
  end
  if not valid(p.FpsArm)or not same(a.RootComponent.AttachParent,p.FpsArm)then if V.gun then V.reset()end;return end
  mathlib=mathlib or StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
  if not same(V.gun,a)then
   V.reset();V.gun=a;V.pawn=p;V.pc=pc;V.baseFOV=pc.PlayerCameraManager:GetFOVAngle()
   local tr=p.FpsArm:GetRelativeTransform()
   V.originalArm=copy(tr)
  end
  dt=math.max(0,math.min(dt or .016,.1))
  local aim=pc:IsInputKeyDown({KeyName=FName('RightMouseButton')})
  V.hudFrame()
  V.blend=V.blend+((aim and 1 or 0)-V.blend)*(1-math.exp(-14*dt))
  local body=V.equipCache and V.equipCache.body
  if not valid(body)then return end
  local view=pc.PlayerCameraManager
  local cam=mathlib:MakeTransform(view:GetCameraLocation(),view:GetCameraRotation(),{X=1,Y=1,Z=1});local arm=p.FpsArm:K2_GetComponentToWorld()
  local relative=mathlib:MakeRelativeTransform(body:K2_GetComponentToWorld(),arm)
  local nativeSight=d.Id=='ak'and V.equipCache.sight
  local sight=nativeSight and nativeSight.height or d.Id=='m4'and 9.6 or d.Id=='hunting'and 7.1 or 6.0
  local optic=M.rail and M.rail.optic.has(a);if optic then sight=(M.rail.optic.mounts[d.Id].z+M.rail.optic.axisHeight)*1.06 end
  local wanted={Translation={X=24,Y=8*(1-V.blend)-(optic and (M.rail.optic.mounts[d.Id].y or 0)*1.06*V.blend or 0),Z=-11*(1-V.blend)-sight*V.blend},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1.06,Y=1.06,Z=1.06}}
  if nativeSight and not optic then wanted.Translation.Y=wanted.Translation.Y-nativeSight.lateral*V.blend end
  if d.Id=='ak'then wanted.Rotation={X=0,Y=0,Z=-.70710678118655,W=.70710678118655}end
  -- Work in camera space: body/arms remain joined and movement cannot accumulate.
  local target=mathlib:ComposeTransforms(mathlib:InvertTransform(relative),wanted)
  V.pose=V.pose and mathlib:TLerp(V.pose,target,1-math.exp(-22*dt),0)or target
  local world=mathlib:ComposeTransforms(V.pose,cam)
  p.FpsArm:K2_SetWorldTransform(world,false,{},true)
  V.appliedArm=copy(p.FpsArm:GetRelativeTransform())
  local aimed=optic and math.deg(2*math.atan(math.tan(math.rad(V.baseFOV)/2)/2))or V.baseFOV*.84
  pc:FOV(V.baseFOV+(aimed-V.baseFOV)*V.blend)
 end
 function V.mapping(active)
  local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_Universal.IMC_Universal');local action=StaticFindObject('/Game/Inputs/ActionsPlayer/RotateItem.RotateItem')
  if not valid(ctx)or not valid(action)or active==not not V.middle then return end
  if active then
   local found=false;ctx.Mappings:ForEach(function(_,v)local m=v:get();if m.Action:GetAddress()==action:GetAddress()and m.Key.KeyName:ToString()=='MiddleMouseButton'then found=true end end)
   if not found then return end
   ctx:UnmapKey(action,{KeyName=FName('MiddleMouseButton')});V.middle=true
  else ctx:MapKey(action,{KeyName=FName('MiddleMouseButton')});V.middle=false end
  StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'):RequestRebuildControlMappingsUsingContext(ctx,true)
 end
 -- DBH sends its camera angles separately from ALS's third-person aim rotation.
 -- Keep those native paths in agreement; never send first-person arm transforms.
 function V.remoteFrame(p)
  if M.features==false or same(p,H.GetPlayer())or not valid(p.ItemEquiped)or not p.ItemEquiped:IsA(M.akClass())then return end
  local r=p.ControlRotation
  if r.X==r.X and r.Y==r.Y then p.ReplicatedControlRotation={Pitch=r.X,Yaw=r.Y,Roll=0}end
 end
 function V.tick()
  if not V.aimHook and valid(H.GetPlayer())then
   local path='/Game/BP/PlayerController/PlayerControllerBase.PlayerControllerBase_C:ServerSendControlRotation'
   V.aimHook={RegisterHook(path,function(ctx,rotation)
    local r=rotation:get();local pitch,yaw=r.X,r.Y
    if pitch~=pitch or yaw~=yaw or math.abs(pitch)>180 or math.abs(yaw)>720 then return end
    local pc=ctx:get();enqueue(function()
     if M.features==false or not valid(pc)or not pc:HasAuthority()or pc:IsLocalPlayerController()then return end
     local p=pc.PlayerControlled
     if valid(p)and valid(p.ItemEquiped)and p.ItemEquiped:IsA(M.akClass())and not valid(pc.Vehicle)then
      pc:SetControlRotation({Pitch=pitch,Yaw=yaw,Roll=0})
     end
    end)
   end)}
  end
  if not V.hudHook and valid(H.GetPlayer())then
   V.hudHook={RegisterHook('/Game/UI/HUD.HUD_C:Tick',function(ctx)
    local pc=H.GetPlayerController();if valid(pc)and same(ctx:get(),pc.HUD)then V.hudFrame()end
   end)}
  end
  if not V.equipHooks and valid(H.GetPlayer())then
   V.equipHooks={}
   for _,name in ipairs({'OnRepItemEquiped','OnRep_ItemEquiped'})do
    local path='/Game/BP/Player/PlayerBase.PlayerBase_C:'..name
    if valid(StaticFindObject(path))then V.equipHooks[#V.equipHooks+1]={RegisterHook(path,function(ctx)
     if M.features==false then return end
     local p=ctx:get();local a=p.ItemEquiped
     if valid(a)and a:GetFullName():match('^AkWeapon_C ')then
      if valid(a.SkeletalMesh)then a.SkeletalMesh:SetVisibility(false,false)end
      M.refreshWeapon(a)
      if same(p,H.GetPlayer())then V.equipCache=nil;M.backpack.pickupPrompt();V.mapping(true)end
     end
    end)}end
   end
  end
  V.mapping(V.equipped()~=nil)
  if not V.hook and valid(H.GetPlayer())then
   -- Blueprint ReceiveTick callback runs after the native first-person animation.
   V.hook={RegisterHook('/Game/BP/Player/PlayerBase.PlayerBase_C:ReceiveTick',function(ctx,dt)
    if not same(ctx:get(),H.GetPlayer())then
     local ok,e=pcall(V.remoteFrame,ctx:get());if not ok and V.remoteError~=tostring(e)then V.remoteError=tostring(e);log('Remote rifle pose: '..V.remoteError)end
     return
    end
    local ok,e=pcall(V.frame,dt:get());if not ok and V.error~=tostring(e)then V.error=tostring(e);V.reset();log('Weapon view: '..V.error)end
   end)}
  end
  if not V.animHook and valid(H.GetPlayer())then
   V.animHook={RegisterHook('/MasterCharacter/Blueprints/Arms/ABP_FPSArmsMainAnimBlueprint.ABP_FPSArmsMainAnimBlueprint_C:BlueprintUpdateAnimation',function(ctx)
    if M.active==false or M.features==false then return end
    local a,p,pc=V.equipped()
    if a and pc.IsInFPS and valid(p.FpsArm)and same(ctx:get(),p.FpsArm:GetAnimInstance())then ctx:get().bSprinting=false end
   end)}
  end
 end
 return V
end

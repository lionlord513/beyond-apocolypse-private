-- Route dashboard controls through the game's input actions and their normal RPCs.
return function(M,H,valid,D)
 local I={actions={}}
 local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
 local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
 local slate=StaticFindObject('/Script/UMG.Default__SlateBlueprintLibrary')
 local function blocked(pc)
  return not valid(pc)or H.IsPauseMenu(pc)or(M.utility and M.utility.opened)or
   (M.backpack and M.backpack.ui.opened)or(M.overlayCapturesInput and M.overlayCapturesInput())or
   (valid(pc.HUD)and valid(pc.HUD.ChatUI)and pc.HUD.ChatUI.TypeInChat)
 end
 function I.pointer(enabled)
  local pc=H.GetPlayerController()
  if not enabled then
   I.pressed=nil;I.clickPending=nil;D.drag=nil
   local old=I.owner;I.owner=nil
   if valid(old)then
    old:SetIgnoreLookInput(false)
    if not blocked(old)then old.bShowMouseCursor=I.cursorBefore or false;lib:SetInputMode_GameOnly(old,false)end
   end
   return
  end
  if I.owner or blocked(pc)or not valid(D.widget)then return end
  I.owner=pc;I.cursorBefore=pc.bShowMouseCursor
  pc:SetIgnoreLookInput(true);pc.bShowMouseCursor=true
  lib:SetInputMode_GameAndUIEx(pc,D.widget,0,false,false)
 end
 local function allowed(pc)
  local a=valid(pc)and pc.Vehicle
  return not blocked(pc)and valid(a)and valid(a.Driver)and valid(pc.PlayerControlled)and a.Driver:GetAddress()==pc.PlayerControlled:GetAddress()
 end
 function I.action(name)
  if I.actions[name]and valid(I.actions[name])then return I.actions[name]end
  local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_Vehicule.IMC_Vehicule')
  if valid(ctx)then ctx.Mappings:ForEach(function(_,v)local a=v:get().Action
   if valid(a)and a:GetFName():ToString()==name then I.actions[name]=a end
  end)end
  return I.actions[name]
 end
 function I.press(name)
  local pc=H.GetPlayerController();if not allowed(pc)then return end
  local action=I.action(name);if not valid(action)then return end
  I.pressed={action=action,name=name,pc=pc,vehicle=pc.Vehicle,once=name~='Ignition'}
 end
 function I.attach()
  if I.clickBound then return end;I.clickBound=true
  local click=function()if I.owner then I.clickPending=true end end
  RegisterKeyBind(Key.LEFT_MOUSE_BUTTON,click)
  RegisterKeyBind(Key.LEFT_MOUSE_BUTTON,{ModifierKey.ALT},click)
 end
 function I.click(q)
  local x,y=(q.X-D.x)/D.scale,(q.Y-D.y)/D.scale
  for _,b in ipairs(D.buttons or{})do
   if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then I.press(b.action);return end
  end
 end
 function I.frame()
  local pc=H.GetPlayerController()
  if D.editing then
   I.pressed=nil;I.clickPending=nil
   if D.drag and valid(pc)then
    local q={};slate:AbsoluteToViewport(pc,layout:GetMousePositionOnPlatform(),{},q);D.move(q)
    if not pc:IsInputKeyDown({KeyName=FName('LeftMouseButton')})then D.release(q)end
   end
   return
  end
  local ready=valid(D.widget)and allowed(pc)
  local alt=ready and(pc:IsInputKeyDown({KeyName=FName('RightAlt')})or pc:IsInputKeyDown({KeyName=FName('LeftAlt')}))
  if alt and not I.owner then I.pointer(true)elseif not alt and I.owner then
   I.pointer(false)
  end
  if not ready then I.pressed=nil;I.clickPending=nil;D.drag=nil;return end
  if I.clickPending then
   I.clickPending=nil
   if I.owner then local q={};slate:AbsoluteToViewport(pc,layout:GetMousePositionOnPlatform(),{},q);I.click(q)end
  end
  local p=I.pressed
  if p then
   if not valid(p.pc)or pc:GetAddress()~=p.pc:GetAddress()or not valid(p.vehicle)or pc.Vehicle:GetAddress()~=p.vehicle:GetAddress()then I.pressed=nil;return end
   local sub=StaticFindObject('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetLocalPlayerSubSystemFromPlayerController(pc,StaticFindObject('/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem'))
   if valid(sub)then
    -- FInputActionValue has native-only fields that UE4SS cannot round-trip.
    sub:InjectInputVectorForAction(p.action,{X=1,Y=0,Z=0},{},{})
   end
   if p.once or not pc:IsInputKeyDown({KeyName=FName('LeftMouseButton')})then I.pressed=nil end
  end
 end
 return I
end

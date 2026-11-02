return function(M,root,H,valid,enqueue,log)
 local B={message='Drag items to arrange your inventory.',guid=M.guid};B.policy=dofile(root..'/Scripts/backpack/policy.lua')
 local N=dofile(root..'/Scripts/backpack/native.lua')(B,M,root,H,valid,enqueue,log)
 B.ui=dofile(root..'/Scripts/backpack/ui.lua')(B,root,H,valid)
 B.hotbar=dofile(root..'/Scripts/backpack/hotbar.lua')(N,H,valid)
 function B.ready()
  if M.features==false then return false end
  local pc=H.GetPlayerController();local p=H.GetPlayer()
  if not valid(p)or not p:GetFullName():match('^[MF][a-z]+Character_C ')and not p:GetFullName():match('^PlayerBase_C ')then return false end
  return valid(pc)and valid(p)and p.IsLoaded and p.IsInitialized and not p.BP_PlayerStats.IsDead and not p.BP_PlayerStats.IsDying
 end
 local function hint(s)
  B.message=s;local pc=H.GetPlayerController();if valid(pc)then StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):PrintString(pc,s,true,false,{R=.85,G=.7,B=.35,A=1},3,FName('BeyondBackpack'))end
 end
 B.notify=hint
 local function busy()
  if not B.ready()then return true end
  local pc=H.GetPlayerController();return pc.bShowMouseCursor or pc.HUD.ChatUI.TypeInChat or H.IsPauseMenu(pc)or M.devmenu.ui.opened or valid(pc.Vehicle)
 end
 function B.toggle()
  if B.ui.opened then B.ui.close();return end;if busy()then return end
  local b=N.target(H.GetPlayerController());if not b then hint('Wear a backpack or look at one within reach.');return end
  local ok,e=pcall(B.ui.open,b);if not ok then B.ui.close();error(e)end
 end
 function B.unequip()
  if B.ui.opened or busy()then return end
  local pc=H.GetPlayerController();local b=N.worn(H.GetPlayer())
  if not N.tier(b)then hint('No backpack equipped.');return end
  if N.held(pc)then hint('Empty your hands before removing your backpack.');return end
  local ok,e=pcall(N.request,b,'unequip',-1,-1);if not ok then hint(tostring(e):gsub('^.-:%d+: ',''))end
 end
 local function fistMappings(ctx,action)
  local simple,protected={},{}
  ctx.Mappings:ForEach(function(_,v)local m=v:get();if valid(m.Action)and m.Action:GetAddress()==action:GetAddress()then
   local key=m.Key.KeyName:ToString();if #m.Modifiers==0 and #m.Triggers==0 then simple[key]=(simple[key]or 0)+1 else protected[key]=true end
  end end)
  return simple,protected
 end
 function B.restoreMelee()
  if valid(B.fistContext)and valid(B.fistAction)then
   local simple,protected=fistMappings(B.fistContext,B.fistAction)
   for _,key in ipairs(B.fistAdded or{})do if not protected[key]then B.fistContext:UnmapKey(B.fistAction,{KeyName=FName(key)});simple[key]=nil end end
   for _,key in ipairs(B.fistOriginal or{})do if not simple[key]and not protected[key]then B.fistContext:MapKey(B.fistAction,{KeyName=FName(key)})end end
   StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'):RequestRebuildControlMappingsUsingContext(B.fistContext,true)
  end
  B.fistContext=nil;B.fistAction=nil;B.fistOriginal=nil;B.fistAdded=nil;B.mapping=nil;B.meleeSignature=nil;B.meleeCheckAt=nil
 end
 function B.remap()
  local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_Player.IMC_Player');if not valid(ctx)then return end
  local keys=M.controls and M.controls.values.melee or {'CapsLock','None'};local signature=keys[1]..'|'..keys[2]
  local unchanged=B.mapping==ctx:GetAddress()and B.meleeSignature==signature
  local now=os.clock();if unchanged and now<(B.meleeCheckAt or 0)then return end
  local action=StaticFindObject('/Game/Inputs/ActionsPlayer/FistMode.FistMode');if not valid(action)then return end
  if unchanged then
   -- Native settings can refill the same context after our first remap. Check
   -- at most once a second, rebuilding only when our simple mappings drift.
   B.meleeCheckAt=now+1
   local simple,protected=fistMappings(ctx,action);local desired={};local matches=true
   for _,key in ipairs(keys)do if key~='None'then desired[key]=true;if simple[key]~=1 then matches=false end end end
   for key in pairs(simple)do if not desired[key]and not protected[key]then matches=false end end
   if matches then return end
  end
  B.restoreMelee();local original={}
  -- Borrow only simple native bindings; modified/chorded mappings are preserved.
  local simple,protected=fistMappings(ctx,action)
  -- UnmapKey removes every mapping for that action/key, including chords.
  for key in pairs(simple)do if not protected[key]then original[#original+1]=key end end
  for _,key in ipairs(keys)do assert(not protected[key],'Melee key has a native chord: '..key)end
  B.fistContext=ctx;B.fistAction=action;B.fistOriginal=original;B.fistAdded={}
  for _,key in ipairs(B.fistOriginal)do ctx:UnmapKey(action,{KeyName=FName(key)})end
  for _,key in ipairs(keys)do if key~='None'then ctx:MapKey(action,{KeyName=FName(key)});B.fistAdded[#B.fistAdded+1]=key end end
  StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'):RequestRebuildControlMappingsUsingContext(ctx,true)
  B.mapping=ctx:GetAddress();B.meleeSignature=signature;B.meleeCheckAt=now+1;log('Backpack controls ready: Tab inventory, '..keys[1]..' melee, B unequip on foot')
 end
 function B.store(intended)
  if not intended or not B.secondarySuppressed or B.ui.opened or busy()or B.pending then return end
  local pc=H.GetPlayerController();local b=N.worn(pc.PlayerControlled)
  if not N.tier(b)or not N.access(pc,b)then return end
  local item=N.looked(pc);if not item or item:GetAddress()~=intended:GetAddress()then return end
  local slot=N.free(b);if slot==nil then hint('Backpack is full.');return end
  local ok,e=pcall(N.request,b,'store',-1,slot,item)
  hint(ok and B.message or tostring(e):gsub('^.-:%d+: ',''))
 end
 function B.pickupPrompt()
  local pc=H.GetPlayerController();local item,bag
  if not B.ui.opened and not busy()then bag=N.worn(pc.PlayerControlled);if N.tier(bag)and N.access(pc,bag)then item=N.looked(pc)end end
  B.storeTarget=item
  local active=valid(item)
  local gun=M.weaponHandling and M.weaponHandling.equipped()
  local suppress=not not(active or valid(gun))
  local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_Player.IMC_Player')
  local action=StaticFindObject('/Game/Inputs/ActionsPlayer/InteractSecondary.InteractSecondary')
  if valid(ctx)and valid(action)and(suppress or B.secondarySuppressed)and
   (not B.secondaryBinding or B.secondaryBinding.ctx~=ctx:GetAddress()or B.secondaryBinding.suppress~=suppress or os.clock()>=B.secondaryBinding.verifyAt)then
   local found=false;ctx.Mappings:ForEach(function(_,v)local m=v:get();if m.Action:GetAddress()==action:GetAddress()and m.Key.KeyName:ToString()=='RightMouseButton'then found=true end end)
   local changed=false
   if suppress then
    -- The shipped RMB mapping has no triggers/modifiers. Only borrow that key
    -- while TAKE is available with empty hands; native aim/drop remain intact.
    if found then ctx:UnmapKey(action,{KeyName=FName('RightMouseButton')});changed=true end
    B.secondarySuppressed=true
   elseif B.secondarySuppressed then if not found then ctx:MapKey(action,{KeyName=FName('RightMouseButton')});changed=true end;B.secondarySuppressed=false end
   if changed then StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'):RequestRebuildControlMappingsUsingContext(ctx,true)end
   -- Input changes are immediate; only reconciliation with external/native
   -- rebinding is periodic. Idle play never needs to enumerate every mapping.
   B.secondaryBinding={ctx=ctx:GetAddress(),suppress=suppress,verifyAt=os.clock()+1}
  end
  local hud=valid(pc)and pc.HUD
  if not valid(hud)then return end
  if not valid(B.promptRow)or B.promptHUD~=hud:GetAddress()then
   if valid(B.promptRow)then B.promptRow:RemoveFromParent()end
   B.promptRow=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),hud.WidgetTree)
   local font=hud.ArrowCompl.Font;font.Size=14;B.promptRow:SetFont(font)
   B.promptRow:SetColorAndOpacity({SpecifiedColor={R=.85,G=.8,B=.63,A=1},ColorUseRule=0})
   local parent=hud.ActionBox:GetParent();local tail={};local after=false
   for index=0,parent:GetChildrenCount()-1 do
    local child=parent:GetChildAt(index)
    if after then local s=child.Slot;local p=s.Padding;local z=s.Size
     tail[#tail+1]={child=child,padding={Left=p.Left,Top=p.Top,Right=p.Right,Bottom=p.Bottom},size={Value=z.Value,SizeRule=z.SizeRule},h=s.HorizontalAlignment,v=s.VerticalAlignment}
    end
    if child:GetAddress()==hud.ActionBox:GetAddress()then after=true end
   end
   for _,entry in ipairs(tail)do entry.child:RemoveFromParent()end
   local row=parent:AddChildToVerticalBox(B.promptRow)
   row:SetHorizontalAlignment(1);row:SetPadding({Left=0,Top=3,Right=0,Bottom=3})
   for _,entry in ipairs(tail)do local s=parent:AddChildToVerticalBox(entry.child);s:SetPadding(entry.padding);s:SetSize(entry.size);s:SetHorizontalAlignment(entry.h);s:SetVerticalAlignment(entry.v)end
   B.promptHUD=hud:GetAddress()
  end
  if active then B.promptRow:SetText(FText(N.free(bag)==nil and 'BACKPACK FULL  [RMB]'or'STORE IN BACKPACK  [RMB]'))end
  local lamp=valid(gun)and M.rail and M.rail.target(pc)
  if lamp then B.promptRow:SetText(FText(M.rail.optic.item(lamp)and 'ATTACH 2x SIGHT  [L]'or 'ATTACH FLASHLIGHT  [L]'))end
  B.promptRow:SetVisibility((active or lamp)and 3 or 1)
  B.promptVisible=active
 end
 function B.tick()
  N.tick();if B.ready()then N.install();B.remap();B.hotbar.tick()end;B.ui.tick()
  local ok,e=pcall(B.pickupPrompt)
  if not ok and B.promptError~=tostring(e)then B.promptError=tostring(e);log('Backpack prompt: '..B.promptError)end
 end
 function B.reset()
  B.restoreMelee()
  B.ui.close();B.hotbar.reset();B.storeTarget=nil
  if valid(B.promptRow)then B.promptRow:RemoveFromParent()end;B.promptRow=nil;B.promptHUD=nil
  if B.secondarySuppressed then
   local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_Player.IMC_Player');local a=StaticFindObject('/Game/Inputs/ActionsPlayer/InteractSecondary.InteractSecondary')
   if valid(ctx)and valid(a)then ctx:MapKey(a,{KeyName=FName('RightMouseButton')});StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'):RequestRebuildControlMappingsUsingContext(ctx,true)end
  end
  B.secondarySuppressed=false;B.secondaryBinding=nil;B.promptVisible=false;B.mapping=nil;N.scratch=nil;N.rate={};N.last={};N.pickups={};N.clearPending()
  if N.view then N.view.reset()end
 end
 return B
end

-- Borrow the native slot bindings only while a custom rifle is equipped.
return function(M,H,valid,enqueue)
 local S={bindings={},down={}}
 local function rebuild(ctx)StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'):RequestRebuildControlMappingsUsingContext(ctx,true)end
 function S.reset()
  if valid(S.ctx)then
   local present={};S.ctx.Mappings:ForEach(function(_,v)local m=v:get();present[m.Action:GetAddress()..':'..m.Key.KeyName:ToString()]=true end)
   for _,b in ipairs(S.bindings)do if valid(b.action)and not present[b.action:GetAddress()..':'..b.key]then S.ctx:MapKey(b.action,{KeyName=FName(b.key)})end end
   if #S.bindings>0 then rebuild(S.ctx)end
  end
  S.ctx=nil;S.bindings={};S.down={};S.nextAt=0
 end
 function S.frame()
  local gun,p,pc=M.weaponHandling.equipped()
  -- Reinstating a mapping while its holster key is still held can equip again.
  if not gun and #S.bindings>0 then
   local owner=H.GetPlayerController()
   if valid(owner)and not owner.bShowMouseCursor and not owner.HUD.ChatUI.TypeInChat then
    for _,b in ipairs(S.bindings)do if owner:IsInputKeyDown({KeyName=FName(b.key)})then return end end
   end
  end
  if not gun or pc.bShowMouseCursor or pc.HUD.ChatUI.TypeInChat or H.IsPauseMenu(pc)or M.backpack.ui.opened or M.overlayCapturesInput() then if #S.bindings>0 then S.reset()end;return end
  local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_Player.IMC_Player');if not valid(ctx)then return end
  if valid(S.ctx)and S.ctx:GetAddress()~=ctx:GetAddress()then S.reset()end;S.ctx=ctx
  if os.clock()>=(S.nextAt or 0)then
   S.nextAt=os.clock()+.25;local added={}
   ctx.Mappings:ForEach(function(_,v)local m=v:get();local n=tonumber(m.Action:GetFullName():match('/Slot(%d+)%.Slot%d+$'));local key=m.Key.KeyName:ToString()
    if n and n>=1 and n<=6 and key~='None'and #m.Modifiers==0 and #m.Triggers==0 then added[#added+1]={action=m.Action,key=key,slot=n-1}end
   end)
   for _,b in ipairs(added)do
    ctx:UnmapKey(b.action,{KeyName=FName(b.key)})
    local found=false;for _,old in ipairs(S.bindings)do if old.key==b.key and old.slot==b.slot then found=true;break end end
    if not found then S.bindings[#S.bindings+1]=b;S.down[b.key]=pc:IsInputKeyDown({KeyName=FName(b.key)})end
   end
   if #added>0 then rebuild(ctx)end
  end
  for _,b in ipairs(S.bindings)do
   local down=pc:IsInputKeyDown({KeyName=FName(b.key)});local previous=S.down[b.key];S.down[b.key]=down
   if down and not previous then local slot=b.slot;enqueue(function()M.rail.request('slot',slot)end)end
  end
 end
 return S
end

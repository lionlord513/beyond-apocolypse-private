-- Native UpdateInventory leaves the old empty row visible after Unequip. Only
-- adjust the local HUD presentation; never edit the native wearable map/slots.
return function(N,H,valid)
 local nextAt=0;local hidden
 local function restore()
  if hidden and valid(hidden.widget)then hidden.widget:SetVisibility(hidden.visibility);hidden.widget:UpdateInventory()end
  hidden=nil
 end
 return {reset=restore,tick=function()
  if os.clock()<nextAt then return end;nextAt=os.clock()+.25
  local pc=H.GetPlayerController();if not valid(pc)or not valid(pc.PlayerControlled)or not valid(pc.HUD)then return end
  local w=pc.HUD.WBP_Inventory;if not valid(w)then return end
  if hidden and (not valid(hidden.widget)or hidden.widget:GetAddress()~=w:GetAddress())then restore()end
  local b=N.worn(pc.PlayerControlled)
  if N.tier(b)then if hidden then restore()end
  else
   if not hidden then hidden={widget=w,visibility=w:GetVisibility()}end
   if w:GetVisibility()~=1 then w:SetVisibility(1)end
  end
 end}
end

-- Build 25172482: Bazooka is an ActivableEquipableMasterItem, with cooldown
-- but no ammunition resource. Consume the original after its native launch.
return function(M,root,H,valid,enqueue,log)
 local R={spent={}}
 local path='/Game/BP/Items/Movable/Bazooka/Bazooka.Bazooka_C'
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 function R.fired(a)
  if M.features==false then return end
  if not valid(a)or a:IsActorBeingDestroyed()or not a:HasAuthority()or not a.IsActive then return end
  local owner=a:GetOwner();if not valid(owner)then return end
  local key=a:GetAddress();if R.spent[key]then return end;R.spent[key]=a
  -- Finish the current native firing graph before releasing the launcher.
  enqueue(function()
   if not valid(a)then R.spent[key]=nil;return end
   a:CheckRemoveItemFromInventory()
   for _,pc in ipairs(FindAllOf('PlayerController')or{})do if valid(pc)and pc:HasAuthority()and valid(pc.PlayerControlled)then
    local p=pc.PlayerControlled
    if same(p.ItemEquiped,a)then p:RemoveEquipedItem()end
    if same(M.backpack.native.held(pc),a)then pc:RemoveItemInHand()end
   end end
   a:K2_DestroyActor();R.spent[key]=nil;log('Single-use RPG consumed after native launch')
  end)
 end
 function R.install()
  if R.hook then return end
  local c=LoadAsset(path);if not valid(c)then return end
  R.hook={RegisterHook(path..':OnRepIsActive',function(ctx)R.fired(ctx:get())end)}
 end
 return R
end

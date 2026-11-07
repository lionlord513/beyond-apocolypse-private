-- React to native inventory/identity events instead of waiting for the world poll.
return function(M,valid)
 local R={waiting={},queued={}}
 R.sockets={ba_nativeak='ak',ba_rifle_m4='m4',ba_rifle_hunting='hunting',ba_rifle_enfield='enfield'}
 function R.awaitIdentity(a)
  local key=a:GetFullName();local r=R.waiting[key]
  if not r or not valid(r.actor)or r.actor:GetAddress()~=a:GetAddress()then r={actor=a,untilAt=os.clock()+2};R.waiting[key]=r end
  -- A missing marker must never leave an otherwise usable native rifle invisible.
  return os.clock()<r.untilAt
 end
 function R.identified(a)R.waiting[a:GetFullName()]=nil end
 function R.reset()R.waiting={};R.queued={}end
 function R.prune()for key,r in pairs(R.waiting)do if not valid(r.actor)then R.waiting[key]=nil end end end
 function R.install(enqueue)
  R.enqueue=enqueue or R.enqueue
  if R.beginHook and R.replicationHook and R.inventoryHook then return end
  local enqueue=R.enqueue;if not enqueue then return end
  local function rifle(a)return valid(a)and a:GetFullName():match('^AkWeapon_C ')end
  local function changed(a,id)
   if M.features==false or not rifle(a)then return end
   if id and id~='ak'and valid(a.SkeletalMesh)then a.SkeletalMesh:SetVisibility(false,false)end
   local key=a:GetFullName();if R.queued[key]then return end;R.queued[key]=a
   enqueue(function()
    if R.queued[key]~=a then return end;R.queued[key]=nil
    if M.features==false or not valid(a)then return end
    M.refreshWeapon(a)
    local h=M.weaponHandling;local c=h and h.equipCache
    if c and valid(c.actor)and c.actor:GetAddress()==a:GetAddress()then h.equipCache=nil end
   end)
  end
  if not R.beginHook then
   RegisterBeginPlayPostHook(function(ctx)
    if M.features==false or M.travelling then return end
    local a=ctx:get();if not rifle(a)then return end
    -- Native BeginPlay has finished, but the first rendered frame has not.
    -- Identity can replicate later; never show the donor during that gap.
    if valid(a.SkeletalMesh)then R.awaitIdentity(a);a.SkeletalMesh:SetVisibility(false,false)end
    changed(a)
   end)
   R.beginHook=true
  end
  local path='/Script/Engine.SceneComponent:OnRep_AttachSocketName'
  if not R.replicationHook and valid(StaticFindObject(path))then R.replicationHook={RegisterHook(path,function()end,function(ctx)
   local c=ctx:get();if M.features==false or not valid(c)then return end
   local id=R.sockets[c.AttachSocketName:ToString():lower()];if id then changed(c:GetOwner(),id)end
  end)}end
  path='/Game/BP/Components/BP_InventoryComponent.BP_InventoryComponent_C:GetItemFromSlot'
  if not R.inventoryHook and valid(StaticFindObject(path))then R.inventoryHook={RegisterHook(path,function(_,slot,force,pos,remove,defer,item)
   if not defer:get()then changed(item:get())end
  end)}end
 end
 return R
end

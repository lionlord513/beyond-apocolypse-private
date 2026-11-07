local scripts=assert(arg[1]);local hooks,queue={},{}
local function valid(v)return type(v)=='table'and v.alive~=false end
StaticFindObject=function()return{}end
RegisterHook=function(path,pre,post)hooks[path]=post or pre;return 1,2 end
RegisterBeginPlayPostHook=function(fn)hooks.begin=fn end
local now=0;os.clock=function()return now end
local function actor(id)
 return {GetFullName=function()return 'AkWeapon_C Fixture.'..id end,GetAddress=function()return id end}
end
local a,b=actor(1),actor(2);local refreshed={}
a.SkeletalMesh={SetVisibility=function(self,visible)self.visible=visible end}
local M={features=true,weaponHandling={},refreshWeapon=function(v)refreshed[#refreshed+1]=v end}
local R=dofile(scripts..'/weapons/refresh.lua')(M,valid)
R.install(function(fn)queue[#queue+1]=fn end)
assert(R.awaitIdentity(a));now=1.9;assert(R.awaitIdentity(a));now=2;assert(not R.awaitIdentity(a),'Missing identity permanently hid native AK')
R.identified(a);assert(not next(R.waiting))
local function ctx(v)return {get=function()return v end}end
local function marker(owner,tag)return {AttachSocketName={ToString=function()return tag end},GetOwner=function()return owner end}end
local replication=hooks['/Script/Engine.SceneComponent:OnRep_AttachSocketName']
replication(ctx(marker(a,'BT_Laptop_1')));assert(#queue==0,'Unrelated marker scheduled rifle work')
M.weaponHandling.equipCache={actor=a};replication(ctx(marker(a,'BA_Rifle_m4')));replication(ctx(marker(a,'BA_Rifle_m4')))
assert(a.SkeletalMesh.visible==false,'Replicated custom identity left the donor visible until the next poll')
assert(#queue==1,'Duplicate identity events repeated geometry work');queue[1]();queue={}
assert(refreshed[1]==a and not M.weaponHandling.equipCache,'Late identity failed to refresh equipped model')
local restored=hooks['/Game/BP/Components/BP_InventoryComponent.BP_InventoryComponent_C:GetItemFromSlot']
restored(nil,nil,nil,nil,nil,ctx(true),ctx(a));assert(#queue==0,'Deferred actor was accessed before finish-spawn')
restored(nil,nil,nil,nil,nil,ctx(false),ctx(b));b.alive=false;queue[1]();queue={};assert(#refreshed==1,'Destroyed inventory item was refreshed')
replication(ctx(marker(a,'BA_NativeAK')));R.reset();queue[1]();assert(#refreshed==1,'Travel retained an old-world refresh')
M.features=false;replication(ctx(marker(a,'BA_Rifle_m4')));assert(not next(R.queued))
queue={};hooks.begin(ctx(a));assert(#queue==0,'Unmodded session intercepted a native rifle')
M.features=true;a.SkeletalMesh.visible=true;hooks.begin(ctx(a))
assert(a.SkeletalMesh.visible==false and #queue==1,'New rifle rendered its donor before receiving identity')
R.reset();queue[1]();assert(not next(R.queued),'Pending spawn survived a world change')
return 'Late identity, hotbar restoration, duplicate events, native AK fallback, destroyed actors and travel'

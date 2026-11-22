local scripts,scratch=arg[1],arg[2]
local function valid(o)return type(o)=='table'and o.alive~=false end
local function obj(id)return {GetAddress=function()return id end}end
StaticFindObject=function(path)if path:find('GameplayStatics')then return {GetGameInstance=function()return{}end}end;return{}end
FindAllOf=function()return{}end
local P=dofile(scripts..'/backpack/policy.lua')
local B={policy=P};local M={statePath=function(n)return scratch..'/state/'..n end}
local N=dofile(scripts..'/backpack/native.lua')(B,M,scripts:gsub('/Scripts$',''),{},valid,function(f)f()end,function()end)
local slots,inv,bag,pc,p,gun={},obj(1),obj(2),obj(3),obj(4),obj(5)
local data={[0]={_token=string.rep('a',8)..':'..string.rep('b',8)..':'..string.rep('c',8)..':'..string.rep('d',8)}}
local writes=0
slots.Contains=function(_,k)return data[k]~=nil end
slots.Find=function(_,k)return {get=function()return data[k]end}end
slots.Add=function()writes=writes+1;error('A live snapshot must never be copied')end
slots.Remove=slots.Add
inv.Slots=slots;inv.CurrentSlot=0;bag.BP_InventoryComponent=inv
bag.GetFullName=function()return 'BackpackBase_C fixture'end;bag.ID=7
pc.PlayerControlled=p;pc.HasAuthority=function()return true end
pc.GetItemInHand=function()end
p.GetBackpack=function(_,o)o.Backpack=bag end;p.ItemEquiped=gun
gun.LastInventoryComponent=inv;gun.LastSlot=0
N.access=function()return true end
assert(N.held(pc)==gun,'Equipped actor must be visible when GetItemInHand is empty')
local token=data[0]._token
for _,op in ipairs({'move','attach','detach','drop','take'})do
 local r={bag='n:7',op=op,from=0,to=(op=='move'or op=='attach')and 3 or -1,source=token,target='-'}
 local ok=pcall(N.execute,pc,r);assert(not ok and writes==0 and data[0]._token==token,op)
end
assert(N.liveSlot(pc,bag,0)and not N.liveSlot(pc,bag,3))
inv.CurrentSlot=-1;assert(N.liveSlot(pc,bag,0),'LastSlot must protect a stale CurrentSlot')
p.ItemEquiped=nil;pc.GetItemInHand=function(_,o)o.Item=gun end
assert(N.liveSlot(pc,bag,0),'A hotbar item in physical hands still owns its saved cell')
pc.GetItemInHand=function()end
assert(not N.liveSlot(pc,bag,0),'Unequipped items remain movable')
gun.ID=9;gun.GetFullName=function()return 'AkWeapon_C fixture'end;gun.IsA=function()return false end
p.ItemEquiped=gun;p.RemoveEquipedItem=function()end;pc.RemoveItemInHand=function()end
inv.RemoveItem=function()end;inv.CanAddItemToSlot=function(_,k,a,out)out.Return=true end
local ok,err=pcall(N.execute,pc,{bag='n:7',op='put',from=-1,to=3,source='n:9',target='-'})
assert(not ok and tostring(err):find('still equipped',1,true)and writes==0,'A refused native unequip cannot create a stored copy')
return 'Equipped-only weapons, physical hands, stale CurrentSlot, moves, swaps, take/drop and attachment guards'

-- Two independent shop instances exchange the production wire messages.
local root, scratch = arg[1], arg[2]
local factory = dofile(root .. '/owner_shop.lua')
local hooks, clock, serial = {}, 5, 0
os.clock = function() return clock end
local place = {GetAddress = function() return 41 end}
local valid = function(x) return type(x) == 'table' end
local function guid(a) return {A = a, B = 2, C = 3, D = 4} end
function StaticFindObject(name)
 if name:find('KismetGuidLibrary') then
  return {NewGuid = function() serial = serial + 1; return guid(serial) end}
 end
end
function FName(s) return s end
function RegisterHook(name, callback) hooks[name:match(':(%w+)$')] = callback end
local function argOf(x) return {get = function() return x end} end
local function message(x) return argOf({ToString = function() return x end}) end
local function player(address, authority, isLocal)
 return {GetWorld = function() return place end, GetAddress = function() return address end,
  HasAuthority = function() return authority end, IsLocalPlayerController = function() return isLocal end,
  PlayerControlled = {IsLoaded = true}, NetConnection = {}, wallet = 100}
end
local host, remote, guest = player(1,true,true), player(2,true,false), player(3,false,true)
local saves, delivered, refunds, deny, async = 0, 0, 0, false, false
local finish, requests, replies = nil, {}, {}
guest.GetCurrentMoney = function(self,out) out.NewParam = self.wallet end
guest.TryPurchase = function(self,price,save,out)
 assert(save); out.Success = self.wallet >= price
 if out.Success then self.wallet = self.wallet - price end
end
guest.AddMoney = function(self,price) refunds = refunds + 1; self.wallet = self.wallet + price end
guest.BP_GarageComp = {SAVE = function() saves = saves + 1 end}
guest.ServerExecRPC = function(_,v) requests[#requests+1] = v end
remote.ClientMessage = function(_,v) replies[#replies+1] = v end
local game = {GetGameInstance = function() return {MainSaveGame = {SaveGameMetadata={SaveName={Guid=guid(100)}}}} end}
local function build(side,pc)
 hooks = {}
 local shop = factory({protocol='QAOrder',valid=valid,game=game,pc=function()return pc end,
  note=function()end,path=function(file)return scratch .. '/state/' .. side .. file end,
  price=function(item)if item=='part'then return 25 end end,
  deliver=function(recipient,item,complete)
   assert(recipient==remote and item=='part')
   if deny then error('Obstructed') end
   delivered=delivered+1
   if async then finish=complete else complete(true,'Delivered') end
  end})
 return shop,hooks
end
local h,hooksH=build('host',host)
local c,hooksC=build('client',guest)
local function request()local q=requests;requests={};for _,v in ipairs(q)do hooksH.ServerExecRPC(argOf(remote),message(v))end;h.tick(host)end
local function reply()local q=replies;replies={};for _,v in ipairs(q)do hooksC.ClientMessage(argOf(guest),message(v))end;c.tick(guest)end
local function advance()clock=clock+4;c.tick(guest);request();reply()end
advance(); assert(c.world)
c.order('part'); request();reply()
assert(c.pending.state=='paid' and guest.wallet==75)
local paid=requests[1]
request(); assert(delivered==1);replies={} -- drop the first receipt
c,hooksC=build('client',guest);advance();advance()
assert(c.pending.state=='done' and delivered==1 and host.wallet==100 and guest.wallet==75)
requests={paid,paid};request();reply();assert(delivered==1 and guest.wallet==75)
clock=clock+2;deny=true;c.order('part');request();reply();request();reply()
assert(c.pending.state=='refunded' and guest.wallet==75 and refunds==1 and saves==1)
clock=clock+2;deny=false;async=true;c.order('part');request();reply();request();reply()
assert(finish and c.pending.state=='paid');h.reset();advance()
assert(c.pending.state=='refunded' and guest.wallet==75)
finish(true,'Late callback');advance();assert(guest.wallet==75 and refunds==2)
clock=clock+2;guest.wallet=7;c.order('part');request();reply();assert(c.pending.state=='cancelled' and guest.wallet==7)
print('Owner wallet, duplicate messages, lost receipt, delivery failure, travel and insufficient funds pass')

-- Custom shop orders. The owning controller charges its local garage. Only the
-- host places actors. Both sides persist receipts before acknowledging a step.
return function(api)
 local shop={queue={},nextHello=0,limits={},outstanding={}}
 local prefix=api.protocol..'|'
 local guid=StaticFindObject('/Script/Engine.Default__KismetGuidLibrary')
 local steam=StaticFindObject('/Script/SteamCorePro.Default__SteamUtilities')
 local function id(g)return ('%08x%08x%08x%08x'):format(g.A&0xffffffff,g.B&0xffffffff,g.C&0xffffffff,g.D&0xffffffff)end
 local function hex(s)return type(s)=='string'and #s==32 and s:match('^[a-f0-9]+$')and s~=string.rep('0',32)end
 local function path(name)return api.path(api.protocol..'-'..name..'.txt')end
 local function read(name)
  for _,suffix in ipairs({'','.bak'})do
   local f,err,code=io.open(path(name)..suffix,'r')
   if f then local r={};for line in f:lines()do local k,v=line:match('^(%a+)=(.*)$');assert(k,'Invalid shop receipt');r[k]=v end;f:close();return r end
   assert(code==2,err)
  end
 end
 local function write(name,r)
  local p=path(name);local f=assert(io.open(p..'.tmp','w'))
  for k,v in pairs(r)do assert(f:write(k..'='..tostring(v):gsub('[\r\n]',' ')..'\n'))end;assert(f:close())
  local old=io.open(p,'r');if old then old:close();os.remove(p..'.bak');assert(os.rename(p,p..'.bak'))end
  local ok,err=os.rename(p..'.tmp',p);if not ok then if old then os.rename(p..'.bak',p)end;error(err)end
 end
 local function identity()
  if not shop.identity then local r=read('buyer');shop.identity=r and r.id
   if not hex(shop.identity)then shop.identity=id(guid:NewGuid());write('buyer',{id=shop.identity})end
  end;return shop.identity
 end
 shop.buyerIdentity=identity
 local function owner(pc,token)
  if api.valid(steam)and api.valid(pc.PlayerState)then
   local value=steam:BreakSteamID(steam:GetSteamIdFromPlayerState(pc.PlayerState))
   local s=type(value)=='string'and value or value:ToString()
   if s:match('^%d+$')and #s>=15 and not s:match('^0+$')then return s end
  end
  return token
 end
 local function world(pc)
  local save=api.game:GetGameInstance(pc).MainSaveGame;if not api.valid(save)then return end
  local w=id(save.SaveGameMetadata.SaveName.Guid);if hex(w)then return w end
 end
 local function reply(pc,text)pc:ClientMessage(prefix..text,FName(api.protocol),0)end
 local function terminal(r)return r.state=='done'or r.state=='refunded'or r.state=='cancelled'end
 local function transmit()
  local r=shop.pending;api.pc():ServerExecRPC(prefix..table.concat({r.state=='paid'and 'paid'or 'quote',r.world,r.id,identity(),r.item},'|'))
  shop.nextSend=os.clock()+3
 end
 local function store(r)write('buyer-'..r.world,r)end
 local function balance(pc)local out={};pc:GetCurrentMoney(out);return assert(tonumber(out.NewParam),'Wallet unavailable')end
 local function settle(pc,r)
  local price=assert(tonumber(r.price));local before=assert(tonumber(r.before));local current=balance(pc)
  if r.state=='charging'then
   if current==before then local out={};pc:TryPurchase(price,true,out)
    if not out.Success then r.state='cancelled';store(r);api.note('Not enough money');return end
   elseif current~=before-price then api.note('Wallet changed during payment. Order receipt retained.');return end
   r.state='paid';store(r);transmit()
  elseif r.state=='refunding'then
   if current==before then pc:AddMoney(price);pc.BP_GarageComp:SAVE()
   elseif current~=before+price then api.note('Wallet changed during refund. Order receipt retained.');return end
   r.state='refunded';store(r);api.note('Delivery failed. Your $'..price..' was refunded.')
  end
 end
 function shop.order(item)
  assert(shop.world,'Waiting for the updated host shop')
  assert(not shop.pending or terminal(shop.pending),'Your previous order is still pending')
  assert(api.price(item),'Unknown item')
  local r={id=id(guid:NewGuid()),world=shop.world,item=item,state='quote'}
  shop.pending=r;store(r);transmit();api.note('Ordering…')
 end
 local function server(pc,text)
  local w=world(pc);if not w then return end
  if text=='hello'then reply(pc,'world|'..w);return end
  local op,requested,order,token,item=text:match('^(%a+)|(%x+)|(%x+)|(%x+)|(%w+)$')
  if not hex(requested)or not hex(order)or not hex(token)or (op~='paid'and op~='quote')then return end
  local price=api.price(item);if not price then return end
  local key='order-'..requested..'-'..order;local who=owner(pc,token);local r=read(key)
  if requested~=w then
   -- Settle an existing receipt in its original save. Never deliver its item
   -- into a different world. A stale first quote has taken no money.
   if r and r.who==who and r.token==token and r.item==item then
    if r.state=='quote'then r.state='refund';r.message='Save changed before delivery';write(key,r)end
    if r.state=='done'or r.state=='refund'then reply(pc,table.concat({r.state,requested,order,r.price,r.message or ''},'|'))end
   end
   reply(pc,'world|'..w);return
  end
  if not r then
   if op~='quote'or os.clock()<(shop.limits[who]or 0)then return end
   shop.limits[who]=os.clock()+1
   r={state='quote',who=who,token=token,item=item,price=price};write(key,r)
  end
  if r.who~=who or r.token~=token or item~=r.item then return end
  if op=='paid'and r.state=='quote'then
   r.state='delivering';write(key,r)
   local function complete(success,message)
    if r.state~='delivering'then return end
    shop.outstanding[key]=nil
    r.state=success and 'done'or 'refund';r.message=tostring(message or ''):gsub('[\r\n|]',' '):sub(1,120)
    write(key,r)
   end
   shop.outstanding[key]=complete
   local ok,reason=pcall(api.deliver,pc,item,complete)
   if not ok then complete(false,tostring(reason):gsub('^.-:%d+: ',''))end
  end
  local state=(r.state=='delivering'and not shop.outstanding[key])and 'review' or r.state
  reply(pc,table.concat({state,w,order,r.price,r.message or ''},'|'))
 end
 local function client(pc,text)
  local w=text:match('^world|(%x+)$')
  if hex(w)then if shop.world~=w then shop.world=w;shop.pending=read('buyer-'..w);shop.nextSend=0 end;return end
  local op,worldId,order,price,message=text:match('^(%a+)|(%x+)|(%x+)|(%d+)|(.*)$')
  local r=shop.pending;if not r or r.id~=order or r.world~=worldId or terminal(r)then return end
  if op=='quote'and r.state=='quote'then
   assert(tonumber(price)==api.price(r.item),'Shop price mismatch');r.price=price;r.before=balance(pc);r.state='charging';store(r);settle(pc,r)
  elseif op=='done'and r.state=='paid'then r.state='done';store(r);api.note(message)
  elseif op=='refund'and r.state=='paid'then r.before=balance(pc);r.state='refunding';store(r);settle(pc,r)
  elseif op=='refund'and r.state=='quote'then r.state='cancelled';store(r);api.note('Save changed. Place the order again.')
  elseif op=='review'then api.note('Delivery was interrupted on the host. Order receipt '..r.id..' retained.')
  elseif op=='delivering'then api.note('Waiting for the host to finish delivery')end
 end
 local function capture(ctx,msg,direction)
  local value=msg:get():ToString()
  if value:sub(1,#prefix)~=prefix or #value>360 or #shop.queue>=64 then return end
  shop.queue[#shop.queue+1]={pc=ctx:get(),text=value:sub(#prefix+1),direction=direction}
 end
 RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,msg)capture(ctx,msg,'request')end)
 RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(ctx,msg)capture(ctx,msg,'reply')end)
 function shop.tick(pc)
  if not api.valid(pc)or not api.valid(pc.PlayerControlled)or not pc.PlayerControlled.IsLoaded then shop.queue={};return end
  local q=shop.queue;shop.queue={}
  for _,m in ipairs(q)do if api.valid(m.pc)and m.pc:GetWorld():GetAddress()==pc:GetWorld():GetAddress()then
   if pc:HasAuthority()and m.direction=='request'and not m.pc:IsLocalPlayerController()and api.valid(m.pc.NetConnection)and api.valid(m.pc.PlayerControlled)and m.pc.PlayerControlled.IsLoaded then server(m.pc,m.text)
   elseif not pc:HasAuthority()and m.direction=='reply'and pc:GetAddress()==m.pc:GetAddress()then client(pc,m.text)end
  end end
  if pc:HasAuthority()then return end
  local now=os.clock()
  if not shop.world and now>=shop.nextHello then shop.nextHello=now+8;pc:ServerExecRPC(prefix..'hello')end
  local r=shop.pending
  if r and not terminal(r)and now>=(shop.nextSend or 0)then
   shop.nextSend=now+3
   if r.state=='charging'or r.state=='refunding'then settle(pc,r)else transmit()end
  end
 end
 function shop.reset()
  for _,finish in pairs(shop.outstanding)do finish(false,'World closed before delivery')end
  shop.queue={};shop.world=nil;shop.pending=nil;shop.nextHello=0;shop.nextSend=0;shop.limits={}end
 return shop
end

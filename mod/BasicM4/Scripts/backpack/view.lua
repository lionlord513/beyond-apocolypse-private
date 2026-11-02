-- Display metadata only. The host keeps the original native save records and
-- remains the only writer; no item is reconstructed from these messages.
return function(B,M,N,root,H,valid,log)
 local V={queue={},pending={},cache={},seq=0,nextAt=0,rate={}};local kind='BABackpackView'
 local P=B.policy
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function clean(s)return tostring(s):gsub('[|~;\r\n]',' '):sub(1,48)end
 function V.decode(s)
  if type(s)~='string'or #s>2200 then return end
  local seq,id,capacity,body=s:match('^BAIV3|(%d+)|(n:%d+)|(%d+)|(.*)$')
  seq,capacity=tonumber(seq),tonumber(capacity)
  if not seq or not P.actor(id)or not(capacity==6 or capacity==12 or capacity==18)then return end
  local data={};local count=0
  for row in body:gmatch('[^;]+')do
   local k,token,label,attachments=row:match('^(%d+)~([^~]+)~([^~]+)~([^~]*)$');if not k then k,token,label=row:match('^(%d+)~([^~]+)~([^~]+)$')end;k=tonumber(k)
   if not P.slot(k,capacity)or not P.token(token)or token=='-'or #label>48 or #(attachments or '')>48 or data[k]then return end
   data[k]={_token=token,label=label,attachments=attachments or ''};count=count+1;if count>capacity then return end
  end
  return {seq=seq,id=id,capacity=capacity,data=data}
 end
 function V.encode(seq,b)
  local rows={};for k,d in pairs(N.nativeData(b))do rows[#rows+1]=k..'~'..N.token(d)..'~'..clean(N.title(d,b,k))..'~'..clean(N.attachments(d,b,k))end;table.sort(rows)
  return 'BAIV3|'..seq..'|'..N.actor(b)..'|'..N.tier(b).cells..'|'..table.concat(rows,';')
 end
 function V.data(b,native)
  local v=V.cache[b:GetAddress()]
  if not v or v.id~=N.actor(b)then return native end
  local result={};for k,d in pairs(v.data)do
   local saved=native[k]
   result[k]={_token=d._token,label=d.label,attachments=d.attachments,native=saved and N.token(saved)==d._token and saved or nil}
  end
  return result
 end
 function V.fresh(b)local v=V.cache[b:GetAddress()];return v and v.id==N.actor(b)and os.clock()-v.at<=5 end
 function V.request(pc,b)
  local id=N.actor(b);if not id then return end
  V.seq=V.seq+1;V.pending[V.seq]={bag=b,id=id,at=os.clock()}
  pc:ServerExecRPC('BAIV3Q|'..V.seq..'|'..id)
 end
 function V.tick()
  local q=V.queue;V.queue={}
  for _,v in ipairs(q)do
   local pc=v.pc
   if valid(pc)then
    if v.request and pc:HasAuthority()then
     local now=os.clock();local key=pc:GetAddress()
     if now>=(V.rate[key]or 0)then
      V.rate[key]=now+.15
      local b=N.find(pc,v.id)
      if b and N.access(pc,b)then pc:ClientMessage(V.encode(v.seq,b),FName(kind),0)end
     end
    elseif not pc:HasAuthority()and pc:IsLocalPlayerController()then
     local r=V.decode(v.text);local pending=r and V.pending[r.seq]
     if pending and pending.id==r.id and valid(pending.bag)and N.actor(pending.bag)==r.id and N.tier(pending.bag).cells==r.capacity then
      local key=pending.bag:GetAddress();local old=V.cache[key]
      if not old or r.seq>old.seq then r.at=os.clock();V.cache[key]=r end
      V.pending[r.seq]=nil
     end
    end
   end
  end
  local now=os.clock();for seq,v in pairs(V.pending)do if now-v.at>6 then V.pending[seq]=nil end end
  for key,v in pairs(V.cache)do if now-v.at>30 then V.cache[key]=nil end end
  if now<V.nextAt then return end;V.nextAt=now+.5
  local pc=H.GetPlayerController();if not valid(pc)or pc:HasAuthority()or not valid(pc.PlayerControlled)or not pc.PlayerControlled.IsLoaded then return end
  local b=B.ui.opened and B.ui.bag or N.target(pc)
  if b and N.access(pc,b)then V.request(pc,b)end
 end
 function V.install()
  if V.hooks then return end
  V.hooks={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,msg)
   local ok,s=pcall(function()return msg:get():ToString()end);if not ok or #s>64 then return end
   local seq,id=s:match('^BAIV3Q|(%d+)|(n:%d+)$');seq=tonumber(seq)
   if seq and seq<=2147483647 and P.actor(id)and #V.queue<64 then V.queue[#V.queue+1]={pc=ctx:get(),request=true,seq=seq,id=id}end
  end),RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(ctx,msg,ty)
   local ok,s=pcall(function()if ty:get():ToString()==kind then return msg:get():ToString()end end)
   if ok and s and #s<=2200 and #V.queue<64 then V.queue[#V.queue+1]={pc=ctx:get(),text=s}end
  end)}
 end
 function V.reset()V.queue={};V.pending={};V.cache={};V.rate={};V.nextAt=0 end
 return V
end

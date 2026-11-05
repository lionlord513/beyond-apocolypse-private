-- Gameplay is opt-in by the host. Graphics repair remains local in any lobby.
return function(M,H,valid,enqueue)
 local S={nextAt=0,attempts=0,peers={},identities={}};M.features=false
 local hello='BAMOD1|hello';local reply='BAMOD1|ready'
 local ask='BAMOD1|identity?';local identityPrefix='BAMOD1|identity|'
 -- Steam identities remain primary. Only a host lacking a native identity
 -- requests the guest's persistent installation ID for its ammo reserve.
 function S.offlineOwner(pc)
  local key=pc:GetAddress();local r=S.identities[key]
  if not S.peers[key]then return end
  if not r or not valid(r.pc)then r={pc=pc,nextAt=0};S.identities[key]=r end
  if r.id then return 'offline-'..r.id end
  if os.clock()>=r.nextAt then r.nextAt=os.clock()+5;pc:ClientMessage(ask,FName('BAModSession'),0)end
 end
 function S.allowed()return M.features~=false end
 function S.reset()M.features=false;S.nextAt=0;S.attempts=0;S.peers={};S.identities={};S.controller=nil end
 function S.tick()
  local pc=H.GetPlayerController();if not valid(pc)or not valid(pc.PlayerControlled)or not pc.PlayerControlled.IsLoaded then M.features=false;return end
  local key=pc:GetFullName()
  if key~=S.controller then S.reset();S.controller=key end
  if not S.hooks then
   S.hooks={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,msg)
    local ok,s=pcall(function()return msg:get():ToString()end)
    if not ok then return end
    if s:sub(1,#identityPrefix)==identityPrefix then
     local token=s:sub(#identityPrefix+1)
     if #token~=32 or not token:match('^[a-f0-9]+$')or token==string.rep('0',32)then return end
     local caller=ctx:get();enqueue(function()
      if not valid(caller)or not caller:HasAuthority()then return end
      local r=S.identities[caller:GetAddress()]
      if r and valid(r.pc)and not r.id then r.id=token end
     end);return
    end
    if s~=hello then return end
    local caller=ctx:get();enqueue(function()
     if not valid(caller)or not caller:HasAuthority()then return end
     local key=caller:GetAddress();local now=os.clock()
     if S.peers[key]and now-S.peers[key]<2 then return end
     S.peers[key]=now;caller:ClientMessage(reply,FName('BAModSession'),0)
    end)
   end),RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(ctx,msg,kind)
    local ok,s=pcall(function()return msg:get():ToString()end)
    local caller=ctx:get()
    if ok and (s==reply or s==ask)and kind:get():ToString()=='BAModSession'then enqueue(function()
     local localPC=H.GetPlayerController()
     if valid(localPC)and valid(caller)and localPC:GetAddress()==caller:GetAddress()then
      if s==reply then M.features=true
      elseif not localPC:HasAuthority()then localPC:ServerExecRPC(identityPrefix..M.hangar.orders.buyerIdentity())end
     end
    end)end
   end)}
  end
  if pc:HasAuthority()then M.features=true;return end
  if M.features or os.clock()<S.nextAt then return end
  S.attempts=S.attempts+1;S.nextAt=os.clock()+(S.attempts<=6 and 5 or 30);pc:ServerExecRPC(hello)
 end
 return S
end

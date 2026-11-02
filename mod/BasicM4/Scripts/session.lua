-- Gameplay is opt-in by the host. Graphics repair remains local in any lobby.
return function(M,H,valid,enqueue)
 local S={nextAt=0,attempts=0,peers={}};M.features=false
 local hello='BAMOD1|hello';local reply='BAMOD1|ready'
 function S.allowed()return M.features~=false end
 function S.reset()M.features=false;S.nextAt=0;S.attempts=0;S.peers={}end
 function S.tick()
  local pc=H.GetPlayerController();if not valid(pc)then return end
  if not S.hooks then
   S.hooks={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,msg)
    local ok,s=pcall(function()return msg:get():ToString()end)
    if not ok or s~=hello then return end
    local caller=ctx:get();enqueue(function()
     if not valid(caller)or not caller:HasAuthority()then return end
     local key=caller:GetAddress();local now=os.clock()
     if S.peers[key]and now-S.peers[key]<2 then return end
     S.peers[key]=now;caller:ClientMessage(reply,FName('BAModSession'),0)
    end)
   end),RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(ctx,msg,kind)
    local ok,s=pcall(function()return msg:get():ToString()end)
    local caller=ctx:get()
    if ok and s==reply and kind:get():ToString()=='BAModSession'then enqueue(function()
     local localPC=H.GetPlayerController()
     if valid(localPC)and valid(caller)and localPC:GetAddress()==caller:GetAddress()then M.features=true end
    end)end
   end)}
  end
  if pc:HasAuthority()then M.features=true;return end
  if M.features or S.attempts>=6 or os.clock()<S.nextAt then return end
  S.attempts=S.attempts+1;S.nextAt=os.clock()+5;pc:ServerExecRPC(hello)
 end
 return S
end

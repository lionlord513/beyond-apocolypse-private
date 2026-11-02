return function(N,M,H,valid,enqueue,log)
 local S={nextInput=0,queue=0,peers={},nextPeers=0};local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local ids=M.gyrocopter.transport.sync
 function S.input(now)
  local pc=H.GetPlayerController();if not valid(pc)or pc:HasAuthority()then return end
  local a=pc.Vehicle;local r=valid(a)and N.cars[a:GetFullName()]
  local held=r and same(a.Driver,pc.PlayerControlled)and N.held(pc)or false
  if now>=S.nextInput or held~=S.wasHeld then
   if r or S.wasHeld then pc:ServerExecRPC('BANI1|'..(held and '1'or '0'))end
   S.wasHeld=held;S.nextInput=now+.2
  end
 end
 S.requestHook={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,msg)
  local ok,s=pcall(function()return msg:get():ToString()end);if not ok or not(s=='BANI1|0'or s=='BANI1|1')or S.queue>=32 then return end
  local pc=ctx:get();S.queue=S.queue+1;enqueue(function()
   S.queue=math.max(0,S.queue-1);if M.features==false or not valid(pc)or not pc:HasAuthority()then return end
   local a=pc.Vehicle;if not valid(a)or not N.cars[a:GetFullName()]or not same(a.Driver,pc.PlayerControlled)then return end
   N.requests[pc:GetAddress()]={pc=pc,car=a,held=s=='BANI1|1',at=game:GetTimeSeconds(pc)}
  end)
 end)}
 function S.publish(r,now)
  if now<(r.netAt or 0)and r.sentActive==r.active then return end;r.netAt=now+.2;r.sentActive=r.active
  if now>=S.nextPeers then S.peers=FindAllOf('PlayerControllerBase_C')or{};S.nextPeers=now+2 end
  local id=ids.number(r.actor);local message=('BANS1|%d|%.3f|%.3f|%.0f|%d'):format(id,r.acceleration or 0,r.litres or 0,r.capacity or 0,r.tier or 0)
  for _,pc in ipairs(S.peers)do if valid(pc)and pc:HasAuthority()and not pc:IsLocalPlayerController()and valid(pc.PlayerControlled)then
   local a,b=pc.PlayerControlled:K2_GetActorLocation(),r.actor:K2_GetActorLocation()
   if (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2<25000^2 then pc:ClientMessage(message,FName('BANitrous'),0)end
  end end
 end
 S.replyHook={RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(ctx,msg,kind)
  if kind:get():ToString()~='BANitrous'then return end
  local s=msg:get():ToString();if #s>100 or S.queue>=32 then return end
  local id,acc,qty,cap,tier=s:match('^BANS1|(%d+)|([%d%.]+)|([%d%.]+)|(%d+)|([012])$')
  id,acc,qty,cap,tier=tonumber(id),tonumber(acc),tonumber(qty),tonumber(cap),tonumber(tier)
  if not id or id>2147483647 or not acc or acc>5.4 or not qty or not cap or qty>cap or cap>10000 then return end
  local pc=ctx:get();S.queue=S.queue+1;enqueue(function()
   S.queue=math.max(0,S.queue-1);if not valid(pc)or pc:HasAuthority()or not same(pc,H.GetPlayerController())then return end
   for _,r in pairs(N.cars)do if valid(r.actor)and ids.matches(r.actor,id)then r.net={at=game:GetTimeSeconds(pc),acceleration=acc};r.litres=qty;r.capacity=cap;r.tier=tier;break end end
  end)
 end)}
 -- Native boost input may run between service ticks. Restore only equipped cars;
 -- aircraft keep the existing collective/flight implementation.
 local base='/Game/AVS_Template/Template/AVS_Template_Vehicle.AVS_Template_Vehicle_C:'
 S.hooks={}
 function S.install()
  if S.installed then return end;local complete=true
  for i=1,5 do local path=base..'InpActEvt_Boost_K2Node_EnhancedInputActionEvent_'..i
   if not S.hooks[path]and valid(StaticFindObject(path))then S.hooks[path]={RegisterHook(path,function(ctx)
    local a=ctx:get();local r=valid(a)and N.cars[a:GetFullName()]
    if r and not M.gyrocopter.tracked[a:GetFullName()]then N.apply(r,r.acceleration or 0);if not r.active then a.BoostInput=0 end end
   end)}elseif not S.hooks[path]then complete=false end
  end
  S.installed=complete
 end
 function S.reset()S.nextInput=0;S.wasHeld=false;S.peers={};S.nextPeers=0 end
 S.install();return S
end

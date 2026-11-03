return function(M,root,H,valid,enqueue,log)
 local C={selected=0,nonce=0,players={},owners={},humans={},states={},nextAt=0,hooks={},revision=0}
 local P=dofile(root..'/Scripts/player_models/policy.lua');C.policy=P;C.catalog=P.catalog
 local R=dofile(root..'/Scripts/player_models/visuals.lua')(M,root,H,valid,log);C.visuals=R
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics');local scene=StaticFindObject('/Script/Engine.SceneComponent')
 local pawnClass
 local function isPlayer(p)
  pawnClass=pawnClass or StaticFindObject('/Game/BP/Player/PlayerBase.PlayerBase_C')
  return valid(p)and valid(pawnClass)and p:IsA(pawnClass)and p.IsLoaded==true
 end
 local file=M.statePath and M.statePath('player-model.txt')or root..'/state/player-model.txt'
 do local f=io.open(file,'r');if f then local n=tonumber(f:read('*a'):match('^model=([01])%s*$'));if P.allowed(n)then C.selected=n end;f:close()end end
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function status(s)C.status=s;C.revision=C.revision+1 end
 local function save(id)
  local f=assert(io.open(file..'.tmp','w'),'Cannot save model selection');assert(f:write('model='..id..'\n'));assert(f:close())
  os.remove(file..'.bak');local old=io.open(file,'r');if old then old:close();assert(os.rename(file,file..'.bak'))end
  local ok,e=os.rename(file..'.tmp',file);if not ok then os.rename(file..'.bak',file);error(e)end
  C.selected=id
 end
 local function findMarker(p)
  for _,v in ipairs(p:K2_GetComponentsByClass(scene))do local c=v:get();if valid(c)and P.markerId(c.AttachSocketName:ToString())~=nil then return c end end
 end
 local I={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 function C.mark(p,id,record)
  assert(p:HasAuthority()and P.allowed(id),'Host owns model selection')
  local c=record and record.marker;if not valid(c)then c=findMarker(p)end
  if not valid(c)then c=p:AddComponentByClass(scene,true,I,false);assert(valid(c),'Model marker unavailable');c:SetVisibility(false,false);c:SetComponentTickEnabled(false)end
  if P.markerId(c.AttachSocketName:ToString())~=id then c:K2_AttachToComponent(p.Mesh,FName(P.marker..id),0,0,0,false)end
  if not c.bReplicates then c:SetIsReplicated(true)end
  if record then record.marker=c end;p:FlushNetDormancy();p:ForceNetUpdate();return c
 end
 local function record(p)
  local key=p:GetFullName();local r=C.players[key]
  if not r or not same(r.actor,p)then r={actor=p,key=key,id=0,nextMarker=0};C.players[key]=r end;return r
 end
 local function owner(pc)
  local key=pc:GetFullName();local r=C.owners[key];if not r or not same(r.pc,pc)then r={pc=pc,id=0};C.owners[key]=r end;return r
 end
 function C.observe(p)
  if valid(p)and valid(pawnClass)and p:IsA(pawnClass)then C.humans[p:GetFullName()]=p end
 end
 function C.server(pc,nonce,id)
  if M.features==false or not valid(pc)or not pc:HasAuthority()or not P.allowed(id)then return false end
  local p=pc.PlayerControlled;local ps=pc.PlayerState
  -- Native UnPossess clears the human's PlayerState while driving. The RPC's
  -- server-owned controller still supplies PlayerControlled and its identity.
  if not isPlayer(p)or not valid(ps)or(valid(p.PlayerState)and not same(p.PlayerState,ps))then return false end
  C.states[p:GetFullName()]=ps
  local state=owner(pc);if not P.accept(state,nonce,id,os.clock())then return false end
  local r=record(p);C.mark(p,id,r);state.pawn=p
  if pc:IsLocalPlayerController()then C.ack(nonce,id)else pc:ClientMessage(P.message('ack',nonce,id),FName(P.kind),0)end
  return true
 end
 function C.ack(nonce,id)
  local pending=C.pending;if not pending or pending.nonce~=nonce or pending.id~=id then return end
  local ok,e=pcall(save,id);C.pending=nil;C.sent=true
  status(ok and(P.catalog[id+1].name..' selected. Saved on this PC.')or('Selected for this session; '..tostring(e):gsub('^.-:%d+: ','')))
 end
 function C.select(id)
  assert(P.allowed(id),'Unknown player model');local p,pc=H.GetPlayer(),H.GetPlayerController()
  assert(M.features~=false,'The host must run this version of Beyond Apocalypse')
  assert(isPlayer(p)and valid(pc),'Join a game first')
  if id==1 then R.load(p,'body',p.Mesh);R.load(p,'arms',p.FpsArm);R.load(p,'first_body',p.Mesh)end
  C.nonce=C.nonce%2147483647+1;C.pending={nonce=C.nonce,id=id,attempts=0,at=0};status('Applying '..P.catalog[id+1].name..'...');C.send()
 end
 function C.send()
  local pending=C.pending;if not pending or os.clock()<pending.at then return end
  if pending.attempts>=5 then C.pending=nil;status('Host did not confirm the choice. Everyone needs the same mod version.');return end
  local pc=H.GetPlayerController();if not valid(pc)then return end
  pending.attempts=pending.attempts+1;pending.at=os.clock()+3
  if pc:HasAuthority()then C.server(pc,pending.nonce,pending.id)else pc:ServerExecRPC(P.message('set',pending.nonce,pending.id))end
 end
 local function install()
  if C.installed then return end;C.installed=true
  NotifyOnNewObject('/Game/BP/Player/PlayerBase.PlayerBase_C',function(p)enqueue(function()C.observe(p)end)end)
  local function hook(path,before,after)C.hooks[path]={RegisterHook(path,before,after)}end
  hook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,msg)
   local ok,s=pcall(function()return msg:get():ToString()end);if not ok then return end;local nonce,id=P.parse(s,'set');if not nonce then return end
   local pc=ctx:get();enqueue(function()C.server(pc,nonce,id)end)
  end)
  hook('/Script/Engine.PlayerController:ClientMessage',function(ctx,msg,kind)
   if kind:get():ToString()~=P.kind then return end
   local ok,s=pcall(function()return msg:get():ToString()end);if not ok then return end;local nonce,id=P.parse(s,'ack');if not nonce then return end
   local pc=ctx:get();enqueue(function()if same(pc,H.GetPlayerController())then C.ack(nonce,id)end end)
  end)
  local path='/Game/BP/Player/CustomizablePlayer/MaleCharacter.MaleCharacter_C:SetClothes'
  -- Blueprint hooks run after the event; their third callback is ignored.
  if valid(StaticFindObject(path))then hook(path,function(ctx)
   local p=ctx:get();enqueue(function()if not valid(p)then return end
    local r=R.records[p:GetFullName()];if r then R.clothingChanged(r);R.hide(r)end
   end)
  end)end
  path='/Game/BP/PlayerController/PlayerControllerBase.PlayerControllerBase_C:SetFPSView '
  if valid(StaticFindObject(path))then hook(path,function(ctx)
   local pc=ctx:get();enqueue(function()if not valid(pc)then return end
    local p=pc.PlayerControlled;if not valid(p)then return end
    local r=R.records[p:GetFullName()];if r then R.hide(r);R.update(r,H.GetPlayer(),pc)end
   end)
  end)end
 end
 local function appearance(r,id,p,pc)
  if r.id~=id then if r.visual then R.remove(r.visual);r.visual=nil end;r.id=id;r.failed=nil end
  if id==1 and not r.failed then
   local ok,e=pcall(function()r.visual=R.apply(r.actor);R.syncWearables(r.visual);R.syncRagdoll(r.visual);R.hide(r.visual);R.update(r.visual,p,pc)end)
   if not ok then R.remove(r.visual or r.key);r.visual=nil;r.failed=tostring(e);log('Player model fallback: '..r.failed);if same(r.actor,p)then status('Soldier appearance unavailable; default retained.')end end
  end
 end
 function C.tick()
  local p,pc=H.GetPlayer(),H.GetPlayerController();if not valid(pc)then return end;install()
  if M.features==false or not isPlayer(p)then return end
  if C.localPC and not same(C.localPC,pc)then C.sent=false;C.pending=nil end;C.localPC=pc
  if not C.sent and not C.pending then local ok,e=pcall(C.select,C.selected);if not ok then C.sent=true;status(tostring(e):gsub('^.-:%d+: ',''))end end
  C.send()
  -- Only the local first-person visibility gate runs at the existing 20 Hz.
  local own=R.records[p:GetFullName()];if own then R.update(own,p,pc)end
  if os.clock()<C.nextAt then return end;C.nextAt=os.clock()+.5
  local gs=game:GetGameState(p);if not valid(gs)then return end
  local seen,members={},{}
  -- Possession changes PlayerState.PawnPrivate to the vehicle. Keep the human
  -- actor by its replicated PlayerState instead, including drivers at late join.
  if not C.seeded then C.seeded=true;for _,human in ipairs(FindAllOf('PlayerBase_C')or{})do C.observe(human)end end
  C.observe(p)
  C.states[p:GetFullName()]=pc.PlayerState
  gs.PlayerArray:ForEach(function(_,value)local ps=value:get();if valid(ps)then
   members[ps:GetAddress()]=true
   local ctl=ps:GetOwner();local human=valid(ctl)and ctl.PlayerControlled or ps.PawnPrivate
   if not isPlayer(human)then local vehicle=ps.PawnPrivate
    if valid(vehicle)and vehicle:IsA(StaticFindObject('/Script/VehicleSystemPlugin.VehicleSystemBase'))then human=vehicle.Driver end
   end
   if isPlayer(human)then C.observe(human);C.states[human:GetFullName()]=ps end
  end end)
  for key,pawn in pairs(C.humans)do
   local ps=C.states[key];if not valid(ps)and valid(pawn)then ps=pawn.PlayerState end
   if isPlayer(pawn)and valid(ps)and members[ps:GetAddress()]and valid(pawn.Mesh)then
    local r=record(pawn);seen[r.key]=true
    if pc:HasAuthority()then
     local ctl=ps:GetOwner();if valid(ctl)and same(ctl.PlayerControlled,pawn)then local state=owner(ctl)
      if not same(state.pawn,pawn)or not valid(r.marker)then C.mark(pawn,state.id,r);state.pawn=pawn end
     end
    end
    if not valid(r.marker)and os.clock()>=r.nextMarker then r.marker=findMarker(pawn);r.nextMarker=os.clock()+1 end
    local id=valid(r.marker)and P.markerId(r.marker.AttachSocketName:ToString())or 0;appearance(r,id or 0,p,pc)
   elseif not valid(pawn)or(valid(ps)and not members[ps:GetAddress()])then C.humans[key]=nil;C.states[key]=nil end
  end
  for key,r in pairs(C.players)do if not seen[key]then if r.visual then R.remove(r.visual)end;C.players[key]=nil end end
  for key,r in pairs(C.owners)do if not valid(r.pc)then C.owners[key]=nil end end
 end
 function C.reset()
  R.reset();C.players={};C.owners={};C.humans={};C.states={};C.seeded=false;C.pending=nil;C.sent=false;C.localPC=nil;C.nextAt=0;C.nonce=0;C.status=nil;C.revision=C.revision+1
 end
 return C
end

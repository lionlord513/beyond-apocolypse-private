-- Host snapshots use unique, host-created replicated marker tokens. Native
-- car-part IDs can all be zero; save GUIDs also differ on each client.
return function(M,G,T,H,valid,log)
 local S={states={},queue={},telemetryQueue={},sent={},seq=0,nextAt=0};local kind='BAHornetState'
 local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local scene=StaticFindObject('/Script/Engine.SceneComponent')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local identities={}
 local discovery={}
 local function token(c)
  return valid(c)and tonumber(c.AttachSocketName:ToString():match('^BA_HornetNet_(%d+)$'))or nil
 end
 function S.number(a,create)
  if not valid(a)then return 0 end
  local key=a:GetAddress();local saved=identities[key]
  if saved and valid(saved.actor)and saved.actor:GetAddress()==key and valid(saved.component)then return saved.id end
  for _,v in ipairs(a:K2_GetComponentsByClass(scene))do local c=v:get();local n=token(c);if n then identities[key]={actor=a,component=c,id=n};return n end end
  if create==false or not a:HasAuthority()then return 0 end
  if not S.nextToken then
   S.nextToken=1
   for _,c in ipairs(FindAllOf('SceneComponent')or{})do local n=token(c);if n then S.nextToken=math.max(S.nextToken,n+1)end end
  end
  local n=S.nextToken;S.nextToken=n+1
  local c=a:AddComponentByClass(scene,true,identity,false);assert(valid(c),'Hornet network marker unavailable')
  c:SetVisibility(false,false)
  c:K2_AttachToComponent(a.RootComponent,FName('BA_HornetNet_'..n),0,0,0,false);c:SetIsReplicated(true)
  a:FlushNetDormancy();a:ForceNetUpdate();log('Hornet identity '..n..' '..a:GetFullName());return n
 end
 function S.anchor(a)return S.number(a)end
 function S.matches(a,n)return n and n>0 and S.number(a,false)==n end
 function S.receive(s)
  if #s>180 then return end
  local seq,k,body=s:match('^BAHS1|(%d+)|([ATB])|([%d|]+)$');if not seq then return end
  local v={};for n in body:gmatch('%d+')do v[#v+1]=tonumber(n)end
  if not(k=='A'and(#v==4 or #v==7)or k=='B'and #v==5 or k=='T'and #v==2)or v[1]==0 then return end
  for _,n in ipairs(v)do if n>2147483647 then return end end
  if k=='A'and(v[2]>3 or v[4]<1 or v[4]>100000)or k=='B'and(v[2]<1 or v[2]>2 or v[4]>1)or k=='T'and(v[2]<1 or v[2]>100000)then return end
  if k=='A'and #v==7 and(v[5]>1 or v[6]>1000 or v[7]>15000)then return end
  seq=tonumber(seq);local key=k..v[1];local old=S.states[key]
  if old and seq<=old.seq then return end
  S.states[key]={seq=seq,k=k,v=v}
 end
 S.hook={RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(ctx,msg,ty)
  local ok,s=pcall(function()if ty:get():ToString()==kind then return msg:get():ToString()end end)
  if ok and s and #S.queue<256 then S.queue[#S.queue+1]=s end
 end)}
 local function host(now)
  local rows={};local anchors={}
  local function row(k,actor,...)
   local v={...};if v[1]==0 then return end
   local text=k..'|'..table.concat(v,'|');rows[#rows+1]={key=k..v[1],text=text,actor=actor}
  end
  for _,c in pairs(T.carriers)do if valid(c.actor)then row('T',c.actor,S.anchor(c.actor,true),math.floor(c.baseMass+.5))end end
  for _,r in pairs(G.tracked)do if valid(r.actor)then
   local id=S.anchor(r.actor);local guid=G.id(r.actor);if guid then anchors[guid]=id end
   local parked=pcall(T.blades.parked,r.actor)
   local flight=r.telemetry or r.flight or{}
   row('A',r.actor,id,T.blades.mask(r),valid(r.docked)and S.anchor(r.docked,true)or 0,math.floor((r.mass or r.actor.VehicleMesh:GetMass())+.5),parked and 1 or 0,math.floor(flight.rpm or 0),math.floor(flight.propRPM or 0))
  end end
  for _,r in pairs(T.blades.items)do if valid(r.actor)then
   local p=r.actor;local parent=p:GetAttachParentActor()
   row('B',p,S.number(p),r.side,anchors[r.owner]or 0,valid(p.ParentCarEquipableV2)and 1 or 0,T.hasCarrier(parent)and S.anchor(parent,true)or 0)
  end end
  local live={}
  for _,pc in ipairs(FindAllOf('PlayerController')or{})do if valid(pc)and pc:HasAuthority()and not pc:IsLocalPlayerController()and valid(pc.PlayerControlled)then
   local key=pc:GetAddress();live[key]=true;local sent=S.sent[key]or{};S.sent[key]=sent
   for _,r in ipairs(rows)do if T.distance(pc.PlayerControlled:K2_GetActorLocation(),r.actor:K2_GetActorLocation())<80000 then
    local old=sent[r.key]
    if not old or old.text~=r.text or now-old.at>=2 then
     S.seq=S.seq+1;pc:ClientMessage('BAHS1|'..S.seq..'|'..r.text,FName(kind),0);sent[r.key]={text=r.text,at=now}
    end
   end end
  end end
  for key in pairs(S.sent)do if not live[key]then S.sent[key]=nil end end
 end
 local function client(now)
  -- Reuse resolved identities; unresolved packets still retry on every recovery
  -- pass so late actors/markers retain the original recovery timing.
  local function index(class,kind)
   local cache=discovery[class]or{byId={},nextAt=0};discovery[class]=cache
   local missing=false
   for id,a in pairs(cache.byId)do
    if not valid(a)or S.number(a,false)~=id then cache.byId[id]=nil;missing=true end
   end
   for _,state in pairs(S.states)do
    if state.k==kind and not cache.byId[state.v[1]]then missing=true;break end
   end
   if missing or now>=cache.nextAt then
    local out={}
    for _,a in ipairs(FindAllOf(class)or{})do if valid(a)then
     local id=S.number(a,false);if id>0 and not out[id]then out[id]=a end
    end end
    cache.byId=out;cache.nextAt=now+1
   end
   return cache.byId
  end
  local carrierById={};local airById={}
  local trailersById=index('Vehicle_Trailer_C','T');local aircraftById=index('CaddieCar_C','A')
  for _,state in pairs(S.states)do if state.k=='T'then
   for _,t in ipairs({trailersById[state.v[1]]})do if valid(t)then
    T.deck(t);local c=T.carriers[t:GetFullName()]
    if c and c.baseMass~=state.v[2]then c.baseMass=state.v[2];c.massRestored=nil end
    carrierById[state.v[1]]=t;break
   end end
  end end
  for _,state in pairs(S.states)do if state.k=='A'then
   local v=state.v
   for _,a in ipairs({aircraftById[v[1]]})do if valid(a)then
    local ok,r=pcall(G.adopt,a,true)
    if ok and r then
     if not r.netState then log('Hornet client resolved '..v[1]..' '..a:GetFullName())end
     r.netState={mask=v[2],dock=v[3],mass=v[4],parked=v[5]==1,rpm=v[6]or 0,propRPM=v[7]or 0};r.netCarrier=carrierById[v[3]];airById[v[1]]=r
    elseif not ok and S.adoptError~=tostring(r)then S.adoptError=tostring(r);log('Aircraft client setup: '..S.adoptError)end
    break
   end end
  end end
  local itemsById=index('CarItemLightV2_C','B')
  for _,state in pairs(S.states)do if state.k=='B'then
   local v=state.v
   for _,p in ipairs({itemsById[v[1]]})do if valid(p)then
    local r=T.blades.skin(p,v[2]);r.netOwner=v[3];r.netFitted=v[4]==1;r.netRack=v[5];r.netCarrier=carrierById[v[5]]
    -- Each blade packet owns fitted/racked state. An older aircraft mask
    -- must not override a newer blade transition arriving on another actor.
    r.visual:SetVisibility(not r.netFitted,false);T.blades.syncRack(r);break
   end end
  end end
 end
 -- RPC callbacks copy the message only. Unreal object traversal and reflected
 -- calls must run after native RPC dispatch has returned, on the normal tick.
 -- This follows the existing queued transport/backpack request path.
 S.telemetryHook={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,arg)
  local ok,s=pcall(function()return arg:get():ToString()end);if not ok or #s>80 then return end
  local id,rpm,prop=s:match('^BAHF1|(%d+)|(%d+)|(%d+)$');id=tonumber(id);rpm=tonumber(rpm);prop=tonumber(prop)
  if not id or id<1 or id>2147483647 or rpm>1000 or prop>15000 or #S.telemetryQueue>=32 then return end
  S.telemetryQueue[#S.telemetryQueue+1]={pc=ctx:get(),id=id,rpm=rpm,prop=prop}
 end)}
 local function applyTelemetry(v)
  local pc=v.pc;if not valid(pc)or not pc:HasAuthority()or not valid(pc.PlayerControlled)then return end
  -- Revalidate the current pilot after dispatch: no stale seat/ownership grant.
  for _,r in pairs(G.tracked)do if valid(r.actor)and T.same(r.actor.Driver,pc.PlayerControlled)and not valid(r.docked)and not r.pendingDock and S.matches(r.actor,v.id)then
   r.telemetry={rpm=v.rpm,propRPM=v.prop};return
  end end
 end
 function S.telemetry(r,now)
  if r.actor:HasAuthority()then r.telemetry=nil;return end
  if now<(r.telemetryAt or 0)then return end;r.telemetryAt=now+.2
  local pc=H.GetPlayerController();local n=S.number(r.actor,false)
  if n>0 and valid(pc)and T.same(r.actor.Driver,pc.PlayerControlled)then pc:ServerExecRPC(('BAHF1|%d|%d|%d'):format(n,math.floor(r.flight.rpm),math.floor(r.flight.propRPM or 0)))end
 end
 function S.tick(p,now)
  if now<S.nextAt then return end;S.nextAt=now+.25
  if p:HasAuthority()then
   S.queue={} -- ClientMessage hooks also observe server-side sends
   local pending=S.telemetryQueue;S.telemetryQueue={}
   for _,v in ipairs(pending)do
    local ok,e=pcall(applyTelemetry,v)
    if not ok and S.telemetryError~=tostring(e)then S.telemetryError=tostring(e);log('Hornet telemetry rejected: '..S.telemetryError)end
   end
   host(now)
  else
   local q=S.queue;S.queue={};for _,s in ipairs(q)do S.receive(s)end;client(now)
  end
 end
 function S.reset()S.states={};S.queue={};S.telemetryQueue={};S.telemetryError=nil;S.sent={};S.seq=0;S.nextAt=0;S.nextToken=nil;identities={};discovery={} end
 return S
end

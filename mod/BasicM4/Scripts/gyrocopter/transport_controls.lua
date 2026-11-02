-- Context is selected locally; every operation is revalidated by the host.
-- Requests use unique host-created replicated marker tokens, never ID-zero
-- native car parts or client-only save GUIDs.
return function(M,G,T,H,valid,log)
 local C={queue={},incoming={},replyQueue={},last={},seq=0,nextHint=0};local B=T.blades;local J=T.journal
 local key=(M.config.Gyrocopter or{}).TransportKey or 'J'
 if not key:match('^[A-Z]$')or key:match('[WASDQEPRITBLZHXFG]')then key='J'end
 local replyType='BAHornetTransport';C.key=key
 local function number(p)if T.sync then return T.sync.number(p,false)end;return valid(p)and type(p.ID)=='number'and p.ID>0 and p.ID or 0 end
 local function aid(a)return T.sync and T.sync.anchor(a)or(valid(a)and number(a.CarSeatDriver.AttachedCarEquipableActor)or 0)end
 local function tid(t)return T.sync and T.sync.anchor(t,true)or(valid(t)and number(t.CarEquipableV2.AttachedCarEquipableActor)or 0)end
 local function nearest(p,list)
  local best,dist=nil,280
  for _,a in ipairs(list)do if valid(a)then local d=T.distance(p:K2_GetActorLocation(),a:K2_GetActorLocation());if d<dist then best,dist=a,d end end end
  return best
 end
 local function gyros()local out={};for _,r in pairs(G.tracked)do if valid(r.actor)then out[#out+1]=r.actor end end;return out end
 local function packet(op,a,t,p,side,label)return {op=op,a=aid(a),t=tid(t),b=number(p),side=side or 0,label=label}end
 function C.context(pc)
  local p=pc.PlayerControlled;if not valid(p)or p.BP_PlayerStats.IsDead or p.BP_PlayerStats.IsDying then return end
  local vehicle=pc.Vehicle;local r=valid(vehicle)and G.tracked[vehicle:GetFullName()]
  if r and T.same(vehicle.Driver,p)then
   if valid(r.docked)or r.pendingDock then return packet('undock',vehicle,nil,nil,0,'Release Hornet / refit blades, engine off')end
   local best,dist
   for _,c in pairs(T.carriers)do if valid(c.actor)and T.dockRange(vehicle,c.actor)then
    local d=T.distance(vehicle:K2_GetActorLocation(),c.actor:K2_GetActorLocation())
    if not dist or d<dist then best,dist=c.actor,d end
   end end
   if best then return packet('dock',vehicle,best,nil,0,'Snap onto pad and stow blades')end;return
  elseif valid(vehicle)then return end
  local a=nearest(p,gyros());local trailers=FindAllOf('Vehicle_Trailer_C')or{};local t=nearest(p,trailers)
  local held=M.backpack.native.held(pc);local side,owner;if held then side,owner=B.info(held)end
  if side then
   -- Host knows the matching aircraft even when native pilot-seat ID is zero.
   if owner then a=nil;for _,r in pairs(G.tracked)do if valid(r.actor)and G.id(r.actor)==owner and T.distance(p:K2_GetActorLocation(),r.actor:K2_GetActorLocation())<280 then a=r.actor;break end end end
   if t and T.hasCarrier(t)and T.same(pc.ItemTargeted,t)then return packet('rack',nil,t,held,side,'Secure blade in rack')end
   return
  end
  if held then return end
  if a and T.same(pc.ItemTargeted,a)then
   local ar=G.tracked[a:GetFullName()]
   if valid(ar.docked)or ar.pendingDock then return packet('undock',a,nil,nil,0,'Release Hornet / refit its blades')end
  end
 end
 local function resolve(request)
  local a,t,b
  for _,r in pairs(G.tracked)do if request.a>0 and valid(r.actor)and(T.sync and T.sync.matches(r.actor,request.a)or aid(r.actor)==request.a)then a=r.actor end end
  for _,o in ipairs(FindAllOf('Vehicle_Trailer_C')or{})do if request.t>0 and valid(o)and(T.sync and T.sync.matches(o,request.t)or tid(o)==request.t)then t=o end end
  for _,r in pairs(B.items)do if request.b>0 and valid(r.actor)and number(r.actor)==request.b then b=r.actor end end
  -- Blade ownership comes from host state, not an ambiguous ID-zero seat or a
  -- client-provided save GUID. This also protects adjacent aircraft from refits.
  if b and request.op=='fit'and request.a==0 then
   a=nil;local _,owner=B.info(b)
   for _,r in pairs(G.tracked)do if owner and valid(r.actor)and G.id(r.actor)==owner then a=r.actor;break end end
  end
  return a,t,b
 end
 function C.execute(pc,request)
  assert(valid(pc)and pc:HasAuthority(),'The host owns aircraft operations')
  local p=pc.PlayerControlled;assert(valid(p)and p.IsLoaded and p.IsInitialized and not p.BP_PlayerStats.IsDead and not p.BP_PlayerStats.IsDying,'Player unavailable')
  local gi=T.game:GetGameInstance(pc);assert(not gi.IsSaving,'Wait for the game save to finish');J.writable()
  local a,t,b=resolve(request);local inAircraft=valid(a)and T.same(a.Driver,p)
  local function reach(o)
   assert(valid(o),'Object has not synchronized yet')
   if inAircraft and T.same(a,o)then return end
   if T.same(o,b)and T.same(M.backpack.native.held(pc),b)then return end
   assert(T.distance(p:K2_GetActorLocation(),o:K2_GetActorLocation())<300 and pc:LineOfSightTo(o,{X=0,Y=0,Z=0},false),'Move closer with a clear view')
  end
  if request.op=='dock'then reach(a);assert(inAircraft,'Sit in the pilot seat to secure the Hornet');assert(valid(t),'Trailer unavailable');return T.dock(a,t)
  elseif request.op=='undock'then reach(a);return T.undock(assert(G.tracked[a:GetFullName()]))
  elseif request.op=='upgrade'then reach(t);return T.upgrade(t)
  elseif request.op=='fit'then
   reach(a);assert(valid(b),'Blade unavailable');reach(b)
   assert(not valid(pc.Vehicle),'Leave the pilot seat to handle blades')
   local side=B.info(b);assert(side and(request.side==1 or request.side==2),'Use a rotor blade');side=request.side
   local slot=B.slot(a,side)
   if T.same(slot.AttachedCarEquipableActor,b)and T.same(b.ParentCarEquipableV2,slot)then return 'Main blade already installed'end
   assert(T.same(M.backpack.native.held(pc),b),'Hold the blade first')
   return B.fit(pc,b,a,side)

  elseif request.op=='rack'then reach(t);reach(b);assert(T.hasCarrier(t),'Not a carrier');assert(T.same(M.backpack.native.held(pc),b),'Hold the blade first');return B.rack(pc,b,t)
  elseif request.op=='unrack'then reach(t);reach(b);return B.unrack(b)end
  error('Unknown transport operation')
 end
 local function prompt(pc,s)
  local hud=pc.HUD;if not valid(hud)then return end
  if not valid(C.promptRow)or C.promptHUD~=hud:GetAddress()then
   if valid(C.promptRow)then C.promptRow:RemoveFromParent()end
   C.promptRow=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),hud.WidgetTree)
   local font=hud.ArrowCompl.Font;font.Size=14;C.promptRow:SetFont(font)
   C.promptRow:SetColorAndOpacity({SpecifiedColor={R=.85,G=.8,B=.63,A=1},ColorUseRule=0})
   local row=hud.ActionBox:GetParent():AddChildToVerticalBox(C.promptRow)
   row:SetHorizontalAlignment(1);row:SetPadding({Left=0,Top=3,Right=0,Bottom=3});C.promptHUD=hud:GetAddress()
  end
  if s then C.promptRow:SetText(FText(s))end
  C.promptRow:SetVisibility(s and 3 or 1)
 end
 local function message(pc,s)
  s=tostring(s):gsub('.-%.lua:%d+: ',''):gsub('[\r\n|]',' '):sub(1,160)
  pc:ClientMessage(s,FName(replyType),4)
  if pc:IsLocalPlayerController()then C.feedback=s;C.untilAt=os.clock()+4 end
 end
 local function enqueue(pc,r)
  local k=pc:GetAddress();local previous=C.last[k]
  if previous and r.seq<=previous then return end
  C.last[k]=r.seq;C.queue[#C.queue+1]={pc,r}
 end
 function C.submit(pc,context)
  C.seq=C.seq+1;context.seq=C.seq
  log(('Hornet request #%d %s air=%d trailer=%d'):format(context.seq,context.op,context.a,context.t))
  if pc:HasAuthority()then enqueue(pc,context)else pc:ServerExecRPC(('BATR2|%d|%s|%d|%d|%d|%d'):format(context.seq,context.op,context.a,context.t,context.b,context.side));C.feedback='Waiting for host';C.untilAt=os.clock()+3 end
 end
 function C.fitContext(pc)
  if pc:HasAuthority()or valid(pc.Vehicle)then return end
  local held=M.backpack.native.held(pc);local blade=valid(held)and B.items[held:GetFullName()]
  local slot=pc.ItemSelected;local mount=valid(slot)and B.mounts.slots[slot:GetAddress()]
  if not(blade and mount and mount.parked)or valid(slot.AttachedCarEquipableActor)then return end
  local request=packet('fit',mount.actor,nil,held,mount.side)
  if request.a>0 and request.b>0 then return request end
 end
 C.hooks={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,arg)
  local ok,s=pcall(function()return arg:get():ToString()end);if not ok or s:sub(1,6)~='BATR2|'or #s>100 then return end
  local seq,op,a,t,b,side=s:match('^BATR2|(%d+)|(%a+)|(%d+)|(%d+)|(%d+)|([012])$')
  if not seq then return end
  if #C.incoming>=16 then return end
  C.incoming[#C.incoming+1]={ctx:get(),{seq=tonumber(seq),op=op,a=tonumber(a),t=tonumber(t),b=tonumber(b),side=tonumber(side)}}
 end)}
 C.reply={RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(ctx,s,kind)
  local ok,text=pcall(function()if kind:get():ToString()==replyType then return s:get():ToString()end end)
  if ok and text and #C.replyQueue<16 then C.replyQueue[#C.replyQueue+1]={ctx:get(),text}end
 end)}
 function C.tick(p,now)
  local incoming=C.incoming;C.incoming={}
  for _,v in ipairs(incoming)do if valid(v[1])and v[1]:HasAuthority()then enqueue(v[1],v[2])end end
  local replies=C.replyQueue;C.replyQueue={}
  for _,v in ipairs(replies)do if valid(v[1])and v[1]:IsLocalPlayerController()then C.feedback=v[2];C.untilAt=os.clock()+4 end end
  local requests=C.queue;C.queue={}
  for _,v in ipairs(requests)do local ok,result=pcall(C.execute,v[1],v[2]);log('Hornet '..v[2].op..' '..tostring(ok)..': '..tostring(result));if valid(v[1])then message(v[1],result or(ok and 'Done'or 'Operation failed'))end end
  local pc=H.GetPlayerController();if not valid(pc)then return end
  if M.controls then key=M.controls.values.transport[1];if key=='None'then key=M.controls.values.transport[2]end;C.key=key end
  local down=M.controls and M.controls.down(pc,'transport')or(not M.controls and pc:IsInputKeyDown({KeyName=FName(key)}));local pressed=down and not C.down;C.down=down
  local left=pc:IsInputKeyDown({KeyName=FName('LeftMouseButton')});local clicked=left and not C.left;C.left=left
  if pc.HUD.ChatUI.TypeInChat or H.IsPauseMenu(pc)or M.devmenu.ui.opened or M.backpack.ui.opened or(M.utility and M.utility.opened) then if valid(C.promptRow)then C.promptRow:SetVisibility(1)end;return end
  local context=C.context(pc)
  -- Runtime native mount shapes are local objects. Send stable actor tokens
  -- for the same left-click action; the host rechecks the original held part.
  if clicked then local fit=C.fitContext(pc);if fit then C.submit(pc,fit)end end
  if pressed and context then
   C.submit(pc,context)
  end
  if now>=C.nextHint then
   C.nextHint=now+.25;local hint=C.untilAt and os.clock()<C.untilAt and C.feedback or context and '['..key..'] '..context.label
   prompt(pc,hint)
  end
 end
 function C.reset()C.queue={};C.incoming={};C.replyQueue={};C.last={};C.seq=0;C.nextHint=0;C.down=false;C.left=false;C.feedback=nil;if valid(C.promptRow)then C.promptRow:RemoveFromParent()end;C.promptRow=nil;C.promptHUD=nil end
 return C
end

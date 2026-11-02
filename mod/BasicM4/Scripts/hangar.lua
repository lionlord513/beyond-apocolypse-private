return function(M,root,H,valid,enqueue,log)
 local A={last={},seq=0,queue=0,nextAt=0,terminals={}}
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local widget=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
 local items={
  {id='chassis',name='Hornet airframe',price=8500,description='Airframe with fuel tank. Other parts sold separately.'},
  {id='blade',name='Universal rotor blade',price=1200},
  {id='motor',name='Dada engine',key='LadaMotor_C'},
  {id='battery',name='Battery 50',key='Battery50_C'},
  {id='radiator',name='6L radiator',price=1000,iconKey='Radiator6L_C'},
  {id='trailer',name='Landing-pad trailer',price=7500,description='Transport trailer with helicopter landing pad.'},
  {id='suzukiframe',name='Suzuki PV 50 rolling frame',price=3600,description='Compact moped. Uses the same replaceable engine, battery and radiator sold above.'},
  {id='bikeframe',name='Motorcycle rolling frame',price=4200,description='Stock seat and wheels. Motor, battery and radiator can be swapped with Hangar parts.'},
  {id='sight',name='2x sight',price=1500,category='apocalypse'},
  {id='lamp',name='Flashlight',key='LampeTorche_C',category='apocalypse'},
  {id='smallbag',name='Small backpack',key='BackpackBase_C',category='apocalypse'},
  {id='ammo',name='Rifle ammunition',price=300,category='apocalypse',description='30 rifle rounds. Compatible with all rifles.'},
  {id='m4',name='M4A1',price=6500,category='apocalypse'},
  {id='hunting',name='Hunting Rifle',price=5000,category='apocalypse'},
  {id='enfield',name='Lee-Enfield',price=8000,category='apocalypse'},
 }
 for _,d in ipairs(dofile(root..'/Scripts/nitrous/catalog.lua'))do
  items[#items+1]={id='nitrous'..d.id,name=d.name,price=d.price,nitrous=d.id,
   description=('%d L refillable bottle. Attach anywhere on a car. Hold Shift to boost. Stage %s.'):format(d.litres,d.tier==1 and 'I'or 'II')}
 end
 A.items=items
 local function identity(a)
  if not M.guid(a)then a.GuidUnique=StaticFindObject('/Script/Engine.Default__KismetGuidLibrary'):NewGuid()end
  return assert(M.guid(a),'Item identity unavailable')
 end
 local parcels=dofile(root..'/Scripts/hangar_parcels.lua')(M,valid,log);A.parcels=parcels
 local function nearest(p,pc)
  local best,distance;local q=p:K2_GetActorLocation()
  local active=A.terminals[pc:GetAddress()]
  -- Native Open PC already validates interaction. Its actor origin can be
  -- occluded even while the native terminal is open; keep the range check.
  if valid(active)then local at=active:K2_GetActorLocation();if (at.X-q.X)^2+(at.Y-q.Y)^2+(at.Z-q.Z)^2<500^2 then return active end end
  for _,t in ipairs(FindAllOf('BP_eBayPC_C')or{})do if valid(t)then local at=t:K2_GetActorLocation();local d=(at.X-q.X)^2+(at.Y-q.Y)^2+(at.Z-q.Z)^2
   if d<500^2 and(not distance or d<distance)and pc:LineOfSightTo(t,{X=0,Y=0,Z=0},false)then best=t;distance=d end
  end end;return best
 end
 function A.parcel(p,part,item,at)
  local tr={Translation=at,Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
  local box=game:BeginDeferredActorSpawnFromClass(p,LoadAsset('/Game/BP/EbaySystem/BP_eBayColis.BP_eBayColis_C'),tr,2,nil,0);assert(valid(box),'Parcel unavailable')
  local ok,why=pcall(function()
   box.CarClassToSpawn=part:GetClass();box.HUDName=FText(item.name);box.FromShop=true;box.Key=part:GetClass():GetFName()
   game:FinishSpawningActor(box,tr,0);box:OnSpawn();identity(box)
   local inventory=StaticConstructObject(FindObject('BlueprintGeneratedClass','BP_InventoryComponent_C'),box);inventory.NbSlot=1
   local eligible=part.CanBeInBackpack;part.CanBeInBackpack=true;local out={};local worked,e=pcall(function()inventory:AddItemToSlot(0,part,false,false,out)end);part.CanBeInBackpack=eligible
   assert(worked,e);assert(out.Added and inventory.Slots:Contains(0),'Cannot pack this item')
   local data=inventory.Slots:Find(0):get();assert(valid(data.Class)and #data.ByteData>0,'Empty parcel contents')
   box.ActorData=data;box.ClassOfItemToSpawn=part:GetClass();box.ClassToSpawn=part:GetClass();box.ClassToSpawnWhenOpen=part:GetClass();box.HUDName=FText(item.name)
   parcels.prepare(box,part,item.id)
   inventory.Slots:Empty();box:FlushNetDormancy();box:ForceNetUpdate()
  end)
  if not ok then box:K2_DestroyActor();error(why)end
  part:K2_DestroyActor();return box
 end
 function A.purchase(pc,id)
  assert(M.features~=false and pc:HasAuthority(),'Host owns purchases')
  local p=pc.PlayerControlled;assert(valid(p)and p.IsLoaded and not p.BP_PlayerStats.IsDead and not p.BP_PlayerStats.IsDying and not valid(pc.Vehicle),'Player unavailable')
  assert(not game:GetGameInstance(pc).IsSaving,'Wait for the save to finish')
  local terminal=assert(nearest(p,pc),'Use a nearby visible computer')
  local item;for _,row in ipairs(items)do if row.id==id then item=row end end;assert(item and not item.key,'Invalid aircraft order')
  local q=terminal:K2_GetActorLocation();local at
  if id=='chassis'or id=='trailer'then
  for _,radius in ipairs({1200,1800,2400})do for i=0,7 do local a=i*math.pi/4
   at=M.gyrocopter.clearance(p,{X=q.X+math.cos(a)*radius,Y=q.Y+math.sin(a)*radius,Z=q.Z});if at then break end
  end;if at then break end end
  assert(at,'Clear level ground around the terminal before ordering')
  else local q,f=p:K2_GetActorLocation(),p:GetActorForwardVector();at={X=q.X+f.X*100,Y=q.Y+f.Y*100,Z=q.Z-40}end
  local paid={};pc:TryPurchase(item.price,false,paid);assert(paid.Success,'Not enough money')
  local created
  local ok,e=pcall(function()
   if id=='chassis'then local pending;created,pending=M.gyrocopter.create(p,true,at,false);pending.bare=true;pending.onFailure=function()if valid(pc)then pc:AddMoney(item.price);pc:ClientMessage('Airframe delivery failed; purchase refunded.',FName('Hangar'),5)end end;return end
   if id=='bikeframe'or id=='suzukiframe'then
    created=M.motorcycle.spawn(p,function()if valid(pc)then pc:AddMoney(item.price);pc:ClientMessage('Motorcycle delivery failed; purchase refunded.',FName('Hangar'),5)end end,id=='suzukiframe'and 'suzuki'or 'classic')
    return
   end
   if id=='trailer'then local _;_,created=M.gyrocopter.transport.create(p,true,at);return end
   if item.nitrous then created=M.nitrous.spawn(p,item.nitrous,{X=at.X,Y=at.Y,Z=at.Z+50});created=A.parcel(p,created,item,at);return end
   local path=id=='radiator'and '/Game/BP/CarsV2/System/Actors/Radiator/Radiator6L.Radiator6L_C'or id=='ammo'and '/Game/BP/Items/Movable/Bullets/AkBullet.AkBullet_C'or M.definitions[id]and M.definitions[id].BaseClass or id=='tank'and '/Game/BP/CarsV2/System/Actors/Lada/LadaTank.LadaTank_C'or id=='blade'and '/Game/BP/CarsV2/System/Actors/GTR/BP_GTR_Light_HL.BP_GTR_Light_HL_C'or '/Game/BP/Items/Movable/Binocular/Binocular.Binocular_C'
   local cls=LoadAsset(path);assert(valid(cls),'Part model unavailable')
   local tr={Translation={X=at.X,Y=at.Y,Z=at.Z+50},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
   created=game:BeginDeferredActorSpawnFromClass(p,cls,tr,2,nil,0);assert(valid(created),'Delivery space unavailable');if id=='ammo'then created.Min=30;created.Max=30;created.NbBullet=30 end;game:FinishSpawningActor(created,tr,0);if id=='ammo'then created.NbBullet=30;assert(created.NbBullet==30,'Ammo count changed during native spawn')end;identity(created)
   if id=='blade'then
    local B=M.gyrocopter.transport.blades;local J=M.gyrocopter.transport.journal;J.writable();local guid=assert(M.guid(created));J.state.blade[guid]={guid,1};B.skin(created,1,guid)
   elseif id=='sight'then M.rail.journal.writable();M.rail.optic.markItem(created)elseif M.definitions[id]then M.force(created,id)end
   created=A.parcel(p,created,item,at)
  end)
  if not ok then if valid(created)then created:K2_DestroyActor()end;pc:AddMoney(item.price);error(e)end
  return item.name..' ordered'
 end
 function A.buy(index)
  local item=items[index];if not item then return end
  local pc=H.GetPlayerController();local p=H.GetPlayer();local e=p.AC_EbaySystem
  if item.key then
   assert(valid(e.HUDREF)and e.PrimaryData.Structure:Contains(FName(item.key)),'Shop is still loading')
   local c=LoadAsset('/Game/BP/EbaySystem/HUD_EbayCarItem.HUD_EbayCarItem_C');assert(valid(c),'Native shop unavailable')
   local b=widget:Create(pc,c,pc);b.BuyMenuRef=e.HUDREF;b.ItemIndex=e.PrimaryData.Structure:Find(FName(item.key)):get()
   e.HUDREF:RsCarBuyButton(b);b:RemoveFromParent();A.purchaseButton=b
  elseif pc:HasAuthority()then A.ui.status(A.purchase(pc,item.id))
  else
   assert(not A.pending,'Order pending; wait for the server response')
   A.seq=A.seq+1;A.pending={seq=A.seq,at=os.clock()};A.ui.status('Ordering '..item.name..'...')
   pc:ServerExecRPC('BAHG2|'..A.seq..'|'..item.id)
  end
 end
 local ui=dofile(root..'/Scripts/hangar_ui.lua')(A,M,root,valid,enqueue);A.ui=ui
 function A.tick()
  if M.features==false then ui.reset();return end
  if not A.pcHook then A.pcHook={RegisterHook('/Game/BP/EbaySystem/AC_EbaySystem.AC_EbaySystem_C:Open PC',function(ctx,arg)
   local e=ctx:get();local terminal=arg:get();local p=valid(e)and e:GetOwner();local pc=valid(p)and p:GetController()
   if valid(pc)and valid(terminal)then
    A.terminals[pc:GetAddress()]=terminal
    if not pc:HasAuthority()then local q=terminal:K2_GetActorLocation();pc:ServerExecRPC(('BAHC1|%.0f|%.0f|%.0f'):format(q.X,q.Y,q.Z))end
   end
  end)}end
  if not A.rpc then A.rpc={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(ctx,msg)
   local ok,s=pcall(function()return msg:get():ToString()end);if not ok or #s>48 then return end
   local x,y,z=s:match('^BAHC1|(%-?%d+)|(%-?%d+)|(%-?%d+)$')
   if x then
    x,y,z=tonumber(x),tonumber(y),tonumber(z);if math.max(math.abs(x),math.abs(y),math.abs(z))>2147483647 or A.queue>=8 then return end
    local pc=ctx:get();A.queue=A.queue+1;enqueue(function()
     A.queue=math.max(0,A.queue-1);if not valid(pc)or not pc:HasAuthority()or not valid(pc.PlayerControlled)then return end
     local p=pc.PlayerControlled:K2_GetActorLocation();if (p.X-x)^2+(p.Y-y)^2+(p.Z-z)^2>=500^2 then return end
     for _,t in ipairs(FindAllOf('BP_eBayPC_C')or{})do if valid(t)then local q=t:K2_GetActorLocation();if math.abs(q.X-x)<=2 and math.abs(q.Y-y)<=2 and math.abs(q.Z-z)<=2 then A.terminals[pc:GetAddress()]=t;break end end end
    end);return
   end
   local protocol,seq,id=s:match('^(BAHG[12])|(%d+)|([%a%d]+)$');seq=tonumber(seq)
   if not seq or seq>2147483647 or A.queue>=8 then return end
   local pc=ctx:get();A.queue=A.queue+1;enqueue(function()
    A.queue=math.max(0,A.queue-1);if not valid(pc)or not pc:HasAuthority()then return end
    local key=pc:GetFullName();local old=A.last[key]
    local function reply(result)
     pc:ClientMessage(protocol=='BAHG2'and('BAHR2|'..seq..'|'..result)or result,FName('Hangar'),5)
    end
    if old and seq<=old.seq then reply(seq==old.seq and old.result or 'Old order ignored; order again');return end
    local good,result=pcall(A.purchase,pc,id);result=tostring(result):gsub('^.-:%d+: ','')
    A.last[key]={seq=seq,result=result};reply(result)
   end)
  end)}end
  if not A.replyHook then A.replyHook={RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(ctx,msg,kind)
   if kind:get():ToString()~='Hangar'then return end
   local text=msg:get():ToString();local pc=ctx:get()
   enqueue(function()
    local localPC=H.GetPlayerController();if not valid(pc)or not valid(localPC)or pc:GetAddress()~=localPC:GetAddress()then return end
    local seq,result=text:match('^BAHR2|(%d+)|(.*)$')
    if seq then if not A.pending or A.pending.seq~=tonumber(seq)then return end;A.pending=nil;ui.status(result)else ui.status(text)end
   end)
  end)}end
  if A.pending and os.clock()-A.pending.at>15 then A.pending=nil;ui.status('No server reply. Check that the host has the same mod version before ordering again.')end
  parcels.install()
  if os.clock()<A.nextAt then return end;A.nextAt=os.clock()+.5
  local pc=H.GetPlayerController();local p=H.GetPlayer();if not valid(pc)or not valid(p)then return end
  local e=p.AC_EbaySystem;local hud=valid(e)and e.HUDREF;if not valid(hud)or not hud:IsInViewport()then if ui.ui or ui.app then ui.reset()end;return end
  if not valid(e.PrimaryData)then return end
  if not A.catalogue then
   local seats={};e.PrimaryData.Structure:ForEach(function(k,v)local key=k:get():ToString();local d=v:get();if key:lower():find('seat')and d.ItemPrice>0 then local cls=d.ItemClass;while valid(cls)do if cls:GetFName():ToString()=='CarItemSeat_C'then seats[#seats+1]={id='seat'..#seats,name=d.HUDName:ToString(),key=key};break end;cls=cls:GetSuperStruct()end end end)
   table.sort(seats,function(a,b)local ap=a.key=='LadaSeat_C'and 0 or 1;local bp=b.key=='LadaSeat_C'and 0 or 1;if ap~=bp then return ap<bp end;return a.name<b.name end);for i=1,math.min(2,#seats)do items[#items+1]=seats[i]end;A.catalogue=true
  end
  ui.tick(hud,pc)
 end
 function A.reset()ui.reset();A.last={};A.pending=nil;A.nextAt=0;A.terminals={} end
 return A
end

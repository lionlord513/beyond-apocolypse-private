-- One retained, click-through cluster. Telemetry/text at 10 Hz; only bars move per frame.
return function(M,H,valid)
 local D={nextAt=0,cache={},bars={},segments={}};local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local colors={bg={R=.012,G=.019,B=.029,A=.91},line={R=.13,G=.19,B=.25,A=1},text={R=.90,G=.95,B=1,A=1},muted={R=.39,G=.50,B=.61,A=1},blue={R=.12,G=.57,B=1,A=1},purple={R=.65,G=.28,B=1,A=1},red={R=1,G=.20,B=.15,A=1},amber={R=1,G=.62,B=.15,A=1},green={R=.24,G=.85,B=.63,A=1}}
 local function clamp(x)return math.max(0,math.min(1,x))end
 local function new(k,outer)return StaticConstructObject(StaticFindObject('/Script/UMG.'..k),outer)end
 local function text(id,value)
  if D.cache[id]~=value then D.cache[id]=value;D[id]:SetText(FText(value))end
 end
 local function tint(o,c)o:SetColorAndOpacity({SpecifiedColor=c,ColorUseRule=0})end
 local function color(id,c)if D.cache[id..'Color']~=c then D.cache[id..'Color']=c;tint(D[id],c)end end
 function D.hide()
  if valid(D.widget)then D.widget:RemoveFromParent()end;D.widget=nil;D.bars={};D.cache={};D.segments={};D.vehicle=nil
 end
 local function build(pc,flight)
  D.hide();D.rpmCount=nil;D.batteryColor=nil;D.scale=nil;local w=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,StaticFindObject('/Script/UMG.UserWidget'),pc)
  local tree=w.WidgetTree;if not valid(tree)then tree=new('WidgetTree',w);w.WidgetTree=tree end
  local canvas=new('CanvasPanel',tree);tree.RootWidget=canvas
  local panel=new('CanvasPanel',tree);local slot=canvas:AddChildToCanvas(panel)
  slot:SetAnchors({Minimum={X=1,Y=.52},Maximum={X=1,Y=.52}});slot:SetAlignment({X=1,Y=.5});slot:SetPosition({X=-30,Y=0})
  local height=flight and 426 or 342;slot:SetSize({X=304,Y=height});D.panel=panel;D.slot=slot
  local function box(x,y,width,height,c,round)
   local o=new('Image',tree)
   if round then o:SetBrush({DrawAs=4,TintColor={SpecifiedColor=c,ColorUseRule=0},OutlineSettings={Color={SpecifiedColor=colors.line,ColorUseRule=0},Width=1,CornerRadii={X=round,Y=round,Z=round,W=round},RoundingType=0}})else o:SetColorAndOpacity(c)end
   local s=panel:AddChildToCanvas(o);s:SetPosition({X=x,Y=y});s:SetSize({X=width,Y=height});return o,s
  end
  local function label(id,x,y,width,height,size,c,align)
   local t=new('TextBlock',tree);local f=t.Font;f.Size=size;t:SetFont(f);tint(t,c or colors.text);if align then t:SetJustification(align)end
   local s=panel:AddChildToCanvas(t);s:SetPosition({X=x,Y=y});s:SetSize({X=width,Y=height});D[id]=t;return t
  end
  box(0,0,304,height,colors.bg,14);box(20,16,3,15,colors.blue)
  label('title',32,15,218,22,11,colors.muted)
  -- Battery warning is a real vector symbol, independent of font glyph support.
  D.batteryIcon={}
  for _,r in ipairs({{264,18,23,2},{264,30,23,2},{264,18,2,14},{285,18,2,14},{268,15,5,3},{278,15,5,3},{269,24,5,2},{278,24,5,2},{280,22,1.5,6}})do D.batteryIcon[#D.batteryIcon+1]=box(r[1],r[2],r[3],r[4],colors.muted)end
  label('speed',18,35,205,82,62,colors.text,2);label('unit',228,90,57,18,10,colors.muted);text('unit','KM/H')
  box(230,47,54,37,{R=.04,G=.07,B=.10,A=1},7);label('gear',230,49,54,35,21,colors.blue,1)
  for i=1,18 do D.segments[i]=box(20+(i-1)*14.7,125,11.5,5,colors.line)end
  label('rpm',20,139,135,18,10,colors.muted);label('temperature',160,139,124,18,10,colors.muted,2)
  local base=170
  if flight then
   box(20,168,264,1,colors.line)
   label('altitude',20,181,126,29,20);label('climb',158,181,126,29,20,colors.text,2)
   label('altlabel',20,213,126,16,9,colors.muted);text('altlabel','ALTITUDE / MSL')
   label('climblabel',158,213,126,16,9,colors.muted,2);text('climblabel','VERTICAL / M/S')
   label('collectiveLabel',20,237,120,16,10,colors.muted);text('collectiveLabel','COLLECTIVE')
   label('collectiveValue',193,235,91,19,12,colors.blue,2)
   box(20,260,264,5,colors.line);local o,s=box(20,260,0,5,colors.blue);D.bars.collective={image=o,slot=s,width=264,height=5,target=0,display=0}
   local _,hover=box(20,257,2,11,colors.amber);D.hover=hover;base=282
  end
  local rows=flight and {'fuel','oil','coolant','battery'}or {'fuel','oil','coolant','battery','nitrous'}
  for i,key in ipairs(rows)do
   local y=base+(i-1)*26
   label(key..'Label',20,y,76,15,9,colors.muted);text(key..'Label',({fuel='FUEL',oil='OIL',coolant='COOLANT',battery='BATTERY',nitrous='NITROUS'})[key])
   label(key..'Value',184,y-1,100,17,10,colors.text,2)
   box(99,y+5,77,4,colors.line);local o,s=box(99,y+5,0,4,colors.blue);D.bars[key]={image=o,slot=s,width=77,height=4,target=0,display=0}
  end
  box(20,height-37,264,1,colors.line);label('status',20,height-25,264,18,10,colors.muted)
  w:AddToViewport(7900);w:SetVisibility(3);D.widget=w;D.flightMode=flight;D.height=height
 end
 local function fluid(a)
  if not valid(a)then return nil end;local t=a.ItemTankComponent;if not valid(t)then return nil end
  return math.max(0,t.ActualQuantity),math.max(0,t.MaxQuantity)
 end
 local function part(a,key)local c=a[key];return valid(c)and c.AttachedCarEquipableActor or nil end
 local function gauge(key,qty,capacity,unit)
  local bar=D.bars[key];if not bar then return end
  local has=type(qty)=='number'and type(capacity)=='number'and capacity>0
  local percent=has and clamp(qty/capacity)or 0;bar.target=percent
  local c=not has and colors.muted or percent<.1 and colors.red or percent<.25 and colors.amber or key=='nitrous'and D.nitrousColor or colors.blue
  if bar.color~=c then bar.color=c;bar.image:SetColorAndOpacity(c)end
  text(key..'Value',not has and '--'or unit=='%'and ('%.0f%%'):format(percent*100)or ('%.1f / %.0f L'):format(qty,capacity))
 end
 function D.flight(message,collective,hover,climb)D.flightMessage=message;D.flightCollective=collective;D.flightHover=hover end
 function D.tick(now)
  if now<D.nextAt then return end;D.nextAt=now+.1
  local pc=H.GetPlayerController();local a=valid(pc)and pc.Vehicle
  if M.features==false or M.config.VehicleDashboard==false or not valid(a)or not valid(a.VehicleMesh)then if D.widget then D.hide()end;return end
  local key=a:GetFullName();local r=M.gyrocopter and M.gyrocopter.tracked[key];local flight=r~=nil
  if not valid(D.widget)or D.flightMode~=flight or D.vehicle~=key then build(pc,flight);D.vehicle=key end
  local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary');local viewport=layout:GetViewportSize(pc);local dpi=layout:GetViewportScale(pc)
  local scale=math.min(1,viewport.Y/dpi/720);if D.scale~=scale then D.scale=scale;D.panel:SetRenderTransformPivot({X=1,Y=.5});D.panel:SetRenderScale({X=scale,Y=scale})end
  local v=a.VehicleMesh:GetPhysicsLinearVelocity(FName('None'));local speed=math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)*.036
  text('speed',('%03d'):format(math.floor(speed+.5)))
  local bike=M.motorcycle and M.motorcycle.tracked[key]
  local title=flight and 'HORNET / FLIGHT' or bike and(bike.variant=='suzuki'and 'SUZUKI PV 50'or 'MOTORCYCLE')or a:GetClass():GetFName():ToString():gsub('_C$',''):gsub('(%l)(%u)','%1 %2'):gsub('CarNew',''):gsub('Car$',''):upper()
  text('title',title:sub(1,26))
  local motor=part(a,'CarMotorV2');local battery=part(a,'CarBatteryV2')
  local rpm=flight and r.result and r.result.rpm or a.RPM or 0;local maximum=flight and 400 or a.IdleMaxRPM or 7000
  local count=math.floor(clamp(rpm/math.max(1,maximum))*18+.5)
  if D.rpmCount~=count then D.rpmCount=count;for i,o in ipairs(D.segments)do o:SetColorAndOpacity(i>count and colors.line or i>15 and colors.red or i>12 and colors.amber or colors.blue)end end
  text('rpm',(flight and 'ROTOR 'or '')..('%.0f RPM'):format(rpm))
  text('temperature',valid(motor)and ('%.0f C'):format(motor.Heat)or 'NO ENGINE');color('temperature',valid(motor)and motor.IsHeatLimit and colors.red or colors.muted)
  local gear=a.CurrentGear;text('gear',flight and 'AIR'or gear<0 and 'R'or gear==0 and 'N'or tostring(gear))
  local fq,fc=fluid(part(a,'CarTankGasV2'));gauge('fuel',fq,fc)
  local oq,oc=fluid(motor);gauge('oil',oq,oc)
  local cq,cc=fluid(part(a,'CarRadiatorV2'));gauge('coolant',cq,cc)
  local bq,bc=valid(battery)and battery.Capacity or nil,valid(battery)and battery.CapacityMax or nil;gauge('battery',bq,bc,'%')
  local required=valid(motor)and not a.EngineRunning and motor.EnergyToStartMotor or 0
  local badBattery=not bq or bq<math.max(.1,(battery.CapacityUsed or 0),required)or bq/math.max(.001,bc)<.1
  local iconColor=badBattery and colors.red or colors.muted
  if D.batteryColor~=iconColor then D.batteryColor=iconColor;for _,o in ipairs(D.batteryIcon)do o:SetColorAndOpacity(iconColor)end end
  local nr=M.nitrous and M.nitrous.cars[key];D.nitrousColor=nr and nr.tier==2 and colors.purple or colors.blue
  if flight then
   local x=r.result or {};text('altitude',('%.0f m'):format(a:K2_GetActorLocation().Z*.01));text('climb',('%+.1f'):format(v.Z*.01))
   local collective=x.collective or D.flightCollective or 0;D.bars.collective.target=clamp(collective);text('collectiveValue',('%.1f%%'):format(collective*100))
   local hover=x.hoverCollective or D.flightHover;D.hover:SetPosition({X=20+264*clamp(hover or .5),Y=257})
   text('status',not r.running and 'START ENGINE / '..(M.controls and M.controls.values.ignition[1]or 'I')or x.lowRotor and 'ROTOR SPOOLING UP'or M.controls and M.controls.simpleFlight and 'SIMPLE FLIGHT / AUTO HOVER'or 'MANUAL FLIGHT / F9 CONTROLS')
  else
   gauge('nitrous',nr and nr.litres,nr and nr.capacity)
   local status=badBattery and 'BATTERY / LOW OR MISSING'or not valid(motor)and 'ENGINE MISSING'or motor.IsHeatLimit and 'ENGINE OVERHEATING'or not a.EngineRunning and 'ENGINE OFF'or fq and fq<.1 and 'FUEL EMPTY'or nr and nr.active and ('NITROUS / STAGE '..(nr.tier==2 and 'II'or 'I'))or nr and (nr.litres or 0)>.001 and 'HOLD SHIFT / NITROUS'or nr and 'NITROUS EMPTY'or 'SYSTEMS READY'
   text('status',status);color('status',badBattery and colors.red or nr and nr.active and D.nitrousColor or colors.muted)
  end
 end
 function D.frame(dt)
  if not valid(D.widget)then return end
  local r=M.gyrocopter and M.gyrocopter.hudRecord
  if D.flightMode and r and r.result and D.bars.collective then D.bars.collective.target=clamp(r.result.collective or 0)end
  local alpha=1-math.exp(-35*math.max(0,math.min(dt or 0,.1)))
  for _,bar in pairs(D.bars)do local value=bar.display+(bar.target-bar.display)*alpha
   if math.abs(value-bar.display)>.0001 then bar.display=value;bar.slot:SetSize({X=bar.width*value,Y=bar.height})end
  end
 end
 function D.reset()D.hide();D.nextAt=0;D.scale=nil;D.rpmCount=nil;D.batteryColor=nil;D.flightMessage=nil end
 return D
end

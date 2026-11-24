local scripts,dir=arg[1],arg[2]
local labels={};local imports=0
local function widget()
 local w={Font={},visible=0}
 for _,m in ipairs({'SetColorAndOpacity','SetBrushFromTexture','SetBrush','SetRenderTransformPivot','SetRenderTransformAngle','SetRenderScale','SetAnchors','SetAlignment','SetJustification','AddToViewport','RemoveFromParent'})do w[m]=function()end end
 w.SetText=function(_,t)w.text=t end;w.SetFont=function(_,f)w.Font=f end;w.SetClipping=function(_,v)w.clipping=v end
 w.SetVisibility=function(_,v)w.visible=v end;w.SetPosition=function(_,p)w.position=p end;w.SetSize=function(_,s)w.size=s end
 w.AddChildToCanvas=function(_,o)local s=widget();o.slot=s;return s end
 return w
end
StaticConstructObject=function(c)local w=widget();if c:find('TextBlock')then labels[#labels+1]=w end;return w end
local lib={Create=function()local w=widget();w.WidgetTree={};return w end}
StaticFindObject=function(path)
 if path:find('KismetRenderingLibrary')then return {ImportFileAsTexture2D=function()imports=imports+1;return {}end}end
 if path:find('WidgetBlueprintLibrary')then return lib end
 if path:find('WidgetLayoutLibrary')then return {GetViewportSize=function()return {X=1600,Y=900}end,GetViewportScale=function()return 1 end}end
 return path
end
FText=function(v)return v end;FName=function(v)return v end
local function valid(v)return type(v)=='table'end
local motor={ItemTankComponent={ActualQuantity=2,MaxQuantity=4},Heat=70,EnergyToStartMotor=1}
local battery={Capacity=40,CapacityMax=50}
local car={VehicleMesh={GetPhysicsLinearVelocity=function()return {X=0,Y=0,Z=0}end},CurrentGear=0,RPM=0,IdleMaxRPM=7000,EngineRunning=false,
 CarMotorV2={AttachedCarEquipableActor=motor},CarBatteryV2={AttachedCarEquipableActor=battery},CarTankGasV2={AttachedCarEquipableActor={ItemTankComponent={ActualQuantity=10,MaxQuantity=40}}},
 GetFullName=function()return 'QA car'end,GetAddress=function()return 99 end,GetClass=function()return {GetFName=function()return {ToString=function()return 'LadaCarNew_C'end}end}end}
local pc={Vehicle=car};local data='';ModRef={GetSharedVariable=function()return data end}
local M={root=scripts..'/..',config={},statePath=function(n)return dir..'/state/'..n end}
local D=dofile(scripts..'/dashboard.lua')(M,{GetPlayerController=function()return pc end},valid)
D.input={pointer=function()end,attach=function()end,frame=function()end}
D.tick(1)
assert(D.analog and D.realistic and not D.title,'Default analog layout omits the vehicle title')
assert(not D.grip and D.engineState.text=='ENGINE OFF'and D.status.text=='')
assert(D.needles.fuelDial.target==.25 and not D.bars.fuel,'Fuel quantity drives the analog needle')
assert(not D.nitrousVisible and not D.bars.nitrous)
for _,o in ipairs(D.nitrousWidgets)do assert(o.visible==2)end
for _,t in ipairs(labels)do
 local p,s=t.slot.position,t.slot.size
 assert(p.X>=0 and p.X+s.X<=720 and p.Y+s.Y<=320,'Text exceeds the dashboard bounds')
 assert(t.clipping==1,'Text has an explicit clipping boundary')
end
data='99|0|10|2|0';D.tick(2)
assert(D.nitrousVisible and D.needles.nitrousDial.target==0,'An empty installed bottle still has a gauge')
for _,o in ipairs(D.nitrousWidgets)do assert(o.visible==3)end
data='99|7.5|10|2|1';D.tick(3);assert(D.needles.nitrousDial.target==.75)
data='100|7.5|10|2|1';D.tick(4);assert(not D.nitrousVisible,'Another vehicle cannot show a nitrous gauge here')
data='';D.tick(5);assert(not D.nitrousVisible,'Removing nitrous hides the entire pod')
assert(imports==6,'Shared dial artwork is imported once per texture')
D.input.pressed={name='Ignition'};D.frame(.1);assert(D.keyAngle>0,'Starting turns the front-facing key clockwise')
D.input.pressed=nil;D.keyRunning=true;D.frame(.1);assert(D.keyAngle>29 and D.keyAngle<35)
D.keyRunning=false;D.frame(.1);assert(D.keyAngle<2,'The key returns upright when switched off')
pc.Vehicle=nil;D.hide();D.startEdit(pc);D.tick(6)
assert(D.editing and D.preview and D.widget,'Placement works on foot and remains visible')
local oldX,oldY=D.x,D.y;D.press({X=oldX+10,Y=oldY+10});D.release({X=400,Y=300})
D.finishEdit(false);assert(not D.widget and not D.editing and not D.analogX,'Cancel discards preview position')
D.startEdit(pc);assert(D.x==oldX and D.y==oldY);D.press({X=D.x+10,Y=D.y+10});D.release({X=400,Y=300});D.finishEdit(true)
assert(D.analogX and not D.widget and not D.editing,'Confirm saves and dismisses on-foot preview')
D.startEdit(pc);assert(math.abs(D.x-390)<.001 and math.abs(D.y-290)<.001,'Confirmed position survives reopening')
return 'On-foot preview, Confirm/Cancel, fuel needle, empty/full/removed nitrous, vehicle ownership, clipped text and default layout'

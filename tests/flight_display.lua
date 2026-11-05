local root=assert(arg[1]);local made={}
local function widget(kind)
 local w={kind=kind,Font={}}
 function w:SetPosition(p)self.position=p end
 function w:SetText(t)self.text=t end
 function w:RemoveFromParent()self.removed=true end
 function w:AddChildToCanvas(child)local s=widget('slot');child.slot=s;return s end
 for _,name in ipairs({'SetAnchors','SetAlignment','SetSize','SetFont','SetColorAndOpacity','AddToViewport','SetVisibility'})do w[name]=function()end end
 made[#made+1]=w;return w
end
FText=function(s)return s end
StaticConstructObject=function(kind)return widget(kind)end
StaticFindObject=function(path)
 if path:find('Default__WidgetBlueprintLibrary',1,true)then return{Create=function()local w=widget('UserWidget');w.WidgetTree=widget('WidgetTree');return w end}end
 return path:match('%.([^%.]+)$')
end
local function valid(o)return type(o)=='table'and not o.removed end
local hud,frame=dofile(root..'/hud.lua')({GetPlayerController=function()return{}end},valid)
frame(.016,.5);assert(#made==0,'Idle HUD allocates widgets')
hud('Flight',0,.5,0)
local needle
for _,w in ipairs(made)do if w.kind=='slot'and w.position and w.position.X==13 then needle=w end end
assert(needle and needle.position.Y==142)
local n=#made
frame(1/60,.5);local y=needle.position.Y
assert(y<142 and y>90,'Needle must move between flight updates')
for _=1,20 do frame(1/60,.5)end
assert(math.abs(needle.position.Y-90)<.01,'Needle lags current flight output')
frame(.016,2);assert(needle.position.Y>=38,'Gauge exceeded its range')
assert(#made==n,'Frame update allocated widgets')
hud('Simple flight');local old=needle.position.Y;frame(.1,0);assert(needle.position.Y==old,'Simple flight retains manual gauge')
hud('Manual flight',.3,.5,0);hud(nil);n=#made;frame(.016,1);assert(#made==n,'Hidden HUD recreated itself')
local F=dofile(root..'/gyrocopter/flight.lua');local s=F.new()
for _=1,200 do F.step(s,{running=true,power=42000,mass=250,bladeMask=3,pitch=1,roll=-1,yaw=1,collectiveInput=1},.05)end
local x=F.step(s,{running=true,power=42000,mass=250,bladeMask=3,pitch=1,roll=-1,yaw=1},.05)
assert(x.authority>.99 and x.pitch>.79 and x.roll<-.89 and x.yaw>.59)
local held=x.collective;F.step(s,{running=true,power=42000,bladeMask=3},.05);assert(s.collective==held,'Manual collective did not hold')
local P=dofile(root..'/gyrocopter/inputs.lua')({},valid,function()end)
local actor={AutoDisableAirControlOnGround=true,EnableAirControl=false};P.configure(actor)
assert(actor.EnableAirControl and not actor.AutoDisableAirControlOnGround,'Ground gate can disable the Hornet')
P.apply({actor=actor,result=x});assert(actor.AirPitchInput<0 and actor.AirRollInput>0 and actor.AirYawInput>0)
local before=actor.AirPitchInput;P.apply({actor=actor,result={pitch=0},towed=true});assert(actor.AirPitchInput==before,'Docked aircraft received control writes')
local function identified(id)return {GetAddress=function()return id end}end
local plane,car=identified(1),identified(2)
local front,back=identified(3),identified(4)
plane.Vehicle_Hitch_Front=front;car.Vehicle_Hitch_Back=back
front.isHitched=true;back.isHitched=true;front.TowHitch=back
back.TowHitch=back;back.TrailerHitch=front;back.ParentVehicle=car
local tow=dofile(root..'/gyrocopter/native_tow.lua')({},valid)
assert(tow.active(plane)and not tow.active(car),'Follow the actual trailer from either native hitch record')
front.isHitched=false
assert(not tow.active(plane),'Manual release must restore flight')
print('PASS: idle/hidden/simple HUD lifetime, frame-smooth collective, manual collective hold, three axes, grounded air-control gate, tow guard')

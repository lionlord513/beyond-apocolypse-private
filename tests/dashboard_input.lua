local scripts=arg[1]
local function object(id)return {GetAddress=function()return id end}end
local function valid(o)return type(o)=='table'and o.invalid~=true end
local pc,p,car,other=object(1),object(2),object(3),object(4)
pc.PlayerControlled=p;pc.Vehicle=car;car.Driver=p
local keys,look,injections,paused={},0,0,false
pc.IsInputKeyDown=function(_,key)return keys[key.KeyName]end
pc.SetIgnoreLookInput=function(_,on)look=look+(on and 1 or -1)end
FName=function(n)return n end
local mouse={X=700,Y=400};local lib={GetMousePositionOnPlatform=function()return mouse end,AbsoluteToViewport=function(_,pc,p,pixel,q)q.X=p.X;q.Y=p.Y end,SetInputMode_GameOnly=function()end,SetInputMode_GameAndUIEx=function()end}
local action=object(6);action.GetFName=function()return {ToString=function()return 'Ignition'end}end
local ctx={Mappings={ForEach=function(_,fn)fn(nil,{get=function()return {Action=action}end})end}}
local sub={InjectInputVectorForAction=function(_,a,value)assert(a==action and value.X==1 and value.Y==0 and value.Z==0);injections=injections+1 end}
StaticFindObject=function(path)
 if path:find('IMC_Vehicule')then return ctx end
 if path:find('SubsystemBlueprintLibrary')then return {GetLocalPlayerSubSystemFromPlayerController=function()return sub end}end
 if path:find('EnhancedInputLibrary')then return {MakeInputActionValueOfType=function(v,x)return x end}end
 return lib
end
local M={utility={},backpack={ui={}}};local D={widget={},buttons={}}
local H={GetPlayerController=function()return pc end,IsPauseMenu=function()return paused end}
local I=dofile(scripts..'/dashboard_input.lua')(M,H,valid,D)
local binds={};Key={LEFT_MOUSE_BUTTON=1};ModifierKey={ALT=18}
RegisterKeyBind=function(key,mod,fn)binds[#binds+1]={mod=mod,fn=fn or mod}end
I.attach();I.attach();assert(#binds==2 and binds[2].mod[1]==18,'Bind both plain and Alt mouse clicks once')
keys.RightAlt=true;I.frame();assert(look==1 and pc.bShowMouseCursor)
keys.LeftMouseButton=true;I.press('Ignition');I.frame();I.frame();assert(injections==2)
car.Driver=other;I.frame();assert(not I.pressed and look==0 and not pc.bShowMouseCursor,'Passengers cannot drive through the dash')
car.Driver=p;paused=true;I.press('Ignition');assert(not I.pressed,'Pause blocks dashboard input')
paused=false;I.frame();I.press('Ignition');pc.Vehicle=other;I.frame();assert(not I.pressed and look==0,'Changing vehicles releases input')
pc.Vehicle=car;keys.RightAlt=false;I.frame();assert(look==0,'No unmatched look-input release')
keys.LeftAlt=true;I.frame();assert(look==1 and pc.bShowMouseCursor,'Either Alt key exposes the vehicle controls')
keys.LeftAlt=false;I.frame();assert(look==0 and not pc.bShowMouseCursor)
M.utility.opened=true;D.editing=true;D.drag={};local moved,released=0,0
D.move=function(q)assert(q.X==700 and q.Y==400);moved=moved+1 end
D.release=function(q)released=released+1;D.drag=nil end
keys.LeftMouseButton=true;I.frame();assert(moved==1 and released==0,'Utility editor permits dragging while gameplay is blocked')
keys.LeftMouseButton=false;I.frame();assert(moved==2 and released==1 and injections==2,'Releasing ends drag without vehicle input')
return 'Editor dragging, driver-only controls, held ignition, pause, vehicle changes and balanced pointer cleanup'

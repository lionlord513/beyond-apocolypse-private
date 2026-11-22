local scripts=arg[1]
local function object(id)return {GetAddress=function()return id end}end
local function valid(o)return type(o)=='table'and o.invalid~=true end
local pc,p,car,other=object(1),object(2),object(3),object(4)
pc.PlayerControlled=p;pc.Vehicle=car;car.Driver=p
local keys,look,injections,paused={},0,0,false
pc.IsInputKeyDown=function(_,key)return keys[key.KeyName]end
pc.SetIgnoreLookInput=function(_,on)look=look+(on and 1 or -1)end
FName=function(n)return n end
local lib={SetInputMode_GameOnly=function()end,SetInputMode_GameAndUIEx=function()end}
local action=object(6);action.GetFName=function()return {ToString=function()return 'Ignition'end}end
local ctx={Mappings={ForEach=function(_,fn)fn(nil,{get=function()return {Action=action}end})end}}
local sub={InjectInputForAction=function(_,a,value)assert(a==action and value==1);injections=injections+1 end}
StaticFindObject=function(path)
 if path:find('IMC_Vehicule')then return ctx end
 if path:find('SubsystemBlueprintLibrary')then return {GetLocalPlayerSubSystemFromPlayerController=function()return sub end}end
 if path:find('EnhancedInputLibrary')then return {MakeInputActionValueOfType=function(v,x)return x end}end
 return lib
end
local M={utility={},backpack={ui={}}};local D={widget={},buttons={}}
local H={GetPlayerController=function()return pc end,IsPauseMenu=function()return paused end}
local I=dofile(scripts..'/dashboard_input.lua')(M,H,valid,D)
keys.RightAlt=true;I.frame();assert(look==1 and pc.bShowMouseCursor)
keys.LeftMouseButton=true;I.press('Ignition');I.frame();I.frame();assert(injections==2)
car.Driver=other;I.frame();assert(not I.pressed and look==0 and not pc.bShowMouseCursor,'Passengers cannot drive through the dash')
car.Driver=p;paused=true;I.press('Ignition');assert(not I.pressed,'Pause blocks dashboard input')
paused=false;I.frame();I.press('Ignition');pc.Vehicle=other;I.frame();assert(not I.pressed and look==0,'Changing vehicles releases input')
pc.Vehicle=car;keys.RightAlt=false;I.frame();assert(look==0,'No unmatched look-input release')
return 'Driver-only controls, held ignition, pause, vehicle changes and balanced pointer cleanup'

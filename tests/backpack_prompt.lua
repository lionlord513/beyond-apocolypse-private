local root=assert(arg[1]);local source=assert(io.open(root..'/backpack/controller.lua')):read('*a')
local body=assert(source:match('( function B.pickupPrompt%(%).-)\n function B.tick'))
local now=0;os.clock=function()return now end
local B={ui={},ready=function()return true end};local heldRifle;local writable=true
local enumerations,rebuilds=0,0;local mapped=true;local contextID=1
local action={GetAddress=function()return 2 end}
local ctx={GetAddress=function()return contextID end}
local function key()return{ToString=function()return 'RightMouseButton'end}end
ctx.Mappings={ForEach=function(_,fn)
 enumerations=enumerations+1
 if mapped then fn(1,{get=function()return{Action=action,Key={KeyName=key()}}end})end
end}
function ctx:UnmapKey()mapped=false end;function ctx:MapKey()mapped=true end
local pc={};local H={GetPlayerController=function()return pc end}
local N={worn=function()end,tier=function()end}
local M={weaponHandling={equipped=function()return heldRifle end}}
local function valid(o)return type(o)=='table'end
StaticFindObject=function(path)
 if path:find('IMC_Player',1,true)then return ctx end
 if path:find('InteractSecondary',1,true)then return action end
 return{RequestRebuildControlMappingsUsingContext=function()rebuilds=rebuilds+1 end}
end
FName=function(s)return s end
assert(load('return function(B,M,N,H,valid,busy)\n'..body..'\nend'))()(B,M,N,H,valid,function()return false end)
for _=1,100 do now=now+.05;B.pickupPrompt()end
assert(enumerations==0 and mapped,'idle prompt touched native mappings')
heldRifle={};B.pickupPrompt();assert(not mapped and B.secondarySuppressed and rebuilds==1,'rifle did not acquire RMB immediately')
local before=enumerations
for _=1,10 do now=now+.05;B.pickupPrompt()end
assert(enumerations==before,'unchanged prompt rescanned mappings')
heldRifle=nil;B.pickupPrompt();assert(mapped and not B.secondarySuppressed and rebuilds==2,'native RMB was not restored immediately')
heldRifle={};B.pickupPrompt();mapped=true;now=now+1.1;B.pickupPrompt()
assert(not mapped,'native/external rebind was not reconciled')
contextID=3;mapped=true;B.pickupPrompt();assert(not mapped,'replacement input context was not handled immediately')
print('PASS: idle mapping work eliminated, immediate rifle acquire/release, external rebind and replacement context')

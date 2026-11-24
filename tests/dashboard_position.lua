local scripts,dir=arg[1],arg[2]
StaticFindObject=function()return {}end
local function build()
 local m={statePath=function(name)return dir..'/state/'..name end}
 local d=dofile(scripts..'/dashboard.lua')(m,{},function(o)return type(o)=='table'end)
 d.widget={};d.height=342;d.scale=1;d.slot={SetPosition=function()end};return d
end
local d=build();assert(d.realistic,'Realistic dashboard defaults on');d.place(1600,900,1);assert(d.x==1266 and d.y==297)
assert(not d.press({X=0,Y=0}));assert(d.press({X=d.x+20,Y=d.y+14}))
d.move({X=720,Y=410});assert(d.x==700 and d.y==396)
assert(d.release({X=-30,Y=9999})and d.x==0 and d.y==558)
local nextSession=build();nextSession.height=426;nextSession.scale=.5
nextSession.place(800,450,.5);assert(nextSession.x==0 and nextSession.y==237)
local analog=build();analog.analog=true;analog.widthBase=720;analog.height=260;analog.place(1600,900,1)
assert(analog.x==866 and analog.y==626,'Analog dash defaults to bottom right')
assert(not analog.press({X=analog.x+20,Y=analog.y+80}),'Only the header drags')
assert(analog.press({X=analog.x+30,Y=analog.y+12}));analog.release({X=900,Y=500})
local restored=build();restored.analog=true;restored.widthBase=720;restored.height=260;restored.place(1600,900,1)
assert(math.abs(restored.x-870)<.001 and math.abs(restored.y-488)<.001)
assert(restored.savedX==0 and restored.savedY==1,'Layouts keep independent positions')
assert(restored.press({X=restored.x+10,Y=restored.y+10}));restored.move({X=900,Y=-500});assert(restored.y==108,'Top-mounted gauge stays inside the viewport')
local f=assert(io.open(dir..'/state/dashboard-mode.txt','w'));f:write('compact\n');f:close();assert(not build().realistic,'An explicit compact preference is retained')
return 'Default-on analog layout, bottom-right placement, pod clearance, saved preferences, dragging, DPI and flight height'

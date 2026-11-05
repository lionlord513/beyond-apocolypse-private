local scripts,dir=arg[1],arg[2]
StaticFindObject=function()return {}end
local function build()
 local m={statePath=function(name)return dir..'/state/'..name end}
 local d=dofile(scripts..'/dashboard.lua')(m,{},function(o)return type(o)=='table'end)
 d.widget={};d.height=342;d.scale=1;d.slot={SetPosition=function()end};return d
end
local d=build();d.place(1600,900,1);assert(d.x==1266 and d.y==297)
assert(not d.press({X=0,Y=0}));assert(d.press({X=d.x+20,Y=d.y+14}))
d.move({X=720,Y=410});assert(d.x==700 and d.y==396)
assert(d.release({X=-30,Y=9999})and d.x==0 and d.y==558)
local nextSession=build();nextSession.height=426;nextSession.scale=.5
nextSession.place(800,450,.5);assert(nextSession.x==0 and nextSession.y==237)
return 'Drag grip, bounds, normalized persistence, DPI and flight-panel height'

local scripts=assert(arg[1])
local function valid(v)return type(v)=='table'and v.alive~=false end
local count,failed=0,false
local renderer={ImportFileAsTexture2D=function(_,a,path)
 assert(path:match('/gyrocopter/plastic%-dirt.png$'));count=count+1
 if failed then return {alive=false}end
 return {alive=true,serial=count}
end}
StaticFindObject=function(path)return path:find('KismetRenderingLibrary',1,true)and renderer or {}end
FName=function(name)return name end
local V=dofile(scripts..'/gyrocopter/visuals.lua')(scripts..'/..',valid)
local wear=1;local bound;local writes=0
local paint={SetScalarParameterValue=function()end,SetTextureParameterValue=function(_,key,texture)
 assert(key=='TextureColor'and valid(texture),'An expired texture reached the renderer')
 bound=texture;writes=writes+1
end}
local component={IsVisible=function()return true end}
local white={alive=true}
local visual={paint=paint,paintWhite=white}
for _,key in ipairs({'body','plastic','rotor','propeller','nose','left','right','tail','blade1','blade2','rotorSpin','propellerSpin'})do visual[key]=component end
local actor={VehicleMesh={GetMaterial=function()return {K2_GetScalarParameterValue=function()return wear end}end},
 K2_GetComponentsByClass=function()return {}end,CarEquipableComponents={ForEach=function()end}}
local record={actor=actor,visual=visual}
local now=0
local function tick()now=now+1;V.maintain(record,now,{})end
tick();assert(count==1 and bound~=white and visual.dirty)
local first=bound
for i=1,50 do tick()end
assert(count==1 and writes==1,'Idle Hornet imported or rebound a texture')
wear=0;tick();assert(bound==white and not visual.dirty)
first.alive=false -- Native GC releases the unused texture, despite Lua references.
wear=1;tick();assert(count==2 and bound~=first and valid(bound)and visual.dirty)
local second=bound
wear=0;tick();second.alive=false;wear=1;failed=true
assert(not pcall(tick),'Failed texture import should stop before a native material call')
assert(bound==white and not visual.dirty,'Failed import committed invalid presentation state')
failed=false;tick();assert(valid(bound)and visual.dirty)
return 'Native texture collection, clean/dirty transitions, import failure recovery and idle reuse'

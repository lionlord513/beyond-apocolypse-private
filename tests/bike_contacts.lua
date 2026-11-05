local scripts=assert(arg[1]);local mathlib={}
function mathlib:TransformLocation(f,p)local c,s=math.cos(f.angle),math.sin(f.angle);return {X=c*p.X-s*p.Z,Y=p.Y,Z=f.height+s*p.X+c*p.Z}end
function mathlib:InverseTransformLocation(f,p)local c,s=math.cos(f.angle),math.sin(f.angle);return {X=c*p.X+s*(p.Z-f.height),Y=p.Y,Z=-s*p.X+c*(p.Z-f.height)}end
function StaticFindObject(p)return p:find('MathLibrary',1,true)and mathlib or {}end
function FName(v)return v end
local function valid(v)return type(v)=='table'end
local V=dofile(scripts..'/motorcycle/visuals.lua')('',valid)
local center
for i=1,30 do local n,v=debug.getupvalue(V.tick,i);if n=='centerHeight'then center=v;break end end
assert(center)
local function wheel(x,z)
 return {WheelController={K2_GetComponentLocation=function()return {X=x,Y=0,Z=z}end},GetWheelRadius=function(_,out)out.BrakePressure=24 end}
end
for _,scale in ipairs({1,.52})do
 for _,pitch in ipairs({-12,-5,0,5,12})do
  for _,bump in ipairs({0,8,25})do
   local f={angle=math.rad(pitch),height=80};local r={neutralFrame=f,visual={config={tireRadius=32.22805*scale,pivots={front={X=83.82057*scale},rear={X=-72.104*scale}}}}}
   for _,part in ipairs({'front','rear'})do
    local w=wheel(part=='front'and 135 or -135,24+bump)
    local z=center(r,part,w,w,-1000,false,false)
    local world=mathlib:TransformLocation(f,{X=r.visual.config.pivots[part].X,Y=0,Z=z})
    assert(math.abs(world.Z-r.visual.config.tireRadius-bump)<1e-6,'Pitch lifted the visible tire off its contact height')
   end
  end
 end
end
function RegisterHook()return 1,2 end
local J=dofile(scripts..'/gyrocopter/journal.lua')(scripts..'/..',valid,function()end)
local a='00000001:00000002:00000003:00000004';local b='00000005:00000006:00000007:00000008'
local state=J.empty();state.lampClassic[a]=true;state.lampSuzuki[b]=true;state.blade[b]={a,2}
local restored=J.decode(J.encode(state));assert(restored.lampClassic[a]and restored.lampSuzuki[b]and restored.blade[b][2]==2)
local old=J.decode('BAT1\nblade '..b..' '..a..' 1\n');assert(old.blade[b][2]==1 and next(old.lampClassic)==nil)
print('PASS: both bike contact heights under pitch and bumps; headlamp identity round-trip and old-save compatibility')

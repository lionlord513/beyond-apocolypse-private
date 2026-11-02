-- SI units. Native AVS integrates body-axis forces and pilot torque.
-- Collective is retained. Upright hands-off leveling is deliberately gentle.
local F={}
function F.clamp(x,a,b)return math.max(a,math.min(b,x))end
local clamp=F.clamp
local function smooth(x,y,rate,dt)return x+(y-x)*(1-math.exp(-rate*dt))end
function F.new()return {rpm=0,collective=0,pitch=0,roll=0,yaw=0,lift=0,damage=0,propDamage=false}end
function F.step(s,x,dt)
 dt=clamp(dt,0,.1)
 local verticalInput=clamp(x.collectiveInput or 0,-1,1)
 s.collective=x.noPilot and 0 or clamp(s.collective+verticalInput*((s.hover and math.abs(s.collective-s.hover)<.06)and .16 or .40)*dt,0,1)
 local mass=math.max(x.mass or 250,1);local power=math.max(x.power or 42000,0)
 local blades=x.bladeMask==nil or x.bladeMask==3
 local running=x.running and power>0 and blades
 local forward=x.forward or 0;local vertical=x.vertical or 0
 local wind=math.sqrt(forward*forward+math.max(0,-vertical)^2*12)
 local targetRPM=running and 360 or clamp(wind/24*350,0,420)
 s.rpm=smooth(s.rpm,targetRPM,running and .85 or .16,dt)
 if not blades then s.rpm=0 end
 local efficiency=clamp((s.rpm-70)/290,0,1)^2
 local lift;local available=0
 if running then
  available=(power*.72*math.sqrt(2*1.225*34.4))^(2/3)*efficiency*.8
  -- More native engine/turbo power produces more thrust. Tilting spends
  -- vertical lift on acceleration; added mass must be carried by the pilot.
  -- Rotor climb resistance grows with upward speed. It does not brake a
  -- descent/dive or clamp forward velocity; stronger engines retain headroom.
  local climbDrag=.5*1.225*34.4*.6*math.max(0,vertical)^2*clamp(x.up or 1,0,1)
  -- Upright low-speed damping makes small collective changes settle gently.
  -- Fade it out while accelerating or banking; never arrest a dive/inverted trick.
  local assist=clamp(((x.up or 1)-.65)/.35,0,1)*clamp(1-math.abs(forward)/25,0,1)
  local damping=mass*1.1*vertical*assist*clamp(s.collective/.2,0,1)
  damping=clamp(damping,-mass*9.81*.25,mass*9.81*.4)
  lift=clamp(available*s.collective-climbDrag-damping,0,available)
 else
  -- Engine-out airflow retains autorotation, but cannot sustain a stationary hover.
  lift=clamp(3.8*(forward*forward+math.max(0,-vertical)^2*5)*efficiency,0,mass*9.81*1.15)
 end
 s.lift=blades and smooth(s.lift,lift,6,dt)or 0
 local pitch=clamp(x.pitch or 0,-1,1);local roll=clamp(x.roll or 0,-1,1)
 s.neutralTime=(pitch==0 and roll==0)and (s.neutralTime or 0)+dt or 0
 local pitchAssist,rollAssist=0,0
 -- No attitude feedback during maneuvers or through inverted Euler wrapping.
 -- Wait before gently returning an upright aircraft toward level.
 if s.neutralTime>.35 and (x.up or 1)>0 and not x.ground and not x.noPilot then
  pitchAssist=clamp(-(x.attitudePitch or 0)*.008,-.25,.25)
  rollAssist=clamp(-(x.attitudeRoll or 0)*.008,-.25,.25)
 end
 s.pitch=smooth(s.pitch,pitch*.8+pitchAssist,7,dt)
 s.roll=smooth(s.roll,roll*.9+rollAssist,7,dt)
 s.yaw=smooth(s.yaw,clamp(x.yaw or 0,-1,1)*.6,5,dt)
 local drag=.5*1.225*.7*math.abs(forward)*forward
 s.hover=available>0 and (x.up or 1)>.2 and mass*9.81/(available*(x.up or 1))or nil
 s.propRPM=running and (x.engineRPM or 0)*.32 or 0
 return {lift=s.lift,thrust=0,drag=drag,authority=efficiency,rpm=s.rpm,
  pitch=s.pitch,roll=s.roll,yaw=s.yaw,airspeed=math.abs(forward),lowRotor=s.rpm<300,
  collective=s.collective,hoverCollective=s.hover,
  governor=running and (.35+s.collective*.65)or 0}
end
return F

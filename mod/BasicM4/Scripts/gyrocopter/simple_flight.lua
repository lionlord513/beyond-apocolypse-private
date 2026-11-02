-- Assisted VTOL conversion requested for the Hornet. SI units; native AVS
-- integrates held forces. Collective controls climb/hover/descent, not airspeed.
local F={}
function F.clamp(x,a,b)return math.max(a,math.min(b,x))end
local clamp=F.clamp
local function smooth(x,y,rate,dt)return x+(y-x)*(1-math.exp(-rate*dt))end
local function delta(a,b)return (a-b+180)%360-180 end
function F.new()return {rpm=0,collective=0,pitch=0,roll=0,yaw=0,lift=0,damage=0,propDamage=false}end
function F.step(s,x,dt)
 dt=clamp(dt,0,.1)
 local verticalInput=clamp(x.collectiveInput or 0,-1,1)
 local targetCollective=verticalInput>0 and .8 or verticalInput<0 and (x.ground and 0 or .18) or (x.ground and 0 or .5)
 if x.noPilot then targetCollective=0 end
 s.collective=smooth(s.collective,targetCollective,5,dt)
 local mass=clamp(x.mass or 250,100,2000);local power=clamp(x.power or 42000,0,65000)
 local blades=x.bladeMask==nil or x.bladeMask==3
 local running=x.running and power>0 and blades
 local forward=x.forward or 0;local vertical=x.vertical or 0
 local wind=math.sqrt(forward*forward+math.max(0,-vertical)^2*12)
 local targetRPM=running and 360 or clamp(wind/24*350,0,420)
 s.rpm=smooth(s.rpm,targetRPM,running and .85 or .16,dt)
 if not blades then s.rpm=0 end
 local efficiency=clamp((s.rpm-70)/290,0,1)^2
 local desired=s.collective>=.5 and (s.collective-.5)*12 or (s.collective-.5)*6
 -- A small center detent makes neutral collective a repeatable hover setting.
 if math.abs(s.collective-.5)<.035 then desired=0 end
 local up=clamp(x.up or 1,.35,1);local lift
 if running then
  local available=(power*.72*math.sqrt(2*1.225*34.4))^(2/3)*efficiency
  lift=mass*(9.81+clamp((desired-vertical)*1.8,-7,7))/up
  lift=clamp(lift,0,math.min(available,mass*9.81*1.7))
  if x.ground and s.collective<.12 then lift=0 end
 else
  -- Engine-out airflow retains autorotation, but cannot sustain a stationary hover.
  lift=clamp(3.8*(forward*forward+math.max(0,-vertical)^2*5)*efficiency,0,mass*9.81*1.15)
 end
 s.lift=blades and smooth(s.lift,lift,6,dt)or 0
 local pitch=clamp(x.pitch or 0,-1,1);local roll=clamp(x.roll or 0,-1,1)
 local attitudePitch=x.attitudePitch or 0;local attitudeRoll=x.attitudeRoll or 0
 local pitchRate=dt>0 and s.lastPitch and delta(attitudePitch,s.lastPitch)/dt or 0
 local rollRate=dt>0 and s.lastRoll and delta(attitudeRoll,s.lastRoll)/dt or 0
 s.lastPitch=attitudePitch;s.lastRoll=attitudeRoll
 s.pitch=smooth(s.pitch,clamp((pitch*15-attitudePitch)*.045-pitchRate*.025,-.7,.7),7,dt)
 s.roll=smooth(s.roll,clamp((roll*18-attitudeRoll)*.045-rollRate*.025,-.7,.7),7,dt)
 s.yaw=smooth(s.yaw,clamp(x.yaw or 0,-1,1)*.6,5,dt)
 local thrust=running and math.max(0,-pitch)*math.min(260,power*.006)*efficiency or 0
 local drag=mass*.22*forward+.5*1.225*.8*math.abs(forward)*forward
 s.propRPM=running and (x.engineRPM or 0)*.32 or 0
 return {lift=s.lift,thrust=thrust,drag=drag,authority=efficiency,rpm=s.rpm,
  pitch=s.pitch,roll=s.roll,yaw=s.yaw,airspeed=math.abs(forward),lowRotor=s.rpm<300,
  collective=s.collective,verticalTarget=desired,governor=running and (.42+s.collective*.22)or 0}
end
return F
